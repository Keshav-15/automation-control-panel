# Commands Reference — Centurion QA

Canonical commands derived from actual `package.json` files, `wdio.ios.conf.ts`,
`wdio.ios.simulator.conf.ts`, `src/config/env.ts`, and `dev-setup-and-testing-notes.md`.

**This file is the source of truth** for the actual shell commands used
across the app — but as of the multi-project rewrite (see
[`PROJECTS_SYSTEM.md`](./PROJECTS_SYSTEM.md)), the commands that actually
run for a live "Centurion" project come from one shared command pool in
`lib/src/base/qa/project_template.dart` (`_commands()`, assigned per
surface — six surfaces now, `android_dev`/`android_stage`/`ios_dev`/
`ios_stage`/`web_dev`/`web_stage`, not three), **not**
`manifests/centurion.yaml`. The YAML is still loaded once at every launch
(a side effect of the now-orphaned legacy `QAProvider`), but nothing
downstream of that load is ever displayed or acted on — it and
`project_template.dart` are not kept in sync with each other. Update
**both** whenever a package.json script or WDIO conf changes, or they will
silently drift.

Command text uses `{environment}`/`{branch}`/`{bundleId}`/`{udid}`/
`{script}` placeholders (substituted per-run by
`RunDispatcher.substitute()`) instead of the dev-only hardcoded literals
this file's examples below show for readability — e.g. the real
`test:ios:{environment}` command becomes `test:ios:dev` or `test:ios:stage`
depending on which surface it runs from.

**Whether a surface pulls/builds before running is a per-surface switch**
(`SurfaceConfig.runPull`/`.runBuild`, shown as Pull/Build sections on the
Project Detail card), not a per-click Run/Pull&Run/Build&Run choice — the
Scripts screen has a single Run button. See
[`RUN_EXPERIENCE_REDESIGN.md`](./RUN_EXPERIENCE_REDESIGN.md)'s final step.

---

## Web — `crichq-webapp-nextjs`

Package manager: **yarn** (Node ≥ 22).

| Purpose | Command |
|---|---|
| Install deps | `yarn install --frozen-lockfile` |
| Build (per environment) | `yarn build:{environment}` (real scripts: `build:dev`/`build:stage`) |
| Run a test script | `yarn {script}` — {script} is whichever package.json script is picked on the Scripts screen |
| Generate Allure report | `yarn allure:generate` |
| Open Allure report | `yarn allure:open` |
| Run headed (debug) | `yarn test:headed` |
| Playwright UI mode | `yarn test:ui` |
| Auth warm-up (dev) | `yarn test:auth:dev` |

**What `yarn test` does internally** — do NOT add separate steps for these:
```
allure:clean      → rm -rf allure-results allure-report
playwright:clean  → rm -rf test-results playwright-report blob-report
                    env-cmd -f .env.dev env-cmd -f .env.test playwright test
allure:generate   → node scripts/normalize-allure-suites.mjs
                    && allure generate allure-results --clean -o allure-report
```

Required env files (repo root): `.env.dev` **and** `.env.test`.
Allure report: `allure-report/`

---

## Mobile tests — `centurion-app-automation-tests-ts`

Package manager: **npm** (Node ≥ 20). Config read via `src/config/env.ts`.

### WDIO configs — there are TWO

| Config file | Target | Appium udid source | Signing |
|---|---|---|---|
| `wdio.ios.conf.ts` | Real device | `IOS_DEVICE_ID` | ✅ xcodeOrgId + xcodeSigningId required |
| `wdio.ios.simulator.conf.ts` | Simulator | `IOS_SIMULATOR_UDID` | ❌ none |
| `wdio.android.conf.ts` | Device/emulator | `ANDROID_DEVICE_ID` | n/a |

### npm scripts

One shared command per row now (`test_ios_device`/`test_ios_simulator`/
`test_android` in the pool), `{environment}` picking `dev` vs `stage` per
surface — not separate dev/stage commands.

| Purpose | Command | WDIO config used |
|---|---|---|
| iOS **device** tests | `npm run test:ios:{environment} -- --spec {script}` | `wdio.ios.conf.ts` |
| iOS **simulator** tests | `ENV_FILE=.env.{environment} npx wdio run wdio.ios.simulator.conf.ts --spec {script}` | `wdio.ios.simulator.conf.ts` |
| Android tests | `npm run test:android:{environment} -- --spec {script}` | `wdio.android.conf.ts` |
| Install test deps | `npm ci` | — |
| Generate serialization code (build_runner, `crichq-app-flutter` side) | `fvm flutter pub run build_runner build --delete-conflicting-outputs` | — |
| Generate Allure report | `npm run report:generate` | — |
| Open Allure report | `npm run report:open` | — |

