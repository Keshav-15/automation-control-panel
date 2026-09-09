# QA Control Center 🧪

A macOS desktop app that runs Centurion's Web / iOS / Android test suites with a click —
Doctor checks your machine first, so you never end up staring at a cryptic failure from a
missing `.env` file or a dead Appium server.

This repo **is** the control center. It does not contain any Centurion code itself — it shells
out to four sibling repos that must sit next to it in the same folder:

| Repo | What it is |
|---|---|
| `automation-testing` | **This repo.** The control-center app. |
| `crichq-app-flutter` | The Centurion Flutter app — built + installed for mobile runs. |
| `crichq-webapp-nextjs` | The Centurion Next.js web app — Playwright tests live here. |
| `centurion-app-automation-tests-ts` | WDIO mobile test suite (iOS + Android). |

Dev environment only for now — see `docs/CONVERSATION_CONTEXT.md` if you're wondering why.

---

## Prerequisites

Install these once, in Terminal — the control center only *shells out* to them, it doesn't
install anything for you.

| Tool | Needed for | Check with |
|---|---|---|
| **Flutter** ≥ 3.35 | Building this app, and the `crichq-app-flutter` mobile builds | `flutter --version` |
| **Node** ≥ 22 | Web tests (Playwright) | `node --version` |
| **Node** ≥ 20 | Mobile tests (WDIO) — a second, older floor is fine if you use `nvm` | `node --version` |
| **Yarn** | Web repo package manager | `yarn --version` |
| **npm** | Mobile tests + app repo package manager | `npm --version` |
| **Xcode** + command-line tools | iOS builds/simulators | `xcode-select -p` |
| **Java** | Allure report generation (`allure-commandline`) | `java -version` |
| **Appium** | Any mobile (iOS/Android) run | `npm i -g appium` |

The web repo needs Node ≥ 22 and the mobile repo needs Node ≥ 20 — if your default `node`
is older than 22, the Web card will correctly show a red Doctor check (this is expected, not
a bug in the control center; either upgrade or manage two versions with `nvm`).

The Home screen's version banner shows exactly what this app sees on PATH — it's a login shell
(`zsh -l`), the same PATH Terminal uses, so if `which node` works in Terminal it'll show up here.

---

## One-time setup

### 1. Clone all four repos into one folder

```bash
mkdir -p ~/Projects && cd ~/Projects
git clone <url>/automation-testing.git
git clone <url>/crichq-app-flutter.git
git clone <url>/crichq-webapp-nextjs.git
git clone <url>/centurion-app-automation-tests-ts.git
```

They must be **siblings** — the control center resolves every repo path as
`<your Projects folder>/<repo>`, picked once in the Setup screen.

### 2. Fill in each repo's `.env` files

The control center **never reads, stores, or displays** these — ask a teammate for real
values, or use each repo's `.env.example` as a starting point.

**`crichq-webapp-nextjs`** needs `.env.dev` and `.env.test` in its root (Playwright reads both).

**`centurion-app-automation-tests-ts`** needs `.env.dev` in its root. Copy `.env.example` and
fill in at minimum:

| Variable | What it's for |
|---|---|
| `IOS_SIMULATOR_UDID` + `IOS_SIMULATOR_PLATFORM_VERSION` | iOS **simulator** target (see step 3 below) |
| `IOS_DEVICE_ID` + `IOS_PLATFORM_VERSION` | iOS **real device** target |
| `IOS_XCODE_ORG_ID` + `IOS_XCODE_SIGNING_IDENTITY` | Required only for the real-device target (code signing) |
| `ANDROID_DEVICE_ID` + `ANDROID_DEVICE_NAME` | Android target (device or emulator, already connected) |
| `TEST_EMAIL`, `COGNITO_CLIENT_ID`, `OTP_URL` | Login flow — you'll paste the OTP by hand (see below) |
| `FIXTURE_*` | Deterministic test data (team/ground ids) — ask a teammate |

`crichq-app-flutter` needs no `.env` — its dev flavor is baked into the build command.

### 3. One-time iOS simulator setup (only if you'll run iOS on Simulator)

```bash
xcrun simctl list devices available        # find a runtime to use
xcrun simctl create "iPhone 17 Pro" "iPhone 17 Pro" <runtime-id>
xcrun simctl boot <udid>
xcrun simctl list devices booted           # confirm + copy the UDID
```

Put that UDID in `centurion-app-automation-tests-ts/.env.dev` as `IOS_SIMULATOR_UDID`
(plus `IOS_SIMULATOR_PLATFORM_VERSION`, e.g. `26.5`). Doctor re-checks that the simulator is
actually **booted** every time you flip the Simulator/Real Device toggle — a created-but-not-booted
simulator is the most common cause of `ECONNREFUSED 127.0.0.1:8100`.

### 4. Start Appium before any mobile run

