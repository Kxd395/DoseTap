//
//  UIStateTests.swift
//  DoseTapTests
//
//  UI smoke tests, phase transitions, snooze/skip state, and settings tests.
//  Extracted from DoseTapTests.swift for maintainability.
//

import XCTest
@testable import DoseTap
import DoseCore
import UIKit
import SwiftUI

// MARK: - UI Smoke Tests

@MainActor
final class UISmokeTests: XCTestCase {
    func testMorningExceptionUsesActualIntervalAndReasonStartsUnanswered() throws {
        let model = MorningCheckInViewModel(sessionId: "synthetic", sessionDate: "2026-09-10", loadRememberedSettings: false)
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        model.loggedDose1Time = first
        XCTAssertNil(model.dose2TakenReason)
        model.nightType = .workNight
        let unanswered = try XCTUnwrap(model.toStoredCheckIn().timingContextJson?.data(using: .utf8))
        XCTAssertNil((try JSONSerialization.jsonObject(with: unanswered) as? [String: Any])?["dose2TakenReason"])
        for (minutes, expected) in [(149.0, true), (150, false), (170, false), (240, false), (240.01, true)] {
            model.loggedDose2Time = first.addingTimeInterval(minutes * 60)
            XCTAssertEqual(model.showsDose2TakenReason, expected)
        }
        model.loggedDose2Time = nil
        model.dose2Reconciliation = .taken
        model.reconcileDose2Time = first.addingTimeInterval(170 * 60)
        XCTAssertFalse(model.showsDose2TakenReason)
        model.reconcileDose2Time = first.addingTimeInterval(250 * 60)
        XCTAssertTrue(model.showsDose2TakenReason)
        model.dose2TakenReason = .unsure
        XCTAssertEqual(model.selectedDose2TakenReasonRawValue, "unsure")
        let explicit = try XCTUnwrap(model.toStoredCheckIn().timingContextJson?.data(using: .utf8))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: explicit) as? [String: Any])?["dose2TakenReason"] as? String, "unsure")
    }
    func testMorningReminderAndFailedSaveReadableAtLargeText() throws {
        let model = MorningCheckInViewModel(sessionId: "synthetic-night", sessionDate: "2026-08-30", loadRememberedSettings: false)
        model.submissionErrorMessage = "Your morning answers were not saved. They are still here; try Complete Check-In again. Any dose corrections already saved remain recorded."
        for size in [DynamicTypeSize.large, .accessibility5] {
            let content = VStack(spacing: 16) {
                IncompleteSessionBanner(sessionDate: "2026-08-30", isBlocking: false, onComplete: {}, onDismiss: {})
                MorningCheckInSubmitSection(viewModel: model, dismissAction: {}, onComplete: {})
            }.padding().frame(width: 350).environment(\.dynamicTypeSize, size).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            let rendered = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "Earlier morning reminder and retained draft error - \(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    
    private var storage: EventStorage!
    private var repo: SessionRepository!
    private var previousPrepTimeMinutes: Int!
    
    /// Fixed clock well after the 18:00 UTC rollover so dose times at
    /// `Date() - 180 min` never cross a session boundary on CI (UTC).
    private let fixedNow: Date = {
        ISO8601DateFormatter().date(from: "2026-01-15T23:00:00Z")!
    }()
    
    override func setUp() async throws {
        previousPrepTimeMinutes = UserSettingsManager.shared.prepTimeMinutes
        UserSettingsManager.shared.prepTimeMinutes = 18 * 60
        storage = EventStorage.shared
        repo = SessionRepository(
            storage: storage,
            clock: { [fixedNow] in fixedNow },
            timeZoneProvider: { TimeZone(identifier: "UTC")! }
        )
        storage.clearAllData()
        repo.reload()
    }
    
    override func tearDown() async throws {
        storage.clearAllData()
        UserSettingsManager.shared.prepTimeMinutes = previousPrepTimeMinutes
    }
    
    func test_tonightEmptyState_afterSessionDelete() async throws {
        repo.setDose1Time(fixedNow.addingTimeInterval(-180 * 60))
        repo.incrementSnooze()
        repo.setDose2Time(fixedNow.addingTimeInterval(-15 * 60))
        
        let sessionDate = repo.currentSessionDateString()
        
        XCTAssertNotNil(repo.dose1Time, "Session should exist before delete")
        XCTAssertNotNil(repo.dose2Time, "Dose 2 should exist before delete")
        XCTAssertEqual(repo.snoozeCount, 1, "Snooze count should be 1")
        
        repo.deleteSession(sessionDate: sessionDate)
        
        let context = repo.currentContext
        XCTAssertEqual(context.phase, .noDose1, "Phase should be noDose1 (empty state)")
        XCTAssertNil(repo.dose1Time, "Dose 1 should be nil")
        XCTAssertNil(repo.dose2Time, "Dose 2 should be nil")
        XCTAssertEqual(repo.snoozeCount, 0, "Snooze count should be 0")
        XCTAssertNil(repo.activeSessionDate, "Active session should be nil")
        
        if case .disabled(let msg) = context.primary {
            XCTAssertTrue(msg.contains("Dose 1") || msg.contains("Log"), "Empty state should prompt for Dose 1")
        }
    }
    
    func test_exportProducesData_whenSessionExists() async throws {
        let now = fixedNow
        repo.setDose1Time(now.addingTimeInterval(-180 * 60))
        repo.setDose2Time(now.addingTimeInterval(-15 * 60))
        
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "bathroom",
            timestamp: now.addingTimeInterval(-60 * 60),
            colorHex: nil
        )
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "lights_out",
            timestamp: now.addingTimeInterval(-120 * 60),
            colorHex: nil
        )
        
        let sessionDate = repo.currentSessionDateString()
        let sleepEvents = storage.fetchSleepEvents(forSession: sessionDate)
        
        XCTAssertGreaterThan(sleepEvents.count, 0, "Should have sleep events to export")
        XCTAssertNotNil(repo.dose1Time, "Should have dose1 to export")
        XCTAssertNotNil(repo.dose2Time, "Should have dose2 to export")
        
        for event in sleepEvents {
            XCTAssertFalse(event.id.isEmpty, "Event should have ID")
            XCTAssertFalse(event.eventType.isEmpty, "Event should have type")
        }
    }
    
    func test_exportReturnsEmpty_whenNoSession() async throws {
        storage.clearAllData()
        repo.reload()
        
        let sessionDate = repo.currentSessionDateString()
        let sleepEvents = storage.fetchSleepEvents(forSession: sessionDate)
        
        XCTAssertTrue(sleepEvents.isEmpty, "Should have no events when no session")
        XCTAssertNil(repo.dose1Time, "Should have no dose1")
        XCTAssertNil(repo.dose2Time, "Should have no dose2")
    }
}

