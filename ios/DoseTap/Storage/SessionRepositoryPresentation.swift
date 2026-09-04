import Foundation
import DoseCore
#if canImport(OSLog)
import OSLog
#endif

@MainActor
extension SessionRepository {
    // MARK: - Queries

    /// Check if a given session date is the active/current session
    public func isActiveSession(_ sessionDate: String) -> Bool {
        return sessionDate == storage.currentSessionDate()
    }

    // MARK: - Computed Context (for UI binding)

    /// Computed dose window context based on current session state.
    /// This is THE context that UI should bind to - it derives from repository state.
    public var currentContext: DoseWindowContext {
        let calculator = DoseWindowCalculator(now: clock)
        let context = calculator.context(
            dose1At: dose1Time,
            dose2TakenAt: dose2Time,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount,
            wakeFinalAt: wakeFinalTime,
            checkInCompleted: checkInCompleted
        )

        // Log phase transitions (edges only)
        checkAndLogPhaseTransition(newPhase: context.phase, context: context)

        return context
    }

    /// Check if phase changed and log transition (diagnostic logging at edges)
    private func checkAndLogPhaseTransition(newPhase: DoseWindowPhase, context: DoseWindowContext) {
        guard let sessionId = activeSessionId ?? activeSessionDate else { return }
        guard newPhase != lastLoggedPhase else { return }

        let previousPhase = lastLoggedPhase
        lastLoggedPhase = newPhase

        // Map phase to diagnostic event
        let event: DiagnosticEvent
        switch newPhase {
        case .active where previousPhase == .beforeWindow:
            event = .doseWindowOpened
        case .nearClose where previousPhase == .active:
            event = .doseWindowNearClose
        case .closed where previousPhase == .nearClose || previousPhase == .active:
            event = .doseWindowExpired
        default:
            event = .sessionPhaseEntered
        }

        let elapsed = context.elapsedSinceDose1.map { Int($0 / 60) }
        let remaining = context.remainingToMax.map { Int($0 / 60) }

        Task {
            await DiagnosticLogger.shared.log(event, sessionId: sessionId) { entry in
                entry.phase = String(describing: newPhase)
                entry.previousPhase = previousPhase.map { String(describing: $0) }
                entry.elapsedMinutes = elapsed
                entry.remainingMinutes = remaining
                entry.snoozeCount = context.snoozeCount
            }
        }
    }

    // MARK: - Sleep Events (Quick Log)

    /// Log a sleep event (bathroom, lights_out, wake_final, etc.)
    /// - Parameters:
    ///   - eventType: The type of event (e.g., "bathroom", "lights_out")
    ///   - timestamp: When the event occurred
    ///   - notes: Optional notes
    ///   - source: Event source (default "manual")
    public func logSleepEvent(
        eventType: String,
        timestamp: Date = Date(),
        notes: String? = nil,
        source: String = "manual"
    ) {
        let session = ensureActiveSession(for: timestamp, reason: "sleep_event")
        let eventId = UUID().uuidString
        let normalizedType = normalizeStoredEventType(eventType)

        storage.insertSleepEvent(
            id: eventId,
            eventType: normalizedType,
            timestamp: timestamp,
            sessionDate: session.sessionDate,
            sessionId: session.sessionId,
            colorHex: nil,
            notes: notes
        )

        // Diagnostic logging (Tier 2: Session Context)
        Task {
            await DiagnosticLogger.shared.logSleepEventLogged(
                sessionId: session.sessionId,
                eventType: normalizedType,
                eventId: eventId
            )
        }

        #if canImport(OSLog)
        logger.info("Sleep event '\(normalizedType)' logged for session \(session.sessionDate)")
        #endif

        sessionDidChange.send()
    }

    /// Delete a sleep event by ID
    public func deleteSleepEvent(id: String) {
        // Get event type before deleting (for diagnostic logging)
        let events = storage.fetchSleepEvents(forSession: currentSessionKey)
        let eventType = events.first(where: { $0.id == id })?.eventType ?? "unknown"

        storage.deleteSleepEvent(id: id)

        // Diagnostic logging (Tier 2: Session Context)
        Task {
            await DiagnosticLogger.shared.logSleepEventDeleted(
                sessionId: currentSessionKey,
                eventType: eventType,
                eventId: id
            )
        }

        sessionDidChange.send()
    }
}
