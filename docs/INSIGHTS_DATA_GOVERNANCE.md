# DoseTap Insights Data Governance

Last updated: 2026-03-21

## Scope

This document covers the `DoseTap` iPhone export path and the read-only `DoseTapStudio` macOS insights workflow.

## Storage Model

- HealthKit and WHOOP ingestion happens on iPhone only.
- `DoseTapStudio` remains read-only for imported exports.
- Imported `insights_bundle.json` files are treated as immutable source payloads.
- Studio can re-save the exact imported bundle bytes without rewriting or normalizing the original payload.

## Privacy Boundaries

- Do not store identifiable PHI in iCloud / CloudKit for the insights workflow.
- Use local export/import files for review, clinician sharing, and audit packages.
- Clinician-facing exports should prefer redacted mode when free-text notes or exact timestamps are not required.

## Retention

- Keep the original exported bundle only as long as it is needed for review or clinician follow-up.
- Prefer generating a new export over mutating an older bundle.
- If a bundle is no longer needed, delete the imported file from local storage and clear it from Studio.

## Deletion

- Deleting an imported bundle from disk removes the source payload for future Studio reloads.
- Clearing data in Studio removes the in-memory imported sessions, validation state, analytics, and cached bundle bytes for the current workspace session.
- Redacted clinician exports should be regenerated instead of edited in place.

## Sharing

- Share the full immutable bundle only with trusted technical reviewers or clinicians who need exact provenance.
- Share redacted provider summaries, recommendation packages, and CSV exports when free-text notes or exact timestamps are not necessary.
- Include the observational disclaimer in any recommendation review package.

## Provenance

- Bundle fingerprints identify the exact imported payload.
- Metric facts should carry source provenance such as `manual`, `healthkit`, `whoop`, or `derived`.
- Derived metrics should remain explainable and traceable back to imported source facts.

## Language

- Use “insight,” “pattern,” and “historically associated with” language.
- Do not describe timing output as prescribing guidance or a dosage calculator.
