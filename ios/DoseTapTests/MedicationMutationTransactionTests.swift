import Foundation
import SQLite3
import XCTest
@testable import DoseTap
import DoseCore
@preconcurrency import UserNotifications

@MainActor
private final class MedicationMutationNotificationCenter: AlarmNotificationCenterClient {
    private(set) var requestsByIdentifier: [String: UNNotificationRequest] = [:]

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {}
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }

    func add(_ request: UNNotificationRequest) async throws {
        requestsByIdentifier[request.identifier] = request
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        Array(requestsByIdentifier.values)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        for identifier in identifiers {
            requestsByIdentifier.removeValue(forKey: identifier)
        }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
}

@MainActor
final class MedicationMutationTransactionTests: XCTestCase {
    private let sessionId = "transaction-session"
    private let sessionDate = "2026-08-31"
    private let oldDose1 = Date(timeIntervalSince1970: 1_788_200_000)

    func test_databaseOpenFailure_returnsTypedFailureWithoutPublishingState() throws {
        let storage = EventStorage(
            dbPath: ":memory:",
            medicationFaultInjector: { point in
                guard point == .open else { return nil }
                return MedicationStorageInjectedFailure(
                    code: .databaseUnavailable,
                    sqliteCode: SQLITE_CANTOPEN,
                    detail: "Injected database-open failure"
                )
            }
        )

        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        let failure = try requireFailure(result, code: .databaseUnavailable, stage: .open)
        XCTAssertEqual(failure.sqliteCode, SQLITE_CANTOPEN)
        XCTAssertNil(storage.db)
        XCTAssertNil(storage.loadCurrentSessionState().dose1Time)
    }

    func test_diskFullDuringReplacement_rollsBackDeleteAndPreservesAcknowledgedDose() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let replacement = oldDose1.addingTimeInterval(600)
        storage.medicationFaultInjector = { point in
            guard point == .insert else { return nil }
            return MedicationStorageInjectedFailure(
                code: .diskFull,
                sqliteCode: SQLITE_FULL,
                detail: "Injected full disk"
            )
        }

