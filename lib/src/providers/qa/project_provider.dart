import 'package:flutter/foundation.dart';
import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/qa/project_template.dart';
import 'package:flutter_boilerplate/src/base/utils/constants/preference_key_constant.dart';
import 'package:flutter_boilerplate/src/controllers/qa/project_controller.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the list of all [ProjectConfig] objects and tracks the currently
/// open project.
class ProjectProvider extends ChangeNotifier {
  final ProjectController _controller;

  ProjectProvider({ProjectController? controller})
      : _controller = controller ?? locator<ProjectController>();

  // ── State ─────────────────────────────────────────────────────────────────

  List<ProjectConfig> _projects = [];
  List<ProjectConfig> get projects => List.unmodifiable(_projects);

  List<ProjectConfig> get pinned =>
      _projects.where((p) => p.isPinned).toList();

  List<ProjectConfig> get recent =>
      _projects.where((p) => !p.isPinned).toList();

  ProjectConfig? _currentProject;
  ProjectConfig? get currentProject => _currentProject;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  // ── Initialise ────────────────────────────────────────────────────────────

  Future<void> initialise() async {
    _loading = true;
    notifyListeners();
    try {
      _projects = await _controller.loadAll();
      if (_projects.isEmpty) await _migrateLegacyProfile();
      _error = null;
    } catch (e) {
      _error = 'Failed to load projects: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Project CRUD ──────────────────────────────────────────────────────────

  Future<ProjectConfig> createProject({
    required String name,
    required String projectsRoot,
    required ProjectTemplateType templateType,
    Map<String, String>? repoRelPaths,
    Map<String, String>? repoBranches,
    List<String> extraPathDirs = const [],
  }) async {
    final project = await _controller.create(
      name: name,
      projectsRoot: projectsRoot,
      templateType: templateType,
      repoRelPaths: repoRelPaths,
      repoBranches: repoBranches,
      extraPathDirs: extraPathDirs,
    );
    _projects = await _controller.loadAll();
    notifyListeners();
    return project;
  }

  Future<void> updateProject(ProjectConfig project) async {
    await _controller.save(project);
    _projects = await _controller.loadAll();
    if (_currentProject?.id == project.id) _currentProject = project;
    notifyListeners();
  }

  Future<void> deleteProject(String id) async {
    await _controller.delete(id);
    if (_currentProject?.id == id) _currentProject = null;
    _projects = await _controller.loadAll();
    notifyListeners();
  }

  Future<void> togglePin(ProjectConfig project) async {
    final updated = await _controller.togglePin(project);
    _projects = await _controller.loadAll();
    if (_currentProject?.id == updated.id) _currentProject = updated;
    notifyListeners();
  }

  Future<void> openProject(ProjectConfig project) async {
    final updated = await _controller.markLastOpened(project);
    _currentProject = updated;
    _projects = await _controller.loadAll();
    notifyListeners();
  }

  // ── Global command pool ───────────────────────────────────────────────────

  /// Add or update a command in the project pool.
  Future<ProjectConfig> upsertProjectCommand({
    required ProjectConfig project,
    required CommandConfig command,
  }) async {
    final updated = await _controller.upsertProjectCommand(
      project: project,
      command: command,
    );
    _sync(updated);
    return updated;
  }

  /// Add command to pool AND append to [surfaceId]'s commandIds.
  Future<ProjectConfig> addCommandToSurface({
    required ProjectConfig project,
    required CommandConfig command,
    required String surfaceId,
  }) async {
    final updated = await _controller.addCommandToSurface(
      project: project,
      command: command,
      surfaceId: surfaceId,
    );
    _sync(updated);
    return updated;
  }

  /// Delete a command from the pool and remove from all surfaces.
  Future<ProjectConfig> deleteProjectCommand({
    required ProjectConfig project,
    required String commandId,
  }) async {
    final updated = await _controller.deleteProjectCommand(
      project: project,
      commandId: commandId,
    );
    _sync(updated);
    return updated;
  }

  /// Replace commandIds for a surface (reorder / toggle assignment).
  Future<ProjectConfig> updateSurfaceCommandIds({
    required ProjectConfig project,
    required String surfaceId,
    required List<String> commandIds,
  }) async {
    final updated = await _controller.updateSurfaceCommandIds(
      project: project,
      surfaceId: surfaceId,
      commandIds: commandIds,
    );
    _sync(updated);
    return updated;
  }

  // ── Surface management ────────────────────────────────────────────────────

  Future<ProjectConfig> upsertSurface({
    required ProjectConfig project,
    required SurfaceConfig surface,
  }) async {
    final updated = await _controller.upsertSurface(
      project: project,
      surface: surface,
    );
    _sync(updated);
    return updated;
  }

  Future<ProjectConfig> removeSurface({
    required ProjectConfig project,
    required String surfaceId,
  }) async {
    final updated = await _controller.removeSurface(
      project: project,
      surfaceId: surfaceId,
    );
    _sync(updated);
    return updated;
  }

  // ── Import / Export ───────────────────────────────────────────────────────

  Future<String?> exportProject(ProjectConfig project) =>
      _controller.exportToFile(project);

  Future<ProjectConfig?> importProjectFromFile() =>
      _controller.importFromFile();

  Future<void> saveImportedProject(ProjectConfig project) async {
    await _controller.save(project);
    _projects = await _controller.loadAll();
    notifyListeners();
  }

  Future<List<CommandConfig>?> importCommandsFromFile() =>
      _controller.importCommandsFromFile();

  // ── Internal helpers ──────────────────────────────────────────────────────

  /// Update the cached project list and current project after a mutation.
  ///
  /// Updates in-memory from [updated] directly instead of re-reading every
  /// project from disk — that disk round-trip was `await`-less at every call
  /// site, so it raced callers that read `projects`/`currentProject` right
  /// after their `await provider.upsertSurface(...)` returned (e.g. a switch
  /// toggle not visibly rebuilding the surface card).
  void _sync(ProjectConfig updated) {
    if (_currentProject?.id == updated.id) _currentProject = updated;
    final idx = _projects.indexWhere((p) => p.id == updated.id);
    _projects = idx >= 0
        ? (List.of(_projects)..[idx] = updated)
        : [..._projects, updated];
    notifyListeners();
  }

  // ── Legacy migration ──────────────────────────────────────────────────────

  Future<void> _migrateLegacyProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final root = prefs.getString(prefkeyQAProjectsRoot);
      if (root == null || root.isEmpty) return;
      final extraDirs = prefs.getStringList(prefkeyQAExtraPath) ?? [];
      final project = await _controller.create(
        name: 'Centurion',
        projectsRoot: root,
        templateType: ProjectTemplateType.centurion,
        extraPathDirs: extraDirs,
      );
      _projects = [project];
    } catch (_) {
      // Best-effort — user starts fresh if migration fails.
    }
  }
}
