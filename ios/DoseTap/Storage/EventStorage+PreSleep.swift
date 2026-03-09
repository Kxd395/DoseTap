import Foundation
import SQLite3
import DoseCore
import os.log

// MARK: - Pre-Sleep Check-In Storage

extension EventStorage {

    private static let maxDoseAmountMg = 20_000

    private func normalizedDoseAmount(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return max(250, min(Self.maxDoseAmountMg, value))
    }

    private func normalizedTotalNightlyDoseAmount(_ value: Int?) -> Int? {
        guard let value else { return nil }
        let clamped = max(500, min(Self.maxDoseAmountMg, value))
        let step = 250
        return Int((Double(clamped) / Double(step)).rounded()) * step
    }

    private func normalizedDoseSplitRatio(_ ratio: [Double]?, totalMg: Int?) -> [Double]? {
        guard var sanitized = PreSleepLogAnswers.sanitizedDoseSplitRatio(ratio) else { return nil }
        guard let totalMg, totalMg > 0 else { return sanitized }

        let minComponent = min(0.5, max(250.0 / Double(totalMg), 0.0))
        let clampedFirst = min(max(sanitized[0], minComponent), 1.0 - minComponent)
        let roundedFirst = (clampedFirst * 100).rounded() / 100
        sanitized = [roundedFirst, max(0, 1 - roundedFirst)]
        return sanitized
    }

    private func mergedPreSleepPainEntries(_ answers: PreSleepLogAnswers) -> [PreSleepLogAnswers.PainEntry] {
        if let entries = answers.painEntries, !entries.isEmpty {
            var keyed: [String: PreSleepLogAnswers.PainEntry] = [:]
            for entry in entries {
                keyed[entry.entryKey] = entry
            }
            return keyed.values.sorted { $0.entryKey < $1.entryKey }
        }

        guard
            let locations = answers.painLocations,
            !locations.isEmpty,
            let bodyPain = answers.bodyPain,
            bodyPain != .none
        else {
            return []
        }

        let intensity = preSleepPainScore(bodyPain)
        let sensation = answers.painType.map { [PreSleepLogAnswers.PainSensation(rawValue: $0.rawValue) ?? .aching] } ?? [.aching]

        return locations.map { location in
            PreSleepLogAnswers.PainEntry(
                area: PreSleepLogAnswers.PainArea(legacyLocation: location),
                side: .na,
                intensity: intensity,
                sensations: sensation,
                pattern: nil,
                notes: nil
            )
        }
    }

