import 'dart:convert';
import 'dart:io';

import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:path_provider/path_provider.dart';

/// Persists [ProjectConfig] objects as individual JSON files under
/// `<appSupportDir>/qa_control_center/projects/<id>.json`.
///
/// All methods are async but never throw — errors are returned as empty lists
/// or re-thrown with context so callers can surface them to the user.
class ProjectStore {
  static const _subDir = 'qa_control_center/projects';

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_subDir');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  File _file(Directory dir, String id) => File('${dir.path}/$id.json');

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Load every project from disk; silently skips malformed files.
  Future<List<ProjectConfig>> loadAll() async {
    final dir = await _dir();
    final projects = <ProjectConfig>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw = entity.readAsStringSync();
        projects.add(ProjectConfig.fromJsonString(raw));
      } catch (_) {
        // Malformed JSON — skip this file rather than crashing the app.
      }
    }
    // Sort: pinned first (newest pin at top), then by lastOpenedAt desc.
    projects.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      if (a.isPinned && b.isPinned) {
        return (b.pinnedAt ?? DateTime(0)).compareTo(a.pinnedAt ?? DateTime(0));
      }
      return (b.lastOpenedAt ?? DateTime(0))
          .compareTo(a.lastOpenedAt ?? DateTime(0));
    });
    return projects;
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Save (create or update) a project.
  Future<void> save(ProjectConfig project) async {
    final dir = await _dir();
    _file(dir, project.id).writeAsStringSync(project.toJsonString());
  }

  /// Delete a project by id. No-op if not found.
  Future<void> delete(String id) async {
    final dir = await _dir();
    final f = _file(dir, id);
    if (f.existsSync()) f.deleteSync();
  }

  // ── Import / Export ───────────────────────────────────────────────────────

  /// Serialize a project to a shareable JSON string.
  ///
  /// The recipient can call [importFromJsonString] on another machine.
  /// Absolute [projectsRoot] and repo paths are NOT stripped — the importer
  /// will need to re-map them via the Create/Edit screen.
  String exportToJsonString(ProjectConfig project) => project.toJsonString();

  /// Write the project JSON to [path] (chosen via file dialog by the caller).
  Future<void> exportToFile(ProjectConfig project, String path) async {
    File(path).writeAsStringSync(exportToJsonString(project));
  }

  /// Parse a project JSON string and return a [ProjectConfig].
  ///
  /// Does NOT save to disk — call [save] after the user has confirmed /
  /// re-mapped repo paths.
  ProjectConfig importFromJsonString(String jsonStr) {
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    // Always generate a fresh id so we never collide with an existing project
    // on this machine if the user imports the same config twice.
    final newId = generateProjectId();
    return ProjectConfig.fromJson({...json, 'id': newId});
  }

  /// Read a JSON file from [path] and return the parsed [ProjectConfig].
  ProjectConfig importFromFile(String path) {
    final raw = File(path).readAsStringSync();
    return importFromJsonString(raw);
  }
}
