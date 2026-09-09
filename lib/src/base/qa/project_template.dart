import 'package:flutter_boilerplate/src/models/qa/project_model.dart';

// Centurion seed template.
//
// Commands are stored at the project level (global pool). Each surface
// references them by ID via commandIds. This means editing a command in the
// Command Library updates it everywhere it's used.
//
// Kept in sync with the real, live Centurion project data (see
// docs/COMMANDS_REFERENCE.md) — six surfaces (dev/stage × android/ios/web),
// `{environment}`/`{branch}`/`{bundleId}` dynamic substitution instead of
// hardcoded values, and Pull/Build maintained as per-surface switches
// (`SurfaceConfig.runPull`/`.runBuild`) rather than a per-run Run/Pull&Run/
// Build&Run choice. See docs/RUN_EXPERIENCE_REDESIGN.md's final step for why.

class ProjectTemplate {
  ProjectTemplate._();

  /// Available template types for the Create Project screen.
  static const List<ProjectTemplateType> available = [
    ProjectTemplateType.centurion,
    ProjectTemplateType.custom,
  ];

  static ProjectConfig centurion({
    required String name,
    required String projectsRoot,
    Map<String, String>? repoRelPaths,
    Map<String, String>? repoBranches,
    List<String> extraPathDirs = const [],
  }) {
    String relPath(String role, String defaultName) =>
        repoRelPaths?[role] ?? defaultName;
    String branch(String role) => repoBranches?[role] ?? 'develop';

    final repos = {
      'mobile_ui': RepoEntry(
        role: 'mobile_ui',
        label: 'Flutter App',
        relPath: relPath('mobile_ui', 'crichq-app-flutter'),
        branch: branch('mobile_ui'),
      ),
      'web': RepoEntry(
        role: 'web',
        label: 'Web App',
        relPath: relPath('web', 'crichq-webapp-nextjs'),
        branch: branch('web'),
      ),
      'mobile_test': RepoEntry(
        role: 'mobile_test',
        label: 'Mobile Tests',
        relPath: relPath('mobile_test', 'centurion-app-automation-tests-ts'),
        branch: branch('mobile_test'),
      ),
    };

    final commands = _commands();
    final byId = {for (final c in commands) c.id: c.id};
    List<String> ids(List<String> wanted) {
      // Defensive: every id referenced by a surface below must exist in the
      // pool above — fail loudly at template-build time, not with a silent
      // missing command in the UI later.
      for (final id in wanted) {
        assert(byId.containsKey(id), 'Unknown command id in template: $id');
      }
      return wanted;
    }

    // Shared across dev/stage: prerequisites that don't vary by environment.
    // `sync_app`/`sync_web` are deliberately NOT assigned here — pulling the
    // buildable repo is now the surface-level `runPull` switch's job (same
    // repo, same branch), so assigning the old sync command too would pull
    // it twice per run. `sync_tests` stays assigned: it pulls the separate
    // mobile_test repo, which runPull doesn't touch.
    const mobilePrereqs = ['sync_tests', 'install_deps_mobile_test', 'clean_allure_mobile'];
    const mobileReport = ['allure_generate_mobile', 'allure_open_mobile'];
    const webPrereqs = ['install_web'];
    const webReport = ['allure_generate_web', 'allure_open_web'];

    SurfaceConfig androidSurface(String env, String bundleId) => SurfaceConfig(
          id: 'android_$env',
          name: 'Android (${_titleCase(env)})',
          icon: '🤖',
          platformType: 'android',
          environmentId: env,
          appId: MobileAppId(androidApplicationId: bundleId),
          commandIds: ids([
            'build_runner_mobile',
            ...mobilePrereqs,
            'build_android_$env',
            'install_android_$env',
            'test_android',
            ...mobileReport,
          ]),
          runPrerequisites: true,
          runPull: true,
          runBuild: true,
          reportOutputRelPath: 'allure-report',
        );

    SurfaceConfig iosSurface(String env, String bundleId) => SurfaceConfig(
          id: 'ios_$env',
          name: 'iOS (${_titleCase(env)})',
          icon: '🍎',
          platformType: 'ios',
          environmentId: env,
          appId: MobileAppId(iosBundleId: bundleId),
          commandIds: ids([
            'build_runner_mobile',
            ...mobilePrereqs,
            'build_ios_simulator_$env',
            'install_ios_simulator',
            'launch_ios_simulator',
            'build_ios_device_$env',
            'install_ios_device',
            'launch_ios_device',
            'test_ios_simulator',
            'test_ios_device',
            ...mobileReport,
          ]),
          runPrerequisites: true,
          runPull: true,
          runBuild: true,
          reportOutputRelPath: 'allure-report',
        );

    SurfaceConfig webSurface(String env) => SurfaceConfig(
          id: 'web_$env',
          name: 'Web (${_titleCase(env)})',
          icon: '🌐',
          platformType: 'web',
          environmentId: env,
          commandIds: ids(['build_web', ...webPrereqs, 'test_web', ...webReport]),
          runPrerequisites: true,
          runPull: true,
          runBuild: true,
          reportOutputRelPath: 'allure-report',
        );

    return ProjectConfig(
      id: generateProjectId(),
      name: name,
      projectsRoot: projectsRoot,
      repos: repos,
      commands: commands,
      extraPathDirs: extraPathDirs,
      surfaces: [
        androidSurface('dev', 'com.goa.app.dev'),
        androidSurface('stage', 'com.goa.app.stage'),
        iosSurface('dev', 'com.goa.app.dev'),
        iosSurface('stage', 'com.goa.app.stage'),
        webSurface('dev'),
        webSurface('stage'),
      ],
    );
  }

