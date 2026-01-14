# Feature Specification: CloudKit Integration

**Feature Branch**: `002-cloudkit-sync`  
**Created**: 2026-01-10  
**Status**: Draft  
**Input**: "Add CloudKit sync for cross-device data synchronization (iOS, watchOS, macOS)"

## Overview

Integrate Apple CloudKit to enable seamless, encrypted data synchronization across all Apple devices while maintaining the offline-first architecture. User data is stored in their private iCloud account, ensuring medical data privacy and eliminating server costs.

### Goals

1. **Cross-Device Sync**: Automatically sync dose events, sleep logs, and check-ins across iOS, watchOS, and macOS
2. **Privacy-First**: All data stored in user's private iCloud database (encrypted at rest and in transit)
3. **Offline-First Preserved**: Continue working fully offline; sync when connectivity available
4. **Zero Server Cost**: User's iCloud storage handles all data (no backend infrastructure)
5. **watchOS Integration Ready**: Enable the planned watchOS companion app to share data seamlessly

### Non-Goals

- Public database or shared data between users
- Web dashboard (CloudKit JS possible but deferred)
- Custom backend API (keeping defined endpoints for future hybrid approach)
- Real-time collaboration features

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Cross-Device Sync (Priority: P1)

As a user with multiple Apple devices, I want my DoseTap data to automatically sync across my iPhone and Apple Watch so that I can take doses on either device and see the same history.

**Why this priority**: Primary value proposition of CloudKit - enables watchOS companion app and multi-device workflows essential for 3 AM medication management.

**Independent Test**: Take Dose 1 on iPhone, verify it appears on Apple Watch within 30 seconds. Log sleep event on Watch, verify it appears on iPhone.

**Acceptance Scenarios**:

1. **Given** user is signed into iCloud on iPhone and Watch, **When** user takes Dose 1 on iPhone, **Then** dose appears on Watch within 30 seconds
2. **Given** airplane mode on iPhone, **When** user logs sleep event offline, **Then** event syncs to Watch when connectivity restored
3. **Given** new iPhone setup with same iCloud account, **When** app launches, **Then** all historical data downloads automatically

---

### User Story 2 - Offline-First Continuity (Priority: P1)

As a user in poor connectivity (3 AM, basement, airplane), I want the app to work exactly as before, queuing changes until sync is possible.

**Why this priority**: Medical apps cannot fail due to network issues. Existing offline-first behavior must be preserved.

**Independent Test**: Enable airplane mode, perform full dose session (Dose 1 → Dose 2 → Morning Check-in), disable airplane mode, verify all data syncs correctly.

**Acceptance Scenarios**:

1. **Given** no network connectivity, **When** user records Dose 1, **Then** app functions normally with local persistence
2. **Given** data recorded offline, **When** connectivity restored, **Then** CloudKit sync occurs within 60 seconds
3. **Given** conflict between local and cloud data, **When** sync occurs, **Then** most recent timestamp wins (last-write-wins)

---

### User Story 3 - Privacy & Data Ownership (Priority: P1)

As a user with sensitive medical data, I want my data stored only in MY iCloud account so that neither the app developer nor Apple can access my personal health information.

**Why this priority**: XYWAV is a controlled substance; users need confidence their medication data is private.

**Independent Test**: Verify CloudKit console shows data only in Private Database, encrypted fields are not readable.

**Acceptance Scenarios**:

1. **Given** user records dose data, **When** checking CloudKit Console, **Then** data exists only in Private Database (not Public)
2. **Given** sensitive fields (notes, timestamps), **When** stored in CloudKit, **Then** fields are encrypted at rest
3. **Given** user signs out of iCloud, **When** app launches, **Then** local data remains accessible (graceful degradation)

---

### User Story 4 - Initial Setup & Migration (Priority: P2)

As an existing user with local SQLite data, I want my data automatically migrated to CloudKit-enabled storage so that I don't lose my history.

**Why this priority**: Existing users must have seamless upgrade path.

**Independent Test**: Install update on device with existing SQLite data, verify all historical sessions appear in new Core Data store and sync to CloudKit.

