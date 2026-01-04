# DoseTap — Spec & Correctness TODO (follow-along)

Last updated: 2026-01-02

This is the execution checklist to make the SSOT **unambiguous, machine-checkable, and contradiction-proof**.

> Scope: This doc is intentionally actionable (what to do + how to prove it). The normative rules still live in `docs/SSOT/README.md`.

---

## P0 — Trust breakers (must fix before “production-ready”)

### 1) Unify interval math across the app (single helper)

**Why:** Negative intervals destroy trust. The “-1201 minutes” screenshot is a midnight rollover interval bug, not storage split brain.

**Contract (must hold everywhere):**

- Intervals MUST be computed from absolute timestamps (`Date` / ISO8601), not from `session_date + time-of-day strings`.
- If `end < start` and the gap is plausibly “after midnight”, treat as rollover:
  - Compute `rolled = (end - start) + 24h`.
  - If `rolled` is in `[0h, 12h]`, use `rolled`.
  - Otherwise treat as a data ordering bug and surface an invariant failure in debug builds.

**Acceptance:**

- Dose 1: 8:53 PM
- Dose 2: 12:51 AM
- Interval shown is **+238 minutes** everywhere (History, Timeline, dashboard, export).

**Implementation checklist:**

- [ ] Add a single canonical helper (in core/shared logic), e.g.:
  - `minutesBetween(start:end:) -> Int`
- [ ] Replace any one-off interval math with calls to the helper.
  - Search for: `intervalMinutes`, `timeIntervalSince`, and UI formatters that do their own subtraction.

**Verification:**

- [ ] Add a unit test for the midnight rollover example (8:53 PM → 12:51 AM = 238 min).
- [ ] Add a unit test covering a nonsensical negative delta (should assertionFail in debug / still return negative minutes in release-safe path).

---

## P0 — Split brain “single writer contract” (close remaining escape hatches)

Split brain means two or more live code paths can write the same “truth” to different stores.

### 2) Codify and continuously enforce the single writer boundary

**Contract:**

- Views and view models MAY call `SessionRepository` only.
- `SessionRepository` is the only module allowed to talk to `EventStorage`.
- `EventStorage` is the only module allowed to talk to SQLite.
- `SQLiteStorage.swift` is legacy and banned.

**Acceptance:**

- CI fails if any UI, watch, widget, extension (or other target) references any banned symbol.

**Implementation checklist:**

- [ ] Audit non-UI entrypoints where split brain can hide:
  - widgets
  - watchOS app
  - notification actions
  - Siri shortcuts / intents
  - share extensions
- [ ] Confirm each entrypoint is one of:
  - (a) read-only, or
  - (b) routes through `SessionRepository`.

**Verification:**

- [ ] Run `tools/ssot_check.sh` and confirm PASS.
- [ ] Confirm CI guard patterns cover *every target* (not just iOS app UI sources).

---

## P1 — Make SSOT enforceable (spec machinery)

### 3) Hard Invariants (MUST/SHALL) mapping table

**Goal:** Each MUST rule is backed by code + tests + CI checks.

**Implementation checklist:**

- [ ] Add a section to `docs/SSOT/README.md`: `Hard Invariants (MUST/SHALL)`.
- [ ] Include a table:
  - Invariant → Enforced by (file/type) → Test proving it → CI guard (if applicable)

**Minimum invariants to list:**

- [ ] All storage writes go through `SessionRepository`.
- [ ] Interval math uses absolute timestamps only.
- [ ] `session_date` is a grouping key only.
- [ ] No personal identifiers belong in SSOT.

### 4) Time Model section (expand)

**Implementation checklist:**

- [ ] Define storage format explicitly:
  - UTC ISO8601 timestamps
  - If/when added: `tz_identifier` + `local_offset_minutes`
- [ ] Define session grouping rules:
  - cross-midnight assignment (midnight–6AM belongs to prior session)
- [ ] Prohibit timestamp reconstruction from display strings.

### 5) State machine transition table (minimal v1)

**Implementation checklist:**

- [ ] Add a table:
  - `Current state | Action | Guard | Writes | Next state | Notification updates`
- [ ] Ensure these actions are represented:
  - Dose 1
  - Dose 2
  - Snooze
  - Skip
  - Undo
  - Late Dose 2 override

### 6) Schema migration policy

**Implementation checklist:**

- [ ] Define:
  - every schema change bumps `schema_version`
  - every change has a numbered migration
  - migrations are idempotent and tested
- [ ] Link to where migrations live in-repo.

---

## P2 — Maintainability & naming

### 7) Normalize naming

**Goal:** The same term is used across SSOT, UI labels, deep links, and component IDs.

**Implementation checklist:**

- [ ] Decide on canonical labels (e.g. “Tonight”, “History”, “Settings”, “Review”).
- [ ] Ensure consistent naming in:
  - component IDs
  - deep link routes
  - docs

---

## Verification gates (run every time)


- [ ] `tools/ssot_check.sh` passes
- [ ] `swift test -q` passes
- [ ] Manual smoke:
  - log Dose 1 at ~8:53 PM
  - log Dose 2 at ~12:51 AM
  - interval shows **+238 minutes** on all screens and in export
