import 'dart:io';

import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/base/qa/report_archive_store.dart';
import 'package:flutter_boilerplate/src/base/utils/dir_copy_utils.dart';
import 'package:flutter_boilerplate/src/models/qa/device_model.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/models/qa/report_archive_model.dart';
import 'package:path_provider/path_provider.dart';

/// Copies a surface's report output into app-managed storage and records a
/// [ReportArchive] entry — the actual archiving mechanism behind
/// docs/RUN_EXPERIENCE_REDESIGN.md §8. Deliberately separate from
/// [RunDispatcher]: [RunDispatcher] only needs to call [archiveAfterRun]
/// once a run finishes; [Regenerate] (driven from the Reports screen, no run
/// involved) reuses the same copy logic via [regenerate].
class ReportArchiver {
  ReportArchiver({ProcessGateway? gateway}) : _gateway = gateway ?? ProcessGateway();
  final ProcessGateway _gateway;

  static const _subDir = 'qa_control_center/reports';

  static Future<Directory> _reportsRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/$_subDir');
  }

  /// Resolves where the report tool actually wrote its output — the
  /// filter-resolved report command's own repo (see
  /// [ProjectConfig.reportCommandFor]) joined with
  /// [SurfaceConfig.reportOutputRelPath]. Null if either half of the report
  /// config is missing.
  static String? sourcePathFor(
    ProjectConfig project,
    SurfaceConfig surface, {
    required String environmentId,
  }) {
    final relPath = surface.reportOutputRelPath;
    if (relPath == null) return null;
    final cmd = project.reportCommandFor(surface.id);
    final repo = cmd == null ? null : project.repos[cmd.repoRole];
    if (repo == null) return null;
    return '${repo.absPath(project.projectsRoot)}/$relPath';
  }

  /// Copies [surface]'s report output (if any is on disk — best-effort, a
  /// report command that failed or a surface with no report config
  /// configured just means nothing to archive) into
  /// `<appSupportDir>/qa_control_center/reports/<projectId>/<surfaceId>/<runId>/`
  /// and records + prunes a [ReportArchive] entry. Returns null when there
  /// was nothing to archive.
  Future<ReportArchive?> archiveAfterRun({
    required ProjectConfig project,
    required SurfaceConfig surface,
    required ScriptEntry script,
    required String environmentId,
    required String runId,
    required String commandUsed,
    DevicePlatform? platform,
    String? deviceUdid,
  }) async {
    final sourcePath = sourcePathFor(project, surface, environmentId: environmentId);
    if (sourcePath == null) return null;

    final sourceDir = Directory(sourcePath);
    if (!sourceDir.existsSync()) return null;

    final destDir = Directory(
        '${(await _reportsRoot()).path}/${project.id}/${surface.id}/$runId');
    copyDirectoryContents(sourceDir, destDir);

    final entry = ReportArchive(
      runId: runId,
      projectId: project.id,
      surfaceId: surface.id,
      script: script.displayName,
      environment: environmentId,
      platform: platform?.name,
      device: deviceUdid,
      commandUsed: commandUsed,
      generatedAt: DateTime.now(),
      sourcePath: sourcePath,
      archivePath: destDir.path,
    );
    await ReportArchiveStore.append(entry);
    await ReportArchiveStore.pruneFor(project.id, surface.id);
    return entry;
  }

  /// Re-runs [archive]'s exact original report command against its
  /// [ReportArchive.sourcePath], then re-copies it over the same archived
  /// folder — best-effort, per docs/RUN_EXPERIENCE_REDESIGN.md §8: if the
  /// repo's raw report output is gone (cleaned up since), this returns
  /// false rather than trying to trigger a whole new script run, which is
  /// out of scope here — the caller tells the user a full re-run is needed
  /// instead.
  Future<bool> regenerate(ReportArchive archive, ProjectConfig project) async {
    final surface = project.surfaceById(archive.surfaceId);
    if (surface == null) return false;
    final reportCmd = project.reportCommandFor(surface.id);
    final repo = reportCmd == null ? null : project.repos[reportCmd.repoRole];
    if (reportCmd == null || repo == null) return false;

    final sourceDir = Directory(archive.sourcePath);
    if (!sourceDir.existsSync()) return false;

    await _gateway.exec(
      archive.commandUsed,
      workingDirectory: repo.absPath(project.projectsRoot),
      ignoreExitCode: true,
    );

    final destDir = Directory(archive.archivePath);
    deleteDirectoryQuietly(destDir.path);
    copyDirectoryContents(sourceDir, destDir);

    await ReportArchiveStore.update(archive.copyWith(generatedAt: DateTime.now()));
    return true;
  }
}