    private func normalizedPreSleepAnswers(_ answers: PreSleepLogAnswers) -> PreSleepLogAnswers {
        var normalized = answers
        let trimmedNotes = normalized.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.notes = trimmedNotes?.isEmpty == true ? nil : trimmedNotes
        let trimmedStressNotes = normalized.stressNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.stressNotes = trimmedStressNotes?.isEmpty == true ? nil : trimmedStressNotes
        let resolvedStressDrivers = normalized.resolvedStressDrivers
        normalized.stressDrivers = resolvedStressDrivers.isEmpty ? nil : resolvedStressDrivers
        normalized.stressDriver = normalized.primaryStressDriver

        if let entries = normalized.painEntries {
            var keyed: [String: PreSleepLogAnswers.PainEntry] = [:]
            for entry in entries {
                let safeSensations = entry.sensations.isEmpty ? [PreSleepLogAnswers.PainSensation.aching] : entry.sensations
                let safeNotes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                keyed[entry.entryKey] = PreSleepLogAnswers.PainEntry(
                    area: entry.area,
                    side: entry.side,
                    intensity: entry.intensity,
                    sensations: safeSensations,
                    pattern: entry.pattern,
                    notes: safeNotes?.isEmpty == true ? nil : safeNotes
                )
            }
            normalized.painEntries = keyed.values.sorted { $0.entryKey < $1.entryKey }
        }

        let resolvedCaffeineSources = normalized.resolvedCaffeineSources
        normalized.caffeineSources = resolvedCaffeineSources.isEmpty ? nil : resolvedCaffeineSources
        if !resolvedCaffeineSources.isEmpty {
            normalized.stimulants = PreSleepLogAnswers.caffeineSummary(for: resolvedCaffeineSources)
        }

        let hasCaffeine = normalized.hasCaffeineIntake
        if hasCaffeine {
            if let value = normalized.caffeineLastAmountMg {
                normalized.caffeineLastAmountMg = max(0, value)
            }
            if let value = normalized.caffeineDailyTotalMg {
                normalized.caffeineDailyTotalMg = max(0, value)
            }
            if let last = normalized.caffeineLastAmountMg,
               let total = normalized.caffeineDailyTotalMg,
               total < last {
                normalized.caffeineDailyTotalMg = last
            }
        } else {
            normalized.caffeineLastIntakeAt = nil
            normalized.caffeineLastAmountMg = nil
            normalized.caffeineDailyTotalMg = nil
            normalized.caffeineSources = nil
            normalized.stimulants = PreSleepLogAnswers.Stimulants.none
        }

        let legacyDose1 = normalizedDoseAmount(normalized.plannedDose1Mg)
        let legacyDose2 = normalizedDoseAmount(normalized.plannedDose2Mg)
        var nightlyTotal = normalizedTotalNightlyDoseAmount(normalized.plannedTotalNightlyMg)
        if nightlyTotal == nil, let legacyDose1, let legacyDose2 {
            nightlyTotal = normalizedTotalNightlyDoseAmount(legacyDose1 + legacyDose2)
        }

        var splitRatio = normalizedDoseSplitRatio(normalized.plannedDoseSplitRatio, totalMg: nightlyTotal)
        if splitRatio == nil, let legacyDose1, let legacyDose2 {
            let total = Double(legacyDose1 + legacyDose2)
            if total > 0 {
                splitRatio = [Double(legacyDose1) / total, Double(legacyDose2) / total]
            }
        }
        if splitRatio == nil, nightlyTotal != nil {
            splitRatio = PreSleepLogAnswers.defaultDoseSplitRatio
        }

        if let nightlyTotal, let splitRatio {
            let dose1 = normalizedDoseAmount(Int((Double(nightlyTotal) * splitRatio[0]).rounded()))
            let dose2 = normalizedDoseAmount(max(250, nightlyTotal - (dose1 ?? 0)))

            normalized.plannedTotalNightlyMg = nightlyTotal
            normalized.plannedDose1Mg = dose1
            normalized.plannedDose2Mg = dose2

            if let dose1, let dose2, nightlyTotal > 0 {
                normalized.plannedDoseSplitRatio = [Double(dose1) / Double(nightlyTotal), Double(dose2) / Double(nightlyTotal)]
            } else {
                normalized.plannedDoseSplitRatio = splitRatio
            }
        } else {
            normalized.plannedDose1Mg = legacyDose1
            normalized.plannedDose2Mg = legacyDose2
            if let legacyDose1, let legacyDose2 {
                let total = normalizedTotalNightlyDoseAmount(legacyDose1 + legacyDose2) ?? (legacyDose1 + legacyDose2)
                normalized.plannedTotalNightlyMg = total
                if total > 0 {
                    normalized.plannedDoseSplitRatio = [Double(legacyDose1) / Double(total), Double(legacyDose2) / Double(total)]
                }
            } else {
                normalized.plannedTotalNightlyMg = nil
                normalized.plannedDoseSplitRatio = nil
            }
        }

        let hasAlcohol = (normalized.alcohol ?? .none) != .none
        if hasAlcohol {
            if let value = normalized.alcoholLastAmountDrinks {
                normalized.alcoholLastAmountDrinks = max(0, value)
            }
            if let value = normalized.alcoholDailyTotalDrinks {
                normalized.alcoholDailyTotalDrinks = max(0, value)
            }
            if let last = normalized.alcoholLastAmountDrinks,
               let total = normalized.alcoholDailyTotalDrinks,
               total < last {
                normalized.alcoholDailyTotalDrinks = last
            }
        } else {
            normalized.alcoholLastDrinkAt = nil
            normalized.alcoholLastAmountDrinks = nil
            normalized.alcoholDailyTotalDrinks = nil
        }

        let hasExercise = (normalized.exercise ?? .none) != .none
        if hasExercise {
            if let duration = normalized.exerciseDurationMinutes {
                normalized.exerciseDurationMinutes = max(5, min(600, duration))
            }
        } else {
            normalized.exerciseType = nil
            normalized.exerciseLastAt = nil
            normalized.exerciseDurationMinutes = nil
        }

        let hasNap = (normalized.napToday ?? .none) != .none
        if hasNap {
            if let count = normalized.napCount {
                normalized.napCount = max(1, min(6, count))
            }
            if let total = normalized.napTotalMinutes {
                normalized.napTotalMinutes = max(5, min(360, total))
            }
        } else {
            normalized.napCount = nil
            normalized.napTotalMinutes = nil
            normalized.napLastEndAt = nil
        }

        if (normalized.lateMeal ?? PreSleepLogAnswers.LateMeal.none) == PreSleepLogAnswers.LateMeal.none {
            normalized.lateMealEndedAt = nil
        }

        if (normalized.screensInBed ?? PreSleepLogAnswers.ScreensInBed.none) == PreSleepLogAnswers.ScreensInBed.none {
            normalized.screensLastUsedAt = nil
        }

        let resolvedSleepAidSelections = normalized.resolvedSleepAidSelections
        normalized.sleepAidSelections = resolvedSleepAidSelections.isEmpty ? nil : resolvedSleepAidSelections
        if !resolvedSleepAidSelections.isEmpty {
            normalized.sleepAids = PreSleepLogAnswers.sleepAidSummary(for: resolvedSleepAidSelections)
        } else if (normalized.sleepAids ?? PreSleepLogAnswers.SleepAid.none) == PreSleepLogAnswers.SleepAid.none {
            normalized.sleepAidSelections = nil
        }

        return normalized
    }

