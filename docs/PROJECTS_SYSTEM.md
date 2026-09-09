# Projects System — Current Live Architecture

**Read this file for the architecture; read `PROGRESS.md`'s Phase 7–9
sections for the phase-by-phase "what changed and why."** This file is a
single, coherent, code-verified snapshot — written by reading the actual
files on disk, not from memory of who built what or when — that
consolidates and extends what `PROGRESS.md`/`CONVERSATION_CONTEXT.md`
already documented incrementally across Phases 7–9. Its one genuinely new
contribution is the "Known gaps" section below: real issues found while
verifying the code against those docs, not yet written down anywhere or
fixed.

**Since Phase 9, the Projects/Commands system above was extended by a much
larger effort — the "Run Experience Redesign"** (mobile/web scripts, runner
commands, the Run/Pull&Run/Build&Run dispatcher, report archiving, device
management, and more). That work is documented in full step-by-step detail
in **`docs/RUN_EXPERIENCE_REDESIGN.md`** — read it for the *why* behind
every model field and screen added below (design rationale, decisions
made, bugs found, tests written). This file's job stays the same: the
current, consolidated *what* — updated below to include everything that
redesign added, not just what Phases 7–9 built. See `PROGRESS.md`'s Phase
12 entry for the one-paragraph pointer into that history.

`PROGRESS.md`/`CONVERSATION_CONTEXT.md`/`IMPLEMENTATION_PLAN.md`'s Phases
0–6 document the **original single-project system** — still accurate for
the execution engine internals (`StepRunner`, `DoctorRunner`,
`ProcessGateway`, `RunProvider`) since those are reused unchanged, but their
UI layer (`HomeScreen`, `SetupScreen`, `QAProvider`,
`manifests/centurion.yaml`) is now orphaned — the app's `initialRoute` is
`routeProjects`, not `routeQAHome`, and nothing in the reachable UI pushes
the legacy route anymore (see "What's actually dead" below).

---

## The one-sentence version

`initialRoute` is `routeProjects`, not `routeQAHome` — the app now manages
**multiple named projects**, each with its own repos, a shared **command
pool**, and **surfaces** that reference pool commands by id — instead of one
fixed web/iOS/Android manifest. The actual shell-command execution engine
underneath (`StepRunner` → `ProcessGateway`, `DoctorRunner`) is **unchanged**;
the new system's whole job is to materialize the same legacy value objects
(`ManifestModel`, `RecipeConfig`, `StepConfig`, `MachineProfile`) from a
`ProjectConfig` on the fly, then hand them to that unmodified engine.

---

## Data model — `lib/src/models/qa/project_model.dart`

