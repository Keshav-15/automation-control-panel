import 'dart:io';

import 'package:flutter_boilerplate/src/base/qa/report_archive_store.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart' as prefs;
import 'package:flutter_boilerplate/src/models/qa/report_archive_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    prefs.dispose();
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    tempRoot = Directory.systemTemp.createTempSync('report_archive_store_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  /// Creates a real folder with [bytes] worth of file content, for the
  /// retention tests — [ReportArchiveStore.pruneFor] measures actual
  /// on-disk size, not a fake number.
  ReportArchive makeArchive(
    String runId, {
    String projectId = 'proj-1',
    String surfaceId = 'mobile',
    required DateTime generatedAt,
    int bytes = 10,
  }) {
    final dir = Directory('${tempRoot.path}/$projectId/$surfaceId/$runId')
      ..createSync(recursive: true);
    File('${dir.path}/report.html').writeAsStringSync('x' * bytes);
    return ReportArchive(
      runId: runId,
      projectId: projectId,
      surfaceId: surfaceId,
      script: 'script.ts',
      environment: 'dev',
      commandUsed: 'allure open',
      generatedAt: generatedAt,
      sourcePath: '/repo/allure-report',
      archivePath: dir.path,
    );
  }

  test('load() returns empty when nothing has been saved', () {
    expect(ReportArchiveStore.load(), isEmpty);
  });

  test('append() persists an entry that load() reads back byte-for-byte',
      () async {
    final entry = makeArchive('run-1', generatedAt: DateTime(2026, 1, 1));
    await ReportArchiveStore.append(entry);

    final loaded = ReportArchiveStore.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.runId, 'run-1');
    expect(loaded.first.projectId, 'proj-1');
    expect(loaded.first.generatedAt, DateTime(2026, 1, 1));
  });

  test('forSurface() filters by project+surface and sorts newest first',
      () async {
    await ReportArchiveStore.append(
        makeArchive('a', surfaceId: 'web', generatedAt: DateTime(2026, 1, 1)));
    await ReportArchiveStore.append(makeArchive('b',
        surfaceId: 'mobile', generatedAt: DateTime(2026, 1, 3)));
    await ReportArchiveStore.append(makeArchive('c',
        surfaceId: 'mobile', generatedAt: DateTime(2026, 1, 2)));

    final mobile = ReportArchiveStore.forSurface('proj-1', 'mobile');
    expect(mobile.map((r) => r.runId), ['b', 'c']);
  });

  test('update() replaces the stored entry with the same runId', () async {
    final entry = makeArchive('run-1', generatedAt: DateTime(2026, 1, 1));
    await ReportArchiveStore.append(entry);

    await ReportArchiveStore.update(entry.copyWith(generatedAt: DateTime(2026, 6, 1)));

    final loaded = ReportArchiveStore.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.generatedAt, DateTime(2026, 6, 1));
  });

  test('remove() deletes both the store entry and the archived folder',
      () async {
    final entry = makeArchive('run-1', generatedAt: DateTime(2026, 1, 1));
    await ReportArchiveStore.append(entry);

    await ReportArchiveStore.remove('run-1');

    expect(ReportArchiveStore.load(), isEmpty);
    expect(Directory(entry.archivePath).existsSync(), isFalse);
  });

  test('a corrupted stored value is dropped instead of throwing', () async {
    await prefs.setString('prefkeyQAReportArchive', 'not valid json{{{');
    expect(ReportArchiveStore.load(), isEmpty);
  });

  group('pruneFor', () {
    test('keeps only the newest maxCount, deleting older folders too',
        () async {
      for (var i = 0; i < 5; i++) {
        await ReportArchiveStore.append(
            makeArchive('run-$i', generatedAt: DateTime(2026, 1, i + 1)));
      }

      await ReportArchiveStore.pruneFor('proj-1', 'mobile', maxCount: 2);

      final remaining = ReportArchiveStore.forSurface('proj-1', 'mobile');
      expect(remaining.map((r) => r.runId), ['run-4', 'run-3']);
      // Pruned folders are actually gone from disk, not just untracked.
      expect(Directory('${tempRoot.path}/proj-1/mobile/run-0').existsSync(),
          isFalse);
      expect(Directory('${tempRoot.path}/proj-1/mobile/run-2').existsSync(),
          isFalse);
      expect(Directory('${tempRoot.path}/proj-1/mobile/run-4').existsSync(),
          isTrue);
    });

    test('prunes oldest-first once total size exceeds maxBytes', () async {
      await ReportArchiveStore.append(makeArchive('run-0',
          generatedAt: DateTime(2026, 1, 1), bytes: 100));
      await ReportArchiveStore.append(makeArchive('run-1',
          generatedAt: DateTime(2026, 1, 2), bytes: 100));
      await ReportArchiveStore.append(makeArchive('run-2',
          generatedAt: DateTime(2026, 1, 3), bytes: 100));

      // Budget only fits the newest ~2 entries (100 bytes each).
      await ReportArchiveStore.pruneFor('proj-1', 'mobile',
          maxCount: 100, maxBytes: 250);

      final remaining = ReportArchiveStore.forSurface('proj-1', 'mobile');
      expect(remaining.map((r) => r.runId), ['run-2', 'run-1']);
    });

    test('always keeps the newest report even if it alone exceeds maxBytes',
        () async {
      await ReportArchiveStore.append(
          makeArchive('run-0', generatedAt: DateTime(2026, 1, 1), bytes: 1000));

      await ReportArchiveStore.pruneFor('proj-1', 'mobile', maxBytes: 10);

      final remaining = ReportArchiveStore.forSurface('proj-1', 'mobile');
      expect(remaining.map((r) => r.runId), ['run-0']);
    });

    test('does not touch other surfaces/projects', () async {
      await ReportArchiveStore.append(makeArchive('mobile-1',
          surfaceId: 'mobile', generatedAt: DateTime(2026, 1, 1)));
      await ReportArchiveStore.append(makeArchive('web-1',
          surfaceId: 'web', generatedAt: DateTime(2026, 1, 1)));
      await ReportArchiveStore.append(makeArchive('other-proj-1',
          projectId: 'proj-2', generatedAt: DateTime(2026, 1, 1)));

      await ReportArchiveStore.pruneFor('proj-1', 'mobile', maxCount: 0);

      expect(ReportArchiveStore.forSurface('proj-1', 'mobile'), isEmpty);
      expect(ReportArchiveStore.forSurface('proj-1', 'web'), hasLength(1));
      expect(ReportArchiveStore.forSurface('proj-2', 'mobile'), hasLength(1));
    });
  });

  group('clearFor', () {
    test('deletes every entry and folder for that project+surface only',
        () async {
      final entry0 = makeArchive('run-0',
          surfaceId: 'mobile', generatedAt: DateTime(2026, 1, 1));
      final entry1 = makeArchive('run-1',
          surfaceId: 'mobile', generatedAt: DateTime(2026, 1, 2));
      final webEntry = makeArchive('web-run',
          surfaceId: 'web', generatedAt: DateTime(2026, 1, 1));
      await ReportArchiveStore.append(entry0);
      await ReportArchiveStore.append(entry1);
      await ReportArchiveStore.append(webEntry);

      await ReportArchiveStore.clearFor('proj-1', 'mobile');

      expect(ReportArchiveStore.forSurface('proj-1', 'mobile'), isEmpty);
      expect(Directory(entry0.archivePath).existsSync(), isFalse);
      expect(Directory(entry1.archivePath).existsSync(), isFalse);
      // Web surface untouched.
      expect(ReportArchiveStore.forSurface('proj-1', 'web'), hasLength(1));
      expect(Directory(webEntry.archivePath).existsSync(), isTrue);
    });
  });
}
