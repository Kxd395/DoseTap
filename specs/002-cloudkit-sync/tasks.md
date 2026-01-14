# Tasks: CloudKit Integration

**Input**: Design documents from `specs/002-cloudkit-sync/`  
**Prerequisites**: spec.md, plan.md  
**Estimated Duration**: 7 days

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1=Cross-Device, US2=Offline, US3=Privacy, US4=Migration, US5=Account

---

## Phase 0: Setup & Entitlements (Day 1)

**Purpose**: Configure Xcode project for CloudKit capability

- [ ] T001 [US1] Add iCloud capability to DoseTap.xcodeproj target
- [ ] T002 [US1] Create CloudKit container `iCloud.com.dosetap.app` in Apple Developer Portal
- [ ] T003 [P] [US1] Update `DoseTap.entitlements` with iCloud container identifier
- [ ] T004 [P] [US1] Add Background Modes capability for remote notifications
- [ ] T005 [US1] Verify CloudKit container visible in CloudKit Console

**Checkpoint**: CloudKit Console shows container, app builds with capability

---

## Phase 1: Core Data Model (Day 1-2)

**Purpose**: Create Core Data model matching SQLite schema

### Tests First ⚠️

- [ ] T006 [P] [US4] Create `Tests/CloudKitTests/CoreDataModelTests.swift` - entity creation tests
- [ ] T007 [P] [US4] Test CDDoseEvent CRUD operations
- [ ] T008 [P] [US4] Test CDSleepEvent CRUD operations
- [ ] T009 [P] [US4] Test CDCurrentSession singleton constraint

### Implementation

- [ ] T010 [US1] Create `DoseTap.xcdatamodeld` in `ios/DoseTap/Models/`
- [ ] T011 [US1] Add CDCurrentSession entity (8 attributes, singleton constraint)
- [ ] T012 [P] [US1] Add CDDoseEvent entity (6 attributes, UUID primary key)
- [ ] T013 [P] [US1] Add CDSleepEvent entity (7 attributes, indexes)
- [ ] T014 [P] [US1] Add CDMorningCheckIn entity (20+ attributes, UNIQUE sessionDate)
- [ ] T015 [P] [US1] Add CDPreSleepLog entity (10 attributes, UNIQUE sessionDate)
- [ ] T016 [US3] Mark sensitive fields for CloudKit encryption (notes, metadata, symptoms)
- [ ] T017 [US1] Add indexes: sessionDate, timestamp (matching SQLite)

**Checkpoint**: All entity tests pass, model file compiles

---

## Phase 2: CloudKit Storage Layer (Day 2-3)

**Purpose**: Create `NSPersistentCloudKitContainer` wrapper

### Tests First ⚠️

- [ ] T018 [P] [US2] Create `Tests/CloudKitTests/CloudKitStorageTests.swift`
- [ ] T019 [P] [US2] Test offline initialization (no iCloud signed in)
- [ ] T020 [P] [US2] Test save persists locally without network

### Implementation

- [ ] T021 [US1] Create `ios/DoseTap/Storage/CloudKitStorage.swift`
- [ ] T022 [US1] Implement `NSPersistentCloudKitContainer` initialization
- [ ] T023 [US2] Configure local-only fallback when iCloud unavailable
- [ ] T024 [US1] Set `cloudKitContainerOptions` with container ID
- [ ] T025 [US1] Enable `automaticallyMergesChangesFromParent` for UI updates
- [ ] T026 [US5] Handle `NSPersistentCloudKitContainer.Event` notifications
- [ ] T027 [US5] Implement iCloud account change observer

**Checkpoint**: CloudKitStorage initializes, saves work offline

---

## Phase 3: Migration Manager (Day 3-4)

**Purpose**: Migrate existing SQLite data to Core Data

### Tests First ⚠️

- [ ] T028 [P] [US4] Create `Tests/CloudKitTests/MigrationTests.swift`
- [ ] T029 [P] [US4] Test migration of 100 DoseEvents
- [ ] T030 [P] [US4] Test migration of 100 SleepEvents
- [ ] T031 [P] [US4] Test migration of 30 MorningCheckIns
- [ ] T032 [P] [US4] Test migration preserves all field values
- [ ] T033 [P] [US4] Test migration performance (< 60s for 1 year data)

### Implementation

- [ ] T034 [US4] Create `ios/DoseTap/Storage/MigrationManager.swift`
- [ ] T035 [US4] Implement `fetchAllFromSQLite()` using EventStorage
- [ ] T036 [US4] Implement `batchInsertToCoreData()` with 100-record batches
- [ ] T037 [US4] Add progress callback `(Float) -> Void` for UI
- [ ] T038 [US4] Implement `verifyMigration()` - count comparison
- [ ] T039 [US4] Implement `archiveSQLiteFile()` - move to .backup
- [ ] T040 [US4] Add `UserDefaults` flag `cloudkit_migration_complete`
- [ ] T041 [US4] Implement rollback capability if migration fails

**Checkpoint**: Migration tests pass, 1 year data migrates in < 60s

---

## Phase 4: SessionRepository Adapter (Day 4-5)

**Purpose**: Swap SessionRepository backend without changing API

### Tests First ⚠️

- [ ] T042 [US2] Update existing `SessionRepositoryTests` to use mock storage
- [ ] T043 [US2] Add test: save dose, fetch dose - Core Data backend
- [ ] T044 [US2] Add test: save sleep event, fetch by session - Core Data
- [ ] T045 [US2] Add test: morning check-in CRUD - Core Data

