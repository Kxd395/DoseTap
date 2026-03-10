import Foundation

@MainActor
public extension SessionRepository {
    /// Link pre-sleep log to session.
    func linkPreSleepLogToSession(sessionId: String) {
        let sessionDate = activeSessionDate ?? currentSessionKey
        storage.linkPreSleepLogToSession(sessionId: sessionId, sessionDate: sessionDate)
    }

    /// Clear tonight's events (for session reset).
    func clearTonightsEvents() {
        storage.clearTonightsEvents(sessionDateOverride: activeSessionDate ?? currentSessionKey)
    }

    /// Save dose 1 timestamp through the repository.
    func saveDose1(timestamp: Date) {
        setDose1Time(timestamp)
    }

    /// Save dose 2 timestamp through the repository.
    func saveDose2(timestamp: Date, isEarly: Bool = false, isExtraDose: Bool = false) {
        setDose2Time(timestamp, isEarly: isEarly, isExtraDose: isExtraDose)
    }

    /// Insert sleep event for event logging and import flows.
    func insertSleepEvent(id: String, eventType: String, timestamp: Date, colorHex: String?, notes: String? = nil) {
        let session = ensureActiveSession(for: timestamp, reason: "sleep_event_insert")
        let normalizedType = eventType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        storage.insertSleepEvent(
            id: id,
            eventType: normalizedType,
            timestamp: timestamp,
            sessionDate: session.sessionDate,
            sessionId: session.sessionId,
            colorHex: colorHex,
            notes: notes
        )
    }

    /// Upsert sleep event imported from sync with explicit session identity.
    func upsertSleepEventFromSync(
        id: String,
        eventType: String,
        timestamp: Date,
        sessionDate: String,
        sessionId: String?,
        colorHex: String?,
        notes: String?
    ) {
        storage.insertSleepEvent(
            id: id,
            eventType: eventType,
            timestamp: timestamp,
            sessionDate: sessionDate,
            sessionId: sessionId ?? sessionDate,
            colorHex: colorHex,
            notes: notes
        )
    }

    /// Upsert dose event imported from sync with explicit id.
    func upsertDoseEventFromSync(
        id: String,
        eventType: String,
        timestamp: Date,
        sessionDate: String,
        sessionId: String?,
        metadata: String?
    ) {
        storage.upsertDoseEvent(
            id: id,
            eventType: eventType,
            timestamp: timestamp,
            sessionDate: sessionDate,
            sessionId: sessionId ?? sessionDate,
            metadata: metadata
        )
    }

    /// Upsert morning check-in imported from sync.
    func upsertMorningCheckInFromSync(_ checkIn: StoredMorningCheckIn) {
        if let existing = fetchMorningCheckIn(for: checkIn.sessionDate), existing.timestamp > checkIn.timestamp {
            return
        }
        storage.saveMorningCheckIn(checkIn, forSession: checkIn.sessionDate)
    }

    /// Upsert pre-sleep log imported from sync.
    func upsertPreSleepLogFromSync(_ log: StoredPreSleepLog, sessionDate: String) {
        storage.upsertPreSleepLogFromSync(log, sessionDate: sessionDate)
    }

    /// Upsert medication event imported from sync.
    func upsertMedicationEventFromSync(_ entry: StoredMedicationEntry) {
        storage.upsertMedicationEvent(entry)
    }

    /// Delete a sleep event imported as removed by sync.
    func deleteSleepEventFromSync(id: String) {
        storage.deleteSleepEvent(id: id, recordCloudKitDeletion: false)
    }

    /// Delete a dose event imported as removed by sync.
    func deleteDoseEventFromSync(id: String) {
        storage.deleteDoseEvent(id: id, recordCloudKitDeletion: false)
    }

    /// Delete a morning check-in imported as removed by sync.
    func deleteMorningCheckInFromSync(id: String) {
        storage.deleteMorningCheckIn(id: id, recordCloudKitDeletion: false)
    }

    /// Delete a pre-sleep log imported as removed by sync.
    func deletePreSleepLogFromSync(id: String) {
        storage.deletePreSleepLog(id: id, recordCloudKitDeletion: false)
    }

    /// Delete a medication event imported as removed by sync.
    func deleteMedicationEventFromSync(id: String) {
        storage.deleteMedicationEvent(id: id, recordCloudKitDeletion: false)
    }

    /// Delete a whole session imported as removed by sync.
    func deleteSessionFromSync(sessionDate: String) {
        storage.deleteSession(sessionDate: sessionDate, recordCloudKitDeletion: false)
    }

    /// Reload and broadcast after a sync import batch is applied.
    func finalizeSyncImport() {
        reload()
    }
}
