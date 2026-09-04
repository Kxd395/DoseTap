# 02 — Target Rebuild Scope

## Product Surfaces

### Tonight

Primary 2-4 AM operating surface.

Required:

- Large, low-cognitive-load dose state.
- Current session state, next action, and countdown.
- Dose 1, Dose 2, skip, snooze, late dose, after-skip, and extra dose flows through one shared policy.
- Night mode, high contrast, reduced motion, and large Dynamic Type support.
- Offline-first writes with clear local success feedback.
- No dashboard-heavy analytics on this surface.

### Pre-Sleep

Required:

- Brief pre-sleep check-in for factors likely to affect sleep: caffeine, alcohol, exercise, stress, naps, schedule variance, medication context.
- Partial completion support.
- Idempotent updates for the same session.
- Clear distinction between pre-sleep planning and post-night review.

### Morning Check-In

Required:

- Fast wake-state capture.
- Symptom and sleep quality fields already represented in current schema should be reviewed and retained if clinically useful.
- Session closure must occur only after successful persistence.
- Draft/retry behavior if app is interrupted.

### History

Required:

- Session list with dose timing, sleep events, medication entries, morning check-in status, and integration data availability.
- Safe edit flows for dose timestamps and notes.
- Audit trail or immutable event history for clinical data changes.
- Export by date range.

### Dashboard

Required:

- Weekly/monthly trends.
- Dose interval compliance.
- Dose effectiveness correlation.
- Night scores.
- Sleep quality, wake symptoms, and biometric trends.
- Data completeness and source labels.
- No fake health data and no statistically weak claims without sample-size warnings.

### Settings

Required:

- Medication configuration.
- Sleep schedule and prep-time configuration.
- Integrations: HealthKit, WHOOP, Flic, widgets/watch status.
- Data management: export, import/migration status, delete data, support bundle, diagnostics.
- Privacy controls and local-only/cloud-staging mode clarity.

## Storage and Sync Scope

### Version 2 Baseline

- Keep local-first as the default and minimum viable architecture.
- Use a repository interface so app views do not depend directly on SQLite or CloudKit.
- Support idempotent local migrations from the existing SQLite schema.
- Preserve CSV export and support bundle generation before and after migration.

### Sync Architecture

SQLite local + CloudKit adapter.

- Lower migration risk.
- Keeps current domain/storage model closer to existing behavior.
- Requires custom conflict handling and tombstones.

Recommendation: prove migration, conflict handling, account sign-out, offline behavior, and watch sync latency with real devices before enabling production sync.

## Integration Scope

| Feature | Version 2 Recommendation |
| --- | --- |
| HealthKit | First-class. Import sleep, heart rate, HRV, respiratory rate, resting HR where permitted. |
| WHOOP | Feature-flagged until real OAuth credentials, PKCE validation, and rate-limit tests pass. |
| Flic | Supported only if dose-confirmation parity can be guaranteed. |
| Apple Watch | High-value for dose status and logging; requires shared storage/sync story first. |
| Widgets | Read-mostly status, countdown, and next action. Mutating widgets require policy review. |
| Siri/Shortcuts | Status and safe quick-log events first. Dose actions require explicit app confirmation unless Apple interaction model proves adequate. |
| CloudKit | Staging first, production only after migration and rollback rehearsals. |

## Explicit Non-Goals for First Rebuild Release

- Clinician portal.
- Multi-user caregiver dashboard.
- Public cloud backend storing medication data.
- AI diagnosis or medical advice.
- Replacing clinician instructions.
- Social/community features.
- Real-time collaboration.
