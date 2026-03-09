import Foundation
import DoseCore
#if canImport(OSLog)
import OSLog
#endif

@MainActor
public extension SessionRepository {
    /// Log a medication entry for the session date derived from its timestamp.
    /// Returns the DuplicateGuardResult for UI to handle.
    func logMedicationEntry(
        medicationId: String,
        doseMg: Int,
        takenAt: Date,
        notes: String? = nil,
        confirmedDuplicate: Bool = false
    ) -> DuplicateGuardResult {
        let sessionDate = computeSessionDate(for: takenAt)

        if !confirmedDuplicate {
            let guardResult = checkDuplicateGuard(
                medicationId: medicationId,
                takenAt: takenAt,
                sessionDate: sessionDate
            )
            if guardResult.isDuplicate {
                return guardResult
            }
        }

        let sessionId: String? = sessionDate == activeSessionDate ? activeSessionId : nil
        let localOffsetMinutes = timeZoneProvider().secondsFromGMT(for: takenAt) / 60
        let formulation = persistedMedicationFormulation(for: medicationId)

        let entry = StoredMedicationEntry(
            sessionId: sessionId,
            sessionDate: sessionDate,
            medicationId: medicationId,
            doseMg: doseMg,
            takenAtUTC: takenAt,
            doseUnit: "mg",
            formulation: formulation,
            localOffsetMinutes: localOffsetMinutes,
            notes: notes,
            confirmedDuplicate: confirmedDuplicate
        )

        storage.insertMedicationEvent(entry)
        sessionDidChange.send()

        #if canImport(OSLog)
        logger.debug("Logged medication \(medicationId, privacy: .public) \(doseMg)mg")
        #endif

        return .notDuplicate
    }

    /// Check if a medication entry would be a duplicate.
    func checkDuplicateGuard(medicationId: String, takenAt: Date, sessionDate: String) -> DuplicateGuardResult {
        let guardMinutes = DoseCore.MedicationConfig.duplicateGuardMinutes

        if let existing = storage.findRecentMedicationEntry(
            medicationId: medicationId,
            sessionDate: sessionDate,
            withinMinutes: guardMinutes,
            ofTime: takenAt
        ) {
            let deltaSeconds = abs(takenAt.timeIntervalSince(existing.takenAtUTC))
            let minutesDelta = Int(deltaSeconds / 60)

            let entry = MedicationEntry(
                id: existing.id,
                sessionId: existing.sessionId,
                sessionDate: existing.sessionDate,
                medicationId: existing.medicationId,
                doseMg: existing.doseMg,
                takenAtUTC: existing.takenAtUTC,
                notes: existing.notes,
                confirmedDuplicate: existing.confirmedDuplicate,
                createdAt: existing.createdAt
            )

            return DuplicateGuardResult(isDuplicate: true, existingEntry: entry, minutesDelta: minutesDelta)
        }

        return .notDuplicate
    }

    /// Convenience: Check duplicate without needing to compute session date.
    func checkDuplicateMedication(medicationId: String, takenAt: Date) -> DuplicateGuardResult {
        let sessionDate = computeSessionDate(for: takenAt)
        return checkDuplicateGuard(medicationId: medicationId, takenAt: takenAt, sessionDate: sessionDate)
    }

    /// List medication entries for a session date.
    func listMedicationEntries(for sessionDate: String) -> [MedicationEntry] {
        storage.fetchMedicationEvents(sessionDate: sessionDate).map { stored in
            MedicationEntry(
                id: stored.id,
                sessionId: stored.sessionId,
                sessionDate: stored.sessionDate,
                medicationId: stored.medicationId,
                doseMg: stored.doseMg,
                takenAtUTC: stored.takenAtUTC,
                notes: stored.notes,
                confirmedDuplicate: stored.confirmedDuplicate,
                createdAt: stored.createdAt
            )
        }
    }

    /// List medication entries for current session.
    func listMedicationEntriesForCurrentSession() -> [MedicationEntry] {
        listMedicationEntries(for: currentSessionDateString())
    }

    /// Delete a medication entry.
    func deleteMedicationEntry(id: String) {
        storage.deleteMedicationEvent(id: id)
        sessionDidChange.send()
    }
}

private extension SessionRepository {
    func persistedMedicationFormulation(for medicationId: String) -> String {
        guard let medication = MedicationConfig.type(for: medicationId) else { return "ir" }
        switch medication.formulation {
        case .immediateRelease:
            return "ir"
        case .extendedRelease:
            return "xr"
        case .liquid:
            return "liquid"
        }
    }

    /// Compute session date for a given timestamp using the repository rollover boundary.
    func computeSessionDate(for date: Date) -> String {
        sessionKey(for: date, timeZone: timeZoneProvider(), rolloverHour: rolloverHour)
    }
}
