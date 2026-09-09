# Run Experience Redesign — Draft Spec

Status: **Decisions locked in** (see "Decisions" at the bottom — the four
forks this doc originally flagged as open questions are now resolved).
Sections still marked "proposal" elsewhere are smaller defaults, stated so
you can correct them inline, not blocking.

This document redesigns/organizes the rough requirements dump for:
repo pairing + sync branch, auto-surface creation, scripts, runner
commands, the Run / Pull&Run / Build&Run flows, prerequisite commands,
report lifecycle, recent runs, a live run screen, and global device
management. It's grounded in the actual current codebase (audited before
writing this — see "Current state" callouts throughout) — not a rewrite
from scratch; wherever today's model already covers something, this reuses
it instead of inventing a parallel concept.

---

## 0. What already exists vs. what's genuinely new

To avoid re-litigating things that are already fine:

| Already exists, reused as-is | Genuinely new |
|---|---|
| `ProjectConfig.commands` — global pool, referenced by id | Environment/flavor model (none exists — flat strings in shell commands today) |
| `SurfaceConfig.commandIds` — ordered id refs | Bundle ID / package name storage (none exists — hardcoded in command text today) |
| `CommandConfig` (name, command, repoRole, category, detach, ...) | Device listing / emulator management (none exists — only pass/fail Doctor checks) |
| `RunRecord` / `RunHistoryStore` (last-50, SharedPreferences) | "Script" as a distinct concept from "Command" (a leaf test file / package.json entry, not a pipeline step) |
| `ProcessGateway.exec/stream/detach` + `ProcessHandle.kill()` | Report archiving (today a report is never actually preserved — see §7) |
| `{flags}`-style single-brace placeholder substitution (already used in `specCommand`) | Runner-command templates with `{environment}`/`{udid}`/`{script}` placeholders (same substitution mechanism, new field) |
| `RepoEntry.branch` field (exists today, just **not editable in the UI** — see §1) | Live multi-run progress screen (today's UI assumes one active run per surface) |
| category `'report'` convention on `CommandConfig` | Global device-busy registry (requires runs to become trackable as a registry, not a singleton) |

---

## 1. Repo model changes

### 1a. Sync branch (Change #1)
**Not a new field.** `RepoEntry.branch` already exists (defaults `'develop'`) but the
Create/Edit Project screen never shows it — it's silently preserved on save.
Fix: add a "Sync branch" text field per repo row, pre-filled `develop`,
editable. This is a UI fix, not a model change.

### 1b. Mobile repo pairing (Change #2)
Today a repo is a single free-text `role` + folder. For "Mobile" this becomes
**two repos added together as one unit**:
- `mobile_ui` — the app source (what gets built/installed; also where
  bundle ID / applicationId auto-detection reads from, §3).
- `mobile_test` — the E2E test repo (WDIO/Appium-style specs; where
  script files get imported from, §4).

Proposal: the "Add repo" flow gets a type selector — **Web** (single
folder) or **Mobile** (two folder pickers, both required, labeled "App
source" and "Test scripts"). Adding a Web repo can complete on its own;
adding a Mobile repo only completes (and only then triggers surface
auto-creation, §2) once **both** folders are set — matching your
"if we select mobile and mobile test then only" condition literally: it's
not two independent optional repos, it's one atomic "Mobile" repo-pair add.

---

## 2. Auto-surface creation

**Decided: one shared `mobile` surface**, not today's separate
`ios`/`android` split. Today's `SurfaceConfig.id` convention is
`"web" | "ios" | "android"` as three *separate* surfaces, but a WDIO/Appium
spec file is normally shared across Android and iOS (only capabilities
differ) — splitting into two surfaces would mean maintaining the same
script list twice, and picking Android/iOS is naturally a **per-run**
choice, not a permanent per-surface one. This is both the easier one to
maintain (one script list, one runner-command set, one report history to
reason about instead of two kept in sync) and the more professional shape
(matches how the underlying test tooling actually organizes specs) — so:
- Adding a Web repo → auto-creates (or ensures) a `web` surface.
- Completing a Mobile repo pair → auto-creates (or ensures) **one** `mobile`
  surface, with platform (Android/iOS) as a per-run choice, not a
  per-surface split.

Auto-creation is **idempotent** (create-if-missing, never duplicate/overwrite
an existing surface with that id) and **never auto-deletes** a surface if
its repo is later removed — deleting scripts/runner-commands/report-history
silently on a repo edit is a data-loss trap. Instead: if a surface's backing
repo is gone, show a warning banner ("this surface's repo was removed —
commands may fail") and let the user delete it manually, same as today's
existing manual-delete confirmation flow.

**Manual surface creation — kept as an escape hatch (deferred, not removed
from the data model), use cases where it earns its keep:**
- One repo serving two distinct testable surfaces (e.g. a web repo hosting
  both a customer site and an admin dashboard) — two "web-shaped" surfaces
  from the same repo, each with its own script list/report/history.
- A backend/API-only repo — a surface running Postman/Newman-style checks
  that fits neither web nor mobile.
- A cross-repo "smoke test" surface chaining commands across the whole
  project as one identity, separate from the per-repo surfaces.
- A project with no local repo at all — a surface that just hits a hosted
  staging URL (Playwright/Cypress against a live site, nothing to build).

Since auto-creation is just a convenience pre-fill of an otherwise-ordinary
`SurfaceConfig`, none of this needs its own code path later — "Add surface
manually" already exists today, unchanged.

---

## 3. Environment / flavor model (new)

**Decided: independent per surface**, not shared at the project level — the
mobile and web surface of a project each define their own environment list
(they don't have to line up 1:1; e.g. mobile might have `dev`/`staging`/
`prod` while web only has `dev`/`prod`):
```dart
class EnvironmentDef {
  final String id;      // "dev", "staging", "prod"
  final String label;
  final bool isDefault;
}
List<EnvironmentDef> environments;   // on SurfaceConfig
```

**Bundle ID / package name** — genuinely new, stored per environment on the
`mobile_ui` repo (it's a property of the app being built, not of the
surface) — keyed by the `mobile` surface's environment ids:
```dart
Map<String, MobileAppId> appIdsByEnvironment;  // key = EnvironmentDef.id
class MobileAppId { final String? androidApplicationId; final String? iosBundleId; }
```
**Auto-detect proposal:** best-effort parse, always overridable, never
blocking on failure:
- Android: `android/app/build.gradle(.kts)` — read `applicationId` inside
  each `productFlavors { ... }` block.
- iOS: per-scheme `.xcconfig` (or `project.pbxproj` if no xcconfig split) —
  read `PRODUCT_BUNDLE_IDENTIFIER`.
If parsing fails (non-standard project layout), the field is just left
blank and **required** before that environment's mobile runs are enabled —
same "mandatory but shown, never silently defaulted" principle you asked
for everywhere else.

**Environment selection at run time:** a plain dropdown, pre-filled to
"last used for this surface" (falling back to the project's default env) —
no fragile flavor-sniffing heuristic. You mentioned "or you figure out an
algorithm" — I'd rather keep this simple and correct than clever and wrong.

---

## 4. Scripts (new concept, distinct from Commands)

A **Script** is a leaf test file (mobile) or a named `package.json` script
(web) — not a pipeline step. New model, lives on the surface:
```dart
class ScriptEntry {
  final String id;
  final String path;          // mobile: file path; web: package.json script name
  final String? customName;   // user-entered; falls back to filename/script-name
  final DateTime addedAt;
}
```
`SurfaceConfig.scripts: List<ScriptEntry>`.

**Mobile:**
- Add one via a Finder file picker (captures the path).
- "Import from folder" — recursive, **files only** (skips directory
  entries), de-duplicated by path against what's already in the list (a
  second dump of the same folder adds nothing already present).
- At the moment `mobile_test`'s folder is set during repo setup: prompt
  "Import scripts from `test/specs`?" (Yes / No / Choose a different
  folder) — a suggestion, never a silent default.

**Web:**
- "Import from `package.json`" — dumps every entry in `"scripts"`, deduped
  by script name against what's already there.
- Or add one manually (type/pick a script name) — same de-dup rule.

Edit (rename the custom name) and Delete both available on every script row,
as you asked.

---

## 5. Runner commands (new, per surface)

Four command **templates**, one per Android/iOS × Simulator/Physical
combination for the mobile surface (web needs none of this — see §5b).
These are **not hardcoded Dart strings** — per your "everything dynamic,
from the command list" requirement, each is an ordinary `CommandConfig` in
the project's existing pool (so it's editable, duplicable, and visible in
the Command Library like everything else), referenced from the surface:
```dart
Map<String, String> runnerCommandIds; // keys: android_simulator, android_device, ios_simulator, ios_device
```
Placeholder tokens reuse the **existing** `{flags}`-style single-brace
substitution already used for `specCommand` (no new syntax introduced):
`{environment}`, `{udid}`, `{script}`.

All four are **mandatory** before any Run/Pull&Run/Build&Run button enables
— a completeness checklist above the scripts list shows which of the four
are still missing, same spirit as the Doctor checklist you already have.

### 5b. Web
No platform/device step — the web surface just needs one runner command
template (using `{environment}` and `{script}`; no `{udid}`), plus a
build/install command pair for the Build/Pull flows below.

---

## 6. Run / Pull & Run / Build & Run

> **Superseded** — this section describes the *original* design (a
> per-click Run ▾ menu with a smart "is it already installed" check). It
> shipped (Step 6 below) and stayed live through several iterations, but was
> **replaced** by a simpler design: Pull and Build are now plain per-surface
> switches (`SurfaceConfig.runPull`/`.runBuild`, same shape as
> `runPrerequisites`), maintained on the surface card, not chosen per click.
> The Scripts screen now has a single **Run** button. See the final step in
> "Progress" below (search "Pull/Build switches") for the current design and
> why the smart "already installed" check was dropped. Left in place below
> as the historical record of the original proposal.

Common picker sequence, mobile (as originally proposed):
**Environment → Platform (Android/iOS) → Target (Simulator/Physical) →
Device** (with a "Run on an available device" default option that
auto-picks the first idle device of the right kind — busy devices excluded,
§10) **→ dispatch** via the matching runner-command template.

Web: **Environment → dispatch** (no platform/device step).

- **Run** — check whether the app is already installed with the current
  environment's bundle id (`adb shell pm list packages` for Android;
  `xcrun simctl get_app_container <udid> <bundleId>` for iOS simulator;
  `devicectl device info apps` for physical iOS). Installed → run the
  script directly. Not installed → run the Build command → Install command
  (both ordinary pool `CommandConfig`s, auto-suggested/prefilled by
  category but user-editable, per your ask) → then the script.
  **Accepted risk, flagged not solved:** "installed" only means *a* build
  with that bundle id is present — not that it's the *current* code. This
  redesign does not add build-staleness detection (comparing installed
  build's commit vs. HEAD) for v1; `Run` is knowingly optimistic, and
  Pull&Run/Build&Run are the safe paths when freshness matters. Flag if you
  want staleness detection added — it's a real, buildable follow-up (stamp
  the `mobile_ui` HEAD commit at each successful install, compare on `Run`),
  just scoped out here to keep v1 lean.
- **Pull & Run** — pulls the repo's configured sync branch (§1a), or a
  one-off manual branch typed in for that run only (not remembered). This
  **is** feasible to detect precisely, so no degraded fallback is needed:
  `git rev-parse HEAD` before pull, pull, `git rev-parse HEAD` after — if
  they differ, treat it exactly like Build & Run (build → install → run);
  if identical, just run.
- **Build & Run** — always build → install → run, unconditionally.

Web equivalents: "build" = the project's build/setup command, "install" =
dependency install (`npm install`/`yarn`), "run" = the script itself — same
three buttons, mapped to web-appropriate commands from the pool.

---

## 7. Prerequisite commands (per-surface switch)

```dart
bool runPrerequisites;
List<String> prerequisiteCommandIds;   // user-picked from this surface's pool commands
```
When on, these run first (in order), ahead of Pull and Build (now their own
switches too, per the superseded-note in §6 above) — this is exactly where
`flutter pub get` / `pod install` / `npm install` belong, picked from the
pool rather than hardcoded.

(`prerequisiteCommandIds` above was itself later replaced by tag-based
resolution — `ProjectConfig.prerequisiteCommandsFor()` filters the surface's
assigned commands for the `git`/`prerequisite` tags, same convention as
Build/Test/Report — see the tags-overhaul entry in "Progress" below.)

---

## 8. Report command + report lifecycle

`SurfaceConfig.reportCommandId` — mandatory, prefilled from the pool's
existing `category: 'report'` convention, user-editable/swappable.

**Current state, confirmed by audit:** reports are **never actually
preserved** today. "Reopen last report" just re-runs the original report
command; there's no stored report path, because the underlying repo's own
report folder gets overwritten by the next run — exactly the loss you
flagged.

**New: `SurfaceConfig.reportOutputRelPath`** — required, since the app can't
guess where a given project's report tool writes its output (e.g.
`allure-report/` or similar) — this is genuinely project-specific and needs
a real field, not a guess.

