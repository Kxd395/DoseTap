//
//  TestHelpers.swift
//  DoseTapTests
//
//  Shared test helpers and fakes for DoseTapTests.
//

import XCTest
@testable import DoseTap

// MARK: - Fake Notification Scheduler (conforms to production protocol)

/// Fake notification scheduler for testing - captures all cancellation calls
/// Conforms to the production NotificationScheduling protocol from SessionRepository
final class FakeNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private(set) var cancelledIdentifiers: [String] = []
    private let lock = NSLock()
    
    func cancelNotifications(withIdentifiers ids: [String]) {
        lock.lock()
        defer { lock.unlock() }
        cancelledIdentifiers.append(contentsOf: ids)
    }
    
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        cancelledIdentifiers.removeAll()
    }
}
