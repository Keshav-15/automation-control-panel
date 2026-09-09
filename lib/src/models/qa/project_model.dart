import 'dart:convert';
import 'dart:math';

import 'package:flutter_boilerplate/src/models/qa/machine_profile_model.dart';
import 'package:flutter_boilerplate/src/models/qa/manifest_model.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Generates a simple UUID-v4-like id without an external package.
String generateProjectId() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

// ── MobileAppId ───────────────────────────────────────────────────────────────

/// The Android applicationId / iOS bundle identifier for one surface — see
/// docs/RUN_EXPERIENCE_REDESIGN.md §3. One per [SurfaceConfig] (not a map any
/// more) since a surface now already *is* one environment — a dev/staging/
/// prod flavor is normally a distinct installable app, and that's exactly
/// the granularity a surface has become.
class MobileAppId {
  final String? androidApplicationId;
  final String? iosBundleId;

  const MobileAppId({this.androidApplicationId, this.iosBundleId});

  bool get isEmpty => androidApplicationId == null && iosBundleId == null;

  MobileAppId copyWith({
    String? androidApplicationId,
    String? iosBundleId,
    bool clearAndroid = false,
    bool clearIos = false,
  }) =>
      MobileAppId(
        androidApplicationId: clearAndroid
            ? null
            : (androidApplicationId ?? this.androidApplicationId),
        iosBundleId: clearIos ? null : (iosBundleId ?? this.iosBundleId),
      );

  Map<String, dynamic> toJson() => {
        if (androidApplicationId != null) 'android': androidApplicationId,
        if (iosBundleId != null) 'ios': iosBundleId,
      };

  factory MobileAppId.fromJson(Map<String, dynamic> json) => MobileAppId(
        androidApplicationId: json['android'] as String?,
        iosBundleId: json['ios'] as String?,
      );
}

// ── RepoEntry ─────────────────────────────────────────────────────────────────

/// One repository inside a project.
class RepoEntry {
  final String role;     // e.g. "web", "app", "mobile_tests"
  final String label;    // display name, e.g. "Web App"
  final String relPath;  // folder under projectsRoot, e.g. "crichq-webapp-nextjs"
  final String branch;   // expected git branch, e.g. "develop"

  const RepoEntry({
    required this.role,
    required this.label,
    required this.relPath,
    this.branch = 'develop',
  });

  String absPath(String projectsRoot) => '$projectsRoot/$relPath';

  RepoEntry copyWith({
    String? role,
    String? label,
    String? relPath,
    String? branch,
  }) =>
      RepoEntry(
        role: role ?? this.role,
        label: label ?? this.label,
        relPath: relPath ?? this.relPath,
        branch: branch ?? this.branch,
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'label': label,
        'relPath': relPath,
        'branch': branch,
      };

  factory RepoEntry.fromJson(Map<String, dynamic> json) => RepoEntry(
        role: json['role'] as String,
        label: json['label'] as String,
        relPath: json['relPath'] as String,
        branch: json['branch'] as String? ?? 'develop',
      );

  RepoConfig toRepoConfig() => RepoConfig(relPath: relPath, branch: branch);
}

// ── CommandConfig ─────────────────────────────────────────────────────────────

/// One pipeline step stored in the project's global command pool.
class CommandConfig {
  final String id;
  final String name;
  final String command;

  /// Key into [ProjectConfig.repos].
  final String repoRole;

  final int? timeoutSeconds;
  final bool skipIfNoSync;
  final bool skipIfNoBuild;
  final bool detach;
  final String? envFile;

  /// iOS-only target filter: `"simulator"` | `"device"` | `null` (both).
  /// The one dynamic-per-run axis left besides the script/device udid
  /// themselves — kept because it genuinely swaps in a different build/
  /// install/test command, unlike environment/platform (now static
  /// properties of which surface a command is assigned to).
  final String? target;

  final bool checkAppium;
  final String? specCommand;

  /// Position hint used for sorting / template ordering.
  final int order;

