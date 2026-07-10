---
description: Prepare dependency-ordered DoseTap work items for Axxess without writing to GitHub Issues.
tools: []
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

1. Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").
1. From the executed script, extract the path to **tasks**.
1. Confirm the repository identity by running:

```bash
git config --get remote.origin.url
```

> [!CAUTION]
> Axxess is the canonical execution tracker. Never create GitHub Issues from this agent.

1. For each task, prepare an Axxess-ready work-item draft with title, description, priority, proposed state, labels, dependencies, acceptance criteria, and a stable external ID.
1. Write the drafts to the feature directory as `axxess-work-items.md` for review and import through the project-scoped Axxess integration.

> [!CAUTION]
> Do not call Plane REST endpoints directly and do not read `PLANE_API_KEY`. Use the scoped Symphony tracker tool when it is available.
