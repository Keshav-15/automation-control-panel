import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_boilerplate/src/base/qa/project_store.dart';
import 'package:flutter_boilerplate/src/base/qa/project_template.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';

/// CRUD and I/O operations for [ProjectConfig].
///
/// Thin layer between [ProjectProvider] and [ProjectStore]; owns no state.
class ProjectController {
  final ProjectStore _store;

  ProjectController({ProjectStore? store})
      : _store = store ?? ProjectStore();

  Future<List<ProjectConfig>> loadAll() => _store.loadAll();

  // ── Create ────────────────────────────────────────────────────────────────

  Future<ProjectConfig> create({
    required String name,
    required String projectsRoot,
    required ProjectTemplateType templateType,
    Map<String, String>? repoRelPaths,
    Map<String, String>? repoBranches,
    List<String> extraPathDirs = const [],
  }) async {
    final project = ensureAutoSurfaces(switch (templateType) {
      ProjectTemplateType.centurion => ProjectTemplate.centurion(
          name: name,
          projectsRoot: projectsRoot,
          repoRelPaths: repoRelPaths,
          repoBranches: repoBranches,
          extraPathDirs: extraPathDirs,
        ),
      ProjectTemplateType.custom => ProjectTemplate.custom(
          name: name,
          projectsRoot: projectsRoot,
          repoRelPaths: repoRelPaths,
          repoBranches: repoBranches,
          extraPathDirs: extraPathDirs,
        ),
    });
    await _store.save(project);
    return project;
  }

  /// Ensures the well-known auto-surfaces exist for whatever repos are
  /// currently configured — idempotent (create-if-missing) and additive
  /// only: never removes or overwrites an existing surface, even one whose
  /// backing repo was later removed (see docs/RUN_EXPERIENCE_REDESIGN.md §2).
  ///
  /// Called from [create] and [save] — the only two places a project's
  /// `repos` map can actually change.
  ProjectConfig ensureAutoSurfaces(ProjectConfig project) {
    bool hasSurface(String id) => project.surfaces.any((s) => s.id == id);
    // The Centurion template already ships its own 'ios'/'android' surfaces
    // for a project whose mobile_ui/mobile_test repos it seeded — those
    // already cover mobile, so don't also add an empty unified 'mobile'
    // surface alongside them.
    final mobileAlreadyCovered =
        hasSurface('mobile') || hasSurface('ios') || hasSurface('android');
    final additions = <SurfaceConfig>[
      if (project.repos.containsKey('web') && !hasSurface('web'))
        SurfaceConfig.autoWeb(),
      if (project.repos.containsKey('mobile_ui') &&
          project.repos.containsKey('mobile_test') &&
          !mobileAlreadyCovered)
        SurfaceConfig.autoMobile(),
    ];
    return additions.isEmpty
        ? project
        : project.copyWith(surfaces: [...project.surfaces, ...additions]);
  }

  // ── Update ────────────────────────────────────────────────────────────────

  Future<void> save(ProjectConfig project) =>
      _store.save(ensureAutoSurfaces(project));

  Future<ProjectConfig> markLastOpened(ProjectConfig project) async {
    final updated = project.copyWith(lastOpenedAt: DateTime.now());
    await _store.save(updated);
    return updated;
  }

  Future<ProjectConfig> togglePin(ProjectConfig project) async {
    final updated = project.isPinned
        ? project.copyWith(clearPinnedAt: true)
        : project.copyWith(pinnedAt: DateTime.now());
    await _store.save(updated);
    return updated;
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> delete(String id) => _store.delete(id);

  // ── Global command pool ───────────────────────────────────────────────────

  /// Add or update a command in the project's global pool.
  Future<ProjectConfig> upsertProjectCommand({
    required ProjectConfig project,
    required CommandConfig command,
  }) async {
    final newCommands = List<CommandConfig>.of(project.commands);
    final idx = newCommands.indexWhere((c) => c.id == command.id);
    if (idx >= 0) {
      newCommands[idx] = command;
    } else {
      newCommands.add(command);
    }
    final updated = project.copyWith(commands: newCommands);
    await _store.save(updated);
    return updated;
  }

  /// Add command to pool (if not present) AND append its id to [surfaceId]'s
  /// commandIds (if not already there).
  Future<ProjectConfig> addCommandToSurface({
    required ProjectConfig project,
    required CommandConfig command,
    required String surfaceId,
  }) async {
    // Upsert in pool
    final newCommands = List<CommandConfig>.of(project.commands);
    final idx = newCommands.indexWhere((c) => c.id == command.id);
    if (idx >= 0) {
      newCommands[idx] = command;
    } else {
      newCommands.add(command);
    }

    // Append to surface commandIds if not already there
    final newSurfaces = project.surfaces.map((s) {
      if (s.id != surfaceId) return s;
      if (s.commandIds.contains(command.id)) return s;
      return s.copyWith(commandIds: [...s.commandIds, command.id]);
    }).toList();

    final updated = project.copyWith(commands: newCommands, surfaces: newSurfaces);
    await _store.save(updated);
    return updated;
  }

  /// Delete a command from the pool and remove it from all surfaces.
  Future<ProjectConfig> deleteProjectCommand({
    required ProjectConfig project,
    required String commandId,
  }) async {
    final newCommands =
        project.commands.where((c) => c.id != commandId).toList();
    final newSurfaces = project.surfaces
        .map((s) => s.copyWith(
              commandIds: s.commandIds.where((id) => id != commandId).toList(),
            ))
        .toList();
    final updated =
        project.copyWith(commands: newCommands, surfaces: newSurfaces);
    await _store.save(updated);
    return updated;
  }

  /// Replace the ordered commandIds for [surfaceId] (used for reordering /
  /// toggling surface assignment).
  Future<ProjectConfig> updateSurfaceCommandIds({
    required ProjectConfig project,
    required String surfaceId,
    required List<String> commandIds,
  }) async {
    final newSurfaces = project.surfaces
        .map((s) =>
            s.id == surfaceId ? s.copyWith(commandIds: commandIds) : s)
        .toList();
    final updated = project.copyWith(surfaces: newSurfaces);
    await _store.save(updated);
    return updated;
  }

  /// Add or remove a surface, or rename/change its icon.
  Future<ProjectConfig> upsertSurface({
    required ProjectConfig project,
    required SurfaceConfig surface,
  }) async {
    final existing = project.surfaces.any((s) => s.id == surface.id);
    final surfaces = existing
        ? project.surfaces
            .map((s) => s.id == surface.id ? surface : s)
            .toList()
        : [...project.surfaces, surface];
    final updated = project.copyWith(surfaces: surfaces);
    await _store.save(updated);
    return updated;
  }

  /// Remove a surface.
  Future<ProjectConfig> removeSurface({
    required ProjectConfig project,
    required String surfaceId,
  }) async {
    final surfaces =
        project.surfaces.where((s) => s.id != surfaceId).toList();
    final updated = project.copyWith(surfaces: surfaces);
    await _store.save(updated);
    return updated;
  }

  // ── Import / Export ───────────────────────────────────────────────────────

  Future<String?> exportToFile(ProjectConfig project) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export project config',
      fileName:
          '${project.name.toLowerCase().replaceAll(' ', '_')}_project.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return null;
    await _store.exportToFile(project, result);
    return result;
  }

