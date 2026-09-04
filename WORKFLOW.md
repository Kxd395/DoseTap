---
tracker:
  kind: plane
  provider:
    endpoint: "$PLANE_BASE_URL"
    api_key: "$Plane_DoseTap_API"
    workspace_slug: dark-water-drones
    project_id: f2300d5b-01c5-4b0d-b930-34a954db2f2e
    project_identifier: DOSETAP
    api_resource: work-items
  active_states:
    - Todo
    - In Progress
  terminal_states:
    - Done
    - Cancelled
polling:
  interval_ms: 15000
workspace:
  root: ~/code/symphony-workspaces/dosetap
hooks:
  after_create: |
    set -euo pipefail
    git clone --depth 1 "${SOURCE_REPO_URL:-https://github.com/Kxd395/DoseTap.git}" .
    if [ ! -f ios/DoseTap/Secrets.swift ] && [ -f ios/DoseTap/Secrets.template.swift ]; then
      cp ios/DoseTap/Secrets.template.swift ios/DoseTap/Secrets.swift
    fi
  before_run: |
    set -euo pipefail
    ruby tools/plane_tracker.rb validate-config
  timeout_ms: 60000
agent:
  max_concurrent_agents: 1
  max_turns: 12
codex:
  command: codex --config shell_environment_policy.inherit=all app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
---

You are working on Plane work item `{{ issue.identifier }}` for the DoseTap iOS repository.

Work item context:

- Identifier: `{{ issue.identifier }}`
- Title: `{{ issue.title }}`
- Current state: `{{ issue.state }}`
- URL: `{{ issue.url }}`
- Labels: `{{ issue.labels }}`

{% if issue.description %}
Description:

{{ issue.description }}
{% else %}
Description: none provided.
{% endif %}

{% if attempt %}
This is continuation attempt `#{{ attempt }}`. Resume from the existing workspace state instead of restarting unless the workspace is unusable.
{% endif %}

## Required Plane preflight

1. Read `.agents/plane-workflow.yml` and `AGENTS.md`.
2. Confirm the exact current work item before editing:

   ```bash
   ruby tools/plane_tracker.rb preflight --issue "{{ issue.identifier }}"
   ```

3. If the item is `Todo` and implementation is beginning, move it to `In Progress` and verify the returned readback:

   ```bash
   ruby tools/plane_tracker.rb start --issue "{{ issue.identifier }}" --apply
   ```

Do not claim `Backlog`, `Done`, or `Cancelled` work. Never guess a work item from title similarity, and never display the API key.

## Operating mode

- Work autonomously inside the current issue workspace.
- Stop only for a real blocker: missing authority, missing auth, missing required external tooling, an unsupported Plane adapter, an ambiguous work item, or a repository state that cannot be preserved safely.
- Preserve unrelated worktree changes.
- Reproduce or capture the missing behavior signal before code edits when practical.
- Read `README.md`, `docs/SSOT/README.md`, `docs/TESTING_GUIDE.md`, and `.specify/memory/constitution.md` as required by the task.
- Update SSOT before behavior changes.

## Validation gates

Choose the smallest sufficient set, but do not skip a required touched-area gate:

- Workflow or tracker changes: `bash tools/check_plane_workflow.sh`.
- Behavior or contract changes: `bash tools/ssot_check.sh`.
- SwiftPM or `DoseCore` changes: `swift build -q` and `swift test -q`.
- App-facing changes: `bash tools/check_app_version.sh`.
- Changes under `ios/DoseTap/`, `ios/Core/`, `ios/DoseTapTests/`, or the Xcode project: build the `DoseTap` scheme for an iOS Simulator with code signing disabled.
- Targeted Xcode tests: run when they directly cover the touched behavior.
- User-facing UI: obtain an available-simulator proof signal; keep signed-device and owner-observed gates separate.
- Every change: `git diff --check`.

## Required Plane closeout

Before the final response, prepare a JSON closeout with:

- `issue_identifier`
- `summary`
- `changed_files`
- non-empty `validation` entries containing `command`, `result`, and `evidence_class`
- `open_gates`
- `acceptance_complete`
- `target_state`

First inspect the dry-run:

```bash
ruby tools/plane_tracker.rb closeout --issue "{{ issue.identifier }}" --input <closeout.json>
```

Then apply it and independently verify the readback:

```bash
ruby tools/plane_tracker.rb closeout --issue "{{ issue.identifier }}" --input <closeout.json> --apply
ruby tools/plane_tracker.rb verify --issue "{{ issue.identifier }}" --input <closeout.json>
```

Use `Done` only when acceptance is complete, every recorded validation passed, and `open_gates` is empty. Otherwise keep the item `In Progress` and record the remaining gates. Automated evidence must not close signed-device, human, provider, privacy, legal, or release gates.

The agent must not claim that the task or Plane update is complete unless post-write readback succeeds. If Plane is unavailable, authentication is missing, the work item is ambiguous, or the tracker write/readback fails, preserve the local work and report that exact blocker.

Do not enable this file for unattended polling until the installed Plane adapter defines a non-dispatchable handoff for items waiting on human or external gates. Leaving such an item in an actively polled state without that policy can cause repeated runs.

## Handoff

Report only verified outcomes:

- what changed,
- exact validation and evidence class,
- the Plane identifier and read-back state,
- remaining gates,
- PR or commit state when applicable.

Merge, release, medical, legal, privacy, and physical-device decisions remain manual unless the work item explicitly grants and satisfies that authority.
