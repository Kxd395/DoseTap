import Foundation
import DoseCore
import os.log
#if canImport(SwiftUI)
import SwiftUI
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
///   .needsConfirm   → show confirmation dialog, then call again with override
///   .blocked        → show reason to user
///
@available(iOS 15.0, *)
@MainActor
final class DoseActionCoordinator: ObservableObject {

    // MARK: - Dependencies (injected by the app root)

    let core: DoseTapCore
    let alarmService: AlarmService
    var eventLogger: EventLogger?
    var undoState: UndoStateManager?
    var sessionRepo: SessionRepository?

    // MARK: - Result Types

    enum ActionResult: Equatable {
        case success(message: String)
        case needsConfirm(ConfirmationType)
        case blocked(reason: String)
    }

    enum ConfirmationType: Equatable {
        /// Window not open yet – tell user how many minutes remain
        case earlyDose(minutesRemaining: Int)
        /// 240-minute window has passed
        case lateDose
        /// Dose 2 was skipped; user wants to un-skip
        case afterSkip
        /// Dose 2 already recorded; this would be a 3rd+ dose
        case extraDose
    }

    enum DoseOverride: Equatable {
        case none
        case earlyConfirmed
        case lateConfirmed
        case afterSkipConfirmed
    }

    // MARK: - Init

    init(
        core: DoseTapCore,
        alarmService: AlarmService = .shared,
        eventLogger: EventLogger? = nil,
        undoState: UndoStateManager? = nil,
        sessionRepo: SessionRepository? = nil
    ) {
        self.core = core
        self.alarmService = alarmService
        self.eventLogger = eventLogger
        self.undoState = undoState
        self.sessionRepo = sessionRepo
    }

    // MARK: - Take Dose 1

    func takeDose1() async -> ActionResult {
        guard core.dose1Time == nil else {
            return .blocked(reason: "Dose 1 already taken")
        }

        let now = Date()
        await core.takeDose()

        // Event log
        eventLogger?.logEvent(
            name: "Dose 1", color: .green,
            cooldownSeconds: 3600 * 8, persist: false
        )

        // Undo
        undoState?.register(.takeDose1(at: now))

        // Schedule alarms
        let targetMinutes = UserSettingsManager.shared.targetIntervalMinutes
        let target = targetMinutes > 0 ? targetMinutes : 165
        let wakeTime = now.addingTimeInterval(Double(target) * 60)
        await alarmService.scheduleWakeAlarm(at: wakeTime, dose1Time: now)
        await alarmService.scheduleDose2Reminders(dose1Time: now)

        coordinatorLog.info("Dose 1 logged via coordinator")
        return .success(message: "✓ Dose 1 logged")
    }

    // MARK: - Take Dose 2

    func takeDose2(override: DoseOverride = .none) async -> ActionResult {
        // Pre-check: Dose 1 must exist
        guard core.dose1Time != nil else {
            return .blocked(reason: "Take Dose 1 first")
        }

        let ctx = core.windowContext

        // Extra dose guard: if Dose 2 already taken, block
        if core.dose2Time != nil {
            return .needsConfirm(.extraDose)
        }

        // After-skip correction
        if ctx.phase == .completed, core.isSkipped, core.dose2Time == nil {
            if override == .afterSkipConfirmed || override == .lateConfirmed {
                return await performDose2(eventName: "Dose 2 (After Skip)", isLate: true)
            }
            return .needsConfirm(.afterSkip)
        }

        // Phase routing
        switch ctx.phase {
        case .noDose1:
            return .blocked(reason: "Take Dose 1 first")

        case .beforeWindow:
            if override == .earlyConfirmed {
                return await performDose2(eventName: "Dose 2 (Early)", isLate: false, isEarly: true)
            }
            let remaining = remainingMinutesToWindowOpen()
            return .needsConfirm(.earlyDose(minutesRemaining: remaining))

        case .active, .nearClose:
            return await performDose2(eventName: "Dose 2", isLate: false)

        case .closed:
            if override == .lateConfirmed {
                return await performDose2(eventName: "Dose 2 (Late)", isLate: true)
            }
            return .needsConfirm(.lateDose)

        case .completed:
            return .blocked(reason: "Session already complete")

        case .finalizing:
            return .blocked(reason: "Session already complete")
        }
    }

    // MARK: - Snooze

    func snooze() async -> ActionResult {
        let ctx = core.windowContext

        guard case .snoozeEnabled = ctx.snooze else {
            let reason: String
            if case .snoozeDisabled(let r) = ctx.snooze {
                reason = r
            } else {
                reason = "Snooze not available"
            }
            return .blocked(reason: reason)
        }

        if let newTime = await alarmService.snoozeAlarm(dose1Time: core.dose1Time) {
            await core.snooze()
            let formatted = newTime.formatted(date: .omitted, time: .shortened)
            coordinatorLog.info("Snoozed to \(formatted, privacy: .public)")
            return .success(message: "✓ Snoozed to \(formatted)")
        } else {
            // Still increment snooze count even if alarm couldn't be rescheduled
            await core.snooze()
            return .success(message: "✓ Snoozed (+10m)")
        }
    }

    // MARK: - Skip Dose

    func skipDose() async -> ActionResult {
        guard core.dose1Time != nil else {
            return .blocked(reason: "Take Dose 1 first")
        }
        guard core.dose2Time == nil, !core.isSkipped else {
            return .blocked(reason: "Dose 2 already taken or skipped")
        }

        await core.skipDose()
        alarmService.cancelAllAlarms()
        alarmService.clearWakeAlarmState()

        eventLogger?.logEvent(
            name: "Skip Dose 2", color: .orange,
            cooldownSeconds: 3600 * 8, persist: false
        )

        coordinatorLog.info("Dose 2 skipped via coordinator")
        return .success(message: "✓ Dose 2 skipped")
    }

    // MARK: - Private Helpers

    private func performDose2(
        eventName: String,
        isLate: Bool,
        isEarly: Bool = false
    ) async -> ActionResult {
        let now = Date()
        await core.takeDose(earlyOverride: isEarly, lateOverride: isLate)

        alarmService.cancelAllAlarms()
        alarmService.clearWakeAlarmState()

        eventLogger?.logEvent(
            name: eventName,
            color: isLate ? .orange : .green,
            cooldownSeconds: 3600 * 8,
            persist: false
        )

        undoState?.register(.takeDose2(at: now))

        coordinatorLog.info("\(eventName, privacy: .public) logged via coordinator")
        return .success(message: "✓ \(eventName) logged")
    }

    private func remainingMinutesToWindowOpen() -> Int {
        guard let dose1Time = core.dose1Time else { return 0 }
        let windowOpen = dose1Time.addingTimeInterval(150 * 60)
        let remaining = windowOpen.timeIntervalSince(Date())
        return max(1, Int(ceil(remaining / 60)))
    }
}
