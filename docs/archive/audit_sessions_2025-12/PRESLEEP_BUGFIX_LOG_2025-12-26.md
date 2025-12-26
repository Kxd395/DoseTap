# Pre-Sleep Bugfix Log: DoseTap v2.10.0
**Date**: 2025-12-26

- [2025-12-26T03:38:05Z] START
- [2025-12-26T03:38:22Z] rg -n "pre.?sleep|PreSleep|sleep_log|checkin" ios -S -> see command output above
- [2025-12-26T03:38:42Z] git rev-parse HEAD -> 68e74bdccb0bdd09cbae199d2339fb5460aab8a5
- [2025-12-26T03:39:04Z] git status --short -> working tree dirty (see output)
- [2025-12-26T03:39:36Z] bash tools/ssot_check.sh ; echo 0 -> exit 0
- [2025-12-26T03:39:53Z] bash tools/doc_lint.sh ; echo 0 -> exit 0
- [2025-12-26T03:40:18Z] swift test --verbose -> exit 0 (268 tests)
- [2025-12-26T03:40:40Z] TZ=UTC swift test --verbose -> exit 0 (268 tests)
- [2025-12-26T03:41:05Z] TZ=America/New_York swift test --verbose -> exit 0 (268 tests)
- [2025-12-26T03:42:30Z] xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 15' CODE_SIGNING_ALLOWED=NO -> exit 70 (device not found)
- [2025-12-26T03:44:47Z] xcodebuild test -project ios/DoseTap.xcodeproj -scheme DoseTap -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.2' CODE_SIGNING_ALLOWED=NO -> exit 0 (TEST SUCCEEDED)
- [2025-12-26T03:47:26Z] output excerpt: "Test Suite 'All tests' passed ... Executed 268 tests, with 0 failures" (swift test)
- [2025-12-26T03:47:26Z] output excerpt: "SessionRepositoryTests.test_addPreSleepLog_persistsRowAndIsQueryableBySessionKey()' passed" (xcodebuild)
- [2025-12-26T03:47:26Z] output excerpt: "SessionRepositoryTests.test_preSleepSubmit_broadcastsChangeSignal()' passed" (xcodebuild)
- [2025-12-26T03:47:26Z] files reviewed: ios/DoseTap/Views/PreSleepLogView.swift, ios/DoseTap/ContentView.swift, ios/DoseTap/Storage/EventStorage.swift, ios/DoseTap/Storage/SessionRepository.swift, ios/Core/SessionKey.swift, ios/DoseTapTests/SessionRepositoryTests.swift
