# DoseTap Insights and Studio status

Status: Current implementation reference with open validation gates
Last verified: 2026-09-02

## Current implementation

DoseTap exports a versioned insights bundle and related files from the iPhone app. The macOS `DoseTapStudio` package imports those files into a read-only analysis workflow. The Studio source tree includes:

- import validation and immutable bundle handling under `macos/DoseTapStudio/Sources/Import/`;
- normalized insight models and builders under `macos/DoseTapStudio/Sources/Insights/`;
- Library, Night Detail, Trends, Correlations, Adherence, Recommendation, and Export views under `macos/DoseTapStudio/Sources/Views/`;
- fixture-driven tests under `macos/DoseTapStudio/Tests/`.

The iPhone export path is centered in `ios/DoseTap/SettingsStudioExport.swift`. iPhone dashboard aggregation remains separate under `ios/DoseTap/Views/Dashboard/`.

## Current boundary

- The iPhone app remains the capture and mutation system.
- Studio analyzes imported exports and must not become a second medication-write owner.
- Imported source bytes and derived models are distinct.
- Apple Health and WHOOP values must remain source-labeled.
- Missing Dose 2, skipped Dose 2, early, in-window, and late outcomes must remain distinct.
- Insight language is observational. It is not prescribing guidance or a dosage calculator.

## Evidence and open gates

The 2026-09-01 audit records complete automated evidence for canonical Studio night identity and dashboard source labels. It also leaves these stronger gates open:

- signed-device Apple Health authorization, denial, no-data, and real-data parity;
- owner comparison of Dashboard, History, Night Review, and Apple Health for the same night;
- future per-event named-timezone provenance;
- complete clear-all and content-equal backup/restore evidence;
- live WHOOP OAuth and end-to-end service validation.

See `docs/audit/2026-09-01/findings.md` and Plane items DOSETAP-10, DOSETAP-35, DOSETAP-36, DOSETAP-37, and DOSETAP-39.

## Archived source plans

The original MVP, implementation plan, and completed optimal-timing checklist are retained under `docs/archive/planning/insights/`. They explain intent but do not describe the current file layout or acceptance state.