  /// Free-form labels — replaces the old fixed `category` enum plus the
  /// `platform`/`environment` filter fields. A command's *pipeline stage*
  /// (which command actually runs when) is just one of these tags —
  /// `"test"` / `"build"` / `"report"` / `"git"` / `"prerequisite"` — read by
  /// [ProjectConfig]'s resolvers ([ProjectConfig.testCommandFor] et al.); any
  /// other tag on the list (`"smoke"`, `"regression"`, ...) is purely
  /// descriptive, for search/filtering in the UI, with no effect on
  /// execution. Environment/platform aren't tags any more at all — they're
  /// static properties of the [SurfaceConfig] a command is assigned to.
  final List<String> tags;

  const CommandConfig({
    required this.id,
    required this.name,
    required this.command,
    required this.repoRole,
    this.timeoutSeconds,
    this.skipIfNoSync = false,
    this.skipIfNoBuild = false,
    this.detach = false,
    this.envFile,
    this.target,
    this.checkAppium = false,
    this.specCommand,
    required this.order,
    this.tags = const [],
  });

  bool hasTag(String tag) => tags.contains(tag);

  CommandConfig copyWith({
    String? id,
    String? name,
    String? command,
    String? repoRole,
    int? timeoutSeconds,
    bool? skipIfNoSync,
    bool? skipIfNoBuild,
    bool? detach,
    String? envFile,
    String? target,
    bool? checkAppium,
    String? specCommand,
    int? order,
    List<String>? tags,
    bool clearTimeout = false,
    bool clearEnvFile = false,
    bool clearTarget = false,
    bool clearSpecCommand = false,
  }) =>
      CommandConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        command: command ?? this.command,
        repoRole: repoRole ?? this.repoRole,
        timeoutSeconds: clearTimeout ? null : (timeoutSeconds ?? this.timeoutSeconds),
        skipIfNoSync: skipIfNoSync ?? this.skipIfNoSync,
        skipIfNoBuild: skipIfNoBuild ?? this.skipIfNoBuild,
        detach: detach ?? this.detach,
        envFile: clearEnvFile ? null : (envFile ?? this.envFile),
        target: clearTarget ? null : (target ?? this.target),
        checkAppium: checkAppium ?? this.checkAppium,
        specCommand: clearSpecCommand ? null : (specCommand ?? this.specCommand),
        order: order ?? this.order,
        tags: tags ?? this.tags,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'command': command,
        'repoRole': repoRole,
        if (timeoutSeconds != null) 'timeoutSeconds': timeoutSeconds,
        'skipIfNoSync': skipIfNoSync,
        'skipIfNoBuild': skipIfNoBuild,
        'detach': detach,
        if (envFile != null) 'envFile': envFile,
        if (target != null) 'target': target,
        'checkAppium': checkAppium,
        if (specCommand != null) 'specCommand': specCommand,
        'order': order,
        if (tags.isNotEmpty) 'tags': tags,
      };

  factory CommandConfig.fromJson(Map<String, dynamic> json) => CommandConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        command: json['command'] as String,
        repoRole: json['repoRole'] as String,
        timeoutSeconds: json['timeoutSeconds'] as int?,
        skipIfNoSync: json['skipIfNoSync'] as bool? ?? false,
        skipIfNoBuild: json['skipIfNoBuild'] as bool? ?? false,
        detach: json['detach'] as bool? ?? false,
        envFile: json['envFile'] as String?,
        target: json['target'] as String?,
        checkAppium: json['checkAppium'] as bool? ?? false,
        specCommand: json['specCommand'] as String?,
        order: json['order'] as int? ?? 0,
        tags: (json['tags'] as List? ?? []).cast<String>(),
      );

  StepConfig toStepConfig() => StepConfig(
        id: id,
        name: name,
        command: command,
        repo: repoRole,
        timeoutSeconds: timeoutSeconds,
        skipIfNoSync: skipIfNoSync,
        skipIfNoBuild: skipIfNoBuild,
        detach: detach,
        envFile: envFile,
        target: target,
        checkAppium: checkAppium,
        specCommand: specCommand,
      );

  factory CommandConfig.fromStepConfig(StepConfig step, {int order = 0}) =>
      CommandConfig(
        id: step.id,
        name: step.name,
        command: step.command,
        repoRole: step.repo,
        timeoutSeconds: step.timeoutSeconds,
        skipIfNoSync: step.skipIfNoSync,
        skipIfNoBuild: step.skipIfNoBuild,
        detach: step.detach,
        envFile: step.envFile,
        target: step.target,
        checkAppium: step.checkAppium,
        specCommand: step.specCommand,
        order: order,
      );
}

