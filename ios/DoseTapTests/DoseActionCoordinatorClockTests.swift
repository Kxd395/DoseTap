import Foundation
import XCTest
@testable import DoseTap
import DoseCore

private final class MutableDateProvider: DateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var currentDate: Date
    private var readCountValue = 0

    init(_ date: Date) {
        currentDate = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        readCountValue += 1
        return currentDate
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        currentDate = currentDate.addingTimeInterval(interval)
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return readCountValue
    }
}

@MainActor
final class DoseActionCoordinatorClockTests: XCTestCase {
    func testHistorySaveInvalidatesPendingDoseConsentAndCommitsOnlyReviewedTime() async throws {
        dateProvider.advance(by: 30)
        guard case .needsConfirm(.dose2Record(let token)) = await coordinator.takeDose2() else {
            return XCTFail("Expected ordinary confirmation")
        }
        let review = try repository.historySnapshot(sessionDate: repository.activeSessionDate!)
        let occurrence = dose1Time.addingTimeInterval(100 * 60)
        let result = await coordinator.saveHistoryDoseChange(
            HistoryDoseChange(eventType: "dose2", timestamp: occurrence, reason: "Entered afterward"),
            review: review, confirmed: true, warningConfirmed: true)
        guard case .success = result else { return XCTFail("Expected saved history: \(result)") }
        XCTAssertEqual(repository.dose2Time, occurrence)
        guard case .blocked = await coordinator.confirmDose2(token) else { return XCTFail("Old consent must be invalid") }
        XCTAssertEqual(repository.dose2Time, occurrence)
        XCTAssertFalse(storage.fetchDoseEvents(sessionId: review.sessionId, sessionDate: review.sessionDate).contains { $0.eventType == "extra_dose" })
    }
    private let dose1Time = Date(timeIntervalSince1970: 1_800_000_000)
    private var storage: EventStorage!
    private var repository: SessionRepository!
    private var core: DoseTapCore!
    private var dateProvider: MutableDateProvider!
    private var coordinator: DoseActionCoordinator!
    private var previousSoundEnabled = true
    private var previousSchedule: (prep: Int, wake: Int, cutoff: Int)!

    override func setUp() async throws {
        let settings = UserSettingsManager.shared
        previousSchedule = (settings.prepTimeMinutes, settings.wakeTimeMinutes, settings.missedCheckInCutoffHours)
        settings.prepTimeMinutes = 18 * 60
        settings.wakeTimeMinutes = 7 * 60
        settings.missedCheckInCutoffHours = 4
        let beforeWindow = dose1Time.addingTimeInterval(150 * 60 - 30)
        let repositoryNow = beforeWindow

        storage = EventStorage.inMemory()
        repository = SessionRepository(
            storage: storage,
            notificationScheduler: FakeNotificationScheduler(),
            clock: { repositoryNow },
            timeZoneProvider: { TimeZone(secondsFromGMT: 0)! }
        )
        repository.setDose1Time(dose1Time)

        core = DoseTapCore()
        core.setSessionRepository(repository)
        dateProvider = MutableDateProvider(beforeWindow)
        coordinator = DoseActionCoordinator(
            core: core,
            alarmService: .shared,
            dateProvider: dateProvider,
            sessionRepo: repository
        )

        previousSoundEnabled = UserSettingsManager.shared.soundEnabled
        UserSettingsManager.shared.soundEnabled = false
        AlarmService.shared.cancelAllAlarms()
        AlarmService.shared.clearDose2AlarmState()
    }

    override func tearDown() async throws {
        UserSettingsManager.shared.soundEnabled = previousSoundEnabled
        AlarmService.shared.cancelAllAlarms()
        AlarmService.shared.clearDose2AlarmState()
        repository?.clearTonight()
        let settings = UserSettingsManager.shared
        settings.prepTimeMinutes = previousSchedule.prep
        settings.wakeTimeMinutes = previousSchedule.wake
        settings.missedCheckInCutoffHours = previousSchedule.cutoff
        coordinator = nil
        core = nil
        repository = nil
        storage = nil
        dateProvider = nil
    }

