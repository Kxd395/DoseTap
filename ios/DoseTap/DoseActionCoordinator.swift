import Foundation
import DoseCore
import os.log
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit)
import UIKit
import AudioToolbox
#endif

private let coordinatorLog = Logger(subsystem: "com.dosetap.app", category: "DoseActionCoordinator")

// MARK: - Dose Action Coordinator
/// P0-4: Single entry point for all dose actions across every surface
/// (CompactDoseButton, DoseButtonsSection, FlicButtonService, URLRouter).
///
/// Centralises: validation → confirmation routing → persistence →
/// alarm scheduling → event logging → undo registration.
///
/// Surfaces call coordinator methods and handle the returned `ActionResult`:
///   .success        → update UI with feedback
///   .attentionRequired → dose committed, but a follow-up safety effect needs retry
///   .needsConfirm   → show confirmation dialog, then call again with override
///   .blocked        → show reason to user
///
@available(iOS 15.0, *)
@MainActor
final class DoseActionCoordinator: ObservableObject {

    // MARK: - Dependencies (injected by the app root)

    let core: DoseTapCore
    let alarmService: AlarmService
    let dateProvider: any DateProviding
    var eventLogger: EventLogger?
    var undoState: UndoStateManager?
    var sessionRepo: SessionRepository?
    var hapticObserver: ((FeedbackIntensity) -> Void)?
    private var pendingDose2Confirmation: Dose2Confirmation?
    private var pendingDose1Review: Dose1Review?
    private var dose1ReviewGeneration = 0
    private var dose1ReviewInFlight = false
    private(set) var savedDose1Review: (reviewId: UUID, sessionId: String, occurrence: Date, recordedAt: Date)?

    struct Dose1Review: Equatable, Identifiable {
        let id = UUID()
        fileprivate let sessionId: String?
        fileprivate let sessionDate: String
        fileprivate let generation: Int
        fileprivate let surface: RegistrationSurface
    }

    func prepareDose1Review(surface: RegistrationSurface = .tonightButton) -> Dose1Review? {
        guard !dose1ReviewInFlight, let repo = sessionRepo else { return nil }
        repo.refreshForTimeChange()
        guard repo.dose1Time == nil else { return nil }
        dose1ReviewGeneration += 1
        let review = Dose1Review(sessionId: repo.activeSessionId, sessionDate: repo.currentSessionKey,
            generation: dose1ReviewGeneration, surface: surface)
        pendingDose1Review = review
        return review
    }

    func cancelDose1Review(_ review: Dose1Review? = nil) {
        if review == nil || pendingDose1Review == review {
            pendingDose1Review = nil
            dose1ReviewGeneration += 1
        }
    }

    func prepareDose1ReviewForRetry(_ original: Dose1Review) -> Dose1Review? {
        guard let repo = sessionRepo else { return nil }
        repo.refreshForTimeChange()
        guard repo.activeSessionId == original.sessionId, repo.currentSessionKey == original.sessionDate else { return nil }
        return prepareDose1Review(surface: original.surface)
    }

    private func dose1ReviewMatches(_ review: Dose1Review) -> Bool {
        guard let repo = sessionRepo else { return false }
        repo.refreshForTimeChange()
        return review.generation == dose1ReviewGeneration && repo.activeSessionId == review.sessionId
            && repo.currentSessionKey == review.sessionDate && repo.dose1Time == nil
    }

    func confirmDose1(_ review: Dose1Review, occurrence: Date? = nil, targetMinutes: Int,
                      remember: Bool = false) async -> ActionResult {
        guard pendingDose1Review == review, dose1ReviewMatches(review) else {
            return .blocked(reason: "This Dose 1 review expired. Cancel and review the current night again.")
        }
        pendingDose1Review = nil
        dose1ReviewInFlight = true
        defer { dose1ReviewInFlight = false }
        let now = dateProvider.now()
        let taken = occurrence ?? now
        guard UserSettingsManager.shared.validTargetOptions.contains(targetMinutes),
              taken.timeIntervalSince1970.isFinite, taken <= now,
              sessionRepo?.dose1OccurrenceIsInCurrentNight(taken) == true else {
            return .blocked(reason: "Choose a recorded time in this treatment night, no later than now, and an available reminder interval. Use History for another night.")
        }
        return await commitDose1(surface: review.surface, occurrence: taken, recordedAt: now,
            targetMinutes: targetMinutes, remember: remember, review: review)
    }

