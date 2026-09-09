# Conversation Context — QA Control Center

Decisions, constraints, and discoveries accumulated across sessions.
A future Claude session should read this + PROGRESS.md before touching any code.

> **Primary progress tracker → [`PROGRESS.md`](./PROGRESS.md)**  
> This file holds fixed decisions and key discoveries. PROGRESS.md holds the full scope checklist.

**Last updated:** Phase 9 complete — see that section below. Also read
[`PROJECTS_SYSTEM.md`](./PROJECTS_SYSTEM.md), a later code-verified pass
covering what evolved after this file's Phase 7 note was written (notably:
`SurfaceConfig` now references a shared command **pool** by id, from Phase
8 — documented in `PROGRESS.md`'s Phase 8 section but not backfilled here)
plus gaps found along the way that weren't written down anywhere yet.

---

## What this repo is

`automation-testing` is our **Flutter desktop (macOS) app** — the QA Control Center.
It is **not** a clone of Centurion. It shells out to the Centurion sibling repos.

| Repo | Role |
|---|---|
| `automation-testing` | **This repo.** The macOS control-center UI. |
| `crichq-app-flutter` | Centurion Flutter mobile app. We build + install it (optional). |
| `crichq-webapp-nextjs` | Centurion Next.js web app. Playwright lives here. |
| `centurion-app-automation-tests-ts` | WDIO mobile test suite. npm-based. |

---

## Fixed decisions (do not revisit)

| Topic | Decision |
|---|---|
| Platform | Flutter **macOS desktop**, unsandboxed (needs `Process.start`, shell access) |
| Run command for this app | `flutter run -d macos -t lib/dev/main_dev.dart` (no `--flavor`; macOS has one build config in v1) |
| Test environment | **Dev only** for all of v1. Stage/prod are post-v1. |
| Auth in the control center | None. Boilerplate login/Dio kept but unused by QA flows. |
| PATH | Always use `/bin/zsh -l -c` to get login-shell PATH (same as Terminal) |
| Node orchestrator | None. `dart:io Process` is the privileged layer. |
| State persistence | `SharedPreferences` for machine profile (Projects root path). |
| Manifest format | YAML bundled as Flutter asset — `manifests/centurion.yaml`. |
| Env secrets | Stay in sibling repo `.env.dev` files. The control center never reads or stores them. |
| Env injection | Only steps that declare `env_file:` in the manifest get vars injected. |
| Dirty git | Abort the pipeline. |
| One run at a time | Enforced in `RunProvider.isRunning`. |
| Process kill | `kill -TERM -<pgid>` via `ProcessHandle`. Requires the child to be its own group leader — `ProcessGateway` re-execs through `/usr/bin/perl -e 'setpgrp; exec @ARGV'` because Dart does not `setsid()` a normal child. |
| Allure pool | Always `rm -rf allure-results allure-report` before test step. |

---

## Key discoveries (from actual package.json + setup notes)

### Web (`crichq-webapp-nextjs`)
- Package manager: **yarn**
- `yarn test` is the single entry point — it already does: `allure:clean` → `playwright:clean` → `playwright test` (with `env-cmd .env.dev .env.test`) → `allure:generate`
- Do **not** add separate clean or generate steps — `yarn test` handles everything
- Allure report lands in `allure-report/`; opened with `yarn allure:open`

### Mobile tests (`centurion-app-automation-tests-ts`)
- Package manager: **npm** (Node ≥ 20)
- Test commands: `npm run test:ios:dev` / `npm run test:android:dev`
  - Both resolve to `ENV_FILE=.env.dev wdio run wdio.{ios,android}.conf.ts`
- Allure: NOT automatic — separate steps: `npm run report:generate` then `npm run report:open`
  - `report:generate` = `allure generate --clean allure-results -o allure-report`
- **Allure shared pool**: `allure-results/` accumulates across runs. Our fix: always `rm -rf allure-results allure-report` before the test step → pool is single-run → generate directly.
- **OTP**: WDIO blocks on `readline` stdin waiting for a human to paste an OTP code.
  The pipeline engine must pipe the UI stdin field to the child process PTY (Phase 4).
