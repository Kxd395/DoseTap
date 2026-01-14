# Implementation Plan: CloudKit Integration

**Branch**: `002-cloudkit-sync` | **Date**: 2026-01-10 | **Spec**: [spec.md](./spec.md)

## Summary

Migrate DoseTap from raw SQLite (`EventStorage.swift`) to Core Data with CloudKit sync (`NSPersistentCloudKitContainer`). This enables cross-device synchronization while preserving the offline-first architecture and existing `SessionRepository` facade.

## Technical Context

**Language/Version**: Swift 5.9+  
**Primary Dependencies**: CoreData, CloudKit (Apple frameworks)  
**Storage**: SQLite (via Core Data) + CloudKit Private Database  
**Testing**: XCTest, CloudKit Console for sync verification  
**Target Platforms**: iOS 16+, watchOS 9+, macOS 13+  
**Project Type**: Mobile (iOS/watchOS)  
**Performance Goals**: Sync < 30s, Migration < 60s, Launch +500ms max  
**Constraints**: Offline-first preserved, existing API unchanged  
**Scale**: ~1000 records/year, 5 entity types

## Constitution Check

*GATE: Must pass all principles. CloudKit aligns with constitution.*

| Principle | Status | How CloudKit Complies |
| --------- | ------ | --------------------- |
| I. SSOT-First | ✅ | Update SSOT with CloudKit architecture |
| II. Test-First | ✅ | Write tests for migration, sync, offline |
| III. Platform-Free Core | ✅ | Core Data model separate from UI |
| IV. Storage Boundary | ✅ | SessionRepository facade preserved |
| V. Deterministic Time | ✅ | UTC timestamps preserved |
| VI. Offline-First | ✅ | `NSPersistentCloudKitContainer` works offline |
| VII. XYWAV-Only | ✅ | No scope change |

## Project Structure

### New Files to Create

```
ios/DoseTap/
├── Storage/
│   ├── CloudKitStorage.swift       # NSPersistentCloudKitContainer setup
│   ├── MigrationManager.swift      # SQLite → Core Data migration
│   └── SessionRepository.swift     # UPDATED (switch to Core Data)
├── Models/
│   └── DoseTap.xcdatamodeld/       # Core Data model
│       └── DoseTap.xcdatamodel/
│           └── contents            # Entity definitions
└── Entitlements/
    └── DoseTap.entitlements        # iCloud capability

Tests/
└── CloudKitTests/
    ├── MigrationTests.swift        # SQLite → Core Data tests
    ├── SyncTests.swift             # CloudKit sync behavior
    └── OfflineTests.swift          # Offline-first preservation
```

### Files to Modify

```
ios/DoseTap/
├── DoseTapApp.swift                # Initialize CloudKit container
├── Storage/
│   ├── SessionRepository.swift     # Switch backend to Core Data
│   └── EventStorage.swift          # Mark deprecated, keep for migration
├── Info.plist                      # Background modes for sync
└── DoseTap.xcodeproj/
    └── project.pbxproj             # Add iCloud capability
```

### Files Deprecated (Keep for Migration)

```
ios/DoseTap/Storage/
└── EventStorage.swift              # Read-only for migration, then archive
```

## Architecture

### Current Architecture (SQLite)

```
Views → SessionRepository → EventStorage → SQLite
                                ↓
                         dosetap_events.sqlite
```

### Target Architecture (CloudKit)

```
Views → SessionRepository → CloudKitStorage → NSPersistentCloudKitContainer
                                    ↓                    ↓
                              Local SQLite ←──sync──→ CloudKit
                              (Core Data)           Private DB
```

### Migration Path

