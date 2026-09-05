# Dashboard audit decisions

- Work in DoseTap-main only; preserve original DoseTap checkout and owner scheme edit.
- Local data remains authoritative for medication/check-ins. Provider sleep values retain source labels; missing data is never a negative answer or zero observation.
- Do not infer treatment effectiveness, ideal timing, or physiological awake duration from logging frequency.
- Keep nightly timing rules and dose writes unchanged. This work is analytics and presentation, not medication guidance.
- Favor existing recorded data and small corrections; no new dependency, provider, migration, cloud upload or production-data mutation.
- Add useful metrics only with explicit denominator, units, coverage and tests. Record unsupported candidates rather than fabricating values.
- Current artifact/runtime tests are not proof of physical provider accuracy or owner/device/accessibility acceptance.
