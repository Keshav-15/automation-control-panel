// Parsed representation of manifests/centurion.yaml (and future product YAMLs).
//
// The YAML is the source of truth; these classes are plain Dart — no
// code-gen needed since the schema is simple and known at compile time.

// ── iOS build target ─────────────────────────────────────────────────────────

/// Whether the iOS recipe targets a simulator or a real device.
/// Chosen by the user at runtime via a toggle in the recipe card.
enum IosBuildTarget {
  simulator,
  device;

  String get label {
    return switch (this) {
      IosBuildTarget.simulator => 'Simulator',
      IosBuildTarget.device => 'Real Device',
    };
  }

  String get icon {
    return switch (this) {
      IosBuildTarget.simulator => '🖥️',
      IosBuildTarget.device => '📱',
    };
  }
}

// ── Manifest ─────────────────────────────────────────────────────────────────

class ManifestModel {
  final String product;
  final String environment;
  final Map<String, RepoConfig> repos;
  final Map<String, RecipeConfig> recipes;

  const ManifestModel({
    required this.product,
    required this.environment,
    required this.repos,
    required this.recipes,
  });

  factory ManifestModel.fromYaml(Map<dynamic, dynamic> yaml) {
    final rawRepos = yaml['repos'] as Map? ?? {};
    final rawRecipes = yaml['recipes'] as Map? ?? {};

    return ManifestModel(
      product: yaml['product'] as String? ?? '',
      environment: yaml['environment'] as String? ?? 'dev',
      repos: rawRepos.map(
        (key, value) => MapEntry(
          key as String,
          RepoConfig.fromYaml(value as Map),
        ),
      ),
      recipes: rawRecipes.map(
        (key, value) {
          final id = key as String;
          return MapEntry(id, RecipeConfig.fromYaml(id, value as Map));
        },
      ),
    );
  }
}

class RepoConfig {
  /// Relative path inside the Projects root (e.g. "crichq-app-flutter").
  final String relPath;
  final String branch;

  const RepoConfig({required this.relPath, required this.branch});

  factory RepoConfig.fromYaml(Map yaml) {
    return RepoConfig(
      relPath: yaml['rel_path'] as String? ?? '',
      branch: yaml['branch'] as String? ?? 'develop',
    );
  }
}

class RecipeConfig {
  final String id;
  final String name;

  final String surface;

  /// This recipe's device type — `"ios"` | `"android"` | `"web"` | `null` —
  /// carried over from [SurfaceConfig.platformType] so a custom-named
  /// surface (e.g. `android_stage`) still resolves correctly here instead of
  /// guessing from the raw [surface] id string.
  final String? platformType;

  final List<StepConfig> steps;

  const RecipeConfig({
    required this.id,
    required this.name,
    required this.surface,
    this.platformType,
    required this.steps,
  });

  bool get isIos => platformType == 'ios';
  bool get isAndroid => platformType == 'android';
  bool get isWeb => platformType == 'web';
  bool get isMobile => isIos || isAndroid;

  /// The step that opens this recipe's Allure report (`detach: true` in the
  /// manifest — e.g. `yarn allure:open`, `npm run report:open`). Re-running
  /// this exact command is how "Reopen last report" works — no separate
  /// concept of a report file path needed, since `allure open` already
  /// handles serving the static report correctly (a bare `open index.html`
  /// would hit CORS loading its data).
  StepConfig? get reportStep => steps.where((s) => s.detach).lastOrNull;

  /// Returns steps filtered for a given [IosBuildTarget].
  /// Steps with no target tag always pass through.
  /// Only meaningful for iOS recipes — for web/android returns all steps.
  List<StepConfig> stepsFor({IosBuildTarget iosTarget = IosBuildTarget.simulator}) {
    if (!isIos) return steps;
    return steps.where((s) {
      if (s.target == null) return true;
      return switch (iosTarget) {
        IosBuildTarget.simulator => s.target == 'simulator',
        IosBuildTarget.device => s.target == 'device',
      };
    }).toList(growable: false);
  }