@MainActor
final class AppScreenCaptureTests: XCTestCase {
    func test_bestFullPageScrollView_prefersVisibleVerticalContentOverPagingScrollView() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        let pageScrollView = UIScrollView(frame: root.bounds)
        pageScrollView.contentSize = CGSize(width: 390 * 5, height: 844)
        root.addSubview(pageScrollView)

        let contentScrollView = UIScrollView(frame: CGRect(x: 0, y: 80, width: 390, height: 700))
        contentScrollView.contentSize = CGSize(width: 390, height: 1_600)
        root.addSubview(contentScrollView)

        let selected = AppScreenCapture.bestFullPageScrollView(in: root)

        XCTAssertTrue(selected === contentScrollView)
    }

    func test_bestFullPageScrollView_returnsNilWithoutVerticalOverflow() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let scrollView = UIScrollView(frame: root.bounds)
        scrollView.contentSize = root.bounds.size
        root.addSubview(scrollView)

        XCTAssertNil(AppScreenCapture.bestFullPageScrollView(in: root))
    }

    func test_bestFullPageScrollView_ignoresHiddenScrollableContent() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let scrollView = UIScrollView(frame: root.bounds)
        scrollView.contentSize = CGSize(width: 390, height: 1_600)
        scrollView.isHidden = true
        root.addSubview(scrollView)

        XCTAssertNil(AppScreenCapture.bestFullPageScrollView(in: root))
    }

    func test_bestFullPageScrollView_prefersTallestVisibleReviewContent() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        let nestedPreview = UIScrollView(frame: CGRect(x: 24, y: 220, width: 342, height: 300))
        nestedPreview.contentSize = CGSize(width: 342, height: 900)
        root.addSubview(nestedPreview)

        let fullReview = UIScrollView(frame: CGRect(x: 0, y: 88, width: 390, height: 692))
        fullReview.contentSize = CGSize(width: 390, height: 2_600)
        root.addSubview(fullReview)

        let selected = AppScreenCapture.bestFullPageScrollView(in: root)

        XCTAssertTrue(selected === fullReview)
    }
}

final class ReviewContextMetricTests: XCTestCase {
    func test_wakeToDose1Metric_usesLatestWakeBeforeDose1() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let olderWake = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 7, minute: 0))!
        let priorWake = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 6, minute: 48))!
        let dose1 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 21, minute: 15))!
        let sameNightWake = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 6, minute: 48))!

        let events = [
            DoseTap.StoredSleepEvent(
                id: "older",
                eventType: "wake_final",
                timestamp: olderWake,
                sessionDate: "2026-06-15"
            ),
            DoseTap.StoredSleepEvent(
                id: "prior",
                eventType: "wake_final",
                timestamp: priorWake,
                sessionDate: "2026-06-16"
            ),
            DoseTap.StoredSleepEvent(
                id: "same-night",
                eventType: "wake_final",
                timestamp: sameNightWake,
                sessionDate: "2026-06-17"
            )
        ]

        let metric = buildWakeToDose1Metric(dose1Time: dose1, events: events)

        XCTAssertEqual(metric?.wakeTime, priorWake)
        XCTAssertEqual(metric?.dose1Time, dose1)
        XCTAssertEqual(metric?.minutes, 867)
        XCTAssertEqual(metric?.formattedInterval, "14h 27m")
    }

    func test_wakeToDose1Metric_returnsNilForStaleWake() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let staleWake = calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 6, minute: 48))!
        let dose1 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 21, minute: 15))!
        let events = [
            DoseTap.StoredSleepEvent(
                id: "stale",
                eventType: "wake_final",
                timestamp: staleWake,
                sessionDate: "2026-06-14"
            )
        ]

        XCTAssertNil(buildWakeToDose1Metric(dose1Time: dose1, events: events))
    }
}

final class HomeStateResolverTests: XCTestCase {
    private let currentSessionDate = "2026-01-15"

    func test_screenshotState_keepsPriorCheckInNonBlockingAndHidesDuplicateStatus() {
        let state = resolve(
            doseStatus: .noDose1,
            activeSessionDate: nil,
            incompleteSessionDate: "2026-01-14"
        )

        XCTAssertEqual(state.primary, .tonightReady)
        XCTAssertEqual(state.priorSessionReview?.sessionDate, "2026-01-14")
        XCTAssertEqual(state.priorSessionReview?.isBlocking, false)
        XCTAssertFalse(state.isBlockedByPriorSession)
        XCTAssertTrue(state.showsDosePrimaryAction)
        XCTAssertFalse(state.showsDoseStatusCard, "Tonight-ready should not show a second Ready for Dose 1 status card above the Take Dose 1 button.")
        XCTAssertFalse(state.showsWakeAction)
        XCTAssertTrue(state.showsQuickLog)
        XCTAssertFalse(state.showsLiveDoseIntervals)
    }

    func test_currentSessionIncompleteBlocksCurrentActions() {
        let state = resolve(
            doseStatus: .noDose1,
            activeSessionDate: nil,
            incompleteSessionDate: currentSessionDate
        )

        XCTAssertEqual(state.primary, .previousSessionNeedsReview)
        XCTAssertTrue(state.isBlockedByPriorSession)
        XCTAssertEqual(state.priorSessionReview?.isBlocking, true)
        XCTAssertFalse(state.showsDosePrimaryAction)
        XCTAssertFalse(state.showsQuickLog)
        XCTAssertFalse(state.showsWakeAction)
    }

