import 'package:flutter_boilerplate/src/models/qa/run_record_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RunRecord re-run metadata', () {
    test('JSON round-trip preserves projectId, runId, and every re-run field',
        () {
      final record = RunRecord(
        recipeId: 'mobile',
        recipeName: 'Mobile — Login test',
        startedAt: DateTime.utc(2026, 1, 1),
        durationMs: 5000,
        status: 'done',
        hasReport: true,
        projectId: 'proj-1',
        runId: 'run-1',
        scriptDisplayName: 'Login test',
        environmentId: 'staging',
        platform: 'android',
        deviceKind: 'simulator',
        deviceUdid: 'emulator-5554',
        mode: 'pullAndRun',
      );
      final back = RunRecord.fromJson(record.toJson());

      expect(back.projectId, 'proj-1');
      expect(back.runId, 'run-1');
      expect(back.scriptDisplayName, 'Login test');
      expect(back.environmentId, 'staging');
      expect(back.platform, 'android');
      expect(back.deviceKind, 'simulator');
      expect(back.deviceUdid, 'emulator-5554');
      expect(back.mode, 'pullAndRun');
    });

    test('a record with none of the new fields (pre-existing history) parses '
        'with them all null, not a crash', () {
      final legacy = {
        'recipeId': 'web',
        'recipeName': 'Web Tests',
        'startedAt': DateTime.utc(2025, 1, 1).toIso8601String(),
        'durationMs': 1000,
        'status': 'done',
        'hasReport': false,
      };
      final record = RunRecord.fromJson(legacy);

      expect(record.projectId, isNull);
      expect(record.runId, isNull);
      expect(record.environmentId, isNull);
      expect(record.hasRerunInfo, isFalse);
    });

    test('hasRerunInfo is true once environmentId is on file', () {
      final record = RunRecord(
        recipeId: 'web',
        recipeName: 'Web',
        startedAt: DateTime.now(),
        durationMs: 0,
        status: 'done',
        hasReport: false,
        environmentId: 'dev',
      );
      expect(record.hasRerunInfo, isTrue);
    });
  });
}