- **Appium**: Must be running on `localhost:4723` before WDIO runs. Not auto-started.
  Doctor checks `GET http://localhost:4723/status` (Phase 2). ✅

### iOS — TWO WDIO configs, TWO target types

`wdio.ios.simulator.conf.ts` and `wdio.ios.conf.ts` are **deliberately separate files** —
they have different Appium capability shapes (signing, udid source, WDA setup).

| | Simulator | Real Device |
|---|---|---|
| WDIO config | `wdio.ios.simulator.conf.ts` | `wdio.ios.conf.ts` |
| UDID env var | `IOS_SIMULATOR_UDID` | `IOS_DEVICE_ID` |
| npm script | none — use `npx wdio` directly | `npm run test:ios:dev` |
| Build artifact | `iphonesimulator/Runner.app` | `iphoneos/Runner.app` |
| Install tool | `xcrun simctl install` | `xcrun devicectl device install app` |
| Launch tool | `xcrun simctl launch` | `xcrun devicectl device process launch` |
| Code signing | ❌ not needed | ✅ `IOS_XCODE_ORG_ID` + `IOS_XCODE_SIGNING_IDENTITY` required |
| Flutter build flags | `--simulator --debug` | (none extra) |

All UDID / signing vars come from `centurion-app-automation-tests-ts/.env.dev`.
The control center never reads or stores them — injected via `env_file:` in the manifest.

### Android build + install
- Build: `flutter build apk --flavor development -t lib/dev/main_dev.dart --debug`
- APK path: `build/app/outputs/flutter-apk/app-development-debug.apk`
- Install: `adb install -r <apk_path>`

### iOS target filter in manifest

Steps in the iOS recipe have a `target: simulator | device` tag. The step runner
(`RecipeConfig.stepsFor(iosTarget: …)`) filters steps to only the matching target before
executing them. Steps with no `target` tag run for both. This is how the pipeline handles
`xcrun simctl` vs `xcrun devicectl` without branching in Dart.

The `IosBuildTarget` enum lives in `manifest_model.dart`. The home screen exposes a
`SegmentedButton` on the iOS recipe card; selection is held in `_HomeScreenState._iosTarget`.

### env_file injection (manifest → pipeline engine)
Steps that need vars from a sibling repo's `.env.dev` declare `env_file: <repo>/.env.dev`.
The pipeline engine resolves the absolute path (`projectsRoot/rel_path/.env.dev`), parses it,
and merges those vars into the step's environment. This is how `IOS_SIMULATOR_UDID` reaches
`xcrun simctl install` without hardcoding it anywhere in Dart.

---

## Phase 3 discoveries

### Dart never puts a child in its own process group

`Process.start` only calls `setsid()` for `ProcessStartMode.detached*`. In normal
mode the child inherits *our* process group, so the documented
`kill -TERM -<pgid>` was either a silent no-op (no group has that pgid) or a
signal aimed at the control center itself — and every npm / gradle / flutter
grandchild survived Cancel. Fix: `ProcessGateway` spawns
`/usr/bin/perl -e 'setpgrp; exec @ARGV' /bin/zsh -l -c <cmd>`, making the child
zsh a group leader (pgid == pid). Verified in `test/process_gateway_test.dart` —
three `sleep` descendants, zero survivors after `kill()`.

`exec` skips the wrapper (short-lived, awaited, never killed) and `detach`
skips it too (`ProcessStartMode.detached` already calls `setsid`).

### Closing a merged output stream on `exitCode` loses the tail

`process.exitCode` can complete before stdout/stderr finish draining, so the
last lines of a step were being dropped. The stream now waits for both pipes,
with a 2s grace period after exit so a grandchild that inherited stdout and
never closes it cannot hang a run forever. `handle.exitCode` is set before the
stream closes, which is what `StepRunner` relies on.

### The repo shipped a leftover `flutter create` counter app