```
ProjectConfig
├── id, name, projectsRoot
├── repos: Map<role, RepoEntry>              — role/label/relPath/branch
├── commands: List<CommandConfig>            — the GLOBAL POOL for this project
├── surfaces: List<SurfaceConfig>
├── extraPathDirs: List<String>
├── pinnedAt, lastOpenedAt: DateTime?
└── methods: toProfile(), toManifestModel(), simpleRecipeForSurface()
             ← legacy-object adapters
             testCommandFor(), buildInstallCommandsFor(), prerequisiteCommandsFor(),
             reportCommandFor(surfaceId, {target}) ← all built on one shared
             _filteredCommandsFor(surfaceId, {stageTag, target}) — see below

RepoEntry
└── role, label, relPath, branch              — branch IS editable in the Create/Edit
                                                 Project UI ("Sync branch" field — this
                                                 used to be a silent-preserve-only field;
                                                 that's fixed). No per-environment app-id
                                                 map here any more — see MobileAppId below.

MobileAppId                                    — one flat id per surface, not a
├── androidApplicationId: String?                per-environment map (a surface now
└── iosBundleId: String?                         already *is* one environment — see
                                                   SurfaceConfig.environmentId)

SurfaceConfig
├── id, name, icon
├── platformType: String?                     — "android" | "ios" | "web" | null — the
│                                                 one fixed enum left; everything else
│                                                 about a surface is free-form
├── environmentId: String?                     — free text ("dev"/"stage"/...), static
│                                                 per surface — substituted into a
│                                                 command's {environment} placeholder,
│                                                 not asked at Run time any more
├── appId: MobileAppId?                        — this surface's installed-app identity
│                                                 (mobile only)
├── commandIds: List<String>                   — ORDERED references into
│                                                 ProjectConfig.commands (assignment,
│                                                 not ownership) — pipeline order too
├── scripts: List<ScriptEntry>                 — leaf test files/package.json scripts
├── runPrerequisites, runPull, runBuild: bool   — three independent, plain always-
│                                                 on/off switches (default false),
│                                                 maintained on the surface card — no
│                                                 "smart" conditional-skip logic for any
│                                                 of them. Replaced the old per-click
│                                                 Run/Pull&Run/Build&Run menu entirely.
└── reportOutputRelPath: String?               — where the report tool writes its
                                                  output inside the project's own repo

ScriptEntry                                    — a leaf test file (mobile) or a
│                                                 package.json script name (web) — NOT
│                                                 a CommandConfig (a pipeline step);
│                                                 see "Scripts vs Commands" below
├── id, path, customName?, addedAt
├── displayName (getter)                       — customName if set, else derived from path
└── mergeUnique(existing, paths, {customName})  — dedup-by-path merge, static

CommandConfig                                  — one pool entry
├── id, name, command, repoRole               — repoRole → ProjectConfig.repos key
├── timeoutSeconds, skipIfNoSync, skipIfNoBuild, detach, envFile, target,
│   checkAppium, specCommand                  — identical fields to legacy StepConfig
│   (target: "simulator"|"device"|null — the one dynamic-per-run axis left; a build/
│   install/test command can still differ by target within one surface)
├── order                                      — sort hint
├── groupId, groupLabel, runParallel           — no legacy equivalent (parallel groups)
├── tags: List<String>                         — replaces the old fixed `category` enum
│                                                 PLUS the separate platform/environment
│                                                 filter fields. A command's pipeline
│                                                 stage is just one tag —
│                                                 "test"/"build"/"report"/"git"/
│                                                 "prerequisite", read by ProjectConfig's
│                                                 resolvers above; any other tag
│                                                 ("smoke", "regression", ...) is purely
│                                                 descriptive. Environment/platform
│                                                 aren't tags at all — they're static
│                                                 properties of the SurfaceConfig a
│                                                 command is *assigned* to.
└── toStepConfig() / fromStepConfig()          — bidirectional legacy adapter
```

`{environment}`/`{udid}`/`{script}`/`{branch}`/`{bundleId}` are the full set
of substitution placeholders a command's text or `envFile` path can use —
see `RunDispatcher.substitute()`/`.placeholderDocs` below.

### Surfaces are per-environment, one platform each — not a single shared "mobile" surface

An earlier iteration of this redesign tried a single unified `"mobile"`
surface with platform chosen per run (see `RUN_EXPERIENCE_REDESIGN.md` §2's
original proposal) — that was **reverted**. The live Centurion project (and
the current `ProjectTemplate.centurion()`) instead has one surface per
(environment × platform): `android_dev`, `android_stage`, `ios_dev`,
`ios_stage`, `web_dev`, `web_stage`. `platformType` and `environmentId` are
both static per surface now; the one thing still picked at Run time for a
mobile surface is target (simulator/device) + which device.

### Repo roles: the `mobile_ui` / `mobile_test` / `web` convention

