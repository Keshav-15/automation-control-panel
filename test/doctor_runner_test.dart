import 'dart:io';

import 'package:flutter_boilerplate/src/base/qa/doctor_runner.dart';
import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/models/qa/doctor_model.dart';
import 'package:flutter_boilerplate/src/models/qa/machine_profile_model.dart';
import 'package:flutter_boilerplate/src/models/qa/manifest_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Real git repo, real `git` subprocess — the point is to prove the actual
/// fixCommand a user would click "Fix" on genuinely resolves the check,
/// not just that the right string got threaded through.
const _yaml = '''
product: test
environment: dev
repos:
  web:
    rel_path: web_repo
    branch: develop
recipes:
  web:
    name: Web Tests
    surface: web
    steps: []
''';

Future<void> _git(String cwd, String args) async {
  final r = await Process.run('/bin/zsh', ['-l', '-c', 'git $args'],
      workingDirectory: cwd);
  if (r.exitCode != 0) {
    throw Exception('git $args failed: ${r.stderr}');
  }
}

void main() {
  late Directory root;
  late MachineProfile profile;
  late ManifestModel manifest;
  final gateway = ProcessGateway();

  setUp(() async {
    root = Directory.systemTemp.createTempSync('qa_doctor_runner');
    final repo = Directory('${root.path}/web_repo')..createSync();
    await _git(repo.path, 'init -q -b develop');
    await _git(repo.path, 'config user.email test@example.com');
    await _git(repo.path, 'config user.name Test');
    File('${repo.path}/f.txt').writeAsStringSync('hello');
    await _git(repo.path, 'add f.txt');
    await _git(repo.path, 'commit -q -m init');

    profile = MachineProfile(projectsRoot: root.path);
    manifest = ManifestModel.fromYaml(loadYaml(_yaml) as Map);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<DoctorCheck> checkNamed(String idPrefix) async {
    final result = await DoctorRunner.run(
      recipe: manifest.recipes['web']!,
      profile: profile,
      manifest: manifest,
      gateway: gateway,
    );
    return result.checks.firstWhere((c) => c.id.startsWith(idPrefix));
  }

  test('branch mismatch: fixCommand is the real git checkout, and running it fixes the check',
      () async {
    final repoPath = '${root.path}/web_repo';
    await _git(repoPath, 'checkout -q -b feature/other');

    final before = await checkNamed('repo_branch_');
    expect(before.status, DoctorStatus.warn);
    expect(before.fixCommand, 'git checkout develop');
    expect(before.fixCwd, repoPath);

    // Run the exact fixCommand a "Fix" button click would run.
    await gateway.exec(before.fixCommand!, workingDirectory: before.fixCwd);

    final after = await checkNamed('repo_branch_');
    expect(after.status, DoctorStatus.pass,
        reason: 'the real fixCommand should have actually fixed it');
  });

  test('dirty tree: fixCommand is git stash, and running it fixes the check',
      () async {
    final repoPath = '${root.path}/web_repo';
    File('$repoPath/f.txt').writeAsStringSync('changed');

    final before = await checkNamed('repo_clean_');
    // Dirty is a heads-up, not a blocker — Doctor still passes overall.
    expect(before.status, DoctorStatus.warn);
    expect(before.fixCommand, 'git stash');
    expect(before.fixCwd, repoPath);

    await gateway.exec(before.fixCommand!, workingDirectory: before.fixCwd);

    final after = await checkNamed('repo_clean_');
    expect(after.status, DoctorStatus.pass);
  });

  test('clean repo on the right branch: no fixCommand offered', () async {
    final check = await checkNamed('repo_branch_');
    expect(check.status, DoctorStatus.pass);
    expect(check.fixCommand, isNull);
    expect(check.fixCwd, isNull);
  });

  test(
      "node fixCommand gives a clear error when nvm genuinely isn't there — "
      'run against a stripped PATH/HOME so this never touches the real '
      'machine\'s actual nvm state', () async {
    final check = await checkNamed('node_version');
    if (check.fixCommand == null) {
      // This machine's currently-active Node already satisfies minMajor —
      // nothing to test (the check passed, so no fixCommand was offered).
      return;
    }

    final fakeHome = Directory.systemTemp.createTempSync('qa_fake_home');
    addTearDown(() => fakeHome.deleteSync(recursive: true));

    await expectLater(
      gateway.exec(
        check.fixCommand!,
        extraEnv: {'PATH': '/usr/bin:/bin', 'HOME': fakeHome.path},
      ),
      throwsA(isA<ProcessException>().having(
          (e) => e.message, 'message', contains('nvm not found'))),
    );
  });

  group('mobile repo-role fallback (new mobile_ui/mobile_test vs. legacy '
      'app/mobile_tests)', () {
    // A real regression risk from renaming ProjectTemplate.centurion()'s
    // roles: DoctorRunner's ios/android checks used to hardcode the legacy
    // names directly, which would silently skip the repo-branch/clean
    // checks entirely (not crash) for a project using the new names.
    Future<ManifestModel> manifestWith(String mobileUiRole, String mobileTestRole) async {
      final uiRepo = Directory('${root.path}/$mobileUiRole')..createSync();
      await _git(uiRepo.path, 'init -q -b develop');
      await _git(uiRepo.path, 'config user.email test@example.com');
      await _git(uiRepo.path, 'config user.name Test');
      File('${uiRepo.path}/f.txt').writeAsStringSync('hello');
      await _git(uiRepo.path, 'add f.txt');
      await _git(uiRepo.path, 'commit -q -m init');

      return ManifestModel(
        product: 'test',
        environment: 'dev',
        repos: {
          // Both roles point at the same real repo — only the role *name*
          // matters for what this test is checking.
          mobileUiRole: RepoConfig(relPath: mobileUiRole, branch: 'develop'),
          mobileTestRole: RepoConfig(relPath: mobileUiRole, branch: 'develop'),
        },
        recipes: {
          'ios': const RecipeConfig(
              id: 'ios', name: 'iOS', surface: 'ios', platformType: 'ios', steps: []),
        },
      );
    }

    test('new convention (mobile_ui/mobile_test) is actually checked, not silently skipped',
        () async {
      final manifest = await manifestWith('mobile_ui', 'mobile_test');
      final result = await DoctorRunner.run(
        recipe: manifest.recipes['ios']!,
        profile: profile,
        manifest: manifest,
        gateway: gateway,
      );
      expect(result.checks.map((c) => c.id), contains('repo_branch_mobile_ui'));
      expect(
          result.checks.firstWhere((c) => c.id == 'repo_branch_mobile_ui').status,
          DoctorStatus.pass);
    });

    test('legacy convention (app/mobile_tests) still works — backward compat',
        () async {
      final manifest = await manifestWith('app', 'mobile_tests');
      final result = await DoctorRunner.run(
        recipe: manifest.recipes['ios']!,
        profile: profile,
        manifest: manifest,
        gateway: gateway,
      );
      expect(result.checks.map((c) => c.id), contains('repo_branch_app'));
      expect(result.checks.firstWhere((c) => c.id == 'repo_branch_app').status,
          DoctorStatus.pass);
    });
  });
}
