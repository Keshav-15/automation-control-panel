import 'dart:io';

import 'package:flutter_boilerplate/src/base/qa/run_dispatcher.dart';
import 'package:flutter_boilerplate/src/models/qa/device_model.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _git(String cwd, String args) async {
  final r = await Process.run('/bin/zsh', ['-l', '-c', 'git $args'],
      workingDirectory: cwd);
  if (r.exitCode != 0) {
    throw Exception('git $args failed in $cwd: ${r.stderr}');
  }
}

void main() {
  group('substitute', () {
    test('replaces environment, udid, and script tokens', () {
      final result = RunDispatcher.substitute(
        'wdio run --env {environment} --udid {udid} --spec {script}',
        environment: 'dev',
        udid: 'ABCD-1234',
        script: 'login.e2e.ts',
      );
      expect(result, 'wdio run --env dev --udid ABCD-1234 --spec login.e2e.ts');
    });

    test('a command with no udid/script placeholders (web) only substitutes environment',
        () {
      final result =
          RunDispatcher.substitute('npm run test:{environment}', environment: 'staging');
      expect(result, 'npm run test:staging');
    });
  });

  group('pullAndCheckForChanges', () {
    late Directory root;
    late Directory origin;
    late Directory clone;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('qa_dispatcher_pull');
      origin = Directory('${root.path}/origin')..createSync();
      await _git(origin.path, 'init -q -b develop');
      await _git(origin.path, 'config user.email test@example.com');
      await _git(origin.path, 'config user.name Test');
      File('${origin.path}/f.txt').writeAsStringSync('v1');
      await _git(origin.path, 'add f.txt');
      await _git(origin.path, 'commit -q -m v1');

      await _git(root.path, 'clone -q "${origin.path}" clone');
      clone = Directory('${root.path}/clone');
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('reports true when the remote has new commits, and actually pulls them',
        () async {
      File('${origin.path}/f.txt').writeAsStringSync('v2');
      await _git(origin.path, 'add f.txt');
      await _git(origin.path, 'commit -q -m v2');

      final changed = await RunDispatcher().pullAndCheckForChanges(
        repoAbsPath: clone.path,
        branch: 'develop',
      );

      expect(changed, isTrue);
      expect(File('${clone.path}/f.txt').readAsStringSync(), 'v2',
          reason: 'the change should actually have been pulled, not just detected');
    });

    test('reports false when already up to date', () async {
      final changed = await RunDispatcher().pullAndCheckForChanges(
        repoAbsPath: clone.path,
        branch: 'develop',
      );
      expect(changed, isFalse);
    });
  });

  group('planSteps', () {
    RepoEntry repo(String role, {String branch = 'develop'}) =>
        RepoEntry(role: role, label: role, relPath: role, branch: branch);

    CommandConfig cmd(
      String id, {
      List<String> tags = const [],
      String? target,
      String command = 'echo noop',
      String repoRole = 'mobile_ui',
    }) =>
        CommandConfig(
          id: id,
          name: id,
          command: command,
          repoRole: repoRole,
          tags: tags,
          target: target,
          order: 0,
        );

    ProjectConfig baseProject({
      required SurfaceConfig surface,
      List<CommandConfig> commands = const [],
      Map<String, RepoEntry> repos = const {},
    }) =>
        ProjectConfig(
          id: 'p1',
          name: 'Test',
          projectsRoot: '/tmp',
          repos: repos,
          commands: commands,
          surfaces: [surface],
        );

    ScriptEntry script() =>
        ScriptEntry(id: 's1', path: '/repo/test/login.e2e.ts', addedAt: DateTime.now());

    test('returns null when the runner command for this combo is not configured',
        () async {
      final surface = SurfaceConfig.autoMobile(); // no test commands assigned
      final project = baseProject(surface: surface);

      final steps = await RunDispatcher().planSteps(
        project: project,
        surface: surface,
        script: script(),
      );

      expect(steps, isNull);
    });

    test('runBuild on includes every matching build step before the run step',
        () async {
      final runCmd = cmd('run_android_sim',
          tags: const ['test'],
          target: 'simulator',
          command: 'wdio run --spec {script} --udid {udid} --env {environment}');
      final buildCmd = cmd('build_android', tags: const ['build']);
      final installCmd = cmd('install_android', tags: const ['build']);

      var surface = SurfaceConfig.autoMobile().copyWith(
        environmentId: 'dev',
        commandIds: [runCmd.id, buildCmd.id, installCmd.id],
        runBuild: true,
      );
      final project = baseProject(
        surface: surface,
        commands: [runCmd, buildCmd, installCmd],
      );

      final steps = await RunDispatcher().planSteps(
        project: project,
        surface: surface,
        script: script(),
        platform: DevicePlatform.android,
        deviceKind: DeviceKind.simulator,
        deviceUdid: 'emulator-5554',
      );

      expect(steps, isNotNull);
      final ids = steps!.map((s) => s.id).toList();
      expect(ids, [buildCmd.id, installCmd.id, 'run_s1']);
      expect(steps.last.command,
          'wdio run --spec /repo/test/login.e2e.ts --udid emulator-5554 --env dev');
    });

    test('runBuild off skips build steps on web, regardless of what the pool has',
        () async {
      final runCmd = cmd('run_web',
          tags: const ['test'], command: 'npm run test:{environment}', repoRole: 'web');
      final buildCmd = cmd('build_web', tags: const ['build'], repoRole: 'web');

      var surface = SurfaceConfig.autoWeb().copyWith(
        environmentId: 'staging',
        commandIds: [runCmd.id, buildCmd.id],
      );
      final project = baseProject(surface: surface, commands: [runCmd, buildCmd]);

      final steps = await RunDispatcher().planSteps(
        project: project,
        surface: surface,
        script: script(),
      );

      expect(steps!.map((s) => s.id).toList(), ['run_s1']);
      expect(steps.single.command, 'npm run test:staging');
    });

    test('runBuild off skips build steps on mobile too', () async {
      final runCmd = cmd('run_ios_sim',
          tags: const ['test'], target: 'simulator', command: 'wdio run ios');
      final buildCmd = cmd('build_ios', tags: const ['build']);

      var surface = SurfaceConfig.autoMobile().copyWith(
        commandIds: [runCmd.id, buildCmd.id],
      );
      final project = baseProject(
        surface: surface,
        commands: [runCmd, buildCmd],
        repos: {'mobile_ui': repo('mobile_ui')},
      );

      final steps = await RunDispatcher().planSteps(
        project: project,
        surface: surface,
        script: script(),
        platform: DevicePlatform.ios,
        deviceKind: DeviceKind.simulator,
        deviceUdid: 'some-sim-udid',
      );

      expect(steps!.map((s) => s.id).toList(), ['run_s1']);
    });

    test('prerequisite commands (tagged git/prerequisite) run first, in '
        'order, ahead of everything else', () async {
      final runCmd = cmd('run_web',
          tags: const ['test'], command: 'npm run test:{environment}', repoRole: 'web');
      final gitPull =
          cmd('git_pull', tags: const ['git'], command: 'git pull', repoRole: 'web');
      final pubGet = cmd('pub_get',
          tags: const ['prerequisite'], command: 'flutter pub get', repoRole: 'web');
      // Untagged — must NOT be swept in as a prerequisite just because it's
      // assigned to the surface.
      final notPrereq = cmd('unrelated', command: 'echo hi', repoRole: 'web');

      var surface = SurfaceConfig.autoWeb().copyWith(
        environmentId: 'dev',
        commandIds: [runCmd.id, gitPull.id, pubGet.id, notPrereq.id],
        runPrerequisites: true,
      );
      final project = baseProject(
          surface: surface, commands: [runCmd, gitPull, pubGet, notPrereq]);

      final steps = await RunDispatcher().planSteps(
        project: project,
        surface: surface,
        script: script(),
      );

      expect(steps!.map((s) => s.id).toList(), [gitPull.id, pubGet.id, 'run_s1']);
    });

    test('runPrerequisites off skips them even though tagged git/prerequisite',
        () async {
      final runCmd = cmd('run_web', tags: const ['test'], command: 'npm run test', repoRole: 'web');
      final pubGet = cmd('pub_get',
          tags: const ['prerequisite'], command: 'flutter pub get', repoRole: 'web');

      var surface = SurfaceConfig.autoWeb().copyWith(
        commandIds: [runCmd.id, pubGet.id],
        runPrerequisites: false,
      );
      final project = baseProject(surface: surface, commands: [runCmd, pubGet]);

      final steps = await RunDispatcher().planSteps(
        project: project,
        surface: surface,
        script: script(),
      );

      expect(steps!.map((s) => s.id).toList(), ['run_s1']);
    });

    test(
        'report command is appended last when a report-tagged command and '
        'reportOutputRelPath are both set', () async {
      final runCmd = cmd('run_web',
          tags: const ['test'], command: 'npm run test:{environment}', repoRole: 'web');
      final reportCmd = cmd('allure_open_web',
          tags: const ['report'], command: 'yarn allure:open', repoRole: 'web');

      var surface = SurfaceConfig.autoWeb().copyWith(
        environmentId: 'dev',
        commandIds: [runCmd.id, reportCmd.id],
        reportOutputRelPath: 'allure-report',
      );
      final project = baseProject(surface: surface, commands: [runCmd, reportCmd]);

      final steps = await RunDispatcher().planSteps(
        project: project,
        surface: surface,
        script: script(),
      );

      expect(steps!.map((s) => s.id).toList(), ['run_s1', 'report_web']);
      expect(steps.last.command, 'yarn allure:open');
      expect(steps.last.repo, 'web');
    });

    test('report command is omitted when reportOutputRelPath is not set',
        () async {
      final runCmd = cmd('run_web', tags: const ['test'], command: 'npm run test', repoRole: 'web');
      final reportCmd = cmd('allure_open_web', tags: const ['report'], repoRole: 'web');

      var surface = SurfaceConfig.autoWeb().copyWith(
        commandIds: [runCmd.id, reportCmd.id],
        // reportOutputRelPath left unset
      );
      final project = baseProject(surface: surface, commands: [runCmd, reportCmd]);

      final steps = await RunDispatcher().planSteps(
        project: project,
        surface: surface,
        script: script(),
      );

      expect(steps!.map((s) => s.id).toList(), ['run_s1']);
    });

    test('report command is omitted entirely when neither field is set',
        () async {
      final runCmd = cmd('run_web', tags: const ['test'], command: 'npm run test', repoRole: 'web');
      var surface = SurfaceConfig.autoWeb().copyWith(
        commandIds: [runCmd.id],
      );
      final project = baseProject(surface: surface, commands: [runCmd]);

      final steps = await RunDispatcher().planSteps(
        project: project,
        surface: surface,
        script: script(),
      );

      expect(steps!.map((s) => s.id).toList(), ['run_s1']);
    });
  });
}
