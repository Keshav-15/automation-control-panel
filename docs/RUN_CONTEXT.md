# Run Context

Auto-updated by the QA Control Center before and after each pipeline run.
A future session reads this to understand what happened last time and whether re-running makes sense.

*Written by `StepRunner._writeRunContext` — do not edit by hand.*

---

## Last run

| Field | Value |
|---|---|
| Surface | iOS (Dev) — login.e2e.ts (`ios_dev`) |
| Environment | project |
| Status | failed |
| Started | 2026-09-09T10:29:24.732123 |
| Duration | 2m 40s |
| Sync enabled | true |
| Build+Install enabled | true |

## Repo SHAs at run time

| Repo | Branch | SHA |
|---|---|---|
| crichq-app-flutter | develop | 76fede5c |
| crichq-webapp-nextjs | develop | 95d96ed7 |
| centurion-app-automation-tests-ts | feat/simulator_changes_and_team_creation_test_cases | facb2f8 |
|  | — | — |

## Step log

| Step | Outcome | Duration |
|---|---|---|
| build_ios_simulator_dev | success | 20s |
| install_ios_simulator | success | 1s |
| launch_ios_simulator | success | 1s |
| run_script_login | failed | 2m 15s — Exit code 1 |

## Report location

No report opened.
