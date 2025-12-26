# UI Redesign Brief

**Branch:** `feature/ui-redesign`  
**Created:** 2025-12-26  
**Base:** `main` (v2.12.0 - Storage Unification Complete)

---

## Starting Point

### Current State (v2.12.0)
- ✅ **Storage:** Unified architecture (EventStorage → SQLite)
- ✅ **Build:** 275 unit tests passing, Xcode build succeeds
- ✅ **Core Logic:** Platform-free DoseCore module
- ✅ **CI/CD:** Automated builds + storage guards
- ✅ **Documentation:** SSOT v2.12.0 published

### Architecture Overview
```
UI Views
    ↓
SessionRepository (Facade)
    ↓
EventStorage
    ↓
SQLite (dosetap_events.sqlite)
```

---

## UI Components to Redesign

### 1. Tonight View (`ios/DoseTap/ContentView.swift`)
**Current:** Basic dose timer with manual state management  
**Files:** ContentView.swift, ContentView_Clean.swift, ContentView_Enhanced.swift

**Key Functionality:**
- Dose 1 & 2 logging
- Window phase display (beforeWindow → active → nearClose → closed)
- Snooze/Skip controls
- Quick log panel (12 event types)

### 2. Timeline View (`ios/DoseTapiOSApp/TimelineView.swift`)
**Current:** Event timeline with date picker  
**Features:**
- Sleep events visualization
- Date navigation
- Event editing/deletion

### 3. Settings View (`ios/DoseTap/SettingsView.swift`)
**Current:** Basic settings list  
**Features:**
- Target interval picker (165-225min)
- Max snoozes (1-5)
- WHOOP integration toggle
- Data export

### 4. Dashboard View (`ios/DoseTapiOSApp/DashboardView.swift`)
**Current:** Session summary cards  
**Features:**
- Recent sessions list
- Completion statistics
- Insights charts

### 5. Morning Check-In (`ios/DoseTap/Views/MorningCheckInView.swift`)
**Current:** Multi-step questionnaire  
**Features:**
- Sleep quality (1-5 stars)
- Sleep environment factors
- Medication tracking
- Notes

---

## SSOT Component IDs (Pending Implementation)

These component IDs are documented in SSOT but not yet bound to UI:

| Component ID | Intended Purpose | Priority |
|--------------|------------------|----------|
| `tonight_snooze_button` | Snooze Dose 2 reminder | P1 |
| `wake_up_button` | Log wake_final event | P1 |
| `watch_dose_button` | watchOS companion dose button | P2 |
| `timeline_list` | Event timeline scroll view | P1 |
| `timeline_export_button` | Export timeline data | P2 |
| `session_list` | Dashboard session list | P1 |
| `settings_target_picker` | Target interval selector | P1 |
| `insights_chart` | Analytics visualization | P2 |
| `heart_rate_chart` | WHOOP HR overlay | P3 |
| `date_picker` | Timeline date selector | P1 |
| `bulk_delete_button` | Multi-select deletion | P3 |
| `delete_day_button` | Delete entire session | P3 |
| `devices_add_button` | WHOOP device pairing | P3 |
| `devices_list` | Connected devices list | P3 |
| `devices_test_button` | Test device connection | P3 |

---

## Design Constraints

### 1. SSOT Compliance
All UI behavior must match `docs/SSOT/README.md`:
- Window timing: 150-240 minutes
- Snooze duration: 10 minutes
- Max snoozes: 3 (default, configurable 1-5)
- Undo window: 5 seconds
- Event cooldowns: 60s for physical events (bathroom, water, snack)

### 2. Storage Rules
**NEVER** call `EventStorage.shared` directly from views:
```swift
// ❌ WRONG
EventStorage.shared.insertSleepEvent(...)

// ✅ CORRECT
SessionRepository.shared.insertSleepEvent(...)
```

### 3. Accessibility
- VoiceOver labels for all interactive elements
- Dynamic Type support
- Reduced Motion support (via `UserSettingsManager.shouldReduceMotion`)
- High Contrast mode support

### 4. Platform Support
- iOS 16+
- watchOS 9+ (companion app)
- iPad support (adaptive layouts)

---

## Recommended Approach

### Phase 1: Component ID Binding (P1)
1. Add accessibility identifiers to existing components
2. Update SSOT compliance tests
3. Verify with `tools/ssot_check.sh`

### Phase 2: Tonight View Redesign (P1)
1. Consolidate ContentView variants (Clean/Enhanced)
2. Improve phase transition animations
3. Add visual window progress indicator
4. Polish Quick Log Panel UX

### Phase 3: Timeline Improvements (P1)
1. Add event grouping by session
2. Improve date picker UX
3. Add event filtering
4. Optimize scroll performance

### Phase 4: Settings & Dashboard (P2)
1. Reorganize settings into categories
2. Add inline help text
3. Improve analytics visualizations
4. Add export history

### Phase 5: Polish & Testing (P2)
1. Add UI snapshot tests
2. Test on various screen sizes
3. VoiceOver audit
4. Performance profiling

---

## Resources

### Documentation
- **SSOT:** `docs/SSOT/README.md`
- **Architecture:** `docs/architecture.md`
- **API Contracts:** `docs/SSOT/contracts/api.openapi.yaml`
- **Audit Reports:** `docs/ADVERSARIAL_AUDIT_REPORT_2025-12-26.md`

### Code References
- **Core Logic:** `ios/Core/DoseWindowState.swift`
- **Storage Facade:** `ios/DoseTap/Storage/SessionRepository.swift`
- **Event Types:** `ios/Core/SleepEvent.swift`
- **Settings:** `ios/DoseTap/UserSettingsManager.swift`

### Testing
- Run tests: `swift test`
- Build app: `xcodebuild build -project ios/DoseTap.xcodeproj -scheme DoseTap`
- SSOT check: `bash tools/ssot_check.sh`

---

## Branch Management

### Current Branch
```bash
git branch
# * feature/ui-redesign
```

### Merge Strategy
When UI redesign is complete:
1. Ensure all tests pass (`swift test`)
2. Verify SSOT check passes
3. Create PR: `feature/ui-redesign → main`
4. Squash commits on merge

### Commit Convention
```
feat(ui): Add component accessibility IDs
fix(ui): Correct timeline scroll performance
refactor(ui): Consolidate ContentView variants
docs(ui): Update component ID mapping
test(ui): Add snapshot tests for Dashboard
```

---

## Success Criteria

✅ All 15 SSOT component IDs bound to real UI elements  
✅ VoiceOver audit passes  
✅ No direct `EventStorage.shared` references in views  
✅ SSOT check script passes  
✅ Build succeeds on iOS Simulator  
✅ UI matches design mockups (if any)  
✅ Performance: <16ms frame time on timeline scroll  

---

*Ready to begin UI redesign work on branch `feature/ui-redesign`*