### Implementation

- [ ] T046 [US1] Create `SessionRepositoryV2.swift` (parallel implementation)
- [ ] T047 [US1] Implement all existing `SessionRepository` public methods
- [ ] T048 [P] [US1] Implement `saveDose1(at:)` using Core Data
- [ ] T049 [P] [US1] Implement `saveDose2(at:)` using Core Data
- [ ] T050 [P] [US1] Implement `insertSleepEvent(_:)` using Core Data
- [ ] T051 [P] [US1] Implement `fetchTonightEvents()` using NSFetchRequest
- [ ] T052 [P] [US1] Implement `fetchRecentSessions(days:)` using NSFetchRequest
- [ ] T053 [P] [US1] Implement `saveMorningCheckIn(_:)` using Core Data
- [ ] T054 [P] [US1] Implement `savePreSleepLog(_:)` using Core Data
- [ ] T055 [US1] Add `@Published` property wrappers for SwiftUI observation
- [ ] T056 [US1] Subscribe to `NSManagedObjectContext` changes for live updates
- [ ] T057 [US1] Swap `SessionRepository.shared` to use `SessionRepositoryV2`

**Checkpoint**: All existing SessionRepository tests pass with new backend

---

## Phase 5: CloudKit Sync Enable (Day 5-6)

**Purpose**: Enable CloudKit synchronization

### Tests First ⚠️

- [ ] T058 [P] [US1] Create `Tests/CloudKitTests/SyncTests.swift`
- [ ] T059 [P] [US1] Test sync status observable
- [ ] T060 [P] [US5] Test iCloud sign-out behavior (graceful degradation)

### Implementation

- [ ] T061 [US1] Add sync status enum: `.syncing`, `.synced`, `.offline`, `.error`
- [ ] T062 [US1] Implement sync status publisher from container events
- [ ] T063 [US1] Add sync status indicator to Settings view
- [ ] T064 [US5] Handle `CKAccountStatus` changes
- [ ] T065 [US5] Show alert when iCloud storage near full
- [ ] T066 [US1] Test cross-device sync with iPhone + iPad
- [ ] T067 [US3] Verify data only in Private Database (CloudKit Console)

**Checkpoint**: Data syncs between devices within 30 seconds

---

## Phase 6: watchOS Preparation (Day 6)

**Purpose**: Prepare shared components for watchOS companion

- [ ] T068 [P] [US1] Create shared Core Data model target (Framework)
- [ ] T069 [P] [US1] Move `DoseTap.xcdatamodeld` to shared framework
- [ ] T070 [US1] Configure watchOS target to use same CloudKit container
- [ ] T071 [US1] Create minimal watchOS CloudKitStorage wrapper
- [ ] T072 [US1] Test sync between iPhone and Apple Watch

**Checkpoint**: Dose on Watch appears on iPhone

---

## Phase 7: Edge Cases & Polish (Day 7)

**Purpose**: Handle error cases and finalize

### Error Handling

- [ ] T073 [P] [US2] Handle CloudKit rate limits (exponential backoff)
- [ ] T074 [P] [US2] Handle network errors gracefully
- [ ] T075 [P] [US5] Handle iCloud storage full (alert + offline mode)
- [ ] T076 [P] [US4] Handle migration interruption (resume capability)

### Documentation

- [ ] T077 [P] [US1] Update `docs/SSOT/README.md` with CloudKit architecture
- [ ] T078 [P] [US1] Update `docs/architecture.md` with new storage layer
- [ ] T079 [P] [US1] Add CloudKit section to `docs/DATABASE_SCHEMA.md`
- [ ] T080 [US1] Update `.github/copilot-instructions.md` with CloudKit patterns

### Cleanup

- [ ] T081 [US4] Mark `EventStorage.swift` as deprecated
- [ ] T082 [US4] Add migration removal plan for future version
- [ ] T083 [US1] Performance profiling with Instruments
- [ ] T084 [US1] Final cross-device testing on real hardware

**Checkpoint**: All edge case tests pass, SSOT updated

---

## Summary

| Phase | Tasks | Parallel | Blocking |
| ----- | ----- | -------- | -------- |
| Phase 0: Setup | 5 | 2 | Phase 1 |
| Phase 1: Model | 12 | 5 | Phase 2 |
| Phase 2: Storage | 10 | 3 | Phase 3 |
| Phase 3: Migration | 14 | 6 | Phase 4 |
| Phase 4: Adapter | 16 | 8 | Phase 5 |
| Phase 5: Sync | 10 | 3 | Phase 6 |
| Phase 6: watchOS | 5 | 2 | Phase 7 |
| Phase 7: Polish | 12 | 7 | Done |
| **Total** | **84** | **36** | - |

## User Story Coverage

| Story | Tasks | Coverage |
| ----- | ----- | -------- |
| US1: Cross-Device Sync | 45 | Primary feature |
| US2: Offline-First | 12 | Preserve existing |
| US3: Privacy | 3 | Encrypted fields |
| US4: Migration | 18 | One-time |
| US5: Account Changes | 6 | Edge cases |

## Definition of Done

- [ ] All 84 tasks completed
- [ ] All existing tests pass (277+)
- [ ] New CloudKit tests pass (20+)
- [ ] Migration verified with real data
- [ ] Cross-device sync verified
- [ ] SSOT documentation updated
- [ ] No constitution violations
- [ ] Performance within targets