**Acceptance Scenarios**:

1. **Given** existing SQLite database with 30 days of history, **When** app updates to CloudKit version, **Then** all data migrates to Core Data
2. **Given** migration in progress, **When** user opens app, **Then** progress indicator shows migration status
3. **Given** migration completes, **When** CloudKit sync enabled, **Then** all historical data uploads to iCloud

---

### User Story 5 - iCloud Account Changes (Priority: P2)

As a user who switches iCloud accounts, I want the app to handle account changes gracefully without data loss.

**Why this priority**: Users change devices and accounts; must handle edge cases.

**Independent Test**: Sign out of iCloud, sign into different account, verify correct data isolation.

**Acceptance Scenarios**:

1. **Given** user signs out of iCloud, **When** app is used, **Then** local data persists and functions offline-only
2. **Given** user signs into different iCloud account, **When** app syncs, **Then** new account's data loads (not mixed)
3. **Given** user re-signs into original account, **When** app syncs, **Then** original data reappears

---

### Edge Cases

- **iCloud storage full**: Show alert, continue working offline
- **CloudKit rate limits**: Exponential backoff, queue changes
- **Schema migration mid-sync**: Pause sync during app update
- **Deleted on one device**: Soft-delete propagates (not hard delete)
- **Time zone conflicts**: Use UTC timestamps (existing pattern)
- **Very large history**: Batch sync in chunks (1000 records/batch)

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: App MUST use `NSPersistentCloudKitContainer` for Core Data + CloudKit sync
- **FR-002**: App MUST store all user data in CloudKit Private Database only
- **FR-003**: App MUST continue functioning fully offline when iCloud unavailable
- **FR-004**: App MUST migrate existing SQLite data to Core Data on first launch post-update
- **FR-005**: App MUST sync all 5 entity types: CurrentSession, DoseEvent, SleepEvent, MorningCheckIn, PreSleepLog
- **FR-006**: App MUST handle iCloud account sign-out gracefully (continue offline)
- **FR-007**: App MUST use encrypted fields for sensitive data (notes, metadata)
- **FR-008**: App MUST preserve `SessionRepository` facade (Views unchanged)
- **FR-009**: App MUST support iOS 16+, watchOS 9+, macOS 13+
- **FR-010**: App MUST use `automaticallyMergesChangesFromParent` for live UI updates

### Non-Functional Requirements

- **NFR-001**: Sync latency MUST be < 30 seconds under normal connectivity
- **NFR-002**: Migration of 1 year of data MUST complete in < 60 seconds
- **NFR-003**: App launch time MUST NOT increase by more than 500ms
- **NFR-004**: Local storage MUST NOT exceed 50MB for 1 year of data
- **NFR-005**: Battery impact of sync MUST be negligible (use system scheduling)

### Key Entities (Core Data Model)

