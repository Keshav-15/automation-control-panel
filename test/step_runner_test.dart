import 'dart:io';

import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/base/qa/step_runner.dart';
import 'package:flutter_boilerplate/src/models/qa/machine_profile_model.dart';
import 'package:flutter_boilerplate/src/models/qa/manifest_model.dart';
import 'package:flutter_boilerplate/src/models/qa/run_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Records what the pipeline asked the shell to do, and hands back canned
/// exit codes — no real processes in tests.
class FakeGateway extends ProcessGateway {
  /// exit code per command substring; anything unmatched exits 0.
  final Map<String, int> exitCodes;

  final List<String> streamed = [];
  final List<String> detached = [];
  final Map<String, Map<String, String>?> envFor = {};

  FakeGateway({this.exitCodes = const {}});

  int _exitFor(String command) {
    for (final entry in exitCodes.entries) {
      if (command.contains(entry.key)) return entry.value;
    }
    return 0;
  }

  @override
  Stream<LogLine> stream(
    String command, {
    String? workingDirectory,
    Map<String, String>? extraEnv,
    ProcessHandle? handle,
  }) async* {
    streamed.add(command);
    envFor[command] = extraEnv;
    yield LogLine('fake output for: $command', isError: false);
    handle?.setExitCode(_exitFor(command));
  }

  @override
  Future<void> detach(
    String command, {
    String? workingDirectory,
    Map<String, String>? extraEnv,
  }) async {
    detached.add(command);
  }

  @override
  Future<String> exec(
    String command, {
    String? workingDirectory,
    Map<String, String>? extraEnv,
    bool ignoreExitCode = false,
  }) async =>
      'fake';
}

const _yaml = '''
product: test
environment: dev
repos:
  web:
    rel_path: web_repo
    branch: develop
  mobile_tests:
    rel_path: tests_repo
    branch: develop
recipes:
  web:
    name: Web Tests
    surface: web
    steps:
      - id: sync
        name: Sync
        command: git pull origin develop
        repo: web
        skip_if_no_sync: true
      - id: install
        name: Install
        command: yarn install
        repo: web
      - id: test
        name: Test
        command: yarn test
        repo: web
        spec_command: playwright test {flags}
      - id: report
        name: Open report
        command: yarn allure:open
        repo: web
        detach: true
  ios:
    name: iOS Tests
    surface: ios
    steps:
      - id: build_sim
        name: Build simulator
        command: flutter build ios --simulator
        repo: web
        target: simulator
        skip_if_no_build: true
      - id: build_dev
        name: Build device
        command: flutter build ios
        repo: web
        target: device
        skip_if_no_build: true
      - id: install_sim
        name: Install on simulator
        command: xcrun simctl install \$IOS_SIMULATOR_UDID app
        repo: web
        target: simulator
        env_file: tests_repo/.env.dev
  android:
    name: Android Tests
    surface: android
    steps:
      - id: install_deps
        name: npm ci
        command: npm ci
        repo: mobile_tests
      - id: test_android
        name: Run WDIO Android tests
        command: npm run test:android:dev
        repo: mobile_tests
        check_appium: true
      - id: report
        name: Generate report
        command: npm run report:generate
        repo: mobile_tests
''';