`lib/main.dart` (untracked) plus `test/widget_test.dart` were the default Flutter
demo from the Phase 0 `flutter create . --platforms=macos`. Nothing referenced
them, and `lib/main.dart` used dot-shorthand syntax (`colorScheme: .fromSeed(…)`)
— a Dart 3.10 feature. That single file is why `pubspec.yaml` demanded
`sdk: ">=3.10.0"`, which no installed Flutter satisfies (3.35.5 ships Dart 3.9.2),
so `pub get` had never succeeded in this working copy. Both files deleted, SDK
floor lowered to `>=3.9.0`, and the project now resolves, analyzes, tests and
builds for macOS.

### `_checkProfile()` raced `QAProvider.initialise()` (found by relaunch testing)

`HomeScreen.initState()` checked `qa.hasProfile` in a one-shot
`addPostFrameCallback` — which fires right after the *first* frame (the loading
spinner), well before `initialise()`'s awaits (manifest load + five shell
subprocesses for tool versions) resolve. Every launch, `_profile` was still
null at check time, so the app bounced to Setup **even with a valid saved
profile** — a Phase 1 bug nobody had caught because it only reproduces past a
first run with a profile already saved. Verified by seeding `.plist`
UserDefaults directly (`defaults write com.example.flutterBoilerplate
flutter.prefkeyQAProjectsRoot -string <path>`) and screenshotting a real
relaunch before/after.

Fix: the check now runs inside `build()`'s `Consumer<QAProvider>`, guarded on
`qa.loadState == QALoadState.ready` and a `_profileChecked` flag so it fires
exactly once, after the real profile is loaded.

### Phase 4 — stdin needed no PTY

WDIO's `otpFetcher.ts` blocks on Node's `readline`, which just reads whatever
arrives on `process.stdin` — a plain pipe, not a TTY. A normal-mode
`Process.start` already leaves that pipe open, so `ProcessHandle.writeStdin`
is a two-line `stdin.writeln(...)`; no PTY library was needed. Verified with a
real child (`read code` mirroring the OTP prompt) in
`test/process_gateway_test.dart` — the fake-gateway tests in
`step_runner_test.dart` can't exercise this since `ProcessHandle._attach` is
private to `process_gateway.dart` and a fake never has a real `Process` to
attach.

### Appium re-check shares its HTTP logic with Doctor

`StepConfig.checkAppium` (`check_appium: true` in the manifest) re-probes
`localhost:4723/status` immediately before `test_ios_simulator` /
`test_ios_device` / `test_android` — Doctor's check happens before Run is
even enabled, and Build+Install can run for minutes in between. The GET
`/status` logic used to live only inside `DoctorRunner._checkAppium`;
factored out to `lib/src/base/qa/appium_probe.dart` so `StepRunner` doesn't
duplicate it. `StepRunner` takes an `isAppiumRunning` constructor seam so
tests don't hit the real network.

### Phase 5 — reopening a report re-runs the command, not a static path

`RunRecord` deliberately has no `reportPath` field. `allure open` (and
`npm run report:open`) start a local server to serve the report — a bare
`open <folder>/index.html` hits CORS loading the report's JSON data over
`file://`. So "reopen last report" just re-invokes the recipe's actual
`detach` step (`RecipeConfig.reportStep`) via `QAProvider.reopenReport`.
`hasReport` on a `RunRecord` is simply `status == done`, since that step is
always the pipeline's last one — reaching `done` means it ran.

### Phase 5 — quit must *wait* for cleanup, not just trigger it

`didRequestAppExit()` (the macOS Cmd+Q hook) can't just call
`RunProvider.cancel()` and return — `cancel()` only *requests* the kill;
the actual process-group termination, sleep-guard release, and history
write all happen asynchronously inside `start()`'s `finally` block. If
`didRequestAppExit` returned `AppExitResponse.exit` immediately, macOS could
tear down the app process before that cleanup ran, leaking exactly the
orphan this phase exists to prevent. `RunProvider.cancelAndWait()` tracks
the in-flight `start()` call via a `Completer` and awaits it before
`didRequestAppExit` returns. Verified for real in
`test/run_provider_quit_test.dart` — two `sleep 300` descendants and a
`caffeinate` process, both confirmed gone after `cancelAndWait()`.