    private func preSleepResponsesByQuestionID(_ answers: PreSleepLogAnswers) -> [String: Any] {
        let normalized = normalizedPreSleepAnswers(answers)
        var responses: [String: Any] = [:]
        if let value = normalized.intendedSleepTime?.rawValue { responses["pre.sleep.intended_time"] = value }
        if let value = normalized.stressLevel { responses["overall.stress"] = value }
        if let value = normalized.primaryStressDriver?.rawValue { responses["pre.stress.driver"] = value }
        if let value = normalized.stressDrivers?.map(\.rawValue), !value.isEmpty { responses["pre.stress.drivers"] = value }
        if let value = normalized.stressProgression?.rawValue { responses["pre.stress.progression"] = value }
        if let value = normalized.stressNotes, !value.isEmpty { responses["pre.stress.notes"] = value }
        if let value = normalized.laterReason?.rawValue { responses["pre.sleep.later_reason"] = value }
        if let value = normalized.bodyPain?.rawValue {
            responses["pain.level"] = value
            responses["pain.any"] = value != PreSleepLogAnswers.PainLevel.none.rawValue
        }
        let painEntries = mergedPreSleepPainEntries(normalized)
        if !painEntries.isEmpty {
            responses["pain.any"] = true
            responses["pain.entries"] = preSleepPainEntryDictionaries(painEntries)
            responses["pain.locations"] = Array(Set(painEntries.map { $0.area.rawValue })).sorted()
            responses["pain.sensations"] = Array(Set(painEntries.flatMap { $0.sensations.map(\.rawValue) })).sorted()
            responses["pain.overall_intensity"] = painEntries.map(\.intensity).max() ?? 0
        } else if let pain = normalized.bodyPain {
            responses["pain.overall_intensity"] = preSleepPainScore(pain)
        }
        if let value = normalized.painLocations?.map(\.rawValue), !value.isEmpty, responses["pain.locations"] == nil { responses["pain.locations"] = value }
        if let value = normalized.painType?.rawValue { responses["pain.type"] = value }
        if let value = normalized.caffeineSourceSummary?.rawValue { responses["pre.substances.stimulants_after_2pm"] = value }
        if let value = normalized.caffeineSourceSummary?.rawValue { responses["pre.substances.caffeine.source"] = value }
        if let value = normalized.caffeineSources?.map(\.rawValue), !value.isEmpty { responses["pre.substances.caffeine.sources"] = value }
        if let value = normalized.caffeineLastIntakeAt { responses["pre.substances.caffeine.last_time_utc"] = isoFormatter.string(from: value) }
        if let value = normalized.caffeineLastAmountMg {
            responses["pre.substances.caffeine.last_amount_mg"] = value
            responses["pre.substances.caffeine.last_amount_oz"] = value
        }
        if let value = normalized.caffeineDailyTotalMg {
            responses["pre.substances.caffeine.daily_total_mg"] = value
            responses["pre.substances.caffeine.daily_total_oz"] = value
        }
        if let value = normalized.plannedTotalNightlyMg { responses["pre.dose_plan.total_mg"] = value }
        if let value = normalized.plannedDoseSplitRatio, value.count == 2 { responses["pre.dose_plan.split_ratio"] = value }
        if let value = normalized.plannedDosePercentages { responses["pre.dose_plan.split_percentages"] = value }
        if let value = normalized.plannedDose1Mg { responses["pre.dose_plan.dose1_mg"] = value }
        if let value = normalized.plannedDose2Mg { responses["pre.dose_plan.dose2_mg"] = value }
        if normalized.plannedDose1Mg != nil || normalized.plannedDose2Mg != nil {
            responses["pre.dose_plan.any"] = true
        }
        if let dose1 = normalized.plannedDose1Mg, let dose2 = normalized.plannedDose2Mg {
            responses["pre.dose_plan.off_label_single_dose"] = max(dose1, dose2) > 4500
        }
        if normalized.hasCaffeineIntake {
            responses["pre.substances.caffeine.amount_unit"] = "oz"
        }
        if normalized.stimulants != nil || normalized.caffeineSources != nil || normalized.caffeineLastIntakeAt != nil || normalized.caffeineLastAmountMg != nil || normalized.caffeineDailyTotalMg != nil {
            responses["pre.substances.caffeine.any"] = normalized.hasCaffeineIntake
        }
        if let value = normalized.alcohol?.rawValue { responses["pre.substances.alcohol"] = value }
        if let value = normalized.alcoholLastDrinkAt { responses["pre.substances.alcohol.last_time_utc"] = isoFormatter.string(from: value) }
        if let value = normalized.alcoholLastAmountDrinks { responses["pre.substances.alcohol.last_amount_drinks"] = value }
        if let value = normalized.alcoholDailyTotalDrinks { responses["pre.substances.alcohol.daily_total_drinks"] = value }
        if normalized.alcohol != nil || normalized.alcoholLastDrinkAt != nil || normalized.alcoholLastAmountDrinks != nil || normalized.alcoholDailyTotalDrinks != nil {
            responses["pre.substances.alcohol.any"] = (normalized.alcohol ?? .none) != .none
        }
        if let value = normalized.exercise?.rawValue { responses["pre.day.exercise_level"] = value }
        if normalized.exercise != nil || normalized.exerciseType != nil || normalized.exerciseLastAt != nil || normalized.exerciseDurationMinutes != nil {
            responses["pre.day.exercise.any"] = (normalized.exercise ?? .none) != .none
        }
        if let value = normalized.exerciseType?.rawValue { responses["pre.day.exercise.type"] = value }
        if let value = normalized.exerciseLastAt { responses["pre.day.exercise.last_time_utc"] = isoFormatter.string(from: value) }
        if let value = normalized.exerciseDurationMinutes { responses["pre.day.exercise.duration_minutes"] = value }
        if let value = normalized.napToday?.rawValue { responses["pre.day.nap_duration"] = value }
        if normalized.napToday != nil || normalized.napCount != nil || normalized.napTotalMinutes != nil || normalized.napLastEndAt != nil {
            responses["pre.day.nap.any"] = (normalized.napToday ?? .none) != .none
        }
        if let value = normalized.napCount { responses["pre.day.nap.count"] = value }
        if let value = normalized.napTotalMinutes { responses["pre.day.nap.total_minutes"] = value }
        if let value = normalized.napLastEndAt { responses["pre.day.nap.last_end_time_utc"] = isoFormatter.string(from: value) }
        if let value = normalized.lateMeal?.rawValue { responses["pre.day.late_meal"] = value }
        if let value = normalized.lateMealEndedAt { responses["pre.day.late_meal.last_time_utc"] = isoFormatter.string(from: value) }
        if let value = normalized.screensInBed?.rawValue { responses["pre.sleep.screens_in_bed"] = value }
        if let value = normalized.screensLastUsedAt { responses["pre.sleep.screens_in_bed.last_time_utc"] = isoFormatter.string(from: value) }
        if let value = normalized.roomTemp?.rawValue { responses["pre.environment.room_temp"] = value }
        if let value = normalized.noiseLevel?.rawValue { responses["pre.environment.noise_level"] = value }
        if let value = normalized.sleepAidSummary?.rawValue { responses["pre.sleep.aids"] = value }
        if let value = normalized.sleepAidSelections?.map(\.rawValue), !value.isEmpty { responses["pre.sleep.aids_list"] = value }
        if normalized.sleepAids != nil || normalized.sleepAidSelections != nil {
            responses["pre.sleep.aids.any"] = normalized.hasSleepAids
        }
        if let value = normalized.notes, !value.isEmpty { responses["notes.anything_else"] = value }
        return responses
    }