See [Core Data Model Design](#core-data-model-design) section below.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Dose taken on iPhone appears on Watch within 30 seconds (normal connectivity)
- **SC-002**: 100% of existing SQLite data successfully migrates to Core Data
- **SC-003**: App functions identically in airplane mode (all features work)
- **SC-004**: CloudKit Console shows data only in Private Database
- **SC-005**: Zero data loss during iCloud sign-out/sign-in cycle
- **SC-006**: Memory usage increase < 10MB with CloudKit enabled
- **SC-007**: All existing tests continue to pass with new storage layer
- **SC-008**: `SessionRepository` API unchanged (Views require no modification)

---

## Core Data Model Design

### Entity Mapping: SQLite → Core Data

```
┌─────────────────────────────────────────────────────────────────┐
│                    DoseTap.xcdatamodeld                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐     ┌─────────────────────────────────┐   │
│  │ CDCurrentSession│     │        CDDoseEvent              │   │
│  │ (singleton)     │     │                                 │   │
│  ├─────────────────┤     ├─────────────────────────────────┤   │
│  │ id: Int64 = 1   │     │ id: UUID                        │   │
│  │ dose1Time: Date?│     │ eventType: String               │   │
│  │ dose2Time: Date?│     │ timestamp: Date                 │   │
│  │ snoozeCount:Int16│    │ sessionDate: String             │   │
│  │ dose2Skipped:Bool│    │ metadata: String? (JSON)        │   │
│  │ sessionDate:Str │     │ createdAt: Date                 │   │
│  │ terminalState:Str?│   └─────────────────────────────────┘   │
│  │ updatedAt: Date │                                           │
│  └─────────────────┘     ┌─────────────────────────────────┐   │
│                          │        CDSleepEvent             │   │
│  ┌─────────────────┐     ├─────────────────────────────────┤   │
│  │CDMorningCheckIn │     │ id: UUID                        │   │
│  ├─────────────────┤     │ eventType: String               │   │
│  │ id: UUID        │     │ timestamp: Date                 │   │
│  │ sessionDate: Str│     │ sessionDate: String             │   │
│  │ sessionId: Str? │     │ colorHex: String?               │   │
│  │ completedAt:Date│     │ notes: String?                  │   │
│  │ overallQuality: │     │ createdAt: Date                 │   │
│  │   Int16         │     └─────────────────────────────────┘   │
│  │ wakeCount: Int16│                                           │
│  │ feelingRested:  │     ┌─────────────────────────────────┐   │
│  │   Int16         │     │       CDPreSleepLog             │   │
│  │ sleepLatency:   │     ├─────────────────────────────────┤   │
│  │   Int16?        │     │ id: UUID                        │   │
│  │ ... (many more) │     │ sessionDate: String (UNIQUE)    │   │
│  │ sleepEnvJson:Str│     │ completedAt: Date               │   │
│  │ createdAt: Date │     │ caffeineCups: Int16?            │   │
│  └─────────────────┘     │ caffeineCutoff: Date?           │   │
│                          │ alcoholDrinks: Int16?           │   │
│                          │ exerciseType: String?           │   │
│                          │ exerciseDuration: Int16?        │   │
│                          │ stressLevel: Int16?             │   │
│                          │ notes: String?                  │   │
│                          │ createdAt: Date                 │   │
│                          └─────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Detailed Entity Definitions

#### CDCurrentSession (Singleton)
| Attribute | Type | CloudKit | Notes |
|-----------|------|----------|-------|
| id | Integer 64 | ✓ | Always 1 (constraint) |
| dose1Time | Date | ✓ | Optional |
| dose2Time | Date | ✓ | Optional |
| snoozeCount | Integer 16 | ✓ | 0-3 |
| dose2Skipped | Boolean | ✓ | Default false |
| sessionDate | String | ✓ | YYYY-MM-DD |
| terminalState | String | ✓ | Optional |
| updatedAt | Date | ✓ | Auto-updated |

#### CDDoseEvent
| Attribute | Type | CloudKit | Indexed | Notes |
|-----------|------|----------|---------|-------|
| id | UUID | ✓ | PK | |
| eventType | String | ✓ | | dose_1, dose_2, snooze, skip |
| timestamp | Date | ✓ | ✓ | When event occurred |
| sessionDate | String | ✓ | ✓ | YYYY-MM-DD grouping |
| metadata | String | ✓ Encrypted | | JSON blob |
| createdAt | Date | ✓ | | Record creation |

#### CDSleepEvent
| Attribute | Type | CloudKit | Indexed | Notes |
|-----------|------|----------|---------|-------|
| id | UUID | ✓ | PK | |
| eventType | String | ✓ | | 13 event types |
| timestamp | Date | ✓ | ✓ | |
| sessionDate | String | ✓ | ✓ | |
| colorHex | String | ✓ | | Optional UI color |
| notes | String | ✓ Encrypted | | User notes (sensitive) |
| createdAt | Date | ✓ | | |

#### CDMorningCheckIn
| Attribute | Type | CloudKit | Notes |
|-----------|------|----------|-------|
| id | UUID | ✓ | PK |
| sessionDate | String | ✓ UNIQUE | Identity constraint |
| sessionId | String | ✓ | Optional link |
| completedAt | Date | ✓ | |
| overallQuality | Integer 16 | ✓ | 1-5 |
| wakeCount | Integer 16 | ✓ | 0+ |
| feelingRested | Integer 16 | ✓ | 1-5 |
| sleepLatency | Integer 16 | ✓ | Optional, minutes |
| hasSleepTherapy | Boolean | ✓ | |
| sleepTherapyJson | String | ✓ | JSON array |
| hasSleepEnvironment | Boolean | ✓ | |
| sleepEnvironmentJson | String | ✓ | JSON object |
| physicalSymptomsJson | String | ✓ Encrypted | Sensitive |
| respiratorySymptomsJson | String | ✓ Encrypted | Sensitive |
| mentalClarity | Integer 16 | ✓ | 1-10 |
| mood | String | ✓ | Enum string |
| notes | String | ✓ Encrypted | |
| createdAt | Date | ✓ | |

#### CDPreSleepLog
| Attribute | Type | CloudKit | Notes |
|-----------|------|----------|-------|
| id | UUID | ✓ | PK |
| sessionDate | String | ✓ UNIQUE | Identity |
| completedAt | Date | ✓ | |
| caffeineCups | Integer 16 | ✓ | Optional |
| caffeineCutoff | Date | ✓ | Optional |
| alcoholDrinks | Integer 16 | ✓ | Optional |
| exerciseType | String | ✓ | none/light/moderate/intense |
| exerciseDuration | Integer 16 | ✓ | Minutes |
| stressLevel | Integer 16 | ✓ | 1-10 |
| notes | String | ✓ Encrypted | |
| createdAt | Date | ✓ | |

---

## CloudKit Configuration

### Container Setup

```
Container ID: iCloud.com.dosetap.app
Database: Private (only)
Zone: com.apple.coredata.cloudkit.zone (automatic)
```

### Encrypted Fields (Sensitive Medical Data)

The following fields MUST use CloudKit encrypted assets:
- `CDDoseEvent.metadata`
- `CDSleepEvent.notes`
- `CDMorningCheckIn.physicalSymptomsJson`
- `CDMorningCheckIn.respiratorySymptomsJson`
- `CDMorningCheckIn.notes`
- `CDPreSleepLog.notes`

---

## Migration Strategy

### Phase 1: SQLite → Core Data (Local Only)

```swift
// MigrationManager.swift
func migrateFromSQLite() async throws {
    // 1. Read all records from SQLite (EventStorage)
    let sleepEvents = EventStorage.shared.fetchAllSleepEvents()
    let doseEvents = EventStorage.shared.fetchAllDoseEvents()
    let checkIns = EventStorage.shared.fetchAllMorningCheckIns()
    // ...
    
    // 2. Insert into Core Data (batch for performance)
    let context = persistentContainer.newBackgroundContext()
    try await context.perform {
        for event in sleepEvents {
            let cdEvent = CDSleepEvent(context: context)
            cdEvent.id = event.id
            cdEvent.eventType = event.type.rawValue
            // ... map all fields
        }
        try context.save()
    }
    
    // 3. Mark migration complete
    UserDefaults.standard.set(true, forKey: "cloudkit_migration_complete")
    
    // 4. Archive SQLite file (don't delete yet)
    try FileManager.default.moveItem(
        at: sqliteURL,
        to: sqliteURL.appendingPathExtension("backup")
    )
}
```

### Phase 2: Enable CloudKit Sync

After migration verified:
1. Set `cloudKitContainerOptions` on store description
2. `NSPersistentCloudKitContainer` handles upload automatically
3. Monitor progress via `NSPersistentCloudKitContainer.eventChangedNotification`

---

## Assumptions

1. User has iCloud account signed in (graceful degradation if not)
2. User has sufficient iCloud storage (show warning if < 100MB free)
3. iOS 16+ deployment target (requirement for modern CloudKit APIs)
4. Single iCloud container shared across iOS/watchOS/macOS
5. No need for public database or sharing between users
6. Conflict resolution: last-write-wins based on `modifiedAt` timestamp