### Phase 5 — `extraPathDirs` had been dead since Phase 1

The Setup screen already persisted `MachineProfile.extraPathDirs`, but
nothing downstream ever read it: `ProcessGateway._buildEnv` never touched
PATH, and `DoctorController` / `StepRunner` each defaulted to constructing
their **own** `ProcessGateway()` rather than the locator's shared singleton
— so even fixing `_buildEnv` alone wouldn't have helped Doctor or the
pipeline. Fixed all three points: `ProcessGateway.extraPathDirs` prepends to
PATH (`_withExtraPath`); `DoctorController` now defaults to
`locator<ProcessGateway>()`; `RunProvider.start` passes
`locator<ProcessGateway>()` into `StepRunner` explicitly.
`QAProvider._applyExtraPathDirs()` pushes the profile's value into that
shared instance on load/save/clear. One thing worth knowing: the login
shell's own `.zprofile` / `/usr/libexec/path_helper` run *after* we set
PATH and can reorder it — we guarantee the directory ends up on PATH
somewhere, not a fixed position.

### Phase 6 — why the manifest field is `spec_command`, not `spec_flags`

The original Phase 6 idea (append `-- --grep foo` to the existing `command`)
breaks for Web specifically: `yarn test`'s actual `package.json` script is a
**4-command chain** (`allure:clean && playwright:clean && env-cmd ...
playwright test && allure:generate`), and npm/yarn's `-- <args>` forwarding
appends to the very end of that whole resolved string — landing on
`allure:generate`, not `playwright test`. The filter would be silently
ignored while looking like it worked.

Fix: `StepConfig.specCommand` is a full alternate command template, used
**instead of** `command` only when the recipe's spec field is non-blank,
with `{flags}` placed correctly:
- Web: reconstructs the chain with the flag on the actual `playwright test`
  line
- iOS/Android: a direct `wdio run wdio.*.conf.ts {flags}` (confirmed from
  the real `centurion-app-automation-tests-ts/package.json` that
  `test:ios:dev`/`test:android:dev` are single commands, so npm forwarding
  would have been safe there too — the direct form was chosen for
  consistency with the simulator step's existing style, not because
  forwarding was actually broken for mobile)

No escaping is applied to what the user types — same trust boundary as
`env_file` values already interpolated via the shell: this is a single-user
local tool, the user is trusting themselves, same as typing the command into
Terminal directly.

### Node version split between repos

`crichq-webapp-nextjs` needs Node ≥ 22; the machine currently resolves
`node --version` to v20.19.1 inside `centurion-app-automation-tests-ts`. Doctor
already checks both floors separately — expect the Web card to flag Node until
the shell's default version is raised (or an `.nvmrc` per repo is honoured).

---

## Architecture principles

- **Gateways absorb I/O**: `ProcessGateway`, `ManifestLoader` — UI and controllers never call `Process.start` or `File` directly for test-related I/O.
- **Controllers call gateways**: `HomeController`, `SetupController`, `DoctorController` — pure Dart, testable.
- **Provider owns shared state**: `QAProvider` — manifest, profile, tool versions, doctor results. `RunProvider` — run state, log lines. Kept separate so a 2000-line log stream never rebuilds the version banner or Doctor panels; the home screen reads it through narrow `context.select` calls.
- **Manifest is declarative**: steps are data; `StepRunner` interprets them and contains no per-recipe branching. Adding a step = edit YAML only (no Dart change).

---

## What is NOT in v1

- Stage / prod recipes or env picker
- Auto-starting Appium
- Auto-OTP (stays human; a stdin field is provided instead)
- Windows support
- Second product YAML

(History/run-log persistence and the spec picker were originally listed here
as future work — both are done now, Phases 5 and 6.)

---

## Current status

