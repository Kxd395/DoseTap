import Foundation
import DoseCore
#if canImport(OSLog)
import OSLog
#endif

@MainActor
public extension SessionRepository {
    /// Save morning check-in through unified storage.
    func saveMorningCheckIn(_ checkIn: SQLiteStoredMorningCheckIn, sessionDateOverride: String? = nil) {
        let sessionDate = sessionDateOverride ?? activeSessionDate ?? currentSessionKey

        let isHistoricalSession = sessionDateOverride != nil
            && sessionDateOverride != activeSessionDate
        let resolvedSessionId = isHistoricalSession
            ? checkIn.sessionId
            : (activeSessionId ?? checkIn.sessionId)

        let storedCheckIn = StoredMorningCheckIn(
            id: checkIn.id,
            sessionId: resolvedSessionId,
            timestamp: checkIn.timestamp,
            sessionDate: sessionDate,
            sleepQuality: checkIn.sleepQuality,
            feelRested: checkIn.feelRested,
            grogginess: checkIn.grogginess,
            sleepInertiaDuration: checkIn.sleepInertiaDuration,
            dreamRecall: checkIn.dreamRecall,
            hasPhysicalSymptoms: checkIn.hasPhysicalSymptoms,
            physicalSymptomsJson: checkIn.physicalSymptomsJson,
            hasRespiratorySymptoms: checkIn.hasRespiratorySymptoms,
            respiratorySymptomsJson: checkIn.respiratorySymptomsJson,
            mentalClarity: checkIn.mentalClarity,
            mood: checkIn.mood,
            anxietyLevel: checkIn.anxietyLevel,
            stressLevel: checkIn.stressLevel,
            stressContextJson: checkIn.stressContextJson,
            readinessForDay: checkIn.readinessForDay,
            hadSleepParalysis: checkIn.hadSleepParalysis,
            hadHallucinations: checkIn.hadHallucinations,
            hadAutomaticBehavior: checkIn.hadAutomaticBehavior,
            fellOutOfBed: checkIn.fellOutOfBed,
            hadConfusionOnWaking: checkIn.hadConfusionOnWaking,
            usedSleepTherapy: checkIn.usedSleepTherapy,
            sleepTherapyJson: checkIn.sleepTherapyJson,
            hasSleepEnvironment: checkIn.hasSleepEnvironment,
            sleepEnvironmentJson: checkIn.sleepEnvironmentJson,
            notes: checkIn.notes
        )

        storage.saveMorningCheckIn(storedCheckIn, forSession: sessionDate)

        if resolvedSessionId == activeSessionId {
            completeCheckIn()
        } else {
            Task {
                await DiagnosticLogger.shared.log(.checkinCompleted, sessionId: resolvedSessionId)
            }
            storage.closeHistoricalSession(
                sessionId: resolvedSessionId,
                sessionDate: sessionDate,
                end: clock(),
                terminalState: "checkin_completed"
            )
        }

        #if canImport(OSLog)
        logger.info("Morning check-in saved for session \(sessionDate)")
        #endif
    }
}
