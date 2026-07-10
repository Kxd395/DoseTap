# Symphony Setup For DoseTap

Last updated: 2026-07-09

## Purpose

[WORKFLOW.md](../WORKFLOW.md) connects DoseTap engineering work to the local Axxess Plane project. Symphony polls eligible Axxess work items, creates an isolated repository workspace, runs Codex, and stops at `In Review` for human review.

This workflow handles engineering work only. It does not read app telemetry, sleep metrics, medication history, or other user health data.

## Canonical tracker

- Product: Plane v1.3.1
- Workspace: `Axxess`
- Workspace slug: `axxess`
- Project: `Dose_Tap`
- Identifier: `DOSETAP`
- Project ID: `b195f92c-529b-4fd9-8e48-12221ecfa91f`
- Human URL: http://localhost:18080/axxess/projects/b195f92c-529b-4fd9-8e48-12221ecfa91f/issues
- REST base: `http://localhost:18080/api/v1`

The human URL is not an API endpoint. Automation uses Plane work-item endpoints under `/api/v1/workspaces/axxess/projects/<project-id>/work-items/`.

## Workflow states

- `Backlog`: product triage, not claimed by Symphony
- `Todo`: eligible for Symphony
- `In Progress`: active implementation
- `In Review`: validated handoff, not claimed by Symphony
- `Done`: terminal
- `Cancelled`: terminal

Only `Todo` and `In Progress` are active in the current workflow. Concurrency remains `1`.

## Authentication and secret boundary

The runner uses a dedicated Axxess API token from `PLANE_API_KEY`. The token is stored only in:

```text
/Volumes/HomeLab_Workspace/repos/services/symphony/.env
```

That file is untracked and mode `600`. Never put the token in `WORKFLOW.md`, repository files, logs, comments, prompts, or shell examples.

Symphony owns the credential and exposes project-scoped tracker operations to Codex. The workflow explicitly excludes `PLANE_API_KEY` from model-generated shell subprocesses. Do not replace the scoped tracker tool with raw REST access.

## Required Symphony implementation

Upstream Symphony is Linear-only. This workflow requires the local Plane adapter worktree:

```text
/Volumes/HomeLab_Workspace/repos/services/symphony-plane
```

The adapter provides:

- Plane REST pagination and work-item normalization
- candidate polling and issue-state refresh
- state-name lookup and state transitions
- comment creation
- tracker-specific dynamic tool selection
- Linear and memory adapter regression compatibility

Pointing the old Linear client at the Plane URL does not work. Linear uses GraphQL and `Authorization`; Plane uses REST and `X-Api-Key`.

## Start Symphony

```bash
cd /Volumes/HomeLab_Workspace/repos/services/symphony-plane/elixir
source /Volumes/HomeLab_Workspace/repos/services/symphony/.env

mise trust
mise install
mise exec -- mix setup
mise exec -- mix build

mise exec -- ./bin/symphony \
  /Users/VScode_Projects/projects/DoseTap-p0-late-dose-recovery/WORKFLOW.md \
  --port 4050
```

Dashboard and status endpoints are then available at `http://localhost:4050`.

The workflow path above is the isolated implementation worktree. After the branch is integrated, use the merged DoseTap checkout path.

## Per-work-item behavior

For each eligible Axxess work item, Symphony will:

1. Create an isolated workspace under `~/code/symphony-workspaces/dosetap`.
2. Clone DoseTap and create a local `Secrets.swift` stub from the checked-in template when needed.
3. Move `Todo` to `In Progress` before edits.
4. Reproduce the issue or record the concrete missing behavior signal.
5. Implement the smallest safe change.
6. Run repository-specific checks from `WORKFLOW.md`.
7. Post one `## Codex Workpad` Axxess comment with validation and blockers.
8. Move the work item to `In Review` only after required checks pass.

Merge remains manual.

## Validation

Validate the adapter before starting unattended work:

```bash
cd /Volumes/HomeLab_Workspace/repos/services/symphony-plane/elixir
mise exec -- mix test
mise exec -- mix specs.check
```

Then start Symphony and confirm the dashboard sees `DOSETAP-1` through `DOSETAP-5` with the correct states. Use a disposable comment or state transition only when intentionally testing write behavior.

## Localhost limitation

`localhost:18080` is valid only when Symphony runs on this Mac. Remote workers cannot reach that address. Before enabling SSH workers, expose Plane through an authenticated private network endpoint, update `tracker.endpoint` and `tracker.project_url`, and re-run adapter integration tests.

## Rollback

1. Stop Symphony.
2. Revert the DoseTap workflow to the last known-good tracker configuration only if intentionally returning to another tracker.
3. Revert or remove the local Symphony Plane adapter worktree.
4. Disable the `Symphony DoseTap Axxess` API token in Plane.
5. Keep created Axxess work items for audit history. Move abandoned items to `Cancelled` instead of deleting them.