| Phase | Status | Notes |
|---|---|---|
| 0 — macOS + PATH | ✅ Complete | Version banner matches Terminal |
| 1 — Manifest + Setup UI | ✅ Complete | Folder picker → home with 3 cards |
| 2 — Doctor | ✅ Complete | Run button gated; iOS toggle re-runs Doctor |
| 3 — Pipeline engine + Web | ✅ Complete | `StepRunner`, `RunProvider`, `RunPanel`; gateway kill/stream fixed |
| 4 — iOS + Android | ✅ Complete | stdin/OTP field (real test); Appium re-check via shared `AppiumProbe` |
| 5 — History + polish | ✅ Complete | `RunHistoryStore`, `SleepGuard`, quit→kill (real test), extra PATH dirs actually wired |
| 6 — Spec picker + README | ✅ Complete | Grep/spec filter; onboarding README |
| 7 — Multi-project + Dynamic Commands | ✅ Complete | ProjectsListScreen as new entry point; ProjectConfig data model; adapters keep StepRunner/DoctorRunner unchanged |
| 8 — Bug fixes + groups + history | ✅ Complete | Command pool + `commandIds` references; parallel groups; per-surface run history (see PROGRESS.md — not detailed in this file) |
| 9 — Create-time repo-loss fix + duplicate + validation | ✅ Complete | `ProjectTemplate.custom()` repoRelPaths fix; duplicate for commands/surfaces/repos; repo-role filter; mandatory-repo validation |
| 10 — Doctor quick-fix + filter consolidation + tooltips | ✅ Complete | See `PROGRESS.md` Phase 10 |
| 11 — ProcessGateway PATH resolution fix | ✅ Complete | `env: node: No such file or directory` fix — see `PROGRESS.md` Phase 11 |
| 12 — Run Experience Redesign | ✅ Complete | Mobile/web scripts, runner commands, Run/Pull&Run/Build&Run dispatcher, active-runs registry, reports, devices — see `docs/RUN_EXPERIENCE_REDESIGN.md` (full detail) + `docs/PROJECTS_SYSTEM.md` (current architecture) + `PROGRESS.md` Phase 12 (pointer) |

---

## Files to read before starting a new session

**The app's live entry point is the Projects system (Phase 7+), not the
legacy single-project screens Phases 0–6 describe below** — start with
`docs/PROJECTS_SYSTEM.md` for current architecture and
`docs/RUN_EXPERIENCE_REDESIGN.md` for the full run-experience feature
(Phase 12, the largest single addition since Phase 7). The list below is
kept for the legacy engine internals (`StepRunner`/`ProcessGateway`/
`DoctorRunner`), which those newer systems still reuse unchanged.

1. `docs/PROJECTS_SYSTEM.md` ← **start here for current architecture**
2. `docs/RUN_EXPERIENCE_REDESIGN.md` ← full detail on the mobile/web run
   experience (scripts, runner commands, dispatch, reports, devices)
3. `docs/PROGRESS.md` — full phase-by-phase scope checklist
4. `docs/CONVERSATION_CONTEXT.md` (this file) — fixed decisions + discoveries
5. `docs/COMMANDS_REFERENCE.md` — canonical commands (source of truth for YAML)
6. `manifests/centurion.yaml` — recipe steps (legacy; `project_template.dart`
   is the actual source of truth for the live Projects system's default
   commands — the two are not kept in sync, see `docs/PROJECTS_SYSTEM.md`)
7. `lib/src/base/qa/` — gateways
8. `lib/src/models/qa/` — data models
9. `lib/src/providers/qa/qa_provider.dart` — shared state (legacy single-project;
   `lib/src/providers/qa/run_provider.dart` + `lib/src/providers/qa/project_provider.dart`
   are the ones the live Projects system actually uses)

---

## Phase 7 — Multi-project + Dynamic Commands (COMPLETE)

**Completed:** 2026-09-07

### What changed

#### Architecture change
- The app now starts at `routeProjects` (ProjectsListScreen) instead of `routeQAHome`.
- Phases 0–6 (manifest-driven, single-project) remain fully intact and accessible via `routeQAHome`. The legacy flow is not deleted.
- The new flow: Projects List → Project Detail → Run. The old flow (legacy home) is kept for backward compat.

