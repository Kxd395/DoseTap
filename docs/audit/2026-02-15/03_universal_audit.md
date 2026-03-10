# Phase 2 — Universal Repo Audit (Correctness vs SSOT)

**Date:** 2026-02-15
**Scope:** Domain invariants vs SSOT, ghost/zombie detection, channel parity, constant verification

---

## Constants Verification Matrix

| Constant | SSOT Value | Code Value | Match |
|----------|-----------|------------|-------|
| `doseWindow.minMinutes` | 150 | `DoseWindowConfig.minIntervalMin = 150` | ✅ |
| `doseWindow.maxMinutes` | 240 | `DoseWindowConfig.maxIntervalMin = 240` | ✅ |
| `doseWindow.defaultTarget` | 165 | `DoseWindowConfig.defaultTargetMin = 165` | ✅ |
| `doseWindow.validTargets` | [165,180,195,210,225] | `UserSettingsManager.validTargetOptions` | ✅ |
| `doseWindow.nearWindowThreshold` | 15 | `DoseWindowConfig.nearWindowThresholdMin = 15` | ✅ |
| `doseWindow.sleepThroughGrace` | 30 | `DoseWindowConfig.sleepThroughGraceMin = 30` | ✅ |
| `snooze.durationMinutes` | 10 | `DoseWindowConfig.snoozeStepMin = 10` | ✅ |
| `snooze.maxCount` | 3 | `DoseWindowConfig.maxSnoozes = 3` | ✅ |
| `rolloverHour` | 18 | `sessionKey(rolloverHour: 18)` | ✅ |
| SleepEvent cooldowns (bathroom/water/snack=60s, rest=0) | SSOT constants.json | `SleepEventType.defaultCooldownSeconds` | ✅ |

**All 10 critical constants verified: 10/10 match.** ✅

---

## State Machine Verification

| Phase | SSOT | Code (`DoseWindowPhase`) | Match |
|-------|------|-------------------------|-------|
| noDose1 | ✅ | ✅ | ✅ |
| beforeWindow | ✅ | ✅ | ✅ |
| active | ✅ | ✅ | ✅ |
| nearClose | ✅ | ✅ | ✅ |
| closed | ✅ | ✅ | ✅ |
| completed | ✅ | ✅ | ✅ |
| finalizing | ✅ | ✅ | ✅ |

**All 7 phases match.** ✅

---

## API Error Codes

| Code | SSOT | `DoseAPIError` | Match |
|------|------|----------------|-------|
| `422_WINDOW_EXCEEDED` | ✅ | `.windowExceeded` | ✅ |
| `422_SNOOZE_LIMIT` | ✅ | `.snoozeLimit` | ✅ |
| `422_DOSE1_REQUIRED` | ✅ | `.dose1Required` | ✅ |
| `409_ALREADY_TAKEN` | ✅ | `.alreadyTaken` | ✅ |
| `429_RATE_LIMIT` | ✅ | `.rateLimit` | ✅ |
| `401_DEVICE_NOT_REGISTERED` | ✅ | `.deviceNotRegistered` | ✅ |

**All 6 error codes match.** ✅

---

## Findings

### COR-001 (P2): SleepEventType / EventType split-brain

- **Core:** `SleepEventType` (13 cases) — bathroom, water, snack, inBed, lightsOut, wakeFinal, wakeTemp, anxiety, dream, heartRacing, noise, temperature, pain
- **App:** `EventType` (26+ cases) — adds napStart, napEnd, dose1, dose2, skipDose, snooze, extraDose, congestion, grogginess, morningCheckIn, preSleepLog, wakeSurvey, unknown(String)
- **Issue:** Core module cannot reason about nap events (napStart/napEnd). Nap pairing logic lives entirely in the app tier (`SessionRepository.napIntervals`). If Core ever needs nap awareness (e.g., for recommendations), it has no model.
- **SSOT:** Documents naps as "paired sleep events" in the app — currently consistent with code.
- **Recommendation:** Add napStart/napEnd to `SleepEventType` in Core when nap-aware recommendations are needed.

### COR-002 (P2): URLRouter bypasses DoseTapCore for extra doses

- **File:** `ios/DoseTap/URLRouter.swift` ~line 200
- **Evidence:** `SessionRepository.shared.saveDose2(timestamp:isExtraDose:true)` called directly, bypassing `DoseTapCore`
- **Risk:** The SSOT Channel Parity invariant states "All dose entry channels MUST trigger identical side effects." This direct call may skip alarm cancellation or diagnostic logging that `DoseTapCore.takeDose()` would provide.
- **Fix:** Route extra-dose deep link through `DoseTapCore` with an `isExtraDose` parameter.

### COR-003 (P3): EventType congestion/grogginess cases misleading

- **Issue:** `EventType.congestion` and `.grogginess` look like loggable sleep events but are actually morning check-in display fields. No UI trigger exists for them as standalone events.
- **Assessment:** Not a bug — they're used for History timeline display. But the naming is confusing.
- **Recommendation:** Document or comment in EventType that these are check-in display types, not loggable events.

---

## Quick Log Event Parity

| SSOT Quick Log | UserSettingsManager.allAvailableEvents | SleepEventType | Match |
|----------------|----------------------------------------|----------------|-------|
| Bathroom | ✅ `bathroom` | ✅ `.bathroom` | ✅ |
| Water | ✅ `water` | ✅ `.water` | ✅ |
| Snack | ✅ `snack` | ✅ `.snack` | ✅ |
| Nap Start | ✅ `napStart` | ❌ missing | ⚠️ App-only |
| Nap End | ✅ `napEnd` | ❌ missing | ⚠️ App-only |
| Lights Out | ✅ `lightsOut` | ✅ `.lightsOut` | ✅ |
| Brief Wake | ✅ `wakeTemp` | ✅ `.wakeTemp` | ✅ |
| In Bed | ✅ `inBed` | ✅ `.inBed` | ✅ |
| Anxiety | ✅ `anxiety` | ✅ `.anxiety` | ✅ |
| Dream | ✅ `dream` | ✅ `.dream` | ✅ |
| Heart Racing | ✅ `heartRacing` | ✅ `.heartRacing` | ✅ |
| Noise | ✅ `noise` | ✅ `.noise` | ✅ |
| Temperature | ✅ `temperature` | ✅ `.temperature` | ✅ |
| Pain | ✅ `pain` | ✅ `.pain` | ✅ |

**13/15 in Core, 15/15 in App. 2 nap events are App-tier only.** ⚠️ Documented.

---

## Channel Parity Audit

| Surface | Routes Through DoseTapCore | Alarm Side-Effects | Diagnostic Log |
|---------|---------------------------|-------------------|----------------|
| CompactDoseButton (Tonight) | ✅ `core.takeDose()` | ✅ via core | ✅ |
| HistoryViews (DoseButtons) | ✅ `core.takeDose()` | ✅ via core | ✅ |
| URLRouter (deep link) | ⚠️ Extra dose bypasses core | ⚠️ May skip alarm | ⚠️ May skip log |
| FlicButtonService (hardware) | ✅ via `FlicAction.takeDose` → core | ✅ via core | ✅ |

**3/4 surfaces fully compliant. URLRouter extra-dose path needs fix.** ⚠️

---

## SSOT Check Script Result

`tools/ssot_check.sh` output: **1 issue found** — False positive triggered by this audit's own Phase 1 document mentioning "CoreData" in a finding description. Not a real divergence.

---

## Stop Condition Assessment

No P0 findings. P2 findings documented. **Proceeding to Phase 3.**
