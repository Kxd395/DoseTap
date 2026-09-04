import Foundation
import DoseCore
#if canImport(OSLog)
import OSLog
#endif

@MainActor
public extension SessionRepository {
    #if DEBUG && targetEnvironment(simulator)
    /// Persist a prior-night fixture before the singleton is initialized, so
    /// process-level UI tests cover synchronous startup rollover.
    static func prepareExpiredSessionUITestFixture() {
        let storage = EventStorage.shared
        let start = Date().addingTimeInterval(-48 * 60 * 60)
        let id = UUID().uuidString
        let date = storage.sessionDateString(for: start)
        _ = storage.saveDose1(timestamp: start, sessionId: id, sessionDateOverride: date, sessionStart: start)
    }

    func prepareWorkWarningUITestSession() {
        AlarmService.shared.resetForNewSession(closingSessionId: currentSessionIdString())
        clearTonight()
        let now = clock()
        let firstDose = now.addingTimeInterval(-180 * 60)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZoneProvider()
        let firstMinutes = calendar.component(.hour, from: firstDose) * 60 + calendar.component(.minute, from: firstDose)
        // Keep this synthetic night open regardless of the wall-clock hour
        // at which the simulator test runs.
        UserSettingsManager.shared.prepTimeMinutes = (firstMinutes + 1439) % 1440
        let wake = now.addingTimeInterval(60 * 60)
        UserSettingsManager.shared.wakeTimeMinutes = calendar.component(.hour, from: wake) * 60 + calendar.component(.minute, from: wake)
        _ = setDose1Time(firstDose)
        let previous = try? workWakeSchedule()
        var plan = WorkWakeSchedule(timeZoneIdentifier: timeZoneProvider().identifier, workingWeekdays: Set(1...7), wakeMinutes: 420, target: .doseTarget)
        if let previous { plan.revision = previous.revision }
        _ = saveWorkWakeSchedule(plan)
    }
    #endif

    public func workWakeSchedule() throws -> WorkWakeSchedule { try storage.loadWorkWakeSchedule() }

    @discardableResult
    public func saveWorkWakeSchedule(_ value: WorkWakeSchedule) -> MedicationMutationResult {
        var revised = value
        revised.revision = UUID()
        let result = storage.saveWorkWakeSchedule(revised, expectedRevision: value.revision)
        if result.isCommitted { sessionDidChange.send() }
        return result
    }

    @discardableResult
    public func changeWorkWakeDate(_ warning: WorkWakeWarning, isWorking: Bool, wakeMinutes: Int? = nil) -> MedicationMutationResult {
        do {
            var plan = try workWakeSchedule()
            guard plan.revision == warning.revision else {
                return failedMedicationMutation(operation: .workSchedule, detail: "Your schedule changed. Reopen the warning to review it.", sessionId: warning.sessionId)
            }
            plan.exceptions[warning.wakeDate] = WorkWakeException(isWorking: isWorking, wakeMinutes: wakeMinutes ?? plan.exceptions[warning.wakeDate]?.wakeMinutes)
            return saveWorkWakeSchedule(plan)
        } catch {
            return failedMedicationMutation(operation: .workSchedule, detail: "Work schedule could not be saved. Your dose record has not changed.", sessionId: warning.sessionId)
        }
    }

    /// Resolve one explicitly selected historical session without reopening it.
    /// Does not schedule/cancel alarms; live-session actions use the coordinator.
    @discardableResult
    public func recordHistoricalDose2Occurrence(
        sessionId: String,
        sessionDate: String,
        occurrenceTime: Date,
        confirmed: Bool,
        reason: String?,
        notes: String?,
        workWarning: WorkWakeWarning? = nil
    ) -> MedicationMutationResult {
        let enteredAt = clock()
        guard confirmed, sessionId != activeSessionId else {
            return failedMedicationMutation(operation: .reconcileDoseState, detail: "Confirm a historical occurrence, or resolve the active session from Tonight.", sessionId: sessionId)
        }
        let events = storage.fetchDoseEvents(sessionId: sessionId, sessionDate: sessionDate)
        let firstDoses = events.filter { $0.eventType == "dose1" }
        guard firstDoses.count == 1, let first = firstDoses.first,
              occurrenceTime >= first.timestamp, occurrenceTime <= enteredAt,
              !events.contains(where: { $0.eventType == "dose2" || $0.eventType == "extra_dose" }) else {
            return failedMedicationMutation(operation: .reconcileDoseState, detail: "Reload this session. Dose 1 must be unambiguous, Dose 2 must be unrecorded, and its occurrence must be between Dose 1 and now.", sessionId: sessionId)
        }
        let timing = MedicationTiming.classify(dose1: first.timestamp, dose2: occurrenceTime)
        var metadata: [String: Any] = [
            "entry_mode": "retrospective", "recorded_at_utc": ISO8601DateFormatter().string(from: enteredAt),
            "source": "history_user_review", "surface": "session_detail",
            "is_early": timing == .early, "is_late": timing == .late,
            "occurrence_confirmed": true
        ]
        if let workWarning, let data = try? JSONEncoder().encode(workWarning), let json = try? JSONSerialization.jsonObject(with: data) {
            metadata["work_warning_acknowledgement"] = json
        }
        metadata["reason"] = reason
        metadata["reason_notes"] = notes
        guard let data = try? JSONSerialization.data(withJSONObject: metadata), let json = String(data: data, encoding: .utf8) else {
            return failedMedicationMutation(operation: .reconcileDoseState, detail: "The correction could not be encoded. No record changed.", sessionId: sessionId)
        }
        let result = recordMedicationMutation(storage.reconcileDoseEvent(
            eventType: .dose2, timestamp: occurrenceTime, sessionDate: sessionDate,
            sessionId: sessionId, metadata: json, expectedDose1Time: first.timestamp, onlyIfDose2Missing: true, workWarning: workWarning
        ))
        if result.isCommitted { sessionDidChange.send() }
        return result
    }

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

    /// Save a medication supply snapshot for export and Studio tracking.
    func saveInventorySnapshot(
        medicationName: String,
        bottlesRemaining: Int,
        dosesRemaining: Int,
        estimatedDaysLeft: Int?,
        nextRefillDate: Date?,
        notes: String?
    ) {
        let snapshot = StoredInventorySnapshot(
            medicationName: medicationName.trimmingCharacters(in: .whitespacesAndNewlines),
            bottlesRemaining: max(0, bottlesRemaining),
            dosesRemaining: max(0, dosesRemaining),
            estimatedDaysLeft: estimatedDaysLeft.map { max(0, $0) },
            nextRefillDate: nextRefillDate,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )

        storage.upsertInventorySnapshot(snapshot)
        sessionDidChange.send()
    }

    /// List inventory snapshots, newest first.
    func listInventorySnapshots(limit: Int = 500) -> [StoredInventorySnapshot] {
        storage.fetchInventorySnapshots(limit: limit)
    }

    /// Latest saved inventory snapshot.
    func latestInventorySnapshot() -> StoredInventorySnapshot? {
        storage.fetchLatestInventorySnapshot()
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
