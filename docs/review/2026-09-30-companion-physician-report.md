# iPad physician review implementation checkpoint

DOSETAP-45 remains In Progress. This checkpoint supplies an immutable read-only report adapter; it does not close device, privacy, owner-observed or release acceptance.

The adapter requires the exact source snapshot, canonical selected nights and an explicit period at the received capture cutoff. Same headers with changed rows fail. Actual metric occurrence timestamps place records; unknown/day-only times stay unplaced. Shared night filters and independent daytime scope are explicit. Night outcome source detail, sourced contexts, custom daytime ratings/events and reviewed nap estimates retain provenance and coverage. WHOOP and provider nap reconciliation are explicitly unavailable in the current transferred format.

Numeric summaries reuse PhysicianReportSnapshot. Full-period/monthly/recent layers and JSON/summary CSV/detail CSV/print text retain the same immutable values. Sampling/context strata remain separate; resolved nap duplicates are detail-only; timer duration does not become measured sleep. No phone editing, visit notes or saved phone previews are transported.

Validation on 2026-09-30:
- RED: missing DashboardCompanionPhysicianReport type captured before implementation.
- Six focused regression tests passed.
- Full core: 1,120 XCTest plus 43 Swift Testing tests passed.
- SwiftPM build, SSOT, Plane workflow and diff checks passed.

The second checkpoint adds the read-only iPad view and shared FileDocument helper. It exposes full-period, all-month and recent layers, source detail, explicit scope and unavailable-source disclosures. Exports are immutable JSON, summary CSV, detail CSV and plain text, plus native Print. No direct PDF-file exporter was added. Changed source/filter selections retain the previous capture with a stale-preview explanation. Nested daytime source payloads name their Unix epoch separately from the report envelope's Foundation epoch.

Second-checkpoint validation:
- RED: actual-formatter test failed to compile before the shared print formatter existed; daytime source-epoch assertions failed before labels were added.
- Generic iPad simulator build-for-testing passed for arm64 and x86_64. The required generic phone simulator build also passed after copying the checked-in nonsecret Secrets template into this isolated checkout's ignored local configuration.
- The focused native UIPrintPageRenderer/PDFKit test passed on the allocated iPad simulator: multiple pages, exact complete formatter text, final source record and snapshot provenance. Synthetic PDF/text evidence is retained in `.build/physician-print-tests-v3.xcresult`.
- The initial synthetic marker used underscores, which PDFKit extracted after the words; the final test uses plain words and still checks the final record and snapshot identifier.
- Full core after the source-epoch labels: 1,120 XCTest plus 43 Swift Testing tests passed; SwiftPM build, Plane workflow, SSOT, architecture, app-version, companion-target, mutation-path, legacy-safety and documentation checks passed.
- Repository hygiene initially returned a nonzero Git fsck result; an isolated read-only fsck showed only dangling objects, and the full hygiene retry passed. No Git object/reference repair or cleanup was performed.

Root integration, the integrated native print-sheet cancellation journey and physical-device/owner review remain open. The native pagination test is programmatic evidence, not physical print or owner-observed acceptance. Physical iPad launch remains deferred at the user's request. No version bump, installation, PR or Plane closeout was performed by this slice.
