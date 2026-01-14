# Tasks: Manual Dose Time Entry & Adjustment

**Input**: plan.md, spec.md
**Feature ID**: 003-manual-dose-entry

---

## Phase 1: Data Model & Validation

### Tests First ⚠️

- [ ] T001 [P] Create `Tests/DoseCoreTests/ManualEntryValidationTests.swift`
- [ ] T002 [P] Test: `test_validateManualDose2_at90min_returnsNil`
- [ ] T003 [P] Test: `test_validateManualDose2_at89min_returnsTooEarly`
- [ ] T004 [P] Test: `test_validateManualDose2_at360min_returnsNil`
- [ ] T005 [P] Test: `test_validateManualDose2_at361min_returnsTooLate`
- [ ] T006 [P] Test: `test_validateAdjustment_at30min_returnsNil`
- [ ] T007 [P] Test: `test_validateAdjustment_at31min_returnsTooLarge`
- [ ] T008 [P] Test: `test_validateRecovery_at11hours_returnsNil`
- [ ] T009 [P] Test: `test_validateRecovery_at13hours_returnsTooOld`

### Implementation

- [ ] T010 Create `ios/Core/ManualEntryValidation.swift`
- [ ] T011 Add `ManualEntryError` enum with all cases
- [ ] T012 Add `ManualEntryValidator` struct with static methods
- [ ] T013 Add constants to `docs/SSOT/constants.json`
- [ ] T014 Run tests, verify 9/9 pass

**Checkpoint**: Validation logic complete and tested

---

## Phase 2: SessionRepository Methods

### Tests First ⚠️

- [ ] T015 Add tests to `ios/DoseTapTests/SessionRepositoryTests.swift`
- [ ] T016 Test: `test_setDose2TimeManual_validTime_succeeds`
- [ ] T017 Test: `test_setDose2TimeManual_tooEarly_throwsError`
- [ ] T018 Test: `test_setDose2TimeManual_withoutConfirmation_throws`
- [ ] T019 Test: `test_adjustDose2Time_plus20min_succeeds`
- [ ] T020 Test: `test_adjustDose2Time_plus45min_throwsError`
- [ ] T021 Test: `test_recoverSkippedSession_converts_skipToComplete`
- [ ] T022 Test: `test_recoverSkippedSession_oldSession_throwsError`

### Implementation

- [ ] T023 Add `saveDose2Manual(timestamp:)` to EventStorage
- [ ] T024 Add `updateDose2Time(newTime:originalTime:)` to EventStorage
- [ ] T025 Add schema migration for `source`, `original_timestamp`, `entry_timestamp`
- [ ] T026 Add `setDose2TimeManual(_:confirmed:)` to SessionRepository
- [ ] T027 Add `adjustDose2Time(_:)` to SessionRepository
- [ ] T028 Add `recoverSkippedSession(dose2Time:)` to SessionRepository
- [ ] T029 Run tests, verify all pass

**Checkpoint**: Repository layer complete

---

## Phase 3: Manual Entry UI

### Implementation

- [ ] T030 Create `ios/DoseTap/Views/ManualDoseEntryView.swift`
- [ ] T031 Add time picker with min/max constraints
- [ ] T032 Add interval preview (calculated from selected time)
- [ ] T033 Add confirmation checkbox
- [ ] T034 Add validation error display
- [ ] T035 Add Night Mode theme support
- [ ] T036 Add "I Already Took It" button to ContentView (expired state)
- [ ] T037 Wire button to present ManualDoseEntryView sheet
- [ ] T038 Handle save action → call `setDose2TimeManual`
- [ ] T039 UI test: Verify picker constraints work

**Checkpoint**: Manual entry flow works end-to-end

---

## Phase 4: Time Adjustment UI

### Implementation

- [ ] T040 Create `ios/DoseTap/Views/EditDoseTimeView.swift`
- [ ] T041 Add original time display
- [ ] T042 Add time picker with ±30 min constraint
- [ ] T043 Add adjustment preview ("−5 min" / "+10 min")
- [ ] T044 Add save action → call `adjustDose2Time`
- [ ] T045 Add edit icon to SessionDetailView dose rows
- [ ] T046 Wire edit icon to present EditDoseTimeView

**Checkpoint**: Time adjustment works

---

## Phase 5: Recovery Flow

### Implementation

- [ ] T047 Update `IncompleteSessionBanner` with "I Took Dose 2" option
- [ ] T048 Add menu with Complete/Recovery/Dismiss options
- [ ] T049 Wire "I Took Dose 2" to present ManualDoseEntryView
- [ ] T050 On save → call `recoverSkippedSession(dose2Time:)`
- [ ] T051 Verify banner dismisses after recovery
- [ ] T052 Verify session shows as `completed_manual`

**Checkpoint**: Recovery flow works

---

## Phase 6: Testing & Polish

### Diagnostic Logging

- [ ] T053 Add `dose2ManualEntry` to DiagnosticEvent.swift
- [ ] T054 Add `dose2TimeAdjusted` to DiagnosticEvent.swift
- [ ] T055 Add `sessionRecovered` to DiagnosticEvent.swift
- [ ] T056 Verify logs appear in trace viewer

### SSOT Updates

- [ ] T057 Add "Manual Entry" section to `docs/SSOT/README.md`
- [ ] T058 Document `completed_manual` terminal state
- [ ] T059 Document recovery window rules
- [ ] T060 Update Contract Index table

### Final Testing

- [ ] T061 Integration: Auto-skip → Recovery → Verify completed
- [ ] T062 Integration: Log dose → Adjust → Verify update
- [ ] T063 Edge: Test 12-hour boundary exactly
- [ ] T064 Edge: Test 90-minute minimum exactly
- [ ] T065 Run full test suite: `swift test`

**Checkpoint**: Feature complete

---

## Summary

| Phase | Tasks | Status |
| ----- | ----- | ------ |
| Phase 1: Validation | 14 | ⏳ 0% |
| Phase 2: Repository | 15 | ⏳ 0% |
| Phase 3: Manual Entry UI | 10 | ⏳ 0% |
| Phase 4: Adjustment UI | 7 | ⏳ 0% |
| Phase 5: Recovery Flow | 6 | ⏳ 0% |
| Phase 6: Polish | 13 | ⏳ 0% |
| **Total** | **65** | **0%** |
