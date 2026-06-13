import Foundation
import SQLite3
import DoseCore
import os.log

// MARK: - Morning Check-In Storage

extension EventStorage {

    private func morningResponsesByQuestionID(_ checkIn: StoredMorningCheckIn) -> [String: Any] {
        var responses: [String: Any] = [
            "sleep.quality": checkIn.sleepQuality,
            "sleep.rested": checkIn.feelRested,
            "sleep.grogginess": checkIn.grogginess,
            "sleep.inertia_duration": checkIn.sleepInertiaDuration,
            "sleep.dream_recall": checkIn.dreamRecall,
            "overall.mood": checkIn.mood,
            "overall.anxiety": checkIn.anxietyLevel,
            "overall.energy": checkIn.readinessForDay,
            "mental.clarity": checkIn.mentalClarity,
            "pain.any": checkIn.hasPhysicalSymptoms,
            "respiratory.any": checkIn.hasRespiratorySymptoms,
            "narcolepsy.sleep_paralysis": checkIn.hadSleepParalysis,
            "narcolepsy.hallucinations": checkIn.hadHallucinations,
            "narcolepsy.automatic_behavior": checkIn.hadAutomaticBehavior,
            "narcolepsy.fell_out_of_bed": checkIn.fellOutOfBed,
            "narcolepsy.confusion_on_waking": checkIn.hadConfusionOnWaking,
            "sleep_therapy.used": checkIn.usedSleepTherapy,
            "sleep_environment.any": checkIn.hasSleepEnvironment
        ]
        if let stressLevel = checkIn.stressLevel {
            responses["overall.stress"] = stressLevel
        }

        let stress = jsonDictionary(from: checkIn.stressContextJson)
        if let drivers = stress["drivers"] as? [String], !drivers.isEmpty {
            responses["morning.stress.drivers"] = drivers
            responses["morning.stress.driver"] = drivers.first
        }
        if let progression = stress["progression"] as? String, !progression.isEmpty {
            responses["morning.stress.progression"] = progression
        }
        if let notes = stress["notes"] as? String, !notes.isEmpty {
            responses["morning.stress.notes"] = notes
        }

        let physical = jsonDictionary(from: checkIn.physicalSymptomsJson)
        if let entries = physical["painEntries"] as? [[String: Any]], !entries.isEmpty {
            responses["pain.entries"] = entries

            let locations = entries.compactMap { $0["area"] as? String }
            if !locations.isEmpty {
                responses["pain.locations"] = Array(Set(locations)).sorted()
            }

            let intensities = entries.compactMap { item -> Int? in
                if let value = item["intensity"] as? Int { return value }
                if let value = item["intensity"] as? Double { return Int(value) }
                return nil
            }
            if let maxIntensity = intensities.max() {
                responses["pain.overall_intensity"] = maxIntensity
            }

            let sensations = entries.flatMap { item -> [String] in
                guard let values = item["sensations"] as? [String] else { return [] }
                return values
            }
            if !sensations.isEmpty {
                responses["pain.sensations"] = Array(Set(sensations)).sorted()
            }
        }
        if let value = physical["painLocations"] as? [String], !value.isEmpty, responses["pain.locations"] == nil { responses["pain.locations"] = value }
        if let value = physical["painSeverity"] as? Int, responses["pain.overall_intensity"] == nil { responses["pain.overall_intensity"] = value }
        if let value = physical["painType"] as? String { responses["pain.type"] = value }
        if let value = symptomBurdenValue(from: physical["painBurden"]) ?? derivedPainBurden(from: physical) {
            responses["pain.burden"] = value
        }
        if let value = symptomBurdenValue(from: physical["refluxBurden"]) {
            responses["sleep.reflux_burden"] = value
        }
        if let value = symptomBurdenValue(from: physical["restlessLegsBurden"]) {
            responses["sleep.restless_legs_burden"] = value
        }
        if let value = symptomBurdenValue(from: physical["bathroomUrgencyBurden"]) {
            responses["wake.bathroom_urgency_burden"] = value
        }
        if let value = physical["muscleStiffness"] as? String { responses["stiffness.level"] = value }
        if let value = physical["muscleSoreness"] as? String { responses["soreness.level"] = value }
        if let value = physical["hasHeadache"] as? Bool { responses["headache.any"] = value }
        if let value = physical["headacheSeverity"] as? String { responses["headache.severity"] = value }
        if let value = physical["headacheLocation"] as? String { responses["headache.location"] = value }
        if let value = physical["notes"] as? String, !value.isEmpty { responses["pain.notes"] = value }

        let respiratory = jsonDictionary(from: checkIn.respiratorySymptomsJson)
        if let value = respiratory["congestion"] as? String { responses["respiratory.congestion"] = value }
        if let value = symptomBurdenValue(from: respiratory["congestionBurden"]) ?? derivedCongestionBurden(from: respiratory) {
            responses["respiratory.congestion_burden"] = value
        }
        if let value = respiratory["throatCondition"] as? String { responses["respiratory.throat"] = value }
        if let value = respiratory["coughType"] as? String { responses["respiratory.cough"] = value }
        if let value = respiratory["sinusPressure"] as? String { responses["respiratory.sinus_pressure"] = value }
        if let value = respiratory["feelingFeverish"] as? Bool { responses["respiratory.feverish"] = value }
        if let value = respiratory["sicknessLevel"] as? String { responses["respiratory.sickness_level"] = value }
        if let value = respiratory["notes"] as? String, !value.isEmpty { responses["respiratory.notes"] = value }

        let therapy = jsonDictionary(from: checkIn.sleepTherapyJson)
        if let value = therapy["device"] as? String { responses["sleep_therapy.device"] = value }
        if let value = therapy["compliance"] as? Int { responses["sleep_therapy.compliance"] = value }
        if let value = therapy["notes"] as? String, !value.isEmpty { responses["sleep_therapy.notes"] = value }

        let environment = jsonDictionary(from: checkIn.sleepEnvironmentJson)
        if let value = environment["roomTemp"] as? String { responses["sleep_environment.room_temp"] = value }
        if let value = environment["noiseLevel"] as? String { responses["sleep_environment.noise_level"] = value }
        if let value = environment["sleepAids"] as? String { responses["sleep_environment.sleep_aids"] = value }
        if let value = environment["notes"] as? String, !value.isEmpty { responses["sleep_environment.notes"] = value }

        let timing = jsonDictionary(from: checkIn.timingContextJson)
        if let value = timing["nightType"] as? String, !value.isEmpty { responses["night.type"] = value }
        if let value = timing["firstNightOffAfterWorkBlock"] as? Bool { responses["night.first_off_after_work_block"] = value }
        if let value = timing["wakeType"] as? String, !value.isEmpty { responses["wake.type"] = value }
        if let value = timing["nextDayDemand"] as? String, !value.isEmpty { responses["day_demand.type"] = value }
        if let value = timing["dose2WakeMethod"] as? String, !value.isEmpty { responses["dose2.wake_method"] = value }
        if let value = timing["backToSleepDuration"] as? String, !value.isEmpty { responses["dose2.back_to_sleep"] = value }
        if let value = timing["dose2TakenReason"] as? String, !value.isEmpty { responses["dose2.taken_reason"] = value }
        if let value = timing["dose2SkippedReason"] as? String, !value.isEmpty { responses["dose2.skip_reason"] = value }
        if let value = timing["dose2ReasonNotes"] as? String, !value.isEmpty { responses["dose2.reason_notes"] = value }
        if let value = timing["wakeRequirement"] as? String, !value.isEmpty { responses["wake.requirement"] = value }
        if let value = timing["shiftStartAtUTC"] as? String, !value.isEmpty { responses["work.shift_start_utc"] = value }
        if let value = timing["shiftEndAtUTC"] as? String, !value.isEmpty { responses["work.shift_end_utc"] = value }
        if let value = timing["nextRequiredWakeAtUTC"] as? String, !value.isEmpty { responses["wake.required_at_utc"] = value }
        if let value = timing["commuteMinutes"] as? Int { responses["work.commute_minutes"] = value }
        if let value = timing["drivingConfidence"] as? Int { responses["safety.driving_confidence"] = value }
        if let value = timing["daytimeSleepiness"] as? Int { responses["daytime.sleepiness"] = value }
        if let value = timing["cataplexyBurden"] as? String, !value.isEmpty { responses["daytime.cataplexy_burden"] = value }
        if let value = timing["sleepDisorders"] as? [String], !value.isEmpty { responses["clinical.sleep_disorders"] = value }
        if let value = timing["sleepDisorderNotes"] as? String, !value.isEmpty { responses["clinical.sleep_disorder_notes"] = value }
        if let value = timing["coMedicationNotes"] as? String, !value.isEmpty { responses["clinical.co_medication_notes"] = value }
        if let value = timing["pharmacogenomicFastMetabolizer"] as? Bool { responses["clinical.pharmacogenomic_fast_metabolizer"] = value }
        if let value = timing["pharmacogenomicClinicianReviewed"] as? Bool { responses["clinical.pharmacogenomic_clinician_reviewed"] = value }
        if let value = timing["pharmacogenomicNotes"] as? String, !value.isEmpty { responses["clinical.pharmacogenomic_notes"] = value }

        if let value = checkIn.notes, !value.isEmpty { responses["notes.anything_else"] = value }
        return responses
    }