```bash
appium --port 4723
```

Leave it running in its own terminal tab. Doctor checks `GET http://localhost:4723/status`
before enabling Run, and re-checks again right before the actual test step (a Build+Install
can take minutes — long enough for Appium to have been quit in between).

---

## Running the app

```bash
cd automation-testing
flutter pub get
flutter run -d macos -t lib/dev/main_dev.dart
```

(Or build once and keep reusing the `.app`: `flutter build macos --debug -t lib/dev/main_dev.dart`,
then open `build/macos/Build/Products/Debug/flutter_boilerplate.app`.)

**First launch** asks you to pick your Projects folder (step 1 above) and shows which repos it
found. After that it remembers — the gear icon reopens this screen any time you need to change
the folder or add extra PATH directories (only needed if a tool works in Terminal but isn't on
the login-shell PATH this app inherits).

### Everyday flow

1. **Run Doctor** on the card you want (Web / iOS / Android). Every check is read-only —
   it never modifies your repos. A ✅ means nothing to fix; a ⚠️ is non-blocking (e.g. a repo
   not on `develop`); a ❌ blocks Run and shows exactly what to do about it.
2. Flip **Sync** (git pull `develop`) and, for mobile, **Build + Install** (rebuilds and
   installs the app fresh) on or off — both default sensibly, and Doctor re-runs automatically
   when you switch the iOS Simulator/Real Device target.
3. Optionally type into **Spec / extra flags** to run a subset instead of the full suite —
   e.g. `--grep "@smoke"` for Web, or `--spec test/specs/login.e2e.ts` for a mobile recipe.
   Leave it blank to run everything.
4. Click **Run**. Output streams live below; only one recipe can run at a time, and the other
   two cards grey out while it's in flight.
5. If a step blocks waiting for a one-time password (login flows do this by design — see
   `centurion-app-automation-tests-ts`'s own README), the **input field at the bottom of the
   log** sends whatever you type straight to that step, same as typing it in a terminal.
6. When it finishes, the **Allure report opens automatically**. Missed it? Each card keeps a
   "Reopen last report" link, and the **Recent runs** panel below the cards keeps the last 8
   (of up to 50 stored) with the same shortcut plus a link to that run's full saved log.
7. **Cancel** kills the whole process tree for that step, not just its immediate shell —
   and quitting the app (⌘Q) does the same for whatever's still running before it actually exits.

---

## Troubleshooting

| Doctor says | It means |
|---|---|
| `Node ≥ 22 on PATH` failed, showing an older version | Your default `node` doesn't meet the Web suite's floor — Node ≥ 20 is enough for mobile, so this is normal if you use `nvm` for two versions |
| `<repo> working tree clean` failed, `M <file>` | That repo has real uncommitted changes — commit or `git stash` them; the control center refuses to run against a dirty tree on purpose |
| `<repo> on develop` warns (not fails) | You're on a different branch — the fix hint (`git checkout develop`) is safe to run yourself, or ignore the warning if you mean to be on that branch |
| `Appium running` failed | Start it: `appium --port 4723` (see step 4 above) |
| iOS: simulator not booted | `xcrun simctl boot <UDID>` — must match `IOS_SIMULATOR_UDID` in `.env.dev` exactly |
| `ECONNREFUSED 127.0.0.1:8100` during a run | Same as above — the simulator UDID in `.env.dev` isn't actually booted on this machine |

---

## Continuing development on this app

Everything about *how this app itself* is built — phase-by-phase history, fixed architectural
decisions, and what's left — lives in `docs/`:

1. [`docs/PROGRESS.md`](docs/PROGRESS.md) — full scope checklist + current status, start here
2. [`docs/CONVERSATION_CONTEXT.md`](docs/CONVERSATION_CONTEXT.md) — fixed decisions + discoveries
3. [`docs/COMMANDS_REFERENCE.md`](docs/COMMANDS_REFERENCE.md) — canonical commands (source of
   truth for `manifests/centurion.yaml`)
4. [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) — detailed per-phase design spec
5. [`docs/RUN_CONTEXT.md`](docs/RUN_CONTEXT.md) — auto-written after every run; what happened
   last time and whether re-running makes sense

```
lib/src/
  models/qa/      manifest_model.dart, machine_profile_model.dart, run_model.dart, ...
  controllers/qa/ setup_controller.dart, home_controller.dart, doctor_controller.dart
  providers/qa/   qa_provider.dart, run_provider.dart
  base/qa/        process_gateway.dart, step_runner.dart, doctor_runner.dart, ...
  ui/qa/          setup/, home/, doctor/, runner/, history/
manifests/
  centurion.yaml  the declarative recipe/step definitions — edit this to add a step,
                  not the Dart pipeline engine
test/             flutter_test suite — real shell processes where it matters (kill,
                  stdin, PATH), fakes where a real process would be slow/networked
```
