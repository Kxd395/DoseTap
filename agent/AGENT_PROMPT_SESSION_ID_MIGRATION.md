# Agent Prompt: Session ID Migration + Duplicate Cleanup

**Date**: 2026-01-19  
**Branch**: `003-timeline-refinements`  
**Priority**: P0 (Session ID) + P1 (Duplicate cleanup)

---

## Context

Runtime verification confirmed the core fixes are working:
- ✅ No doses in `sleep_events` (dose pollution fixed)
- ✅ Event types are snake_case (normalization working)
- ✅ New dose entries are not duplicated

However, two issues remain from the audit:

### Issue 1: Session ID Split-Brain (P0)

The database has mixed session ID formats:
- **Old format**: Date strings like `2026-01-03`, `2025-12-24`
- **New format**: UUIDs like `FCF58FEA-2805-4014-B92C-9C8344C33066`

This causes:
- Timeline/History view mismatches
- Grouping failures when correlating events across tables
- Potential data loss when querying by session

### Issue 2: Legacy Duplicate Entries (P1)

Old data has duplicates with identical timestamps (within 2-5ms):
```
dose1  2026-01-04T15:32:33.473Z  2026-01-03  (duplicate)
dose1  2026-01-04T15:32:33.473Z  2026-01-03  (duplicate)

wake_final  2025-12-24T22:40:50.301Z
wake_final  2025-12-24T22:40:50.303Z
```

---

## Task 1: Normalize Session IDs to UUID Format

### Requirements

1. **Add migration function** in `EventStorage.swift` (alongside existing `normalizeEventTypes()`)
2. **Convert date-string session IDs to UUIDs** using deterministic mapping:
   - Generate a UUID v5 (or seeded UUID) from the date string so the same date always maps to the same UUID
   - This preserves grouping relationships
3. **Run migration on app launch** (once, tracked via UserDefaults flag)
4. **Update all tables**: `dose_events`, `sleep_events`, `sleep_sessions`, `current_session`

### Implementation Pattern

```swift
// In EventStorage.swift

/// Migrates legacy date-string session IDs to UUID format
/// Called once on app launch, tracked via UserDefaults
func migrateSessionIDsToUUID() {
    let migrationKey = "sessionIDMigrationCompleteV1"
    guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
    
    // 1. Find all unique date-string session IDs (format: YYYY-MM-DD)
    // 2. For each, generate deterministic UUID: UUID(uuidString: sha256(dateString).prefix(32))
    //    Or use UUID v5 with a namespace
    // 3. UPDATE all tables SET session_id = newUUID WHERE session_id = oldDateString
    // 4. Set migration flag
    
    UserDefaults.standard.set(true, forKey: migrationKey)
}
```

### Deterministic UUID Generation

Use this approach so the same date always maps to the same UUID:

```swift
import CryptoKit

func deterministicUUID(from dateString: String) -> String {
    let data = Data(dateString.utf8)
    let hash = SHA256.hash(data: data)
    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
    // Format as UUID: 8-4-4-4-12
    let uuid = "\(hashString.prefix(8))-\(hashString.dropFirst(8).prefix(4))-\(hashString.dropFirst(12).prefix(4))-\(hashString.dropFirst(16).prefix(4))-\(hashString.dropFirst(20).prefix(12))"
    return uuid.uppercased()
}

// Example:
// "2026-01-03" -> "A1B2C3D4-E5F6-7890-ABCD-EF1234567890" (deterministic)
```

### SQL Updates

```sql
-- For each legacy date-string session ID found:
UPDATE dose_events SET session_id = ? WHERE session_id = ?;
UPDATE sleep_events SET session_id = ? WHERE session_id = ?;
UPDATE sleep_sessions SET session_id = ? WHERE session_id = ?;
UPDATE current_session SET session_id = ? WHERE session_id = ?;
```

---

## Task 2: Remove Duplicate Entries

### Requirements

1. **Add deduplication function** in `EventStorage.swift`
2. **Remove duplicates** where `event_type` + `timestamp` (within 100ms) + `session_id` match
3. **Keep the first entry** (lowest rowid), delete others
4. **Run after session ID migration** (same launch, separate flag)

### Implementation Pattern

```swift
func deduplicateLegacyEntries() {
    let migrationKey = "deduplicationCompleteV1"
    guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
    
    // For each table (dose_events, sleep_events):
    // DELETE FROM dose_events 
    // WHERE rowid NOT IN (
    //   SELECT MIN(rowid) FROM dose_events 
    //   GROUP BY event_type, session_id, SUBSTR(timestamp, 1, 22)
    // )
    
    UserDefaults.standard.set(true, forKey: migrationKey)
}
```