// ── ScriptEntry ───────────────────────────────────────────────────────────────

/// One leaf test script — a file path (mobile) or a `package.json` script
/// name (web). Distinct from [CommandConfig]: a script is *what* to run,
/// not a pipeline step. See docs/RUN_EXPERIENCE_REDESIGN.md §4.
class ScriptEntry {
  final String id;
  final String path;         // mobile: file path; web: package.json script name
  final String? customName;  // user-entered; falls back to the filename/script name
  final DateTime addedAt;

  /// Mirrors [ProjectConfig.pinnedAt] — pinned scripts sort to their own
  /// section above the rest on the Scripts screen.
  final DateTime? pinnedAt;

  const ScriptEntry({
    required this.id,
    required this.path,
    this.customName,
    required this.addedAt,
    this.pinnedAt,
  });

  bool get isPinned => pinnedAt != null;

  /// What to show in the UI — the user's own name if they gave one, else
  /// derived from [path] (the filename for a mobile file path; unchanged for
  /// a web package.json script name, which has no directory to strip).
  String get displayName {
    final custom = customName;
    if (custom != null && custom.trim().isNotEmpty) return custom;
    final slash = path.lastIndexOf('/');
    return slash == -1 ? path : path.substring(slash + 1);
  }

  ScriptEntry copyWith({
    String? id,
    String? path,
    String? customName,
    DateTime? addedAt,
    DateTime? pinnedAt,
    bool clearCustomName = false,
    bool clearPinnedAt = false,
  }) =>
      ScriptEntry(
        id: id ?? this.id,
        path: path ?? this.path,
        customName: clearCustomName ? null : (customName ?? this.customName),
        addedAt: addedAt ?? this.addedAt,
        pinnedAt: clearPinnedAt ? null : (pinnedAt ?? this.pinnedAt),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        if (customName != null) 'customName': customName,
        'addedAt': addedAt.toIso8601String(),
        if (pinnedAt != null) 'pinnedAt': pinnedAt!.toIso8601String(),
      };

  factory ScriptEntry.fromJson(Map<String, dynamic> json) => ScriptEntry(
        id: json['id'] as String,
        path: json['path'] as String,
        customName: json['customName'] as String?,
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ??
            DateTime.now(),
        pinnedAt: json['pinnedAt'] == null
            ? null
            : DateTime.tryParse(json['pinnedAt'] as String),
      );

  /// Merges [paths] into [existing], skipping any path already present
  /// (dedup is by path — a second import of the same folder/package.json
  /// adds nothing already there, and a batch with internal duplicates only
  /// adds the first occurrence). [added] is how many were actually new, for
  /// reporting back to the user.
  static ({List<ScriptEntry> scripts, int added}) mergeUnique(
    List<ScriptEntry> existing,
    Iterable<String> paths, {
    String? customName,
  }) {
    final seen = existing.map((s) => s.path).toSet();
    final additions = <ScriptEntry>[];
    for (final path in paths) {
      if (!seen.add(path)) continue;
      additions.add(ScriptEntry(
        id: generateProjectId(),
        path: path,
        customName: customName,
        addedAt: DateTime.now(),
      ));
    }
    return (scripts: [...existing, ...additions], added: additions.length);
  }
}

// ── SurfaceConfig ─────────────────────────────────────────────────────────────

/// A surface inside a project — now a custom, user-named env+platform combo
/// (e.g. "Android Dev", "Android Stage"), not one of a fixed `web`/`ios`/
/// `android` triplet. [platformType] carries the surface's actual "kind"
/// explicitly, decoupled from [id]/[name], so a custom id like
/// `android_stage` still resolves correctly everywhere a device-type check
/// used to look at the raw id.
///
/// Surfaces don't own commands — they reference them by id from
/// [ProjectConfig.commands]. This allows commands to be shared across
/// surfaces (e.g. the same `git pull` command reused by both an Android and
/// an iOS surface on the same repo) and managed from a single project-level
/// library.
///
/// **No more explicit runner-command/report-command id slots** — which
/// command actually runs the script (or the report) is *resolved by
/// filtering the pool* at dispatch time ([ProjectConfig.testCommandFor]/
/// [ProjectConfig.reportCommandFor]), by [CommandConfig.tags], not
/// pre-assigned to a slot here. Environment, unlike a command's tags, IS a
/// slot here ([environmentId]) — it's a static property of the surface, not
/// picked at Run time.
class SurfaceConfig {
  final String id;       // e.g. "android_dev" — auto-slugged, not hand-typed
  final String name;     // e.g. "Android Dev"
  final String icon;     // "🤖"