    func testAdvancingClock_reclassifiesBoundaryAndPersistsOneCapturedInstant() async {
        let earlyResult = await coordinator.takeDose2()

        XCTAssertEqual(earlyResult, .needsConfirm(.earlyDose(minutesRemaining: 1)))
        XCTAssertNil(repository.dose2Time)
        XCTAssertEqual(dateProvider.readCount, 1, "One action must capture the clock exactly once")

        dateProvider.advance(by: 30)
        let windowOpen = dose1Time.addingTimeInterval(150 * 60)
        let allowedResult = await requestAndConfirmDose2()

        XCTAssertEqual(allowedResult, .success(message: "✓ Dose 2 logged"))
        XCTAssertEqual(repository.dose2Time, windowOpen)
        XCTAssertEqual(dateProvider.readCount, 3, "Request and confirmation each use one fresh clock snapshot")
    }

    func testUnconfirmedDose2ActionsNeverPersistAcrossEntrySurfaces() async {
        dateProvider.advance(by: 30)
        for surface: RegistrationSurface in [.tonightButton, .sessionDetail, .deepLink, .flic, .historyButton, .notificationAction] {
            let result = await coordinator.takeDose2(surface: surface)
            guard case .needsConfirm = result else {
                XCTFail("An initial \(surface.rawValue) request must require confirmation: \(result)")
                continue
            }
            XCTAssertNil(repository.dose2Time, "Opening confirmation must not record a dose")
        }
        XCTAssertNil(storage.loadCurrentSessionState().dose2Time)
        let events = storage.fetchDoseEvents(sessionId: repository.activeSessionId, sessionDate: repository.activeSessionDate!)
        XCTAssertFalse(events.contains { $0.eventType == "dose2" || $0.eventType == "extra_dose" })
    }

    func testEarlyOverrideRetainsItsExistingExplicitHoldConfirmation() async {
        let initial = await coordinator.takeDose2()
        XCTAssertEqual(initial, .needsConfirm(.earlyDose(minutesRemaining: 1)))
        XCTAssertNil(repository.dose2Time)
        // The existing warning + three-second hold has already collected
        // explicit consent; it must not end in an unhandled new prompt.
        let confirmed = await coordinator.takeDose2(override: .earlyConfirmed)
        XCTAssertEqual(confirmed, .success(message: "✓ Dose 2 (Early) logged"))
        XCTAssertNotNil(repository.dose2Time)
    }

    func testRepositoryNilDose2DoesNotFallBackToAnotherCoreProjection() async {
        let otherStorage = EventStorage.inMemory()
        let otherRepository = SessionRepository(storage: otherStorage, notificationScheduler: FakeNotificationScheduler(), clock: { self.dose1Time.addingTimeInterval(160 * 60) }, timeZoneProvider: { TimeZone(secondsFromGMT: 0)! })
        XCTAssertTrue(otherRepository.setDose1Time(dose1Time).isCommitted)
        XCTAssertTrue(otherRepository.setDose2Time(dose1Time.addingTimeInterval(155 * 60)).isCommitted)
        core.setSessionRepository(otherRepository)
        dateProvider.advance(by: 30)
        let result = await requestAndConfirmDose2()
        XCTAssertEqual(result, .success(message: "✓ Dose 2 logged"))
        XCTAssertNotNil(repository.dose2Time)
        XCTAssertEqual(storage.fetchDoseEvents(sessionId: repository.activeSessionId, sessionDate: repository.activeSessionDate!).filter { $0.eventType == "dose2" }.count, 1)
    }

    func testWorkWarningAcknowledgementAndDatedExceptionAreSeparateMutations() async throws {
        let previousTarget = UserSettingsManager.shared.targetIntervalMinutes
        UserSettingsManager.shared.targetIntervalMinutes = 165
        defer { UserSettingsManager.shared.targetIntervalMinutes = previousTarget }
        let plan = WorkWakeSchedule(timeZoneIdentifier: "UTC", workingWeekdays: Set(1...7), wakeMinutes: 420, target: .doseTarget)
        XCTAssertTrue(repository.saveWorkWakeSchedule(plan).isCommitted)
        dateProvider.advance(by: 30 * 60)
        let response = await coordinator.takeDose2()
        guard case .needsConfirm(.workWake(let warning)) = response else { return XCTFail("Expected work warning: \(response)") }
        XCTAssertNil(repository.dose2Time)
        let persisted = try repository.workWakeSchedule()
        XCTAssertTrue(repository.changeWorkWakeDate(warning, isWorking: false).isCommitted)
        XCTAssertNil(repository.dose2Time, "A dated schedule change is not a medication event")
        XCTAssertEqual(try repository.workWakeSchedule().workingWeekdays, persisted.workingWeekdays)
        XCTAssertEqual(try repository.workWakeSchedule().exceptions[warning.wakeDate]?.isWorking, false)
        let recorded = await requestAndConfirmDose2()
        XCTAssertEqual(recorded, .success(message: "✓ Dose 2 logged"))
    }

