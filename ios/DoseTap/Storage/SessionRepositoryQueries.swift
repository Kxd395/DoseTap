import Foundation
import DoseCore

@MainActor
public extension SessionRepository {
    struct NapSummary {
        let count: Int
        let totalMinutes: Int

        init(count: Int, totalMinutes: Int) {
            self.count = count
            self.totalMinutes = totalMinutes
        }
    }

    /// Get the current session date string (based on the rollover boundary).
    func currentSessionDateString() -> String {
        activeSessionDate ?? currentSessionKey
    }

    /// Get the current session id (falls back to session date for legacy rows).
    func currentSessionIdString() -> String {
        activeSessionId ?? activeSessionDate ?? currentSessionKey
    }

    /// Raw medication rows for sync/export code paths that need storage metadata.
    func fetchStoredMedicationEntries(for sessionDate: String) -> [StoredMedicationEntry] {
        storage.fetchMedicationEvents(sessionDate: sessionDate)
    }

    /// Compute the planner/pre-sleep session date key for a given timestamp without
    /// binding it to the currently active session id.
    func preSleepSessionDateKey(for date: Date) -> String {
        preSleepSessionKey(for: date, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
    }

    /// Get all session dates from storage for export.
    func getAllSessions() -> [String] {
        storage.getAllSessionDates()
    }

    /// Fetch morning check-in for a session.
    func fetchMorningCheckIn(for sessionDate: String) -> StoredMorningCheckIn? {
        guard let coreCheckIn = storage.fetchMorningCheckIn(sessionKey: sessionDate) else { return nil }
        return convertMorningCheckIn(coreCheckIn)
    }

    /// Fetch morning check-in for the current session.
    func fetchMorningCheckInForCurrentSession() -> StoredMorningCheckIn? {
        let key = activeSessionId ?? activeSessionDate ?? currentSessionKey
        guard let coreCheckIn = storage.fetchMorningCheckIn(sessionKey: key) else { return nil }
        return convertMorningCheckIn(coreCheckIn)
    }

    /// Fetch tonight's sleep events for the current session.
    func fetchTonightSleepEvents() -> [StoredSleepEvent] {
        if let sessionId = activeSessionId {
            return storage.fetchSleepEvents(forSessionId: sessionId)
        }
        if let sessionDate = activeSessionDate {
            return storage.fetchSleepEvents(forSession: sessionDate)
        }
        return storage.fetchSleepEvents(forSession: currentSessionKey)
    }

    /// Fetch sleep events for a specific session date.
    func fetchSleepEvents(for sessionDate: String) -> [StoredSleepEvent] {
        storage.fetchSleepEvents(forSession: sessionDate)
    }

    /// Fetch sleep events for a specific session (alternate label).
    func fetchSleepEvents(forSession sessionDate: String) -> [StoredSleepEvent] {
        storage.fetchSleepEvents(forSession: sessionDate)
    }

    /// Summarize naps for a session by pairing `nap_start` and `nap_end` events in timestamp order.
    func napSummary(for sessionDate: String) -> NapSummary {
        let events = fetchSleepEvents(for: sessionDate).sorted { $0.timestamp < $1.timestamp }
        var openStarts: [Date] = []
        var napCount = 0
        var totalMinutes = 0

        for event in events {
            let type = event.eventType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch type {
            case "nap_start", "nap start":
                openStarts.append(event.timestamp)
            case "nap_end", "nap end":
                if let start = openStarts.popLast() {
                    napCount += 1
                    totalMinutes += max(0, TimeIntervalMath.minutesBetween(start: start, end: event.timestamp))
                } else {
                    napCount += 1
                }
            default:
                continue
            }
        }

        napCount += openStarts.count
        return NapSummary(count: napCount, totalMinutes: totalMinutes)
    }

    /// Fetch dose events for the active session (ordered by timestamp asc).
    func fetchDoseEventsForActiveSession() -> [DoseCore.StoredDoseEvent] {
        let sessionDate = activeSessionDate ?? currentSessionKey
        return loadDoseEvents(sessionId: activeSessionId, sessionDate: sessionDate)
    }

    /// Fetch dose events for a specific session date (ordered by timestamp asc).
    func fetchDoseEvents(forSessionDate sessionDate: String) -> [DoseCore.StoredDoseEvent] {
        loadDoseEvents(sessionId: fetchSessionId(forSessionDate: sessionDate), sessionDate: sessionDate)
    }

    /// Fetch recent events across all sessions for history display.
    func fetchRecentEvents(limit: Int = 50) -> [StoredSleepEvent] {
        storage.fetchEvents(limit: limit)
    }

    /// Fetch all sleep events for timeline display.
    func fetchAllSleepEvents(limit: Int = 500) -> [StoredSleepEvent] {
        storage.fetchAllSleepEventsLocal(limit: limit)
    }

    /// Fetch all dose logs for timeline display.
    func fetchAllDoseLogs(limit: Int = 500) -> [StoredDoseLog] {
        let sessions = storage.fetchRecentSessionsLocal(days: 365)
        return sessions.prefix(limit).compactMap { session in
            guard let dose1Time = session.dose1Time else { return nil }
            return StoredDoseLog(
                id: session.sessionDate,
                sessionDate: session.sessionDate,
                dose1Time: dose1Time,
                dose2Time: session.dose2Time,
                dose2Skipped: session.dose2Skipped,
                snoozeCount: session.snoozeCount
            )
        }
    }

    /// Filter session dates to those that still exist.
    func filterExistingSessionDates(_ dates: [String]) -> [String] {
        storage.filterExistingSessionDates(dates)
    }

    /// Fetch session id for a given session date.
    func fetchSessionId(forSessionDate sessionDate: String) -> String? {
        storage.fetchSessionId(forSessionDate: sessionDate)
    }

    /// Export all data to CSV.
    func exportToCSV() -> String {
        storage.exportToCSV()
    }

    /// Fetch the most recent pre-sleep log for prefilling forms.
    func fetchMostRecentPreSleepLog() -> StoredPreSleepLog? {
        storage.fetchMostRecentPreSleepLog()
    }

    /// Get schema version for debug display.
    func getSchemaVersion() -> Int {
        storage.getSchemaVersion()
    }

    /// Get session date string for a given date.
    func sessionDateString(for date: Date) -> String {
        storage.sessionDateString(for: date)
    }

    /// Fetch recent sessions for history display.
    func fetchRecentSessions(days: Int = 7) -> [SessionSummary] {
        storage.fetchRecentSessionsLocal(days: days)
    }

    /// Async compatibility wrapper for test/API parity.
    func fetchRecentSessionsAsync(days: Int = 7) async -> [SessionSummary] {
        fetchRecentSessions(days: days)
    }

    /// Fetch dose log for a specific session.
    func fetchDoseLog(forSession sessionDate: String) -> StoredDoseLog? {
        storage.fetchDoseLog(forSession: sessionDate)
    }

    /// Most recent incomplete session for check-in prompts.
    func mostRecentIncompleteSession() -> String? {
        let excluded = activeSessionDate ?? currentSessionKey
        return storage.mostRecentIncompleteSession(excluding: excluded)
    }

    /// Fetch pre-sleep log by session ID.
    func fetchMostRecentPreSleepLog(sessionId: String) -> StoredPreSleepLog? {
        storage.fetchMostRecentPreSleepLog(sessionId: sessionId)
    }

    /// Resolve and fetch the session's canonical pre-sleep log for sync/export flows.
    func fetchPreSleepLog(forSessionDate sessionDate: String) -> StoredPreSleepLog? {
        let resolvedSessionId = fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
        return storage.fetchMostRecentPreSleepLog(sessionId: resolvedSessionId)
            ?? (resolvedSessionId == sessionDate ? nil : storage.fetchMostRecentPreSleepLog(sessionId: sessionDate))
    }

    /// Get all discovered session dates from local storage for sync export.
    func allSessionDatesForSync() -> [String] {
        storage.getAllSessionDates()
    }

    /// Fetch pending CloudKit tombstones.
    func fetchCloudKitTombstones(limit: Int = 500) -> [CloudKitTombstone] {
        storage.fetchCloudKitTombstones(limit: limit)
    }

    /// Clear delivered CloudKit tombstones.
    func clearCloudKitTombstones(keys: [String]) {
        storage.clearCloudKitTombstones(keys: keys)
    }

    /// Fetch list of recent session keys for the night review picker.
    func getRecentSessionKeys(limit: Int = 30) -> [String] {
        storage.fetchRecentSessionsLocal(days: limit).map { $0.sessionDate }
    }

    /// Fetch sleep events for a specific session using local view models.
    func fetchSleepEventsLocal(for sessionKey: String) -> [StoredSleepEvent] {
        storage.fetchSleepEvents(forSession: sessionKey)
    }
}

private extension SessionRepository {
    func convertMorningCheckIn(_ core: DoseCore.StoredMorningCheckIn) -> StoredMorningCheckIn {
        StoredMorningCheckIn(
            id: core.id,
            sessionId: core.sessionId,
            timestamp: core.timestamp,
            sessionDate: core.sessionDate,
            sleepQuality: core.sleepQuality,
            feelRested: core.feelRested,
            grogginess: core.grogginess,
            sleepInertiaDuration: core.sleepInertiaDuration,
            dreamRecall: core.dreamRecall,
            hasPhysicalSymptoms: core.hasPhysicalSymptoms,
            physicalSymptomsJson: core.physicalSymptomsJson,
            hasRespiratorySymptoms: core.hasRespiratorySymptoms,
            respiratorySymptomsJson: core.respiratorySymptomsJson,
            mentalClarity: core.mentalClarity,
            mood: core.mood,
            anxietyLevel: core.anxietyLevel,
            stressLevel: core.stressLevel,
            stressContextJson: core.stressContextJson,
            readinessForDay: core.readinessForDay,
            hadSleepParalysis: core.hadSleepParalysis,
            hadHallucinations: core.hadHallucinations,
            hadAutomaticBehavior: core.hadAutomaticBehavior,
            fellOutOfBed: core.fellOutOfBed,
            hadConfusionOnWaking: core.hadConfusionOnWaking,
            usedSleepTherapy: core.usedSleepTherapy,
            sleepTherapyJson: core.sleepTherapyJson,
            hasSleepEnvironment: core.hasSleepEnvironment,
            sleepEnvironmentJson: core.sleepEnvironmentJson,
            notes: core.notes
        )
    }
}
