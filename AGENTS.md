# DoseTap agent instructions

These instructions apply to every agent working in this repository. They supplement the project constitution and do not weaken any system, security, approval, or user-consent requirement.

## Required context

Before changing behavior or architecture, read:

1. `README.md`
2. `docs/SSOT/README.md`
3. `docs/TESTING_GUIDE.md`
4. `.specify/memory/constitution.md`
5. `.agents/plane-workflow.yml`

Preserve the existing dirty worktree. Never reset, stash, overwrite, commit, or reclassify unrelated user changes.

## Plane is the work-status authority

The local Plane project defined in `.agents/plane-workflow.yml` owns priority, assignment, work state, and completion. Markdown plans are evidence and navigation, not a substitute tracker.

- Match work by an exact stable `DOSETAP-N` identifier. Never match or create work solely from a similar title.
- Before implementation, read the current work item with `ruby tools/plane_tracker.rb preflight --issue DOSETAP-N`.
- If a material task arrived outside Plane, search for an existing exact or equivalent item before creating one. The helper prevents duplicate creation by returning an existing exact-title match and fails on ambiguous matches.
- Move `Todo` to `In Progress` with `ruby tools/plane_tracker.rb start --issue DOSETAP-N --apply` only when implementation is actually starting.
- `Backlog`, `Done`, and `Cancelled` items are not silently claimed. Report the state mismatch or obtain the required product decision.
- Never print, paste, log, or commit the Plane API key. The helper reads `Plane_DoseTap_API` from the process environment or ignored `.env` without displaying it. It reads `PLANE_BASE_URL` the same way and supports the existing `.env` bare-URL line for backward compatibility.

## Definition of done and Plane closeout

An agent must not say a task is complete until all of the following are true:

1. The requested implementation and in-scope documentation are written to disk.
2. The required validation for the touched area has passed.
3. Remaining simulator, signed-device, owner-observed, privacy, provider, legal, or release gates are named accurately.
4. A structured closeout has been applied to the exact Plane item using `ruby tools/plane_tracker.rb closeout --issue DOSETAP-N --input <closeout.json> --apply`.
5. `ruby tools/plane_tracker.rb verify --issue DOSETAP-N --input <closeout.json>` confirms the workpad and state by reading Plane back.

Use `Done` only when acceptance is complete, every listed validation passed, and `open_gates` is empty. Otherwise keep the item `In Progress`, update the same workpad, and describe the open gates. A local or automated pass never closes a human, physical-device, provider, privacy, legal, or release gate.

The closeout helper is dry-run by default. Do not claim that Plane was updated from a dry-run, an HTTP success alone, or a local Markdown edit; successful post-write readback is required.

## Required checks

Follow `docs/TESTING_GUIDE.md` and the touched-area gates in `WORKFLOW.md`. Always run:

```bash
bash tools/check_plane_workflow.sh
git diff --check
```

If Plane is unavailable, auth is missing, no exact work item exists, multiple matches are found, or readback does not match, the task is not fully closed. Preserve the implementation, report the concrete blocker, and do not invent a tracker update.
