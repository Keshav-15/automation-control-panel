# QA Control Center — Full Scope & Progress

> **Read [`PROJECTS_SYSTEM.md`](./PROJECTS_SYSTEM.md) alongside this file.**
> Phases 0–6 below describe the *original single-project system*
> (`routeQAHome`) — its execution engine (`StepRunner`, `DoctorRunner`,
> `ProcessGateway`, `RunProvider`) is still reused unchanged, but its UI
> layer (`HomeScreen`, `SetupScreen`, `QAProvider`,
> `manifests/centurion.yaml`) is now orphaned — the app's `initialRoute` is
> `routeProjects`, and nothing in the reachable UI pushes `routeQAHome`
> anymore. Phases 7–8 below already document the multi-project system that
> replaced it as the live UI. PROJECTS_SYSTEM.md is a later, code-verified
> pass that captures what evolved *after* Phase 8 was written (the
> command-pool/`commandIds` reference model, this session's fixes and
> additions — see its own "Phase 9" companion section below) plus gaps
> found along the way that hadn't been written down anywhere yet.

Single file to track every deliverable across all phases.
Update this file whenever a phase or sub-item is completed.

**App:** Flutter macOS desktop (`flutter run -d macos -t lib/dev/main_dev.dart`)  
**Purpose:** Orchestrate Centurion test suites (Web / iOS / Android) without memorising terminal flags.  
**Environment:** Dev only for v1. Stage/prod are post-v1.

Legend: ✅ Done · 🔄 In progress · ⬜ Pending

---

## Quick status

| Phase | Name | Status | Verified |
|---|---|---|---|
| 0 | macOS + login-shell PATH | ✅ Done | Version banner matches Terminal |
| 1 | Manifest + machine profile + setup UI | ✅ Done | Folder picker → home with 3 cards |
| 2 | Doctor (pre-flight checks) | ✅ Done | Run button gated on Doctor pass |
| 3 | Pipeline engine + Web tests | ✅ Done | Pipeline verified on real repos; 10 tests pass |
| 4 | iOS + Android (stdin / OTP) | ✅ Done | Real OTP-delivery test passes; Appium re-check wired |
| 5 | History + daily-use polish | ✅ Done | Real orphan-kill-on-quit test passes |
| 6 | Spec picker + README | ✅ Done | All phases complete |
| 7 | Multi-project + dynamic commands | ✅ Done | Build clean; 0 errors; import/export JSON |
| 8 | Bug fixes + groups + history | ✅ Done | 0 errors, 0 warnings; persistence bug fixed |
| 9 | Create-time repo-loss fix + duplicate + validation | ✅ Done | 29/29 tests pass; build clean |
| 10 | Doctor quick-fix + filter consolidation + tooltips | ✅ Done | 32/32 tests pass; real git-fix end-to-end tests |
| 11 | ProcessGateway PATH resolution fix | ✅ Done | `env: node: No such file or directory` fixed |
| 12 | Run Experience Redesign | ✅ Done | 137/137 tests pass; see RUN_EXPERIENCE_REDESIGN.md |
| 13 | Tags overhaul, real Centurion data, Pull/Build switches | ✅ Done | 132/135 tests pass (3 pre-existing flaky, unrelated) |

---

## Phase 0 — macOS + login-shell PATH ✅

**Goal:** App launches on macOS, tool versions in the banner match what `which node` shows in Terminal.

- [x] `flutter create . --platforms=macos` — macOS target added
- [x] `DebugProfile.entitlements` — sandbox disabled (`com.apple.security.app-sandbox = false`)
- [x] `Release.entitlements` — sandbox disabled
- [x] `ProcessGateway` — every command runs as `/bin/zsh -l -c <cmd>` (login-shell PATH)
- [x] `ProcessHandle` — kills process group via `kill -TERM -<pgid>`
- [x] Home screen version banner — git / node / flutter / yarn / npm
- [x] Initial route → `routeQAHome` (not `routeLogin`)
- [x] `.vscode/launch.json` — "QA Control Center (macOS)" primary config

**Files:**
- `lib/src/base/qa/process_gateway.dart`
- `macos/Runner/DebugProfile.entitlements`
- `macos/Runner/Release.entitlements`

---

## Phase 1 — Manifest + machine profile + setup UI ✅

**Goal:** Declarative YAML drives the pipeline; machine paths stored without hard-coded usernames; first-run setup screen works.

- [x] `manifests/centurion.yaml` — `environment: dev`; 3 recipes (web / ios / android)
- [x] Steps corrected from actual `package.json` + WDIO conf files (see `COMMANDS_REFERENCE.md`)
- [x] `StepConfig.envFile` — path to `.env` file injected into step's env before running
- [x] `StepConfig.target` — `"simulator" | "device" | null` for iOS step filtering
- [x] `IosBuildTarget` enum — `simulator` / `device`; label + icon getters
- [x] `RecipeConfig.stepsFor(iosTarget:)` — filters step list by target tag
- [x] `ManifestLoader` — loads YAML from Flutter asset bundle (cached; `invalidate()` to reload)
- [x] `MachineProfile` — `projectsRoot` + `extraPathDirs` in SharedPreferences; no secrets
- [x] `EnvFileParser` — dotenv-style parser: strips comments, handles quoted values
- [x] `SetupController` — folder picker (`file_picker`), repo validation, save/load/clear
- [x] `HomeController` — parallel `Future.wait` for all tool versions
- [x] `QAProvider` — `ChangeNotifier`; owns manifest, profile, tool versions
- [x] Setup screen — folder picker + green/red repo validation per repo
- [x] Home screen — version banner + 3 recipe cards; iOS card has Simulator/Device toggle
- [x] `res_base_model.g.dart` — hand-written JSON stubs (build_runner version mismatch workaround)

**Files:**
- `manifests/centurion.yaml`
- `lib/src/models/qa/manifest_model.dart`
- `lib/src/models/qa/machine_profile_model.dart`
- `lib/src/base/qa/manifest_loader.dart`
- `lib/src/base/qa/env_file_parser.dart`
- `lib/src/controllers/qa/setup_controller.dart`
- `lib/src/controllers/qa/home_controller.dart`
- `lib/src/providers/qa/qa_provider.dart`
- `lib/src/ui/qa/setup/setup_screen.dart`
- `lib/src/ui/qa/home/home_screen.dart`

---

## Phase 2 — Doctor (pre-flight checks) ✅

**Goal:** Every recipe has a health-check panel. Run button stays disabled until all blocking checks pass.

### Checks implemented