  /// This surface's device type — `"ios"` | `"android"` | `"web"` | `null`.
  /// The one fixed enum left; everything else about a surface (name, icon,
  /// environment) is free-form.
  final String? platformType;

  /// This surface's environment — free text (`"dev"`, `"stage"`, `"prod"`,
  /// or empty/null for a surface with no environment concept). Static now,
  /// substituted into a command's `{environment}` placeholder the same way
  /// it always was — just read from here instead of asked at Run time.
  final String? environmentId;

  /// This surface's installed-app identity (mobile only) — one flat id, not
  /// a per-environment map, since a surface now already *is* one
  /// environment. Used by the run dispatcher to skip a rebuild/install when
  /// the right app is already on the device.
  final MobileAppId? appId;

  /// Ordered list of [CommandConfig.id] values from [ProjectConfig.commands].
  /// The order here determines the pipeline execution order for this surface.
  final List<String> commandIds;

  /// Leaf test scripts for this surface — see [ScriptEntry].
  final List<ScriptEntry> scripts;

  /// When true, this surface's pool commands tagged `git`/`prerequisite` run
  /// first (in pool order) ahead of whichever Run/Pull&Run/Build&Run path is
  /// dispatched — e.g. `git pull`, `flutter pub get`, `pod install`, `npm
  /// install`. See [ProjectConfig.prerequisiteCommandsFor].
  final bool runPrerequisites;

  /// When true, pulls the surface's buildable repo (`mobile_ui` for mobile,
  /// `web` for web) at its configured branch before build/test — a plain,
  /// always-does-it toggle (same "no cleverness" shape as
  /// [runPrerequisites]/[runBuild]), not a per-run choice any more. Doesn't
  /// gate whether [runBuild] runs; that's now a fully independent switch.
  final bool runPull;

  /// When true, runs this surface's `build`-tagged pool commands before
  /// test — see [ProjectConfig.buildInstallCommandsFor]. A plain switch, not
  /// the old "only if not already installed" guesswork — turn it off once
  /// you know you don't need a fresh build, on when you do.
  final bool runBuild;

  /// Folder the report tool writes its output to, relative to the report
  /// command's own [CommandConfig.repoRole] repo (e.g. `allure-report`) —
  /// genuinely project-specific, so this can't be guessed; required before
  /// archiving can run.
  final String? reportOutputRelPath;

  const SurfaceConfig({
    required this.id,
    required this.name,
    required this.icon,
    this.platformType,
    this.environmentId,
    this.appId,
    this.commandIds = const [],
    this.scripts = const [],
    this.runPrerequisites = false,
    this.runPull = false,
    this.runBuild = false,
    this.reportOutputRelPath,
  });

  /// Auto-bootstrap surfaces created by [ProjectController.ensureAutoSurfaces]
  /// when a project's repos are configured but it has no surfaces yet — a
  /// starting point the user renames/retags (environment, icon) via Edit
  /// surface, not a fixed pair the app relies on by id.
  factory SurfaceConfig.autoWeb() => const SurfaceConfig(
      id: 'web', name: 'Web Tests', icon: '🌐', platformType: 'web');

  factory SurfaceConfig.autoMobile() =>
      const SurfaceConfig(id: 'mobile', name: 'Mobile Tests', icon: '📱');

  bool get isIos => platformType == 'ios';
  bool get isAndroid => platformType == 'android';
  bool get isWeb => platformType == 'web';
  bool get isMobile => isIos || isAndroid;