```
┌─────────────────────────────────────────────────────────────────┐
│                    MIGRATION FLOW                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐ │
│  │ Old SQLite  │───▶│ Migration   │───▶│ Core Data (Local)   │ │
│  │ EventStorage│    │ Manager     │    │ CloudKitStorage     │ │
│  └─────────────┘    └─────────────┘    └─────────────────────┘ │
│                                                  │              │
│                                                  ▼              │
│                                         ┌─────────────────────┐ │
│                                         │ CloudKit Private DB │ │
│                                         │ (Automatic Sync)    │ │
│                                         └─────────────────────┘ │
│                                                  │              │
│                                                  ▼              │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │  Other Devices (iPhone, Watch, Mac)                         ││
│  │  Same iCloud account = same data                            ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## Phases

### Phase 0: Setup & Entitlements (Day 1)

**Objective**: Configure Xcode project for CloudKit

**Deliverables**:
- [ ] Add iCloud capability with CloudKit to DoseTap target
- [ ] Create CloudKit container `iCloud.com.dosetap.app`
- [ ] Add Background Modes for remote notifications
- [ ] Update entitlements file

**Verification**: CloudKit Console shows new container

---

### Phase 1: Core Data Model (Day 1-2)

**Objective**: Create `.xcdatamodeld` matching SQLite schema

**Deliverables**:
- [ ] Create `DoseTap.xcdatamodeld` with all 5 entities
- [ ] Configure CloudKit-compatible attributes
- [ ] Mark sensitive fields for encryption
- [ ] Add indexes matching SQLite indexes
- [ ] Create `CloudKitStorage.swift` with `NSPersistentCloudKitContainer`

**Verification**: Model compiles, container initializes without CloudKit (local only first)

---

### Phase 2: Migration Manager (Day 2-3)

**Objective**: Migrate existing SQLite data to Core Data

**Deliverables**:
- [ ] Create `MigrationManager.swift`
- [ ] Implement batch read from `EventStorage`
- [ ] Implement batch insert to Core Data
- [ ] Add progress callback for UI
- [ ] Archive old SQLite file (don't delete)
- [ ] Write migration tests

**Verification**: 30 days of test data migrates in < 60 seconds

---

### Phase 3: SessionRepository Adapter (Day 3-4)

**Objective**: Swap SessionRepository backend from EventStorage to CloudKitStorage

**Deliverables**:
- [ ] Create Core Data fetch requests matching existing queries
- [ ] Update `SessionRepository` to use `NSManagedObjectContext`
- [ ] Preserve all existing public API methods
- [ ] Add `@Published` bindings for SwiftUI observation
- [ ] Implement `automaticallyMergesChangesFromParent` for sync updates

**Verification**: All existing tests pass with new backend

---

### Phase 4: CloudKit Sync Enable (Day 4-5)

**Objective**: Enable CloudKit synchronization

**Deliverables**:
- [ ] Set `cloudKitContainerOptions` on store description
- [ ] Handle `NSPersistentCloudKitContainer` events
- [ ] Implement sync status indicator
- [ ] Handle iCloud sign-out gracefully
- [ ] Test cross-device sync

**Verification**: Data syncs between iPhone and iPad within 30 seconds

---

### Phase 5: watchOS Integration Prep (Day 5-6)

**Objective**: Prepare for watchOS companion app

**Deliverables**:
- [ ] Share Core Data model with watchOS target
- [ ] Configure same CloudKit container for Watch
- [ ] Test sync between iPhone and Watch
- [ ] Document watchOS architecture

**Verification**: Dose logged on Watch appears on iPhone

---

### Phase 6: Edge Cases & Polish (Day 6-7)

**Objective**: Handle error cases and polish

**Deliverables**:
- [ ] iCloud storage full handling
- [ ] Rate limit / throttle handling
- [ ] Conflict resolution verification
- [ ] Migration rollback capability
- [ ] Update SSOT documentation
- [ ] Performance profiling

**Verification**: All edge case tests pass

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Migration data loss | Low | Critical | Archive SQLite, verify counts match |
| Sync conflicts | Medium | Medium | Last-write-wins with `modifiedAt` |
| CloudKit quota limits | Low | Low | Only private DB, user's quota |
| Test device setup | Medium | Low | Use simulator groups |
| Schema migration later | Medium | Medium | Plan lightweight migrations |

## Complexity Tracking

No constitution violations. CloudKit is additive and preserves all existing principles.

| Addition | Justification |
| -------- | ------------- |
| Core Data layer | Apple-native sync solution, replaces raw SQLite |
| CloudKit sync | Enables cross-device, user-owned data |
| Migration code | One-time, can be removed after transition period |

## Dependencies

### Apple Frameworks (Built-in)
- `CoreData` - Local persistence with managed objects
- `CloudKit` - iCloud sync infrastructure
- `Combine` - Reactive updates from Core Data

### No External Dependencies
CloudKit requires only Apple frameworks - no third-party SDKs needed.

## Testing Strategy

### Unit Tests
- `MigrationTests.swift` - SQLite → Core Data data integrity
- `CloudKitStorageTests.swift` - CRUD operations
- `OfflineTests.swift` - Airplane mode behavior

### Integration Tests
- Cross-device sync (requires 2+ devices or simulators)
- iCloud sign-out/sign-in cycle
- Migration with real user data

### Manual Testing
- CloudKit Console verification
- Real Watch testing (simulator limited)
- Network condition simulation

## Metrics

| Metric | Target | Measurement |
| ------ | ------ | ----------- |
| Migration time (1 year data) | < 60s | Timed test |
| Sync latency (normal network) | < 30s | Manual test |
| App launch delta | < 500ms | Instruments |
| Memory increase | < 10MB | Instruments |
| Existing test pass rate | 100% | CI |