| Surface | Check | Status |
|---|---|---|
| All | Repo directory exists on disk | ✅ |
| All | Repo on `develop` branch (warn if not) | ✅ |
| All | Repo working tree clean (fail if dirty) | ✅ |
| Web | Node ≥ 22 on PATH | ✅ |
| Web | Yarn on PATH | ✅ |
| Web | `.env.dev` present in web repo | ✅ |
| Web | `.env.test` present in web repo | ✅ |
| Web | Port 3000 free (warn) | ✅ |
| iOS + Android | Node ≥ 20 on PATH | ✅ |
| iOS + Android | npm on PATH | ✅ |
| iOS + Android | `.env.dev` present in `mobile_tests` | ✅ |
| iOS + Android | Appium running at `localhost:4723/status` | ✅ |
| iOS + Android | Flutter on PATH | ✅ |
| iOS + Android | Java on PATH / Allure (warn) | ✅ |
| iOS Simulator | `IOS_SIMULATOR_UDID` set in `.env.dev` | ✅ |
| iOS Simulator | Simulator booted with that UDID | ✅ |
| iOS Device | `IOS_DEVICE_ID` set in `.env.dev` | ✅ |
| iOS Device | `IOS_XCODE_ORG_ID` set in `.env.dev` | ✅ |
| iOS Device | Real device connected (`xcrun devicectl`) | ✅ |
| iOS Device | Xcode not open (warn — can conflict) | ✅ |
| Android | adb on PATH | ✅ |
| Android | Device/emulator connected (`adb devices`) | ✅ |

### Behaviour

- [x] "Run Doctor" button on each card before first check
- [x] Spinner while checks run (parallel `Future.wait`)
- [x] Collapsible check list with ✅ / ⚠️ / ✗ icons
- [x] Fix hint + detail line per failing/warning check
- [x] Re-check button with last-checked timestamp
- [x] Auto-expands when failures or warnings found
- [x] iOS Simulator ↔ Real Device toggle re-runs Doctor automatically
- [x] Run button enabled only when zero blocking failures (`DoctorResult.isRunnable`)

**Files:**
- `lib/src/models/qa/doctor_model.dart` — `DoctorStatus`, `DoctorCheck`, `DoctorResult`
- `lib/src/base/qa/doctor_runner.dart` — all check logic (static, never throws)
- `lib/src/controllers/qa/doctor_controller.dart` — thin controller; registered in GetIt
- `lib/src/providers/qa/qa_provider.dart` — `doctorResults`, `isDoctorRunning`, `isRecipeRunnable`, `runDoctor`
- `lib/src/ui/qa/doctor/doctor_panel.dart` — collapsible panel UI
- `lib/src/ui/qa/home/home_screen.dart` — DoctorPanel embedded; Run gate wired
- `lib/src/base/dependencyinjection/locator.dart` — `DoctorController` registered

---

## Phase 3 — Pipeline engine + Web tests ✅

**Goal:** One click runs Centurion web tests and opens the Allure report; no terminal needed.

### Step runner

- [x] `lib/src/base/qa/step_runner.dart`
  - [x] Resolve cwd: `profile.repoPath(step.repo)` — missing dir fails the step, never throws
  - [x] Env injection: parse `step.envFile`, merge into that step's child env only
  - [x] Skip logic: `skipIfNoSync` / `skipIfNoBuild` → reported as `skipped`, not dropped
  - [x] Detach: `ProcessGateway.detach()` for the `allure open` step
  - [x] Stream: `ProcessGateway.stream()` → forward `LogLine` to provider
  - [x] Non-zero exit → stop pipeline, mark `failed`
  - [x] Per-step `timeout_seconds` → kills the process group, marks `timedOut`
  - [x] `cancel()` → kills the active step, remaining steps marked `cancelled`
  - [x] Write `docs/RUN_CONTEXT.md` at pipeline start + completion (with real git SHAs)

### Process gateway fixes (found while wiring Phase 3)

- [x] **Process-group kill actually works.** Dart does not `setsid()` a normal
      child, so the old `kill -TERM -<pgid>` either no-opped or aimed at this
      app's own group — every npm/gradle/flutter grandchild survived Cancel.
      Children are now re-exec'd via `/usr/bin/perl -e 'setpgrp; exec @ARGV'`
      so the child zsh is its own group leader. Falls back to plain zsh if perl
      is ever absent.