    func test_dosePhasesResolveToSinglePrimaryWorkflow() {
        XCTAssertEqual(resolve(doseStatus: .beforeWindow).primary, .dose2Waiting)
        XCTAssertEqual(resolve(doseStatus: .active).primary, .dose2Ready)
        XCTAssertEqual(resolve(doseStatus: .nearClose).primary, .dose2Ready)
        XCTAssertEqual(resolve(doseStatus: .closed).primary, .dose2NeedsResolution)

        let activeState = resolve(doseStatus: .active, activeSessionDate: currentSessionDate)
        XCTAssertTrue(activeState.showsDoseStatusCard)
        XCTAssertTrue(activeState.showsDosePrimaryAction)
        XCTAssertFalse(activeState.showsWakeAction)
        XCTAssertTrue(activeState.showsLiveDoseIntervals)
    }

    func test_completedAndFinalizingUseWakeActionInsteadOfDoseButton() {
        let completed = resolve(doseStatus: .completed, activeSessionDate: currentSessionDate)
        XCTAssertEqual(completed.primary, .morningCloseout)
        XCTAssertFalse(completed.showsDosePrimaryAction)
        XCTAssertTrue(completed.showsWakeAction)

        let finalizing = resolve(doseStatus: .finalizing, activeSessionDate: currentSessionDate)
        XCTAssertEqual(finalizing.primary, .morningCloseout)
        XCTAssertFalse(finalizing.showsDosePrimaryAction)
        XCTAssertTrue(finalizing.showsWakeAction)
    }

    func test_completedCheckInResolvesToReviewOnly() {
        let state = resolve(
            doseStatus: .completed,
            activeSessionDate: nil,
            checkInCompleted: true,
            hasMorningCheckIn: true
        )

        XCTAssertEqual(state.primary, .reviewOnly)
        XCTAssertFalse(state.showsDosePrimaryAction)
        XCTAssertFalse(state.showsWakeAction)
        XCTAssertFalse(state.showsQuickLog)
        XCTAssertTrue(state.showsWeeklyInsights)
    }

    private func resolve(
        doseStatus: DoseStatus,
        activeSessionDate: String? = nil,
        incompleteSessionDate: String? = nil,
        awaitingRolloverMessage: String? = nil,
        checkInCompleted: Bool = false,
        hasMorningCheckIn: Bool = false
    ) -> HomePresentationState {
        HomeStateResolver.resolve(
            doseStatus: doseStatus,
            currentSessionDate: currentSessionDate,
            activeSessionDate: activeSessionDate,
            incompleteSessionDate: incompleteSessionDate,
            awaitingRolloverMessage: awaitingRolloverMessage,
            checkInCompleted: checkInCompleted,
            hasMorningCheckIn: hasMorningCheckIn
        )
    }
}

// MARK: - Full UI State Tests

@MainActor
final class UIStateTests: XCTestCase {
    
    private var storage: EventStorage!
    private var repo: SessionRepository!
    private var previousPrepTimeMinutes: Int!
    
    /// Fixed clock well after the 18:00 UTC rollover so dose times at
    /// `Date() - N min` never cross a session boundary on CI (UTC).
    private let fixedNow: Date = {
        ISO8601DateFormatter().date(from: "2026-01-15T23:00:00Z")!
    }()
    
    override func setUp() async throws {
        previousPrepTimeMinutes = UserSettingsManager.shared.prepTimeMinutes
        UserSettingsManager.shared.prepTimeMinutes = 18 * 60
        storage = EventStorage.shared
        repo = SessionRepository(
            storage: storage,
            clock: { [fixedNow] in fixedNow },
            timeZoneProvider: { TimeZone(identifier: "UTC")! }
        )
        storage.clearAllData()
        repo.reload()
    }
    
    override func tearDown() async throws {
        storage.clearAllData()
        UserSettingsManager.shared.prepTimeMinutes = previousPrepTimeMinutes
    }
    
    // MARK: - Phase Transition Tests
    
    func test_phaseTransitions_fullCycle() async throws {
        XCTAssertEqual(repo.currentContext.phase, .noDose1, "Initial phase should be noDose1")
        
        let dose1Time = fixedNow.addingTimeInterval(-100 * 60)
        repo.setDose1Time(dose1Time)
        XCTAssertEqual(repo.currentContext.phase, .beforeWindow, "Should be beforeWindow when window not open")
        
        repo.setDose1Time(fixedNow.addingTimeInterval(-155 * 60))
        XCTAssertEqual(repo.currentContext.phase, .active, "Should be active when in window")
        
        repo.setDose1Time(fixedNow.addingTimeInterval(-235 * 60))
        XCTAssertEqual(repo.currentContext.phase, .nearClose, "Should be nearClose near window end")
        
        repo.setDose1Time(fixedNow.addingTimeInterval(-250 * 60))
        XCTAssertEqual(repo.currentContext.phase, .closed, "Should be closed past window")
    }
    
    func test_completedPhase_afterDose2() async throws {
        repo.setDose1Time(fixedNow.addingTimeInterval(-160 * 60))
        repo.setDose2Time(fixedNow)
        XCTAssertEqual(repo.currentContext.phase, .completed, "Should be completed after dose2")
    }
    
    func test_completedPhase_afterSkip() async throws {
        repo.setDose1Time(fixedNow.addingTimeInterval(-160 * 60))
        repo.skipDose2()
        XCTAssertEqual(repo.currentContext.phase, .completed, "Should be completed after skip")
    }

    func test_defaultTimelineMode_closedSession_staysLiveForLateDose() {
        let mode = defaultTimelineMode(
            status: .closed,
            reviewSessionAvailable: true,
            currentHour: 9
        )

        XCTAssertEqual(mode, .live, "Closed sessions should stay on the live surface so late Dose 2 remains actionable")
    }