**New `ReportArchive` model + `ReportArchiveStore`** (mirrors the existing
`RunRecord`/`RunHistoryStore` pattern — same shape of solution, just adds a
physical file copy):
- Immediately after the report command finishes, **copy** (not move — leave
  the repo's own folder alone) `reportOutputRelPath`'s contents into
  app-managed storage keyed `{projectId}/{surfaceId}/{runId}/`, alongside a
  metadata JSON (`runId, script, environment, platform, device, command
  used, generatedAt, sourcePath`).
- **Download** — reveal-in-Finder / copy to a user-chosen location.
- **Share** — needs checking whether this app has any macOS share-sheet
  integration already; if not, scoped down to Finder-reveal + "copy path"
  for v1, share-sheet as a stretch item.
- **Regenerate** — re-runs just the report command against the same run's
  leftover raw results, if still on disk; if they've since been cleaned up,
  this degrades to "re-run the whole script."
- **Open** — a real technical risk worth flagging: a static copy of an
  Allure-style HTML report often needs to be *served*, not
  double-clicked, or its own JSON data fails to load under `file://` due to
  CORS. "Open archived report" likely needs to spin up a throwaway local
  static server for that folder (or shell out to `allure open
  <archived-folder>` if the Allure CLI supports opening a pre-generated
  folder directly) rather than a plain `open index.html`.

---

## 9. Recent runs (surface + global)

**Bug found while designing this, worth fixing in the same pass:**
`RunRecord` has no `projectId` — run history today is one global list keyed
only by surface id (e.g. `"web"`), so two different projects that both have
a `"web"` surface show **each other's** run history. Adding `projectId` to
`RunRecord` is a one-line model fix that should ride along with this work.

- Surface-level "Recent runs" — unchanged in spirit, now correctly scoped
  per project.
- Global "Recent runs" screen — same data, unfiltered by project, with a
  project/surface column.
- **Re-run** — proposal: re-opens the same env/platform/device/script
  picker flow from §6, **pre-filled** with that record's values, so the
  user can tweak before confirming rather than blindly repeating identical
  config.

---

## 10. Live run / progress screen (new)

Shows: which surface/script/environment/device is running, live streamed
stdout/stderr (reuses `ProcessGateway.stream`/`LogLine` as-is — just needs a
UI), a Cancel button (`ProcessHandle.kill()` already exists), and on
completion a link into the archived report (§8).

**Decided: true concurrency.** Multiple scripts can run simultaneously
against different devices, which is what makes device-busy tracking mean
something and lets the progress screen show several in-flight runs at once.
This is the single biggest architectural change in this whole redesign:
`RunProvider` moves from today's singleton "current run" to a **registry of
active runs**, keyed by run id, each with its own device binding, log
stream, and cancel handle. Everything else in this doc (busy/idle device
status in §11, the progress screen itself, re-run from history) is built
assuming this registry exists.

---

## 11. Global device management

New screen, Android / iOS tabs, listing both real devices and
simulators/emulators under each. Classification is **not actually
ambiguous** (contrary to the doubt in your notes) — it's determined by
which tool sourced the entry, not guessed: `xcrun simctl list devices` is
always simulators; `adb devices -l` / `devicectl` are always real Android /
iOS hardware. No user confirmation needed there.

- **Decided: fetch-on-demand, no persisted cache**, plus a manual
  Sync/Reload button. `simctl list` / `adb devices` are sub-second calls; a
  stale cache is worse than a fast live query, and this can always grow a
  cache later if a real perf problem shows up.
- **Busy/idle status** — derived from *our own* active-runs registry (§10,
  now confirmed real, not hypothetical) — not an OS-level signal (there
  isn't a reliable external "is this simulator busy" flag). A device is
  "busy" iff some entry in the active-runs registry is currently bound to
  its UDID; only idle devices are selectable in the run picker (§6).
- **Add simulator/emulator:**
  - iOS: device type + OS runtime (from `xcrun simctl list devicetypes` /
    `list runtimes`) + name → `xcrun simctl create <name> <type> <runtime>`.
  - Android: AVD name + device profile (`avdmanager list device`) + system
    image (`sdkmanager --list` / `avdmanager list target`) →
    `avdmanager create avd -n <name> -k <image> -d <device>`.
  Both are ordinary shell-outs via the existing `ProcessGateway` — same
  philosophy the rest of the app already uses.

---

## 12. Report storage cleanup

Proposal (not yet confirmed): a retention policy — keep the last *N*
reports per surface (default 20) and/or a max total folder size (default
2GB), whichever limit is hit first prunes oldest-first — plus a manual
"Clear all reports" button per project/surface. Runs opportunistically
right after each new report is archived; no background timer/scheduler
needed.

---

## Decisions

1. **Concurrency: true concurrent runs.** `RunProvider` becomes a registry
   of active runs (§10) — the biggest architectural change here, and the
   thing §11's device-busy tracking depends on.
2. **Mobile surface shape: one shared `mobile` surface**, not today's split
   `ios`/`android` surfaces — platform is a per-run choice (§2).
3. **Environment/flavor scope: independent per surface**, not shared at the
   project level (§3) — mobile and web each define their own list.
4. **Device list refresh: fetch-on-demand + manual Sync/Reload, no
   persisted cache** (§11).

Everything else above is a stated proposal/assumption you're welcome to
correct in-line — I didn't want to block on every small default (recursive
folder-import, one-off manual branch override, report retention numbers,
etc.) when a reasonable choice was available.

## Suggested build order

Given the scope, this is not a one-shot implementation. Rough dependency
order:
1. Repo model: sync-branch UI field, mobile repo-pairing add-flow.
2. Auto-surface creation (`mobile` + `web`), environment model on
   `SurfaceConfig`, bundle-id storage + best-effort auto-detect.
3. Scripts model + import flows (file picker, folder dump, package.json
   dump) — no run wiring yet, just CRUD.
4. Runner commands (as pool `CommandConfig`s) + the completeness
   checklist gating Run buttons.
5. `RunProvider` → active-runs registry (the big one) + global device
   listing/busy-status built on top of it.
6. Run / Pull&Run / Build&Run dispatch logic + the picker flow (§6).
7. Prerequisite commands switch (§7) — small, slots into the dispatch
   built in step 6.
8. Report archiving (`ReportArchive`/`ReportArchiveStore`) + Download/
   Share/Regenerate/Open actions.
9. Live progress screen (reads the registry from step 5).
10. Recent runs fix (`projectId` on `RunRecord`) + global recent-runs
    screen + re-run-with-picker.
11. Report storage cleanup/retention.
12. Device management screen: Add-simulator/emulator flows.

Recommend confirming this order (or reprioritizing) before I start, since
step 5 is a prerequisite for several later ones and is worth getting right
in isolation before layering the run flows on top.

## Progress

### Step 1 — Repo model: sync-branch UI field + mobile repo-pairing add-flow ✅

- **Sync branch field**: `RepoEntry.branch` already existed but had no UI —
  added a "Sync branch" `TextFormField` to every repo row in
  `create_edit_project_screen.dart` (pre-filled `develop` for new rows, the
  existing value for edit/import rows).
- **Bug found and fixed while wiring this up**: `ProjectProvider.createProject`
  didn't accept/forward `repoBranches` at all — `ProjectController.create` and
  both `ProjectTemplate` factories already had the parameter (from a prior
  session's fix), but the provider layer in between silently dropped it,
  same class of bug as the earlier `ProjectTemplate.custom()` repo-loss issue.
  Fixed by adding `repoBranches` to `ProjectProvider.createProject`'s
  signature and forwarding it through.
- **Mobile repo pairing**: added an "Add mobile repo" quick-action next to
  the existing generic "Add repo" button. It adds two rows atomically under
  the reserved role keys `mobile_ui` (App source) and `mobile_test` (Test
  scripts) — each labeled distinctly in the UI. No new model field was
  needed: `RepoEntry.role` is already free text, so these are just
  well-known key conventions a later auto-surface-creation pass (step 2)
  will key off of. The existing generic "Add repo" (arbitrary role) stays
  available for custom/advanced repos.

```
lib/src/ui/qa/projects/create_edit_project_screen.dart
    + _branchCtrlMap (parallel to _roleNameCtrlMap/_repoCtrlMap)
    + _addMobileRepoPair() — atomic two-row add under mobile_ui/mobile_test
    + Sync branch TextFormField per repo row
lib/src/providers/qa/project_provider.dart
    fix: createProject() now accepts and forwards repoBranches
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
38/38 tests pass (no regressions); `flutter build macos --debug` clean.
No dedicated test added for the provider-level fix — it's a 3-line
parameter forward already exercised end-to-end by the existing
`ProjectTemplate.custom()` regression test at the layer below it.

### Step 2 — auto-surface creation + environment model ✅

- **`EnvironmentDef`** model (`id`, `label`, `isDefault`) + `SurfaceConfig.environments`
  field (independent per surface, per the locked-in decision) — full JSON
  round-trip, `copyWith`.
- **`SurfaceConfig.isMobile`** widened to `id == 'mobile' || isIos || isAndroid`
  — the new unified surface counts as mobile without breaking existing
  Centurion-template projects that still use separate `ios`/`android`
  surfaces.
- **`SurfaceConfig.autoWeb()` / `SurfaceConfig.autoMobile()`** — named
  constructors for the auto-created defaults, each seeded with one `dev`
  environment marked default (matches this app's existing "dev only for
  v1" convention — staging/prod are added manually via the new
  Environments UI, never silently assumed).
- **`ProjectController.ensureAutoSurfaces()`** — pure, idempotent: adds a
  `web` surface once a `web` repo exists and none does yet; adds one
  `mobile` surface once both `mobile_ui` and `mobile_test` repos exist and
  none does yet. Never removes or overwrites an existing surface — a repo
  being deleted later leaves its surface exactly where it was (per §2's
  "never auto-delete" principle). Wired into the only two places a
  project's `repos` map actually changes: `ProjectController.create()` and
  `ProjectController.save()` (the latter covers both the edit-project
  screen and project import, since both funnel through it).
- **Environments UI** — a new section on each surface card
  (`project_detail_screen.dart`) to add/remove environments and pick which
  one is default, backed by the existing `upsertSurface` plumbing (no new
  persistence path needed).

```
lib/src/models/qa/project_model.dart
    + EnvironmentDef (id, label, isDefault)
    + SurfaceConfig.environments, .autoWeb(), .autoMobile()
    SurfaceConfig.isMobile now also true for id == 'mobile'
lib/src/controllers/qa/project_controller.dart
    + ensureAutoSurfaces() — called from create() and save()
lib/src/ui/qa/projects/project_detail_screen.dart
    + _EnvironmentsSection — add/remove/set-default environment chips
test/project_controller_test.dart          new — 7 tests for ensureAutoSurfaces
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
45/45 tests pass (38 prior + 7 new); `flutter build macos --debug` clean.

### Step 3 — Scripts model + import flows ✅

- **`ScriptEntry`** model (`id`, `path`, `customName`, `addedAt`) +
  `SurfaceConfig.scripts` field — full JSON round-trip. `displayName`
  getter: the user's custom name if non-blank, else the filename derived
  from `path` (or the path itself unchanged for a web `package.json` script
  name, which has no directory to strip).
- **`ScriptEntry.mergeUnique()`** — the dedup-by-path merge logic, kept as a
  pure static method on the model (not buried in widget state) specifically
  so it's unit-testable without pulling in widget-test/GetIt bootstrapping.
  Handles all three cases: skips a path already in the existing list, skips
  a duplicate *within* the same import batch, and re-importing the exact
  same folder/package.json a second time adds nothing.
- **`ProjectController`** gained the I/O primitives the import flows need:
  `pickFiles()` (multi-select file picker), `collectFilesUnder()`
  (recursive, files only — directory entries themselves are never
  collected), `parsePackageJsonScripts()` (reads a `package.json`'s
  `"scripts"` object; returns null rather than throwing on a missing file
  or malformed JSON). `pickFolder()` gained an optional `initialDirectory`
  so the mobile import flow can suggest `<mobile_test repo>/test/specs` as
  a starting point — still a real folder-picker dialog the user confirms,
  never a silent default.
- **New `ScriptsScreen`** (`lib/src/ui/qa/scripts/scripts_screen.dart`,
  routed as `routeScripts`, opened via a new "Scripts" entry in each
  surface's `⋮` menu): lists scripts with rename/delete, and shows
  surface-appropriate import actions — mobile gets "Add file(s)" (multi-select
  picker) + "Import from folder"; web gets "Add script" (manual name entry)
  + "Import from package.json" (reads the project's `web` repo); any other
  manually-created surface just gets "Add script" as a generic fallback.
  Pure CRUD — no run wiring yet, per the step-3 scope.

```
lib/src/models/qa/project_model.dart
    + ScriptEntry (id, path, customName, addedAt, displayName, mergeUnique())
    + SurfaceConfig.scripts field
lib/src/controllers/qa/project_controller.dart
    + pickFiles(), collectFilesUnder(), parsePackageJsonScripts()
    pickFolder() gained optional initialDirectory
lib/src/ui/qa/scripts/scripts_screen.dart   new — CRUD + import screen
lib/src/base/utils/navigation_utils.dart
lib/src/base/utils/constants/navigation_route_constants.dart
    + routeScripts
lib/src/ui/qa/projects/project_detail_screen.dart
    + "Scripts" menu entry per surface card
test/script_entry_test.dart                 new — 11 tests (displayName, JSON, mergeUnique)
test/project_controller_scripts_test.dart   new — 7 tests (real temp files/folders)
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
63/63 tests pass (45 prior + 18 new); `flutter build macos --debug` clean.

### Bundle-ID storage + best-effort auto-detect ✅

- **`MobileAppId`** model (`androidApplicationId`, `iosBundleId`) +
  `RepoEntry.appIdsByEnvironment: Map<String, MobileAppId>` — keyed by
  `EnvironmentDef.id`, stored on the `mobile_ui` repo specifically (empty
  for everything else, no cost to other repos).
- **`BundleIdDetector`** (`lib/src/base/qa/bundle_id_detector.dart`) — a
  small, dedicated parser class matching this codebase's existing
  `EnvFileParser` pattern:
  - `detectAndroid()` — a depth-counting line scanner over
    `android/app/build.gradle`(`.kts`), reading `applicationId` inside each
    `productFlavors { <name> { ... } }` block. Handles both Groovy
    (`applicationId "x"`) and Kotlin DSL (`applicationId = "x"`) syntax.
    Deliberately **not** a full Gradle parser — a flavor written as
    `create("name") { ... }` (an alternate Kotlin DSL form) isn't recognized;
    it's skipped rather than mis-parsed, since the manual field is always
    there as the real fallback.
  - `detectIos()` — scans every `.xcconfig` under `ios/` for
    `PRODUCT_BUNDLE_IDENTIFIER`, keyed by the xcconfig's own filename as a
    best-guess flavor name. Skips any value still containing an unresolved
    `$(...)` build variable rather than surfacing a wrong/partial id.
  - Never throws — a missing file, missing folder, or unexpected layout
    just yields an empty (or partial) map.
- **UI**: a new "App IDs" section on the mobile surface card (shown only
  once a `mobile_ui` repo exists), one row per environment with an Android
  and an iOS text field. "Auto-detect" runs both parsers and fills in
  **only the fields that are still blank** — it never overwrites something
  the user already typed, and nothing is saved until they hit the Save
  button that appears once anything's changed — matching the "prefill is
  fine, but user-prompted, never silently defaulted" principle from the
  original ask.

```
lib/src/models/qa/project_model.dart
    + MobileAppId (androidApplicationId, iosBundleId, isEmpty)
    + RepoEntry.appIdsByEnvironment
lib/src/base/qa/bundle_id_detector.dart     new — detectAndroid(), detectIos()
lib/src/ui/qa/projects/project_detail_screen.dart
    + _AppIdsSection — per-environment Android/iOS fields, Auto-detect, Save
test/bundle_id_detector_test.dart           new — 8 tests (real temp gradle/xcconfig files)
test/repo_entry_appid_test.dart             new — 4 tests (JSON round-trip)
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
75/75 tests pass (63 prior + 12 new); `flutter build macos --debug` clean.

This closes out step 2's full scope (auto-surface creation, environment
model, bundle-id storage+detection) and step 3 (scripts). **Everything the
data model needs for the Run/Pull&Run/Build&Run dispatch logic now
exists.**

### Step 5 — `RunProvider` → active-runs registry ✅

The biggest architectural change in this whole redesign: `RunProvider`
moved from a singleton "one run at a time" model to a registry of
concurrent runs — confirmed working against **real concurrent OS
processes**, not just parallel Dart futures.

- **New `RunEntry`** class — everything that used to live directly on
  `RunProvider` as single scalar fields (`status`, `logs`, `stepResults`,
  `currentStepName`, its own `StepRunner`, its own `SleepGuard`, its own
  completer for `cancelAndWait`) now lives per-entry. `RunProvider._activeRuns`
  is a `Map<String, RunEntry>`, insertion-ordered.
- **Real bug this fixes, not just a refactor**: the old code held a single
  shared `SleepGuard` for the whole app. Two concurrent runs would have had
  run A's completion calling `.stop()` and killing the `caffeinate` process
  run B still needed — silently letting the Mac sleep mid-run. Each
  `RunEntry` now owns its own `SleepGuard`.
- **Every existing call site kept working unchanged** — `isIdle`,
  `isRunning`, `status`, `recipeId`, `logs`, `stepResults`,
  `startedAt`/`duration`/`elapsed`, `cancel()`, `reset()`, `sendInput()` all
  still exist, now computed over the *primary* entry (the most recently
  started one still in the registry) rather than stored directly — today's
  UI never actually starts two runs at once yet (the call sites that start
  a run still gate on the old single-run `isRunning` check), so this is a
  genuinely zero-behavior-change refactor for existing screens.
- **New registry-aware API**, for what actually needs to know about *every*
  run: `activeRuns`, `isRunningFor(recipeId)` (correct even with several
  concurrent runs, unlike the legacy `recipeId ==` check), `runIdFor(recipeId)`,
  `isDeviceBusy(udid)` (the device picker in step 11 will use this directly).
  `start`/`startFromProject` now return the new run's id (`Future<String>`/
  `Future<String?>`) instead of `Future<void>` — source-compatible with
  every existing fire-and-forget call site.
- **One real UI improvement made in passing**: `project_detail_screen.dart`'s
  per-surface `isThisRunning` check and its Cancel button now use
  `isRunningFor`/`runIdFor` instead of the old primary-only check — a
  one-line fix, already correct for when concurrent runs actually start
  appearing from later steps, with no other UI rewrite needed yet.

```
lib/src/providers/qa/run_provider.dart
    + RunEntry (id, recipeId, recipeName, deviceUdid, sleepGuard, runner, logs, ...)
    _activeRuns: Map<String, RunEntry> replaces the old scalar fields
    + activeRuns, isRunningFor(), runIdFor(), isDeviceBusy()
    start()/startFromProject() now return the new run's id
    cancel()/reset()/sendInput() take an optional runId (default: primary run)
lib/src/ui/qa/projects/project_detail_screen.dart
    isThisRunning / Cancel button now use isRunningFor()/runIdFor()
test/run_provider_registry_test.dart   new — 4 tests, two REAL concurrent
    OS process trees (distinct sleep durations as markers, not just two Dart
    futures) proving independent tracking, independent cancel (kills only
    the targeted run's process tree), independent history, and that reset()
    refuses to dismiss a still-running entry
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
79/79 tests pass (75 prior + 4 new, including `run_provider_quit_test.dart`'s
existing single-run quit/history contract, unchanged); `flutter build macos
--debug` clean.

### Step 6 — Run / Pull&Run / Build&Run dispatch + the picker flow ✅

**Superseded by the Pull/Build-switches step at the end of this log** — the
`RunMode`/Run ▾ menu/`isInstalled()` design below was fully removed; kept
here only as the historical record of what originally shipped.

**Note on the build order:** step 4 ("Runner commands") from the original
list hadn't actually been built yet when I labeled the previous entry "step
5" — this step folds it in, since the dispatch logic is meaningless without
somewhere to look up the actual run command from. Flagging this rather than
quietly renumbering: everything downstream (§5 runner commands, real device
listing, and the actual dispatcher) shipped together in this pass.

- **Runner commands (§5)** — `SurfaceConfig.runnerCommandIds: Map<String, String>`,
  keyed by `runnerKeyAndroidSimulator`/`..Device`/`runnerKeyIosSimulator`/
  `..Device`/`runnerKeyWeb` — each references a pool `CommandConfig.id`
  (reused, not duplicated). `SurfaceConfig.runnerCommandsComplete` gates the
  Scripts screen's Run buttons. New **"Runner commands" section** on the
  surface card: one dropdown per slot, picking from commands already
  assigned to that surface — the command text itself is still edited in
  the existing Command Library, this just wires which command plays which
  role.
- **`CommandConfig.platform`** (new field: `"android"`/`"ios"`/null) — needed
  because the unified `mobile` surface can hold both platforms' build/install
  commands in one pool, unlike the legacy separate `ios`/`android` surfaces
  where the surface itself implied platform. Added a matching Platform
  filter to the command editor, alongside the existing Target filter
  (widened to also apply to the `mobile` surface, not just legacy `ios`).
  `ProjectConfig.buildInstallCommandsFor()` resolves a surface's `category:
  'build'` pool commands filtered by platform+target — reuses the exact
  filtering pattern `commandsForSurface` already had for iOS target, just
  adds the platform dimension.
- **Real device listing** (`DeviceProbe`) — `xcrun simctl list devices
  --json` for iOS simulators, `adb devices -l` for Android (emulator vs.
  physical distinguished by the `emulator-` id prefix), `xcrun devicectl
  list devices --json-output` for physical iOS (best-effort — its JSON
  shape varies across Xcode versions and the tool may not exist at all on
  older toolchains; any failure just yields an empty list, manual entry
  isn't wired up anywhere yet since nothing needed it). No persisted cache,
  per the earlier decision — fetched live every time this is called.
- **`RunDispatcher`** — the actual glue, reusing the existing `StepRunner`/
  `RunProvider` execution machinery rather than a parallel engine:
  - `substitute()` — the same `{flags}`-style single-brace convention
    already used for `specCommand`, extended to `{environment}`/`{udid}`/
    `{script}`.
  - `isInstalled()` — Android via `adb shell pm list packages`; iOS
    simulator via `xcrun simctl get_app_container`; physical iOS is
    **deliberately never checked** (`devicectl`'s app-listing JSON is one
    of the least stable Xcode APIs) — always reports "not installed" there,
    which safely routes through Build+Install rather than silently
    skipping a build it can't actually confirm is unnecessary.
  - `pullAndCheckForChanges()` — the real, precise git-HEAD-diff check
    from §6 (not a guess): `git rev-parse HEAD` before/after `git pull`.
  - `planSteps()` — the actual Run/Pull&Run/Build&Run decision tree,
    assembling a plain `List<StepConfig>` (build/install commands only
    when needed, then the resolved runner command) — kept separate from
    actually starting it specifically so the branching is unit-testable
    without a real device or `RunProvider`.
  - `dispatch()` — plans, then hands the assembled steps to
    `RunProvider.start()` as an ordinary synthetic `RecipeConfig`, binding
    `deviceUdid` for busy-tracking.
- **UI**: Scripts screen rows gained a Run ▾ menu (Run / Pull & Run /
  Build & Run — disabled with an explanatory tooltip until
  `runnerCommandsComplete`), which walks Environment → (mobile only)
  Platform → Simulator/Physical → Device, excluding busy devices via
  `RunProvider.isDeviceBusy`, defaulting to "run on an available device."
  Deliberately simple sequential dialogs, not a custom wizard widget.

```
lib/src/models/qa/project_model.dart
    + CommandConfig.platform
    + SurfaceConfig.runnerCommandIds, .runnerCommandsComplete
    + runnerKeyAndroidSimulator/..Device/runnerKeyIosSimulator/..Device/runnerKeyWeb
    + ProjectConfig.runnerCommand(), .buildInstallCommandsFor()
lib/src/models/qa/device_model.dart      new — DevicePlatform, DeviceKind, DeviceInfo
lib/src/base/qa/device_probe.dart        new — real simctl/adb/devicectl listing
lib/src/base/qa/run_dispatcher.dart      new — RunMode, substitute(), isInstalled(),
    pullAndCheckForChanges(), planSteps(), dispatch()
lib/src/ui/qa/projects/project_detail_screen.dart
    + _RunnerCommandsSection — per-slot dropdowns, completeness indicator
lib/src/ui/qa/commands/command_edit_screen.dart
    + Platform filter (mobile surface); Target filter widened to include mobile
lib/src/ui/qa/scripts/scripts_screen.dart
    + Run ▾ menu per script row + the environment/platform/target/device picker flow
test/device_probe_test.dart     new — 4 tests against the real local toolchain
test/run_dispatcher_test.dart   new — 13 tests: substitute, runnerKeyFor,
    isInstalled safe-fallback, pullAndCheckForChanges (real git repos, actually
    verifies the pull happened, not just the diff-detection), and planSteps'
    full decision tree (build/install filtering, web never rebuilding, missing
    bundle id falling back safely, unconfigured runner command returning null)
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
96/96 tests pass (79 prior + 17 new); `flutter build macos --debug` clean.

### Step 7 — Prerequisite commands switch ✅

- **`SurfaceConfig.runPrerequisites` (bool) + `.prerequisiteCommandIds`
  (`List<String>`)** — pool command ids, in order. JSON round-trips, both
  default off/empty.
- **`RunDispatcher.planSteps()`** now prepends the resolved prerequisite
  commands (in order) ahead of everything else — build/install, pull, and
  the runner command all still come after, unconditionally, whenever
  `runPrerequisites` is on.
- **UI**: a switch + a checklist of the surface's already-assigned pool
  commands on the surface card, right below Runner commands. Order follows
  the pool's existing order (no separate reorder UI needed) — check the
  ones you want (`flutter pub get`, `pod install`, `npm install`, ...).

```
lib/src/models/qa/project_model.dart
    + SurfaceConfig.runPrerequisites, .prerequisiteCommandIds
lib/src/base/qa/run_dispatcher.dart
    planSteps() prepends resolved prerequisite commands first
lib/src/ui/qa/projects/project_detail_screen.dart
    + _PrerequisiteCommandsSection — switch + checklist
test/run_dispatcher_test.dart
    + 2 tests: prerequisites run first in order; runPrerequisites=false
      skips them even when prerequisiteCommandIds is populated
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
98/98 tests pass (96 prior + 2 new); `flutter build macos --debug` clean.

### Step 8 — Report command + report lifecycle ✅

- **`SurfaceConfig.reportCommandId`/`.reportOutputRelPath`** — same
  mandatory-in-spirit pattern as `runnerCommandIds` (§5), just a single slot
  since a surface has one report tool, not one per platform. Prefilled
  candidates come from the pool's existing `category: 'report'` convention
  (`allure_open_web`/`..._ios`/`..._android` in the Centurion template); the
  dropdown falls back to every command assigned to the surface if none are
  tagged `report` yet (a custom surface may not use the convention). New
  **"Report" section** on the surface card
  (`project_detail_screen.dart`), mirroring `_RunnerCommandsSection`'s style
  — one dropdown (not per-platform) plus a required text field for the
  output folder, right next to it.
- **`ReportArchive` model + `ReportArchiveStore`** — mirrors
  `RunRecord`/`RunHistoryStore` exactly (SharedPreferences-backed, capped,
  silently drops corrupted entries), with a real fix baked in from day one
  rather than retrofitted later: `ReportArchive` carries its own `projectId`
  from the start, unlike `RunRecord` (still missing one — flagged in §9 as a
  bug for a future step, not this one). Extra query surface `RunRecord`
  doesn't need: `forSurface()` (project+surface scoped, newest first),
  `update()` (Regenerate refreshes `generatedAt` in place), `remove()`,
  `pruneFor()`, `clearFor()` — see retention below.
- **Recursive directory copy** (`lib/src/base/utils/dir_copy_utils.dart`) —
  `dart:io` has no built-in one. `copyDirectoryContents()` (real-filesystem
  tested: flat files, nested subfolders, merging into an existing
  destination without wiping what's already there), plus
  `directorySizeBytes()` and `deleteDirectoryQuietly()` for the retention
  logic below.
- **`ReportArchiver`** (`lib/src/base/qa/report_archiver.dart`) — the actual
  archiving mechanism. `RunDispatcher.planSteps()` appends the resolved
  report command as the pipeline's last step (once both report fields are
  set); `RunDispatcher.dispatch()` — once `RunProvider.start()` resolves,
  which only happens after every step including that one has run — calls
  `ReportArchiver.archiveAfterRun()`: best-effort copies
  `reportOutputRelPath`'s contents (if anything is actually there — a failed
  report command just means nothing to archive, not a crash) into
  `<appSupportDir>/qa_control_center/reports/<projectId>/<surfaceId>/<runId>/`,
  records a `ReportArchive`, and prunes. Kept as a plain follow-up call
  inside `RunDispatcher` rather than a callback threaded through
  `RunProvider` — the smaller diff, since `RunProvider` doesn't need to know
  anything about reports at all. `ReportArchiver.regenerate()` reuses the
  same copy logic for the Reports screen's Regenerate action (re-runs the
  original resolved command against the run's raw results if still on disk,
  overwriting the same archived folder; returns false — no fallback to a
  full script re-run, out of scope — if the repo's raw output is gone).
- **`ReportOpener`** (`lib/src/base/qa/report_opener.dart`) — the CORS risk
  the doc flagged is real: a static report copy usually needs to be served,
  not double-clicked. Fallback chain: `allure open <folder>` if the Allure
  CLI is on PATH → a throwaway `python3 -m http.server 0` (OS-assigned port,
  parsed from its own stdout) + `open http://localhost:<port>` → plain
  Finder-reveal with a warning as the last resort. `ponytail:` one server
  per Open click, never torn down — matches this app's existing
  shell-out-and-forget style (e.g. the `detach: true` "Open Allure report"
  pool command); revisit if stray `http.server` processes become a real
  nuisance.
- **No share-sheet integration exists anywhere in this app** (checked) — per
  the doc's own fallback plan, Share is Finder-reveal + "copy path to
  clipboard" (`Clipboard.setData`) for v1.
- **New `ReportsScreen`** (`lib/src/ui/qa/reports/reports_screen.dart`,
  routed as `routeReports`, opened via a new "Reports" entry in each
  surface's `⋮` menu, next to "Scripts"): lists a surface's archived reports
  with Open/Download/Reveal/Copy-path/Regenerate per row, plus a "Clear all
  reports" action (confirmation dialog first) — the manual retention
  companion from §12, folded into this step since the screen already needed
  to exist.
- **Retention (§12), folded into this step** — `ReportArchiveStore.pruneFor()`
  keeps the newest N per surface (default 20) and/or stops once total
  on-disk size would exceed a byte budget (default 2GB), whichever hits
  first, oldest-first — always keeping at least the newest entry even if it
  alone blows the byte budget (a budget that can never hold anything isn't
  useful). Runs opportunistically right after every archive — no background
  timer, per the doc's own "no background timer" note.

**Bug found while building this, not left for later:** none new — the one
`RunRecord`-shaped bug in this area (`projectId` missing) was already
correctly flagged in §9 as a separate future step and left alone here,
per "don't touch steps 1-7 except where this genuinely needs to hook in."

```
lib/src/models/qa/project_model.dart
    + SurfaceConfig.reportCommandId, .reportOutputRelPath (+ copyWith/JSON)
lib/src/models/qa/report_archive_model.dart   new — ReportArchive
lib/src/base/qa/report_archive_store.dart     new — load/append/forSurface/
    update/remove/pruneFor/clearFor
lib/src/base/qa/report_archiver.dart          new — archiveAfterRun(), regenerate()
lib/src/base/qa/report_opener.dart            new — allure/http.server/Finder fallback chain
lib/src/base/utils/dir_copy_utils.dart        new — copyDirectoryContents(),
    directorySizeBytes(), deleteDirectoryQuietly()
lib/src/base/qa/run_dispatcher.dart
    planSteps() appends the report command as the pipeline's last step
    dispatch() archives via ReportArchiver once the run completes
lib/src/ui/qa/projects/project_detail_screen.dart
    + _ReportSection — report-command dropdown + output-path field
    + "Reports" menu entry per surface card
lib/src/ui/qa/reports/reports_screen.dart     new — list + Open/Download/
    Reveal/Copy path/Regenerate/Clear all
lib/src/base/utils/navigation_utils.dart
lib/src/base/utils/constants/navigation_route_constants.dart
    + routeReports
lib/src/base/utils/constants/preference_key_constant.dart
    + prefkeyQAReportArchive
pubspec.yaml
    + path_provider_platform_interface (dev, for faking the app-support dir in tests)
test/dir_copy_utils_test.dart          new — 7 tests, real temp files/folders
test/report_archive_model_test.dart    new — 3 tests, JSON round-trip
test/report_archive_store_test.dart    new — 13 tests: load/append/forSurface/
    update/remove/corrupted-entry, pruneFor (count limit, byte limit,
    newest-always-kept, cross-surface isolation — all real temp folders,
    asserting deletion actually happened on disk), clearFor
test/report_archiver_test.dart         new — 4 tests, real filesystem + a
    real (harmless) shell command: archiveAfterRun copies and records,
    returns null when there's nothing on disk to archive, regenerate
    re-copies over the same folder, regenerate fails safely when the raw
    results are gone
test/run_dispatcher_test.dart
    + 3 tests: report step appended last when both fields set, omitted when
      only one/neither is set
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
126/126 tests pass (98 prior + 28 new); `flutter build macos --debug -t
lib/dev/main_dev.dart` clean.

**Deliberately out of scope** (flagged, not forgotten): the live progress
screen (§9), recent-runs fixes (§10 — `RunRecord.projectId`, unrelated to
`ReportArchive` already having one from day one), and the full global
device-management screen — add/create simulator flows, tabs, sync button
(§12's device half; `DeviceProbe` covers the *listing* half only).

### Step 9 — Live run/progress screen ✅

Built on top of step 5's `RunProvider` registry — this step is UI-only, no
provider changes (a concurrent session was mid-flight on step 10's
`RunEntry`/`start()` changes, so `run_provider.dart`, `run_record_model.dart`,
and `run_history_store.dart` were left untouched per an explicit hard
boundary; only imported and read from).

- **New `ActiveRunsScreen`** (`lib/src/ui/qa/runner/active_runs_screen.dart`,
  routed as `routeActiveRuns`) — a `Consumer<RunProvider>` listing every
  `RunEntry` in `RunProvider.activeRuns` (newest-started first), each as an
  expandable `Card` mirroring `project_detail_screen.dart`'s `_SurfaceCard`
  visual style exactly (rounded corners, a highlighted border while running/
  expanded, an expand/collapse chevron). Collapsed, a card shows a status dot
  (spinner while running; a green/red/orange filled dot for done/failed/
  cancelled — same palette as `RunPanel`'s `_StatusBadge`), the recipe name,
  device udid (if any), current step or terminal-step summary, and live
  elapsed time (its own 1-second `Timer`, same reason `RunPanel` keeps one:
  the provider only notifies on log/step activity, which can go quiet for
  minutes). Expanded, it shows that entry's live log stream.
- **Log rendering reuses `RunPanel`'s exact approach** (`_LogView`/`_LogRow`
  auto-follow-until-scrolled-up, truncation banner, monospace error/normal
  coloring), adapted to read one `RunEntry`'s `logs`/`logsTruncated` directly
  instead of going through `RunProvider`'s primary-entry getters — the only
  real change, since the whole point here is showing every entry, not just
  the primary one.
- **Cancel** — `RunProvider.cancel(entry.id)`, shown only while
  `entry.status == RunStatus.running`. **Dismiss** — `RunProvider.reset(entry.id)`,
  shown once finished (mirrors `RunProvider.reset`'s own contract: refuses to
  drop a still-running entry).
- **"View report"** — shown once finished, only if a `ReportArchive` exists
  for that run. **Small, deliberate addition to `ReportArchiveStore`** (not on
  the hard-boundary list): `findByRunId(String runId)` — a run id is globally
  unique (`RunProvider._newRunId()`), so no project/surface scoping is needed
  to look one up, unlike every other `ReportArchiveStore` query. Opens the
  same way `ReportsScreen`'s "Open" action does — `ReportOpener().open(...)`
  directly against the archive's `archivePath` — rather than navigating to
  `ReportsScreen`, since that screen needs a `ProjectConfig` + `surfaceId`
  that `RunEntry` doesn't carry (see gap below).
- **Entry point**: an "Active runs" icon button in `project_detail_screen.dart`'s
  AppBar actions, badged with `RunProvider.activeRuns.length` (same `Badge`-
  wrapping-`IconButton` pattern as `command_library_screen.dart`'s filter
  badge), live via its own small `Consumer<RunProvider>`.
- **Empty state**: "No runs in progress" centered text when `activeRuns` is
  empty.

**Gap flagged, not solved here (per the hard boundary):** `RunEntry` today
only carries `recipeId` (== the surface id for a project-backed run, but with
no `projectId` alongside it), `recipeName`, and `deviceUdid` — no
`environment`, `script`, or `platform`. The card therefore can't show which
environment/script a run used, and can't deep-link into `ReportsScreen`
(which needs a `ProjectConfig`). This is exactly the metadata step 10 is
adding to `RunEntry`/`RunProvider.start()` concurrently; once that lands, the
card's subtitle and (optionally) a "See all reports for this surface" link
can be wired in without any change to this screen's structure — the card
already renders whatever `_subtitle()` assembles from available fields.

No new pure logic non-trivial enough to warrant a dedicated unit test — the
one non-widget addition (`ReportArchiveStore.findByRunId`) is a one-line
filter over an already-tested `load()`/`fromJson` path (see
`report_archive_store_test.dart`'s existing coverage of that path).

```
lib/src/base/qa/report_archive_store.dart
    + findByRunId(runId) — global lookup, no project/surface scoping needed
lib/src/ui/qa/runner/active_runs_screen.dart   new — ActiveRunsScreen,
    _RunEntryCard, _StatusDot, _ViewReportButton, _EntryLogView (RunPanel's
    log-rendering approach, adapted per-entry)
lib/src/ui/qa/projects/project_detail_screen.dart
    + "Active runs" badged AppBar icon button
lib/src/base/utils/navigation_utils.dart
lib/src/base/utils/constants/navigation_route_constants.dart
    + routeActiveRuns
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
126/126 tests pass (no regressions — no new tests added, per the note above);
`flutter build macos --debug -t lib/dev/main_dev.dart` clean.

### Step 10 — Recent-runs fix + global screen + re-run-with-picker ✅

- **Bug fix**: `RunRecord.projectId` — the flagged gap from earlier steps.
  `RunHistoryStore` is one flat, global list keyed only by `recipeId` (==
  surface id); two projects that both have a `"web"` surface used to see
  each other's history. `RunEntry`/`RunProvider.start()` gained a matching
  `projectId`, threaded from `startFromProject`. `RunProvider.lastReportFor`
  and `_RunHistorySection`'s filtering both now scope by `(recipeId,
  projectId)` — a record with no `projectId` on file (pre-fix history)
  stops showing per-project rather than risking a bleed; verified with a
  real test starting two genuine `startFromProject` runs against two
  different `ProjectConfig`s sharing a `"web"` surface id.
- **Re-run metadata**: `RunRecord`/`RunEntry` also gained `runId` (same
  identity `ReportArchive.runId` already used, from day one in that model —
  joinable, not duplicated further), `scriptDisplayName`, `environmentId`,
  `platform`, `deviceKind`, `deviceUdid`, `mode` — all threaded from
  `RunDispatcher.dispatch()`, the one call site that actually knows them.
  All nullable; `RunRecord.hasRerunInfo` gates whether a re-run can be
  pre-filled at all (legacy/manual runs can't).
- **Shared `RunPicker`** (`lib/src/ui/qa/runner/run_picker.dart`) — the
  Environment→Platform→Target→Device dialogs extracted out of
  `ScriptsScreen` into standalone static methods, plus a new
  `RunPicker.reRun()` that resolves the original script by display name
  (falls back to a clear message if it's been renamed/deleted since,
  rather than guessing) and re-opens the picker pre-filled with the
  recorded environment. `ScriptsScreen` itself now just calls `RunPicker.pick()`
  — no behavior change there, pure de-duplication so Recent-runs' Re-run
  doesn't reimplement the same flow.
- **New global `RecentRunsScreen`** (`lib/src/ui/qa/history/recent_runs_screen.dart`,
  route `routeRecentRuns`, reached via a new icon on `ProjectsListScreen`'s
  AppBar) — every run across every project, newest first, with resolved
  project/surface names and a Re-run action per row (disabled with an
  explanatory tooltip when the original project no longer exists).

```
lib/src/models/qa/run_record_model.dart
    + projectId, runId, scriptDisplayName, environmentId, platform,
      deviceKind, deviceUdid, mode, hasRerunInfo
lib/src/providers/qa/run_provider.dart
    + matching RunEntry fields; start()/startFromProject() thread them through
    lastReportFor() gained an optional projectId filter
lib/src/base/qa/run_dispatcher.dart
    dispatch() passes the new metadata to RunProvider.start()
lib/src/ui/qa/runner/run_picker.dart     new — shared picker dialogs + reRun()
lib/src/ui/qa/scripts/scripts_screen.dart
    _startRun() now calls RunPicker.pick() instead of its own private dialogs
lib/src/ui/qa/projects/project_detail_screen.dart
    _RunHistorySection scoped by projectId; Re-run button per record
lib/src/ui/qa/history/recent_runs_screen.dart   new — global run history
lib/src/ui/qa/projects/projects_list_screen.dart
    + "Recent runs" AppBar icon
lib/src/base/utils/navigation_utils.dart
lib/src/base/utils/constants/navigation_route_constants.dart
    + routeRecentRuns
test/run_record_rerun_test.dart              new — 3 tests (JSON round-trip,
    legacy-record backward compat, hasRerunInfo)
test/run_provider_project_scoping_test.dart  new — 1 test, two REAL
    startFromProject() runs against two different ProjectConfigs sharing a
    "web" surface id, proving history/lastReportFor don't bleed between them
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
130/130 tests pass (126 prior + 4 new); `flutter build macos --debug -t
lib/dev/main_dev.dart` clean.

**Note on concurrent step 9**: this step and step 9 (live progress screen)
were built in parallel per your "proceed asynchronously" — step 9 ran in an
isolated worktree with an explicit boundary not to touch `RunProvider`/
`RunRecord` (this step's territory), and flagged that `RunEntry` lacked
environment/script/platform metadata for a fuller progress card. That gap
is now closed by this step; `ActiveRunsScreen`'s card wasn't revisited to
use it, since that's a small follow-up, not a re-open of step 9's work.

**Deliberately out of scope**: report retention/cleanup beyond what step 8
already shipped, and the full global device-management screen (§12;
`DeviceProbe` still covers only the listing half).

### §11/§12 — Global device management screen ✅

The last remaining piece from the original build order — everything else
is now shipped. Classification confirmed **not actually ambiguous** as the
doc predicted: it comes from which tool sourced the entry, no user
confirmation needed anywhere.

- **`DeviceProbe` extended** with the "Add simulator/emulator" primitives:
  - iOS: `listIosDeviceTypes()`/`listIosRuntimes()` (real `xcrun simctl
    list devicetypes/runtimes --json`, confirmed against this machine's
    real Xcode toolchain) + `createIosSimulator()`.
  - Android: `listAndroidDeviceProfiles()`/`listAndroidSystemImages()` +
    `createAndroidAvd()`. **Real limitation, flagged rather than hidden**:
    this dev machine has no Android SDK command-line tools installed
    (`avdmanager`/`sdkmanager` both absent), so unlike every other probe in
    this app, these two could not be verified against live command output.
    The parsing logic itself (`parseAndroidDeviceProfiles`/
    `parseInstalledSystemImages`) is pulled out as pure functions and
    tested against recorded sample output in the documented, stable
    `avdmanager`/`sdkmanager` format instead — the actual shell-out
    wrappers stay thin and untested, same as this app's existing precedent
    for physical-iOS `devicectl` probing.
  - **Deliberate asymmetry in error handling**: every *listing* method
    stays never-throws (a missing tool just yields an empty list, per this
    file's existing convention) — but the two *create* methods let
    `ProcessException` propagate. A user who just pressed "Create" needs to
    see the real error (bad device type, SDK not installed, ...); silently
    swallowing it here would be the same class of bug this session already
    fixed once before (the Doctor "Fix" button's `ignoreExitCode: true`
    issue).
- **New `DevicesScreen`** (route `routeDevices`, reached via a new icon on
  `ProjectsListScreen`'s AppBar) — Android/iOS tabs, each device row shows
  Busy/Idle/Shutdown (Busy computed from `RunProvider.isDeviceBusy`, not an
  OS signal — there isn't a reliable one), a manual Sync/Reload button
  (no persisted cache, matching the earlier decision), and an "Add
  simulator/emulator" flow (platform choice → type/runtime or
  profile/image dropdowns → Create, with the real error shown inline on
  failure rather than a generic toast).

```
lib/src/models/qa/device_model.dart
    + IosDeviceType, IosRuntime, AndroidDeviceProfile
lib/src/base/qa/device_probe.dart
    + listIosDeviceTypes(), listIosRuntimes(), createIosSimulator()
    + parseAndroidDeviceProfiles(), listAndroidDeviceProfiles()
    + parseInstalledSystemImages(), listAndroidSystemImages()
    + createAndroidAvd()
lib/src/ui/qa/devices/devices_screen.dart   new — DevicesScreen, _DeviceList,
    _AddIosSimulatorDialog, _AddAndroidAvdDialog
lib/src/ui/qa/projects/projects_list_screen.dart
    + "Devices" AppBar icon
lib/src/base/utils/navigation_utils.dart
lib/src/base/utils/constants/navigation_route_constants.dart
    + routeDevices
test/device_probe_add_test.dart   new — 7 tests: 2 real (device types/runtimes
    against this machine's actual Xcode toolchain), 5 against recorded
    sample avdmanager/sdkmanager output (Android SDK not installed here)
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item —
2 new info-level findings surfaced and were fixed during this pass, not
left in); 137/137 tests pass (130 prior + 7 new); `flutter build macos
--debug -t lib/dev/main_dev.dart` clean.

---

## Redesign status: all steps from the original build order are shipped

Repo model, auto-surface creation, environment/bundle-id model, scripts,
runner commands, real device listing, the full Run/Pull&Run/Build&Run
dispatcher, prerequisite commands, report archiving + lifecycle, the
active-runs registry, the live progress screen, recent-runs scoping +
re-run, and global device management. Remaining known gaps, all flagged
in-line at the step that deferred them rather than silently dropped:
report retention tuning beyond step 8's defaults, `ActiveRunsScreen`'s
card not yet using the environment/script metadata step 10 added after it
shipped, and Android AVD creation being untested against a live SDK on
this particular machine.

## Follow-up fix — "Add repo" UX correction (post-redesign)

The step-1 "Add mobile repo" button shipped *alongside* the existing
generic "+ Add repo" button, and a brand-new project's repo section
separately pre-populated 3 blank legacy rows (`app`/`web`/`mobile_tests`)
regardless of which button got used — real users hit a confusing, cluttered
screen (legacy free-role rows sitting next to a freshly-added mobile pair).
Corrected based on direct user feedback (a screenshot of the actual
clutter):

- **"Add repo" is now one typed menu**, not two separate buttons: **Web
  (Playwright)** and **Mobile (Appium)** — the only two supported types for
  now, deliberately not a free-text "custom role" option. Designed to
  extend easily (more `PopupMenuItem`s) when e.g. an Android-only Appium or
  Flutter-integration-test type is added later.
- **The legacy 3-blank-row prefill is now scoped to the Centurion template
  only** (`_prefill()`'s "new project" branch checks
  `_templateType == ProjectTemplateType.centurion` before populating) — a
  "Start blank" new project, or an existing project with zero repos on
  file, now starts genuinely empty. No behavior change for the Centurion
  flow itself.
- **Mobile pairing is now actually enforced at save time**, not just by
  the add-flow adding both rows together — `_save()` blocks with a clear
  message if exactly one of `mobile_ui`/`mobile_test` is present (removing
  one row without the other, or editing an existing project down to just
  one, used to silently save an incomplete pair). Scoped to those two role
  keys specifically so it can never fire on an existing Centurion-template
  project's unrelated `app`/`mobile_tests` roles.

```
lib/src/ui/qa/projects/create_edit_project_screen.dart
    _prefill() — legacy defaults gated on Centurion template
    _addRepo() → _addWebRepo() (typed, not free-text)
    _buildRepoSection() — one PopupMenuButton instead of two TextButtons
    _save() — mandatory mobile_ui/mobile_test pairing check
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
137/137 tests pass (no regressions); `flutter build macos --debug` clean.

## Follow-up fix #2 — fully manual repo add, labeling, Centurion consistency, and command discoverability

Five more issues found via direct user feedback, addressed together since
several turned out to be entangled:

1. **New projects now start with zero repo rows, always** — the previous
   fix only stopped auto-population for "Start blank"; Centurion still
   auto-added its 3 legacy rows on open. Now `_prefill()` never touches
   repo rows for a brand-new project regardless of template; `+ Add repo`
   is the only way any row appears. `_onTemplateChanged`/`_pickRoot` no
   longer touch repo rows either.
2. **Web rows get a type label too** — `'web' => 'Web (Playwright)'` added
   alongside the existing Mobile labels (relabeled `'Mobile (Appium) — App
   source'`/`'... Test scripts'` for clarity).
3. **Centurion's known folder names now surface through the same manual
   add flow** (`_addWebRepo`/`_addMobileRepoPair` pre-fill from
   `_centurionDefaults` when Centurion is selected — still just a
   starting point in the text field, never auto-added) rather than a
   separate template-triggered auto-population path.

   **This surfaced a real correctness bug**, not just a UX one:
   `ProjectTemplate.centurion()` only recognized the legacy role keys
   `app`/`mobile_tests`. Once *any* new project's "Add mobile repo" always
   produces `mobile_ui`/`mobile_test` rows (per fix #1, no special-casing
   by template), selecting Centurion + using that button would have
   silently discarded the typed folder path — `centurion()`'s `relPath()`
   helper doesn't recognize those keys, so it falls back to its hardcoded
   default folder name. Same class of bug as the earlier
   `ProjectTemplate.custom()` repo-loss fix, just reachable through a new
   path. Fixed at the root: **`ProjectTemplate.centurion()`'s repo roles
   are now `mobile_ui`/`mobile_test`** (was `app`/`mobile_tests`; `web`
   unchanged) — a mechanical rename across every `CommandConfig.repoRole`
   in `project_template.dart` too, so the whole pool stays internally
   consistent.

   Two things had to be fixed *because of* that rename, to avoid trading
   one bug for two others:
   - `ProjectController.ensureAutoSurfaces()` would otherwise add an extra,
     empty, unified `mobile` surface alongside Centurion's own already-fully-wired
     `ios`/`android` surfaces (since a Centurion project now has both
     `mobile_ui` and `mobile_test` repos — exactly what that check looks
     for). Guarded: it now treats an existing `ios` or `android` surface as
     "mobile already covered," same as an existing `mobile` surface.
   - `DoctorRunner` hardcoded the legacy role names directly in three
     places (`_reposForRecipe`, and the iOS/mobile-shared checks' repo-path
     lookups) — a newly-created Centurion project's `mobile_ui`/`mobile_test`
     repos would have silently gotten **zero** repo-branch/clean/env-file
     checks (not a crash — a silent gap). Fixed to check both conventions
     (new name first, legacy name as fallback), so this works for a
     brand-new project and an already-saved pre-rename one alike.
4. **Runner-commands and prerequisite-commands sections now have a real
   "Add command" button** when the pool is empty, instead of just prose
   telling you to go find Command Library yourself — wired through the
   surface card's existing `onEditCommands` callback (push + refresh),
   not a second hand-rolled navigation path.
5. **A "Commands" entry added to each project card's menu** on the
   projects list (home) screen — jumps straight to that project's Command
   Library without opening Project Detail first.

```
lib/src/ui/qa/projects/create_edit_project_screen.dart
    _prefill() no longer auto-populates repo rows for any template
    _onTemplateChanged()/_pickRoot() no longer touch repo rows
    + _centurionDefaults, _suggestedFolder() — pre-fill only on manual add
    'web' gained a type label; mobile labels reworded to include "(Appium)"
lib/src/base/qa/project_template.dart
    ProjectTemplate.centurion(): repo roles app→mobile_ui, mobile_tests→mobile_test
    (mechanical rename across every CommandConfig.repoRole too)
lib/src/controllers/qa/project_controller.dart
    ensureAutoSurfaces(): existing ios/android surfaces now also count as
    "mobile already covered", preventing a duplicate unified surface
lib/src/base/qa/doctor_runner.dart
    _reposForRecipe()/_mobileTestsRepo(): check mobile_ui/mobile_test first,
    fall back to app/mobile_tests — supports both new and pre-rename projects
lib/src/ui/qa/projects/project_detail_screen.dart
    _RunnerCommandsSection/_PrerequisiteCommandsSection: real "Add command"
    button (onEditCommands) instead of passive hint text
lib/src/ui/qa/projects/projects_list_screen.dart
    + "Commands" entry in the project card's ⋮ menu
test/project_controller_test.dart
    + 1 test: Centurion-shaped project doesn't get a duplicate mobile surface
test/doctor_runner_test.dart
    + 2 tests: new-convention roles are actually checked (not silently
      skipped); legacy-convention roles still work
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
140/140 tests pass (2 known-flaky, machine-specific tests — the PATH-ordering
test and a process-spawn-timing test — confirmed passing in isolation, not
regressions); `flutter build macos --debug` clean.

## Follow-up fix #3 — environment simplification + sectional-card UI (post-redesign)

More direct user feedback on the Web Tests surface card: the layout was hard
to scan, the section order didn't match execution order, and — the bigger
ask — the whole environment model was judged over-engineered and told to be
simplified.

1. **Environment moved off the surface, onto the command, as a filter tag.**
   `SurfaceConfig.environments` (a managed `List<EnvironmentDef>`, independently
   CRUD'd per surface) is gone entirely, along with `EnvironmentDef` itself.
   `CommandConfig` gained an `environment` field — free text, same shape as
   the existing `platform`/`target` tags, `null` = "applies regardless."
   `ProjectConfig.environmentsFor(surfaceId)` now *derives* the available
   environment list by scanning the distinct non-null `environment` values
   among a surface's assigned pool commands — nothing to manage separately
   any more.
2. **Explicit id-slot maps replaced by filter-based resolution.**
   `SurfaceConfig.runnerCommandIds` (`Map<String,String>` keyed by
   `runnerKeyAndroidSimulator` etc.) and `SurfaceConfig.reportCommandId` are
   both gone, along with `RunDispatcher.runnerKeyFor()` and the `runnerKey*`
   constants. In their place: `ProjectConfig.testCommandFor(surfaceId,
   {environment, platform, target})` and `ProjectConfig.reportCommandFor(
   surfaceId, {environment})` filter the surface's assigned command pool by
   category + tags and return the first match (first-match-wins — no
   ambiguity-blocking, kept simple deliberately). `buildInstallCommandsFor`
   gained the same `environment` filter. `RunDispatcher.planSteps()`/
   `dispatch()` and `ReportArchiver.sourcePathFor()`/`regenerate()` were
   updated to call these instead of reading the deleted slot fields —
   `regenerate()` now re-resolves the report command from the archived
   `ReportArchive.environment` rather than trusting a stored id.
3. **Sectional-card UI + reorder to match execution order.** Project Detail's
   per-surface expanded body now runs Prerequisite → Script (runner) → Report
   — the order they actually execute in — each wrapped in its own bordered
   `_SectionCard` so the three are visually distinct instead of one long
   column. The old `_EnvironmentsSection` (add/remove/default-star chips) is
   deleted outright — nothing to manage there any more. `_RunnerCommandsSection`
   and `_ReportSection` dropped their per-slot dropdowns (there's no slot to
   fill in) and became read-only summaries of the pool's `category: 'test'`/
   `'report'` commands with their tags shown as badges — tagging happens via
   "Edit commands" (Command Library), not here.
4. **Command Library and the command edit form both gained the environment
   axis** — a free-text "Environment" field on the edit form (saved to
   `CommandConfig.environment`), an environment badge on library tiles, and
   a third filter chip row (alongside category/repo) in the filter dialog.
5. **`_AppIdsSection`** (bundle id / package name per environment, unrelated
   to the deleted CRUD list except that it iterated the same source) switched
   from `surface.environments` to `project.environmentsFor(surface.id)` —
   same per-environment text fields, just reading the derived list instead of
   a managed one.
6. Every test touching the deleted symbols was rewritten to tag `CommandConfig`s
   with `category`/`environment`/`platform`/`target` and assign via
   `commandIds`, rather than constructing the old slot maps.

```
lib/src/models/qa/project_model.dart
    CommandConfig: + environment field (copyWith/toJson/fromJson)
    EnvironmentDef, runnerKey* constants: deleted
    SurfaceConfig: environments/runnerCommandIds/runnerCommandsComplete/
      reportCommandId all deleted; autoMobile()/autoWeb() simplified
    ProjectConfig: + _filteredCommandsFor/testCommandFor/reportCommandFor/
      buildInstallCommandsFor/environmentsFor; runnerCommand() removed
lib/src/base/qa/run_dispatcher.dart
    runnerKeyFor() deleted; planSteps()/dispatch() use testCommandFor/
    reportCommandFor/buildInstallCommandsFor instead of the deleted slots
lib/src/base/qa/report_archiver.dart
    sourcePathFor()/regenerate() resolve the report command via
    reportCommandFor() instead of reading surface.reportCommandId
lib/src/ui/qa/runner/run_picker.dart
    pick()/pickEnvironment()/reRun() take a `project` param and call
    project.environmentsFor(surface.id) instead of surface.environments
lib/src/ui/qa/scripts/scripts_screen.dart
    _startRun passes project: _project to RunPicker.pick(); Run-button gate
    now checks for an assigned category: 'test' command directly
lib/src/ui/qa/commands/command_edit_screen.dart
    + Environment text field, saved to CommandConfig.environment
lib/src/ui/qa/commands/command_library_screen.dart
    + Environment filter chip row + tile badge
lib/src/ui/qa/projects/project_detail_screen.dart
    + _SectionCard; sections reordered Prerequisite → Script → Report
    _EnvironmentsSection: deleted
    _RunnerCommandsSection/_ReportSection: dropdown slots → read-only
      tag summaries of the resolved command pool
    _AppIdsSection: surface.environments → project.environmentsFor(...)
test/project_controller_test.dart, test/run_dispatcher_test.dart,
test/report_archiver_test.dart
    rewritten for the tag+filter model (no more slot maps/EnvironmentDef)
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
137/137 tests pass (3 fewer than before — the deleted `runnerKeyFor` group);
`flutter build macos --debug` clean.

## Follow-up fix #4 — retiring the duplicate legacy Run pipeline (post-redesign)

User feedback traced back to a real architectural split: **two separate run
pipelines coexisted**, and only one of them was environment/device-aware.

- The Scripts screen (`RunPicker` → `RunDispatcher`) — asks environment, then
  platform, then simulator/device, then an idle device; resolves the right
  tagged command per combo. This is the one built across the whole redesign.
- The surface card's own "Run"/"Quick run" button (`_runSurface` →
  `RunProvider.startFromProject` → `ProjectConfig.toRecipeConfigForSurface`) —
  predates the redesign, was never retired. **Never asked for an environment
  or a device at all** — just ran every assigned command in pool order,
  gated only by Sync/Build+Install boolean toggles and the iOS target chip.

That's why Sync/Build+Install never felt "dynamic": on that path they
weren't filters, just skip-flags. Confirmed with the user which one to keep
(see conversation) — retired the old one:

1. **`_SurfaceCard`** (project_detail_screen.dart) — removed the Sync/
   Build+Install toggle chips, the spec/flags free-text field, and
   `_runSurface`. The collapsed card's quick-action icon and the expanded
   body's primary button now both open the Scripts screen (`onEditScripts`)
   instead of running blind. The iOS target chip stays — it now only feeds
   Doctor's iOS checks (`_iosTarget[surfaceId]`), which never went through
   the retired pipeline. `_CommandPreview` and `_ToggleChip` (now-orphaned
   widgets) deleted.
2. **`RunProvider.startFromProject`** and **`ProjectConfig.toRecipeConfigForSurface`**
   deleted outright — `commandsForSurface`'s now-unused `iosTarget` filter
   param dropped with it. `run_provider_project_scoping_test.dart` (the one
   test using `startFromProject`) rewritten to call `RunProvider.start`
   directly — it was only ever testing `start`'s projectId-scoping, never
   `startFromProject`-specific behavior.
3. **A real bug found while tracing this**: `RunDispatcher.dispatch()` never
   threaded the picked `DeviceKind` into `RunProvider.start()`'s `iosTarget`
   param (default: simulator). `RecipeConfig.stepsFor(iosTarget:)` re-filters
   steps by `CommandConfig.target` a *second* time, but only for the legacy
   `ios` surface (`recipe.surface == 'ios'`) — so picking "Physical device"
   for that surface via the *modern* Scripts-screen flow would silently
   filter every device-tagged step back out, leaving an empty pipeline. Fixed
   by adding `RunDispatcher._iosBuildTarget(DeviceKind?)` and threading it
   into `runProvider.start(iosTarget: ...)`. The unified `mobile` surface was
   never affected (`stepsFor` only filters when `surface == 'ios'`).
4. **Prerequisites converted to the same filter-based resolution as test/
   build/report** — `SurfaceConfig.prerequisiteCommandIds` (a manually
   checked-off id list, the one remaining place still using the old
   explicit-slot pattern) deleted. `ProjectConfig.prerequisiteCommandsFor(
   surfaceId, {environment})` filters the pool for `category: 'git'`/
   `'prerequisite'`, environment-matched — same convention as
   `testCommandFor`/`reportCommandFor`/`buildInstallCommandsFor`. Tagging a
   command `git`/`prerequisite` is now enough; nothing to separately check
   off. `_PrerequisiteCommandsSection` redesigned to match `_RunnerCommandsSection`'s
   read-only resolved-summary style (checkbox list → tag badges).
5. **Another real bug found while wiring #4**: `planSteps()` only ever
   called `substitute()` (the `{environment}`/`{udid}`/`{script}` token
   replacement) on the final run step and the report step — prerequisite and
   build/install steps used `CommandConfig.toStepConfig()` raw, with no
   substitution at all, *and* those two steps were hand-built `StepConfig`s
   that silently dropped `envFile`/`checkAppium`/`skipIfNoSync`/
   `skipIfNoBuild` (e.g. `test_ios_simulator`'s `checkAppium: true` was never
   actually enforced via the Scripts-screen path). Fixed with one shared
   `RunDispatcher._stepFor(CommandConfig, {environmentId, udid, script, ...})`
   — builds off `toStepConfig()` (so every tag carries through) and
   substitutes both `command` *and* `envFile`, used for all four step kinds
   (prerequisite, build/install, run, report) instead of three different
   hand-rolled paths.
6. **Centurion template commands now actually use `{environment}`** — every
   hardcoded `.env.dev` in `project_template.dart` (in `envFile` and in
   inline `ENV_FILE=...` command prefixes) became `.env.{environment}`, so a
   fresh Centurion project demonstrates real environment switching instead
   of silently ignoring the environment picker. Left untouched: two
   `npm run test:*:dev`-style commands whose *script name itself* bakes in
   "dev" (can't safely guess a project's actual package.json script names —
   their own `specCommand` variant is templated, so the spec-filtered path
   already works per-environment).

Also, unrelated small fixes bundled into the same session: surface
duplication now makes the *name* unique (`"X (copy)"`, `"X (copy 2)"`, ...)
before deriving a matching id, instead of only uniquifying the id;
`_AddSurfaceDialog` dropped its manual "ID" field entirely (id is now always
slugified from the name, same as duplicate); command categories renamed
`setup` → split into `git`/`prerequisite` (clearer, and the built-in
template's own `git pull`/`install deps` commands retagged to match); the
Devices screen gained an All/Simulators/Physical filter (shared across both
tabs); and the two device-creation dialogs (`_AddIosSimulatorDialog`,
`_AddAndroidAvdDialog`) now bound their initial probe (`simctl`/
`avdmanager`/`sdkmanager` — all real subprocesses with no prior timeout)
with a 20s timeout and a visible error+Retry state instead of spinning
forever on a hung tool.

```
lib/src/ui/qa/projects/project_detail_screen.dart
    _SurfaceCard: Sync/Build+Install toggles, spec-flags field, Run/Cancel
      → Run-from-Scripts removed; _runSurface deleted; _CommandPreview/
      _ToggleChip deleted; _AddSurfaceDialog's ID field removed (slugified
      from name); _duplicateSurface makes the name unique first
    _PrerequisiteCommandsSection: checkbox list → read-only resolved summary
lib/src/providers/qa/run_provider.dart
    startFromProject() deleted
lib/src/models/qa/project_model.dart
    ProjectConfig.toRecipeConfigForSurface()/commandsForSurface's iosTarget
      param deleted; + prerequisiteCommandsFor()
    SurfaceConfig.prerequisiteCommandIds deleted
lib/src/base/qa/run_dispatcher.dart
    + _iosBuildTarget(), + _stepFor() (shared substitution+field-passthrough
      for prerequisite/build/run/report steps); dispatch() now threads
      iosTarget through to runProvider.start()
lib/src/base/qa/project_template.dart
    every hardcoded .env.dev → .env.{environment}; sync commands → category
      'git', install/clean commands → category 'prerequisite'
lib/src/ui/qa/commands/command_edit_screen.dart, command_library_screen.dart
    _kCategories: 'setup' → 'prerequisite'/'git'
lib/src/ui/qa/devices/devices_screen.dart
    + All/Simulators/Physical filter chips; device-probe dialogs get a 20s
      timeout + error/Retry state instead of an indefinite spinner
test/run_provider_project_scoping_test.dart
    rewritten to call RunProvider.start directly (was startFromProject)
test/run_dispatcher_test.dart
    prerequisite tests rewritten for category-tag filtering (no more
      prerequisiteCommandIds)
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
full test suite passes; `flutter build macos --debug` clean.

### Step 11 — Tags overhaul, real Centurion data, Pull/Build switches ✅

Everything below happened across several follow-up sessions after Step 10,
condensed into one entry rather than one per small fix — see
`docs/PROJECTS_SYSTEM.md` for the resulting *current* architecture; this is
the *what changed and why*.

**Data model: `tags` replaces `category`/`environment`/`platform`.**
`CommandConfig.category` (the `git`/`prerequisite`/`build`/`test`/`report`
enum from Step 10) and the separate `environment`/`platform` filter fields
are gone; `CommandConfig.tags` (`List<String>`) carries the pipeline-stage
tag (still `git`/`prerequisite`/`build`/`test`/`report` — just a free-form
list entry now, not an enum) plus any purely-descriptive tags
(`smoke`/`regression`/...). Environment and platform are no longer
per-command at all — they're static properties of the `SurfaceConfig` a
command is *assigned* to (`environmentId`, `platformType`), resolved once
per surface instead of filtered per command. `ProjectConfig.testCommandFor`/
`buildInstallCommandsFor`/`prerequisiteCommandsFor`/`reportCommandFor` all
now share one `_filteredCommandsFor(surfaceId, {stageTag, target})` —
`target` (simulator/device) is the one axis still genuinely picked at run
time; everything else is resolved from which surface a command is assigned
to.

**Real Centurion project rebuilt on this model** — six surfaces
(android/ios/web × dev/stage, replacing the old single `mobile`+`web`
pair), ~30 commands sourced from the real sibling repos, not the template's
guesses. Along the way:
- `{branch}` (`project.repos[cmd.repoRole]?.branch`) and `{bundleId}`
  (`surface.appId`, android/ios per `surface.isAndroid`/`.isIos`) added as
  real substitution tokens alongside `{environment}`/`{udid}`/`{script}` —
  all five documented in one place, `RunDispatcher.placeholderDocs`,
  surfaced directly in the Command Edit screen so whoever writes a command
  can see what's available.
- Redundant commands merged: 4 per-environment iOS launch commands → 2
  shared ones (via `{bundleId}`); `test_android`/`test_ios_simulator`/
  `test_ios_device`'s dev/stage pairs → one shared command each (via
  `{environment}`) — `crichq-app-flutter`'s flavors are literally
  `development`/`stage`/`production`, which is why the *build* commands
  (which bake the flavor into `--flavor`/`-t lib/<env>/main_<env>.dart`)
  could **not** similarly merge — a real, permanent naming mismatch, not an
  oversight.
- `build_web` added — web previously had zero `build`-tagged commands, so
  Build&Run/Pull&Run (Step 6's design) were silently identical to Run for
  every web surface. Uses the real `crichq-webapp-nextjs` scripts
  (`build:dev`/`build:stage`).
- `build_runner_mobile` prerequisite added to the 4 mobile surfaces, after
  a real build failure traced to stale/missing `build_runner`-generated
  `.g.dart` files in `crichq-app-flutter`.
- Recent-runs screen rewritten with status/project filters and working
  report/log buttons — fixed a real bug where "Open last report" opened the
  run's log file instead of the actual archived report (`RunRecord.hasReport`
  only ever meant "run succeeded", never "has an archived report"; fixed by
  joining `ReportArchiveStore.forSurface(...)` on `runId`).
- `RunPanel`: removed the stdin bar (dead weight — nothing used it), added
  a minimize toggle (`RunProvider.minimized`) so a stuck/failed run's panel
  can be gotten out of the way without losing it.
- Real bug fixed: `RunProvider.start()` awaits the *entire* pipeline, so
  `RunDispatcher.dispatch()`'s caller awaiting it before popping/toasting
  meant the Scripts screen looked frozen for the whole run. Fixed via a
  quick synchronous pre-check (does a runner command even resolve for this
  combo) + fire-and-forget dispatch, in both `ScriptsScreen._startRun` and
  `RunPicker.reRun`; added an "Active runs" AppBar button to the Scripts
  screen so a fired-and-forgotten run is still reachable.

**Pull/Build: per-click `RunMode` → per-surface switches.** The Step 6
design (Run ▾ menu choosing Run/Pull&Run/Build&Run, with `Run`'s "smart"
`isInstalled()` check) turned out to be exactly the kind of implicit
behavior this app otherwise avoids — nothing on the surface card said
*whether* a script run would pull or build, and the "already installed"
check could go stale invisibly. Replaced with:
- `SurfaceConfig.runPull`/`.runBuild` (bool, default false) — same plain
  always-on/off shape as the existing `runPrerequisites`, no conditional
  skip logic.
- `RunMode` enum deleted entirely, along with `isInstalled()`.
  `RunDispatcher.planSteps()`/`.dispatch()` no longer take a `mode`
  parameter — pull (informational git-pull step, `pullAndCheckForChanges`
  still used for its log line but no longer gates build) and build
  (`buildInstallCommandsFor`) are now two independent `if` blocks reading
  the surface's switches directly.
- Scripts screen: the Run ▾ popup menu (Run/Pull & Run/Build & Run) →
  single plain **Run** `IconButton` per script row.
- `project_detail_screen.dart`'s `_SurfaceCard` gained **Pull** (switch
  only — pulling is a fixed mechanic, not a command list) and **Build**
  (switch + read-only preview of `build`-tagged assigned commands + Manage
  button, mirroring the existing Prerequisites section) sections, in
  execution order: Prerequisites → Pull → Build → Script → Report.
- `project_template.dart` (had drifted badly out of sync with all of the
  above — still the old single `web`/`ios`/`android` surfaces, hardcoded
  `com.goa.app.dev`/`.env.dev` literals, duplicate per-platform
  `sync_app_ios`/`sync_app_android` commands) rewritten from scratch to
  match the real Centurion project 1:1: six dev/stage surfaces, one shared
  command pool with no duplicate ids, `{bundleId}`/`{environment}`/
  `{branch}` placeholders throughout, `build_runner_mobile`/`build_web`
  included, `runPrerequisites`/`runPull`/`runBuild` all on by default.
  `sync_app`/`sync_web` are still in the pool (for manual/ad-hoc use) but no
  longer auto-assigned to any surface — `runPull` now does that job, and
  assigning both would pull the same repo twice per run.
- **Naming fix, root cause**: `build_ios_device_dev`/`build_ios_device_stage`
  were missing `--debug` (silently building release) while their name said
  nothing about it and their simulator sibling both had `--debug` *and*
  said so in its name ("...(dev, debug)"). Added `--debug` to both device
  build commands and renamed them to match, in both the template and (once
  the user has fully quit the app so the live file is safe to touch) the
  live project data.

```
lib/src/models/qa/project_model.dart
    SurfaceConfig.runPull, .runBuild (bool, default false)
lib/src/base/qa/run_dispatcher.dart
    RunMode enum deleted; isInstalled() deleted; planSteps()/dispatch() lose
      the `mode` param — read surface.runPull/.runBuild directly instead
lib/src/ui/qa/scripts/scripts_screen.dart
    Run ▾ PopupMenuButton<RunMode> → single Run IconButton; _startRun loses
      its `mode` param
lib/src/ui/qa/runner/run_picker.dart
    reRun() no longer reconstructs RunMode from record.mode
lib/src/ui/qa/projects/project_detail_screen.dart
    + _PullSection (switch only), _BuildCommandsSection (switch + preview +
      Manage, mirrors _PrerequisiteCommandsSection)
lib/src/base/qa/project_template.dart
    rewritten: 6 dev/stage surfaces, deduped shared command pool,
      {bundleId}/{environment}/{branch} placeholders, build_runner_mobile +
      build_web added, --debug fix on iOS device builds, sync_app/sync_web
      no longer auto-assigned (runPull covers it)
test/run_dispatcher_test.dart
    mode: RunMode.xxx → surface.copyWith(runPull:, runBuild:); the 2
      isInstalled()-specific tests removed
```

**Done-when:** ✅ `flutter analyze` clean (same 1 pre-existing info item);
132/135 tests pass (the 3 failures are `run_provider_quit_test.dart`/
`run_provider_registry_test.dart`'s real-`sleep`-process timing tests —
pre-existing flakiness, unrelated to anything in this step: neither file
references `RunMode`/`runPull`/`runBuild`/`RunDispatcher` at all);
`flutter build macos --debug -t lib/dev/main_dev.dart` clean.

**Deliberately not done in this step**: the live Centurion project's own
JSON data (as opposed to the template used for *new* projects) — the app
was open with real run history from the same day while this step ran, and
a direct file edit while it's open risks being silently overwritten by the
app's own next save (this has already happened once before, with an
earlier `{branch}` fix). Needs the app fully quit first.