### SQL for Deduplication

```sql
-- dose_events: Keep first entry per (event_type, session_id, timestamp truncated to 100ms)
DELETE FROM dose_events 
WHERE rowid NOT IN (
    SELECT MIN(rowid) 
    FROM dose_events 
    GROUP BY event_type, session_id, SUBSTR(timestamp, 1, 22)
);

-- sleep_events: Same logic
DELETE FROM sleep_events 
WHERE rowid NOT IN (
    SELECT MIN(rowid) 
    FROM sleep_events 
    GROUP BY event_type, session_id, SUBSTR(timestamp, 1, 22)
);
```

---

## Task 3: Update Session Creation Code

### Requirements

Ensure **all new sessions use UUID format** (verify this is already the case):

1. Check `SessionRepository.swift` — session creation should use `UUID().uuidString`
2. Check `EventStorage.swift` — any session ID generation
3. Check `ContentView.swift` — where sessions are started

If any code still generates date-string session IDs, update to use UUIDs.

---

## Files to Modify

| File | Changes |
|------|---------|
| `ios/DoseTap/Storage/EventStorage.swift` | Add `migrateSessionIDsToUUID()`, `deduplicateLegacyEntries()` |
| `ios/DoseTap/App/DoseTapApp.swift` | Call migrations on launch (after existing `normalizeEventTypes()`) |
| `ios/DoseTap/Session/SessionRepository.swift` | Verify UUID generation (likely already correct) |

---

## Testing

### Unit Tests (add to `Tests/DoseCoreTests/`)

```swift
func test_deterministicUUID_sameInputSameOutput() {
    let uuid1 = deterministicUUID(from: "2026-01-03")
    let uuid2 = deterministicUUID(from: "2026-01-03")
    XCTAssertEqual(uuid1, uuid2)
}

func test_deterministicUUID_differentInputDifferentOutput() {
    let uuid1 = deterministicUUID(from: "2026-01-03")
    let uuid2 = deterministicUUID(from: "2026-01-04")
    XCTAssertNotEqual(uuid1, uuid2)
}

func test_deterministicUUID_validFormat() {
    let uuid = deterministicUUID(from: "2026-01-03")
    XCTAssertNotNil(UUID(uuidString: uuid))
}
```

### Manual Verification

After implementation, run:

```bash
# Query to verify no date-string session IDs remain
sqlite3 "<app-container>/Documents/dosetap_events.sqlite" \
  "SELECT DISTINCT session_id FROM dose_events WHERE session_id LIKE '____-__-__';"
# Should return empty

# Query to verify no duplicates
sqlite3 "<app-container>/Documents/dosetap_events.sqlite" \
  "SELECT event_type, session_id, SUBSTR(timestamp,1,22), COUNT(*) as cnt 
   FROM dose_events GROUP BY 1,2,3 HAVING cnt > 1;"
# Should return empty
```

---

## Acceptance Criteria

- [ ] All session IDs in all tables are UUID format
- [ ] Same legacy date maps to same UUID (deterministic)
- [ ] No duplicate entries (same event_type + timestamp within 100ms + session_id)
- [ ] Migration runs once, tracked via UserDefaults flags
- [ ] Unit tests pass for UUID generation
- [ ] Manual verification queries return empty results
- [ ] `swift test -q` passes (277+ tests)
- [ ] Xcode build succeeds

---

## SSOT Update Required

After completing this work, update `docs/SSOT/README.md`:

```markdown
### Session ID Format
- All session IDs are UUIDs (e.g., `FCF58FEA-2805-4014-B92C-9C8344C33066`)
- Legacy date-string IDs (`2026-01-03`) were migrated to deterministic UUIDs in v2.0.3
- Migration is one-time, tracked via `sessionIDMigrationCompleteV1` UserDefaults key
```

---

## Commit Message

```
fix: migrate session IDs to UUID format, deduplicate legacy entries

- Add deterministicUUID() to convert date-strings to stable UUIDs
- Add migrateSessionIDsToUUID() migration (one-time)
- Add deduplicateLegacyEntries() cleanup (one-time)
- Fixes P0 session ID split-brain issue
- Fixes P1 duplicate entries issue

Closes audit items #3 (session ID) and #7 (duplicates)
```