    func test_defaultTimelineMode_completedSession_usesReview() {
        let mode = defaultTimelineMode(
            status: .completed,
            reviewSessionAvailable: true,
            currentHour: 9
        )

        XCTAssertEqual(mode, .review)
    }
    
    // MARK: - Snooze State Tests
    
    func test_snoozeState_throughCycles() async throws {
        repo.setDose1Time(fixedNow.addingTimeInterval(-155 * 60))
        
        if case .snoozeEnabled = repo.currentContext.snooze {
        } else {
            XCTFail("Snooze should be enabled initially")
        }
        XCTAssertTrue(repo.incrementSnoozeIfActive())
        XCTAssertEqual(repo.snoozeCount, 1)
        
        XCTAssertTrue(repo.incrementSnoozeIfActive())
        XCTAssertEqual(repo.snoozeCount, 2)
        
        XCTAssertTrue(repo.incrementSnoozeIfActive())
        XCTAssertEqual(repo.snoozeCount, 3)
        if case .snoozeDisabled = repo.currentContext.snooze {
        } else {
            XCTFail("Snooze should be disabled at max")
        }
    }
    
    func test_snoozeDisabled_nearWindowEnd() async throws {
        repo.setDose1Time(fixedNow.addingTimeInterval(-230 * 60))
        if case .snoozeDisabled = repo.currentContext.snooze {
        } else {
            XCTFail("Snooze should be disabled when <15 min remain")
        }
    }
    
    // MARK: - Skip State Tests
    
    func test_skipState_enabledInActiveWindow() async throws {
        repo.setDose1Time(fixedNow.addingTimeInterval(-155 * 60))
        if case .skipEnabled = repo.currentContext.skip {
        } else {
            XCTFail("Skip should be enabled in active window")
        }
    }
    
    func test_skipState_disabledAfterSkip() async throws {
        repo.setDose1Time(fixedNow.addingTimeInterval(-155 * 60))
        repo.skipDose2()
        if case .skipDisabled = repo.currentContext.skip {
        } else {
            XCTFail("Skip should be disabled after skip")
        }
    }
    
    // MARK: - Primary CTA Tests
    
    func test_primaryCTA_changesWithPhase() async throws {
        if case .disabled = repo.currentContext.primary {
        } else {
            XCTFail("Primary should be disabled without dose1")
        }
        
        repo.setDose1Time(fixedNow.addingTimeInterval(-155 * 60))
        switch repo.currentContext.primary {
        case .takeNow, .takeBeforeWindowEnds:
            break
        default:
            XCTFail("Primary should be take action in active window")
        }
        
        repo.setDose2Time(fixedNow)
        if case .disabled = repo.currentContext.primary {
        } else {
            XCTFail("Primary should be disabled after completion")
        }
    }

    func test_primaryCTA_closedPhase_requiresRecordResolution() async throws {
        repo.setDose1Time(fixedNow.addingTimeInterval(-250 * 60))
        XCTAssertEqual(repo.currentContext.phase, .closed)

        switch repo.currentContext.primary {
        case .resolveExpiredRecord(let reason):
            XCTAssertFalse(reason.isEmpty, "Resolution CTA should include rationale.")
        default:
            XCTFail("Closed phase should surface .resolveExpiredRecord.")
        }
    }
    
    // MARK: - Settings State Tests
    
    func test_settings_persistenceRoundTrip() {
        let defaults = UserDefaults.standard
        let testKey = "test_reduced_motion"
        
        defaults.set(true, forKey: testKey)
        XCTAssertTrue(defaults.bool(forKey: testKey), "Should persist boolean setting")
        defaults.removeObject(forKey: testKey)
    }
    
    func test_settings_targetMinutesPersistence() {
        let defaults = UserDefaults.standard
        let key = "dose2_target_minutes"
        
        defaults.removeObject(forKey: key)
        let defaultValue = defaults.integer(forKey: key)
        XCTAssertEqual(defaultValue, 0, "Missing key returns 0")
        
        defaults.set(180, forKey: key)
        XCTAssertEqual(defaults.integer(forKey: key), 180, "Should persist custom target")
        defaults.removeObject(forKey: key)
    }
    
    // MARK: - Timer Display Tests
    
    func test_remainingTime_availableInWindow() async throws {
        repo.setDose1Time(fixedNow.addingTimeInterval(-155 * 60))
        let remaining = repo.currentContext.remainingToMax
        XCTAssertNotNil(remaining, "Should have remainingToMax in window")
        if let secs = remaining {
            XCTAssertGreaterThan(secs, 0, "Remaining should be positive in window")
        }
    }
    
    func test_remainingTime_nilWithNoSession() async throws {
        let remaining = repo.currentContext.remainingToMax
        XCTAssertNil(remaining, "No remaining time without session")
    }
}

// MARK: - PreSleep Card State Tests

final class PreSleepCardStateTests: XCTestCase {
    func test_preSleepCardState_loggedHidesCTA() {
        let log = StoredPreSleepLog(
            id: "log-123",
            sessionId: "2025-12-26",
            createdAtUtc: "2025-12-26T03:22:00Z",
            localOffsetMinutes: -300,
            completionState: "complete",
            answers: nil
        )
        let loggedState = PreSleepCardState(log: log)
        XCTAssertTrue(loggedState.isLogged)
        XCTAssertEqual(loggedState.action, .edit(id: "log-123"))
        
        let emptyState = PreSleepCardState(log: nil)
        XCTAssertFalse(emptyState.isLogged)
        XCTAssertEqual(emptyState.action, .start)
    }
    
    func test_preSleepCardState_editActionUsesSameId() {
        let log = StoredPreSleepLog(
            id: "log-999",
            sessionId: "2025-12-26",
            createdAtUtc: "2025-12-26T05:00:00Z",
            localOffsetMinutes: 0,
            completionState: "complete",
            answers: nil
        )
        let state = PreSleepCardState(log: log)
        XCTAssertEqual(state.action, .edit(id: "log-999"))
    }
}

