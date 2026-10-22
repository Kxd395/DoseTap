# DoseTap working folder and document guide

Status: Current runbook
Last verified: 2026-09-30

## Everyday project

Use `/Volumes/Developer/projects/DoseTap-main` as the everyday local checkout of `main`. Verify its branch, local changes and upstream before beginning work:

```bash
git -C /Volumes/Developer/projects/DoseTap-main status --short --branch
git -C /Volumes/Developer/projects/DoseTap-main log -1 --oneline
git -C /Volumes/Developer/projects/DoseTap-main remote -v
```

A folder name does not establish its Git branch or freshness. Do not pull over unexplained local changes. Build or installation evidence must name the exact checkout and commit; an updated working folder alone does not update an installed phone app.

## Documents to open

- [Product overview](PRODUCT_OVERVIEW.md): presentation wording, Apple Health sleep timing and the planned WHOOP capability.
- [Dashboard proposal package](plans/dashboard-2026-09-30/README.md): the four supplied September 30 proposals, consolidated decisions, source mapping and delivery order. These remain proposed behavior.
- [Current behavior](SSOT/README.md): intended implemented behavior and safety contracts.
- [Documentation index](README.md): lifecycle and authority for every document tree.
- [Plane planning index](PLANNING.md): work ownership and evidence links; re-read Plane for current status.

## Why there are multiple working folders

Git worktrees share repository history while providing separate branch files. They do not automatically copy a new document or code change to each other. A file created on a review branch appears in `main` only after integration and updating that checkout. A link ending in `:43` means line 43 of the file, not part of its filename.

The preserved `/Volumes/Developer/projects/DoseTap` checkout owns the shared Git database at `DoseTap/.git`. It contains older local work and private drafts. Do not delete that directory or copy its entire dirty tree over main. Its presence is a preservation boundary, not an additional shipping authority.

## Local archives and pending work

The September 30 local reconciliation uses:

- `/Volumes/Developer/projects/_DoseTap_Archive/2026-09-30/completed/` for worktrees associated with merged PRs.
- `/Volumes/Developer/projects/_DoseTap_Archive/2026-09-30/protected/` for the prior dirty main and other preserved local changes.
- `/Volumes/Developer/projects/_DoseTap_Archive/2026-09-30/evidence/` for private file manifests and migration readback.
- `/Volumes/Developer/projects/_DoseTap_Active/` for remaining open or unpublished branch work.

The original dirty main is preserved as `protected/DoseTap-main-local-changes`, on `preserved/main-before-2026-09-30`. Local changes are retained there; they are not silently applied to the new main.

Use `git worktree list` to find a branch's current folder. Retain its local evidence/configuration and verify branch, HEAD and file contents before moving or retiring it. A merged PR, clean `git status` or non-ancestor head is insufficient by itself: squash/rebase integration can change commit identity, and ignored files can hold useful evidence. Use `git worktree move` for a linked worktree; do not move it manually or force-delete it. Local archive manifests provide the exact old/new mapping for reversal.

Keep future short-lived work under `_DoseTap_Active`, archive it after integration, and leave the everyday project and document entry points stable. Open or unpublished branches must remain explicitly pending; relocation does not approve or merge them.
