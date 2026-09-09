import 'package:flutter_boilerplate/src/base/qa/process_gateway.dart';
import 'package:flutter_boilerplate/src/base/qa/report_archiver.dart';
import 'package:flutter_boilerplate/src/models/qa/device_model.dart';
import 'package:flutter_boilerplate/src/models/qa/manifest_model.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_boilerplate/src/providers/qa/run_provider.dart';

/// Turns "run this script" into an actual pipeline and hands it to
/// [RunProvider] — the glue between the Scripts screen's Run button and the
/// existing [StepRunner]/[RunProvider] execution machinery (reused as-is,
/// not reimplemented). Whether to pull/build first is no longer a per-click
/// choice (there's no more Run/Pull&Run/Build&Run menu) — it's read
/// straight off [SurfaceConfig.runPull]/[SurfaceConfig.runBuild], the same
/// "plain switch, maintained on the surface" shape as
/// [SurfaceConfig.runPrerequisites].
class RunDispatcher {
  RunDispatcher({ProcessGateway? gateway}) : _gateway = gateway ?? ProcessGateway();
  final ProcessGateway _gateway;

  /// Every placeholder a command's text (or `envFile` path) can use — kept
  /// in one place so the Command Edit screen can show the exact same list
  /// to whoever is authoring a command. `{branch}`/`{bundleId}` resolve per
  /// *command* (via its `repoRole`) and per *surface* (via
  /// [SurfaceConfig.appId]) respectively — see [_stepFor].
  static const Map<String, String> placeholderDocs = {
    '{environment}': "The surface's environment (e.g. dev, stage) — see the surface's Environment field.",
    '{udid}': 'The udid of the device/simulator picked at Run time.',
    '{script}': 'The path of the script picked at Run time (Scripts screen).',
    '{branch}': "This command's repo's expected git branch — see the surface card's branch chip.",
    '{bundleId}': "This surface's Android applicationId / iOS bundle id — see the surface's App ID section.",
  };

  /// Reuses the existing `{flags}`-style single-brace substitution
  /// convention (see `StepConfig.specCommand`) rather than inventing a new
  /// placeholder syntax.
  static String substitute(
    String command, {
    required String environment,
    String? udid,
    String? script,
    String? branch,
    String? bundleId,
  }) {
    var result = command.replaceAll('{environment}', environment);
    if (udid != null) result = result.replaceAll('{udid}', udid);
    if (script != null) result = result.replaceAll('{script}', script);
    if (branch != null) result = result.replaceAll('{branch}', branch);
    if (bundleId != null) result = result.replaceAll('{bundleId}', bundleId);
    return result;
  }

  /// This surface's installed-app id for whichever platform it actually is
  /// — a command doesn't need to pick android vs. ios itself, since a given
  /// surface is always exactly one platform.
  static String? _bundleIdFor(SurfaceConfig surface) {
    if (surface.isAndroid) return surface.appId?.androidApplicationId;
    if (surface.isIos) return surface.appId?.iosBundleId;
    return null;
  }

  /// Builds a [StepConfig] from [cmd] with every placeholder in
  /// [placeholderDocs] substituted into *both* its command text and its
  /// `envFile` path — [CommandConfig.toStepConfig] already carries every
  /// other tag through (timeout, skipIfNoSync/Build, detach, checkAppium,
  /// target), so this is the one place that has to add substitution on top,
  /// and every step (prerequisite, build/install, the run step, the report
  /// step) goes through it — not just the run step, which is what silently
  /// dropped checkAppium/envFile for it before.
  static StepConfig _stepFor(
    CommandConfig cmd, {
    required ProjectConfig project,
    required SurfaceConfig surface,
    required String environmentId,
    String? udid,
    String? script,
    String? idOverride,
    String? nameOverride,
  }) {
    final step = cmd.toStepConfig();
    final branch = project.repos[cmd.repoRole]?.branch;
    final bundleId = _bundleIdFor(surface);
    return StepConfig(
      id: idOverride ?? step.id,
      name: nameOverride ?? step.name,
      command: substitute(step.command,
          environment: environmentId,
          udid: udid,
          script: script,
          branch: branch,
          bundleId: bundleId),
      repo: step.repo,
      timeoutSeconds: step.timeoutSeconds,
      skipIfNoSync: step.skipIfNoSync,
      skipIfNoBuild: step.skipIfNoBuild,
      detach: step.detach,
      envFile: step.envFile == null
          ? null
          : substitute(step.envFile!,
              environment: environmentId, branch: branch, bundleId: bundleId),
      target: step.target,
      checkAppium: step.checkAppium,
      specCommand: step.specCommand,
    );
  }

