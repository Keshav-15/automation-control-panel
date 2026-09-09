import 'dart:async';
import 'dart:io';

import 'package:flutter_boilerplate/src/base/dependencyinjection/locator.dart';
import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/models/qa/machine_profile_model.dart';
import 'package:flutter_boilerplate/src/models/qa/manifest_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';
import 'package:flutter_boilerplate/src/base/utils/preference_utils.dart' as prefs;

/// The whole point of the registry refactor: two recipes running at once
/// must be tracked, logged, and cancellable independently — not just two
/// Dart objects that happen to coexist, but genuinely separate real
/// subprocess trees under the hood.
// Deliberately different sleep durations per recipe, not just different repo
// roles — `pgrep -f "sleep 60"` matches BOTH the actual `sleep` process AND
// its own parent shell (whose argv literally contains the substring), so a
// shared marker double-counts in a way that's easy to misread as "the wrong
// process survived." Distinct markers keep the assertions unambiguous.
const _yaml = '''
product: test
environment: dev
repos:
  web:
    rel_path: web_repo
    branch: develop
recipes:
  web:
    name: Web probe
    surface: web
    steps:
      - id: web_step
        name: Web step
        command: sleep 55555 & wait
        repo: web
  android:
    name: Android probe
    surface: android
    steps:
      - id: android_step
        name: Android step
        command: sleep 66666 & wait
        repo: web
''';

Future<int> _countProcs(String pattern) async {
  final r = await Process.run('/bin/sh', ['-c', 'pgrep -f "$pattern" | wc -l']);
  return int.parse((r.stdout as String).trim());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late MachineProfile profile;
  late ManifestModel manifest;
  late RunProvider run;

  setUp(() async {
    prefs.dispose();
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    if (!locator.isRegistered<ProcessGateway>()) {
      locator.registerSingleton<ProcessGateway>(ProcessGateway());
    }
    root = Directory.systemTemp.createTempSync('qa_registry_check');
    Directory('${root.path}/web_repo').createSync();
    profile = MachineProfile(projectsRoot: root.path);
    manifest = ManifestModel.fromYaml(loadYaml(_yaml) as Map);
    run = RunProvider();
  });

  tearDown(() async {
    await run.cancelAndWait();
    run.dispose();
    root.deleteSync(recursive: true);
  });

  Future<void> waitForBothRunning() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while ((await _countProcs('sleep 55555') < 1 ||
            await _countProcs('sleep 66666') < 1) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  test('two recipes running at once both appear in the registry, tracked independently',
      () async {
    unawaited(run.start(
      recipe: manifest.recipes['web']!,
      profile: profile,
      manifest: manifest,
      syncEnabled: true,
      buildEnabled: true,
      deviceUdid: 'device-A',
    ));
    unawaited(run.start(
      recipe: manifest.recipes['android']!,
      profile: profile,
      manifest: manifest,
      syncEnabled: true,
      buildEnabled: true,
      deviceUdid: 'device-B',
    ));

    await waitForBothRunning();

    expect(run.activeRuns, hasLength(2));
    expect(run.isRunningFor('web'), isTrue);
    expect(run.isRunningFor('android'), isTrue);
    expect(run.isDeviceBusy('device-A'), isTrue);
    expect(run.isDeviceBusy('device-B'), isTrue);
    expect(run.isDeviceBusy('device-C'), isFalse);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('cancelling one run by id leaves the other running untouched',
      () async {
    unawaited(run.start(
      recipe: manifest.recipes['web']!,
      profile: profile,
      manifest: manifest,
      syncEnabled: true,
      buildEnabled: true,
    ));
    unawaited(run.start(
      recipe: manifest.recipes['android']!,
      profile: profile,
      manifest: manifest,
      syncEnabled: true,
      buildEnabled: true,
    ));

    await waitForBothRunning();

    final webRunId = run.runIdFor('web');
    expect(webRunId, isNotNull);
    run.cancel(webRunId);

    // Give the cancelled pipeline time to actually finish.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (run.isRunningFor('web') && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(run.isRunningFor('web'), isFalse,
        reason: 'the cancelled run should have stopped');
    expect(run.isRunningFor('android'), isTrue,
        reason: 'the other run must be unaffected by cancelling the first');

    // web's process tree must be gone; android's must survive untouched.
    // The killed process can take a moment to actually leave the process
    // table even after our Dart-side state says "done" — poll rather than
    // asserting the instant isRunningFor flips.
    final procDeadline = DateTime.now().add(const Duration(seconds: 5));
    var webProcs = await _countProcs('sleep 55555');
    while (webProcs > 0 && DateTime.now().isBefore(procDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      webProcs = await _countProcs('sleep 55555');
    }
    expect(webProcs, 0, reason: "web's sleep process should have been killed");
    expect(await _countProcs('sleep 66666'), greaterThan(0),
        reason: "android's sleep process must still be alive");
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('each finished run records its own history entry', () async {
    unawaited(run.start(
      recipe: manifest.recipes['web']!,
      profile: profile,
      manifest: manifest,
      syncEnabled: true,
      buildEnabled: true,
    ));
    unawaited(run.start(
      recipe: manifest.recipes['android']!,
      profile: profile,
      manifest: manifest,
      syncEnabled: true,
      buildEnabled: true,
    ));
    await waitForBothRunning();

    await run.cancelAndWait();

    expect(run.history.where((r) => r.recipeId == 'web'), hasLength(1));
    expect(run.history.where((r) => r.recipeId == 'android'), hasLength(1));
    expect(run.history.map((r) => r.status), everyElement('cancelled'));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('reset() only dismisses a finished entry, never one still running',
      () async {
    unawaited(run.start(
      recipe: manifest.recipes['web']!,
      profile: profile,
      manifest: manifest,
      syncEnabled: true,
      buildEnabled: true,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final runId = run.runIdFor('web');
    run.reset(runId); // should be a no-op — still running
    expect(run.activeRuns, hasLength(1),
        reason: 'reset() must not remove a still-running entry');

    run.cancel(runId);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (run.isRunningFor('web') && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    run.reset(runId);
    expect(run.activeRuns, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
