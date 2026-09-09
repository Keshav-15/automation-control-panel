import 'package:flutter_boilerplate/src/base/qa/run_history_store.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart' as prefs;
import 'package:flutter_boilerplate/src/models/qa/run_record_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

RunRecord _record(String recipeId, {DateTime? startedAt, bool hasReport = true}) {
  return RunRecord(
    recipeId: recipeId,
    recipeName: '$recipeId Tests',
    startedAt: startedAt ?? DateTime(2026, 1, 1),
    durationMs: 12345,
    status: 'done',
    hasReport: hasReport,
    logPath: '/tmp/$recipeId.log',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // preference_utils caches the SharedPreferences instance in a static —
    // dispose() drops that cache so each test actually gets the freshly
    // mocked (empty) backing store instead of the previous test's data.
    prefs.dispose();
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
  });

  test('load() returns empty when nothing has been saved', () {
    expect(RunHistoryStore.load(), isEmpty);
  });

  test('append() persists a record that load() reads back byte-for-byte',
      () async {
    final record = _record('web');
    await RunHistoryStore.append(record);

    final loaded = RunHistoryStore.load();
    expect(loaded, hasLength(1));
    expect(loaded.first.recipeId, 'web');
    expect(loaded.first.recipeName, 'web Tests');
    expect(loaded.first.durationMs, 12345);
    expect(loaded.first.status, 'done');
    expect(loaded.first.hasReport, isTrue);
    expect(loaded.first.logPath, '/tmp/web.log');
    expect(loaded.first.startedAt, DateTime(2026, 1, 1));
  });

  test('append() prepends — newest first', () async {
    await RunHistoryStore.append(_record('web'));
    await RunHistoryStore.append(_record('ios'));

    final loaded = RunHistoryStore.load();
    expect(loaded.map((r) => r.recipeId), ['ios', 'web']);
  });

  test('append() caps at maxRecords, dropping the oldest', () async {
    for (var i = 0; i < RunHistoryStore.maxRecords + 5; i++) {
      await RunHistoryStore.append(_record('recipe$i'));
    }

    final loaded = RunHistoryStore.load();
    expect(loaded, hasLength(RunHistoryStore.maxRecords));
    // Most recent (highest i) survives; earliest ones are trimmed off the end.
    expect(loaded.first.recipeId, 'recipe${RunHistoryStore.maxRecords + 4}');
  });

  test('a corrupted stored value is dropped instead of throwing', () async {
    await prefs.setString('prefkeyQARunHistory', 'not valid json{{{');
    expect(RunHistoryStore.load(), isEmpty);
  });
}