  static String? _platformKey(DevicePlatform? p) =>
      p == null ? null : (p == DevicePlatform.android ? 'android' : 'ios');

  static String? _targetKey(DeviceKind? k) =>
      k == null ? null : (k == DeviceKind.physical ? 'device' : 'simulator');

  /// [RunProvider.start]'s `iosTarget` re-filters a recipe's steps by
  /// [CommandConfig.target] a *second* time (only for the legacy `ios`
  /// surface — see [RecipeConfig.stepsFor]), on top of the filtering
  /// [planSteps] already did via [ProjectConfig.testCommandFor] et al. Left
  /// at its default (simulator) that second pass would silently drop every
  /// device-tagged step whenever the user actually picked a physical
  /// device — so the picked [DeviceKind] has to be threaded through here too.
  static IosBuildTarget _iosBuildTarget(DeviceKind? k) =>
      k == DeviceKind.physical ? IosBuildTarget.device : IosBuildTarget.simulator;

  /// Pulls [branch] in [repoAbsPath] and reports whether HEAD actually
  /// moved — the real, precise "were there incoming changes" check (see
  /// docs/RUN_EXPERIENCE_REDESIGN.md §6), not a guess.
  Future<bool> pullAndCheckForChanges({
    required String repoAbsPath,
    required String branch,
  }) async {
    final before = await _gateway.exec('git rev-parse HEAD',
        workingDirectory: repoAbsPath, ignoreExitCode: true);
    await _gateway.exec('git pull origin $branch', workingDirectory: repoAbsPath);
    final after = await _gateway.exec('git rev-parse HEAD',
        workingDirectory: repoAbsPath, ignoreExitCode: true);
    // An unreadable "before" (e.g. a brand-new repo) can't prove nothing
    // changed — treat that as "changed" too, so it rebuilds rather than
    // silently skipping a first build.
    return before.trim().isEmpty || before.trim() != after.trim();
  }

  /// Assembles the step list for one dispatch — pure decision logic,
  /// deliberately kept separate from actually starting it ([dispatch]) so
  /// the pull/build branching is testable without a real device or
  /// [RunProvider]. Returns null if no `test`-tagged pool command matches
  /// this target (the UI shows what's missing before this is ever
  /// reachable — see [ProjectConfig.testCommandFor]). Environment is no
  /// longer a caller-supplied input — it's read straight off [surface]
  /// ([SurfaceConfig.environmentId]), since a surface now already is one
  /// environment. Whether to pull/build is likewise no longer caller-chosen
  /// — [SurfaceConfig.runPull]/[SurfaceConfig.runBuild] are two independent
  /// plain switches (no "skip build if already installed/up to date"
  /// guesswork any more — see [SurfaceConfig.runBuild]'s doc).
  Future<List<StepConfig>?> planSteps({
    required ProjectConfig project,
    required SurfaceConfig surface,
    required ScriptEntry script,
    DevicePlatform? platform,
    DeviceKind? deviceKind,
    String? deviceUdid,
  }) async {
    final environmentId = surface.environmentId ?? '';
    final targetKey = _targetKey(deviceKind);
    final runnerCmd = project.testCommandFor(surface.id, target: targetKey);
    if (runnerCmd == null) return null;

    final steps = <StepConfig>[];

    // Prerequisites (git pull, flutter pub get, pod install, npm install,
    // ...) always run first, ahead of pull/build — see
    // docs/RUN_EXPERIENCE_REDESIGN.md §7. Resolved by filtering the pool for
    // the `git`/`prerequisite` tags, same convention as
    // [ProjectConfig.testCommandFor] et al. — no more a separately-managed
    // id list to keep in sync with those tags.
    if (surface.runPrerequisites) {
      final prereqs = project.prerequisiteCommandsFor(surface.id);
      steps.addAll(prereqs.map((c) => _stepFor(c,
          project: project,
          surface: surface,
          environmentId: environmentId,
          udid: deviceUdid,
          script: script.path)));
    }

    if (surface.runPull) {
      // The buildable app repo — mobile_ui for mobile, the web repo for
      // web. (mobile_test isn't pulled here — rebuilding only matters for
      // the repo that actually produces an installable artifact.) Purely
      // informational now — it no longer gates whether build runs, that's
      // [SurfaceConfig.runBuild]'s own independent switch.
      final repoRole = surface.isWeb ? 'web' : 'mobile_ui';
      final repo = project.repos[repoRole];
      if (repo != null) {
        final changed = await pullAndCheckForChanges(
          repoAbsPath: repo.absPath(project.projectsRoot),
          branch: repo.branch,
        );
        steps.add(StepConfig(
          id: 'pull_${surface.id}',
          name: 'Pull ${repo.branch}',
          command: 'echo "Pulled ${repo.branch} — '
              '${changed ? 'incoming changes' : 'already up to date'}"',
          repo: repoRole,
        ));
      }
    }

    if (surface.runBuild) {
      final buildCmds =
          project.buildInstallCommandsFor(surface.id, target: targetKey);
      steps.addAll(buildCmds.map((c) => _stepFor(c,
          project: project,
          surface: surface,
          environmentId: environmentId,
          udid: deviceUdid,
          script: script.path)));
    }

    steps.add(_stepFor(runnerCmd,
        project: project,
        surface: surface,
        environmentId: environmentId,
        udid: deviceUdid,
        script: script.path,
        idOverride: 'run_${script.id}',
        nameOverride: 'Run ${script.displayName}'));

    // Report command (§8) — appended last, once the surface has an output
    // path configured and a matching report command can be resolved.
    // Archiving the actual report folder happens after this pipeline
    // finishes (see [dispatch]); this step's own job is just to
    // generate/open it, same as before.
    if (surface.reportOutputRelPath != null) {
      final reportCmd = project.reportCommandFor(surface.id);
      if (reportCmd != null) {
        steps.add(_stepFor(reportCmd,
            project: project,
            surface: surface,
            environmentId: environmentId,
            udid: deviceUdid,
            script: script.path,
            idOverride: 'report_${surface.id}',
            nameOverride: 'Report — ${reportCmd.name}'));
      }
    }

    return steps;
  }