void main() {
  late Directory root;
  late MachineProfile profile;
  late ManifestModel manifest;

  setUp(() {
    root = Directory.systemTemp.createTempSync('qa_step_runner');
    Directory('${root.path}/web_repo').createSync();
    Directory('${root.path}/tests_repo').createSync();
    File('${root.path}/tests_repo/.env.dev').writeAsStringSync(
      '# comment\nIOS_SIMULATOR_UDID="ABC-123"\nEMPTY=\n',
    );
    profile = MachineProfile(projectsRoot: root.path);
    manifest = ManifestModel.fromYaml(loadYaml(_yaml) as Map);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<PipelineResult> runRecipe(
    FakeGateway gateway, {
    String recipeId = 'web',
    bool sync = true,
    bool build = true,
    IosBuildTarget iosTarget = IosBuildTarget.simulator,
    bool appiumUp = true,
    String specFlags = '',
  }) {
    return StepRunner(gateway: gateway, isAppiumRunning: () async => appiumUp)
        .run(
      recipe: manifest.recipes[recipeId]!,
      profile: profile,
      manifest: manifest,
      syncEnabled: sync,
      buildEnabled: build,
      iosTarget: iosTarget,
      specFlags: specFlags,
      onLog: (_) {},
      onStepStart: (_, _, _) {},
      onStepEnd: (_) {},
    );
  }

  test('runs every step in order and detaches the report step', () async {
    final gateway = FakeGateway();
    final result = await runRecipe(gateway);

    expect(result.status, RunStatus.done);
    expect(gateway.streamed,
        ['git pull origin develop', 'yarn install', 'yarn test']);
    expect(gateway.detached, ['yarn allure:open']);
    expect(result.steps.map((s) => s.outcome),
        everyElement(StepOutcome.success));
  });

  test('sync off skips the sync step without running it', () async {
    final gateway = FakeGateway();
    final result = await runRecipe(gateway, sync: false);

    expect(result.status, RunStatus.done);
    expect(gateway.streamed, isNot(contains('git pull origin develop')));
    expect(result.steps.first.outcome, StepOutcome.skipped);
    // A skipped step is reported, not dropped.
    expect(result.steps.length, 4);
  });

  test('a non-zero exit aborts the rest of the pipeline', () async {
    final gateway = FakeGateway(exitCodes: {'yarn install': 1});
    final result = await runRecipe(gateway);

    expect(result.status, RunStatus.failed);
    expect(gateway.streamed, isNot(contains('yarn test')));
    expect(gateway.detached, isEmpty, reason: 'report must not open on failure');
    expect(result.failedStep?.step.id, 'install');
    expect(result.failedStep?.exitCode, 1);
  });

  test('a missing repo directory fails the step instead of throwing', () async {
    Directory('${root.path}/web_repo').deleteSync();
    final gateway = FakeGateway();
    final result = await runRecipe(gateway);

    expect(result.status, RunStatus.failed);
    expect(gateway.streamed, isEmpty);
    expect(result.failedStep?.note, contains('Directory not found'));
  });

  test('env_file vars are injected into that step only', () async {
    final gateway = FakeGateway();
    await runRecipe(gateway, recipeId: 'ios');

    const installCmd = 'xcrun simctl install \$IOS_SIMULATOR_UDID app';
    expect(gateway.envFor[installCmd]?['IOS_SIMULATOR_UDID'], 'ABC-123');
    // The build step declares no env_file, so it must inherit a bare env.
    expect(gateway.envFor['flutter build ios --simulator'], isNull);
  });

  test('iOS target filter drops the other target\'s steps', () async {
    final simGateway = FakeGateway();
    await runRecipe(simGateway,
        recipeId: 'ios', iosTarget: IosBuildTarget.simulator);
    expect(simGateway.streamed, contains('flutter build ios --simulator'));
    expect(simGateway.streamed, isNot(contains('flutter build ios')));

    final devGateway = FakeGateway();
    await runRecipe(devGateway,
        recipeId: 'ios', iosTarget: IosBuildTarget.device);
    expect(devGateway.streamed, contains('flutter build ios'));
    expect(devGateway.streamed,
        isNot(contains('flutter build ios --simulator')));
  });

  test('build off skips build steps but still runs untagged ones', () async {
    final gateway = FakeGateway();
    final result = await runRecipe(gateway, recipeId: 'ios', build: false);

    expect(result.status, RunStatus.done);
    expect(gateway.streamed, isNot(contains('flutter build ios --simulator')));
    // install_sim has no skip flag — it must still run.
    expect(gateway.streamed.length, 1);
  });

  test('check_appium aborts before the command when Appium is down',
      () async {
    final gateway = FakeGateway();
    final result =
        await runRecipe(gateway, recipeId: 'android', appiumUp: false);

    expect(result.status, RunStatus.failed);
    expect(result.failedStep?.step.id, 'test_android');
    expect(result.failedStep?.note, contains('Appium'));
    // The whole point: never actually run the WDIO command against a dead server.
    expect(gateway.streamed, isNot(contains('npm run test:android:dev')));
    expect(gateway.streamed, isNot(contains('npm run report:generate')));
  });

  test('check_appium lets the step through when Appium is up', () async {
    final gateway = FakeGateway();
    final result =
        await runRecipe(gateway, recipeId: 'android', appiumUp: true);

    expect(result.status, RunStatus.done);
    expect(gateway.streamed, contains('npm run test:android:dev'));
  });

  test("reportStep resolves the recipe's detach step (Phase 5 reopen)", () {
    final web = manifest.recipes['web']!;
    expect(web.reportStep?.id, 'report');
    expect(web.reportStep?.command, 'yarn allure:open');
    expect(web.reportStep?.repo, 'web');

    // The android fixture has no detach step — reportStep must be null,
    // not throw, so "Reopen last report" simply doesn't show for it.
    expect(manifest.recipes['android']!.reportStep, isNull);
  });

  test('blank spec flags run the normal command, untouched', () async {
    final gateway = FakeGateway();
    await runRecipe(gateway, specFlags: '   '); // whitespace-only counts as blank

    expect(gateway.streamed, contains('yarn test'));
    expect(gateway.streamed, isNot(contains(startsWith('playwright test'))));
  });

  test('non-blank spec flags substitute into spec_command, not command',
      () async {
    final gateway = FakeGateway();
    await runRecipe(gateway, specFlags: '--grep "@smoke"');

    expect(gateway.streamed, contains('playwright test --grep "@smoke"'));
    expect(gateway.streamed, isNot(contains('yarn test')));
    // Every other step is untouched by the spec filter.
    expect(gateway.streamed, contains('yarn install'));
  });

  test('a step with no spec_command ignores the spec field entirely',
      () async {
    final gateway = FakeGateway();
    await runRecipe(gateway, specFlags: '--grep "@smoke"');

    // "install" has no spec_command — must run verbatim, not get the filter
    // appended or substituted onto it.
    expect(gateway.streamed, contains('yarn install'));
    expect(gateway.streamed, isNot(contains('yarn install --grep "@smoke"')));
  });
}
