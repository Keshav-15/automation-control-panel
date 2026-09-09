import 'dart:io';

import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart' as prefs;

/// The actual bug §9 fixes: two different projects that both have a "web"
/// surface must NOT see each other's run history, since `recipeId` alone
/// (== surface id) was never unique across projects.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late RunProvider run;

  ProjectConfig project(String id, String name) {
    Directory('${root.path}/$id/web_repo').createSync(recursive: true);
    return ProjectConfig(
      id: id,
      name: name,
      projectsRoot: '${root.path}/$id',
      repos: {'web': RepoEntry(role: 'web', label: 'Web', relPath: 'web_repo')},
      commands: [
        CommandConfig(
          id: 'noop',
          name: 'noop',
          command: 'echo hi',
          repoRole: 'web',
          order: 0,
        ),
      ],
      surfaces: [
        SurfaceConfig(id: 'web', name: 'Web Tests', icon: '🌐', commandIds: ['noop']),
      ],
    );
  }

  setUp(() async {
    prefs.dispose();
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    if (!locator.isRegistered<ProcessGateway>()) {
      locator.registerSingleton<ProcessGateway>(ProcessGateway());
    }
    root = Directory.systemTemp.createTempSync('qa_project_scoping');
    run = RunProvider();
  });

  tearDown(() async {
    await run.cancelAndWait();
    run.dispose();
    root.deleteSync(recursive: true);
  });

  test(
      'two projects with the same surface id ("web") do not bleed into each '
      'other\'s history/lastReportFor', () async {
    final projectA = project('proj-a', 'Project A');
    final projectB = project('proj-b', 'Project B');

    await run.start(
      recipe: projectA.simpleRecipeForSurface('web'),
      profile: projectA.toProfile(),
      manifest: projectA.toManifestModel(),
      syncEnabled: true,
      buildEnabled: true,
      projectId: projectA.id,
    );
    await run.start(
      recipe: projectB.simpleRecipeForSurface('web'),
      profile: projectB.toProfile(),
      manifest: projectB.toManifestModel(),
      syncEnabled: true,
      buildEnabled: true,
      projectId: projectB.id,
    );

    // Both recorded, both tagged with their own projectId.
    final webRecords = run.history.where((r) => r.recipeId == 'web').toList();
    expect(webRecords, hasLength(2));
    expect(webRecords.map((r) => r.projectId).toSet(), {'proj-a', 'proj-b'});

    // Scoped lookups only see their own project's record.
    final aOnly =
        run.history.where((r) => r.recipeId == 'web' && r.projectId == 'proj-a');
    expect(aOnly, hasLength(1));
    final bOnly =
        run.history.where((r) => r.recipeId == 'web' && r.projectId == 'proj-b');
    expect(bOnly, hasLength(1));
  });
}
