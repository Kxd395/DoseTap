# Dashboard recorded-dose spacing eligibility

The phone dashboard uses actual dose-occurrence instants. A spacing measurement
requires both instants and a finite, strictly positive Dose 2 minus Dose 1
difference. Equal or reversed instants remain recorded outcomes, but cannot
contribute to spacing averages, interval charts, reference-window counts or
percentages. Their original timestamps are retained for review.

Evaluate eligibility before rounding. A positive 30-second pair is eligible
as 0.5 minutes even if a legacy whole-minute label displays zero. Midnight and
DST do not reset elapsed time. Missing doses, explicit skips and pending outcomes
keep their existing separate meaning; this rule does not change clinical records.

Show a timing-review count for nonpositive pairs. Its denominator is nights with
both selected dose instants. A recorded outcome may need timing review without
becoming a missing or skipped outcome. The built-in 150–240 minute inclusive
spacing reference is descriptive and does not establish a historical prescription.

Duplicate/taken-versus-skipped reconciliation is a separate remaining alignment
task across phone, export and iPad. This change does not silently reinterpret it.