  factory RecipeConfig.fromYaml(String id, Map yaml) {
    final rawSteps = yaml['steps'] as List? ?? [];
    final surface = yaml['surface'] as String? ?? id;
    return RecipeConfig(
      id: id,
      name: yaml['name'] as String? ?? id,
      surface: surface,
      // The static manifests/centurion.yaml world still has surface id ==
      // platform (no custom surfaces there), so fall back to the id itself.
      platformType: yaml['platformType'] as String? ??
          (const ['ios', 'android', 'web'].contains(surface) ? surface : null),
      steps: rawSteps
          .map((s) => StepConfig.fromYaml(s as Map))
          .toList(growable: false),
    );
  }
}

class StepConfig {
  final String id;
  final String name;
  final String command;

  /// Key into [ManifestModel.repos] — resolves to the absolute cwd for this step.
  final String repo;

  /// Seconds before the step is killed (null = no timeout).
  final int? timeoutSeconds;

  /// Skip this step when the user has Sync toggled off.
  final bool skipIfNoSync;

  /// Skip this step when the user has Build+Install toggled off.
  final bool skipIfNoBuild;

  /// Start detached (fire-and-forget). Used for `allure open` so it doesn't block the pipeline.
  final bool detach;

  /// Path to a `.env` file **relative to the Projects root** whose vars the engine
  /// merges into this step's shell environment before running the command.
  /// e.g. `"centurion-app-automation-tests-ts/.env.dev"` supplies IOS_SIMULATOR_UDID,
  /// IOS_DEVICE_ID, etc. to build/install/launch steps.
  final String? envFile;

  /// iOS-only target filter: `"simulator"` | `"device"` | `null` (runs for both).
  /// Step runner skips this step when the active [IosBuildTarget] doesn't match.
  final String? target;

  /// Re-check `http://localhost:4723/status` immediately before this step runs;
  /// abort the pipeline if Appium isn't there. Doctor already checked this
  /// before Run was enabled, but a WDIO step can be minutes into Build+Install
  /// by the time it starts — Appium may have been quit in the meantime.
  final bool checkAppium;

  /// Alternate command template used only when the user typed something into
  /// this recipe's spec/flags field (Phase 6). `{flags}` is replaced with
  /// that text verbatim — the user is responsible for quoting it, same as if
  /// they'd typed it into a terminal themselves.
  ///
  /// Needed wherever [command] is an opaque multi-command chain (e.g.
  /// `yarn test`) that appending `-- --grep foo` at the end can't safely
  /// reach — see the comment on `test_web` in centurion.yaml. Null means this
  /// step doesn't support a spec filter (most steps — only the actual test
  /// step per recipe declares this).
  final String? specCommand;

  const StepConfig({
    required this.id,
    required this.name,
    required this.command,
    required this.repo,
    this.timeoutSeconds,
    this.skipIfNoSync = false,
    this.skipIfNoBuild = false,
    this.detach = false,
    this.envFile,
    this.target,
    this.checkAppium = false,
    this.specCommand,
  });

  factory StepConfig.fromYaml(Map yaml) {
    return StepConfig(
      id: yaml['id'] as String? ?? '',
      name: yaml['name'] as String? ?? '',
      command: yaml['command'] as String? ?? '',
      repo: yaml['repo'] as String? ?? '',
      timeoutSeconds: yaml['timeout_seconds'] as int?,
      skipIfNoSync: yaml['skip_if_no_sync'] as bool? ?? false,
      skipIfNoBuild: yaml['skip_if_no_build'] as bool? ?? false,
      detach: yaml['detach'] as bool? ?? false,
      envFile: yaml['env_file'] as String?,
      target: yaml['target'] as String?,
      checkAppium: yaml['check_appium'] as bool? ?? false,
      specCommand: yaml['spec_command'] as String?,
    );
  }
}