  Future<ProjectConfig?> importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import project config',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    return _store.importFromFile(path);
  }

  /// Import commands for a surface from a JSON file.
  ///
  /// Accepts either:
  ///   • an array of command objects: `[{id, name, command, repoRole, ...}]`
  ///   • a legacy surface config object: `{id, name, icon, commands: [...]}`
  Future<List<CommandConfig>?> importCommandsFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import commands from JSON',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    final raw = File(path).readAsStringSync();
    return parseCommandsJson(raw);
  }

  /// Parse a JSON string into a list of [CommandConfig].
  ///
  /// Returns null on parse error. When [validRepoRoles] is supplied, commands
  /// whose [CommandConfig.repoRole] is not in that set are dropped.
  List<CommandConfig>? parseCommandsJson(
    String raw, {
    Set<String>? validRepoRoles,
    void Function(String message)? onWarning,
  }) {
    try {
      final dynamic parsed = jsonDecode(raw);
      List<CommandConfig> cmds;

      if (parsed is List) {
        cmds = parsed.asMap().entries.map((e) {
          final map = Map<String, dynamic>.from(e.value as Map);
          map.putIfAbsent('order', () => e.key);
          return CommandConfig.fromJson(map);
        }).toList();
      } else if (parsed is Map<String, dynamic> &&
          parsed.containsKey('commands')) {
        // Legacy surface-config format — extract commands array directly
        cmds = (parsed['commands'] as List? ?? []).asMap().entries.map((e) {
          final map = Map<String, dynamic>.from(e.value as Map);
          map.putIfAbsent('order', () => e.key);
          return CommandConfig.fromJson(map);
        }).toList();
      } else {
        return null;
      }

      if (validRepoRoles != null && validRepoRoles.isNotEmpty) {
        final invalid =
            cmds.where((c) => !validRepoRoles.contains(c.repoRole)).toList();
        if (invalid.isNotEmpty) {
          final names =
              invalid.map((c) => '"${c.name}" (repo: ${c.repoRole})').join(', ');
          onWarning
              ?.call('Skipped ${invalid.length} command(s) with unknown repoRole: $names');
          cmds = cmds.where((c) => validRepoRoles.contains(c.repoRole)).toList();
        }
      }

      return cmds.isEmpty ? null : cmds;
    } catch (_) {
      return null;
    }
  }

  // ── Folder / file pickers ─────────────────────────────────────────────────

  Future<String?> pickFolder({String? dialogTitle, String? initialDirectory}) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle ?? 'Select folder',
      initialDirectory: initialDirectory,
    );
    return result;
  }

  /// Pick one or more files (e.g. test spec files to add as scripts).
  Future<List<String>> pickFiles({
    String? dialogTitle,
    bool allowMultiple = true,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle ?? 'Select file(s)',
      allowMultiple: allowMultiple,
    );
    return result?.paths.whereType<String>().toList() ?? [];
  }

  // ── Scripts ───────────────────────────────────────────────────────────────

  /// Recursively collects every *file* (not directory) under [folderPath],
  /// for the "import scripts from a folder" flow — dedup against what's
  /// already added happens at the call site (dedup is by path).
  List<String> collectFilesUnder(String folderPath) {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .toList();
  }

  /// Parses the `"scripts"` object of a `package.json` at [packageJsonPath].
  /// Returns null if the file is missing or not valid JSON with a scripts map.
  Map<String, String>? parsePackageJsonScripts(String packageJsonPath) {
    final file = File(packageJsonPath);
    if (!file.existsSync()) return null;
    try {
      final parsed = jsonDecode(file.readAsStringSync());
      if (parsed is! Map) return null;
      final scripts = parsed['scripts'];
      if (scripts is! Map) return null;
      return scripts.map((k, v) => MapEntry(k as String, v.toString()));
    } catch (_) {
      return null;
    }
  }
}
