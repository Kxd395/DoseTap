# Symphony Setup For DoseTap

Last updated: 2026-03-07

## What this setup does

This repository now includes a repo-owned [WORKFLOW.md](../WORKFLOW.md) for [OpenAI Symphony](https://github.com/openai/symphony).

The workflow is designed to monitor the real DoseTap Linear project, claim active engineering tickets, create an isolated workspace per issue, run Codex against that issue, and stop at `In Review`.

This setup is for engineering-work monitoring and execution. It does not monitor app telemetry, sleep metrics, or user health data.

## What is included

- Repo workflow contract: [WORKFLOW.md](../WORKFLOW.md)
- DoseTap-specific runbook: [docs/SYMPHONY_SETUP.md](SYMPHONY_SETUP.md)

Current Linear wiring:

- Team: `HomeAxxess`
- Project: `DoseTap`
- Project slug: `dosetap-d4b1cc70bc7b`
- Review state: `In Review`

Key defaults in the workflow:

- Poll every `15s`
- Run `1` agent at a time
- Create issue workspaces under `~/code/symphony-workspaces/dosetap`
- Clone `https://github.com/Kxd395/DoseTap.git` by default
- Stub `ios/DoseTap/Secrets.swift` from `Secrets.template.swift` when needed
- Stop at `In Review`; merge stays manual

## Recommended Linear states

The workflow expects these states to exist or be mapped to equivalent names:

- `Todo`
- `In Progress`
- `In Review`
- `Done`
- `Backlog`
- `Canceled`
- `Duplicate`

Only `Todo` and `In Progress` are actively claimed by Symphony in the current config.

## Prerequisites

You need:

- a Linear personal API key
- `codex` installed with app-server support
- Xcode and iOS simulators installed locally
- Git access to the DoseTap repository

You also need the Symphony reference implementation or your own implementation of the [Symphony spec](https://github.com/openai/symphony/blob/main/SPEC.md).

## Environment variables

Export these before starting Symphony:

```bash
export LINEAR_API_KEY="lin_api_..."
export SOURCE_REPO_URL="https://github.com/Kxd395/DoseTap.git"
```

`SOURCE_REPO_URL` is optional if the default GitHub origin is correct.

## Start Symphony

Example using the Elixir reference implementation:

```bash
git clone https://github.com/openai/symphony
cd symphony/elixir
mise trust
mise install
mise exec -- mix setup
mise exec -- mix build
mise exec -- ./bin/symphony /Volumes/Developer/projects/DoseTap/WORKFLOW.md --port 4050
```

The optional `--port 4050` flag exposes the local dashboard and JSON status endpoints.

## How the DoseTap workflow behaves

For each eligible Linear issue, Symphony will:

1. Create an isolated workspace.
2. Clone the DoseTap repo into that workspace.
3. Create a CI-safe `Secrets.swift` stub if needed.
4. Move `Todo` issues to `In Progress`.
5. Keep one `## Codex Workpad` comment updated on the issue.
6. Reproduce the issue before editing when practical.
7. Run repo-appropriate validation:
   - `bash tools/ssot_check.sh` for behavior and contract changes
   - `swift build -q` and `swift test -q` for SwiftPM / DoseCore changes
   - `xcodebuild build ...` for iOS app changes
   - targeted `xcodebuild test -only-testing:...` when applicable
8. Stop at `In Review` once validation is green.

## Recommended pilot posture

Start conservative:

- keep concurrency at `1`
- use one small Linear project or one label-filtered queue first
- keep merge manual
- inspect the workpad comments and dashboard output before increasing concurrency

For this repository, simulator work is heavier than a web-only repo. Raising concurrency too early will reduce signal and increase flaky validation.

## Useful customizations

You can safely customize these fields in [WORKFLOW.md](../WORKFLOW.md):

- `tracker.project_slug`
- `tracker.active_states`
- `polling.interval_ms`
- `workspace.root`
- `agent.max_concurrent_agents`
- `codex.command`

If you later want Symphony to continue past `In Review` and land PRs automatically, add a merge state such as `Ready to Merge` and extend the workflow with a repo-local land/merge skill. That is intentionally not enabled in this first pass.
