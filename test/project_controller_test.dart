import 'package:flutter_boilerplate/src/controllers/qa/project_controller.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// ensureAutoSurfaces is pure (no I/O), so a bare ProjectController is fine —
/// none of these tests touch its ProjectStore.
void main() {
  final controller = ProjectController();

  ProjectConfig baseProject({
    required Map<String, RepoEntry> repos,
    List<SurfaceConfig> surfaces = const [],
  }) =>
      ProjectConfig(
        id: 'p1',
        name: 'Test',
        projectsRoot: '/tmp',
        repos: repos,
        surfaces: surfaces,
      );

  RepoEntry repo(String role) =>
      RepoEntry(role: role, label: role, relPath: role);

  group('ensureAutoSurfaces', () {
    test('adding a web repo creates a web surface', () {
      final project = baseProject(repos: {'web': repo('web')});
      final result = controller.ensureAutoSurfaces(project);

      expect(result.surfaces.map((s) => s.id), contains('web'));
    });

    test('both mobile_ui and mobile_test present creates one mobile surface',
        () {
      final project = baseProject(
          repos: {'mobile_ui': repo('mobile_ui'), 'mobile_test': repo('mobile_test')});
      final result = controller.ensureAutoSurfaces(project);

      expect(result.surfaces.map((s) => s.id), ['mobile']);
    });

    test('only mobile_ui (missing mobile_test) creates nothing', () {
      final project = baseProject(repos: {'mobile_ui': repo('mobile_ui')});
      final result = controller.ensureAutoSurfaces(project);
      expect(result.surfaces, isEmpty);
    });

    test('only mobile_test (missing mobile_ui) creates nothing', () {
      final project = baseProject(repos: {'mobile_test': repo('mobile_test')});
      final result = controller.ensureAutoSurfaces(project);
      expect(result.surfaces, isEmpty);
    });

    test('idempotent: an existing web surface is never duplicated or overwritten',
        () {
      final existingWeb = const SurfaceConfig(
        id: 'web',
        name: 'Custom name the user set',
        icon: '🔵',
        commandIds: ['some_command'],
      );
      final project = baseProject(
        repos: {'web': repo('web')},
        surfaces: [existingWeb],
      );
      final result = controller.ensureAutoSurfaces(project);

      expect(result.surfaces, hasLength(1));
      expect(result.surfaces.single, same(existingWeb));
    });

    test('removing a repo never auto-deletes its surface', () {
      final orphanedSurface = const SurfaceConfig(
        id: 'web', name: 'Web Tests', icon: '🌐');
      // No 'web' repo in this project at all — surface has no backing repo.
      final project = baseProject(repos: {}, surfaces: [orphanedSurface]);
      final result = controller.ensureAutoSurfaces(project);

      expect(result.surfaces, [orphanedSurface]);
    });

    test('web and mobile can both auto-create together', () {
      final project = baseProject(repos: {
        'web': repo('web'),
        'mobile_ui': repo('mobile_ui'),
        'mobile_test': repo('mobile_test'),
      });
      final result = controller.ensureAutoSurfaces(project);
      expect(result.surfaces.map((s) => s.id).toSet(), {'web', 'mobile'});
    });

    test(
        'a Centurion-shaped project (existing ios/android surfaces) does not '
        'also get an extra empty "mobile" surface', () {
      const iosSurface = SurfaceConfig(id: 'ios', name: 'iOS Tests', icon: '🍎');
      const androidSurface =
          SurfaceConfig(id: 'android', name: 'Android Tests', icon: '🤖');
      final project = baseProject(
        repos: {'mobile_ui': repo('mobile_ui'), 'mobile_test': repo('mobile_test')},
        surfaces: [iosSurface, androidSurface],
      );
      final result = controller.ensureAutoSurfaces(project);

      expect(result.surfaces.map((s) => s.id).toSet(), {'ios', 'android'});
      expect(result.surfaces, [iosSurface, androidSurface]);
    });
  });
}
