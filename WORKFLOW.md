---
tracker:
  kind: linear
  project_slug: "dosetap-d4b1cc70bc7b"
  active_states:
    - Todo
    - In Progress
  terminal_states:
    - Done
    - Canceled
    - Duplicate
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
agent:
  max_concurrent_agents: 1
  max_turns: 8
codex:
  command: codex --config shell_environment_policy.inherit=all app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
---

You are working on Linear issue `{{ issue.identifier }}` for the DoseTap iOS repository.

Issue context:

- Identifier: `{{ issue.identifier }}`
- Title: `{{ issue.title }}`
- Current state: `{{ issue.state }}`
- URL: `{{ issue.url }}`
- Labels: `{{ issue.labels }}`

{% if issue.description %}
Issue description:

{{ issue.description }}
{% else %}
Issue description: none provided.
{% endif %}

{% if attempt %}
Retry context:

- This is continuation attempt `#{{ attempt }}`.
- Resume from the existing workspace state instead of restarting unless the current branch or PR state is unusable.
{% endif %}

## Operating mode

- This is an unattended orchestration run. Work autonomously end to end.
- Only stop early for a real blocker: missing auth, missing required secrets, missing required external tooling, or a broken repository state you cannot safely recover from.
- Do not ask the human to do routine follow-up work while the issue is still actionable.
- Work only inside the current issue workspace.

## DoseTap repository posture

- Read only the minimum repo context needed. Start with [README.md](README.md), [docs/SSOT/README.md](docs/SSOT/README.md), and [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md) when relevant.
- This repository is local-first and behavior-sensitive. Reproduce the issue before code edits whenever practical.
- Do not revert unrelated worktree changes unless the issue explicitly requires it.
- Prefer the narrowest safe fix over opportunistic refactors.

## Linear workflow policy

- `Todo`: move to `In Progress` before any code edits.
- `In Progress`: continue active implementation.
- `In Review`: do not continue coding; wait for a human decision or for the issue to move back to `In Progress`.
- `Backlog`: do not claim or modify.
- `Done`, `Canceled`, `Duplicate`: terminal, no work.

If a PR is already attached when work begins, treat the issue as a feedback/rework loop:

1. Collect open PR comments and review notes.
2. Fold each actionable point into the plan.
3. Address or explicitly rebut each point before handoff.

## Workpad policy

Maintain one persistent Linear comment headed `## Codex Workpad`.

Keep it current with these sections:

- `Plan`
- `Reproduction`
- `Validation`
- `Notes`
- `Blockers`

Update the same comment throughout the run instead of posting new progress comments.

## Execution checklist

1. Confirm the current issue state and route using the workflow policy above.
2. Record repo state in the workpad: branch, short SHA, and workspace path.
3. Reproduce the issue or capture the missing behavior signal before editing code.
4. Create or update a small plan in the workpad.
5. Implement the fix.
6. Run the narrowest validation that proves the change.
7. If the change is code-facing, run repository validation gates.
8. Attach or update the PR if GitHub tooling is available.
9. Move the issue to `In Review` only after validation is green and the workpad is current.

## Repository validation gates

Choose the smallest set that matches the change, but do not skip required gates.

- Behavior or contract changes: run `bash tools/ssot_check.sh`.
- SwiftPM or `DoseCore` changes: run `swift build -q` and `swift test -q`.
- Any file under `ios/DoseTap/`, `ios/Core/`, `ios/DoseTapTests/`, or `ios/DoseTap.xcodeproj`: run
  `xcodebuild build -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
- If there is a targeted Xcode test that directly covers the touched behavior, run it with `xcodebuild test -only-testing:...`.
- If user-facing UI changed, boot an available iPhone simulator, launch the app, and capture a concrete proof signal.

Do not claim completion if the required validation for the touched area has not been run.

## Git and PR policy

- If Linear provides a branch name, use it. Otherwise create a branch named `codex/<issue-identifier>` or a sanitized equivalent.
- Sync from `origin/main` before significant code edits when it is safe to do so.
- Keep commits focused and reviewable.
- If a PR exists, check GitHub Actions status before handoff and do not move to `In Review` while checks are red for your changes.
- Merge remains manual in this workflow. Do not auto-merge or land changes after review approval.

## Handoff standard

Before stopping, make sure the workpad contains:

- what changed,
- exact validation run,
- unresolved risks or blockers,
- the current PR link if one exists.

Final output should be concise and factual. Report completed actions and blockers only.