    public func fetchMostRecentPreSleepLog() -> StoredPreSleepLog? {
        let sql = "SELECT id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json FROM pre_sleep_logs ORDER BY created_at DESC LIMIT 1"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let sessionId = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let createdAtUtc = String(cString: sqlite3_column_text(stmt, 2))
            let localOffsetMinutes = Int(sqlite3_column_int(stmt, 3))
            let completionState = String(cString: sqlite3_column_text(stmt, 4))
            let answersJson = String(cString: sqlite3_column_text(stmt, 5))

            var answers: PreSleepLogAnswers? = nil
            if let data = answersJson.data(using: .utf8) {
                answers = try? JSONDecoder().decode(PreSleepLogAnswers.self, from: data)
            }

            return StoredPreSleepLog(
                id: id,
                sessionId: sessionId,
                createdAtUtc: createdAtUtc,
                localOffsetMinutes: localOffsetMinutes,
                completionState: completionState,
                answers: answers
            )
        }

        return nil
    }

    public func fetchMostRecentPreSleepLog(sessionId: String) -> StoredPreSleepLog? {
        let sql = """
            SELECT id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json
            FROM pre_sleep_logs
            WHERE session_id = ?
            ORDER BY created_at DESC
            LIMIT 1
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let sessionId = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let createdAtUtc = String(cString: sqlite3_column_text(stmt, 2))
            let localOffsetMinutes = Int(sqlite3_column_int(stmt, 3))
            let completionState = String(cString: sqlite3_column_text(stmt, 4))
            let answersJson = String(cString: sqlite3_column_text(stmt, 5))

            var answers: PreSleepLogAnswers? = nil
            if let data = answersJson.data(using: .utf8) {
                answers = try? JSONDecoder().decode(PreSleepLogAnswers.self, from: data)
            }

            return StoredPreSleepLog(
                id: id,
                sessionId: sessionId,
                createdAtUtc: createdAtUtc,
                localOffsetMinutes: localOffsetMinutes,
                completionState: completionState,
                answers: answers
            )
        }

        return nil
    }

    public func fetchPreSleepLogCount(sessionId: String) -> Int {
        let sql = "SELECT COUNT(*) FROM pre_sleep_logs WHERE session_id = ?"
        var stmt: OpaquePointer?
        var count = 0

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)

        return count
    }

    public func upsertPreSleepLogFromSync(_ log: StoredPreSleepLog, sessionDate: String) {
        let answersJson: String
        if
            let answers = log.answers,
            let data = try? JSONEncoder().encode(answers),
            let encoded = String(data: data, encoding: .utf8)
        {
            answersJson = encoded
        } else {
            answersJson = "{}"
        }

        let sql = """
            INSERT OR REPLACE INTO pre_sleep_logs (
                id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json
            ) VALUES (?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            storageLog.error("Failed to prepare pre-sleep sync upsert: \(String(cString: sqlite3_errmsg(self.db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, log.id, -1, SQLITE_TRANSIENT)
        if let sessionId = log.sessionId {
            sqlite3_bind_text(stmt, 2, sessionId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_text(stmt, 3, log.createdAtUtc, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, Int32(log.localOffsetMinutes))
        sqlite3_bind_text(stmt, 5, log.completionState, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, answersJson, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            storageLog.error("Failed to upsert pre-sleep log from sync: \(String(cString: sqlite3_errmsg(self.db)))")
            return
        }

        let submittedAt = isoFormatter.date(from: log.createdAtUtc) ?? Date()
        upsertCheckInSubmission(
            sourceRecordId: log.id,
            sessionId: log.sessionId,
            sessionDate: sessionDate,
            checkInType: .preNight,
            questionnaireVersion: CheckInQuestionnaireVersion.preNight,
            submittedAt: submittedAt,
            responsesByQuestionID: log.answers.map(preSleepResponsesByQuestionID) ?? [:]
        )
    }

    public func deletePreSleepLog(id: String, recordCloudKitDeletion: Bool = true) {
        if recordCloudKitDeletion {
            enqueueCloudKitTombstone(recordType: "DoseTapPreSleepLog", recordName: id)
        }

        let sql = "DELETE FROM pre_sleep_logs WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            storageLog.error("Failed to delete pre-sleep log: \(String(cString: sqlite3_errmsg(self.db)))")
            return
        }

        let submissionSQL = "DELETE FROM checkin_submissions WHERE source_record_id = ? AND checkin_type = ?"
        var submissionStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, submissionSQL, -1, &submissionStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(submissionStmt) }
        sqlite3_bind_text(submissionStmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(submissionStmt, 2, CheckInType.preNight.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_step(submissionStmt)
    }

    public enum PreSleepLogStoreError: Error, LocalizedError {
        case encodeFailed
        case prepareFailed(String)
        case bindFailed(String)
        case stepFailed(String)

        public var errorDescription: String? {
            switch self {
            case .encodeFailed: return "Failed to encode pre-sleep answers"
            case .prepareFailed(let message): return "Failed to prepare pre-sleep save: \(message)"
            case .bindFailed(let message): return "Failed to bind pre-sleep save: \(message)"
            case .stepFailed(let message): return "Failed to save pre-sleep log: \(message)"
            }
        }
    }

    private func updatePreSleepLog(
        id: String,
        sessionId: String?,
        completionState: String,
        answersJson: String
    ) throws -> Bool {
        let sql = """
            UPDATE pre_sleep_logs
            SET session_id = ?, completion_state = ?, answers_json = ?
            WHERE id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PreSleepLogStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        if let sessionId = sessionId {
            guard sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        } else {
            guard sqlite3_bind_null(stmt, 1) == SQLITE_OK else {
                throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
        guard sqlite3_bind_text(stmt, 2, completionState, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_bind_text(stmt, 3, answersJson, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_bind_text(stmt, 4, id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw PreSleepLogStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }

        return sqlite3_changes(db) > 0
    }

    @discardableResult
    public func savePreSleepLogOrThrow(
        sessionId: String?,
        answers: PreSleepLogAnswers,
        completionState: String = "complete",
        now: Date = Date(),
        timeZone: TimeZone = .current,
        existingLog: StoredPreSleepLog? = nil
    ) throws -> StoredPreSleepLog {
        let normalizedAnswers = normalizedPreSleepAnswers(answers)

        guard let data = try? JSONEncoder().encode(normalizedAnswers),
              let answersJson = String(data: data, encoding: .utf8) else {
            throw PreSleepLogStoreError.encodeFailed
        }

        var logToUpdate = existingLog
        if logToUpdate == nil, let sessionId = sessionId {
            logToUpdate = fetchMostRecentPreSleepLog(sessionId: sessionId)
        }

        if let existing = logToUpdate {
            let updatedSessionId = sessionId ?? existing.sessionId
            if try updatePreSleepLog(
                id: existing.id,
                sessionId: updatedSessionId,
                completionState: completionState,
                answersJson: answersJson
            ) {
                upsertCheckInSubmission(
                    sourceRecordId: existing.id,
                    sessionId: updatedSessionId,
                    sessionDate: resolvedSessionDate(sessionId: updatedSessionId, fallbackDate: now),
                    checkInType: .preNight,
                    questionnaireVersion: CheckInQuestionnaireVersion.preNight,
                    submittedAt: now,
                    responsesByQuestionID: preSleepResponsesByQuestionID(normalizedAnswers)
                )
                return StoredPreSleepLog(
                    id: existing.id,
                    sessionId: updatedSessionId,
                    createdAtUtc: existing.createdAtUtc,
                    localOffsetMinutes: existing.localOffsetMinutes,
                    completionState: completionState,
                    answers: normalizedAnswers
                )
            }
        }

        let id = UUID().uuidString
        let createdAtUtc = isoFormatter.string(from: now)
        let localOffsetMinutes = timeZone.secondsFromGMT(for: now) / 60

        let sql = """
            INSERT INTO pre_sleep_logs (id, session_id, created_at_utc, local_offset_minutes, completion_state, answers_json)
            VALUES (?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PreSleepLogStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        if let sessionId = sessionId {
            guard sqlite3_bind_text(stmt, 2, sessionId, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
                throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        guard sqlite3_bind_text(stmt, 3, createdAtUtc, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_bind_int(stmt, 4, Int32(localOffsetMinutes)) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_bind_text(stmt, 5, completionState, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
        guard sqlite3_bind_text(stmt, 6, answersJson, -1, SQLITE_TRANSIENT) == SQLITE_OK else {
            throw PreSleepLogStoreError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw PreSleepLogStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }

        upsertCheckInSubmission(
            sourceRecordId: id,
            sessionId: sessionId,
            sessionDate: resolvedSessionDate(sessionId: sessionId, fallbackDate: now),
            checkInType: .preNight,
            questionnaireVersion: CheckInQuestionnaireVersion.preNight,
            submittedAt: now,
            responsesByQuestionID: preSleepResponsesByQuestionID(normalizedAnswers)
        )

        return StoredPreSleepLog(
            id: id,
            sessionId: sessionId,
            createdAtUtc: createdAtUtc,
            localOffsetMinutes: localOffsetMinutes,
            completionState: completionState,
            answers: normalizedAnswers
        )
    }

    public func savePreSleepLog(sessionId: String?, answers: PreSleepLogAnswers, completionState: String = "complete") {
        do {
            _ = try savePreSleepLogOrThrow(
                sessionId: sessionId,
                answers: answers,
                completionState: completionState,
                now: Date(),
                timeZone: .current
            )
            storageLog.debug("Pre-sleep log saved")
        } catch {
            storageLog.error("Failed to save pre-sleep log: \(error.localizedDescription)")
        }
    }

    public func savePreSleepLog(_ log: PreSleepLog) {
        do {
            _ = try savePreSleepLogOrThrow(
                sessionId: log.sessionId,
                answers: log.answers,
                completionState: log.completionState,
                now: log.createdAt,
                timeZone: .current
            )
        } catch {
            storageLog.error("Failed to save pre-sleep log: \(error.localizedDescription)")
        }
    }
}