    private func symptomBurdenValue(from value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func derivedPainBurden(from physical: [String: Any]) -> String? {
        if let direct = symptomBurdenValue(from: physical["painBurden"]) {
            return direct
        }
        if let isMigraine = physical["isMigraine"] as? Bool, isMigraine {
            return "extreme"
        }
        var intensities: [Int] = []
        if let entries = physical["painEntries"] as? [[String: Any]] {
            intensities.append(contentsOf: entries.compactMap { item in
                if let value = item["intensity"] as? Int { return value }
                if let value = item["intensity"] as? Double { return Int(value) }
                return nil
            })
        }
        if let value = physical["painSeverity"] as? Int {
            intensities.append(value)
        }
        switch intensities.max() ?? 0 {
        case 9...:
            return "extreme"
        case 7...8:
            return "severe"
        case 4...6:
            return "moderate"
        case 1...3:
            return "mild"
        default:
            return nil
        }
    }

    private func derivedCongestionBurden(from respiratory: [String: Any]) -> String? {
        if let direct = symptomBurdenValue(from: respiratory["congestionBurden"]) {
            return direct
        }
        let congestion = (respiratory["congestion"] as? String)?.lowercased()
        let sinusPressure = (respiratory["sinusPressure"] as? String)?.lowercased()
        let sicknessLevel = (respiratory["sicknessLevel"] as? String)?.lowercased()

        if sicknessLevel == "actively sick" || sinusPressure == "severe" {
            return "severe"
        }
        if congestion == "both" || sinusPressure == "moderate" || sicknessLevel == "coming down with something" {
            return "moderate"
        }
        if congestion == "stuffy nose" || congestion == "runny nose" || sinusPressure == "mild" || sicknessLevel == "recovering" {
            return "mild"
        }
        return nil
    }

    private enum MorningCheckInStoreError: Error, LocalizedError {
        case prepareFailed(String)
        case stepFailed(String)

        var errorDescription: String? {
            switch self {
            case .prepareFailed(let message): return "Failed to prepare morning check-in save: \(message)"
            case .stepFailed(let message): return "Failed to save morning check-in: \(message)"
            }
        }
    }

    public func saveMorningCheckIn(_ checkIn: StoredMorningCheckIn, forSession sessionDate: String? = nil) {
        let effectiveSessionDate = sessionDate ?? currentSessionDate()

        do {
            try withSQLiteTransaction {
                try saveMorningCheckInRowOrThrow(checkIn, sessionDate: effectiveSessionDate)
                try upsertCheckInSubmissionOrThrow(
                    sourceRecordId: checkIn.id,
                    sessionId: checkIn.sessionId,
                    sessionDate: effectiveSessionDate,
                    checkInType: .morning,
                    questionnaireVersion: CheckInQuestionnaireVersion.morning,
                    submittedAt: checkIn.timestamp,
                    responsesByQuestionID: morningResponsesByQuestionID(checkIn)
                )
                try replaceMorningCheckInSymptomEventsInCurrentTransaction(checkIn, sessionDate: effectiveSessionDate)
            }
            storageLog.debug("Morning check-in saved: \(checkIn.id)")
        } catch {
            storageLog.error("Failed to save morning check-in \(checkIn.id): \(error.localizedDescription)")
        }
    }

    private func saveMorningCheckInRowOrThrow(_ checkIn: StoredMorningCheckIn, sessionDate: String) throws {
        let sql = """
            INSERT OR REPLACE INTO morning_checkins (
                id, session_id, timestamp, session_date,
                sleep_quality, feel_rested, grogginess, sleep_inertia_duration, dream_recall,
                has_physical_symptoms, physical_symptoms_json,
                has_respiratory_symptoms, respiratory_symptoms_json,
                mental_clarity, mood, anxiety_level, stress_level, stress_context_json, readiness_for_day,
                had_sleep_paralysis, had_hallucinations, had_automatic_behavior,
                fell_out_of_bed, had_confusion_on_waking,
                used_sleep_therapy, sleep_therapy_json,
                has_sleep_environment, sleep_environment_json,
                timing_context_json, notes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MorningCheckInStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let timestampStr = isoFormatter.string(from: checkIn.timestamp)

        sqlite3_bind_text(stmt, 1, checkIn.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, checkIn.sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, timestampStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, sessionDate, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, Int32(checkIn.sleepQuality))
        sqlite3_bind_text(stmt, 6, checkIn.feelRested, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, checkIn.grogginess, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, checkIn.sleepInertiaDuration, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 9, checkIn.dreamRecall, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 10, checkIn.hasPhysicalSymptoms ? 1 : 0)
        if let json = checkIn.physicalSymptomsJson {
            sqlite3_bind_text(stmt, 11, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 11)
        }
        sqlite3_bind_int(stmt, 12, checkIn.hasRespiratorySymptoms ? 1 : 0)
        if let json = checkIn.respiratorySymptomsJson {
            sqlite3_bind_text(stmt, 13, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 13)
        }
        sqlite3_bind_int(stmt, 14, Int32(checkIn.mentalClarity))
        sqlite3_bind_text(stmt, 15, checkIn.mood, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 16, checkIn.anxietyLevel, -1, SQLITE_TRANSIENT)
        if let stressLevel = checkIn.stressLevel {
            sqlite3_bind_int(stmt, 17, Int32(stressLevel))
        } else {
            sqlite3_bind_null(stmt, 17)
        }
        if let json = checkIn.stressContextJson {
            sqlite3_bind_text(stmt, 18, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 18)
        }
        sqlite3_bind_int(stmt, 19, Int32(checkIn.readinessForDay))
        sqlite3_bind_int(stmt, 20, checkIn.hadSleepParalysis ? 1 : 0)
        sqlite3_bind_int(stmt, 21, checkIn.hadHallucinations ? 1 : 0)
        sqlite3_bind_int(stmt, 22, checkIn.hadAutomaticBehavior ? 1 : 0)
        sqlite3_bind_int(stmt, 23, checkIn.fellOutOfBed ? 1 : 0)
        sqlite3_bind_int(stmt, 24, checkIn.hadConfusionOnWaking ? 1 : 0)
        sqlite3_bind_int(stmt, 25, checkIn.usedSleepTherapy ? 1 : 0)
        if let json = checkIn.sleepTherapyJson {
            sqlite3_bind_text(stmt, 26, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 26)
        }
        sqlite3_bind_int(stmt, 27, checkIn.hasSleepEnvironment ? 1 : 0)
        if let json = checkIn.sleepEnvironmentJson {
            sqlite3_bind_text(stmt, 28, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 28)
        }
        if let json = checkIn.timingContextJson {
            sqlite3_bind_text(stmt, 29, json, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 29)
        }
        if let notes = checkIn.notes {
            sqlite3_bind_text(stmt, 30, notes, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 30)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw MorningCheckInStoreError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func replaceMorningCheckInSymptomEventsInCurrentTransaction(
        _ checkIn: StoredMorningCheckIn,
        sessionDate: String
    ) throws {
        let entries = checkIn.hasPhysicalSymptoms
            ? painEntries(fromPhysicalSymptomsJson: checkIn.physicalSymptomsJson)
            : []
        let events = try symptomEvents(
            fromPainEntries: entries,
            source: .morningReview,
            sourceRecordId: checkIn.id,
            sessionId: checkIn.sessionId,
            sessionDate: sessionDate,
            phase: .morningReview,
            noticedAt: checkIn.timestamp,
            sleepDisruption: false,
            stillPresent: true
        )
        try replaceSymptomEventsInCurrentTransaction(
            source: .morningReview,
            sourceRecordId: checkIn.id,
            sessionDate: sessionDate,
            events: events
        )
    }
}