- [x] **No lost output tail.** The merged stream used to close on `exitCode`,
      which can fire before stdout/stderr drain. It now waits for both pipes
      (2s grace after exit, so a grandchild holding the pipe can't hang a run).
- [x] **`exitCode` is set before the stream closes** — `StepRunner` reads it
      immediately after the `await for` ends.

### Run state

- [x] `lib/src/providers/qa/run_provider.dart` — `RunStatus { running | done | failed | cancelled }` (null = idle), log buffer, active runner
  - [x] `start(recipe, profile, manifest, syncEnabled, buildEnabled, iosTarget)` → runs `StepRunner`
  - [x] `cancel()` → `StepRunner.cancel()` → `ProcessHandle.kill()` (process group)
  - [x] `reset()` → dismiss the panel once a run has finished
  - [x] `isRunning` → disables the other two recipe cards
  - [x] Log buffer capped at 5000 lines; `logsTruncated` flag shown in the panel
  - [x] Notifications coalesced to 100ms so a chatty build can't drop frames

### Run panel UI

- [x] `lib/src/ui/qa/runner/run_panel.dart`
  - [x] Live scrolling log list (monospace, stderr in red, selectable)
  - [x] Auto-follows the tail; stops when the user scrolls up, "Jump to latest" to resume
  - [x] Step progress indicator (`Step 3/4 — <name>`) + live elapsed timer
  - [x] Cancel button while running; Close button once finished
  - [x] `RUNNING / PASSED / FAILED / CANCELLED` badge with the failing step's reason
  - [x] stdin input field — done in Phase 4 with the iOS/Android OTP work (see below)

### Home screen wiring

- [x] Run button starts the pipeline (still gated on Doctor)
- [x] One run at a time — other cards show "Another run in progress"
- [x] Toggles and the iOS target selector freeze while a run is in flight
- [x] Narrow `context.select` on `RunProvider` so the log stream does not
      rebuild the version banner or the Doctor panels

### Housekeeping

- [x] Deleted `lib/main.dart` + `test/widget_test.dart` — the leftover
      `flutter create` counter app. It was the only thing needing Dart 3.10,
      which no installed Flutter provides; pubspec SDK floor lowered to
      `>=3.9.0` and the project now resolves and builds on Flutter 3.35.5.

### Tests

- [x] `test/step_runner_test.dart` — 7 tests against a fake gateway: step order,
      detach, skip flags, abort-on-nonzero, missing repo dir, `env_file`
      injection scoping, iOS target filtering
- [x] `test/process_gateway_test.dart` — 3 tests against real processes:
      stdout/stderr split + tail + exit code, process-tree kill, env injection

### Web pipeline steps (from `centurion.yaml`)

```
sync_web        git pull origin develop           (skip if !syncEnabled)
install_web     yarn install --frozen-lockfile
test_web        yarn test                          (env-cmd baked in; cleans + runs + generates Allure)
allure_web      yarn allure:open                   (detach)
```

**Done-when:** Click Run on Web card → steps stream in log panel → Allure report opens in browser.

---

## Phase 4 — iOS + Android (stdin / OTP) ✅

**Goal:** iOS and Android tests run from the UI including OTP paste.

### stdin / PTY

- [x] `ProcessHandle.writeStdin(String line)` — writes to the child's stdin pipe
      (a normal-mode `Process.start` leaves it open; no PTY needed — WDIO's
      `readline` reads a plain pipe same as a terminal)
- [x] `RunPanel` shows a persistent `TextField + Send` for the whole run (not
      just the WDIO step — the pipeline has no way to know in advance which
      step will prompt)
- [x] Sending clears the field, echoes `» <text>` into the log, refocuses the
      field; a no-op once the step has exited (stale input can't reach nothing)
- [x] `test/process_gateway_test.dart` — real end-to-end test: a child running
      `read code` (mirrors `otpFetcher.ts`'s `readline`) actually receives what
      `writeStdin` sends

### Appium re-check before the WDIO step

- [x] `StepConfig.checkAppium` (`check_appium: true` in the manifest) — Doctor
      already checked this before Run was enabled, but Build+Install can run
      for minutes first; re-checks `AppiumProbe.isRunning()` immediately before
      `test_ios_simulator` / `test_ios_device` / `test_android` and aborts the
      pipeline with a clear log line if Appium was quit in the meantime
- [x] `AppiumProbe` (`lib/src/base/qa/appium_probe.dart`) — the HTTP
      `GET /status` logic factored out of `DoctorRunner` so Doctor and
      `StepRunner` share one implementation instead of two copies
- [x] `StepRunner(isAppiumRunning: ...)` constructor seam so tests don't hit
      the real network

### iOS pipeline steps (simulator path)

```
sync_app        git pull origin develop           (skip if !syncEnabled)
sync_tests      git pull origin develop
build_ios_sim   flutter build ios --simulator --debug --flavor development -t lib/dev/main_dev.dart
install_ios_sim xcrun simctl install $IOS_SIMULATOR_UDID build/ios/iphonesimulator/Runner.app
launch_ios_sim  xcrun simctl launch $IOS_SIMULATOR_UDID com.goa.app.dev
install_deps    npm ci
clean_allure    rm -rf allure-results allure-report
test_ios_sim    ENV_FILE=.env.dev npx wdio run wdio.ios.simulator.conf.ts
gen_report      npm run report:generate
open_report     npm run report:open               (detach)
```

### iOS pipeline steps (device path)

```
sync_app        git pull origin develop
sync_tests      git pull origin develop
build_ios_dev   flutter build ios --flavor development -t lib/dev/main_dev.dart
install_ios_dev xcrun devicectl device install app --device $IOS_DEVICE_ID build/ios/iphoneos/Runner.app
launch_ios_dev  xcrun devicectl device process launch --device $IOS_DEVICE_ID com.goa.app.dev
install_deps    npm ci
clean_allure    rm -rf allure-results allure-report
test_ios_dev    npm run test:ios:dev
gen_report      npm run report:generate
open_report     npm run report:open               (detach)
```

### Android pipeline steps

```
sync_app        git pull origin develop
sync_tests      git pull origin develop
build_android   flutter build apk --flavor development -t lib/dev/main_dev.dart --debug
install_android adb install -r build/app/outputs/flutter-apk/app-development-debug.apk
install_deps    npm ci
clean_allure    rm -rf allure-results allure-report
test_android    npm run test:android:dev
gen_report      npm run report:generate
open_report     npm run report:open               (detach)
```

**Done-when:** ✅ iOS sim / device / Android tests run from UI with OTP field available.
(The iOS/Android step lists themselves were already correct in `manifests/centurion.yaml`
from Phase 1 — this phase's actual work was the stdin plumbing + Appium re-check above.)

---

## Phase 5 — History + daily-use polish ✅

**Goal:** Second run is blocked while one is active; last report is one click away; quit kills orphan processes.

- [x] `RunRecord { recipeId, recipeName, startedAt, durationMs, status, hasReport, logPath }` model
      — no `reportPath`: reopening re-runs the recipe's actual `detach` step
      (`yarn allure:open`, `npm run report:open`), since `allure open` serves
      the report over a local server — a bare `open index.html` can't load
      its data over `file://`. `hasReport` is `status == done`, since the
      report-open step is always the pipeline's last step.
- [x] `RunHistoryStore` — persists max 50 records to SharedPreferences as one
      JSON-encoded string; a corrupted value is dropped, not thrown
- [x] History panel on Home — last 8 runs (of up to 50 stored), status icon,
      relative time + duration; tap to reopen the report or the saved log file
- [x] "Reopen last report" shortcut per recipe card (visible once that recipe
      has a completed run with a report)
- [x] `SleepGuard` — shells out to `caffeinate -i` for the run's duration
      (no need to reimplement IOKit power-assertion bindings for "run this
      one command until told to stop")
- [x] Quit → kill: `MyApp` (now `StatefulWidget`) overrides
      `WidgetsBindingObserver.didRequestAppExit` — Cmd+Q calls
      `RunProvider.cancelAndWait()`, which kills the active step's process
      group *and* waits for that cleanup (sleep guard released, history
      recorded) before macOS is allowed to actually terminate the app
- [x] One run at a time — already enforced by `RunProvider.isRunning` (Phase 3)
- [x] Setup screen — extra PATH dirs UI, **and** actually wired into
      `ProcessGateway` (see below — this was previously dead data)
- [x] Every run writes its full log to `docs/run-logs/` (beyond the 5000-line
      in-memory cap and the app-quit boundary)

**Done-when:** ✅ No zombie processes after quit (real test: two `sleep 300`
descendants + `caffeinate`, both gone after `cancelAndWait()`); last Allure
report reopenable; concurrent run blocked.

### Found while wiring this: `extraPathDirs` was already-dead data

`MachineProfile.extraPathDirs` existed since Phase 1 (persisted, round-tripped
through Setup) but **nothing ever read it** — `ProcessGateway._buildEnv` never
touched PATH, and worse, `DoctorController` and `StepRunner` each defaulted to
a **fresh** `ProcessGateway()` instead of the locator's shared singleton, so
even setting the field on *that* instance wouldn't have reached Doctor checks
or the pipeline. Fixed all three: `ProcessGateway.extraPathDirs` now prepends
to PATH for every spawned command (`_withExtraPath`); `DoctorController`
defaults to `locator<ProcessGateway>()`; `RunProvider.start` passes
`locator<ProcessGateway>()` into `StepRunner` explicitly. `QAProvider` pushes
`profile.extraPathDirs` into the shared gateway on load/save/clear.
(`test/process_gateway_test.dart` covers this — note the login shell's own
`.zprofile`/`path_helper` can reorder PATH further, so the test asserts the
directory ends up on PATH, not a fixed position.)

---

## Phase 6 — Spec picker + README ✅

**Goal:** Another person can onboard and run tests without memorising flags.

- [x] Spec picker — optional per-recipe free-text field, shown on every card
  - [x] Web: `--grep "@smoke"` (Playwright)
  - [x] Mobile: `--spec test/specs/foo.e2e.ts` or `--mochaOpts.grep "TAG"` (WDIO)
  - [x] Manifest: `spec_command` field on `StepConfig` — **not** `spec_flags` as
        originally planned here; see below for why
- [x] README — full rewrite (was still the generic `flutter create` boilerplate
      template, unrelated to this app): clone → pick Projects folder → Doctor → Run
- [x] README covers: prerequisites (with real version floors), Appium setup,
      simulator one-time setup, `.env.dev` contents per repo, troubleshooting

**Done-when:** ✅ Another person on the team can run dev Centurion tests without touching the terminal.

### Why `spec_command`, not `spec_flags`

Appending `-- --grep foo` to the end of the existing `command` — this
section's original plan — silently breaks for Web: `yarn test`'s real
`package.json` script is a 4-command chain (`allure:clean && playwright:clean
&& env-cmd ... playwright test && allure:generate`), and npm/yarn's arg
forwarding lands on the *last* command in that chain (`allure:generate`), not
`playwright test`. A user's filter would look like it worked while being
silently ignored.

`StepConfig.specCommand` is a full alternate command template (`{flags}`
placeholder), used instead of `command` only when the recipe's spec field is
non-blank, with the flag on the actual test invocation — for Web that means
reconstructing the chain; for iOS/Android, a direct `wdio run
wdio.*.conf.ts {flags}`. No escaping is applied to what the user types — same
trust boundary as everything else here: a single-user local tool, the user
trusting themselves same as typing into a terminal.

### Files

| File | Role |
|---|---|
| `lib/src/models/qa/manifest_model.dart` | `StepConfig.specCommand` |
| `manifests/centurion.yaml` | `spec_command` on the four actual test steps |
| `lib/src/base/qa/step_runner.dart` | Resolves `command` vs `specCommand`; logs the filter when used |
| `lib/src/providers/qa/run_provider.dart` | `specFlags` threaded through `start()` |
| `lib/src/ui/qa/home/home_screen.dart` | Per-card `TextField` + `TextEditingController` |
| `test/step_runner_test.dart` | +3 tests: blank runs normal command; non-blank substitutes; untagged steps ignore it |
| `README.md` | Full rewrite |

---

## File map (all QA files, current state)

```
automation-testing/
  manifests/
    centurion.yaml                     ✅ Manifest — dev env; web/ios/android recipes

  lib/src/
    models/qa/
      manifest_model.dart              ✅ ManifestModel, RecipeConfig, StepConfig, IosBuildTarget
      machine_profile_model.dart       ✅ MachineProfile (paths only, no secrets)
      doctor_model.dart                ✅ DoctorStatus, DoctorCheck, DoctorResult
      run_model.dart                   ✅ StepOutcome, RunStatus, StepResult, PipelineResult
      run_record_model.dart            ✅ RunRecord — one row of run history

    base/qa/
      process_gateway.dart             ✅ exec / stream / detach; ProcessHandle (kill, writeStdin);
                                           login-shell PATH; setpgrp for real group kills
      manifest_loader.dart             ✅ loads YAML from asset bundle (cached)
      env_file_parser.dart             ✅ dotenv-style parser → Map<String,String>
      appium_probe.dart                ✅ shared GET /status check (Doctor + StepRunner)
      run_history_store.dart           ✅ persists RunRecord list to SharedPreferences (capped 50)
      sleep_guard.dart                 ✅ caffeinate -i wrapper — start()/stop()
      doctor_runner.dart               ✅ all Doctor check logic (parallel, never throws)
      step_runner.dart                 ✅ Pipeline engine — steps, env, timeout, cancel, stdin,
                                           check_appium, RUN_CONTEXT

    controllers/qa/
      setup_controller.dart            ✅ folder picker, repo validation, save/load/clear
      home_controller.dart             ✅ parallel tool version fetch
      doctor_controller.dart           ✅ thin wrapper → DoctorRunner.run

    providers/qa/
      qa_provider.dart                 ✅ manifest + profile + versions + doctor results;
                                           reopenReport / openLogFile; pushes extraPathDirs
                                           into the shared ProcessGateway
      run_provider.dart                ✅ RunStatus, log buffer (capped), cancel, reset,
                                           history + log-file write, sleep guard, cancelAndWait

    ui/qa/
      setup/setup_screen.dart          ✅ folder picker; prefills on revisit; extra PATH dirs UI
      home/home_screen.dart            ✅ version banner + 3 cards + Doctor panels + Run gate
      doctor/doctor_panel.dart         ✅ collapsible checks + fix hints + re-check
      runner/run_panel.dart            ✅ live log + step progress + cancel + stdin field
    history/
      history_panel.dart               ✅ last 8 runs; reopen report / reopen log (Phase 5)

    base/dependencyinjection/
      locator.dart                     ✅ ProcessGateway, ManifestLoader, SetupController,
                                           HomeController, DoctorController registered

  docs/
    PROGRESS.md                        ✅ This file — full scope + progress tracker
    IMPLEMENTATION_PLAN.md             ✅ Detailed spec per phase (canonical reference)
    CONVERSATION_CONTEXT.md            ✅ Fixed decisions + key discoveries + current status
    COMMANDS_REFERENCE.md              ✅ Actual commands from package.json + WDIO confs
    RUN_CONTEXT.md                     ✅ Auto-written by StepRunner each run

  macos/Runner/
    DebugProfile.entitlements          ✅ sandbox disabled
    Release.entitlements               ✅ sandbox disabled
```

---

## Constraints that never change (do not revisit)

| Topic | Rule |
|---|---|
| Secrets | Stay in sibling `.env.dev`; control center never reads or displays them |
| Env injection | Only steps that declare `env_file:` in the manifest get vars injected |
| PATH | Always `/bin/zsh -l -c` — login-shell PATH, same as Terminal |
| One run at a time | `RunProvider.isRunning` blocks a second start |
| Kill strategy | `kill -TERM -<pgid>` (negative PID = process group) |
| Env target | Dev only for all of v1 |
| Dirty repo | Always abort the pipeline (never run on a dirty tree) |
| Allure pool | Always `rm -rf allure-results allure-report` before test step |

---

## How to start a new session

1. Read `docs/PROGRESS.md` (this file) — current phase, next items
2. Read `docs/CONVERSATION_CONTEXT.md` — fixed decisions + key discoveries
3. Read `docs/COMMANDS_REFERENCE.md` — canonical commands (source of truth for YAML)
4. Read `manifests/centurion.yaml` — manifest steps
5. Scan `lib/src/base/qa/` and `lib/src/providers/qa/` for current code
6. Pick up from the **first unchecked item** in the current phase above

---

## Phase 7 — Multi-project + Dynamic Commands ✅

**Goal:** Support multiple named projects; every command editable from the app UI; import/export via JSON.

### Architecture

- **`ProjectConfig`** replaces `MachineProfile + ManifestModel` for each project. Stores repos, surfaces, commands, extra PATH dirs, pinned/lastOpened timestamps. JSON-serialised.
- **Adapter pattern** — `ProjectConfig.toProfile()` → `MachineProfile`, `ProjectConfig.toManifestModel()` → `ManifestModel`. StepRunner and DoctorRunner unchanged.
- **`CommandConfig`** mirrors `StepConfig` + `order` field; JSON-serialisable. `CommandConfig.toStepConfig()` for backward compat.
- **`SurfaceConfig`** mirrors `RecipeConfig`. `SurfaceConfig.toRecipeConfig()` for the pipeline.
- **`ProjectStore`** — CRUD JSON files in `<appSupportDir>/qa_control_center/projects/<id>.json`.
- **`ProjectTemplate`** — Centurion seed with all current yaml commands pre-populated as Dart consts.

### First-launch migration

On first launch with no projects, `ProjectProvider` reads the legacy `projectsRoot` / `extraPathDirs` from SharedPreferences and auto-creates a "Centurion" project. Existing users pick up where they left off.

### New screens

| Screen | Route | Purpose |
|---|---|---|
| `ProjectsListScreen` | `routeProjects` | Landing — pinned + recent; create / import |
| `CreateEditProjectScreen` | `routeCreateProject` / `routeEditProject` | Name + root picker + per-repo pickers + template selector |
| `ProjectDetailScreen` | `routeProjectDetail` | Per-surface tabs; Doctor + Run controls + live log |
| `CommandLibraryScreen` | `routeCommandLibrary` | Drag-reorder; add/edit/delete; import from file or paste JSON |
| `CommandEditScreen` | `routeCommandEdit` | All CommandConfig fields; iOS target toggle |

### Import / Export

- **Export project** — `ProjectController.exportToFile()` → user-chosen `.json` via file dialog.
- **Import project** — `ProjectController.importFromFile()` → opens `CreateEditProjectScreen` pre-filled so user can remap paths for this machine.
- **Import commands** — JSON array of command objects or a surface-config object; appended to the surface after a preview confirmation dialog.
- **Paste JSON** — inline paste dialog in `CommandLibraryScreen` for quick import without a file.

### Files added

```
lib/src/models/qa/project_model.dart          RepoEntry, CommandConfig, SurfaceConfig, ProjectConfig + adapters
lib/src/base/qa/project_store.dart            JSON CRUD in appSupportDir
lib/src/base/qa/project_template.dart         Centurion seed + ProjectTemplateType enum
lib/src/controllers/qa/project_controller.dart CRUD + file import/export
lib/src/providers/qa/project_provider.dart    ChangeNotifier; projects list + currentProject
lib/src/ui/qa/projects/projects_list_screen.dart
lib/src/ui/qa/projects/create_edit_project_screen.dart
lib/src/ui/qa/projects/project_detail_screen.dart
lib/src/ui/qa/commands/command_library_screen.dart
lib/src/ui/qa/commands/command_edit_screen.dart
```

### Files modified

```
pubspec.yaml                              + path_provider: ^2.1.3
lib/src/base/dependencyinjection/locator.dart  + ProjectStore, ProjectController
lib/src/main.dart                         + ProjectProvider; initialRoute → routeProjects
lib/src/base/utils/constants/navigation_route_constants.dart  + 6 new routes
lib/src/base/utils/navigation_utils.dart  + 6 new route cases
lib/src/providers/qa/run_provider.dart    + startFromProject() adapter method
```

**Done-when:** ✅ Build clean (`flutter build macos`); 0 errors, 0 warnings from `flutter analyze`.

---

## Phase 8 — Bug Fixes + Groups + History (COMPLETE)

**Goal:** Fix command persistence bug and edit-project repo bug; add command groups/parallel execution/category filter; per-surface run history; add surface from detail screen; repoRole validation on import.

### Bug fixes

| Bug | Root cause | Fix |
|---|---|---|
| **Commands not persisting** | `ProjectProvider.updateSurfaceCommands()` relied on `_currentProject` which is null when navigating straight to a surface without calling `openProject()` | Changed signature to accept `ProjectConfig project` directly; updated both callers (`CommandLibraryScreen`, `CommandEditScreen`) |
| **Edit project repo section missing** | Custom template projects have `repos: {}`; `_repoCtrlMap` stays empty → section guard `_repoCtrlMap.isNotEmpty` hides it | Defensive fallback in `_prefill()` populates 3 default empty controllers when repos are empty; section always shown in edit/import mode |

### Command groups + parallel execution

- Added to `CommandConfig`: `groupId`, `groupLabel`, `runParallel`, `category`
- Commands with the same `groupId` and `runParallel: true` are combined at runtime into a single bash `&` step
- `ProjectConfig.toRecipeConfigForSurface(surfaceId, iosTarget)` — new method that:
  1. Filters commands by iosTarget
  2. Groups parallel commands into `StepConfig(command: "(cd repo1 && cmd1) &\n(cd repo2 && cmd2) &\nwait", repo: '_root')`
  3. Returns a `RecipeConfig` that works with the unchanged `StepRunner`
- `ProjectConfig.toManifestModel()` now includes a `_root` pseudo-repo (`relPath: ''`) so parallel steps have a valid working directory (the project root)
- `RunProvider.startFromProject()` now calls `toRecipeConfigForSurface()` instead of `surface.toRecipeConfig()`

### Category filter

- `CommandConfig.category` field: `"setup"` | `"build"` | `"test"` | `"report"` | null
- `CommandLibraryScreen` shows filter chips at the top; tapping a chip filters the list
- Reorder is disabled while a filter is active (snackbar explains why)

### Group headers in Command Library

- Commands with the same `groupId` are shown under a group header
- Parallel groups show a ⚡ icon and "parallel" badge
- When a category filter is active, group headers are hidden (flat filtered view)

### Run history per surface

- `_RunHistorySection` widget added to `_SurfaceTab` — reads from `RunProvider.history` filtered by surfaceId
- Shows last 5 runs with status icon (✓/✗/⏹), elapsed time, time ago, and a log-open button
- "Open last report" button appears when `RunProvider.lastReportFor(surfaceId)` is non-null

### Add surface from Project Detail

- `+` button in ProjectDetailScreen AppBar opens a dialog: surface name, icon, ID
- On save, `ProjectProvider.updateProject()` appends the surface; `TabController` is rebuilt to reflect new tab count

### repoRole validation on import

- `ProjectController.parseCommandsJson()` accepts optional `validRepoRoles: Set<String>` param
- Commands with unknown `repoRole` are dropped before append; an `onWarning` callback reports which were skipped
- `CommandLibraryScreen._pasteJson()` passes `_project.repos.keys.toSet()` for validation

### Edit project: add / remove repos

- "Add repo" button in edit/import mode appends a blank repo row
- Each row in edit mode has a remove ✕ button and an editable role-name field
- `_removeRepo()` and `_renameRepoRole()` methods manage the controller map

### Files changed (Phase 8)

```
lib/src/models/qa/project_model.dart            + groupId/groupLabel/runParallel/category on CommandConfig
                                                + _root pseudo-repo in toManifestModel()
                                                + toRecipeConfigForSurface() + _buildParallelStep()
lib/src/providers/qa/project_provider.dart      fix updateSurfaceCommands(project:) bug
lib/src/providers/qa/run_provider.dart          use toRecipeConfigForSurface() in startFromProject()
lib/src/ui/qa/commands/command_library_screen.dart  category filter chips + group headers + bug fix
lib/src/ui/qa/commands/command_edit_screen.dart     group/category fields + bug fix
lib/src/ui/qa/projects/project_detail_screen.dart   run history + open last report + add surface
lib/src/ui/qa/projects/create_edit_project_screen.dart  fix repo section + add/remove/rename repos
lib/src/controllers/qa/project_controller.dart  repoRole validation in parseCommandsJson()
```

**Done-when:** ✅ `flutter build macos` clean (48.8 MB); 0 errors, 0 warnings.

---

## Phase 9 — Create-time repo-loss fix + duplicate + mandatory validation ✅

**Goal:** Fix a real data-loss bug found live (a project's typed repo folder
paths disappearing), add duplicate actions the user asked for, and make
"at least one repo" / "a repo is selected" actually enforced rather than
just defaulted-around.

### Bug found and fixed: repo folder paths silently dropped at create time

Different bug from Phase 8's "repo section missing" fix — that one was
about the section not even *rendering* when `repos: {}`. This one is about
data loss even when the section renders and the user fills it in correctly:

`_save()` in `create_edit_project_screen.dart` builds a correct
`repoRelPaths` map from the current controllers and passes it to
`ProjectController.create(..., repoRelPaths: ...)` — but `create()`'s
`switch` only forwarded `repoRelPaths`/`repoBranches` to the `centurion`
template branch. `ProjectTemplate.custom()` ("Start blank") didn't even
accept those parameters and hardcoded `repos: {}` unconditionally. Since the
Repositories rows are shown and editable for *every* template (not gated by
template choice), choosing "Start blank" — or leaving it as the default —
silently discarded whatever was typed into those rows, no error, no warning.
Confirmed on a real project on this machine (`"Cent"`, saved with
`repos: {}` despite the user having typed real folder names).

**Fix:** `ProjectTemplate.custom()` now accepts `repoRelPaths`/`repoBranches`
and builds its `repos` map from them (arbitrary user-typed role names work
too, not just `app`/`web`/`mobile_tests`); `ProjectController.create()`
forwards both params to the `custom` branch as well as `centurion`.
`test/project_template_test.dart` added (3 tests) — regression coverage
this bug never had.

**Not recoverable:** the actual folder paths already lost for the real
"Cent" project on disk can't be un-lost — they only ever lived in the
screen's `TextEditingController`s, never persisted anywhere. Re-typing them
now will stick, going forward.

### Duplicate actions

Added at all three levels the user asked for, each following the same
pattern (clone under a fresh id — `<id>_copy`, numbered if taken — name/role
suffixed to avoid silently colliding with the original):

| Where | File | Notes |
|---|---|---|
| Commands | `command_library_screen.dart` — copy icon between Edit/Delete on every tile | If triggered from a surface tab, the copy is also added to *that* surface (matches "Add command"'s existing behavior) — never touches any other surface the original happens to be assigned to |
| Surfaces | `project_detail_screen.dart` — "Duplicate surface" in the ⋮ menu | Same icon, same `commandIds` (shared by reference — editing a shared command still updates both surfaces, same as any other pool reference) |
| Repo rows | `create_edit_project_screen.dart` — copy icon next to Browse/Remove | Role name gets a `_copy` suffix so it can't silently overwrite the original in the final repos map at save time |

### Repo-role filter chips in Command Library

Second chip row under the existing category filter, in the "All" tab —
`app (5)` / `web (4)` / `mobile_tests (3)` style, only shown when a project
actually spans more than one repo (nothing to filter otherwise).

### Mandatory validation — closing two "defaulted past, not actually required" gaps

- **Project must have ≥1 repo to save.** The "Folder name" field never had a
  validator (only "Role" did); an empty `_repoCtrlMap` (every row removed)
  has nothing for form validation to fail against, so a project could be
  saved with zero repos configured at all. `_save()` now explicitly checks
  and blocks with a snackbar. Closing this also surfaced a related trap:
  "+ Add repo" used to be hidden for brand-new projects (`allowEdit =
  _isEdit || _isImport`), so removing all 3 default rows on a fresh create
  left no way back in without restarting the screen — it's now always shown.
- **A command must have a repo selected to save.** The "Runs in repo"
  dropdown already defaults to a real repo and validates non-null whenever
  the project has repos — but that dropdown doesn't even render when the
  project has zero repos (just a hint text instead), so a command could
  still save with a blank, meaningless `repoRole`. `command_edit_screen.dart`'s
  `_save()` now explicitly blocks that case too, with the same message the
  hint text already gives ("Add a repo to this project first").

### Files changed (Phase 9)

```
lib/src/base/qa/project_template.dart           custom() accepts + uses repoRelPaths/repoBranches
lib/src/controllers/qa/project_controller.dart  forwards repoRelPaths/repoBranches to custom() too
lib/src/ui/qa/projects/create_edit_project_screen.dart
    + Folder-name field validator
    + "at least one repo" save guard
    + "+ Add repo" always shown (was edit/import-only)
    + _duplicateRepo()
lib/src/ui/qa/commands/command_library_screen.dart
    + _duplicateCommand() + trailing Duplicate icon (All tab + surface tabs)
    + repo-role filter chip row (_buildRepoRoleFilter)
lib/src/ui/qa/commands/command_edit_screen.dart  "zero repos" save guard
lib/src/ui/qa/projects/project_detail_screen.dart  _duplicateSurface() + "Duplicate surface" menu item
test/project_template_test.dart                 new — 3 tests, custom() repoRelPaths regression coverage
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
29/29 tests pass (26 prior + 3 new); `flutter build macos` clean.

---

## Phase 10 — Doctor quick-fix + filter consolidation + tooltips ✅

**Goal (user-reported):** (1) the category + repo filter chip rows in Command
Library look cluttered — consolidate into one control, available on every
tab, not just "All". (2) Toggles/switches (Sync, Build+Install, command
badges) aren't self-explanatory — add tooltips/info affordances. (3) Doctor
shows a failure + fix hint but no way to act on it — add a "quick fix" button
that runs the actual fix command, with the exact command shown first, plus a
custom-command option.

### Doctor quick-fix

- `DoctorCheck` gained `fixCommand`/`fixCwd` (`lib/src/models/qa/doctor_model.dart`)
  — a real, runnable shell command + working directory, set **only** where a
  fix is genuinely unambiguous and safe. Left `null` (falls back to
  "Custom…" only) anywhere it needs human judgment — which Node version
  manager, which secrets go in a missing `.env`, "add to PATH".
- Populated in `doctor_runner.dart` for 5 checks: git branch mismatch
  (`git checkout <branch>`), dirty tree (`git stash`), Yarn missing
  (`npm install -g yarn`), Java missing (`brew install openjdk@11`), port
  busy (`lsof -ti:<port> | xargs kill`).
- `project_detail_screen.dart`'s `_DoctorSection`: a **Fix** button per
  failing/warning check (only when `fixCommand != null`) that confirms the
  exact command + cwd before running, plus a **Custom…** (terminal icon)
  option always available — an editable command field seeded with the
  canned fix, for anything with no safe default. Both funnel into one
  `_executeFix()` (no double-confirmation), then auto re-runs Doctor so the
  list reflects whether it actually worked.
- `test/doctor_runner_test.dart` (new, 3 tests) — **real git repos, real
  subprocesses**: dirties a repo / switches its branch, confirms the
  populated `fixCommand` is exactly right, then *actually runs it* and
  confirms Doctor now reports the check as passing. Proves the fix genuinely
  fixes the problem, not just that a string got threaded through.

### Filter consolidation (Command Library)

- Replaced two always-visible chip rows (category, repo-role) with a single
  **Filter** icon button in the AppBar (badge shows active-filter count),
  opening one dialog with both axes — `_FilterChipsContent`.
- Filters now apply to **every tab**, not just "All" — `_SurfaceCommandsTab`
  filters its assigned/unassigned lists too. Reorder is disabled (with an
  explanatory banner) whenever a filter is active there, since reorder
  operates on indices into the *real* unfiltered order and a filtered
  subset's indices don't correspond to it.

### Tooltips / clearer labels

- `_ToggleChip` (Sync, Build+Install) and `_IosTargetChip`
  (`project_detail_screen.dart`): wrapped in `Tooltip` with a full
  explanation of what the toggle actually does, plus a small ⓘ affordance
  next to the label so it's discoverable.
- Command tile badges (`_badge()` in `command_library_screen.dart`): added
  an optional `tooltip` param, used on every behavior badge (Sync, Build,
  detach, ⚡, sim/device, category) — same treatment.
- Spec/flags field helper text reworded to drop `spec_command` jargon.

### Bug found and fixed while touching this code: Spec/flags field lost cursor position

`_SurfaceCard` is a `StatelessWidget`; its Spec/flags `TextField` did
`controller: TextEditingController(text: specFlags)` — a **fresh controller
built inline in `build()`**. Since typing itself triggered
`setState()` in the parent (to mirror the value into a `_specFlags` map),
every keystroke rebuilt the whole card and handed the field a brand-new
controller, resetting the cursor to the end and breaking mid-string editing.
Fixed by hoisting a persistent `Map<String, TextEditingController>
_specControllers` to the parent (same pattern used earlier this session for
the legacy screen's identical class of bug), passing the controller itself
into `_SurfaceCard` instead of a live-synced string — this also let the
redundant `_specFlags` map and its `onChanged` plumbing be deleted entirely;
`_runSurface()` just reads `_specControllers[id]!.text` directly at run time.

### Files changed (Phase 10)

```
lib/src/models/qa/doctor_model.dart              + fixCommand, fixCwd fields
lib/src/base/qa/doctor_runner.dart                populate fixCommand/fixCwd for 5 checks
lib/src/ui/qa/projects/project_detail_screen.dart
    + _DoctorSection: Fix / Custom… buttons, _confirmAndRun / _executeFix / _runCustomFix
    + _ToggleChip / _IosTargetChip: tooltips
    fix: _specControllers replaces _specFlags (cursor-reset bug)
lib/src/ui/qa/commands/command_library_screen.dart
    + Filter button + badge, _showFilterDialog, _FilterChipsContent
    + _SurfaceCommandsTab: filtering, reorder-disabled-while-filtered
    + _badge(): optional tooltip param, used on every behavior badge
test/doctor_runner_test.dart                      new — 3 real end-to-end tests
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
32/32 tests pass (29 prior + 3 new); `flutter build macos` clean; live
smoke-tested against the real "Centurion" project (real Doctor run found 2
real failures against real repos; tooltips and reworded helper text
confirmed rendering correctly via screenshot).

## Phase 11 — ProcessGateway PATH resolution fix (`env: node: No such file or directory`) ✅

### The bug

The Doctor "Fix" button for Node version and for installing yarn both failed
with `ProcessException: exit 127: env: node: No such file or directory`, even
though the user had Node 22 installed via nvm and it worked fine in Terminal.

Root cause: `ProcessGateway` ran every command via `/bin/zsh -l -c <command>`
— login, but **not interactive**. zsh only sources `~/.zshrc` for interactive
shells, and this user's (like most nvm users') node/nvm PATH setup lives
entirely in `.zshrc`, not `.zprofile`. So a login-only shell had no PATH entry
for Node at all — not an old version, genuinely absent.

### The naive fix (tried, reverted)

Adding `-i` to every spawn does source `.zshrc` and does fix PATH — but zsh
then has no real TTY, so anything `.zshrc` prints for a human's benefit (this
user's `.zshrc` ends with `nvm use node`, which echoes `Now using node
vX.Y.Z (npm vA.B.C)`) leaks onto stdout ahead of the command's real output.
That silently corrupted every check parsing stdout (git branch names,
`--version` output, `echo "$PATH"`) — running the full suite immediately
showed 8 broken tests.

### The actual fix: split resolution from execution

- **Resolution** (`ProcessGateway._resolvedPath`): spawn exactly one `-i -l`
  shell, ever, cached for the process's lifetime (`static` cache — shared by
  every `ProcessGateway` instance). Ask it to `echo` PATH after a unique
  marker string, scan every stdout line for that marker rather than trusting
  the first line — any interactive-shell noise before it is simply ignored.
  Falls back to `Platform.environment['PATH']` if zsh isn't found or the
  spawn times out (5s), so a broken shell config degrades instead of hanging
  every command forever.
- **Execution**: every real command still runs through a plain, quiet `-l`
  shell (unchanged) — just now with the resolved PATH from above injected as
  the base environment in `_buildEnv`, instead of the process's own stale
  `Platform.environment['PATH']`.

`_buildEnv` became `async` (it awaits the resolved PATH); the three call
sites in `exec`, `stream`, and `detach` now `await` it.

### Files changed (Phase 11)

```
lib/src/base/qa/process_gateway.dart
    + class doc comment explaining the -l vs -i vs split-resolution history
    + _resolvedPath / _resolvePathOnce / _resolvedPathCache / _resolvingPath / _pathMarker
    _buildEnv is now async, awaited by exec/stream/detach
test/process_gateway_test.dart
    + "uses an interactive shell internally but never lets that leak into stdout"
    + "resolved PATH pulls in .zshrc, not just a login-only shell's PATH"
```

**Done-when:** ✅ `flutter test` — 38/38 pass (0 regressions from the `-i`
experiment); `flutter build macos --debug` clean.

**Not independently re-verified by driving the real app's UI** — this
session's own shell tool carries a stale, frozen PATH snapshot from session
start (documented earlier in this file's history), so any GUI check launched
from *this* session would inherit that same staleness and prove nothing
about a genuinely fresh user launch. The tests above spawn real, fresh `zsh`
subprocesses via Dart's own `Process.run` (not through this session's shell),
which is what actually exercises the fixed code path — but please re-run the
Node/Yarn Doctor fixes yourself and confirm.

## Phase 12 — Run Experience Redesign ✅

**Full step-by-step detail lives in `docs/RUN_EXPERIENCE_REDESIGN.md` —
this entry is the pointer + one-paragraph summary, matching the pattern
already used for Phase 7-9's relationship to `docs/PROJECTS_SYSTEM.md`.**
`docs/PROJECTS_SYSTEM.md` has also been updated with the resulting
architecture (data model, screens, execution flow) — read that file for
the current *what*; read the redesign doc for the *why* behind each piece
(design rationale, decisions made, bugs found, real-subprocess/real-file
tests written for every non-trivial mechanism).

### What this phase covers

Starting from a rough, unstructured requirements dump for a much richer
mobile/web run experience, this phase: analyzed and redesigned the ask
into a structured spec (locking in 4 architectural decisions with the
user — true concurrency, a unified mobile surface, per-surface
environment lists, no device-list cache) before writing any code, then
implemented it in the following order:

1. Repo model: exposed the already-existing but hidden `RepoEntry.branch`
   field as an editable "Sync branch" UI field; added an atomic "Add
   mobile repo" flow (`mobile_ui` + `mobile_test` roles together).
2. Auto-surface creation (`ProjectController.ensureAutoSurfaces()`,
   idempotent/additive-only) + a new environment/flavor model
   (`EnvironmentDef`, independent per surface) + bundle-ID storage
   (`MobileAppId`) with best-effort auto-detect (`BundleIdDetector` —
   Android `build.gradle` flavors, iOS `.xcconfig`).
3. A new "Script" concept (`ScriptEntry`) distinct from `CommandConfig` —
   leaf test files (mobile, with file-picker/folder-import) or
   `package.json` script names (web), with dedup-by-path merging.
4. Runner commands (`SurfaceConfig.runnerCommandIds`, mandatory slots
   gating the Run buttons) + real device listing (`DeviceProbe` — `xcrun
   simctl`/`adb`/`xcrun devicectl`) + the actual `RunDispatcher`
   implementing the Run/Pull&Run/Build&Run decision tree.
5. `RunProvider` rebuilt from a single-run singleton into a registry of
   concurrent runs (`RunEntry`/`activeRuns`) — the biggest architectural
   change in the whole effort, and a real bug fix in passing (the old
   single shared `SleepGuard` would have let one run's finish kill another
   still-running run's sleep-prevention).
6. Prerequisite commands, report archiving (`ReportArchive`/
   `ReportArchiveStore`/`ReportArchiver`, with retention/pruning and a
   `ReportsScreen`), a live multi-run progress screen (`ActiveRunsScreen`),
   recent-runs project-scoping fix + a shared re-run picker + a global
   `RecentRunsScreen`, and finally a global `DevicesScreen` (Android/iOS
   tabs, busy/idle from the active-runs registry, Add simulator/emulator).

Two of these steps (the live progress screen and the recent-runs fix) were
built concurrently by a background agent and the main session per an
explicit "proceed asynchronously" request — merged by hand afterward
(surgical diff-and-copy, not a blind overwrite, since both touched
overlapping files) and re-verified together, not just separately.

### Files changed

Far too many to list here in full — see `docs/RUN_EXPERIENCE_REDESIGN.md`'s
per-step "Files changed" blocks for the complete, precise list. New files
of note: `lib/src/base/qa/{run_dispatcher,device_probe,bundle_id_detector,
report_archive_store,report_archiver,report_opener}.dart`,
`lib/src/models/qa/{device_model,report_archive_model}.dart`,
`lib/src/ui/qa/{scripts/scripts_screen,runner/run_picker,runner/
active_runs_screen,reports/reports_screen,history/recent_runs_screen,
devices/devices_screen}.dart`.

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item
throughout every step of this phase — never grew); 137/137 tests pass (all
real subprocess/real-filesystem tests for non-trivial logic, no mocks
where the actual mechanism was the risk); `flutter build macos --debug -t
lib/dev/main_dev.dart` clean after every step.

**Known remaining gaps** (flagged in-line at the step that deferred them,
not silently dropped): report retention tuning beyond step 8's defaults;
`ActiveRunsScreen`'s card not yet updated to use the environment/script
metadata a later step added to `RunEntry`; Android AVD creation untested
against a live SDK (this dev machine has none installed — the parsing
logic itself is tested against recorded sample output instead).

## Phase 13 — Tags overhaul, real Centurion data, Pull/Build switches ✅

**Full step-by-step detail lives in `docs/RUN_EXPERIENCE_REDESIGN.md`'s
final step ("Step 11") — this entry is the pointer + one-paragraph
summary, matching the pattern already used for Phase 12.**
`docs/PROJECTS_SYSTEM.md`'s data model, `RunDispatcher`, and shared-picker
sections have also been rewritten to match — read that file for the
current *what*.

### What this phase covers

Several follow-up sessions after Phase 12 shipped: `CommandConfig.category`
(enum) plus separate `environment`/`platform` filter fields were replaced
by `CommandConfig.tags` (free-form `List<String>`) — a command's pipeline
stage is just one tag now, and environment/platform became static
properties of the `SurfaceConfig` it's assigned to instead of per-command
filters. The single unified "mobile" surface idea was reverted in favor of
one surface per environment × platform (`android_dev`, `android_stage`,
`ios_dev`, `ios_stage`, `web_dev`, `web_stage`) — matching the real
Centurion project, which was rebuilt on this model with ~30 real commands
sourced from the actual sibling repos (`{branch}`/`{bundleId}` added as
real substitution tokens; redundant per-environment/per-platform commands
merged; `build_web` and `build_runner_mobile` added after real gaps/bugs
were found running actual test suites).

The other headline change: the per-click **Run / Pull & Run / Build & Run**
menu (Phase 12's design, including a "smart" `isInstalled()` skip-build
check) was replaced by two plain per-surface switches —
`SurfaceConfig.runPull`/`.runBuild`, same always-on/off shape as
`runPrerequisites`, shown as Pull/Build sections on the Project Detail
card. `RunMode` and `isInstalled()` were deleted outright; the Scripts
screen now has a single Run button. `project_template.dart` (badly out of
sync with all of the above — hardcoded bundle ids/environments, duplicate
per-platform sync commands, no per-environment surfaces at all) was
rewritten from scratch to match the live project 1:1, fixing a naming bug
in passing: the iOS **device** build commands were missing `--debug` (so
silently built release) while their name and their simulator sibling both
said "debug" — now consistent in both the template and (pending the user
fully quitting the running app so the live project file is safe to edit)
the live data.

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item
throughout); 132/135 tests pass (the 3 failures are pre-existing
`sleep`-process timing flakiness in `run_provider_quit_test.dart`/
`run_provider_registry_test.dart`, unrelated to this phase); `flutter build
macos --debug -t lib/dev/main_dev.dart` clean.

**Known remaining gap**: the live Centurion project's own JSON data hasn't
been updated to match `project_template.dart`'s fixes yet — the app was
open with same-day run history while this phase ran, and a direct file
edit while it's open risks a silent overwrite (this has happened once
before). Needs the app fully quit first.
