import Foundation
import SQLite3
import DoseCore

// MARK: - EventStore Protocol Conformance
// This extension makes EventStorage the single source of truth for all event operations.
// UI and business logic should ONLY interact through the EventStore protocol.

extension EventStorage: EventStore {
    
    // MARK: - Session Identity
    
    public func currentSessionKey() -> String {
        currentSessionDate()
    }
    
    public func getAllSessionKeys() -> [String] {
        getAllSessionDates()
    }
    
    // MARK: - Sleep Events (Protocol methods with explicit sessionKey parameter)
    
    public func insertSleepEvent(
        id: String,
        eventType: String,
        timestamp: Date,
        sessionKey: String,
        colorHex: String?,
        notes: String?
    ) {
        // Delegate to existing method with sessionDate parameter
        insertSleepEvent(
            id: id,
            eventType: eventType,
            timestamp: timestamp,
            sessionDate: sessionKey,
            colorHex: colorHex,
            notes: notes
        )
    }
    
    public func fetchSleepEvents(sessionKey: String) -> [DoseCore.StoredSleepEvent] {
        // Fetch using local type, convert to DoseCore type
        let localEvents = fetchSleepEvents(forSession: sessionKey)
        return localEvents.map { local in
            DoseCore.StoredSleepEvent(
                id: local.id,
                eventType: local.eventType,
                timestamp: local.timestamp,
                sessionDate: local.sessionDate,
                colorHex: local.colorHex,
                notes: local.notes
            )
        }
    }
    
    public func fetchTonightSleepEvents() -> [DoseCore.StoredSleepEvent] {
        fetchSleepEvents(sessionKey: currentSessionKey())
    }
    
    public func fetchAllSleepEvents(limit: Int) -> [DoseCore.StoredSleepEvent] {
        // Use existing method and convert
        let localEvents = fetchAllSleepEventsLocal(limit: limit)
        return localEvents.map { local in
            DoseCore.StoredSleepEvent(
                id: local.id,
                eventType: local.eventType,
                timestamp: local.timestamp,
                sessionDate: local.sessionDate,
                colorHex: local.colorHex,
                notes: local.notes
            )
        }
    }
    
    // MARK: - Dose Events
    
    public func insertDoseEvent(eventType: String, timestamp: Date, sessionKey: String, metadata: String?) {
        insertDoseEvent(eventType: eventType, timestamp: timestamp, sessionDate: sessionKey, metadata: metadata)
    }
    