  /// Plans and starts the run via [runProvider] — returns the new run's id,
  /// or null if the runner command isn't configured for this combo.
  ///
  /// When the surface has a report command + output path configured (§8),
  /// [RunProvider.start] only resolves once that step has run too (it's the
  /// pipeline's last step — see [planSteps]), so archiving the report here,
  /// right after `await`, sees the report tool's finished output. Kept as a
  /// plain follow-up call rather than a callback threaded through
  /// [RunProvider] — the smaller diff, since [RunProvider] doesn't need to
  /// know anything about reports.
  Future<String?> dispatch({
    required RunProvider runProvider,
    required ProjectConfig project,
    required SurfaceConfig surface,
    required ScriptEntry script,
    DevicePlatform? platform,
    DeviceKind? deviceKind,
    String? deviceUdid,
    ReportArchiver? reportArchiver,
  }) async {
    final environmentId = surface.environmentId ?? '';
    final steps = await planSteps(
      project: project,
      surface: surface,
      script: script,
      platform: platform,
      deviceKind: deviceKind,
      deviceUdid: deviceUdid,
    );
    if (steps == null) return null;

    final runId = await runProvider.start(
      recipe: RecipeConfig(
        id: surface.id,
        name: '${surface.name} — ${script.displayName}',
        surface: surface.id,
        platformType: surface.platformType,
        steps: steps,
      ),
      profile: project.toProfile(),
      manifest: project.toManifestModel(),
      syncEnabled: true,
      buildEnabled: true,
      // Only actually filters anything for the legacy `ios` surface (see
      // _iosBuildTarget's doc) — everywhere else it's a no-op.
      iosTarget: _iosBuildTarget(deviceKind),
      deviceUdid: deviceUdid,
      // Re-run/history metadata (docs/RUN_EXPERIENCE_REDESIGN.md §9) — this
      // is the one call site that actually knows all of it.
      projectId: project.id,
      scriptDisplayName: script.displayName,
      environmentId: environmentId,
      platform: _platformKey(platform),
      deviceKind: _targetKey(deviceKind),
    );

    if (surface.reportOutputRelPath != null) {
      final reportCmd = project.reportCommandFor(surface.id);
      if (reportCmd != null) {
        await (reportArchiver ?? ReportArchiver()).archiveAfterRun(
          project: project,
          surface: surface,
          script: script,
          environmentId: environmentId,
          runId: runId,
          commandUsed: substitute(reportCmd.command,
              environment: environmentId,
              udid: deviceUdid,
              script: script.path,
              branch: project.repos[reportCmd.repoRole]?.branch,
              bundleId: _bundleIdFor(surface)),
          platform: platform,
          deviceUdid: deviceUdid,
        );
      }
    }

    return runId;
  }
}
