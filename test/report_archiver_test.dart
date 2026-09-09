import 'dart:io';

import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/base/qa/report_archive_store.dart';
import 'package:flutter_boilerplate/src/base/qa/report_archiver.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart' as prefs;
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `ReportArchiver` reads the real app-support directory via path_provider —
/// this fake redirects it to a real temp folder for the test, rather than
/// mocking the filesystem operations under test.
class _FakePathProvider extends PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    prefs.dispose();
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    root = Directory.systemTemp.createTempSync('report_archiver_test_');
    PathProviderPlatform.instance =
        _FakePathProvider('${root.path}/app-support');
  });

  tearDown(() => root.deleteSync(recursive: true));

  // The report command's own `category: 'report'` tag is what makes it
  // resolvable now (see [ProjectConfig.reportCommandFor]) — no more explicit
  // reportCommandId slot on the surface.
  SurfaceConfig surfaceWith({required String reportCommandId, String? relPath}) =>
      SurfaceConfig.autoWeb().copyWith(
        commandIds: [reportCommandId],
        reportOutputRelPath: relPath ?? 'allure-report',
      );

  ProjectConfig projectWith(SurfaceConfig surface, CommandConfig reportCmd,
          {required String repoAbsPath}) =>
      ProjectConfig(
        id: 'proj-1',
        name: 'Test',
        projectsRoot: root.path,
        repos: {'web': RepoEntry(role: 'web', label: 'web', relPath: 'web')},
        commands: [reportCmd],
        surfaces: [surface],
      );

  ScriptEntry script() =>
      ScriptEntry(id: 's1', path: 'test.spec.ts', addedAt: DateTime.now());

  test('archiveAfterRun copies the report folder into app-managed storage '
      'and records a ReportArchive entry', () async {
    final webRepo = Directory('${root.path}/web')..createSync();
    final reportDir = Directory('${webRepo.path}/allure-report')..createSync();
    File('${reportDir.path}/index.html').writeAsStringSync('<html></html>');

    final reportCmd = CommandConfig(
      id: 'allure_open_web',
      name: 'Open Allure report',
      command: 'yarn allure:open',
      repoRole: 'web',
      tags: const ['report'],
      order: 0,
    );
    final surface = surfaceWith(reportCommandId: reportCmd.id);
    final project = projectWith(surface, reportCmd, repoAbsPath: webRepo.path);

    final entry = await ReportArchiver().archiveAfterRun(
      project: project,
      surface: surface,
      script: script(),
      environmentId: 'dev',
      runId: 'run-1',
      commandUsed: 'yarn allure:open',
    );

    expect(entry, isNotNull);
    expect(entry!.sourcePath, reportDir.path);
    expect(File('${entry.archivePath}/index.html').existsSync(), isTrue);
    expect(File('${entry.archivePath}/index.html').readAsStringSync(),
        '<html></html>');
    // The source is left alone — this is a copy, not a move.
    expect(reportDir.existsSync(), isTrue);

    final stored = ReportArchiveStore.forSurface('proj-1', surface.id);
    expect(stored, hasLength(1));
    expect(stored.first.runId, 'run-1');
  });

  test('archiveAfterRun returns null (and archives nothing) when the report '
      'output folder never got written', () async {
    final webRepo = Directory('${root.path}/web')..createSync();
    // Deliberately no allure-report/ folder created underneath.

    final reportCmd = CommandConfig(
      id: 'allure_open_web',
      name: 'Open Allure report',
      command: 'yarn allure:open',
      repoRole: 'web',
      tags: const ['report'],
      order: 0,
    );
    final surface = surfaceWith(reportCommandId: reportCmd.id);
    final project = projectWith(surface, reportCmd, repoAbsPath: webRepo.path);

    final entry = await ReportArchiver().archiveAfterRun(
      project: project,
      surface: surface,
      script: script(),
      environmentId: 'dev',
      runId: 'run-1',
      commandUsed: 'yarn allure:open',
    );

    expect(entry, isNull);
    expect(ReportArchiveStore.forSurface('proj-1', surface.id), isEmpty);
  });

  test('regenerate re-runs the original command and re-copies over the same '
      'archived folder', () async {
    final webRepo = Directory('${root.path}/web')..createSync();
    final reportDir = Directory('${webRepo.path}/allure-report')..createSync();
    File('${reportDir.path}/index.html').writeAsStringSync('v1');

    final reportCmd = CommandConfig(
      id: 'allure_open_web',
      name: 'Open Allure report',
      command: 'yarn allure:open',
      repoRole: 'web',
      tags: const ['report'],
      order: 0,
    );
    final surface = surfaceWith(reportCommandId: reportCmd.id);
    final project = projectWith(surface, reportCmd, repoAbsPath: webRepo.path);
    final archiver = ReportArchiver(gateway: ProcessGateway());

    final entry = await archiver.archiveAfterRun(
      project: project,
      surface: surface,
      script: script(),
      environmentId: 'dev',
      runId: 'run-1',
      // A real, harmless shell command standing in for the actual report
      // tool (mocking the process itself is fine — the filesystem
      // operations under test are real).
      commandUsed: 'true',
    );
    expect(entry, isNotNull);

    // Raw results changed on disk since the run (as if a fresh report was
    // regenerated by the command).
    File('${reportDir.path}/index.html').writeAsStringSync('v2');

    final ok = await archiver.regenerate(entry!, project);

    expect(ok, isTrue);
    expect(File('${entry.archivePath}/index.html').readAsStringSync(), 'v2');
  });

  test('regenerate returns false when the raw results are gone from disk',
      () async {
    final webRepo = Directory('${root.path}/web')..createSync();
    final reportDir = Directory('${webRepo.path}/allure-report')..createSync();
    File('${reportDir.path}/index.html').writeAsStringSync('v1');

    final reportCmd = CommandConfig(
      id: 'allure_open_web',
      name: 'Open Allure report',
      command: 'yarn allure:open',
      repoRole: 'web',
      tags: const ['report'],
      order: 0,
    );
    final surface = surfaceWith(reportCommandId: reportCmd.id);
    final project = projectWith(surface, reportCmd, repoAbsPath: webRepo.path);
    final archiver = ReportArchiver();

    final entry = await archiver.archiveAfterRun(
      project: project,
      surface: surface,
      script: script(),
      environmentId: 'dev',
      runId: 'run-1',
      commandUsed: 'true',
    );
    expect(entry, isNotNull);

    reportDir.deleteSync(recursive: true); // repo cleaned since the run

    final ok = await archiver.regenerate(entry!, project);
    expect(ok, isFalse);
  });
}