final class SavedPainPatternTests: XCTestCase {
    func testTemplateSeedDoesNotSupplyNightlyReplacementIdentity() {
        let back = PreSleepLogAnswers.PainEntry(area: .midBack, side: .both, intensity: 2, sensations: [.tightness])
        let template = GranularPainEntryEditorView(initialEntry: back, replacesInitialEntry: false) { _ in }
        let edit = GranularPainEntryEditorView(initialEntry: back) { _ in }
        XCTAssertNil(template.replacementEntryKey)
        XCTAssertEqual(edit.replacementEntryKey, back.entryKey)
    }
    func testIndependentPatternsSurviveRestartAndForgetWithoutChangingCopies() throws {
        let suite = "pain-pattern-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedPainPatternStore(defaults: defaults)
        let back = PreSleepLogAnswers.PainEntry(area: .midBack, side: .both, intensity: 2, sensations: [.throbbing, .tightness])
        let feet = PreSleepLogAnswers.PainEntry(area: .ankleFoot, side: .both, intensity: 5, sensations: [.pinsNeedles, .numbness], notes: "Recurring feet symptoms")
        try store.remember(back)
        try store.remember(feet)
        let restarted = SavedPainPatternStore(defaults: defaults)
        XCTAssertEqual(Set(restarted.entries), Set([back, feet]))
        var reviewed = back
        reviewed.intensity = 4
        XCTAssertEqual(restarted.entries.first { $0.entryKey == back.entryKey }?.intensity, 2)
        try restarted.forget(back.entryKey)
        XCTAssertEqual(SavedPainPatternStore(defaults: defaults).entries, [feet])
        XCTAssertEqual(back.intensity, 2, "Forgetting a preference cannot mutate a saved observation")
        defaults.removePersistentDomain(forName: suite)
        restarted.reloadFromPreferences()
        XCTAssertTrue(restarted.entries.isEmpty, "Cleared preferences must also clear the in-memory pattern list")
    }

    func testUnreadablePreferencesAreNotOverwritten() throws {
        let suite = "pain-pattern-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: SavedPainPatternStore.key)
        let store = SavedPainPatternStore(defaults: defaults)
        XCTAssertNotNil(store.loadError)
        XCTAssertThrowsError(try store.remember(.init(area: .midBack, side: .both, intensity: 2, sensations: [.tightness])))
        XCTAssertEqual(defaults.data(forKey: SavedPainPatternStore.key), Data("invalid".utf8))
    }
}

final class CheckInCarryForwardTests: XCTestCase {
    func test_preSleepCarryForwardKeepsOnlyReusableRoomSetup() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sourceDate = try XCTUnwrap(AppFormatters.parseISO8601Flexible("2026-01-10T02:15:00Z"))
        let referenceDate = try XCTUnwrap(AppFormatters.parseISO8601Flexible("2026-01-15T23:00:00Z"))

        var answers = DoseTap.PreSleepLogAnswers()
        answers.intendedSleepTime = .thirtyMin
        answers.stressLevel = 3
        answers.stressDrivers = [.work, .health]
        answers.stressNotes = "one-off stress note"
        answers.stimulants = .coffee
        answers.caffeineLastIntakeAt = sourceDate
        answers.caffeineLastAmountMg = 12
        answers.caffeineDailyTotalMg = 24
        answers.alcohol = .one
        answers.alcoholLastDrinkAt = sourceDate
        answers.alcoholLastAmountDrinks = 1
        answers.alcoholDailyTotalDrinks = 1
        answers.plannedTotalNightlyMg = 9000
        answers.plannedDose1Mg = 4500
        answers.plannedDose2Mg = 4500
        answers.plannedDoseSplitRatio = [0.5, 0.5]
        answers.napCount = 2
        answers.napTotalMinutes = 40
        answers.napLastEndAt = sourceDate
        answers.exercise = .light
        answers.exerciseLastAt = sourceDate.addingTimeInterval(-3600)
        answers.screensInBed = .briefly
        answers.screensLastUsedAt = sourceDate.addingTimeInterval(1800)
        answers.roomTemp = .cool
        answers.noiseLevel = .quiet
        answers.sleepAidSelections = [.fan]
        answers.notes = "one-off note"

        let carried = answers.carriedForwardForNewNight(referenceDate: referenceDate, calendar: calendar)