    func retryDose1Alarm(sessionId: String, dose1: Date, targetMinutes: Int) async -> ActionResult {
        guard UserSettingsManager.shared.validTargetOptions.contains(targetMinutes),
              dose1AlarmStillApplies(sessionId: sessionId, dose1: dose1) else {
            return .blocked(reason: "The dose or session changed. Review tonight before changing its alarm.")
        }
        let wake = await alarmService.scheduleDose2Alarm(at: dose1.addingTimeInterval(Double(targetMinutes) * 60), dose1Time: dose1)
        guard dose1AlarmStillApplies(sessionId: sessionId, dose1: dose1) else {
            return .blocked(reason: "The dose or session changed during alarm setup.")
        }
        let reminders = await alarmService.scheduleDose2Reminders(dose1Time: dose1)
        guard dose1AlarmStillApplies(sessionId: sessionId, dose1: dose1) else {
            return .blocked(reason: "The dose or session changed during alarm setup.")
        }
        let failures = [wake, reminders].compactMap(\.failure)
        if !failures.isEmpty { return .attentionRequired(message: failures.map(\.userMessage).joined(separator: " ")) }
        guard alarmService.alarmScheduled else { return .attentionRequired(message: "Dose 1 is recorded. The Dose 2 alarm is not enabled or no future alarm is scheduled.") }
        return .success(message: "Dose 2 alarm scheduled. Dose 1 was not changed.")
    }

    private func dose1AlarmStillApplies(sessionId: String, dose1: Date) -> Bool {
        guard let repo = sessionRepo else { return false }
        repo.refreshForTimeChange()
        return repo.activeSessionId == sessionId && repo.dose1Time.map { abs($0.timeIntervalSince(dose1)) < 0.001 } == true
            && repo.dose2Time == nil && !repo.dose2Skipped && !repo.checkInCompleted
    }

    // MARK: - Result Types

    enum ActionResult: Equatable {
        case success(message: String)
        case attentionRequired(message: String)
        case retryRequired(message: String)
        case needsConfirm(ConfirmationType)
        case blocked(reason: String)
    }

    enum ConfirmationType: Equatable {
        case dose1Record(Dose1Review)
        case dose2Record(Dose2Confirmation)
        /// Window not open yet - tell user how many minutes remain
        case workWake(WorkWakeWarning)
        case earlyDose(minutesRemaining: Int)
        /// A reported occurrence is outside the configured timing window.
        case outsideWindowOccurrence
        /// Dose 2 was skipped; user wants to un-skip
        case afterSkip
        /// Dose 2 already recorded; this would be a 3rd+ dose
        case extraDose
    }

    enum DoseOverride: Equatable {
        case none
        case earlyConfirmed
        case extraDoseConfirmed
    }

    /// A one-use intent challenge, never a saved dose or an alarm timestamp.
    struct Dose2Confirmation: Equatable, Identifiable {
        let id = UUID()
        fileprivate let sessionId: String
        fileprivate let dose1Time: Date
        fileprivate let override: DoseOverride
        fileprivate let workWarning: WorkWakeWarning?
        fileprivate let reason: String?
        fileprivate let reasonNotes: String?
        fileprivate let surface: RegistrationSurface
    }

    // MARK: - Init

    init(
        core: DoseTapCore,
        alarmService: AlarmService,
        dateProvider: any DateProviding = SystemDateProvider(),
        eventLogger: EventLogger? = nil,
        undoState: UndoStateManager? = nil,
        sessionRepo: SessionRepository? = nil
    ) {
        self.core = core
        self.alarmService = alarmService
        self.dateProvider = dateProvider
        self.eventLogger = eventLogger
        self.undoState = undoState
        self.sessionRepo = sessionRepo
    }

    // MARK: - Take Dose 1

    func takeDose1(surface: RegistrationSurface = .tonightButton) async -> ActionResult {
        guard let review = prepareDose1Review(surface: surface) else {
            return .blocked(reason: "Dose 1 cannot be started here. Review the current session.")
        }
        return .needsConfirm(.dose1Record(review))
    }

