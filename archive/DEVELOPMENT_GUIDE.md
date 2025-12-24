# Local Development Guide

This guide helps you get DoseTap running locally for development and testing.

## Quick Start

1. **Build and Test**:
   ```bash
   cd /Users/VScode_Projects/projects/DoseTap
   swift build --quiet
   swift test --quiet  # Should show 33 tests passing
   ```

2. **Open iOS App**:
   ```bash
   open ios/DoseTap.xcodeproj
   ```

3. **Run on Simulator**: Select iOS Simulator and build/run

## Development Configuration

The app includes special development mode when `Config-Development.plist` settings are active:

### Features Enabled in Development Mode

- ✅ **LOCAL_ONLY**: Skip server authentication and external integrations
- ✅ **MOCK_API_RESPONSES**: Use mock API responses instead of network calls  
- ✅ **AUTO_POPULATE_TEST_DATA**: Automatically create sample dose data
- ✅ **ENABLE_DEBUG_LOGGING**: Show detailed logging for debugging
- ✅ **Core Data Fallback**: App continues running even if storage fails

### Using the Development Helper

Import in any Swift file:
```swift
#if DEBUG
// Available everywhere when DEBUG is enabled
DevelopmentHelper.debugLog("Starting dose window calculation")

// Mock data for testing UI
let mockContext = DevelopmentHelper.mockActiveWindow()

// Simulate user actions
DevelopmentHelper.simulateDose1()
DevelopmentHelper.simulateDose2()
#endif
```

## Core Functionality Testing

### 1. Dose Window Logic (21 Tests)

Test the core medical timing logic:
```bash
swift test --filter DoseWindowStateTests
swift test --filter DoseWindowEdgeTests
```

**Key scenarios tested**:
- ✅ 150-240 minute window enforcement
- ✅ Snooze disabled when <15 minutes remain  
- ✅ DST transitions and timezone handling
- ✅ Maximum 3 snoozes per session

### 2. API Layer (12 Tests)

Test network layer and error handling:
```bash
swift test --filter APIClientTests
swift test --filter APIErrorsTests
```

**Coverage includes**:
- ✅ All endpoints: take, skip, snooze, logEvent, export
- ✅ All error codes: 401, 409, 422 variants, 429
- ✅ Network failure handling and offline support

### 3. Offline Resilience (4 Tests)

Test offline queue and retry logic:
```bash
swift test --filter OfflineQueueTests
swift test --filter EventRateLimiterTests
```

## File Structure

```
ios/DoseTap/
├── Config-Development.plist          # Development settings
├── Foundation/
│   └── DevelopmentHelper.swift       # Debug tools and mock data
├── Persistence/
│   └── PersistentStore.swift         # Core Data with crash protection
└── DoseTap.xcdatamodeld/            # CloudKit disabled for local dev

ios/Core/                            # SwiftPM module (platform-free)
├── DoseWindowState.swift            # Core dose timing logic
├── APIClient.swift                  # Network layer
├── OfflineQueue.swift               # Resilience
└── EventRateLimiter.swift           # Rate limiting

Tests/DoseCoreTests/                 # 33 passing tests
├── DoseWindowStateTests.swift       # Core logic validation
├── APIClientTests.swift             # Network layer
└── OfflineQueueTests.swift          # Resilience
```

## Development Workflow

### Daily Setup
```bash
# 1. Verify build
swift build --quiet

# 2. Run tests  
swift test --quiet

# 3. Open app
open ios/DoseTap.xcodeproj
```

### Testing Key Scenarios

**Dose Window Flow**:
1. Use `DevelopmentHelper.simulateDose1()` to start session
2. Check UI shows active window (150-240 min after dose 1)
3. Test snooze functionality (max 3 times)
4. Verify window closes at 240 minutes

**Offline Functionality**:
1. Disconnect network in simulator
2. Take/skip/snooze doses
3. Verify actions queue for later sync
4. Reconnect and verify sync occurs

**Error Handling**:
1. Mock various API errors (401, 422, etc.)
2. Verify user-friendly error messages
3. Test retry and recovery flows

## Mock Data Available

```swift
// Different window states for UI testing
DevelopmentHelper.mockDoseWindow()      // Before window (< 150 min)
DevelopmentHelper.mockActiveWindow()    // Active window (150-225 min)  
DevelopmentHelper.mockNearCloseWindow() // Near close (225-240 min)

// Simulate user actions
DevelopmentHelper.simulateDose1()       // Start new session
DevelopmentHelper.simulateDose2()       // Complete session
DevelopmentHelper.resetAllData()        // Clear all test data
```

## Troubleshooting

### Build Issues
- **"No such module DoseCore"**: Run `swift build` from repo root first
- **iOS version errors**: Ensure Xcode project targets iOS 16+
- **Missing files**: Check Package.swift includes all source files

### Core Data Issues  
- **App crashes on launch**: Check that CloudKit is disabled (`usedWithCloudKit="NO"`)
- **Test data not appearing**: Verify `AUTO_POPULATE_TEST_DATA=true` in development config
- **Storage failures**: App automatically falls back to in-memory storage

### Test Failures
- **"Expected 33 tests"**: Run `swift test --quiet` from repo root
- **API tests failing**: Check availability annotations on iOS 15+
- **Window logic errors**: Verify time injection in tests matches SSOT

## Production Notes

When deploying to production:
1. Remove or disable `Config-Development.plist`
2. Re-enable CloudKit if needed (`usedWithCloudKit="YES"`)
3. Replace mock credentials with real API keys
4. Enable Critical Alerts entitlement (requires Apple approval)

For production fixes, see `CODEBASE_AUDIT_REPORT.md`.
