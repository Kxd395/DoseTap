# Dashboard audit decisions

- Work in DoseTap-main only; preserve original DoseTap checkout and owner scheme edit.
- Local data remains authoritative for medication/check-ins. Provider sleep values retain source labels; missing data is never a negative answer or zero observation.
- Do not infer treatment effectiveness, ideal timing, or physiological awake duration from logging frequency.
- Keep nightly timing rules and dose writes unchanged. This work is analytics and presentation, not medication guidance.
- Favor existing recorded data and small corrections; no new dependency, provider, migration, cloud upload or production-data mutation.
- Add useful metrics only with explicit denominator, units, coverage and tests. Record unsupported candidates rather than fabricating values.
- Current artifact/runtime tests are not proof of physical provider accuracy or owner/device/accessibility acceptance.

## Confirmed implementation decisions
- Manual supply, first pre-sleep bottle entry, Typical Week/nightly override, and locked-dose alarm behavior stay outside this analytics correction. Existing bottle UI regression passed.
- Separate source selection rather than automatically blend Apple Health and WHOOP. Longest scored overnight WHOOP segment per mapped night; no overlapping-segment summation or inferred timestamps.
- Recorded pairs drive timing; active outcomes are pending, explicit skips are recorded outcomes, missing means no recorded outcome after the configured maximum boundary. This is descriptive history, not prospective dose advice.
- Relative percentage change is retained for averages with nonzero prior value; rate change is percentage points and works from a zero baseline. Neutral color does not rank a higher/lower interval as healthier.
- No new dependency, database/schema migration, production write, phone install, push or deployment. Pure UI fixtures are guarded by DEBUG + simulator + explicit launch argument and do not write records.
- Build 0.4.15 (17) distinguishes the analytics update. Only version hunks from project.pbxproj were staged; concurrent Xcode reorder and pre-existing UI scheme edits remain uncommitted.
- P1/P2 describe audit severity, not medical risk scores. Plane DOSETAP-45 remains In Progress while physical provider/device/accessibility gates remain.
- Pending questions: source parity during travel; treatment of multiple legitimate sleep segments versus overlapping imported duplicates; whether optional supply status and median/range earn dashboard space. Defaults or settings changes must not be applied retroactively as historical facts.


## Owner missing-content correction (2026-09-05)
- Restore the established full-scroll dashboard as the default All view; Overview/Trends/Data are optional filters. This supersedes the previous default Overview presentation.
- Keep corrected source-specific measurements, observed denominators and timing semantics. Do not reintroduce invented bathroom duration, statistical-confidence wording, an invalid streak or treatment-effectiveness claims to reproduce the old appearance.
- Captured Metrics Inventory returns as a reference, with explicit availability wording. Empty datasets retain access to integrations and reference information.
- App version 0.4.16 (18) identifies this visibility correction; no signed-device installation is performed.


## Build-14 comparison and shared section presentation
- User clarified that the original means build 14, including earlier work. Git verifies 0.4.12 (14) in `433ef43` and `2b93aa0`; the latter dashboard is unchanged through `37da941`. The comparison includes both revisions, not just the recent rewrite.
- One set of cards/model properties serves All, Overview, Trends and Data. Restore useful duplicate summary displays using existing aggregate values; these are not competing calculations.
- Replace old confidence wording with category coverage; count consecutive finished civil nights for streak; describe timing change direction without health judgments. Preserve distinct Health/WHOOP values and actual observed denominators.
- Existing WHOOP range colors are centralized; category accents and chart legends explain remaining color differences. No new palette dependency, clinical threshold, provider, DB mutation or migration.
- Version advances to 0.4.17 (19), not a rollback to build 14. Signed-device and owner-observed comparison remain acceptance gates.
