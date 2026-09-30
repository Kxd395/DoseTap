# Dashboard dose-pattern evidence (DOSETAP-45)

Version 1, September 30, 2026. Pattern review is a patient report for a specific stable observation identity; it never administers medication, creates a dosing session, or changes alarms.

- Canonical administration IDs are deduplicated only when their full evidence agrees. Different IDs at the same time remain distinct and require pair review. Extra doses, conflicting slots/identities, omission plus taken, nonfinite times and nonpositive pairs require review.
- Recorded administration count, explicitly confirmed complete count, historical patient-reported plan and occurrence-time completeness are separate. A check-in or closed session alone never confirms count. An unresolved open session is in progress; a closed unresolved second outcome remains incomplete.
- An explicit complete count may report an administration whose time is unknown; preserve that reported count and keep its interval unavailable. A review that reports fewer administrations than the ledger contains requires review. Reviewed count zero without administration records is a valid no-dose report, never a medication-free claim.
- A single administration has no numerical paired interval. Dose 2 omission, missing outcome, missing occurrence and conflicting evidence have different reason codes. Never substitute skip/record/session-close time or zero for a taken event.
- A versioned metric carries optional value, state, reason and unit. Missing, not applicable, partial and needs-review remain distinct. Numeric values must be finite. Sleep measurement eligibility is independent of paired-dose eligibility.
- Review records retain revision history, recorded time and the exact input fingerprint. Changed source dose evidence invalidates a prior count confirmation until reviewed again. Actual amounts are never copied from plans.