        XCTAssertEqual(carried.roomTemp, .cool)
        XCTAssertEqual(carried.noiseLevel, .quiet)
        XCTAssertEqual(carried.sleepAidSelections, [.fan])
        let encoded = try JSONEncoder().encode(carried)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), Set(["roomTemp", "noiseLevel", "sleepAidSelections"]))
        // Carry-forward never mutates the previous night's stored answers.
        XCTAssertEqual(answers.caffeineLastIntakeAt, sourceDate)
        XCTAssertEqual(answers.stressNotes, "one-off stress note")
    }

    func test_preSleepNoAlcoholAndNoCaffeineRequireFreshAnswers() throws {
        var previous = DoseTap.PreSleepLogAnswers()
        previous.alcohol = DoseTap.PreSleepLogAnswers.AlcoholLevel.none
        previous.stimulants = DoseTap.PreSleepLogAnswers.Stimulants.none
        let fresh = previous.carriedForwardForNewNight(referenceDate: Date(timeIntervalSince1970: 0))
        XCTAssertNil(fresh.alcohol)
        XCTAssertNil(fresh.stimulants)
        XCTAssertFalse(fresh.hasCaffeineIntake)
    }

    func test_existingPreSleepAnswersRoundTripWithoutApplyingNewNightDefaults() throws {
        var previous = DoseTap.PreSleepLogAnswers()
        previous.alcohol = .one
        previous.caffeineLastIntakeAt = Date(timeIntervalSince1970: 100)
        previous.notes = "Existing night, not a new observation"
        let encoded = try JSONEncoder().encode(previous)
        let reopened = try JSONDecoder().decode(DoseTap.PreSleepLogAnswers.self, from: encoded)
        XCTAssertEqual(reopened.alcohol, .one)
        XCTAssertEqual(reopened.caffeineLastIntakeAt, previous.caffeineLastIntakeAt)
        XCTAssertEqual(reopened.notes, previous.notes)
    }

    func test_applyingRoomSetupDoesNotOverwriteCurrentOrHistoryAnswers() throws {
        var previous = DoseTap.PreSleepLogAnswers()
        previous.roomTemp = .cool
        previous.noiseLevel = .quiet
        previous.sleepAidSelections = [.fan]
        previous.stressNotes = "Yesterday"
        previous.alcohol = .one
        var current = DoseTap.PreSleepLogAnswers()
        current.stressNotes = "Today's answer"
        current.alcohol = DoseTap.PreSleepLogAnswers.AlcoholLevel.none
        current.sleepAidSelections = [.earplugs]
        let merged = current.applyingRememberedRoomSetup(from: previous)
        XCTAssertEqual(merged.roomTemp, .cool)
        XCTAssertEqual(merged.stressNotes, "Today's answer")
        XCTAssertEqual(merged.alcohol, DoseTap.PreSleepLogAnswers.AlcoholLevel.none)
        XCTAssertEqual(merged.sleepAidSelections, [.earplugs])
        XCTAssertEqual(previous.stressNotes, "Yesterday")
    }

    @MainActor
    func test_morningFallbackRemembersSetupWithoutPriorObservations() throws {
        let storage = EventStorage.shared
        storage.clearAllData()
        SessionRepository.shared.reload()
        UserDefaults.standard.removeObject(forKey: "morningCheckIn.rememberSettings")
        UserDefaults.standard.removeObject(forKey: "morningCheckIn.savedSettings")
        defer {
            storage.clearAllData()
            SessionRepository.shared.reload()
            UserDefaults.standard.removeObject(forKey: "morningCheckIn.rememberSettings")
            UserDefaults.standard.removeObject(forKey: "morningCheckIn.savedSettings")
        }

        let repo = SessionRepository.shared
        repo.saveMorningCheckIn(
            SQLiteStoredMorningCheckIn(
                id: "prior-checkin",
                sessionId: "prior-session",
                timestamp: try XCTUnwrap(AppFormatters.parseISO8601Flexible("2026-01-14T12:00:00Z")),
                sessionDate: "2026-01-14",
                sleepQuality: 4,
                feelRested: DoseTap.RestedLevel.well.rawValue,
                grogginess: DoseTap.GrogginessLevel.none.rawValue,
                sleepInertiaDuration: DoseTap.SleepInertiaDuration.lessThanFive.rawValue,
                dreamRecall: DoseTap.DreamRecallType.normal.rawValue,
                hasPhysicalSymptoms: true,
                physicalSymptomsJson: #"{"hasHeadache":true,"isMigraine":true}"#,
                hasRespiratorySymptoms: true,
                respiratorySymptomsJson: #"{"feelingFeverish":true}"#,
                mentalClarity: 4,
                mood: DoseTap.MoodLevel.good.rawValue,
                anxietyLevel: DoseTap.AnxietyLevel.none.rawValue,
                stressLevel: 2,
                stressContextJson: #"{"drivers":["work"],"notes":"routine"}"#,
                readinessForDay: 4,
                hadSleepParalysis: true,
                hadHallucinations: true,
                hadAutomaticBehavior: true,
                fellOutOfBed: true,
                hadConfusionOnWaking: true,
                usedSleepTherapy: true,
                sleepTherapyJson: #"{"device":"CPAP","compliance":95}"#,
                hasSleepEnvironment: true,
                sleepEnvironmentJson: #"{"roomTemp":"cool","noiseLevel":"quiet","sleepAids":"fan"}"#,
                timingContextJson: #"{"nightType":"work_night","dose2TakenReason":"forgot_to_tap","dose2ReasonNotes":"old reason"}"#,
                notes: "old one-off note"
            ),
            sessionDateOverride: "2026-01-14"
        )

        let viewModel = MorningCheckInViewModel(sessionId: "new-session", sessionDate: "2026-01-15")

        XCTAssertTrue(viewModel.rememberSettings)
        assertNoPriorMorningObservations(viewModel)
        XCTAssertEqual(viewModel.sleepTherapyDevice, .cpap)
        XCTAssertEqual(viewModel.sleepEnvironmentRoomTemp, .cool)
        XCTAssertEqual(viewModel.sleepEnvironmentNoiseLevel, .quiet)
        XCTAssertEqual(viewModel.sleepEnvironmentSleepAid, .fan)
        XCTAssertEqual(viewModel.nightType, .unsure)
        XCTAssertNil(viewModel.dose2TakenReason)
        XCTAssertTrue(viewModel.dose2ReasonNotes.isEmpty)
        XCTAssertTrue(viewModel.notes.isEmpty)
        let prior = try XCTUnwrap(repo.fetchMorningCheckIn(for: "2026-01-14"))
        let edited = MorningCheckInViewModel(sessionId: "prior-session", sessionDate: "2026-01-14", existing: prior)
        XCTAssertEqual(edited.sleepQuality, 4)
        XCTAssertTrue(edited.hasHeadache)
        XCTAssertTrue(edited.hadSleepParalysis)
        XCTAssertTrue(edited.usedSleepTherapy)
        XCTAssertEqual(edited.sleepTherapyCompliance, 95)
        XCTAssertEqual(edited.stressLevel, 2)
        XCTAssertEqual(edited.notes, "old one-off note")
    }

    @MainActor
    func test_legacySavedMorningSettingsWhitelistAndNewPreferencePayload() throws {
        let defaults = UserDefaults.standard
        let keys = ["morningCheckIn.rememberSettings", "morningCheckIn.savedSettings"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) } }
        defaults.set(true, forKey: keys[0])
        let legacy = #"{"sleepQuality":1,"feelRested":"Well Rested","mentalClarity":1,"readinessForDay":1,"stressLevel":5,"stressDrivers":["work"],"stressNotes":"old stress","usedSleepTherapy":true,"sleepTherapyDevice":"CPAP","sleepTherapyCompliance":12,"sleepTherapyNotes":"old therapy","hasSleepEnvironment":true,"sleepEnvironmentRoomTemp":"cool","sleepEnvironmentNoiseLevel":"quiet","sleepEnvironmentSleepAid":"fan","sleepEnvironmentNotes":"old room","pharmacogenomicFastMetabolizer":true,"pharmacogenomicClinicianReviewed":true,"coMedicationNotes":"old medication"}"#.data(using: .utf8)!
        defaults.set(legacy, forKey: keys[1])
        let fresh = MorningCheckInViewModel(sessionId: "new", sessionDate: "2026-01-15")
        assertNoPriorMorningObservations(fresh)
        XCTAssertEqual(fresh.sleepTherapyDevice, .cpap)
        XCTAssertEqual(fresh.sleepEnvironmentRoomTemp, .cool)
        XCTAssertEqual(defaults.data(forKey: keys[1]), legacy, "Opening a form must not rewrite the prior preference payload")
        fresh.saveSettingsForNextTime()
        let saved = try XCTUnwrap(defaults.data(forKey: keys[1]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["sleepTherapyDevice", "sleepEnvironmentRoomTemp", "sleepEnvironmentNoiseLevel", "sleepEnvironmentSleepAid"]))
        assertNoPriorMorningObservations(MorningCheckInViewModel(sessionId: "next", sessionDate: "2026-01-16"))
        fresh.stressLevel = 4
        fresh.setRememberSettingsEnabled(false)
        XCTAssertEqual(fresh.stressLevel, 4)
        XCTAssertNil(defaults.data(forKey: keys[1]))
        XCTAssertEqual(MorningCheckInViewModel(sessionId: "off", sessionDate: "2026-01-17").sleepTherapyDevice, .none)
    }

    @MainActor
    private func assertNoPriorMorningObservations(_ model: MorningCheckInViewModel, file: StaticString = #filePath, line: UInt = #line) {
        let baseline = MorningCheckInViewModel(sessionId: "baseline", sessionDate: "2026-01-15", loadRememberedSettings: false)
        let actual = model.toStoredCheckIn()
        let expected = baseline.toStoredCheckIn()
        XCTAssertEqual(actual.sleepQuality, expected.sleepQuality, file: file, line: line)
        XCTAssertEqual(actual.feelRested, expected.feelRested, file: file, line: line)
        XCTAssertEqual(actual.grogginess, expected.grogginess, file: file, line: line)
        XCTAssertEqual(actual.sleepInertiaDuration, expected.sleepInertiaDuration, file: file, line: line)
        XCTAssertEqual(actual.mentalClarity, expected.mentalClarity, file: file, line: line)
        XCTAssertEqual(actual.mood, expected.mood, file: file, line: line)
        XCTAssertEqual(actual.dreamRecall, expected.dreamRecall, file: file, line: line)
        XCTAssertEqual(actual.anxietyLevel, expected.anxietyLevel, file: file, line: line)
        XCTAssertEqual(actual.readinessForDay, expected.readinessForDay, file: file, line: line)
        XCTAssertNil(actual.stressLevel, file: file, line: line)
        XCTAssertFalse(actual.hasPhysicalSymptoms || actual.hasRespiratorySymptoms || actual.usedSleepTherapy || actual.hasSleepEnvironment, file: file, line: line)
        XCTAssertFalse(actual.hadSleepParalysis || actual.hadHallucinations || actual.hadAutomaticBehavior || actual.fellOutOfBed || actual.hadConfusionOnWaking, file: file, line: line)
        XCTAssertNil(actual.physicalSymptomsJson, file: file, line: line)
        XCTAssertNil(actual.sleepTherapyJson, file: file, line: line)
        XCTAssertNil(actual.sleepEnvironmentJson, file: file, line: line)
        XCTAssertTrue(model.stressNotes.isEmpty && model.coMedicationNotes.isEmpty && model.sleepTherapyNotes.isEmpty && model.sleepEnvironmentNotes.isEmpty, file: file, line: line)
        XCTAssertFalse(model.hasClinicalContext, file: file, line: line)
    }
}

