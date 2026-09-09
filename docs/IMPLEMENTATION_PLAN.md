# Implementation Plan — QA Control Center

> **Progress tracker → [`PROGRESS.md`](./PROGRESS.md)** (full scope checklist with ✅/⬜ per item)  
> This file is the **detailed design spec** per phase. Read it when implementing; read PROGRESS.md for status.
>
> **This file stops at Phase 6 and was never updated for Phases 7–9** — the
> multi-project system (`ProjectConfig`/`CommandConfig`/`SurfaceConfig`, a
> full UI rewrite that replaced this doc's single-manifest design as the
> app's live entry point) has no design spec written here. For that
> architecture, read [`PROJECTS_SYSTEM.md`](./PROJECTS_SYSTEM.md) (current,
> code-verified) and `PROGRESS.md`'s Phase 7–9 sections (the "what changed
> and why," in the same per-phase format this file uses). Phases 0–6 below
> are still an accurate design spec for the execution engine
> (`StepRunner`/`DoctorRunner`/`ProcessGateway`) those later phases reuse
> unchanged.

Build inside **`automation-testing`** (Flutter boilerplate). Follow its code structure and
practices, not its mobile-app environment story.

Related: [PROGRESS.md](./PROGRESS.md) · [CONVERSATION_CONTEXT.md](./CONVERSATION_CONTEXT.md) · [COMMANDS_REFERENCE.md](./COMMANDS_REFERENCE.md) · [PROJECTS_SYSTEM.md](./PROJECTS_SYSTEM.md)

---

## 0. Reassessment (read first)

Three concepts stay separate:

1. **Boilerplate flavors** (`lib/dev`, `lib/stage`, `lib/prod`) — how *this* template boots.  
   For v1: always `flutter run -d macos -t lib/dev/main_dev.dart`. No stage/prod of this app.
2. **Centurion test env** — always **dev** in v1 (`.env.dev`, dev flavor APK, `*:dev` npm scripts).
3. **Control-center runtime** — a local macOS tool that shells out via `ProcessGateway`.

---

## 1. What we reuse from the boilerplate

| Use | Do not use as requirements |
|---|---|
| `lib/src` layering, GetIt, Provider, widgets | Login as the main flow |
| New screens under `lib/src/ui/qa/` | Dio as the way tests run |
| SharedPreferences for machine profile paths | This repo's `.env.stage/.env.prod` as test targets |
| Development flavor to launch macOS | Building this tool as a Centurion APK |

Added under `lib/src`:

```
lib/src/
  models/qa/           manifest_model.dart, machine_profile_model.dart
  controllers/qa/      home_controller.dart, setup_controller.dart
  providers/qa/        qa_provider.dart
  ui/qa/               home/home_screen.dart, setup/setup_screen.dart
  base/qa/             process_gateway.dart, manifest_loader.dart
manifests/
  centurion.yaml       environment: dev only; no stage/prod recipes
```

---

## Phase 0 — macOS + PATH ✅

**What was done:**
- Added macOS target (`flutter create . --platforms=macos`)
- Unsandboxed both `DebugProfile.entitlements` and `Release.entitlements`
- `ProcessGateway` runs every command as `/bin/zsh -l -c <cmd>` → login-shell PATH
- Dummy home banner shows git / node / flutter / yarn / npm versions
- Initial route changed from `routeLogin` → `routeQAHome`
- `.vscode/launch.json` updated with "QA Control Center (macOS)" as primary config

**Done-when:** ✅ `flutter run -d macos -t lib/dev/main_dev.dart` → version banner matches Terminal.

---

## Phase 1 — Manifest + paths + setup UI ✅

**What was done:**
- `manifests/centurion.yaml` — `environment: dev`; three recipes (web/ios/android); no stage/prod recipes
- Manifest corrected from actual `package.json` files (see COMMANDS_REFERENCE.md)
- `ManifestModel` / `RepoConfig` / `RecipeConfig` / `StepConfig` — plain Dart, no code-gen
- `StepConfig.envFile` — path to a `.env` file to inject into a step's environment
- `ManifestLoader` — loads YAML from the Flutter asset bundle (cached)
- `MachineProfile` — projects root path in SharedPreferences; no hard-coded usernames
- `SetupController` — folder picker (`file_picker`), validate repo paths, save/load/clear
- `QAProvider` — `ChangeNotifier` owning manifest, profile, tool versions
- Setup screen — first-run folder picker with green/red repo validation
- Home screen — version banner + three recipe cards with Sync / Build+Install toggles

**Done-when:** ✅ Paths resolve without hard-coded usernames; YAML has no stage/prod recipes.

---

## Phase 2 — Doctor ✅

Doctor runs **before** the Run button is enabled for a given recipe.
All checks are for **dev** only.

### Checks (all recipes)

| Check | How | Fix hint shown |
|---|---|---|
| Projects root exists | `Directory.existsSync()` | Re-run Setup |
| Each repo folder exists | `Directory.existsSync()` | Clone the missing repo |
| Repo on `develop` branch | `git branch --show-current` | `git checkout develop` |
| Repo not dirty | `git status --porcelain` | Commit or stash changes |

### Web-specific checks

| Check | How |
|---|---|
| Node ≥ 22 on PATH | `node --version` → parse semver |
| Yarn on PATH | `yarn --version` |
| `.env.dev` present in web repo | `File.existsSync` |
| `.env.test` present in web repo | `File.existsSync` |
| Port 3000 free (Playwright dev server) | `lsof -ti:3000` returns empty |

### Mobile-specific checks (iOS + Android)

| Check | How |
|---|---|
| Node ≥ 20 on PATH | `node --version` |
| npm on PATH | `npm --version` |
| `.env.dev` present in mobile_tests | `File.existsSync` |
| `IOS_SIMULATOR_UDID` / `ANDROID_DEVICE_UDID` set in `.env.dev` | Parse the file |
| Appium running | `GET http://localhost:4723/status` → `{"value":{"ready":true}}` |
| Flutter on PATH (for build step) | `flutter --version` |

### iOS-only checks (vary by target)

**When target = Simulator:**

| Check | How |
|---|---|
| `IOS_SIMULATOR_UDID` set in `mobile_tests/.env.dev` | `EnvFileParser.loadFile(path)['IOS_SIMULATOR_UDID']` |
| Simulator booted with that UDID | `xcrun simctl list devices booted` contains the UDID |
| Java on PATH (Allure) | `java -version` |

**When target = Real Device:**

| Check | How |
|---|---|
| `IOS_DEVICE_ID` set in `mobile_tests/.env.dev` | `EnvFileParser.loadFile(path)['IOS_DEVICE_ID']` |
| `IOS_XCODE_ORG_ID` set (required for device build) | Same env file |
| Device connected and trusted | `xcrun devicectl list devices` contains `IOS_DEVICE_ID` |
| Xcode not open (can conflict with build) | `pgrep -x Xcode` returns empty |
| Java on PATH (Allure) | `java -version` |

**Note:** Doctor re-runs automatically when the user changes the Simulator/Device toggle.

### Android-only checks

| Check | How |
|---|---|
| adb on PATH | `adb version` |
| Device/emulator connected | `adb devices` shows at least one `device` line |
| Java on PATH (Allure) | `java -version` |

### Implementation

```
lib/src/base/qa/
  doctor.dart          DoctorCheck { id, label, status: pass|warn|fail, fixHint }
  doctor_runner.dart   runDoctor(recipe, profile, manifest) → List<DoctorCheck>

lib/src/models/qa/
  doctor_model.dart    DoctorResult, DoctorStatus enum

lib/src/controllers/qa/
  doctor_controller.dart

lib/src/ui/qa/
  doctor/doctor_panel.dart    Collapsible panel below recipe cards; re-check button
```

**QAProvider changes:** add `doctorResults` map (recipeId → `DoctorResult`); expose
`isRecipeRunnable(recipeId)` → true only when all `fail` checks pass.

**Home screen:** `onRun` on each `_RecipeCard` becomes `isRecipeRunnable(recipe.id) ? () => _run(recipe) : null`.

**Done-when:** ✅ Missing `.env.dev`, Appium down, or no device → red card with one-line fix hint. Run button stays disabled. No `.env.stage` required.

### Files created/updated in Phase 2

| File | Role |
|---|---|
| `lib/src/base/qa/doctor_runner.dart` | All check logic, parallel via `Future.wait`. Static methods, never throws. |
| `lib/src/controllers/qa/doctor_controller.dart` | Thin controller — wraps `DoctorRunner.run`, injected via GetIt. |
| `lib/src/providers/qa/qa_provider.dart` | Added `doctorResults`, `isDoctorRunning`, `isRecipeRunnable`, `runDoctor`. |
| `lib/src/ui/qa/doctor/doctor_panel.dart` | Collapsible check list with status icons, fix hints, Re-check button. |
| `lib/src/ui/qa/home/home_screen.dart` | DoctorPanel embedded in each card; `onRun` gated on `isRecipeRunnable`. |
| `lib/src/base/dependencyinjection/locator.dart` | Registered `DoctorController` singleton. |

---

## Phase 3 — Pipeline engine + Web ✅

### Step runner (`lib/src/base/qa/step_runner.dart`)

Interprets `StepConfig` list from the manifest. For each step:

1. Resolve absolute cwd: `profile.repoPath(step.repo)`
2. If `step.envFile != null`: parse `projectsRoot/envFile`, build `Map<String, String>` from it
3. Skip step if `skipIfNoSync && !syncEnabled` or `skipIfNoBuild && !buildEnabled`
4. If `step.detach`: call `ProcessGateway.detach(...)` and move to next step immediately
5. Otherwise: call `ProcessGateway.stream(...)` with a `ProcessHandle`
6. Forward each `LogLine` to the provider's log buffer
7. On non-zero exit: stop pipeline, mark failed

### `.env` file parser (for `env_file` steps)

Simple key=value parser in `lib/src/base/qa/env_file_parser.dart`:
- Skip lines starting with `#`
- Handle quoted values (`"…"` and `'…'`)
- Return `Map<String, String>`

### Web recipe pipeline

```
sync_web  →  install_web  →  test_web (yarn test — all-in-one)  →  allure_open_web (detach)
```

`yarn test` already does: clean + Playwright (env-cmd .env.dev .env.test) + allure generate.
We do NOT add separate clean or generate steps — those are embedded in the script.

### UI (`lib/src/ui/qa/runner/`)

```
run_panel.dart        Live log list, Cancel button, stdin input field (Phase 4)
run_provider.dart     RunState { idle | running | done | failed }, log lines, active handle
```

`RunProvider` (separate `ChangeNotifier`, added to the provider tree):
- `start(recipe, syncEnabled, buildEnabled)` → runs `StepRunner`, emits log lines
- `cancel()` → calls `ProcessHandle.kill()`
- `isRunning` → guard used by `HomeScreen` to disable the other two recipe cards

**Done-when:** ✅ One click runs Centurion web dev tests and opens the Allure report
without touching the terminal.

### What was actually built

| File | Role |
|---|---|
| `lib/src/models/qa/run_model.dart` | `StepOutcome`, `RunStatus`, `StepResult`, `PipelineResult` |
| `lib/src/base/qa/step_runner.dart` | Engine: cwd, env, skip, detach, stream, timeout, cancel, RUN_CONTEXT |
| `lib/src/providers/qa/run_provider.dart` | Run state, capped log buffer, throttled notify, one-run-at-a-time |
| `lib/src/ui/qa/runner/run_panel.dart` | Live log, step progress, elapsed timer, Cancel / Close |
| `lib/src/base/qa/process_gateway.dart` | **Fixed**: process-group kill, output tail, exit-code ordering |
| `lib/src/ui/qa/home/home_screen.dart` | Run wired; cards + toggles gated on run state |
| `test/step_runner_test.dart` | 7 tests, fake gateway |
| `test/process_gateway_test.dart` | 3 tests, real processes |

Two deviations from the spec above, both deliberate:

- **stdin field deferred to Phase 4.** A disabled text box is not a feature; it
  lands with the OTP work that needs it.
- **`RunProvider` lives in `lib/src/providers/qa/`**, not `lib/src/ui/qa/runner/`
  — matches the layering used by `QAProvider` and the file map in PROGRESS.md.

### Gateway bugs found while wiring this up

`ProcessGateway` was written in Phase 0 but never actually exercised by a
long-running, cancellable, non-zero-exiting process until now. Three defects:

1. **Cancel left orphans.** `Process.start` does not `setsid()` in normal mode,
   so the child shared *this app's* process group and `kill -TERM -<pgid>` could
   not target it. Children now spawn via
   `/usr/bin/perl -e 'setpgrp; exec @ARGV' /bin/zsh -l -c <cmd>`.
2. **Lost output tail.** The merged stream closed on `process.exitCode`, which
   can fire before the pipes drain. Now waits for both, with a 2s post-exit
   grace so an inherited-stdout grandchild cannot hang the run.
3. **Exit code raced the stream close.** Now guaranteed set before close, which
   is what `StepRunner` reads.

---

## Phase 4 — iOS + Android ✅

### stdin / PTY field

WDIO (`otpFetcher.ts`) blocks on Node `readline` waiting for a human to paste an OTP.
The pipeline must keep the child's stdin pipe open and forward text typed in the UI.

`ProcessGateway.stream()` already returns a `ProcessHandle`. Extend it:
- `ProcessHandle.writeStdin(String line)` → writes `$line\n` to the child's stdin
- `RunPanel` shows a `TextField` + Send button when the step is `test_ios` / `test_android`
  (or always when `isRunning`, since other steps may also prompt)

### iOS target — simulator vs device

The iOS recipe card has a `SegmentedButton` (Simulator / Real Device).
The selection is passed as `IosBuildTarget` to `StepRunner`.

`RecipeConfig.stepsFor(iosTarget: …)` filters the full step list — steps tagged
`target: simulator` are dropped in device mode and vice versa. Steps with no tag run for both.
This keeps the YAML declarative and the Dart clean; no `if/else` scattered through the runner.

**Simulator steps** use `xcrun simctl install/launch` and `wdio.ios.simulator.conf.ts`.
**Device steps** use `xcrun devicectl device install app/process launch` and `npm run test:ios:dev`.

### env_file injection for build/install/launch

All build/install/launch steps that need `IOS_SIMULATOR_UDID` or `IOS_DEVICE_ID` declare
`env_file: centurion-app-automation-tests-ts/.env.dev` in the manifest.
`StepRunner` resolves the absolute path (`projectsRoot/relPath/.env.dev`),
calls `EnvFileParser.loadFile(path)`, and merges the result into `ProcessGateway.stream(extraEnv: …)`.

### Android APK path

Debug flavor: `build/app/outputs/flutter-apk/app-development-debug.apk`
Release flavor (post-v1): `build/app/outputs/flutter-apk/app-development-release.apk`

### Appium detection (re-check in Doctor)

Before starting the `test_ios` / `test_android` step, `StepRunner` optionally re-checks
`http://localhost:4723/status` and emits a `LogLine(isError: true)` + aborts if Appium is gone.

**Done-when:** ✅ iOS and Android dev tests run from the UI with Sync / Build toggles
and an OTP stdin field.

### What was actually built

The iOS/Android step lists in `manifests/centurion.yaml` were already correct
from Phase 1 (target-filtered steps, `env_file` injection, Appium checks in
Doctor). This phase's real work:

| File | Role |
|---|---|
| `lib/src/base/qa/process_gateway.dart` | `ProcessHandle.writeStdin(line)` — writes to the child's stdin pipe (already open on a normal-mode start; no PTY needed) |
| `lib/src/base/qa/appium_probe.dart` | `GET /status` check, factored out of `DoctorRunner` so Doctor and `StepRunner` share one implementation |
| `lib/src/models/qa/manifest_model.dart` | `StepConfig.checkAppium` / `check_appium:` manifest field |
| `manifests/centurion.yaml` | `check_appium: true` on the three WDIO test steps |
| `lib/src/base/qa/step_runner.dart` | Re-checks Appium right before a tagged step; `writeStdin` passthrough to the active step; `isAppiumRunning` test seam |
| `lib/src/providers/qa/run_provider.dart` | `sendInput(line)` — forwards to `StepRunner`, echoes `» <line>` into the log |
| `lib/src/ui/qa/runner/run_panel.dart` | Persistent stdin `TextField` + Send, shown for the whole run |
| `test/process_gateway_test.dart` | Real end-to-end test: a child blocking on `read` (mirrors `otpFetcher.ts`) actually receives what `writeStdin` sends |
| `test/step_runner_test.dart` | `check_appium` gates the step and aborts the pipeline when Appium is down |

One deliberate scope note: the stdin field is shown for the **entire run**, not
just the WDIO step — the pipeline has no way to know in advance which step
will prompt, and an idle text field the rest of the time costs nothing.

---

## Phase 5 — History + daily-use polish ✅

- `RunHistory`: persist `RunRecord { recipe, startedAt, durationMs, status, reportPath, logPath }` to SharedPreferences (JSON list, max 50 entries)
- History panel on Home: shows last N runs; tap → reopen report / reopen log
- Sleep assertion: `IOOverrides` or `ProcessGateway` keepalive to prevent macOS sleep during a run
- Quit → kill process group: `ProcessHandle.kill()` called from `AppLifecycleObserver`
- Settings screen: extra PATH dirs (written to `MachineProfile.extraPathDirs`)
- "Re-open last Allure report" shortcut on the recipe card after a completed run

**Done-when:** ✅ Second run is blocked while one is active; last Allure report
can be reopened; quit kills orphan processes (verified with a real process
tree + `caffeinate`, not just a fake).

### What was actually built

| File | Role |
|---|---|
| `lib/src/models/qa/run_record_model.dart` | `RunRecord` — no `reportPath`; reopening re-runs the recipe's `detach` step instead (see below) |
| `lib/src/base/qa/run_history_store.dart` | Persists to SharedPreferences as one JSON string, capped at 50, newest first |
| `lib/src/base/qa/sleep_guard.dart` | `caffeinate -i` subprocess wrapper |
| `lib/src/ui/qa/history/history_panel.dart` | Last 8 runs; reopen report / reopen log |
| `lib/src/providers/qa/run_provider.dart` | Owns history + sleep guard; writes each run's full log to `docs/run-logs/`; `cancelAndWait()` for quit |
| `lib/src/providers/qa/qa_provider.dart` | `reopenReport` / `openLogFile`; pushes `extraPathDirs` into the shared gateway |
| `lib/src/main.dart` | `MyApp` → `StatefulWidget` with `WidgetsBindingObserver.didRequestAppExit` |
| `lib/src/ui/qa/setup/setup_screen.dart` | Extra PATH dirs UI; prefills on revisit (was previously always blank) |
| `lib/src/base/qa/process_gateway.dart` | `extraPathDirs` actually wired into PATH (was dead data — see below) |
| `test/run_history_store_test.dart` | 5 tests |
| `test/run_provider_quit_test.dart` | Real end-to-end: orphan processes + `caffeinate` confirmed gone after `cancelAndWait()` |
| `test/process_gateway_test.dart` | +3 tests for `extraPathDirs` |
| `test/step_runner_test.dart` | +1 test for `RecipeConfig.reportStep` |

### Two things this phase found, not just built

**Reopening a report can't be a static file path.** `allure open` runs a
local server — the report's data won't load over a bare `file://` URL. So
`RunRecord.hasReport` is just `status == done` (the report-open step is
always last), and reopening re-invokes that exact command via
`RecipeConfig.reportStep`.

**`MachineProfile.extraPathDirs` had been dead since Phase 1.** It was
persisted and round-tripped through Setup, but nothing read it —
`ProcessGateway` never touched PATH, and `DoctorController` / `StepRunner`
each built their own private `ProcessGateway()` instead of the shared
locator singleton, so setting the field on *that* instance wouldn't have
reached Doctor or the pipeline anyway. Fixed all three points; see
`docs/CONVERSATION_CONTEXT.md` for the full trace.

---

## Phase 6 — Spec picker + README ✅

- Optional spec file selector for each recipe
  - Web: Playwright `--grep` or specific file paths
  - Mobile: WDIO `--spec test/specs/foo.e2e.ts` (or `--mochaOpts.grep "TAG"`)
  - Manifest: new optional `spec_flags` field per step
- README: "open macOS dev build → select Projects folder → Doctor → Run"

**Done-when:** ✅ Another person can run dev Centurion tests without memorising
npm/yarn flags. README fully rewritten (was still the generic `flutter create`
boilerplate template — completely unrelated to this app).

### What was actually built — and one plan revision

The manifest field is `spec_command`, not `spec_flags`. Appending flags to
the end of the existing `command` — the original idea — silently breaks for
Web: `yarn test`'s real `package.json` script is a 4-command chain
(`allure:clean && playwright:clean && env-cmd ... playwright test &&
allure:generate`), and npm/yarn's arg-forwarding lands on the *last* command
in that chain, not `playwright test`. A user's filter would be silently
ignored. `specCommand` is a full alternate command template, used instead of
`command` only when the recipe's spec field is non-blank:

| Recipe | `spec_command` |
|---|---|
| Web | Reconstructs the chain with the flag on the real `playwright test` line |
| iOS (sim/device) | Direct `wdio run wdio.*.conf.ts {flags}` |
| Android | Direct `wdio run wdio.android.conf.ts {flags}` |

| File | Role |
|---|---|
| `lib/src/models/qa/manifest_model.dart` | `StepConfig.specCommand` |
| `manifests/centurion.yaml` | `spec_command` on the four test steps |
| `lib/src/base/qa/step_runner.dart` | Resolves `command` vs `specCommand`; logs the filter used |
| `lib/src/providers/qa/run_provider.dart` | `specFlags` threaded through `start()` |
| `lib/src/ui/qa/home/home_screen.dart` | Per-card `TextField` + `TextEditingController` |
| `test/step_runner_test.dart` | +3 tests |
| `README.md` | Full rewrite |

---

## Work order inside a phase (always follow this)

1. Model(s)
2. Fakeable gateway / parser
3. Controller + GetIt registration
4. Provider change (if live UI state)
5. Screen / widget
6. Widget tests against fakes (no real shell in widget tests)
7. Manual macOS "done-when" check

---

## Risks

| Risk | Mitigation |
|---|---|
| Mixing boilerplate env with Centurion env | v1: this app = dev flavor only; tests = Centurion dev only |
| GUI PATH / SSH agent missing | Phase 0 ProcessGateway (`-l` flag); Doctor `git ls-remote` |
| Orphan Flutter/Gradle/npm processes | ProcessHandle kills process group (`kill -TERM -<pgid>`) |
| WDIO blocks on OTP stdin | Phase 4 stdin field in RunPanel |
| Mixed Allure results from multiple runs | Clean `allure-results` in manifest before each test step |
| `IOS_SIMULATOR_UDID` not available to install step | `env_file` field on step → StepRunner injects `.env.dev` vars |
| macOS sleep kills long Android build | Phase 5 sleep assertion |
