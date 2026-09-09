/// One completed (or cancelled/failed) pipeline run, persisted so the History
/// panel survives an app restart. Deliberately thin — enough to show "what
/// happened last time" and to re-open its Allure report / log file, not a
/// full audit trail.
class RunRecord {
  final String recipeId;
  final String recipeName;
  final DateTime startedAt;
  final int durationMs;

  /// [RunStatus.name] — kept as a plain string so this model doesn't need to
  /// import run_model.dart just for one enum.
  final String status;

  /// True when the pipeline reached its final (detached) report-open step —
  /// i.e. ran to completion without a terminal failure. A fresh Allure report
  /// exists on disk iff this is true.
  final bool hasReport;

  /// Path to this run's full log, written by [RunProvider] under
  /// `docs/run-logs/`. Null if the write failed or was skipped.
  final String? logPath;

  /// Which project this run belongs to — null for runs recorded before this
  /// field existed. **Bug this fixes**: without it, two different projects
  /// that both have (say) a `"web"` surface show each other's run history
  /// intermixed, since `recipeId` alone (== surface id) isn't unique across
  /// projects. See docs/RUN_EXPERIENCE_REDESIGN.md §9.
  final String? projectId;

  /// The run id [RunProvider.start] returned for this run — same identity
  /// [ReportArchive.runId] uses, so the two can be joined without
  /// duplicating report metadata here. Null for runs recorded before this
  /// field existed.
  final String? runId;

  // ── Re-run metadata (docs/RUN_EXPERIENCE_REDESIGN.md §9's
  // "re-run pre-filled, not blind identical repeat") — all null for a run
  // dispatched before this field existed, or one started outside the
  // Scripts screen's picker flow (the legacy single-project screen).

  /// [ScriptEntry.displayName] at run time — plain text, not a live
  /// reference, since the script may be renamed/deleted since.
  final String? scriptDisplayName;
  final String? environmentId;

  /// `"android"` | `"ios"` | null (web, or platform not applicable).
  final String? platform;

  /// `"simulator"` | `"physical"` | null.
  final String? deviceKind;
  final String? deviceUdid;

  /// `"run"` | `"pullAndRun"` | `"buildAndRun"` | null.
  final String? mode;

  const RunRecord({
    required this.recipeId,
    required this.recipeName,
    required this.startedAt,
    required this.durationMs,
    required this.status,
    required this.hasReport,
    this.logPath,
    this.projectId,
    this.runId,
    this.scriptDisplayName,
    this.environmentId,
    this.platform,
    this.deviceKind,
    this.deviceUdid,
    this.mode,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  /// True if there's enough on file to re-open the run picker pre-filled —
  /// the Re-run action falls back to a plain manual re-run otherwise.
  bool get hasRerunInfo => environmentId != null;

  Map<String, dynamic> toJson() => {
        'recipeId': recipeId,
        'recipeName': recipeName,
        'startedAt': startedAt.toIso8601String(),
        'durationMs': durationMs,
        'status': status,
        'hasReport': hasReport,
        'logPath': logPath,
        if (projectId != null) 'projectId': projectId,
        if (runId != null) 'runId': runId,
        if (scriptDisplayName != null) 'scriptDisplayName': scriptDisplayName,
        if (environmentId != null) 'environmentId': environmentId,
        if (platform != null) 'platform': platform,
        if (deviceKind != null) 'deviceKind': deviceKind,
        if (deviceUdid != null) 'deviceUdid': deviceUdid,
        if (mode != null) 'mode': mode,
      };

  /// Never throws — a malformed row is dropped by the caller instead.
  static RunRecord fromJson(Map<String, dynamic> json) {
    return RunRecord(
      recipeId: json['recipeId'] as String,
      recipeName: json['recipeName'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      durationMs: json['durationMs'] as int,
      status: json['status'] as String,
      hasReport: json['hasReport'] as bool? ?? false,
      logPath: json['logPath'] as String?,
      projectId: json['projectId'] as String?,
      runId: json['runId'] as String?,
      scriptDisplayName: json['scriptDisplayName'] as String?,
      environmentId: json['environmentId'] as String?,
      platform: json['platform'] as String?,
      deviceKind: json['deviceKind'] as String?,
      deviceUdid: json['deviceUdid'] as String?,
      mode: json['mode'] as String?,
    );
  }
}