        let result = storage.saveDose1(
            timestamp: replacement,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .diskFull, stage: .insert)
        assertOnlyAcknowledgedDose1(in: storage)
    }

    func test_corruptionAtTransactionBegin_preservesAcknowledgedDose() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        storage.medicationFaultInjector = { point in
            guard point == .begin else { return nil }
            return MedicationStorageInjectedFailure(
                code: .corrupted,
                sqliteCode: SQLITE_CORRUPT,
                detail: "Injected corruption"
            )
        }

        let result = storage.saveDose1(
            timestamp: oldDose1.addingTimeInterval(600),
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .corrupted, stage: .begin)
        assertOnlyAcknowledgedDose1(in: storage)
    }

    func test_insertFailure_leavesNoPartialEventOrSnapshot() throws {
        let storage = EventStorage.inMemory()
        storage.medicationFaultInjector = { point in
            guard point == .insert else { return nil }
            return MedicationStorageInjectedFailure(
                code: .statement,
                detail: "Injected insert failure"
            )
        }

        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .statement, stage: .insert)
        XCTAssertTrue(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).isEmpty)
        XCTAssertNil(storage.loadCurrentSessionState().dose1Time)
    }

    func test_snapshotUpdateFailure_rollsBackInsertedEvent() throws {
        let storage = EventStorage.inMemory()
        storage.medicationFaultInjector = { point in
            guard point == .update else { return nil }
            return MedicationStorageInjectedFailure(
                code: .io,
                sqliteCode: SQLITE_IOERR,
                detail: "Injected snapshot update failure"
            )
        }

        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .io, stage: .update)
        XCTAssertTrue(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).isEmpty)
        XCTAssertNil(storage.loadCurrentSessionState().dose1Time)
    }

    func test_commitFailure_rollsBackReplacementAndPreservesAcknowledgedDose() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        storage.medicationFaultInjector = { point in
            guard point == .commit else { return nil }
            return MedicationStorageInjectedFailure(
                code: .transaction,
                detail: "Injected commit failure"
            )
        }

        let result = storage.saveDose1(
            timestamp: oldDose1.addingTimeInterval(900),
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .transaction, stage: .commit)
        assertOnlyAcknowledgedDose1(in: storage)
    }

    func test_dose1ReplacementCannotDeleteCommittedDose2Outcome() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let dose2 = oldDose1.addingTimeInterval(165 * 60)
        XCTAssertTrue(storage.saveDose2(
            timestamp: dose2,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        ).isCommitted)

        let replacement = storage.saveDose1(
            timestamp: oldDose1.addingTimeInterval(300),
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(replacement, code: .precondition, stage: .preflight)
        let events = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        XCTAssertEqual(events.map(\.eventType), ["dose1", "dose2"])
        XCTAssertEqual(events.first?.timestamp, oldDose1)
        XCTAssertEqual(events.last?.timestamp, dose2)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
        XCTAssertEqual(storage.loadCurrentSessionState().dose2Time, dose2)
    }

    func test_repeatedOrdinaryDose2WriteFailsWithoutCreatingExtraDose() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let firstDose2 = oldDose1.addingTimeInterval(165 * 60)
        let repeatedDose2 = firstDose2.addingTimeInterval(1)

        XCTAssertTrue(storage.saveDose2(
            timestamp: firstDose2,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        ).isCommitted)

        let repeatedResult = storage.saveDose2(
            timestamp: repeatedDose2,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        let failure = try requireFailure(repeatedResult, code: .precondition, stage: .preflight)
        XCTAssertEqual(
            failure.detail,
            "Dose 2 is already recorded. Use the explicit extra-dose confirmation or Edit to correct it."
        )
        let events = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        XCTAssertEqual(events.filter { $0.eventType == "dose2" }.count, 1)
        XCTAssertFalse(events.contains { $0.eventType == "extra_dose" })
        XCTAssertEqual(storage.loadCurrentSessionState().dose2Time, firstDose2)
    }

    func test_rollbackFailure_isReportedAndLeavesNoAcknowledgedMutation() throws {
        let storage = EventStorage.inMemory()
        storage.medicationFaultInjector = { point in
            switch point {
            case .insert:
                return MedicationStorageInjectedFailure(
                    code: .statement,
                    detail: "Injected insert failure"
                )
            case .rollback:
                return MedicationStorageInjectedFailure(
                    code: .transaction,
                    detail: "Injected rollback verification failure"
                )
            default:
                return nil
            }
        }

        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .transaction, stage: .rollback)
        XCTAssertTrue(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).isEmpty)
        XCTAssertNil(storage.loadCurrentSessionState().dose1Time)
    }

    func test_preflightFailure_doesNotBeginMedicationWrite() throws {
        let storage = EventStorage.inMemory()
        storage.medicationFaultInjector = { point in
            guard point == .preflight else { return nil }
            return MedicationStorageInjectedFailure(
                code: .precondition,
                detail: "Injected stale-state preflight"
            )
        }

        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate
        )

        _ = try requireFailure(result, code: .precondition, stage: .preflight)
        XCTAssertTrue(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).isEmpty)
    }

    func test_repositoryPublishesOnlyAfterCommit_forDose1Dose2SnoozeAndSkip() throws {
        let storage = EventStorage.inMemory()
        let now = oldDose1.addingTimeInterval(160 * 60)
        let repository = makeRepository(storage: storage, now: now)
        let initialResult = repository.setDose1Time(oldDose1)
        XCTAssertTrue(initialResult.isCommitted)
        let acknowledgedSessionId = try XCTUnwrap(repository.activeSessionId)
        let acknowledgedSessionDate = try XCTUnwrap(repository.activeSessionDate)

        storage.medicationFaultInjector = { point in
            guard point == .insert else { return nil }
            return MedicationStorageInjectedFailure(
                code: .statement,
                detail: "Injected live-action insert failure"
            )
        }

        let replacement = repository.setDose1Time(oldDose1.addingTimeInterval(60))
        _ = try requireFailure(replacement, code: .statement, stage: .insert)
        XCTAssertEqual(repository.dose1Time, oldDose1)
        XCTAssertEqual(repository.activeSessionId, acknowledgedSessionId)
        XCTAssertEqual(repository.activeSessionDate, acknowledgedSessionDate)

        let dose2 = repository.setDose2Time(now)
        _ = try requireFailure(dose2, code: .statement, stage: .insert)
        XCTAssertNil(repository.dose2Time)

        let snooze = repository.incrementSnoozeMutationIfActive()
        _ = try requireFailure(snooze, code: .statement, stage: .insert)
        XCTAssertEqual(repository.snoozeCount, 0)

        let skip = repository.skipDose2()
        _ = try requireFailure(skip, code: .statement, stage: .insert)
        XCTAssertFalse(repository.dose2Skipped)
        XCTAssertEqual(repository.lastMedicationMutationError?.stage, .insert)

        let events = storage.fetchDoseEvents(
            sessionId: acknowledgedSessionId,
            sessionDate: acknowledgedSessionDate
        )
        XCTAssertEqual(events.map(\.eventType), ["dose1"])
        XCTAssertEqual(events.first?.timestamp, oldDose1)
    }

    func test_failedReplacement_survivesRestartAsLastAcknowledgedState() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dosetap-medication-transaction-\(UUID().uuidString).sqlite")
        let paths = [baseURL.path, baseURL.path + "-wal", baseURL.path + "-shm"]
        defer {
            for path in paths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        do {
            let storage = EventStorage(dbPath: baseURL.path)
            try seedDose1(in: storage)
            storage.medicationFaultInjector = { point in
                guard point == .commit else { return nil }
                return MedicationStorageInjectedFailure(
                    code: .transaction,
                    detail: "Injected restart-boundary commit failure"
                )
            }
            let failed = storage.saveDose1(
                timestamp: oldDose1.addingTimeInterval(1_200),
                sessionId: sessionId,
                sessionDateOverride: sessionDate
            )
            _ = try requireFailure(failed, code: .transaction, stage: .commit)
        }

        let restartedStorage = EventStorage(dbPath: baseURL.path)
        assertOnlyAcknowledgedDose1(in: restartedStorage)
        let restartedRepository = makeRepository(
            storage: restartedStorage,
            now: oldDose1.addingTimeInterval(160 * 60)
        )
        XCTAssertEqual(restartedRepository.dose1Time, oldDose1)
        XCTAssertNil(restartedRepository.dose2Time)
    }

    func test_coordinatorPersistenceFailure_returnsRetryAndTriggersNoSuccessEffects() async throws {
        let storage = EventStorage.inMemory()
        let now = oldDose1
        let repository = makeRepository(storage: storage, now: now)
        storage.medicationFaultInjector = { point in
            guard point == .insert else { return nil }
            return MedicationStorageInjectedFailure(
                code: .diskFull,
                sqliteCode: SQLITE_FULL,
                detail: "Injected full disk"
            )
        }

        let notificationCenter = MedicationMutationNotificationCenter()
        let defaultsName = "MedicationMutationTransactionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let alarm = AlarmService(
            notificationClient: notificationCenter,
            defaults: defaults,
            nowProvider: { now },
            timeZoneProvider: { TimeZone(secondsFromGMT: 0)! },
            configurationProvider: {
                AlarmConfiguration(
                    notificationsEnabled: true,
                    windowOpenAlert: true,
                    fifteenMinWarning: true,
                    fiveMinWarning: true,
                    soundEnabled: false,
                    criticalAlertsEnabled: false,
                    snoozeDurationMinutes: 10,
                    maxSnoozes: 3
                )
            }
        )
        let core = DoseTapCore()
        core.setSessionRepository(repository)
        let undo = UndoStateManager()
        let coordinator = DoseActionCoordinator(
            core: core,
            alarmService: alarm,
            dateProvider: FixedDateProvider(date: now),
            undoState: undo,
            sessionRepo: repository
        )
        let diagnosticSessionId = repository.currentSessionIdString()
        let diagnosticEventsPath = await DiagnosticLogger.shared.eventsFilePath(
            for: diagnosticSessionId
        )
        try? FileManager.default.removeItem(at: diagnosticEventsPath.deletingLastPathComponent())
        defer {
            try? FileManager.default.removeItem(
                at: diagnosticEventsPath.deletingLastPathComponent()
            )
        }
        var hapticCount = 0
        coordinator.hapticObserver = { _ in hapticCount += 1 }

        let result = await coordinator.takeDose1()

        XCTAssertEqual(
            result,
            .retryRequired(message: "The dose was not saved because device storage is full. Free space, then retry.")
        )
        XCTAssertNil(repository.dose1Time)
        XCTAssertNil(undo.currentAction)
        XCTAssertEqual(hapticCount, 0)
        XCTAssertTrue(notificationCenter.requestsByIdentifier.isEmpty)
        XCTAssertFalse(alarm.alarmScheduled)
        XCTAssertFalse(alarm.reminderScheduled)

        var actionEntries = try diagnosticActionEntries(at: diagnosticEventsPath)
        XCTAssertEqual(actionEntries.map(\.event), [.doseActionAttempted, .doseActionFailed])
        XCTAssertEqual(Set(actionEntries.compactMap(\.actionId)).count, 1)
        XCTAssertEqual(actionEntries.last?.mutationFailureCode, "disk_full")

        storage.medicationFaultInjector = nil
        let retryResult = await coordinator.takeDose1()
        XCTAssertEqual(
            retryResult,
            .attentionRequired(
                message: "Dose 1 was logged. DoseTap could not verify every required notification. Retry the alarm."
            )
        )

        actionEntries = try diagnosticActionEntries(at: diagnosticEventsPath)
        XCTAssertEqual(actionEntries.count, 4)
        XCTAssertEqual(
            actionEntries.map(\.event),
            [.doseActionAttempted, .doseActionFailed, .doseActionAttempted, .doseActionCommitted]
        )
        let actionIds = Set(actionEntries.compactMap(\.actionId))
        XCTAssertEqual(actionIds.count, 2)
        for actionId in actionIds {
            XCTAssertEqual(actionEntries.filter { $0.actionId == actionId }.count, 2)
        }
        XCTAssertEqual(hapticCount, 1)
        XCTAssertNotNil(repository.dose1Time)
        XCTAssertNotNil(undo.currentAction)
        XCTAssertTrue(notificationCenter.requestsByIdentifier.isEmpty)
    }

    func test_timeEditFailure_preservesEventSnapshotAndPublishedTime() throws {
        let storage = EventStorage.inMemory()
        let repository = makeRepository(
            storage: storage,
            now: oldDose1.addingTimeInterval(160 * 60)
        )
        XCTAssertTrue(repository.setDose1Time(oldDose1).isCommitted)
        let activeDate = try XCTUnwrap(repository.activeSessionDate)
        storage.medicationFaultInjector = { point in
            guard point == .update else { return nil }
            return MedicationStorageInjectedFailure(
                code: .io,
                sqliteCode: SQLITE_IOERR,
                detail: "Injected edit failure"
            )
        }

        let result = repository.updateDose1Time(
            newTime: oldDose1.addingTimeInterval(300),
            sessionDate: activeDate
        )

        _ = try requireFailure(result, code: .io, stage: .update)
        XCTAssertEqual(repository.dose1Time, oldDose1)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
        XCTAssertEqual(
            storage.fetchDoseEvents(sessionId: repository.activeSessionId, sessionDate: activeDate).first?.timestamp,
            oldDose1
        )
    }

    func test_morningReconciliationUpdateFailure_rollsBackEventAndPublishedState() throws {
        let storage = EventStorage.inMemory()
        let repository = makeRepository(
            storage: storage,
            now: oldDose1.addingTimeInterval(160 * 60)
        )
        XCTAssertTrue(repository.setDose1Time(oldDose1).isCommitted)
        let activeDate = try XCTUnwrap(repository.activeSessionDate)
        storage.medicationFaultInjector = { point in
            guard point == .update else { return nil }
            return MedicationStorageInjectedFailure(
                code: .io,
                sqliteCode: SQLITE_IOERR,
                detail: "Injected reconciliation snapshot failure"
            )
        }

        let result = repository.reconcileDose2(
            sessionDate: activeDate,
            takenAt: oldDose1.addingTimeInterval(160 * 60),
            amountMg: 4_500,
            reason: "missed_tap"
        )

        _ = try requireFailure(result, code: .io, stage: .update)
        XCTAssertNil(repository.dose2Time)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
        XCTAssertNil(storage.loadCurrentSessionState().dose2Time)
        XCTAssertEqual(
            storage.fetchDoseEvents(sessionId: repository.activeSessionId, sessionDate: activeDate).map(\.eventType),
            ["dose1"]
        )
    }

    func test_historicalMorningReconciliation_commitsLedgerWithoutReplacingActiveSnapshot() throws {
        let storage = EventStorage.inMemory()
        let activeRepository = makeRepository(
            storage: storage,
            now: oldDose1.addingTimeInterval(160 * 60)
        )
        XCTAssertTrue(activeRepository.setDose1Time(oldDose1).isCommitted)
        let activeSessionDate = try XCTUnwrap(activeRepository.activeSessionDate)
        let activeSessionId = try XCTUnwrap(activeRepository.activeSessionId)
        let historicalDate = "2026-08-29"
        let historicalDose1 = oldDose1.addingTimeInterval(-48 * 60 * 60)
        let historicalDose2 = historicalDose1.addingTimeInterval(165 * 60)

        let dose1Result = storage.reconcileDoseEvent(
            eventType: .dose1,
            timestamp: historicalDose1,
            sessionDate: historicalDate,
            metadata: #"{"source":"morning_reconciliation"}"#
        )
        let dose2Result = storage.reconcileDoseEvent(
            eventType: .dose2,
            timestamp: historicalDose2,
            sessionDate: historicalDate,
            metadata: #"{"amount_mg":4500}"#
        )

        XCTAssertTrue(dose1Result.isCommitted)
        XCTAssertTrue(dose2Result.isCommitted)
        XCTAssertEqual(
            storage.fetchDoseEvents(sessionId: nil, sessionDate: historicalDate).map(\.eventType),
            ["dose1", "dose2"]
        )
        let activeSnapshot = storage.loadCurrentSessionState()
        XCTAssertEqual(activeSnapshot.sessionId, activeSessionId)
        XCTAssertEqual(activeSnapshot.sessionDate, activeSessionDate)
        XCTAssertEqual(activeSnapshot.dose1Time, oldDose1)
        XCTAssertNil(activeSnapshot.dose2Time)
    }

    func test_annotationFailure_preservesPreviouslyAcknowledgedMetadata() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        let dose2 = oldDose1.addingTimeInterval(165 * 60)
        XCTAssertTrue(storage.reconcileDoseEvent(
            eventType: .dose2,
            timestamp: dose2,
            sessionDate: sessionDate,
            sessionId: sessionId,
            metadata: #"{"reason":"original"}"#
        ).isCommitted)
        let originalMetadata = storage.fetchDoseEvents(
            sessionId: sessionId,
            sessionDate: sessionDate
        ).first { $0.eventType == "dose2" }?.metadata
        storage.medicationFaultInjector = { point in
            guard point == .update else { return nil }
            return MedicationStorageInjectedFailure(
                code: .statement,
                detail: "Injected annotation failure"
            )
        }

        let result = storage.updateDose2OutcomeAnnotations(
            sessionDate: sessionDate,
            dose2Metadata: #"{"reason":"replacement"}"#,
            skippedMetadata: nil
        )

        _ = try requireFailure(result, code: .statement, stage: .update)
        let persistedMetadata = storage.fetchDoseEvents(
            sessionId: sessionId,
            sessionDate: sessionDate
        ).first { $0.eventType == "dose2" }?.metadata
        XCTAssertEqual(persistedMetadata, originalMetadata)
    }

    func test_skipCorrectionPreservesOriginalRowAndMetadata() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        XCTAssertTrue(storage.saveDoseSkipped(reason: "original reason", sessionId: sessionId, sessionDateOverride: sessionDate).isCommitted)
        let original = try XCTUnwrap(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).first { $0.eventType == "dose2_skipped" })
        XCTAssertTrue(storage.saveDose2(timestamp: oldDose1.addingTimeInterval(160 * 60), entryMode: .retrospective, recordedAt: oldDose1.addingTimeInterval(300 * 60), sessionId: sessionId, sessionDateOverride: sessionDate).isCommitted)
        let replacement = try XCTUnwrap(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate).first { $0.eventType == "dose2" })
        let metadata = try XCTUnwrap(replacement.metadata?.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: metadata) as? [String: Any])
        let correction = try XCTUnwrap(json["correction"] as? [String: Any])
        let previous = try XCTUnwrap(correction["previous_events"] as? [[String: Any]])
        XCTAssertEqual(previous.count, 1)
        XCTAssertEqual(previous.first?["id"] as? String, original.id)
        XCTAssertEqual(previous.first?["metadata"] as? String, original.metadata)
        XCTAssertNotNil(correction["corrected_at_utc"])
    }

    func test_uuidScopedReadsDoNotCombineTwoSessionsOnSameDate() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        XCTAssertTrue(storage.reconcileDoseEvent(eventType: .dose1, timestamp: oldDose1.addingTimeInterval(600), sessionDate: sessionDate, sessionId: "other-session", metadata: nil).isCommitted)
        let original = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        XCTAssertEqual(original.count, 1)
        XCTAssertEqual(original.first?.timestamp, oldDose1)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
    }

    func test_historicalCorrectionDoesNotReopenSessionOrReplaceActiveState() throws {
        let storage = EventStorage.inMemory()
        let repository = makeRepository(storage: storage, now: oldDose1.addingTimeInterval(180 * 60))
        XCTAssertTrue(repository.setDose1Time(oldDose1).isCommitted)
        let activeID = repository.activeSessionId
        let previousDate = "2026-08-29"
        let historicalFirst = oldDose1.addingTimeInterval(-48 * 3600)
        XCTAssertTrue(storage.reconcileDoseEvent(eventType: .dose1, timestamp: historicalFirst, sessionDate: previousDate, sessionId: "historical", metadata: nil).isCommitted)
        let occurrence = historicalFirst.addingTimeInterval(14430)
        let result = repository.recordHistoricalDose2Occurrence(sessionId: "historical", sessionDate: previousDate, occurrenceTime: occurrence, confirmed: true, reason: "owner_review", notes: nil)
        XCTAssertTrue(result.isCommitted)
        XCTAssertEqual(repository.activeSessionId, activeID)
        XCTAssertEqual(storage.loadCurrentSessionState().sessionId, activeID)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1)
        XCTAssertNil(repository.dose2Time)
        let recorded = try XCTUnwrap(storage.fetchDoseEvents(sessionId: "historical", sessionDate: previousDate).first { $0.eventType == "dose2" })
        XCTAssertEqual(recorded.timestamp, occurrence)
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(recorded.metadata).utf8)) as? [String: Any])
        XCTAssertEqual(metadata["is_late"] as? Bool, true)
        XCTAssertFalse(repository.recordHistoricalDose2Occurrence(sessionId: "historical", sessionDate: previousDate, occurrenceTime: occurrence, confirmed: true, reason: nil, notes: nil).isCommitted)
    }

    func test_correctionCommitFailureKeepsOriginalSkipAndItsMetadata() throws {
        let storage = EventStorage.inMemory()
        try seedDose1(in: storage)
        XCTAssertTrue(storage.saveDoseSkipped(reason: "keep me", sessionId: sessionId, sessionDateOverride: sessionDate).isCommitted)
        let before = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .io, detail: "commit failed") : nil }
        XCTAssertFalse(storage.saveDose2(timestamp: oldDose1.addingTimeInterval(160 * 60), entryMode: .retrospective, sessionId: sessionId, sessionDateOverride: sessionDate).isCommitted)
        XCTAssertEqual(storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate), before)
        XCTAssertTrue(storage.loadCurrentSessionState().dose2Skipped)
    }

    func testWorkScheduleSaveFailurePreservesPreviousPlan() throws {
        let storage = EventStorage.inMemory()
        let first = WorkWakeSchedule(timeZoneIdentifier: "America/New_York", workingWeekdays: [2, 4, 6], wakeMinutes: 420)
        XCTAssertTrue(storage.saveWorkWakeSchedule(first).isCommitted)
        var changed = first
        changed.exceptions["2026-09-04"] = WorkWakeException(isWorking: false, wakeMinutes: nil)
        storage.medicationFaultInjector = { $0 == .commit ? MedicationStorageInjectedFailure(code: .io, detail: "work schedule commit failed") : nil }
        XCTAssertFalse(storage.saveWorkWakeSchedule(changed).isCommitted)
        XCTAssertEqual(try storage.loadWorkWakeSchedule(), first)
        XCTAssertTrue(storage.fetchDoseEvents(sessionId: nil, sessionDate: sessionDate).isEmpty)
    }

    func testStaleWorkPlanEditorCannotEraseNewDatedException() throws {
        let storage = EventStorage.inMemory()
        let repository = makeRepository(storage: storage, now: oldDose1)
        XCTAssertTrue(repository.saveWorkWakeSchedule(WorkWakeSchedule(workingWeekdays: [6])).isCommitted)
        var stale = try repository.workWakeSchedule()
        var current = stale
        current.exceptions["2026-09-04"] = WorkWakeException(isWorking: false, wakeMinutes: nil)
        XCTAssertTrue(repository.saveWorkWakeSchedule(current).isCommitted)
        stale.wakeMinutes = 480
        XCTAssertFalse(repository.saveWorkWakeSchedule(stale).isCommitted)
        XCTAssertEqual(try repository.workWakeSchedule().exceptions["2026-09-04"]?.isWorking, false)
    }

    func testWorkScheduleDatedExceptionSurvivesStorageReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("schedule.sqlite").path
        var plan = WorkWakeSchedule(timeZoneIdentifier: "America/New_York", workingWeekdays: [6], target: .wakeBuffer, bufferMinutes: 120)
        plan.exceptions["2026-09-04"] = WorkWakeException(isWorking: false, wakeMinutes: 480)
        do {
            let storage = EventStorage(dbPath: path)
            XCTAssertTrue(storage.saveWorkWakeSchedule(plan).isCommitted)
        }
        let reopened = EventStorage(dbPath: path)
        XCTAssertEqual(try reopened.loadWorkWakeSchedule(), plan)
    }

    private func makeRepository(storage: EventStorage, now: Date) -> SessionRepository {
        SessionRepository(
            storage: storage,
            notificationScheduler: FakeNotificationScheduler(),
            clock: { now },
            timeZoneProvider: { TimeZone(secondsFromGMT: 0)! },
            rolloverHour: 18
        )
    }

    private func seedDose1(in storage: EventStorage) throws {
        let result = storage.saveDose1(
            timestamp: oldDose1,
            sessionId: sessionId,
            sessionDateOverride: sessionDate,
            sessionStart: oldDose1
        )
        XCTAssertTrue(result.isCommitted)
        _ = try XCTUnwrap(result.receipt)
    }

    private func assertOnlyAcknowledgedDose1(
        in storage: EventStorage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let events = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        XCTAssertEqual(events.count, 1, file: file, line: line)
        XCTAssertEqual(events.first?.eventType, "dose1", file: file, line: line)
        XCTAssertEqual(events.first?.timestamp, oldDose1, file: file, line: line)
        XCTAssertEqual(storage.loadCurrentSessionState().dose1Time, oldDose1, file: file, line: line)
        XCTAssertNil(storage.loadCurrentSessionState().dose2Time, file: file, line: line)
    }

    private func diagnosticActionEntries(at path: URL) throws -> [DiagnosticLogEntry] {
        let content = try String(contentsOf: path, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try content
            .split(separator: "\n")
            .map { try decoder.decode(DiagnosticLogEntry.self, from: Data($0.utf8)) }
            .filter {
                $0.event == .doseActionAttempted
                    || $0.event == .doseActionCommitted
                    || $0.event == .doseActionFailed
            }
    }

    @discardableResult
    private func requireFailure(
        _ result: MedicationMutationResult,
        code: MedicationMutationFailure.Code,
        stage: MedicationMutationFailure.Stage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> MedicationMutationFailure {
        let failure = try XCTUnwrap(result.failure, file: file, line: line)
        XCTAssertEqual(failure.code, code, file: file, line: line)
        XCTAssertEqual(failure.stage, stage, file: file, line: line)
        return failure
    }
}
