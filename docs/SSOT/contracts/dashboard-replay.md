# Dashboard replay and curated intervals

Status: implementation contract; device, provider and owner acceptance remain separate.

Replay uses stable durable session identity, occurrence timestamps and named source endpoints. Recording time is displayed separately. The screen, exact table and selected-session CSV/JSON snapshot use `DashboardReplaySnapshot` version `dashboard_replay_v1`; edits create new snapshots. The export preview captures its input before sharing and never sends automatically.

Intervals require explicit selected endpoints in the same resolved session. Unknown outcomes/times are unavailable, an explicit omitted D2 is not applicable, and conflicting identities/duplicate endpoints/nonpositive ordering need review. Required-wake and reminder deviations retain signed arithmetic. A saved reminder target is not proof of alarm delivery. The 150–240-minute built-in reference is not a prescription or safety classification.

Return-to-sleep additionally requires current reviewed-window evidence with an observed awake interval bounded by sleep. Missing segments and sleep spanning an administration cannot become zero latency. Reviewed coverage is an explicit read-only action and remains separate from main-episode totals. Its conflict minutes are a subset of unmeasured minutes, never added twice. The existing date-scoped loader cannot choose between multiple durable sessions on a date.

Source toggles, local changes and refresh invalidate selected coverage. Missing selected sessions are explained instead of silently replaced. Detailed medications, naps and reminder delivery require actual occurrence evidence and explicit associations; absence of those inputs stays visible without fabricated endpoints. Diagnostic logs contain no new health values.

Medication review reads both actual-administration ledgers and preserves formulation, actual amount and occurrence precision. The user explicitly selects XR, IR, a daytime administration or a recorded nap end for this inspection; no nearest-time/date association or source-record mutation occurs. Unknown occurrence times cannot become endpoints. Selected records retain original IDs, formulation and amount in CSV/JSON. Local record changes clear temporary selections. Additional nighttime administrations remain visible and require dose-pair review. Actual alarm-delivery and historical wake endpoints remain unavailable unless their own evidence is supplied.

The replay chart also shows the selected provider's timestamped main-episode intervals as asleep, awake, conflicting or unmeasured bands; it does not reconstruct stages from totals. These interval bands and any separate reviewed window remain separately named. The aligned comparison loads up to 28 sessions beginning at the selected session. The complete range remains available through selection and interval tables. CSV/JSON carry the selected view, preset, alignment and original endpoint IDs.

Actual dose markers preserve their stored session IDs; foreign or unidentified ownership makes the observation need review. Nonfinite or future administrations cannot anchor alignment. The multi-session clock view compares local noon through the following noon, while the exact table retains date and UTC offset and dose-relative intervals use UTC elapsed time. Invalid manual endpoint selections require clearing/reselection before export.