Auto-surface-creation (`ProjectController.ensureAutoSurfaces()`, called
from `create()`/`save()` — idempotent, additive-only, never deletes a
surface if its repo disappears) keys off well-known **repo role strings**,
not a new model field. This is the bootstrap path for a `custom`
(non-Centurion-template) project — it creates one starting `web`/`mobile`
surface via `SurfaceConfig.autoWeb()`/`.autoMobile()` for the user to
rename/duplicate/retag (environment, icon) via Edit surface afterward, not
a fixed pair the app relies on by id:
- `web` repo present → ensures a `web` surface exists.
- Both `mobile_ui` (app source — build/install target, also where bundle-id
  auto-detection writes into the surface's `appId`) **and** `mobile_test`
  (E2E test repo — where scripts get imported from) present → ensures one
  `mobile` surface exists.

The Create/Edit Project screen has a dedicated "Add mobile repo" button
that adds both roles as one atomic pair (can't add just one), alongside
the original free-text "Add repo" for arbitrary/custom roles (still
supported — manual surface creation is a deliberate escape hatch for
surfaces that don't fit the web/mobile mold).

### Scripts vs. Commands — two different concepts, don't conflate them

A **Command** (`CommandConfig`) is a pipeline step — build, install, sync,
report. A **Script** (`ScriptEntry`) is the actual test artifact to run —
a file path (mobile `.e2e.ts` spec) or a `package.json` script name (web).
Scripts are CRUD'd on their own screen (`ScriptsScreen`, route
`routeScripts`) with mobile-specific import (single file picker, or
"import from folder" — recursive, files only, deduped by path) and
web-specific import ("import from package.json", deduped by script name).

### Runner ("test") commands — gate the Run button

No more dedicated id slots — a surface's runner command is just whichever
of its assigned `commandIds` is tagged `test` (optionally further filtered
by `target` for a mobile surface with separate simulator/device variants),
resolved via `ProjectConfig.testCommandFor(surfaceId, {target})`. The
Scripts screen's per-script Run button is disabled (with an explanatory
tooltip) when no `test`-tagged command resolves for the current surface.
Command text uses the single-brace placeholder convention shared with
`specCommand`: `{environment}`/`{udid}`/`{script}`/`{branch}`/`{bundleId}`
(substituted by `RunDispatcher.substitute()`).

**The key relationship:** a command lives once in `ProjectConfig.commands`.
Every `SurfaceConfig.commandIds` entry is just a reference to it by id.
Editing a command in the Command Library updates it everywhere it's
referenced; deleting it strips the id from every surface that had it.

**Command grouping (new, no legacy equivalent):** commands sharing a
`groupId` with `runParallel: true` are collapsed by
`ProjectConfig._buildParallelStep()` into one synthetic `StepConfig` that
backgrounds each command's own `cd "$relPath" && ...` with `&`, then `wait`s.
This is why `toManifestModel()` fabricates a synthetic `'_root'` repo entry
(`relPath: ''`) — the combined step needs *some* repo to report a cwd for,
even though it internally `cd`s per-command.

---

## Run dispatch, the active-runs registry, reports, and devices

The Run Experience Redesign's other big pieces — read
`docs/RUN_EXPERIENCE_REDESIGN.md` for full rationale on each.

### `RunProvider` is a registry, not a singleton

`lib/src/providers/qa/run_provider.dart` — `RunProvider._activeRuns: Map<String,
RunEntry>` holds every in-flight (or just-finished-but-undismissed) run, each
its own `SleepGuard`/`StepRunner`/log buffer/cancel-completer. **This fixed a
real bug in passing**: the old single-slot design shared one `SleepGuard` for
the whole app — two concurrent runs would have had one run's finish silently
kill the `caffeinate` process the other still needed.

Every old singleton getter (`isRunning`, `status`, `logs`, `recipeId`, ...)
still exists, now computed over the *primary* entry (most recently started) —
zero behavior change for existing UI, since nothing starts two runs at once
yet through the old call sites. New registry-aware API for code that
actually needs to see every run: `activeRuns`, `isRunningFor(recipeId)`,
`runIdFor(recipeId)`, `isDeviceBusy(udid)`. `start()`/`startFromProject()`
now return the new run's id (`Future<String>`/`Future<String?>`).

`RunEntry`/`RunRecord` also carry re-run/history metadata: `projectId` (the
actual bug fix — history used to bleed between two projects sharing a
surface id like `"web"`), `runId`, `scriptDisplayName`, `environmentId`,
`platform`, `deviceKind`, `deviceUdid`, `mode` — all threaded from
`RunDispatcher.dispatch()`, the one call site that knows them, all nullable
(legacy/manual runs won't have them). `RunRecord.hasRerunInfo` gates whether
"Re-run" can pre-fill the picker.

### `RunDispatcher` — `lib/src/base/qa/run_dispatcher.dart`

Turns "run this script, on this device" into an ordinary synthetic
`RecipeConfig` and hands it to the **existing, unmodified**
`RunProvider.start()`/`StepRunner` — no parallel execution engine.
Environment/platform are no longer asked at run time at all — they're
static properties of the surface (`environmentId`, `platformType`); target
(simulator/device) + device udid are the only things a mobile run still
picks (see the shared picker below).
- `substitute()` — `{environment}`/`{udid}`/`{script}`/`{branch}`/
  `{bundleId}` placeholder substitution (same single-brace convention as
  `specCommand`) — `{branch}` resolves per *command* (`project.repos
  [cmd.repoRole]?.branch`), `{bundleId}` per *surface*
  (`surface.appId`, android/ios picked by `surface.isAndroid`/`.isIos`).
  All five documented in one place, `RunDispatcher.placeholderDocs`,
  surfaced in the Command Edit screen.
- `pullAndCheckForChanges()` — real `git rev-parse HEAD` diff before/after
  `git pull`, used for the Pull step's log line (see below) — not a guess.
- `planSteps()` — pure, no `RunProvider` dependency, unit-testable in
  isolation. Assembles: prerequisites first (if `surface.runPrerequisites`
  — pool commands tagged `git`/`prerequisite`, resolved via
  `ProjectConfig.prerequisiteCommandsFor`), then Pull (if `surface.runPull`
  — an independent `git pull` step, purely informational now, doesn't gate
  anything), then Build (if `surface.runBuild` — pool commands tagged
  `build`, via `ProjectConfig.buildInstallCommandsFor(surfaceId, target:)`),
  then the runner command, then the report command last (if a `report`-tagged
  command resolves and `reportOutputRelPath` is set). Pull and Build are
  **two independent switches** — no more per-click Run/Pull&Run/Build&Run
  choice, and no more "skip build if the app looks already installed" smart
  check (that mechanism, `isInstalled()`, was deleted along with the
  `RunMode` enum — it could go stale invisibly, and nothing on the surface
  card said whether a run would actually rebuild).
- `dispatch()` — plans, starts via `RunProvider.start()`, then archives the
  report (see below) once the pipeline (including its report step)
  resolves.

### The shared picker — `lib/src/ui/qa/runner/run_picker.dart`

`RunPicker.pick()` — (mobile only) Platform → Simulator/Physical → Device,
as a sequence of plain `showDialog`s (deliberately not a custom wizard
widget) — a web surface's Run shows zero popups. Used by the Scripts
screen's single **Run** button AND by `RunPicker.reRun()` (resolves the
original script by display name — `RunRecord` only kept text, not a live
reference — falls back to a clear message if it's gone, never guesses),
which both the per-surface "Recent runs" section and the global
`RecentRunsScreen` (route `routeRecentRuns`) call into rather than
duplicating the flow. A re-run always follows the surface's *current*
Pull/Build switches, not whatever mode (if any) the original run used.

### Pull/Build — surface-level switches, not a per-click choice

`SurfaceConfig.runPull`/`.runBuild` (bool, default false) — same plain
always-on/off shape as `runPrerequisites`, maintained on the surface card
(`project_detail_screen.dart`'s `_PullSection`/`_BuildCommandsSection`, in
execution order Prerequisites → Pull → Build → Script → Report), not
chosen per click. Pull is just a switch (pulling the surface's buildable
repo — `mobile_ui` for mobile, `web` for web — is a fixed mechanic, not a
list of assignable commands); Build additionally shows a read-only preview
of the surface's assigned `build`-tagged commands plus a Manage button,
mirroring the Prerequisites section exactly.

### Device listing — `lib/src/base/qa/device_probe.dart`

Real `xcrun simctl`/`adb`/`xcrun devicectl` calls, **no persisted cache** —
fetched fresh every time (`DevicesScreen`, route `routeDevices`, has a
manual Sync/Reload button instead). Classification (simulator vs. physical,
Android vs. iOS) comes from which tool sourced the entry, never guessed.
Busy/idle status is derived from `RunProvider.isDeviceBusy()` — there is no
reliable OS-level "is this simulator busy" signal. Also has the "Add
simulator/emulator" primitives (`listIosDeviceTypes/Runtimes`,
`createIosSimulator`; `listAndroidDeviceProfiles/SystemImages`,
`createAndroidAvd`) — listing methods stay never-throws, but the two
`create*` methods deliberately let real errors propagate to the UI (a user
who just pressed "Create" needs to see why it failed).

### Report archiving — `ReportArchive`/`ReportArchiveStore`/`ReportArchiver`

A report is never actually preserved by the underlying repo's own tooling
(the next run overwrites it) — `ReportArchiver` copies
`reportOutputRelPath`'s contents into app-managed storage
(`<appSupportDir>/qa_control_center/reports/<projectId>/<surfaceId>/<runId>/`)
right after each run's report step finishes, and records a `ReportArchive`
entry (mirrors the `RunRecord`/`RunHistoryStore` pattern, with a `projectId`
from day one — unlike `RunRecord`, which needed a later fix to get one).
Retention: keeps newest 20 or under 2GB per surface, pruned oldest-first
after every new archive. `ReportsScreen` (route `routeReports`) exposes
Open (allure CLI → throwaway local HTTP server → Finder-reveal fallback,
addressing Allure's CORS-on-static-files problem), Download, Reveal,
Copy-path, and Regenerate.

### Live progress — `ActiveRunsScreen`

Route `routeActiveRuns`, a badged AppBar icon on Project Detail. Lists
every `RunProvider.activeRuns` entry as an expandable card with its own
live log stream (same rendering approach as the original single-run
`RunPanel`, adapted per-entry), a Cancel button while running, and a "View
report" link once finished (via `ReportArchiveStore.findByRunId`).

---

## Persistence — `lib/src/base/qa/project_store.dart`

- One JSON file per project: `<getApplicationSupportDirectory()>/qa_control_center/projects/<id>.json`
- `id` is a v4-style UUID from `generateProjectId()` (no external uuid package).
- `loadAll()` parses each file in its own try/catch and **silently skips a
  malformed one** rather than crashing the whole list. **Writes (`save`,
  `delete`, `exportToFile`) have no such guard** — a disk error there
  propagates as a normal unhandled Future rejection to whichever
  `ProjectProvider` method called it (most don't catch it either; only
  `ProjectProvider.initialise()` wraps its whole body and surfaces `_error`).
- Export keeps absolute `projectsRoot`/repo paths as-is (by design — the
  import flow re-opens Create/Edit Project so the user can remap them for
  the machine they're importing onto).
- Import always mints a **fresh id**, so importing the same file twice
  creates two independent projects rather than colliding.

---

## Screens, routes, and the real navigation flow

| Route | Screen | Args |
|---|---|---|
| `routeProjects` (**initialRoute**) | `projects_list_screen.dart` | — |
| `routeCreateProject` / `routeEditProject` | `create_edit_project_screen.dart` | `existingProject?`, `importedProject?` |
| `routeProjectDetail` | `project_detail_screen.dart` | `ProjectDetailArgs(project)` |
| `routeCommandLibrary` | `command_library_screen.dart` | `CommandLibraryArgs(project, surfaceId?)` |
| `routeCommandEdit` | `command_edit_screen.dart` | `CommandEditArgs(project, surfaceId?, existing?)` |
| `routeScripts` | `scripts_screen.dart` | `ScriptsArgs(project, surfaceId)` |
| `routeReports` | `reports_screen.dart` | `ReportsArgs(project, surfaceId)` |
| `routeRecentRuns` | `recent_runs_screen.dart` | — (global, across every project) |
| `routeActiveRuns` | `active_runs_screen.dart` | — (global, live progress) |
| `routeDevices` | `devices_screen.dart` | — (global, device management) |

**Real flow:** Projects List → New project (template picker: **Centurion**
seeds six dev/stage android/ios/web surfaces + the shared command pool from
hardcoded Dart literals in `project_template.dart`, or **Start blank**) →
pick Projects folder, fill in repo rows → Save → tap the card → Project
Detail (one expandable card per surface: Doctor, a Branch section, then
Prerequisites/Pull/Build/Script/Report sections in execution order — each a
switch plus a read-only preview of its resolved commands, "Manage" opening
the tag-filtered Command Manager; a "Recent runs" list below) → Scripts
screen (per-surface leaf test scripts, single Run button per row) →
Command Library (per-project pool browser: "All" tab with tag + repo-role
filter chips, one tab per surface with drag-to-reorder and assign/unassign)
→ Command Edit (full field form, "Runs in repo" dropdown, iOS target
filter, group/parallel fields, tag picker with the full placeholder-docs
list shown inline, surface-assignment checkboxes).

**Duplicate actions** (added this session) exist at all three levels:
commands (Command Library tile), surfaces (Project Detail's ⋮ menu), and
repo rows (Create/Edit Project). All follow the same pattern: clone under a
fresh id (`<id>_copy`, numbered if taken), name suffixed `(copy)` (or
`_copy` for repo role names, since those are the map key, not a display
label), no destructive side effects on anything else that referenced the
original.

---

## Execution engine reuse — verified by grep, not assumed

**Nothing was duplicated.** `StepRunner`, `ProcessGateway`, `DoctorRunner`,
`RunHistoryStore`, `SleepGuard`, `AppiumProbe`, `EnvFileParser`, and
`RunProvider` are the exact same classes the legacy system used — the new
system's only role is producing the legacy value objects
(`ManifestModel`/`RecipeConfig`/`StepConfig`/`MachineProfile`) that those
classes already knew how to consume. `RunProvider.startFromProject()` (new
method, added alongside the original `start()`) was the first addition to
the shared engine layer; `RunDispatcher` (see the section above) is the
second, and it too produces an ordinary synthetic `RecipeConfig` rather
than executing anything itself — `StepRunner` still never changed.

`DoctorController`/`DoctorRunner` are filed under a `// legacy` comment
block in `locator.dart`, but are in fact the **live, shared Doctor engine**
for the new system too — "legacy" there means "predates the rewrite," not
"unused."

---

## What's actually dead vs. what's still running

- **Dead (unreachable, but not deleted):** `routeQAHome`/`routeQASetup`
  still resolve to real `HomeScreen`/`SetupScreen` widgets in
  `NavigationUtils.generateRoute`, but nothing in the reachable UI graph
  pushes either route — they only reference *each other* in a closed loop.
  `doctor_panel.dart` and `history_panel.dart` are imported only by
  `home_screen.dart`.
- **Still running, but invisible:** `main.dart` still constructs
  `QAProvider()..initialise()` on every launch — it loads
  `manifests/centurion.yaml`, reads the legacy `SharedPreferences` profile,
  and fetches tool versions via shell calls, all for a screen the user can
  never reach. Not harmful, just unnecessary work + a stale/confusing file
  read on every startup.
- **`manifests/centurion.yaml`** is still parsed (as a side effect of the
  above) but nothing downstream of that parse is ever displayed or acted on.
  `project_template.dart`'s hardcoded Dart command lists are now the actual
  source of truth for default Centurion commands — **the YAML and the Dart
  template are not kept in sync with each other**, so if you change one, the
  other silently drifts.
- **One real bridge from old → new:** `ProjectProvider.initialise()`, if
  `loadAll()` returns an empty project list, reads the legacy
  `prefkeyQAProjectsRoot` SharedPreferences key and auto-creates one
  Centurion-template project named `"Centurion"` from it — a one-time,
  silent migration for anyone who'd already run the old Setup screen.

---

## Known gaps (found while surveying, not yet fixed — flagging, not silently patching)

1. **`ProjectConfig.extraPathDirs` is dead in the new system.** It's stored
   and editable in Create/Edit Project's Advanced section, but nothing in
   the new code path (`ProjectProvider`, `ProjectController`,
   `RunProvider.startFromProject`, `ProjectDetailScreen._runDoctor`) ever
   assigns it into `locator<ProcessGateway>().extraPathDirs`. Only the
   legacy `QAProvider._applyExtraPathDirs()` does that wiring, from the old
   profile — meaning a value typed into a *new* project's Advanced section
   currently has **no effect at all**. Same shape of bug as the "Cent"
   project repo-loss bug fixed this session; not yet fixed here.
2. ~~**Run history has no project scope.**~~ **Fixed** by the Run
   Experience Redesign — `RunRecord`/`RunEntry` gained `projectId`, and
   `RunProvider.lastReportFor`/`_RunHistorySection` both scope by
   `(recipeId, projectId)` now. A record with no `projectId` on file (from
   before the fix) stops showing per-project rather than risking a bleed.
3. **`docs/RUN_CONTEXT.md`** is still written by `StepRunner` after every
   run (legacy or new), to a hardcoded path derived from
   `profile.projectsRoot` — silently skipped if that folder isn't actually
   the `automation-testing` checkout. Harmless, but means the "what happened
   last run" file only ever reflects whichever project happened to run most
   recently, regardless of which project you're actually looking at.
4. **`README.md`** (repo root) still documents only the legacy single-project
   onboarding flow (`Setup → Doctor → Run`) — it predates this rewrite and
   needs updating to describe Projects List / Create Project / Command
   Library instead. Not done as part of this doc pass; flagging it here.

---

## Phase 9 (this session) — bugs fixed and features added

Full write-up in `PROGRESS.md`'s Phase 9 section and
`CONVERSATION_CONTEXT.md`'s Phase 9 section (the "why," not just the
"what"). One-line summary: fixed a real data-loss bug
(`ProjectTemplate.custom()` silently dropping typed repo folder paths —
different from Phase 8's "section doesn't render" fix), added Duplicate for
commands/surfaces/repo rows, added repo-role filter chips to Command
Library, and closed two "looks mandatory but isn't actually enforced" gaps
(a project needs ≥1 repo to save; a command needs a repo selected to save).

---

## How this file came to exist

Mid-session, the user referenced a "Command Library import via JSON" feature
that didn't match anything built in this conversation's earlier phases.
Investigation found the entire Projects/Commands system already present on
disk, staged in git, with file timestamps later than this session's own
edits — built by another process/session outside this conversation's
knowledge. This file is the result of reading that system directly to
document it accurately, rather than assuming anything about how or why it
was added.
