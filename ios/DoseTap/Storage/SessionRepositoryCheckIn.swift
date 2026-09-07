import Foundation
import DoseCore
#if canImport(OSLog)
import OSLog
#endif

@MainActor
public extension SessionRepository {
    internal func historyQuestionnaireSnapshot(sessionDate: String, kind: HistoryQuestionnaireKind) throws -> HistoryQuestionnaireSnapshot {
        try storage.historyQuestionnaireSnapshot(sessionDate: sessionDate, kind: kind)
    }

    internal func saveHistoryPreSleep(answers: PreSleepLogAnswers, review: HistoryQuestionnaireSnapshot,
                                     occurredAt: Date, reason: String) -> MedicationMutationResult {
        let result = storage.saveHistoryPreSleep(answers: answers, review: review, occurredAt: occurredAt,
            recordedAt: clock(), reason: reason, confirmed: true)
        if result.isCommitted { sessionDidChange.send() }
        return result
    }

    internal func saveHistoryMorning(_ draft: SQLiteStoredMorningCheckIn, review: HistoryQuestionnaireSnapshot,
                                    occurredAt: Date, reason: String) -> MedicationMutationResult {
        let record = StoredMorningCheckIn(
            id: review.existingID ?? draft.id, sessionId: review.history.sessionId,
            timestamp: occurredAt, sessionDate: review.history.sessionDate,
            sleepQuality: draft.sleepQuality, feelRested: draft.feelRested,
            grogginess: draft.grogginess, sleepInertiaDuration: draft.sleepInertiaDuration,
            dreamRecall: draft.dreamRecall, hasPhysicalSymptoms: draft.hasPhysicalSymptoms,
            physicalSymptomsJson: draft.physicalSymptomsJson, hasRespiratorySymptoms: draft.hasRespiratorySymptoms,
            respiratorySymptomsJson: draft.respiratorySymptomsJson, mentalClarity: draft.mentalClarity,
            mood: draft.mood, anxietyLevel: draft.anxietyLevel, stressLevel: draft.stressLevel,
            stressContextJson: draft.stressContextJson, readinessForDay: draft.readinessForDay,
            hadSleepParalysis: draft.hadSleepParalysis, hadHallucinations: draft.hadHallucinations,
            hadAutomaticBehavior: draft.hadAutomaticBehavior, fellOutOfBed: draft.fellOutOfBed,
            hadConfusionOnWaking: draft.hadConfusionOnWaking, usedSleepTherapy: draft.usedSleepTherapy,
            sleepTherapyJson: draft.sleepTherapyJson, hasSleepEnvironment: draft.hasSleepEnvironment,
            sleepEnvironmentJson: draft.sleepEnvironmentJson, timingContextJson: draft.timingContextJson,
            notes: draft.notes)
        let result = storage.saveHistoryMorning(record, review: review, occurredAt: occurredAt,
            recordedAt: clock(), reason: reason, confirmed: true)
        if result.isCommitted { sessionDidChange.send() }
        return result
    }

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
            timingContextJson: checkIn.timingContextJson,
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
