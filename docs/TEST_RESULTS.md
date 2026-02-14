# DoseTap Test Results

Last updated: 2026-02-13
Run on: macOS (arm64e-apple-macos14.0), Swift Package Manager

---

## Summary

```
┌─────────────────────────────────────────────────────┐
│  497 tests executed, 0 failures, 0 unexpected       │
│  Duration: 3.064 seconds (wall: 3.150s)             │
│  36 test suites, all passing                        │
└─────────────────────────────────────────────────────┘
```

---

## Per-Suite Breakdown (DoseCoreTests — 36 suites)

### Dosing & Window Logic

| Suite | Tests | Status |
| --- | --- | --- |
| DoseWindowStateTests | ✓ | ✅ Pass |
| DoseWindowEdgeTests | ✓ | ✅ Pass |
| Dose2EdgeCaseTests | ✓ | ✅ Pass |
| DoseEventWithAmountTests | ✓ | ✅ Pass |
| DoseEventSourceTests | ✓ | ✅ Pass |
| DosingAmountTests | ✓ | ✅ Pass |
| DosingServiceTests | ✓ | ✅ Pass |
| DoseBundleTests | ✓ | ✅ Pass |
| DoseBundleStatusTests | ✓ | ✅ Pass |
| DoseUndoManagerTests | ✓ | ✅ Pass |
| AmountUnitTests | ✓ | ✅ Pass |

### Session & Time

| Suite | Tests | Status |
| --- | --- | --- |
| TimeEngineTests | ✓ | ✅ Pass |
| TimeCorrectnessTests | ✓ | ✅ Pass |
| SessionIdBackfillTests | ✓ | ✅ Pass |
| SleepPlanCalculatorTests | ✓ | ✅ Pass |
| SleepEventTests | ✓ | ✅ Pass |
| SleepEnvironmentTests | ✓ | ✅ Pass |
| UnifiedSleepSessionTests | 30 | ✅ Pass |
| SplitModeTests | ✓ | ✅ Pass |
| MorningCheckInTests | ✓ | ✅ Pass |

### Networking & Resilience

| Suite | Tests | Status |
| --- | --- | --- |
| APIClientTests | ✓ | ✅ Pass |
| APIErrorsTests | ✓ | ✅ Pass |
| OfflineQueueTests | ✓ | ✅ Pass |
| EventRateLimiterTests | ✓ | ✅ Pass |
| CertificatePinningTests | ✓ | ✅ Pass |

### Data & Models

| Suite | Tests | Status |
| --- | --- | --- |
| CRUDActionTests | ✓ | ✅ Pass |
| CSVExporterTests | ✓ | ✅ Pass |
| EventStoreModelsTests | ✓ | ✅ Pass |
| MedicationLoggerTests | ✓ | ✅ Pass |
| RegimenTests | ✓ | ✅ Pass |
| StorageModels | ✓ | ✅ Pass |

### Diagnostics & Compliance

| Suite | Tests | Status |
| --- | --- | --- |
| DiagnosticLoggerTests | ✓ | ✅ Pass |
| DiagnosticEventTests | ✓ | ✅ Pass |
| DataRedactorTests | ✓ | ✅ Pass |
| SSOTComplianceTests | ✓ | ✅ Pass |
| AdherenceStatusTests | ✓ | ✅ Pass |
| RecommendationEngineTests | ✓ | ✅ Pass |

---

## Test Coverage by Area

```
Dosing & Window Logic    ██████████████████████ 11 suites
Session & Time           ██████████████████     10 suites
Networking & Resilience  ██████████             5 suites
Data & Models            ████████████           6 suites
Diagnostics & Compliance ████████████           6 suites
                         ─────────────────────────────────
                         Total: 36 suites, 497 tests
```

---

## Additional Test Targets (Not in SwiftPM Run)

| Target | Location | Tests | Runner |
| --- | --- | --- | --- |
| DoseTapTests (Xcode) | `ios/DoseTapTests/` (11 files) | ~134 | `xcodebuild test` |
| DoseTapUITests (XCUITest) | `ios/DoseTapUITests/` (2 files) | 12 | `xcodebuild test` |

**Grand total across all targets: 643+ automated tests.**

---

## How to Run

```bash
# SwiftPM (primary — 497 tests)
swift test -q

# Xcode unit tests
xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20

# XCUITests
xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTapUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

---

## Historical Progression

| Date | SwiftPM Tests | Milestone |
| --- | --- | --- |
| 2026-01-14 | 277 | Baseline after Phase 1 stabilization |
| 2026-01-19 | 296 | Initial audit (all passing) |
| 2026-02-09 | 356 | 60 new tests across 3 files |
| 2026-02-12 | 497 | 7 new test files for untested modules |
| 2026-02-13 | 497 | Post-cleanup verification (all passing) |