@MainActor
final class DashboardStressTrendTests: XCTestCase {
    func test_stressTrendAnalytics_captureCarryoverAndHighStressImpact() throws {
        let model = DashboardAnalyticsModel()
        model.selectedRange = .all
        model.nights = [
            makeNight(
                sessionDate: "2026-01-12",
                bedtimeStress: 5,
                bedtimeDrivers: [.work],
                wakeStress: 4,
                wakeDrivers: [.financial],
                sleepQuality: 3,
                readiness: 3,
                intervalMinutes: 180
            ),
            makeNight(
                sessionDate: "2026-01-11",
                bedtimeStress: 2,
                bedtimeDrivers: [.relationship],
                wakeStress: 1,
                wakeDrivers: [],
                sleepQuality: 4,
                readiness: 4,
                intervalMinutes: 170
            ),
            makeNight(
                sessionDate: "2026-01-10",
                bedtimeStress: 4,
                bedtimeDrivers: [.work, .health],
                wakeStress: 5,
                wakeDrivers: [.work],
                sleepQuality: 2,
                readiness: 2,
                intervalMinutes: 210
            )
        ]

        XCTAssertEqual(model.stressTrendNightCount, 3)
        XCTAssertEqual(model.topRecurringStressDriver, .work)
        XCTAssertEqual(model.topCarryoverStressDriver, .work)
        XCTAssertEqual(model.recurringStressDrivers.first?.totalCount, 2)
        XCTAssertEqual(model.recurringStressDrivers.first?.carryoverCount, 1)
        XCTAssertEqual(model.stressCarryoverNightRate ?? 0, 50, accuracy: 0.01)
        XCTAssertEqual(model.sleepQualityByHighBedtimeStress.high ?? 0, 2.5, accuracy: 0.01)
        XCTAssertEqual(model.sleepQualityByHighBedtimeStress.lower ?? 0, 4.0, accuracy: 0.01)
        XCTAssertEqual(model.readinessByHighBedtimeStress.high ?? 0, 2.5, accuracy: 0.01)
        XCTAssertEqual(model.readinessByHighBedtimeStress.lower ?? 0, 4.0, accuracy: 0.01)
        XCTAssertEqual(model.intervalByHighBedtimeStress.high ?? 0, 195, accuracy: 0.01)
        XCTAssertEqual(model.intervalByHighBedtimeStress.lower ?? 0, 170, accuracy: 0.01)
    }

