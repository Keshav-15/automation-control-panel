import 'dart:convert';

import 'package:flutter_boilerplate/src/base/utils/common_methods.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/preference_key_constant.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart';
import 'package:flutter_boilerplate/src/models/qa/run_record_model.dart';

/// Persists the run history list (newest first, capped) to SharedPreferences
/// as one JSON-encoded string — there's no need for SQLite over ~50 small rows.
class RunHistoryStore {
  static const int maxRecords = 50;

  /// Read every stored record, newest first. Never throws — a corrupted
  /// entry (or the whole key) is dropped rather than crashing the app.
  static List<RunRecord> load() {
    final raw = getString(prefkeyQARunHistory);
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) {
            try {
              return RunRecord.fromJson(e as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<RunRecord>()
          .toList();
    } catch (e) {
      logger('RunHistoryStore.load: corrupted history, ignoring: $e');
      return [];
    }
  }

  /// Prepend [record] and persist, trimming to [maxRecords].
  static Future<void> append(RunRecord record) async {
    final current = load();
    final updated = [record, ...current].take(maxRecords).toList();
    await setString(
      prefkeyQARunHistory,
      jsonEncode(updated.map((r) => r.toJson()).toList()),
    );
  }
}