    private func commitDose1(surface: RegistrationSurface, occurrence: Date? = nil, recordedAt: Date? = nil,
                             targetMinutes: Int? = nil, remember: Bool = false, review: Dose1Review? = nil) async -> ActionResult {
        let sig = DoseSignpost.begin(.takeDose1)
        defer { DoseSignpost.end(.takeDose1, sig) }

        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let decisionTime = occurrence ?? dateProvider.now()
        switch DoseRegistrationPolicy.evaluateDose1(
            input: registrationInput(surface: surface, at: decisionTime),
            at: decisionTime
        ) {
        case .allowed:
            break
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }

        let diagnosticActionId = UUID().uuidString
        let diagnosticSessionId = sessionRepo.currentSessionIdString()
        await DiagnosticLogger.shared.logDoseAction(
            .doseActionAttempted,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "dose1",
            surface: surface.rawValue
        )
        if let review, !dose1ReviewMatches(review) {
            return .blocked(reason: "The session changed. Review Dose 1 again before saving.")
        }
        var metadata: String?
        if let recordedAt, let targetMinutes {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let values: [String: Any] = ["source": surface.rawValue,
                "recorded_at_utc": formatter.string(from: recordedAt), "reminder_interval_minutes": targetMinutes]
            guard let data = try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys) else {
                return .blocked(reason: "Dose details could not be prepared. Review and retry.")
            }
            metadata = String(decoding: data, as: UTF8.self)
        }
        let mutationResult = sessionRepo.setDose1Time(decisionTime, metadata: metadata)
        if mutationResult.isCommitted, let review, let sessionId = sessionRepo.activeSessionId {
            savedDose1Review = (review.id, sessionId, decisionTime, recordedAt ?? decisionTime)
        }
        await logDoseMutationResult(
            mutationResult,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "dose1",
            surface: surface
        )
        guard mutationResult.isCommitted else {
            return retryResult(
                mutationResult,
                action: "Dose 1"
            )
        }

        guard let committedSession = mutationResult.receipt?.sessionId,
              dose1AlarmStillApplies(sessionId: committedSession, dose1: decisionTime) else {
            return .attentionRequired(message: "Dose 1 was logged. The session changed before alarm setup; review tonight.")
        }
        // Event log
        eventLogger?.logEvent(
            name: "Dose 1", color: .green,
            cooldownSeconds: 3600 * 8, persist: false
        )

        // Undo
        undoState?.register(.takeDose1(at: decisionTime))

        // Schedule alarms
        let selectedTarget = targetMinutes ?? UserSettingsManager.shared.targetIntervalMinutes
        let target = UserSettingsManager.shared.validTargetOptions.contains(selectedTarget) ? selectedTarget : 165
        if remember { UserSettingsManager.shared.targetIntervalMinutes = target }
        let wakeTime = decisionTime.addingTimeInterval(Double(target) * 60)
        let wakeResult = await alarmService.scheduleDose2Alarm(
            at: wakeTime,
            dose1Time: decisionTime
        )
        guard dose1AlarmStillApplies(sessionId: committedSession, dose1: decisionTime) else {
            return .attentionRequired(message: "Dose 1 was logged. The session changed during alarm setup; review tonight.")
        }
        let reminderResult = await alarmService.scheduleDose2Reminders(
            dose1Time: decisionTime
        )
        guard dose1AlarmStillApplies(sessionId: committedSession, dose1: decisionTime) else {
            return .attentionRequired(message: "Dose 1 was logged. The session changed during reminder setup; review tonight.")
        }