    private func makeNight(
        sessionDate: String,
        bedtimeStress: Int,
        bedtimeDrivers: [CommonStressDriver],
        wakeStress: Int,
        wakeDrivers: [CommonStressDriver],
        sleepQuality: Double,
        readiness: Int,
        intervalMinutes: Int
    ) -> DashboardNightAggregate {
        let baseDate = AppFormatters.sessionDate.date(from: sessionDate) ?? Date()
        return DashboardNightAggregate(
            sessionDate: sessionDate,
            dose1Time: baseDate,
            dose2Time: baseDate.addingTimeInterval(TimeInterval(intervalMinutes * 60)),
            dose2Skipped: false,
            snoozeCount: 0,
            extraDoseCount: 0,
            events: [],
            morningCheckIn: makeMorningCheckIn(
                sessionDate: sessionDate,
                timestamp: baseDate.addingTimeInterval(8 * 60 * 60),
                sleepQuality: sleepQuality,
                readiness: readiness,
                stressLevel: wakeStress,
                stressDrivers: wakeDrivers
            ),
            preSleepLog: makePreSleepLog(
                sessionDate: sessionDate,
                timestamp: baseDate,
                stressLevel: bedtimeStress,
                stressDrivers: bedtimeDrivers
            ),
            healthSummary: nil,
            whoopSummary: nil,
            duplicateClusterCount: 0,
            napSummary: SessionRepository.NapSummary(count: 0, totalMinutes: 0)
        )
    }

    private func makePreSleepLog(
        sessionDate: String,
        timestamp: Date,
        stressLevel: Int,
        stressDrivers: [CommonStressDriver]
    ) -> DoseTap.StoredPreSleepLog {
        DoseTap.StoredPreSleepLog(
            id: "pre-\(sessionDate)",
            sessionId: sessionDate,
            createdAtUtc: ISO8601DateFormatter().string(from: timestamp),
            localOffsetMinutes: 0,
            completionState: "complete",
            answers: DoseTap.PreSleepLogAnswers(
                stressLevel: stressLevel,
                stressDrivers: stressDrivers
            )
        )
    }

    private func makeMorningCheckIn(
        sessionDate: String,
        timestamp: Date,
        sleepQuality: Double,
        readiness: Int,
        stressLevel: Int,
        stressDrivers: [CommonStressDriver]
    ) -> DoseTap.StoredMorningCheckIn {
        DoseTap.StoredMorningCheckIn(
            id: "morning-\(sessionDate)",
            sessionId: sessionDate,
            timestamp: timestamp,
            sessionDate: sessionDate,
            sleepQuality: sleepQuality,
            stressLevel: stressLevel,
            stressContextJson: stressDrivers.isEmpty ? nil : stressContextJson(drivers: stressDrivers),
            readinessForDay: readiness
        )
    }

    private func stressContextJson(drivers: [CommonStressDriver]) -> String {
        let payload: [String: Any] = [
            "drivers": drivers.map(\.rawValue),
            "progression": CommonStressProgression.same.rawValue,
            "notes": ""
        ]
        let data = try? JSONSerialization.data(withJSONObject: payload)
        return String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }
}

@MainActor
final class DashboardDoseIntegrityMetricTests: XCTestCase {
    func test_missingDose2OutcomesAreVisibleAndExcludedOnlyFromRecordedOnTimeRate() {
        let model = DashboardAnalyticsModel()
        model.selectedRange = .all
        model.nights = [
            makeNight(sessionDate: "2026-08-29", intervalMinutes: 180),
            makeNight(sessionDate: "2026-08-28", intervalMinutes: 260),
            makeNight(sessionDate: "2026-08-27", intervalMinutes: nil)
        ]

        XCTAssertEqual(model.eligibleDose2OutcomeCount, 3)
        XCTAssertEqual(model.recordedDose2OutcomeCount, 2)
        XCTAssertEqual(model.missingDose2OutcomeCount, 1)
        XCTAssertEqual(model.onTimePercentage ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(model.completionRate ?? 0, 200.0 / 3.0, accuracy: 0.001)
    }

    func test_timeZoneLabelIncludesIdentifierAndDateSpecificOffset() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let summer = try XCTUnwrap(AppFormatters.parseISO8601Flexible("2026-08-29T12:00:00Z"))

        XCTAssertEqual(
            AppFormatters.timeZoneLabel(timeZone: timeZone, at: summer),
            "America/New_York (UTC-04:00)"
        )
    }

    private func makeNight(sessionDate: String, intervalMinutes: Int?) -> DashboardNightAggregate {
        let dose1 = AppFormatters.sessionDate.date(from: sessionDate) ?? Date()
        return DashboardNightAggregate(
            sessionDate: sessionDate,
            dose1Time: dose1,
            dose2Time: intervalMinutes.map { dose1.addingTimeInterval(TimeInterval($0 * 60)) },
            dose2Skipped: false,
            snoozeCount: 0,
            extraDoseCount: 0,
            events: [],
            morningCheckIn: nil,
            preSleepLog: nil,
            healthSummary: nil,
            whoopSummary: nil,
            duplicateClusterCount: 0,
            napSummary: SessionRepository.NapSummary(count: 0, totalMinutes: 0)
        )
    }
}