  static ProjectConfig custom({
    required String name,
    required String projectsRoot,
    // Whatever the user actually typed into the Repositories rows on the
    // Create screen — those rows are shown and editable for every template,
    // not just centurion, so this must not be dropped (it used to be, which
    // silently lost repo folder paths for any "Start blank" project).
    Map<String, String>? repoRelPaths,
    Map<String, String>? repoBranches,
    List<String> extraPathDirs = const [],
  }) {
    final repos = <String, RepoEntry>{
      for (final entry in (repoRelPaths ?? const {}).entries)
        entry.key: RepoEntry(
          role: entry.key,
          label: entry.key,
          relPath: entry.value,
          branch: repoBranches?[entry.key] ?? 'develop',
        ),
    };

    return ProjectConfig(
      id: generateProjectId(),
      name: name,
      projectsRoot: projectsRoot,
      repos: repos,
      commands: const [],
      surfaces: const [],
      extraPathDirs: extraPathDirs,
    );
  }

  static String _titleCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  // ── Global command pool ────────────────────────────────────────────────────
  //
  // One shared pool, not three per-platform lists — a command with the same
  // id is assigned wherever it's needed instead of being redefined per
  // platform/environment (that duplication, e.g. separate `sync_app_ios`/
  // `sync_app_android` entries doing the exact same `git pull`, is exactly
  // the "repetitive commands" class of bug this template used to have).
  static List<CommandConfig> _commands() => const [
        // Sync (git) — kept in the pool for manual/ad-hoc use even though
        // sync_app/sync_web aren't assigned to any surface by default (see
        // runPull above); sync_tests IS assigned (mobile_test isn't covered
        // by runPull).
        CommandConfig(
          id: 'sync_app',
          name: 'Sync — app repo',
          command: 'git pull origin {branch}',
          repoRole: 'mobile_ui',
          tags: ['git'],
          order: 0,
        ),
        CommandConfig(
          id: 'sync_tests',
          name: 'Sync — mobile tests repo',
          command: 'git pull origin {branch}',
          repoRole: 'mobile_test',
          tags: ['git'],
          order: 1,
        ),
        CommandConfig(
          id: 'sync_web',
          name: 'Sync — web repo',
          command: 'git pull origin {branch}',
          repoRole: 'web',
          tags: ['git'],
          order: 2,
        ),

        // Prerequisites
        CommandConfig(
          id: 'build_runner_mobile',
          name: 'Generate serialization code (build_runner)',
          command: 'fvm flutter pub run build_runner build --delete-conflicting-outputs',
          repoRole: 'mobile_ui',
          tags: ['prerequisite'],
          order: 3,
        ),
        CommandConfig(
          id: 'install_deps_mobile_test',
          name: 'Install test dependencies (npm ci)',
          command: 'npm ci',
          repoRole: 'mobile_test',
          tags: ['prerequisite'],
          order: 4,
        ),
        CommandConfig(
          id: 'clean_allure_mobile',
          name: 'Clean previous Allure results',
          command: 'rm -rf allure-results allure-report',
          repoRole: 'mobile_test',
          tags: ['prerequisite'],
          order: 5,
        ),
        CommandConfig(
          id: 'install_web',
          name: 'Install dependencies (yarn)',
          command: 'yarn install --frozen-lockfile',
          repoRole: 'web',
          tags: ['prerequisite'],
          order: 6,
        ),

        // Build — iOS simulator (dev/stage both build in --debug, matching
        // the actual debug-only test-email-prefill feature the app relies
        // on; see docs/RUN_EXPERIENCE_REDESIGN.md).
        CommandConfig(
          id: 'build_ios_simulator_dev',
          name: 'Build iOS simulator app (dev, debug)',
          command: 'fvm flutter build ios --flavor development '
              '-t lib/dev/main_dev.dart --simulator --debug',
          repoRole: 'mobile_ui',
          target: 'simulator',
          timeoutSeconds: 900,
          tags: ['build'],
          order: 7,
        ),
        CommandConfig(
          id: 'build_ios_simulator_stage',
          name: 'Build iOS simulator app (stage, debug)',
          command: 'fvm flutter build ios --flavor stage '
              '-t lib/stage/main_stage.dart --simulator --debug',
          repoRole: 'mobile_ui',
          target: 'simulator',
          timeoutSeconds: 900,
          tags: ['build'],
          order: 8,
        ),
        CommandConfig(
          id: 'install_ios_simulator',
          name: 'Install app on simulator',
          command: r'xcrun simctl install "${IOS_SIMULATOR_UDID}" '
              'build/ios/iphonesimulator/Runner.app',
          repoRole: 'mobile_ui',
          target: 'simulator',
          envFile: 'centurion-app-automation-tests-ts/.env.{environment}',
          tags: ['build'],
          order: 9,
        ),
        CommandConfig(
          id: 'launch_ios_simulator',
          name: 'Launch app on simulator',
          command: r'xcrun simctl launch "${IOS_SIMULATOR_UDID}" {bundleId}',
          repoRole: 'mobile_ui',
          target: 'simulator',
          envFile: 'centurion-app-automation-tests-ts/.env.{environment}',
          tags: ['build'],
          order: 10,
        ),

        // Build — iOS real device. Matches the simulator command's --debug
        // flag: previously missing here, which silently produced a release
        // build under a name that never said so — see
        // docs/RUN_EXPERIENCE_REDESIGN.md's final step.
        CommandConfig(
          id: 'build_ios_device_dev',
          name: 'Build iOS device app (dev, debug)',
          command: 'fvm flutter build ios --flavor development '
              '-t lib/dev/main_dev.dart --debug',
          repoRole: 'mobile_ui',
          target: 'device',
          timeoutSeconds: 900,
          tags: ['build'],
          order: 11,
        ),
        CommandConfig(
          id: 'build_ios_device_stage',
          name: 'Build iOS device app (stage, debug)',
          command: 'fvm flutter build ios --flavor stage '
              '-t lib/stage/main_stage.dart --debug',
          repoRole: 'mobile_ui',
          target: 'device',
          timeoutSeconds: 900,
          tags: ['build'],
          order: 12,
        ),
        CommandConfig(
          id: 'install_ios_device',
          name: 'Install app on device (devicectl)',
          command: r'xcrun devicectl device install app --device "${IOS_DEVICE_ID}" '
              'build/ios/iphoneos/Runner.app',
          repoRole: 'mobile_ui',
          target: 'device',
          envFile: 'centurion-app-automation-tests-ts/.env.{environment}',
          tags: ['build'],
          order: 13,
        ),
        CommandConfig(
          id: 'launch_ios_device',
          name: 'Launch app on device',
          command: r'xcrun devicectl device process launch --device "${IOS_DEVICE_ID}" '
              '{bundleId}',
          repoRole: 'mobile_ui',
          target: 'device',
          envFile: 'centurion-app-automation-tests-ts/.env.{environment}',
          tags: ['build'],
          order: 14,
        ),

        // Build — Android (one flavor per environment; already debug).
        CommandConfig(
          id: 'build_android_dev',
          name: 'Build Android debug APK (dev flavor)',
          command: 'fvm flutter build apk --flavor development '
              '-t lib/dev/main_dev.dart --debug',
          repoRole: 'mobile_ui',
          timeoutSeconds: 900,
          tags: ['build'],
          order: 15,
        ),
        CommandConfig(
          id: 'install_android_dev',
          name: 'Install APK via adb (dev)',
          command: 'adb install -r build/app/outputs/flutter-apk/app-development-debug.apk',
          repoRole: 'mobile_ui',
          tags: ['build'],
          order: 16,
        ),
        CommandConfig(
          id: 'build_android_stage',
          name: 'Build Android debug APK (stage flavor)',
          command: 'fvm flutter build apk --flavor stage -t lib/stage/main_stage.dart --debug',
          repoRole: 'mobile_ui',
          timeoutSeconds: 900,
          tags: ['build'],
          order: 17,
        ),
        CommandConfig(
          id: 'install_android_stage',
          name: 'Install APK via adb (stage)',
          command: 'adb install -r build/app/outputs/flutter-apk/app-stage-debug.apk',
          repoRole: 'mobile_ui',
          tags: ['build'],
          order: 18,
        ),

        // Build — web
        CommandConfig(
          id: 'build_web',
          name: 'Build web app',
          command: 'yarn build:{environment}',
          repoRole: 'web',
          timeoutSeconds: 300,
          tags: ['build'],
          order: 19,
        ),

        // Test
        CommandConfig(
          id: 'test_ios_simulator',
          name: 'Run WDIO iOS simulator tests',
          command: 'ENV_FILE=.env.{environment} npx wdio run '
              'wdio.ios.simulator.conf.ts --spec {script}',
          repoRole: 'mobile_test',
          target: 'simulator',
          timeoutSeconds: 1800,
          checkAppium: true,
          tags: ['test'],
          order: 20,
        ),
        CommandConfig(
          id: 'test_ios_device',
          name: 'Run WDIO iOS device tests',
          command: 'npm run test:ios:{environment} -- --spec {script}',
          repoRole: 'mobile_test',
          target: 'device',
          timeoutSeconds: 1800,
          checkAppium: true,
          tags: ['test'],
          order: 21,
        ),
        CommandConfig(
          id: 'test_android',
          name: 'Run WDIO Android tests',
          command: 'npm run test:android:{environment} -- --spec {script}',
          repoRole: 'mobile_test',
          timeoutSeconds: 1800,
          checkAppium: true,
          tags: ['test'],
          order: 22,
        ),
        CommandConfig(
          id: 'test_web',
          name: 'Run web test script',
          command: 'yarn {script}',
          repoRole: 'web',
          timeoutSeconds: 600,
          tags: ['test'],
          order: 23,
        ),

        // Report
        CommandConfig(
          id: 'allure_generate_mobile',
          name: 'Generate Allure report',
          command: 'npm run report:generate',
          repoRole: 'mobile_test',
          tags: ['report'],
          order: 24,
        ),
        CommandConfig(
          id: 'allure_open_mobile',
          name: 'Open Allure report',
          command: 'npm run report:open',
          repoRole: 'mobile_test',
          detach: true,
          tags: ['report'],
          order: 25,
        ),
        CommandConfig(
          id: 'allure_generate_web',
          name: 'Generate Allure report',
          command: 'yarn allure:generate',
          repoRole: 'web',
          tags: ['report'],
          order: 26,
        ),
        CommandConfig(
          id: 'allure_open_web',
          name: 'Open Allure report',
          command: 'yarn allure:open',
          repoRole: 'web',
          detach: true,
          tags: ['report'],
          order: 27,
        ),
      ];
}

// ── ProjectTemplateType ───────────────────────────────────────────────────────

enum ProjectTemplateType {
  centurion,
  custom;

  String get label => switch (this) {
        ProjectTemplateType.centurion => 'Centurion (Recommended)',
        ProjectTemplateType.custom => 'Start blank',
      };

  String get description => switch (this) {
        ProjectTemplateType.centurion =>
          'Pre-fills Android/iOS/Web surfaces for both dev and stage with '
              'all standard commands. Edit from the Command Library after '
              'creation.',
        ProjectTemplateType.custom =>
          'Empty project — add repos and commands manually or import from JSON.',
      };

  String get icon => switch (this) {
        ProjectTemplateType.centurion => '🧪',
        ProjectTemplateType.custom => '📄',
      };
}