**Note:** `npm run test:ios:dev` = `ENV_FILE=.env.dev wdio run wdio.ios.conf.ts` (device only).
There is **no** npm script for simulator yet — run it directly with `npx wdio`.

### Allure shared-pool workaround

`allure-results/` accumulates across all runs. **Our fix**: always run
`rm -rf allure-results allure-report` before the test step → pool is single-run → generate directly.

### OTP / stdin

WDIO (`otpFetcher.ts`) calls `readline` and blocks waiting for an OTP paste from the terminal.
The pipeline engine must keep the child's stdin open and forward input from the UI's stdin field.

---

## App — `crichq-app-flutter`

### iOS — Simulator

```bash
# Build (iphonesimulator/Runner.app, no code-signing)
flutter build ios \
  --flavor development \
  -t lib/dev/main_dev.dart \
  --simulator \
  --debug

# Install
xcrun simctl install "${IOS_SIMULATOR_UDID}" build/ios/iphonesimulator/Runner.app

# Launch (dev bundle id)
xcrun simctl launch "${IOS_SIMULATOR_UDID}" com.goa.app.dev
```

`IOS_SIMULATOR_UDID` comes from `centurion-app-automation-tests-ts/.env.dev`.

### iOS — Real Device

```bash
# Build (iphoneos/Runner.app, requires Xcode signing config in .env.dev)
# --debug matches the simulator build — the app has a debug-only
# test-email-prefill feature real testing relies on; a prior version of
# this command was missing --debug (silently release), fixed.
flutter build ios \
  --flavor development \
  -t lib/dev/main_dev.dart \
  --debug

# Install (Xcode 15+ devicectl)
xcrun devicectl device install app \
  --device "${IOS_DEVICE_ID}" \
  build/ios/iphoneos/Runner.app

# Launch (bundle id comes from the surface's App ID field — {bundleId} —
# not hardcoded per project)
xcrun devicectl device process launch \
  --device "${IOS_DEVICE_ID}" \
  com.goa.app.dev
```

`IOS_DEVICE_ID` from `centurion-app-automation-tests-ts/.env.dev`.
Requires `IOS_XCODE_ORG_ID` and `IOS_XCODE_SIGNING_IDENTITY` also set in that `.env.dev`.

### iOS — Simulator setup (one-time per machine)

```bash
xcrun simctl list devices available        # list runtimes
xcrun simctl create "iPhone 17 Pro" "iPhone 17 Pro" <runtime-id>
xcrun simctl boot <udid>
xcrun simctl list devices booted           # confirm + get UDID
```

Then set in `centurion-app-automation-tests-ts/.env.dev`:
```
IOS_SIMULATOR_UDID=<udid>
IOS_SIMULATOR_PLATFORM_VERSION=<ios-version>   # e.g. 26.5
```

Common failure: `ECONNREFUSED 127.0.0.1:8100` = simulator UDID not booted or doesn't exist
on this machine.

### Android — Device

```bash
# Build (debug APK)
flutter build apk \
  --flavor development \
  -t lib/dev/main_dev.dart \
  --debug

# Install (adb)
adb install -r build/app/outputs/flutter-apk/app-development-debug.apk
```

---

## Appium

Must be running **before** any mobile WDIO run. Doctor checks `GET /status`.

```bash
appium --port 4723
# health check:
curl -s http://localhost:4723/status | python3 -m json.tool
```

---

## Environment variables per repo

| Repo | Files needed | Key variables |
|---|---|---|
| `crichq-webapp-nextjs` | `.env.dev`, `.env.test` | API URLs, Cognito config |
| `centurion-app-automation-tests-ts` | `.env.dev` | `IOS_SIMULATOR_UDID`, `IOS_SIMULATOR_PLATFORM_VERSION`, `IOS_DEVICE_ID`, `IOS_DEVICE_NAME`, `IOS_PLATFORM_VERSION`, `IOS_BUNDLE_ID`, `IOS_XCODE_ORG_ID`, `IOS_XCODE_SIGNING_IDENTITY`, `IOS_WDA_BUNDLE_ID`, `ANDROID_DEVICE_ID`, `ANDROID_DEVICE_NAME`, `ANDROID_APP_PACKAGE`, `ANDROID_APP_ACTIVITY`, `TEST_EMAIL`, `COGNITO_CLIENT_ID`, `FIXTURE_*` |
| `crichq-app-flutter` | none (flavor baked in) | — |

The control center **never stores or displays** these secrets. It only injects env vars from
a sibling `.env.dev` for steps that declare `env_file:` in the manifest.