    public func fetchDoseEvents(sessionId: String?, sessionDate: String) -> [DoseCore.StoredDoseEvent] {
        var events: [DoseCore.StoredDoseEvent] = []
        let sql = """
        SELECT id, event_type, timestamp, session_date, metadata
        FROM dose_events
        WHERE \(sessionId != nil ? "(session_id = ? OR session_date = ?)" : "session_date = ?")
        ORDER BY timestamp ASC
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        
        if let sessionId = sessionId {
            sqlite3_bind_text(stmt, 1, sessionId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, sessionDate, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_text(stmt, 1, sessionDate, -1, SQLITE_TRANSIENT)
        }
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let idPtr = sqlite3_column_text(stmt, 0),
               let typePtr = sqlite3_column_text(stmt, 1),
               let timestampPtr = sqlite3_column_text(stmt, 2),
               let sessionPtr = sqlite3_column_text(stmt, 3) {
                let id = String(cString: idPtr)
                let eventType = String(cString: typePtr)
                let timestampStr = String(cString: timestampPtr)
                let sessionDate = String(cString: sessionPtr)
                let metadata = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
                
                if let timestamp = isoFormatter.date(from: timestampStr) {
                    events.append(DoseCore.StoredDoseEvent(
                        id: id,
                        eventType: eventType,
                        timestamp: timestamp,
                        sessionDate: sessionDate,
                        metadata: metadata
                    ))
                }
            }
        }
        return events
    }
    
    public func fetchDoseEvents(sessionKey: String) -> [DoseCore.StoredDoseEvent] {
        fetchDoseEvents(sessionId: nil, sessionDate: sessionKey)
    }
    
    public func hasDose(type: String, sessionKey: String) -> Bool {
        hasDose(type: type, sessionDate: sessionKey)
    }
    
    // MARK: - Session State (current_session table)
    
    public func saveDose1(timestamp: Date) {
        saveDose1(timestamp: timestamp, sessionId: nil, sessionDateOverride: nil)
    }
    
    public func saveDose2(timestamp: Date, isEarly: Bool, isExtraDose: Bool) {
        saveDose2(timestamp: timestamp, isEarly: isEarly, isExtraDose: isExtraDose, isLate: false, sessionId: nil, sessionDateOverride: nil)
    }
    
    public func saveDoseSkipped(reason: String?) {
        saveDoseSkipped(reason: reason, sessionId: nil, sessionDateOverride: nil)
    }
    
    public func saveSnooze(count: Int) {
        saveSnooze(count: count, sessionId: nil, sessionDateOverride: nil)
    }
    
    public func clearDose1() {
        // Clear dose 1 from current_session
        let sql = """
        UPDATE current_session
        SET dose1_time = NULL
        WHERE id = 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)
    }
    
    public func clearDose2() {
        // Clear dose 2 from current_session
        let sql = """
        UPDATE current_session
        SET dose2_time = NULL, dose2_skipped = 0
        WHERE id = 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)
    }
    
    public func clearSkip() {
        // Clear skip from current_session
        let sql = """
        UPDATE current_session
        SET dose2_skipped = 0
        WHERE id = 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)
    }
    
    // MARK: - Pre-Sleep Logs
    
    public func savePreSleepLogOrThrow(sessionKey: String, answers: DoseCore.PreSleepLogAnswers, completionState: String) throws {
        let now = nowProvider()
        var mapped = PreSleepLogAnswers(
            stressLevel: answers.stressLevel,
            stimulants: answers.caffeineLast6Hours == true
                ? .multiple
                : (answers.caffeineLast6Hours == false ? PreSleepLogAnswers.Stimulants.none : nil),
            caffeineLastIntakeAt: answers.caffeineLast6Hours == true ? now : nil,
            caffeineLastAmountMg: answers.caffeineLast6Hours == true ? 95 : nil,
            caffeineDailyTotalMg: answers.caffeineLast6Hours == true ? 95 : nil,
            alcohol: answers.alcoholLast6Hours == true
                ? .one
                : (answers.alcoholLast6Hours == false ? PreSleepLogAnswers.AlcoholLevel.none : nil),
            alcoholLastDrinkAt: answers.alcoholLast6Hours == true ? now : nil,
            alcoholLastAmountDrinks: answers.alcoholLast6Hours == true ? 1 : nil,
            alcoholDailyTotalDrinks: answers.alcoholLast6Hours == true ? 1 : nil,
            exercise: answers.exerciseLast4Hours == true
                ? .moderate
                : (answers.exerciseLast4Hours == false ? PreSleepLogAnswers.ExerciseLevel.none : nil),
            exerciseType: answers.exerciseLast4Hours == true ? .cardio : nil,
            exerciseLastAt: answers.exerciseLast4Hours == true ? now : nil,
            exerciseDurationMinutes: answers.exerciseLast4Hours == true ? 30 : nil,
            lateMeal: answers.heavyMealLast3Hours == true
                ? .heavyMeal
                : (answers.heavyMealLast3Hours == false ? PreSleepLogAnswers.LateMeal.none : nil),
            screensInBed: answers.screenTime30MinPrior == true
                ? .thirtyMin
                : (answers.screenTime30MinPrior == false ? PreSleepLogAnswers.ScreensInBed.none : nil),
            notes: answers.notes
        )

        if let goalHours = answers.sleepGoalHours, goalHours > 0 {
            mapped.notes = [mapped.notes, "Sleep goal: \(goalHours)h \(answers.sleepGoalMinutes ?? 0)m"]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " | ")
        }

        _ = try savePreSleepLogOrThrow(
            sessionId: sessionKey,
            answers: mapped,
            completionState: completionState,
            now: now,
            timeZone: timeZoneProvider(),
            existingLog: fetchMostRecentPreSleepLog(sessionId: sessionKey)
        )
    }
    
    public func fetchPreSleepLog(sessionKey: String) -> DoseCore.StoredPreSleepLog? {
        guard let local = fetchMostRecentPreSleepLog(sessionId: sessionKey) else { return nil }
        // Convert local type to DoseCore type
        // local.createdAtUtc is String, DoseCore.createdAtUTC is Date
        // local.answers is PreSleepLogAnswers?, DoseCore.answersJson is String
        let createdDate = isoFormatter.date(from: local.createdAtUtc) ?? Date()
        let answersJsonStr: String
        if let answers = local.answers {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(answers), let str = String(data: data, encoding: .utf8) {
                answersJsonStr = str
            } else {
                answersJsonStr = "{}"
            }
        } else {
            answersJsonStr = "{}"
        }
        return DoseCore.StoredPreSleepLog(
            id: local.id,
            sessionId: local.sessionId,
            createdAtUTC: createdDate,
            localOffsetMinutes: local.localOffsetMinutes,
            completionState: local.completionState,
            answersJson: answersJsonStr
        )
    }
    
    // MARK: - Morning Check-Ins
    
    public func saveMorningCheckIn(_ checkIn: DoseCore.StoredMorningCheckIn, sessionKey: String) {
        // Convert DoseCore type to local type and save
        let local = StoredMorningCheckIn(
            id: checkIn.id,
            sessionId: checkIn.sessionId,
            timestamp: checkIn.timestamp,
            sessionDate: checkIn.sessionDate,
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
        saveMorningCheckIn(local, forSession: sessionKey)
    }
    
    public func fetchMorningCheckIn(sessionKey: String) -> DoseCore.StoredMorningCheckIn? {
        guard let local = fetchMorningCheckInInternal(sessionKey: sessionKey) else { return nil }
        return DoseCore.StoredMorningCheckIn(
            id: local.id,
            sessionId: local.sessionId,
            timestamp: local.timestamp,
            sessionDate: local.sessionDate,
            sleepQuality: local.sleepQuality,
            feelRested: local.feelRested,
            grogginess: local.grogginess,
            sleepInertiaDuration: local.sleepInertiaDuration,
            dreamRecall: local.dreamRecall,
            hasPhysicalSymptoms: local.hasPhysicalSymptoms,
            physicalSymptomsJson: local.physicalSymptomsJson,
            hasRespiratorySymptoms: local.hasRespiratorySymptoms,
            respiratorySymptomsJson: local.respiratorySymptomsJson,
            mentalClarity: local.mentalClarity,
            mood: local.mood,
            anxietyLevel: local.anxietyLevel,
            stressLevel: local.stressLevel,
            stressContextJson: local.stressContextJson,
            readinessForDay: local.readinessForDay,
            hadSleepParalysis: local.hadSleepParalysis,
            hadHallucinations: local.hadHallucinations,
            hadAutomaticBehavior: local.hadAutomaticBehavior,
            fellOutOfBed: local.fellOutOfBed,
            hadConfusionOnWaking: local.hadConfusionOnWaking,
            usedSleepTherapy: local.usedSleepTherapy,
            sleepTherapyJson: local.sleepTherapyJson,
            hasSleepEnvironment: local.hasSleepEnvironment,
            sleepEnvironmentJson: local.sleepEnvironmentJson,
            notes: local.notes
        )
    }
    
    private func fetchMorningCheckInInternal(sessionKey: String) -> StoredMorningCheckIn? {
        let sql = """
        SELECT id, session_id, timestamp, session_date, sleep_quality, feel_rested, grogginess,
               sleep_inertia_duration, dream_recall, has_physical_symptoms, physical_symptoms_json,
               has_respiratory_symptoms, respiratory_symptoms_json, mental_clarity, mood, anxiety_level,
               stress_level, stress_context_json, readiness_for_day, had_sleep_paralysis,
               had_hallucinations, had_automatic_behavior, fell_out_of_bed, had_confusion_on_waking,
               used_sleep_therapy, sleep_therapy_json, has_sleep_environment, sleep_environment_json, notes
        FROM morning_checkins
        WHERE session_id = ? OR session_date = ?
        ORDER BY timestamp DESC
        LIMIT 1
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, sessionKey, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        
        guard let idPtr = sqlite3_column_text(stmt, 0),
              let sessionIdPtr = sqlite3_column_text(stmt, 1),
              let timestampPtr = sqlite3_column_text(stmt, 2),
              let sessionDatePtr = sqlite3_column_text(stmt, 3) else { return nil }
        
        let timestamp = isoFormatter.date(from: String(cString: timestampPtr)) ?? Date()
        
        return StoredMorningCheckIn(
            id: String(cString: idPtr),
            sessionId: String(cString: sessionIdPtr),
            timestamp: timestamp,
            sessionDate: String(cString: sessionDatePtr),
            sleepQuality: Int(sqlite3_column_int(stmt, 4)),
            feelRested: sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "moderate",
            grogginess: sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "mild",
            sleepInertiaDuration: sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? "fiveToFifteen",
            dreamRecall: sqlite3_column_text(stmt, 8).map { String(cString: $0) } ?? "none",
            hasPhysicalSymptoms: sqlite3_column_int(stmt, 9) != 0,
            physicalSymptomsJson: sqlite3_column_text(stmt, 10).map { String(cString: $0) },
            hasRespiratorySymptoms: sqlite3_column_int(stmt, 11) != 0,
            respiratorySymptomsJson: sqlite3_column_text(stmt, 12).map { String(cString: $0) },
            mentalClarity: Int(sqlite3_column_int(stmt, 13)),
            mood: sqlite3_column_text(stmt, 14).map { String(cString: $0) } ?? "neutral",
            anxietyLevel: sqlite3_column_text(stmt, 15).map { String(cString: $0) } ?? "none",
            stressLevel: sqlite3_column_type(stmt, 16) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 16)),
            stressContextJson: sqlite3_column_text(stmt, 17).map { String(cString: $0) },
            readinessForDay: Int(sqlite3_column_int(stmt, 18)),
            hadSleepParalysis: sqlite3_column_int(stmt, 19) != 0,
            hadHallucinations: sqlite3_column_int(stmt, 20) != 0,
            hadAutomaticBehavior: sqlite3_column_int(stmt, 21) != 0,
            fellOutOfBed: sqlite3_column_int(stmt, 22) != 0,
            hadConfusionOnWaking: sqlite3_column_int(stmt, 23) != 0,
            usedSleepTherapy: sqlite3_column_int(stmt, 24) != 0,
            sleepTherapyJson: sqlite3_column_text(stmt, 25).map { String(cString: $0) },
            hasSleepEnvironment: sqlite3_column_int(stmt, 26) != 0,
            sleepEnvironmentJson: sqlite3_column_text(stmt, 27).map { String(cString: $0) },
            notes: sqlite3_column_text(stmt, 28).map { String(cString: $0) }
        )
    }
    
    // MARK: - Session Management
    
    public func fetchRecentSessions(days: Int) -> [DoseCore.SessionSummary] {
        let localSessions = fetchRecentSessionsInternal(days: days)
        return localSessions.map { local in
            DoseCore.SessionSummary(
                sessionDate: local.sessionDate,
                dose1Time: local.dose1Time,
                dose2Time: local.dose2Time,
                dose2Skipped: local.dose2Skipped,
                snoozeCount: local.snoozeCount,
                sleepEvents: local.sleepEvents.map { event in
                    DoseCore.StoredSleepEvent(
                        id: event.id,
                        eventType: event.eventType,
                        timestamp: event.timestamp,
                        sessionDate: event.sessionDate,
                        colorHex: event.colorHex,
                        notes: event.notes
                    )
                },
                eventCount: local.eventCount
            )
        }
    }
    
    private func fetchRecentSessionsInternal(days: Int) -> [SessionSummary] {
        fetchRecentSessionsLocal(days: days)
    }
    
    public func deleteSession(sessionKey: String) {
        deleteSession(sessionDate: sessionKey)
    }
}
