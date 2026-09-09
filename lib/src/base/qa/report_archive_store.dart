import 'dart:convert';
import 'dart:io';

import 'package:flutter_boilerplate/src/base/utils/common_methods.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/preference_key_constant.dart';
import 'package:flutter_boilerplate/src/base/utils/dir_copy_utils.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart';
import 'package:flutter_boilerplate/src/models/qa/report_archive_model.dart';

/// Persists the report-archive list to SharedPreferences as one
/// JSON-encoded string — same shape of solution as [RunHistoryStore], just
/// keyed by project+surface too since reports (unlike run history so far)
/// need to be queried per-surface for the Reports screen and per-surface
/// retention (see docs/RUN_EXPERIENCE_REDESIGN.md §8/§9).
class ReportArchiveStore {
  /// Global safety cap across every project/surface — the real limit a user
  /// sees is [pruneFor]'s per-surface `maxCount`/`maxBytes`, run right after
  /// every archive; this just bounds the SharedPreferences blob itself.
  static const int maxRecords = 1000;

  static const int defaultMaxCount = 20;
  static const int defaultMaxBytes = 2 * 1024 * 1024 * 1024; // 2GB

  /// Read every stored entry. Never throws — a corrupted entry (or the whole
  /// key) is dropped rather than crashing the app.
  static List<ReportArchive> load() {
    final raw = getString(prefkeyQAReportArchive);
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) {
            try {
              return ReportArchive.fromJson(e as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<ReportArchive>()
          .toList();
    } catch (e) {
      logger('ReportArchiveStore.load: corrupted archive list, ignoring: $e');
      return [];
    }
  }

  static Future<void> _saveAll(List<ReportArchive> entries) => setString(
        prefkeyQAReportArchive,
        jsonEncode(entries.map((e) => e.toJson()).toList()),
      );

  /// Prepend [entry] and persist, trimming to [maxRecords].
  static Future<void> append(ReportArchive entry) async {
    final updated = [entry, ...load()].take(maxRecords).toList();
    await _saveAll(updated);
  }

  /// The archived report for [runId], or null if none exists (report step
  /// didn't run, failed, or nothing was ever archived for it). [runId] is
  /// globally unique (see `RunProvider._newRunId`), so no project/surface
  /// scoping is needed to look it up — used by the live-runs screen (see
  /// docs/RUN_EXPERIENCE_REDESIGN.md §9), which only has a run id to go on.
  static ReportArchive? findByRunId(String runId) =>
      load().where((r) => r.runId == runId).firstOrNull;

  /// Every archived report for [projectId]/[surfaceId], newest first.
  static List<ReportArchive> forSurface(String projectId, String surfaceId) {
    final entries = load()
        .where((r) => r.projectId == projectId && r.surfaceId == surfaceId)
        .toList();
    entries.sort((a, b) => b.generatedAt.compareTo(a.generatedAt));
    return entries;
  }

  /// Replace the stored entry for [entry.runId] (e.g. after Regenerate
  /// updates [ReportArchive.generatedAt]).
  static Future<void> update(ReportArchive entry) async {
    final updated =
        load().map((r) => r.runId == entry.runId ? entry : r).toList();
    await _saveAll(updated);
  }

  /// Deletes [runId]'s archived folder on disk and removes it from the
  /// store.
  static Future<void> remove(String runId) async {
    final entries = load();
    final target = entries.where((r) => r.runId == runId).firstOrNull;
    if (target != null) deleteDirectoryQuietly(target.archivePath);
    await _saveAll(entries.where((r) => r.runId != runId).toList());
  }

  /// Keeps the newest [maxCount] reports for [projectId]/[surfaceId] and/or
  /// stops once their total on-disk size would exceed [maxBytes] —
  /// whichever limit is hit first prunes the rest, oldest first. Deletes
  /// both the archived folder and the store entry for anything pruned. Run
  /// opportunistically right after each new report is archived — no
  /// background timer (see docs/RUN_EXPERIENCE_REDESIGN.md §9/§12).
  static Future<void> pruneFor(
    String projectId,
    String surfaceId, {
    int maxCount = defaultMaxCount,
    int maxBytes = defaultMaxBytes,
  }) async {
    final entries = forSurface(projectId, surfaceId); // newest first
    final keepIds = <String>{};
    var runningBytes = 0;
    for (final e in entries) {
      final withinCount = keepIds.length < maxCount;
      final size = directorySizeBytes(Directory(e.archivePath));
      // Always keep at least the newest report even if it alone exceeds the
      // byte budget — a budget that can never hold anything isn't useful.
      final withinBytes =
          keepIds.isEmpty || runningBytes + size <= maxBytes;
      if (withinCount && withinBytes) {
        keepIds.add(e.runId);
        runningBytes += size;
      } else {
        deleteDirectoryQuietly(e.archivePath);
      }
    }
    if (keepIds.length == entries.length) return; // nothing pruned

    final all = load()
        .where((r) =>
            !(r.projectId == projectId && r.surfaceId == surfaceId) ||
            keepIds.contains(r.runId))
        .toList();
    await _saveAll(all);
  }

  /// Manual "Clear all reports" — deletes every archived folder and store
  /// entry for [projectId]/[surfaceId].
  static Future<void> clearFor(String projectId, String surfaceId) async {
    for (final e in forSurface(projectId, surfaceId)) {
      deleteDirectoryQuietly(e.archivePath);
    }
    final all = load()
        .where((r) => !(r.projectId == projectId && r.surfaceId == surfaceId))
        .toList();
    await _saveAll(all);
  }
}