  SurfaceConfig copyWith({
    String? id,
    String? name,
    String? icon,
    String? platformType,
    String? environmentId,
    MobileAppId? appId,
    List<String>? commandIds,
    List<ScriptEntry>? scripts,
    bool? runPrerequisites,
    bool? runPull,
    bool? runBuild,
    String? reportOutputRelPath,
    bool clearEnvironmentId = false,
    bool clearAppId = false,
    bool clearReportOutputRelPath = false,
  }) =>
      SurfaceConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        platformType: platformType ?? this.platformType,
        environmentId:
            clearEnvironmentId ? null : (environmentId ?? this.environmentId),
        appId: clearAppId ? null : (appId ?? this.appId),
        commandIds: commandIds ?? this.commandIds,
        scripts: scripts ?? this.scripts,
        runPrerequisites: runPrerequisites ?? this.runPrerequisites,
        runPull: runPull ?? this.runPull,
        runBuild: runBuild ?? this.runBuild,
        reportOutputRelPath: clearReportOutputRelPath
            ? null
            : (reportOutputRelPath ?? this.reportOutputRelPath),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        if (platformType != null) 'platformType': platformType,
        if (environmentId != null) 'environmentId': environmentId,
        if (appId != null && !appId!.isEmpty) 'appId': appId!.toJson(),
        'commandIds': commandIds,
        if (scripts.isNotEmpty)
          'scripts': scripts.map((s) => s.toJson()).toList(),
        if (runPrerequisites) 'runPrerequisites': runPrerequisites,
        if (runPull) 'runPull': runPull,
        if (runBuild) 'runBuild': runBuild,
        if (reportOutputRelPath != null)
          'reportOutputRelPath': reportOutputRelPath,
      };

  factory SurfaceConfig.fromJson(Map<String, dynamic> json) {
    // New format: has 'commandIds'
    // Legacy format: has 'commands' (array of CommandConfig objects) — migrate
    final List<String> commandIds;
    if (json.containsKey('commandIds')) {
      commandIds = (json['commandIds'] as List? ?? []).cast<String>();
    } else {
      // Extract IDs from legacy inline commands list
      commandIds = (json['commands'] as List? ?? [])
          .map((c) => (c as Map<String, dynamic>)['id'] as String)
          .toList();
    }
    final appIdJson = json['appId'] as Map<String, dynamic>?;
    return SurfaceConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String? ?? '🔧',
      platformType: json['platformType'] as String?,
      environmentId: json['environmentId'] as String?,
      appId: appIdJson == null ? null : MobileAppId.fromJson(appIdJson),
      runPrerequisites: json['runPrerequisites'] as bool? ?? false,
      runPull: json['runPull'] as bool? ?? false,
      runBuild: json['runBuild'] as bool? ?? false,
      reportOutputRelPath: json['reportOutputRelPath'] as String?,
      commandIds: commandIds,
      scripts: (json['scripts'] as List? ?? [])
          .map((s) => ScriptEntry.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ── ProjectConfig ─────────────────────────────────────────────────────────────

/// A complete project configuration.
///
/// ### Command architecture (v2)
/// Commands are stored at the project level in [commands] (the global pool).
/// Each [SurfaceConfig] holds an ordered list of [SurfaceConfig.commandIds]
/// that references commands from the pool. This lets you:
///   • Define a command once and use it in multiple surfaces.
///   • Rename / edit a command in one place and have all surfaces updated.
///   • Reorder commands per-surface independently.
class ProjectConfig {
  final String id;
  final String name;

  /// Absolute path to the folder that contains all repos.
  final String projectsRoot;

  /// Repo roles this project uses. Keys match [CommandConfig.repoRole].
  final Map<String, RepoEntry> repos;

  /// Global command pool — all commands available to this project.
  /// Surfaces reference commands here by id via [SurfaceConfig.commandIds].
  final List<CommandConfig> commands;

  final List<SurfaceConfig> surfaces;
  final List<String> extraPathDirs;
  final DateTime? pinnedAt;
  final DateTime? lastOpenedAt;

  const ProjectConfig({
    required this.id,
    required this.name,
    required this.projectsRoot,
    required this.repos,
    this.commands = const [],
    required this.surfaces,
    this.extraPathDirs = const [],
    this.pinnedAt,
    this.lastOpenedAt,
  });

  bool get isPinned => pinnedAt != null;

  ProjectConfig copyWith({
    String? id,
    String? name,
    String? projectsRoot,
    Map<String, RepoEntry>? repos,
    List<CommandConfig>? commands,
    List<SurfaceConfig>? surfaces,
    List<String>? extraPathDirs,
    DateTime? pinnedAt,
    DateTime? lastOpenedAt,
    bool clearPinnedAt = false,
    bool clearLastOpenedAt = false,
  }) =>
      ProjectConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        projectsRoot: projectsRoot ?? this.projectsRoot,
        repos: repos ?? this.repos,
        commands: commands ?? this.commands,
        surfaces: surfaces ?? this.surfaces,
        extraPathDirs: extraPathDirs ?? this.extraPathDirs,
        pinnedAt: clearPinnedAt ? null : (pinnedAt ?? this.pinnedAt),
        lastOpenedAt: clearLastOpenedAt ? null : (lastOpenedAt ?? this.lastOpenedAt),
      );

  // ── Adapters to legacy types ───────────────────────────────────────────────

  MachineProfile toProfile() => MachineProfile(
        projectsRoot: projectsRoot,
        extraPathDirs: extraPathDirs,
      );

  ManifestModel toManifestModel() => ManifestModel(
        product: name,
        environment: 'project',
        repos: {
          ...repos.map((role, entry) => MapEntry(role, entry.toRepoConfig())),
          '_root': RepoConfig(relPath: '', branch: 'develop'),
        },
        recipes: {
          for (final s in surfaces)
            s.id: RecipeConfig(
              id: s.id,
              name: s.name,
              surface: s.id,
              platformType: s.platformType,
              steps: commandsForSurface(s.id).map((c) => c.toStepConfig()).toList(),
            ),
        },
      );

  // ── Command resolution ─────────────────────────────────────────────────────

  /// Resolve the ordered commands for [surfaceId] from the global pool.
  List<CommandConfig> commandsForSurface(String surfaceId) {
    final surface = surfaceById(surfaceId);
    if (surface == null) return [];
    final pool = {for (final c in commands) c.id: c};
    return surface.commandIds
        .map((id) => pool[id])
        .whereType<CommandConfig>()
        .toList();
  }

  /// Simple recipe for a surface — used by DoctorRunner. Actually running a
  /// surface always goes through [RunDispatcher] instead (tag/target-aware —
  /// see [testCommandFor] et al.), not this.
  RecipeConfig simpleRecipeForSurface(String surfaceId) {
    final surface = surfaceById(surfaceId);
    if (surface == null) {
      throw ArgumentError('No surface "$surfaceId" in project "$name"');
    }
    return RecipeConfig(
      id: surfaceId,
      name: surface.name,
      surface: surfaceId,
      platformType: surface.platformType,
      steps: commandsForSurface(surfaceId).map((c) => c.toStepConfig()).toList(),
    );
  }


  SurfaceConfig? surfaceById(String id) {
    try {
      return surfaces.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Pool commands assigned to [surfaceId] — the shared filter every
  /// tag/target-aware lookup below builds on. A command's own null
  /// `target` always matches (it applies regardless of target), same
  /// semantics as before; [stageTag] (when given) must be present in the
  /// command's [CommandConfig.tags] list.
  List<CommandConfig> _filteredCommandsFor(
    String surfaceId, {
    String? stageTag,
    String? target,
  }) {
    final surface = surfaceById(surfaceId);
    if (surface == null) return [];
    final pool = {for (final c in commands) c.id: c};
    return surface.commandIds
        .map((id) => pool[id])
        .whereType<CommandConfig>()
        .where((c) => stageTag == null || c.hasTag(stageTag))
        .where((c) => c.target == null || c.target == target)
        .toList();
  }

  /// The `test`-tagged pool command that actually runs the script for this
  /// target — the "runner command" concept, but resolved by filtering the
  /// pool instead of a pre-assigned slot (see [SurfaceConfig]'s class doc).
  /// First match wins if more than one command happens to match; null if
  /// none does. Used by the run dispatcher.
  CommandConfig? testCommandFor(String surfaceId, {String? target}) =>
      _filteredCommandsFor(surfaceId, stageTag: 'test', target: target)
          .firstOrNull;

  /// The `report`-tagged pool command — same resolution as [testCommandFor],
  /// just without a target axis (a surface has one report tool).
  CommandConfig? reportCommandFor(String surfaceId) =>
      _filteredCommandsFor(surfaceId, stageTag: 'report').firstOrNull;

  /// `build`-tagged pool commands assigned to [surfaceId], filtered to
  /// [target] (`"simulator"`/`"device"`, null = don't filter). Used by the
  /// run dispatcher to decide what to run before the actual script.
  List<CommandConfig> buildInstallCommandsFor(String surfaceId, {String? target}) =>
      _filteredCommandsFor(surfaceId, stageTag: 'build', target: target);

  /// Pool commands tagged `git` or `prerequisite`, assigned to [surfaceId],
  /// in pool order — what [SurfaceConfig.runPrerequisites] actually runs.
  /// Two stage tags can match here (unlike every other resolver, which
  /// matches exactly one), so this is a thin variant rather than reusing
  /// [_filteredCommandsFor] directly.
  List<CommandConfig> prerequisiteCommandsFor(String surfaceId) {
    final surface = surfaceById(surfaceId);
    if (surface == null) return [];
    final pool = {for (final c in commands) c.id: c};
    return surface.commandIds
        .map((id) => pool[id])
        .whereType<CommandConfig>()
        .where((c) => c.hasTag('git') || c.hasTag('prerequisite'))
        .toList();
  }

  // ── JSON ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'projectsRoot': projectsRoot,
        'repos': repos.map((k, v) => MapEntry(k, v.toJson())),
        'commands': commands.map((c) => c.toJson()).toList(),
        'surfaces': surfaces.map((s) => s.toJson()).toList(),
        'extraPathDirs': extraPathDirs,
        if (pinnedAt != null) 'pinnedAt': pinnedAt!.toIso8601String(),
        if (lastOpenedAt != null) 'lastOpenedAt': lastOpenedAt!.toIso8601String(),
      };

  factory ProjectConfig.fromJson(Map<String, dynamic> json) {
    // ── Format detection ──────────────────────────────────────────────────
    // New format (v2): top-level 'commands' array + surfaces have 'commandIds'
    // Legacy format  : no top-level 'commands', surfaces have inline 'commands'
    final hasToplevelCommands = json.containsKey('commands');

    List<CommandConfig> commands;
    List<SurfaceConfig> surfaces;

    if (hasToplevelCommands) {
      commands = (json['commands'] as List? ?? [])
          .map((c) => CommandConfig.fromJson(c as Map<String, dynamic>))
          .toList();
      surfaces = (json['surfaces'] as List? ?? [])
          .map((s) => SurfaceConfig.fromJson(s as Map<String, dynamic>))
          .toList();
    } else {
      // ── Auto-migration from legacy format ─────────────────────────────
      // Collect all commands from all surfaces into a single pool (dedup by id).
      final pool = <String, CommandConfig>{};
      final migratedSurfaces = <SurfaceConfig>[];

      for (final s in (json['surfaces'] as List? ?? [])) {
        final sMap = s as Map<String, dynamic>;
        final surfaceCmds = (sMap['commands'] as List? ?? [])
            .map((c) => CommandConfig.fromJson(c as Map<String, dynamic>))
            .toList();
        for (final cmd in surfaceCmds) {
          pool.putIfAbsent(cmd.id, () => cmd);
        }
        migratedSurfaces.add(SurfaceConfig(
          id: sMap['id'] as String,
          name: sMap['name'] as String,
          icon: sMap['icon'] as String? ?? '🔧',
          commandIds: surfaceCmds.map((c) => c.id).toList(),
        ));
      }

      commands = pool.values.toList();
      surfaces = migratedSurfaces;
    }

    return ProjectConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      projectsRoot: json['projectsRoot'] as String,
      repos: (json['repos'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, RepoEntry.fromJson(v as Map<String, dynamic>)),
      ),
      commands: commands,
      surfaces: surfaces,
      extraPathDirs: (json['extraPathDirs'] as List? ?? []).cast<String>(),
      pinnedAt: json['pinnedAt'] == null
          ? null
          : DateTime.tryParse(json['pinnedAt'] as String),
      lastOpenedAt: json['lastOpenedAt'] == null
          ? null
          : DateTime.tryParse(json['lastOpenedAt'] as String),
    );
  }

  String toJsonString({bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  factory ProjectConfig.fromJsonString(String jsonStr) =>
      ProjectConfig.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
}