        playHaptic(.dose)
        playConfirmationSound()
        coordinatorLog.info("Dose 1 logged via coordinator from \(surface.rawValue, privacy: .public)")
        let schedulingFailures = [wakeResult, reminderResult].compactMap(\.failure)
        if !schedulingFailures.isEmpty {
            let messages = Array(Set(schedulingFailures.map(\.userMessage))).sorted()
            coordinatorLog.error("Dose 1 committed, but notification scheduling needs retry")
            return .attentionRequired(
                message: "Dose 1 was logged. \(messages.joined(separator: " "))"
            )
        }
        return .success(message: "✓ Dose 1 logged")
    }

    // MARK: - Take Dose 2

    /// Historical writes are not live-dose commands. Only a matching active
    /// night's existing alarm state is reconciled after the record commits.
    func saveHistoryDoseChange(_ change: HistoryDoseChange, review: HistoryRecordSnapshot,
                               confirmed: Bool, warningConfirmed: Bool) async -> ActionResult {
        guard let repo = sessionRepo else { return .blocked(reason: "Session store unavailable") }
        let wasActive = repo.activeSessionId == review.sessionId
        if wasActive { await undoState?.invalidateForHistoryReview() }
        let result = repo.applyHistoryDoseChange(change, review: review, confirmed: confirmed, warningConfirmed: warningConfirmed)
        guard result.isCommitted else { return .retryRequired(message: result.failure?.detail ?? "History was not saved.") }
        guard wasActive else { return .success(message: "History record saved") }
        cancelDose2Confirmation()
        undoState?.dismiss()
        alarmService.cancelAllAlarms()
        guard repo.activeSessionId == review.sessionId, let first = repo.dose1Time,
              repo.dose2Time == nil, !repo.dose2Skipped else {
            if let error = alarmService.lastSchedulingError { return .attentionRequired(message: "History saved. \(error)") }
            return .success(message: "History record saved")
        }
        let target = first.addingTimeInterval(Double(repo.activeDoseTargetMinutes) * 60)
        var failures: [String] = []
        if target > dateProvider.now() {
            let wake = await alarmService.scheduleDose2Alarm(at: target, dose1Time: first)
            if let failure = wake.failure { failures.append(failure.userMessage) }
        }
        guard repo.activeSessionId == review.sessionId, repo.dose1Time == first,
              repo.dose2Time == nil, !repo.dose2Skipped else {
            return .attentionRequired(message: "History saved. The active session changed during alarm reconciliation; review Tonight.")
        }
        let reminders = await alarmService.scheduleDose2Reminders(dose1Time: first)
        if let failure = reminders.failure { failures.append(failure.userMessage) }
        if !failures.isEmpty { return .attentionRequired(message: "History saved. \(failures.joined(separator: " "))") }
        if target <= dateProvider.now() {
            return .attentionRequired(message: "History saved. The original alarm time is past and was not replayed. Review Tonight's alarm status.")
        }
        return .success(message: "History saved and remaining reminders updated")
    }

    func takeDose2(
        override: DoseOverride = .none,
        acknowledgedWorkWarning: WorkWakeWarning? = nil,
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface = .tonightButton,
        wakeMethod: Dose2WakeKind? = nil
    ) async -> ActionResult {
        // Bind the challenge to canonical persisted precision, not the
        // sub-millisecond Date still in memory immediately after Dose 1.
        sessionRepo?.refreshForTimeChange()
        return await evaluateDose2(
            override: override, acknowledgedWorkWarning: acknowledgedWorkWarning,
            reason: reason, reasonNotes: reasonNotes, surface: surface,
            explicitlyConfirmed: false, wakeMethod: wakeMethod
        )
    }

    func cancelDose2Confirmation(_ confirmation: Dose2Confirmation? = nil) {
        if confirmation == nil || pendingDose2Confirmation == confirmation {
            pendingDose2Confirmation = nil
        }
    }

    func confirmDose2(_ confirmation: Dose2Confirmation, wakeMethod: Dose2WakeKind? = nil) async -> ActionResult {
        guard pendingDose2Confirmation == confirmation else {
            return .blocked(reason: "This confirmation expired. Reopen Record Dose 2 and review it again.")
        }
        // Consume before any suspension: duplicate taps cannot replay consent.
        pendingDose2Confirmation = nil
        sessionRepo?.refreshForTimeChange()
        guard let repository = sessionRepo,
              repository.activeSessionId == confirmation.sessionId,
              repository.dose1Time == confirmation.dose1Time,
              repository.dose2Time == nil, !repository.dose2Skipped else {
            return .blocked(reason: "The session changed. Review the current record before confirming Dose 2.")
        }
        return await evaluateDose2(
            override: confirmation.override,
            acknowledgedWorkWarning: confirmation.workWarning,
            reason: confirmation.reason, reasonNotes: confirmation.reasonNotes,
            surface: confirmation.surface, explicitlyConfirmed: true, wakeMethod: wakeMethod
        )
    }

    private func evaluateDose2(
        override: DoseOverride,
        acknowledgedWorkWarning: WorkWakeWarning?,
        reason: String?,
        reasonNotes: String?,
        surface: RegistrationSurface,
        explicitlyConfirmed: Bool,
        wakeMethod: Dose2WakeKind? = nil
    ) async -> ActionResult {
        let sig = DoseSignpost.begin(.takeDose2, "override=\(override),surface=\(surface.rawValue)")
        defer { DoseSignpost.end(.takeDose2, sig) }

        guard sessionRepo != nil else {
            return .blocked(reason: "Session store unavailable")
        }

        let decisionTime = dateProvider.now()
        let input = registrationInput(surface: surface, at: decisionTime)
        let phase = input.windowPhase
        let overrideConfirmed = override != .none

        switch DoseRegistrationPolicy.evaluateDose2(
            input: input,
            at: decisionTime,
            overrideConfirmed: overrideConfirmed
        ) {
        case .allowed:
            var workWarning: WorkWakeWarning?
            if input.dose2Time == nil, let first = input.dose1Time, let repo = sessionRepo,
               let identity = repo.activeSessionId, let sessionDate = repo.activeSessionDate {
                do {
                    workWarning = try repo.workWakeSchedule().warning(sessionId: identity, sessionDate: sessionDate, dose1: first, now: decisionTime, doseTargetMinutes: repo.activeDoseTargetMinutes)
                } catch {
                    return .retryRequired(message: "Your work schedule could not be read. Review it in Weekly Schedule and retry.")
                }
                if let warning = workWarning, warning != acknowledgedWorkWarning { return .needsConfirm(.workWake(warning)) }
            }
            if input.dose2Time != nil {
                guard override == .extraDoseConfirmed else {
                    return .needsConfirm(.extraDose)
                }
                return await performExtraDose(
                    at: decisionTime,
                    reason: reason,
                    reasonNotes: reasonNotes,
                    surface: surface
                )
            }
            // The early path already has a warning and an explicit hold-to-confirm
            // screen. Ordinary in-window requests have no such consent yet.
            if !explicitlyConfirmed && override != .earlyConfirmed {
                guard let sessionId = sessionRepo?.activeSessionId, let firstDose = input.dose1Time else {
                    return .blocked(reason: "Reload the current session before recording Dose 2.")
                }
                let confirmation = Dose2Confirmation(
                    sessionId: sessionId, dose1Time: firstDose, override: override,
                    workWarning: workWarning, reason: reason, reasonNotes: reasonNotes,
                    surface: surface
                )
                pendingDose2Confirmation = confirmation
                return .needsConfirm(.dose2Record(confirmation))
            }
            if phase == .beforeWindow {
                guard override == .earlyConfirmed else {
                    return .needsConfirm(
                        .earlyDose(minutesRemaining: remainingMinutesToWindowOpen(at: decisionTime))
                    )
                }
                return await performDose2(
                    at: decisionTime,
                    eventName: "Dose 2 (Early)",
                    isLate: false,
                    isEarly: true,
                    reason: reason,
                    reasonNotes: reasonNotes,
                    surface: surface, wakeMethod: wakeMethod
                )
            }
            return await performDose2(
                at: decisionTime,
                eventName: "Dose 2",
                isLate: false,
                workWarning: workWarning,
                reason: reason,
                reasonNotes: reasonNotes,
                surface: surface, wakeMethod: wakeMethod
            )
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }
    }

    /// Record a Dose 2 occurrence that the user confirms already happened.
    /// This is deliberately separate from `takeDose2`: an outside-window record
    /// preserves history without presenting the app as permission to take a dose now.
    func recordDose2Occurrence(
        at occurrenceTime: Date,
        warningConfirmed: Bool = false,
        acknowledgedWorkWarning: WorkWakeWarning? = nil,
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface = .tonightButton,
        wakeMethod: Dose2WakeKind? = nil
    ) async -> ActionResult {
        guard sessionRepo != nil else {
            return .blocked(reason: "Session store unavailable")
        }

        let decisionTime = dateProvider.now()
        let input = registrationInput(surface: surface, at: decisionTime)

        switch DoseRegistrationPolicy.evaluateRetrospectiveDose2(
            input: input,
            occurrenceTime: occurrenceTime,
            decisionTime: decisionTime,
            warningConfirmed: warningConfirmed
        ) {
        case .allowed:
            guard let dose1Time = input.dose1Time else {
                return .blocked(reason: "Add the missing Dose 1 record first")
            }
            var workWarning: WorkWakeWarning?
            if let repo = sessionRepo, let identity = repo.activeSessionId, let sessionDate = repo.activeSessionDate {
                do {
                    workWarning = try repo.workWakeSchedule().warning(sessionId: identity, sessionDate: sessionDate, dose1: dose1Time, now: occurrenceTime, doseTargetMinutes: repo.activeDoseTargetMinutes, retrospective: true)
                } catch {
                    return .retryRequired(message: "Your work schedule could not be read. Review it in Weekly Schedule and retry.")
                }
                if let warning = workWarning, warning != acknowledgedWorkWarning { return .needsConfirm(.workWake(warning)) }
            }
            let interval = occurrenceTime.timeIntervalSince(dose1Time)
            let config = DoseCore.DoseWindowConfig()
            let timing = MedicationTiming.classify(elapsedSeconds: interval, config: config)
            let isEarly = timing == .early
            let isLate = timing == .late
            let eventName: String
            if isEarly {
                eventName = "Dose 2 (Early, Recorded Later)"
            } else if isLate {
                eventName = "Dose 2 (Late, Recorded Later)"
            } else {
                eventName = "Dose 2 (Recorded Later)"
            }
            return await performDose2(
                at: occurrenceTime,
                eventName: eventName,
                isLate: isLate,
                workWarning: workWarning,
                isEarly: isEarly,
                entryMode: .retrospective,
                recordedAt: decisionTime,
                reason: reason,
                reasonNotes: reasonNotes,
                surface: surface, wakeMethod: wakeMethod
            )
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }
    }

    // MARK: - Snooze

    func snooze(surface: RegistrationSurface = .tonightButton) async -> ActionResult {
        let sig = DoseSignpost.begin(.snooze)
        defer { DoseSignpost.end(.snooze, sig) }

        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let decisionTime = dateProvider.now()
        switch DoseRegistrationPolicy.evaluateSnooze(
            input: registrationInput(surface: surface, at: decisionTime),
            at: decisionTime
        ) {
        case .allowed:
            break
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }

        guard let dose1Time = sessionRepo.dose1Time else {
            return .blocked(reason: "Take Dose 1 first")
        }

        let snoozeMutation = sessionRepo.incrementSnoozeMutationIfActive()
        guard snoozeMutation.isCommitted else {
            return retryResult(snoozeMutation, action: "Snooze")
        }

        guard let newTime = await alarmService.snoozeAlarm(dose1Time: dose1Time) else {
            let rollbackResult = sessionRepo.decrementSnoozeCount()
            if !rollbackResult.isCommitted {
                return retryResult(
                    rollbackResult,
                    action: "Snooze rollback"
                )
            }
            return .blocked(reason: "No alarm available to snooze")
        }

        undoState?.register(.snooze(minutes: alarmService.snoozeDurationMinutes))
        let formatted = newTime.formatted(date: .omitted, time: .shortened)
        coordinatorLog.info("Snoozed to \(formatted, privacy: .public) from \(surface.rawValue, privacy: .public)")
        playHaptic(.action)
        return .success(message: "✓ Snoozed to \(formatted)")
    }

    // MARK: - Skip Dose

    func skipDose(
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface = .tonightButton
    ) async -> ActionResult {
        let sig = DoseSignpost.begin(.skipDose)
        defer { DoseSignpost.end(.skipDose, sig) }

        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let decisionTime = dateProvider.now()
        switch DoseRegistrationPolicy.evaluateSkip(
            input: registrationInput(surface: surface, at: decisionTime),
            at: decisionTime
        ) {
        case .allowed:
            break
        case .requiresConfirmation(let type):
            return .needsConfirm(mapConfirmation(type))
        case .blocked(let reason):
            return .blocked(reason: reason)
        }

        let diagnosticActionId = UUID().uuidString
        let diagnosticSessionId = sessionRepo.currentSessionIdString()
        await DiagnosticLogger.shared.logDoseAction(
            .doseActionAttempted,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "dose2_skip",
            surface: surface.rawValue
        )
        let mutationResult = sessionRepo.skipDose2(
            reason: reason,
            reasonNotes: reasonNotes,
            surface: surface
        )
        await logDoseMutationResult(
            mutationResult,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "dose2_skip",
            surface: surface
        )
        guard mutationResult.isCommitted else {
            return retryResult(mutationResult, action: "Dose 2 skip")
        }
        let reminders = await alarmService.completeDose2Reminders(
            sessionId: mutationResult.receipt?.sessionId ?? diagnosticSessionId,
            activeSessionId: { sessionRepo.activeSessionId })

        eventLogger?.logEvent(
            name: "Skip Dose 2", color: .orange,
            cooldownSeconds: 3600 * 8, persist: false
        )

        undoState?.register(.skipDose(sequence: 2, reason: reason))
        playHaptic(.action)

        coordinatorLog.info("Dose 2 skipped via coordinator from \(surface.rawValue, privacy: .public)")
        if let warning = reminders.warning { return .attentionRequired(message: "Dose 2 skipped (not taken). \(warning)") }
        return .success(message: reminders == .cancelled ? "Dose 2 skipped. Dose reminders cancelled." : "Dose 2 skipped.")
    }

    // MARK: - Private Helpers

    private func performDose2(
        at decisionTime: Date,
        eventName: String,
        isLate: Bool,
        workWarning: WorkWakeWarning? = nil,
        isEarly: Bool = false,
        entryMode: DoseEntryMode = .prospective,
        recordedAt: Date? = nil,
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface,
        wakeMethod: Dose2WakeKind? = nil
    ) async -> ActionResult {
        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let diagnosticActionId = UUID().uuidString
        let diagnosticSessionId = sessionRepo.currentSessionIdString()
        let diagnosticAction = isEarly ? "dose2_early" : (isLate ? "dose2_late" : "dose2")
        await DiagnosticLogger.shared.logDoseAction(
            .doseActionAttempted,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: diagnosticAction,
            surface: surface.rawValue
        )
        let mutationResult = sessionRepo.setDose2Time(
            decisionTime,
            isEarly: isEarly,
            isExtraDose: false,
            entryMode: entryMode,
            workWarning: workWarning,
            recordedAt: recordedAt ?? decisionTime,
            surface: surface,
            reason: reason,
            reasonNotes: reasonNotes, wakeMethod: wakeMethod
        )
        await logDoseMutationResult(
            mutationResult,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: diagnosticAction,
            surface: surface
        )
        guard mutationResult.isCommitted else {
            return retryResult(mutationResult, action: eventName)
        }

        let reminders = await alarmService.completeDose2Reminders(
            sessionId: mutationResult.receipt?.sessionId ?? diagnosticSessionId,
            activeSessionId: { sessionRepo.activeSessionId })

        eventLogger?.logEvent(
            name: eventName,
            color: isLate ? .orange : .green,
            cooldownSeconds: 3600 * 8,
            persist: false
        )

        undoState?.register(.takeDose2(at: decisionTime))

        playHaptic(.dose)
        playConfirmationSound()

        coordinatorLog.info("\(eventName, privacy: .public) logged via coordinator")
        if let warning = reminders.warning { return .attentionRequired(message: "\(eventName) recorded. \(warning) Do not log the dose again.") }
        return .success(message: reminders == .cancelled ? "\(eventName) recorded. Dose reminders cancelled." : "\(eventName) recorded.")
    }

    private func performExtraDose(
        at decisionTime: Date,
        reason: String? = nil,
        reasonNotes: String? = nil,
        surface: RegistrationSurface
    ) async -> ActionResult {
        guard let sessionRepo else {
            return .blocked(reason: "Session store unavailable")
        }

        let diagnosticActionId = UUID().uuidString
        let diagnosticSessionId = sessionRepo.currentSessionIdString()
        await DiagnosticLogger.shared.logDoseAction(
            .doseActionAttempted,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "extra_dose",
            surface: surface.rawValue
        )
        let mutationResult = sessionRepo.setDose2Time(
            decisionTime,
            isEarly: false,
            isExtraDose: true,
            reason: reason,
            reasonNotes: reasonNotes
        )
        await logDoseMutationResult(
            mutationResult,
            sessionId: diagnosticSessionId,
            actionId: diagnosticActionId,
            action: "extra_dose",
            surface: surface
        )
        guard mutationResult.isCommitted else {
            return retryResult(mutationResult, action: "Extra dose")
        }

        eventLogger?.logEvent(
            name: "Extra Dose",
            color: .red,
            cooldownSeconds: 0,
            persist: false
        )

        playHaptic(.dose)
        playConfirmationSound()
        coordinatorLog.warning("Extra dose logged via coordinator after explicit confirmation")
        return .success(message: "Extra dose logged")
    }

    private func registrationInput(
        surface: RegistrationSurface,
        at decisionTime: Date
    ) -> DoseRegistrationInput {
        let dose1Time = sessionRepo?.dose1Time
        let dose2Time = sessionRepo?.dose2Time
        let dose2Skipped = sessionRepo?.dose2Skipped ?? false
        let snoozeCount = sessionRepo?.snoozeCount ?? 0
        let context = DoseWindowCalculator(now: { decisionTime }).context(
            dose1At: dose1Time,
            dose2TakenAt: dose2Time,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount,
            wakeFinalAt: sessionRepo?.wakeFinalTime,
            checkInCompleted: sessionRepo?.checkInCompleted ?? false
        )
        return DoseRegistrationInput(
            dose1Time: dose1Time,
            dose2Time: dose2Time,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount,
            windowPhase: context.phase,
            surface: surface
        )
    }

    private func logDoseMutationResult(
        _ result: MedicationMutationResult,
        sessionId: String,
        actionId: String,
        action: String,
        surface: RegistrationSurface
    ) async {
        await DiagnosticLogger.shared.logDoseAction(
            result.isCommitted ? .doseActionCommitted : .doseActionFailed,
            sessionId: sessionId,
            actionId: actionId,
            action: action,
            surface: surface.rawValue,
            failureCode: result.failure?.code.rawValue
        )
    }

    private func retryResult(
        _ mutationResult: MedicationMutationResult,
        action: String
    ) -> ActionResult {
        guard let failure = mutationResult.failure else {
            return .retryRequired(
                message: "\(action) was not saved. Retry and confirm it appears before relying on it."
            )
        }
        coordinatorLog.error(
            "\(action, privacy: .public) persistence failed at \(failure.stage.rawValue, privacy: .public) with \(failure.code.rawValue, privacy: .public)"
        )
        return .retryRequired(message: failure.userMessage)
    }

    private func mapConfirmation(_ type: DoseConfirmationType) -> ConfirmationType {
        switch type {
        case .earlyDose(let minutesRemaining):
            return .earlyDose(minutesRemaining: minutesRemaining)
        case .outsideWindowOccurrence:
            return .outsideWindowOccurrence
        case .afterSkip:
            return .afterSkip
        case .extraDose:
            return .extraDose
        }
    }

    private func remainingMinutesToWindowOpen(at decisionTime: Date) -> Int {
        guard let dose1Time = sessionRepo?.dose1Time else { return 0 }
        let windowOpen = dose1Time.addingTimeInterval(150 * 60)
        let remaining = windowOpen.timeIntervalSince(decisionTime)
        return max(1, Int(ceil(remaining / 60)))
    }

    // MARK: - Sensory Feedback (P3-1, P3-2)

    /// Standard system sound for dose confirmation (subtle "tick").
    private static let confirmationSoundID: SystemSoundID = 1057

    enum FeedbackIntensity {
        case dose      // Dose taken - strongest
        case action    // Snooze / skip - medium
    }

    /// Haptic feedback respecting user preference. P3-1.
    private func playHaptic(_ intensity: FeedbackIntensity) {
        hapticObserver?(intensity)
        switch intensity {
        case .dose:   Haptics.doseTaken.play()
        case .action: Haptics.action.play()
        }
    }

    /// Audible confirmation respecting user preference. P3-2.
    private func playConfirmationSound() {
        #if canImport(AudioToolbox)
        guard UserSettingsManager.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(Self.confirmationSoundID)
        #endif
    }

}