#### New data model (`project_model.dart`)
- `ProjectConfig` — the new first-class unit. Has `id` (UUID), `name`, `projectsRoot`, `repos: Map<String, RepoEntry>`, `surfaces: List<SurfaceConfig>`, `extraPathDirs`, `pinnedAt`, `lastOpenedAt`. JSON-serialisable.
- `RepoEntry` — role + label + relPath + branch. Same shape as `RepoConfig` in the manifest.
- `CommandConfig` — mirrors `StepConfig` exactly + `order` for drag-reorder. `toStepConfig()` adapter for backward compat.
- `SurfaceConfig` — mirrors `RecipeConfig`. `toRecipeConfig()` adapter. Has `commandsFor(iosTarget)` filter.
- Adapters on `ProjectConfig`: `.toProfile()` → `MachineProfile`, `.toManifestModel()` → `ManifestModel`.
- These adapters mean **StepRunner and DoctorRunner are unchanged** — they still receive `RecipeConfig + MachineProfile + ManifestModel`.

#### Storage (`project_store.dart`)
- JSON files in `<appSupportDir>/qa_control_center/projects/<id>.json` via `path_provider`.
- `loadAll()` returns sorted list (pinned first by pinnedAt desc, then by lastOpenedAt desc).
- `importFromJsonString()` generates a fresh UUID so import never collides with existing.

#### Template (`project_template.dart`)
- `ProjectTemplate.centurion(...)` — all current centurion.yaml commands as Dart consts.
- `ProjectTemplate.custom(...)` — blank project.
- `ProjectTemplateType` enum with `label`, `description`, `icon`.

#### Migration from legacy profile
- On first launch with 0 projects, `ProjectProvider._migrateLegacyProfile()` reads `prefkeyQAProjectsRoot` / `prefkeyQAExtraPath` from SharedPreferences.
- If found, auto-creates a "Centurion" project using the Centurion template with the stored root. Existing users see their project automatically — no data loss, no setup required.

#### RunProvider addition
- `startFromProject(project, surfaceId, ...)` — thin adapter that calls `.surfaceById()`, `.toRecipeConfig()`, `.toProfile()`, `.toManifestModel()` and delegates to existing `start()`.

#### New screens
| Screen | Route | Key features |
|---|---|---|
| `ProjectsListScreen` | `routeProjects` | Pinned/recent sections; per-project context menu (pin, edit, export, delete); import from JSON; empty-state Create prompt |
| `CreateEditProjectScreen` | `routeCreateProject` / `routeEditProject` | Shared create/edit/import screen; template selector; root + per-repo Browse buttons with ✓/✗ disk validation; Advanced (extra PATH dirs) |
| `ProjectDetailScreen` | `routeProjectDetail` | Tabbed by surface; self-contained Doctor panel (calls DoctorController directly, no QAProvider); Sync/Build toggles; iOS target SegmentedButton; spec/flags field; Run button gated on Doctor pass; live RunPanel |
| `CommandLibraryScreen` | `routeCommandLibrary` | ReorderableListView drag-to-reorder; add/edit/delete; import from file OR paste JSON; preview dialog before appending |
| `CommandEditScreen` | `routeCommandEdit` | Full form for all CommandConfig fields; iOS target SegmentedButton (null/simulator/device) |

#### Key fixes made during implementation
- `project_provider.dart` migration: used correct SharedPreferences keys `prefkeyQAProjectsRoot` / `prefkeyQAExtraPath` (not string literals).
- `navigation_utils.dart` casts: `settings.arguments as ProjectConfig?` (typed, not `dynamic`).
- `command_library_screen.dart`: `ReorderableDragStartListener(index: index)` — index must come from `ReorderableListView.builder`'s item index, not hardcoded 0.
- `DoctorStatus.checking` — added to exhaustive switch in `project_detail_screen.dart`.

#### pubspec additions
- `path_provider: ^2.1.3` — for `getApplicationSupportDirectory()`.

