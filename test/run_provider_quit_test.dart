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

// Simulates AppLifecycleObserver.didRequestAppExit firing mid-run: a long
// step is in flight when quit is requested. cancelAndWait() must kill the
// whole process tree AND the sleep guard before returning, and still record
// the run to history.
const _yaml = '''
product: test
environment: dev
repos:
  web:
    rel_path: web_repo
    branch: develop
recipes:
  probe:
    name: Quit probe
    surface: web
    steps:
      - id: long_step
        name: Long step
        command: sleep 300 & sleep 300 & wait
        repo: web
''';

Future<int> _countProcs(String pattern) async {
  final r = await Process.run('/bin/sh', ['-c', 'pgrep -f "$pattern" | wc -l']);
  return int.parse((r.stdout as String).trim());
}

Future<int> _countCaffeinate() async {
  final r = await Process.run('/bin/sh', ['-c', 'pgrep -x caffeinate | wc -l']);
  return int.parse((r.stdout as String).trim());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cancelAndWait kills orphans, releases the sleep guard, and still records history',
      () async {
    prefs.dispose();
    SharedPreferences.setMockInitialValues({});
    await prefs.init();
    // RunProvider.start resolves its StepRunner's gateway via the locator
    // (so MachineProfile.extraPathDirs reaches it) — register the plain
    // singleton this test actually needs rather than pulling in setupLocator's
    // unrelated boilerplate (ApiService, AuthController, ...).
    if (!locator.isRegistered<ProcessGateway>()) {
      locator.registerSingleton<ProcessGateway>(ProcessGateway());
    }

    final root = Directory.systemTemp.createTempSync('qa_quit_check');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/web_repo').createSync();

    final profile = MachineProfile(projectsRoot: root.path);
    final manifest = ManifestModel.fromYaml(loadYaml(_yaml) as Map);
    final run = RunProvider();
    addTearDown(run.dispose);

    // Fire-and-forget, mirroring HomeScreen's real call site.
    unawaited(run.start(
      recipe: manifest.recipes['probe']!,
      profile: profile,
      manifest: manifest,
      syncEnabled: true,
      buildEnabled: true,
    ));

    // Let the pipeline actually spawn its children and the sleep guard.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (await _countProcs('sleep 300') < 2 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(await _countProcs('sleep 300'), greaterThanOrEqualTo(2),
        reason: 'children never started');
    expect(await _countCaffeinate(), 1, reason: 'sleep guard never started');
    expect(run.isRunning, isTrue);

    // Simulate Cmd+Q.
    await run.cancelAndWait();

    expect(await _countProcs('sleep 300'), 0,
        reason: 'orphaned sleep processes survived quit');
    expect(await _countCaffeinate(), 0, reason: 'caffeinate survived quit');
    expect(run.isRunning, isFalse);

    expect(run.history, isNotEmpty, reason: 'quit should still record history');
    final record = run.history.first;
    expect(record.status, 'cancelled');
    expect(record.logPath, isNotNull);
    expect(File(record.logPath!).existsSync(), isTrue,
        reason: 'log file not written');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
