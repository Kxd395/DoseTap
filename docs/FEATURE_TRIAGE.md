# DoseTap feature triage

Status: Current code-backed feature reference
Last verified: 2026-09-02

`Implemented` means a shipping-target code path exists. It does not mean every runtime, signed-device, provider, privacy, or owner-observed gate passed. Plane owns work status; `docs/audit/2026-09-01/findings.md` owns the latest data-integrity evidence.

| Feature | Implementation state | Acceptance state | Decision and evidence |
| --- | --- | --- | --- |
| Dose 1, Dose 2, skip, and snooze policy | Implemented | Partial release evidence | Keep. All surfaces must use `DoseActionCoordinator`, `DoseRegistrationPolicy`, and the transactional repository boundary. DOSETAP-34 retains signed-device and recovery gates. |
| Early, late, after-skip, and extra-dose classification | Implemented | Automated coverage present; clinical/product wording remains governed | Keep under current SSOT. Do not infer a missing dose or silently change a recorded classification. |
| Morning check-in and reconciliation | Implemented | Automated storage coverage present; full owner workflow remains part of release acceptance | Keep. Source record, normalized submission, and derived symptom changes use one transaction where specified. |
| Session rollover and canonical night identity | Implemented | Cross-zone export/Studio regression complete; physical travel evidence remains open | Keep. Session grouping rolls at 18:00 and closure is not midnight. See DOSETAP-35 and DOSETAP-37. |
| Sleep event logging | Implemented | Automated coverage present | Keep. Medication vocabulary is rejected from the sleep-event route. |
| Nap start/end | Partial | Overlap and malformed-pair behavior not fully accepted | Defer expansion. Nap markers remain paired event strings, not canonical enum cases. |
| Other medication logging | Implemented | Whole-lifecycle CRUD proof incomplete | Keep with DOSETAP-39 lifecycle work. It is separate from the Dose 1/Dose 2 state machine. |
| Symptom event foundation | Storage implemented; UI planned | Transaction tests exist; body-map UI not accepted | Continue as bounded Plane work. Do not call the body-map product shipped. |
| Apple Health import | Implemented with explicit source handling | Signed-device grant, denial, no-data, real-data, and cross-screen parity remain open | Hold release claim. See DOSETAP-10 and DT-AUD-028. |
| WHOOP integration | Implemented behind configuration | Live OAuth and end-to-end provider validation remain open | Defer production enablement. See `docs/WHOOP_INTEGRATION.md`. |
| Dashboard aggregation and recent nights | Implemented | Denominator/source regressions complete; owner same-night comparison remains open | Keep with explicit missing counts and source labels. See DOSETAP-36. |
| Current timezone display | Implemented | Historical named-zone provenance and physical timezone-change validation remain open | Keep current UI; continue DOSETAP-37. |
| CloudKit sync | Implemented for staging validation only | Two-device convergence and lifecycle coverage remain open | Do not enable in shipping `DoseTap`. Use `docs/CLOUDKIT_GO_LIVE_CHECKLIST.md`. |
| CSV and Studio export | Implemented | Content-equal restore and all-domain lifecycle proof remain open | Keep export; do not call it a complete backup. See DOSETAP-39. |
| Diagnostic action correlation | Implemented | Signed-device Dose 2 trace remains open | Keep privacy-filtered attempted, committed, and failed outcomes. See DOSETAP-38. |
| Flic hardware actions | Implemented route | Physical hardware and complete user-flow acceptance not current | Defer product claim until owner-observed validation. |
| DoseTap Studio insights | Implemented read-only viewer | Import/source parity and owner data verification remain bounded | Keep read-only. See `docs/INSIGHTS_STATUS.md`. |
| watchOS companion | Proposal only | No target, scheme, signing, CI, or physical acceptance | Defer. See `docs/COMPANION_TARGET_STATUS.md`. |
| Home and Lock Screen widgets | Proposal only | No extension target, App Group acceptance, CI, or physical acceptance | Defer. See `docs/COMPANION_TARGET_STATUS.md`. |
| Supply-cycle end notification | Proposed vNext | No shipping implementation or notification acceptance | Plan after data-integrity foundation. It is a local order-ahead reminder, not a refill or order transaction. |

## Status sources

- Current planning index: `docs/PLANNING.md`
- Current behavior contract: `docs/SSOT/README.md`
- Latest data-integrity findings: `docs/audit/2026-09-01/findings.md`
- Whole-project data lifecycle: `docs/audit/2026-09-01/crud-matrix.md`
- Proposed vNext package: `docs/MYWAV_DOSETAP/README.md`