### Fixed decisions from Phase 7

| Decision | Rationale |
|---|---|
| StepRunner / DoctorRunner unchanged | Adapter pattern on ProjectConfig; no reason to touch proven pipeline code |
| Commands stored as flat list per surface (not nested by target) | `target: "simulator"/"device"/null` field already exists on CommandConfig; `commandsFor(iosTarget)` filters at runtime — same as manifest |
| Import assigns fresh UUID | Prevents collisions when same config imported on multiple machines |
| Migration is best-effort, silent | If prefs are missing or corrupt, user just creates a project fresh — no crash |
| Legacy QAHome route kept | Team may have bookmarks or existing flows; deprecation is gradual |

### Analyze status (post Phase 7)
- 0 errors
- 0 warnings  
- 2 info items (both pre-existing, not from Phase 7):
  - `common_methods.dart:56` — `use_build_context_synchronously` (boilerplate file)
  - `command_edit_screen.dart:223` — `DropdownButtonFormField.value` deprecated in Flutter 3.33+ (framework deprecation, not blocking)

---

## Phase 9 — Create-time repo-loss fix + duplicate + mandatory validation

**Completed:** 2026-09-07 (same day as Phase 7/8, later session)

Full details in `PROGRESS.md`'s Phase 9 section — this is the "why", not
the "what," for anyone continuing from here.

### How the repo-loss bug was actually found

Not from code review — from the user pasting a real screenshot of the Edit
Project screen showing "Role" fields correctly populated (`app`/`web`/
`mobile_tests`) but every "Folder name" field blank, on a real project
(`"Cent"`) on this machine. Reading the actual stored JSON
(`~/Library/Application Support/.../qa_control_center/projects/<id>.json`)
confirmed `"repos": {}` — genuinely empty, not a display bug. A sibling
project (`"Centurion"`) on the same machine had the correct data, which is
what made it clear this wasn't "the Edit screen fails to prefill" (Phase
8's bug) but "the data was never saved in the first place."

### Why this is a *different* bug from Phase 8's fix

Phase 8 fixed the Repositories **section** not rendering at all when
`repos: {}` (`_repoCtrlMap.isNotEmpty` guard). That fix means the section
now always shows — including 3 blank default rows for a repo-less project.
But showing the rows and correctly capturing what's typed into them are two
different things: `_save()` correctly builds `repoRelPaths` from the live
controllers either way, the break was one level deeper —
`ProjectController.create()`'s template `switch` only forwarded that map to
the `centurion` branch, and `ProjectTemplate.custom()` didn't accept it at
all. A user on "Start blank" could type real folder names into
correctly-rendered fields and still lose them, silently, at save.

### Fixed decisions from Phase 9

| Decision | Rationale |
|---|---|
| `custom()` builds `repos` from arbitrary `repoRelPaths` keys, not just app/web/mobile_tests | A "Start blank" project shouldn't be artificially limited to the Centurion role names — someone using this tool for a different product entirely needs custom role names to actually work |
| No auto-escaping/quoting on duplicate role names, command ids, etc. | Same trust boundary as everything else in this app — a single-user local tool; the `_copy` suffix nudges toward a distinct name but doesn't enforce uniqueness beyond what collision-avoidance requires |
| Duplicate never touches surfaces/projects the user isn't currently looking at | Duplicating a command from "All" only adds to the pool; duplicating from a surface tab also adds to *that* surface, never any other surface the original happened to be assigned to — avoids surprising side effects on data outside the current view |
| "At least one repo" / "a repo must be selected" enforced with explicit checks, not just relying on defaults | Both fields already had *a* default that made them look "never blank" in the common case — but the actual guarantee only holds once you check the code path where the default itself can't apply (zero rows, zero repos) |

### Analyze/test status (post Phase 9)
- `flutter analyze`: same 1 pre-existing info item as before (0 new issues)
- `flutter test`: 29/29 (26 prior + 3 new in `test/project_template_test.dart`)
- `flutter build macos`: clean