    func testContinueCommitsAcknowledgementWithDoseAndRejectsStaleSchedule() async throws {
        let previousTarget = UserSettingsManager.shared.targetIntervalMinutes
        UserSettingsManager.shared.targetIntervalMinutes = 165
        defer { UserSettingsManager.shared.targetIntervalMinutes = previousTarget }
        var plan = WorkWakeSchedule(timeZoneIdentifier: "UTC", workingWeekdays: Set(1...7), wakeMinutes: 420, target: .doseTarget)
        XCTAssertTrue(repository.saveWorkWakeSchedule(plan).isCommitted)
        dateProvider.advance(by: 30 * 60)
        guard case .needsConfirm(.workWake(let old)) = await coordinator.takeDose2() else { return XCTFail("Expected warning") }
        plan = try repository.workWakeSchedule()
        plan.wakeMinutes = 450
        XCTAssertTrue(repository.saveWorkWakeSchedule(plan).isCommitted)
        guard case .needsConfirm(.workWake(let current)) = await coordinator.takeDose2(acknowledgedWorkWarning: old) else { return XCTFail("Stale acknowledgement must be rejected") }
        XCTAssertNil(repository.dose2Time)
        let result = await requestAndConfirmDose2(acknowledgedWorkWarning: current)
        XCTAssertEqual(result, .success(message: "✓ Dose 2 logged"))
        let event = try XCTUnwrap(storage.fetchDoseEvents(sessionId: repository.activeSessionId, sessionDate: repository.activeSessionDate!).first { $0.eventType == "dose2" })
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(event.metadata).utf8)) as? [String: Any])
        XCTAssertNotNil(metadata["work_warning_acknowledgement"])
    }

    func testRetrospectiveWorkWarningPreservesOccurrenceAndRequiresSeparateConfirmation() async throws {
        let previousTarget = UserSettingsManager.shared.targetIntervalMinutes
        UserSettingsManager.shared.targetIntervalMinutes = 165
        defer { UserSettingsManager.shared.targetIntervalMinutes = previousTarget }
        XCTAssertTrue(repository.saveWorkWakeSchedule(WorkWakeSchedule(timeZoneIdentifier: "UTC", workingWeekdays: Set(1...7), target: .doseTarget)).isCommitted)
        dateProvider.advance(by: 180 * 60)
        let occurrence = dose1Time.addingTimeInterval(250 * 60)
        guard case .needsConfirm = await coordinator.recordDose2Occurrence(at: occurrence) else { return XCTFail("Timing confirmation must remain required") }
        guard case .needsConfirm(.workWake(let warning)) = await coordinator.recordDose2Occurrence(at: occurrence, warningConfirmed: true) else { return XCTFail("Expected work warning for the actual late occurrence") }
        XCTAssertNil(repository.dose2Time)
        let result = await coordinator.recordDose2Occurrence(at: occurrence, warningConfirmed: true, acknowledgedWorkWarning: warning)
        guard case .success = result else { return XCTFail("Expected committed historical occurrence: \(result)") }
        XCTAssertEqual(repository.dose2Time, occurrence)
        let event = try XCTUnwrap(storage.fetchDoseEvents(sessionId: repository.activeSessionId, sessionDate: repository.activeSessionDate!).first { $0.eventType == "dose2" })
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(event.metadata).utf8)) as? [String: Any])
        XCTAssertEqual(metadata["entry_mode"] as? String, "retrospective")
        XCTAssertNotNil(metadata["work_warning_acknowledgement"])
    }

    func testClosedWindow_blocksProspectiveDose2_withoutWritingOutcome() async {
        dateProvider.advance(by: 150 * 60 + 30)

        let result = await coordinator.takeDose2(surface: .deepLink)

        XCTAssertEqual(
            result,
            .blocked(reason: "The Dose 2 window has ended. Record a dose that already occurred, or mark it missed.")
        )
        XCTAssertNil(repository.dose2Time)
        XCTAssertFalse(repository.dose2Skipped)
        XCTAssertEqual(dateProvider.readCount, 1, "The decision must use one captured instant")
    }

    func testRapidConfirmedDose2Submissions_createOneDoseAndNoUnconfirmedExtra() async {
        dateProvider.advance(by: 30)
        guard case .needsConfirm(.dose2Record(let confirmation)) = await coordinator.takeDose2() else {
            return XCTFail("Expected explicit record confirmation")
        }

        async let tonightResult = coordinator.confirmDose2(confirmation)
        async let deepLinkResult = coordinator.confirmDose2(confirmation)
        let results = await [tonightResult, deepLinkResult]

        XCTAssertEqual(
            results.filter { result in
                if case .success = result { return true }
                return false
            }.count,
            1,
            "Exactly one ordinary submission may commit."
        )

        let sessionId = repository.activeSessionId
        let sessionDate = repository.activeSessionDate ?? ""
        let events = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        XCTAssertEqual(events.filter { $0.eventType == "dose2" }.count, 1)
        XCTAssertFalse(
            events.contains { $0.eventType == "extra_dose" },
            "An interleaved ordinary submission must never be promoted to an extra dose."
        )
    }

    func testRetrospectiveOutsideWindowOccurrence_requiresWarningThenPersistsActualTimeAndAuditMetadata() async throws {
        let decisionTime = dose1Time.addingTimeInterval(300 * 60)
        let occurrenceTime = dose1Time.addingTimeInterval(270 * 60)
        dateProvider.advance(by: decisionTime.timeIntervalSince(dateProvider.now()))
        let readsBeforeActions = dateProvider.readCount

        let unconfirmed = await coordinator.recordDose2Occurrence(
            at: occurrenceTime,
            surface: .sessionDetail
        )
        XCTAssertEqual(unconfirmed, .needsConfirm(.outsideWindowOccurrence))
        XCTAssertNil(repository.dose2Time)

        let confirmed = await coordinator.recordDose2Occurrence(
            at: occurrenceTime,
            warningConfirmed: true,
            reason: "schedule_disruption",
            reasonNotes: "Recorded after waking.",
            surface: .sessionDetail
        )

        XCTAssertEqual(confirmed, .success(message: "✓ Dose 2 (Late, Recorded Later) logged"))
        XCTAssertEqual(repository.dose2Time, occurrenceTime)
        XCTAssertFalse(repository.dose2Skipped)
        XCTAssertEqual(
            dateProvider.readCount - readsBeforeActions,
            2,
            "Each retrospective action must capture the decision clock exactly once"
        )

        let sessionId = try XCTUnwrap(repository.activeSessionId)
        let sessionDate = try XCTUnwrap(repository.activeSessionDate)
        let event = try XCTUnwrap(
            storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
                .first { $0.eventType == "dose2" }
        )
        XCTAssertEqual(event.timestamp, occurrenceTime)

        let metadataData = try XCTUnwrap(event.metadata?.data(using: .utf8))
        let metadata = try XCTUnwrap(
            JSONSerialization.jsonObject(with: metadataData) as? [String: Any]
        )
        XCTAssertEqual(metadata["entry_mode"] as? String, DoseEntryMode.retrospective.rawValue)
        XCTAssertEqual(metadata["surface"] as? String, RegistrationSurface.sessionDetail.rawValue)
        let recordedAtString = try XCTUnwrap(metadata["recorded_at_utc"] as? String)
        let recordedAtFormatter = ISO8601DateFormatter()
        recordedAtFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(recordedAtFormatter.date(from: recordedAtString), decisionTime)
        XCTAssertEqual(metadata["is_late"] as? Bool, true)
        XCTAssertEqual(metadata["reason"] as? String, "schedule_disruption")
    }

    func testRetrospectiveOccurrence_rejectsFutureTimestamp() async {
        let futureOccurrence = dose1Time.addingTimeInterval(151 * 60)

        let result = await coordinator.recordDose2Occurrence(
            at: futureOccurrence,
            warningConfirmed: true
        )

        XCTAssertEqual(result, .blocked(reason: "Dose 2 time cannot be in the future"))
        XCTAssertNil(repository.dose2Time)
        XCTAssertFalse(repository.dose2Skipped)
    }

    func testConfirmationCapturesCurrentTimeNotEarlierPromptTime() async throws {
        dateProvider.advance(by: 30)
        guard case .needsConfirm(.dose2Record(let confirmation)) = await coordinator.takeDose2() else {
            return XCTFail("Expected confirmation without a write")
        }
        XCTAssertNil(repository.dose2Time)
        dateProvider.advance(by: 60)
        let result = await coordinator.confirmDose2(confirmation)
        XCTAssertEqual(result, .success(message: "✓ Dose 2 logged"))
        XCTAssertEqual(repository.dose2Time, dose1Time.addingTimeInterval(151 * 60))
    }

    func testConfirmationUsesPersistedDose1PrecisionAfterReload() async {
        XCTAssertTrue(repository.setDose1Time(dose1Time.addingTimeInterval(0.000123)).isCommitted)
        dateProvider.advance(by: 60)
        let result = await requestAndConfirmDose2()
        XCTAssertEqual(result, .success(message: "✓ Dose 2 logged"))
        XCTAssertNotNil(repository.dose2Time, "Real Date values must survive millisecond storage precision without false stale-session rejection")
    }

    func testCancelledOrBackgroundedConfirmationCannotCommit() async {
        dateProvider.advance(by: 30)
        guard case .needsConfirm(.dose2Record(let confirmation)) = await coordinator.takeDose2() else {
            return XCTFail("Expected confirmation")
        }
        coordinator.cancelDose2Confirmation()
        guard case .blocked = await coordinator.confirmDose2(confirmation) else {
            return XCTFail("Cancelled confirmation must fail closed")
        }
        XCTAssertNil(repository.dose2Time)
        repository.reload()
        XCTAssertNil(repository.dose2Time, "No hidden record may appear after reload")
    }

    func testConfirmationCannotBeAppliedToReplacementSession() async {
        dateProvider.advance(by: 30)
        guard case .needsConfirm(.dose2Record(let confirmation)) = await coordinator.takeDose2() else {
            return XCTFail("Expected confirmation")
        }
        repository.clearTonight()
        XCTAssertTrue(repository.setDose1Time(dose1Time).isCommitted)
        guard case .blocked = await coordinator.confirmDose2(confirmation) else {
            return XCTFail("Consent for another session must fail closed")
        }
        XCTAssertNil(repository.dose2Time)
    }

    func testConfirmationRejectsDose1CorrectionInSameSession() async {
        dateProvider.advance(by: 30)
        guard case .needsConfirm(.dose2Record(let confirmation)) = await coordinator.takeDose2() else {
            return XCTFail("Expected confirmation")
        }
        XCTAssertTrue(repository.setDose1Time(dose1Time.addingTimeInterval(-60)).isCommitted)
        guard case .blocked = await coordinator.confirmDose2(confirmation) else {
            return XCTFail("Changed Dose 1 requires a fresh review")
        }
        XCTAssertNil(repository.dose2Time)
    }

    func testConfirmationRechecksClosedWindowWithoutBackdatingOrMarkingMissed() async {
        dateProvider.advance(by: 30)
        guard case .needsConfirm(.dose2Record(let confirmation)) = await coordinator.takeDose2() else {
            return XCTFail("Expected confirmation")
        }
        dateProvider.advance(by: 90 * 60 + 1)
        guard case .blocked = await coordinator.confirmDose2(confirmation) else {
            return XCTFail("An old prompt cannot authorize a later closed-window action")
        }
        XCTAssertNil(repository.dose2Time)
        XCTAssertFalse(repository.dose2Skipped)
    }

    func testConsumedConfirmationCannotBeReplayedAfterUndo() async {
        dateProvider.advance(by: 30)
        guard case .needsConfirm(.dose2Record(let confirmation)) = await coordinator.takeDose2() else {
            return XCTFail("Expected confirmation")
        }
        let result = await coordinator.confirmDose2(confirmation)
        XCTAssertEqual(result, .success(message: "✓ Dose 2 logged"))
        XCTAssertTrue(repository.clearDose2().isCommitted)
        guard case .blocked = await coordinator.confirmDose2(confirmation) else {
            return XCTFail("Consumed confirmation must never restore an undone dose")
        }
        XCTAssertNil(repository.dose2Time)
    }

    private func requestAndConfirmDose2(acknowledgedWorkWarning: WorkWakeWarning? = nil) async -> DoseActionCoordinator.ActionResult {
        let response = await coordinator.takeDose2(acknowledgedWorkWarning: acknowledgedWorkWarning)
        guard case .needsConfirm(.dose2Record(let confirmation)) = response else {
            XCTFail("Expected a separate record confirmation: \(response)")
            return response
        }
        XCTAssertNil(repository.dose2Time)
        return await coordinator.confirmDose2(confirmation)
    }
}