// MARK: - Dose Action Result Presentation

@available(iOS 15.0, *)
struct DoseActionFeedback: Equatable {
    enum Kind: Equatable {
        case success
        case warning
        case blocked
    }

    let kind: Kind
    let title: String
    let message: String
    let systemImageName: String
}

@available(iOS 15.0, *)
struct DoseActionResultPresentation: Equatable {
    let feedback: DoseActionFeedback?
    let confirmation: DoseActionCoordinator.ConfirmationType?

    init(result: DoseActionCoordinator.ActionResult) {
        switch result {
        case .success(let message):
            feedback = DoseActionFeedback(
                kind: .success,
                title: "Dose action complete",
                message: message,
                systemImageName: "checkmark.circle.fill"
            )
            confirmation = nil
        case .attentionRequired(let message):
            feedback = DoseActionFeedback(
                kind: .warning,
                title: "Record saved; alarm needs attention",
                message: message,
                systemImageName: "exclamationmark.triangle.fill"
            )
            confirmation = nil
        case .retryRequired(let message):
            feedback = DoseActionFeedback(
                kind: .blocked,
                title: "Dose not saved — retry",
                message: message,
                systemImageName: "externaldrive.badge.exclamationmark"
            )
            confirmation = nil
        case .blocked(let reason):
            feedback = DoseActionFeedback(
                kind: .blocked,
                title: "Dose action blocked",
                message: reason,
                systemImageName: "exclamationmark.triangle.fill"
            )
            confirmation = nil
        case .needsConfirm(let type):
            feedback = nil
            confirmation = type
        }
    }
}

#if canImport(SwiftUI)
@available(iOS 15.0, *)
struct DoseActionFeedbackBanner: View {
    let feedback: DoseActionFeedback

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: feedback.systemImageName)
                .foregroundStyle(tint)
                .font(.headline)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                Text(feedback.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feedback.title). \(feedback.message)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var tint: Color {
        switch feedback.kind {
        case .success:
            return .green
        case .warning, .blocked:
            return .orange
        }
    }
}
#endif
