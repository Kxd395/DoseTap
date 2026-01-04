import Foundation

// MARK: - Stored Models (Core versions)

/// Stored sleep event from the database
public struct StoredSleepEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let eventType: String
    public let timestamp: Date
    public let sessionDate: String
    public let colorHex: String?
    public let notes: String?
    
    public init(id: String, eventType: String, timestamp: Date, sessionDate: String, colorHex: String? = nil, notes: String? = nil) {
        self.id = id
        self.eventType = eventType
        self.timestamp = timestamp
        self.sessionDate = sessionDate
        self.colorHex = colorHex
        self.notes = notes
    }
}

/// Stored dose event from the database
public struct StoredDoseEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let eventType: String
    public let timestamp: Date
    public let sessionDate: String
    public let metadata: String?
    
    public init(id: String, eventType: String, timestamp: Date, sessionDate: String, metadata: String? = nil) {
        self.id = id
        self.eventType = eventType
        self.timestamp = timestamp
        self.sessionDate = sessionDate
        self.metadata = metadata
    }
}

/// Pre-sleep log answers
public struct PreSleepLogAnswers: Codable, Equatable, Sendable {
    public var sleepGoalHours: Int?
    public var sleepGoalMinutes: Int?
    public var caffeineLast6Hours: Bool?
    public var alcoholLast6Hours: Bool?
    public var exerciseLast4Hours: Bool?
    public var heavyMealLast3Hours: Bool?
    public var stressLevel: Int?
    public var screenTime30MinPrior: Bool?
    public var notes: String?
    
    public init(
        sleepGoalHours: Int? = nil,
        sleepGoalMinutes: Int? = nil,
        caffeineLast6Hours: Bool? = nil,
        alcoholLast6Hours: Bool? = nil,
        exerciseLast4Hours: Bool? = nil,
        heavyMealLast3Hours: Bool? = nil,
        stressLevel: Int? = nil,
        screenTime30MinPrior: Bool? = nil,
        notes: String? = nil
    ) {
        self.sleepGoalHours = sleepGoalHours
        self.sleepGoalMinutes = sleepGoalMinutes
        self.caffeineLast6Hours = caffeineLast6Hours
        self.alcoholLast6Hours = alcoholLast6Hours
        self.exerciseLast4Hours = exerciseLast4Hours
        self.heavyMealLast3Hours = heavyMealLast3Hours
        self.stressLevel = stressLevel
        self.screenTime30MinPrior = screenTime30MinPrior
        self.notes = notes
    }
}

/// Pre-sleep log from the database
public struct StoredPreSleepLog: Identifiable, Equatable, Sendable {
    public let id: String
    public let sessionId: String?
    public let createdAtUTC: Date
    public let localOffsetMinutes: Int
    public let completionState: String
    public let answersJson: String
    
    public init(
        id: String,
        sessionId: String?,
        createdAtUTC: Date,
        localOffsetMinutes: Int,
        completionState: String,
        answersJson: String
    ) {
        self.id = id
        self.sessionId = sessionId
        self.createdAtUTC = createdAtUTC
        self.localOffsetMinutes = localOffsetMinutes
        self.completionState = completionState
        self.answersJson = answersJson
    }
}

/// Morning check-in from the database
public struct StoredMorningCheckIn: Identifiable, Equatable, Sendable {
    public let id: String
    public let sessionId: String
    public let timestamp: Date
    public let sessionDate: String
    public let sleepQuality: Int
    public let feelRested: String
    public let grogginess: String
    public let sleepInertiaDuration: String
    public let dreamRecall: String
    public let hasPhysicalSymptoms: Bool
    public let physicalSymptomsJson: String?
    public let hasRespiratorySymptoms: Bool
    public let respiratorySymptomsJson: String?
    public let mentalClarity: Int
    public let mood: String
    public let anxietyLevel: String
    public let readinessForDay: Int
    public let hadSleepParalysis: Bool
    public let hadHallucinations: Bool
    public let hadAutomaticBehavior: Bool
    public let fellOutOfBed: Bool
    public let hadConfusionOnWaking: Bool
    public let usedSleepTherapy: Bool
    public let sleepTherapyJson: String?
    public let hasSleepEnvironment: Bool
    public let sleepEnvironmentJson: String?
    public let notes: String?
    
    public init(
        id: String,
        sessionId: String,
        timestamp: Date,
        sessionDate: String,
        sleepQuality: Int = 3,
        feelRested: String = "moderate",
        grogginess: String = "mild",
        sleepInertiaDuration: String = "fiveToFifteen",
        dreamRecall: String = "none",
        hasPhysicalSymptoms: Bool = false,
        physicalSymptomsJson: String? = nil,
        hasRespiratorySymptoms: Bool = false,
        respiratorySymptomsJson: String? = nil,
        mentalClarity: Int = 5,
        mood: String = "neutral",
        anxietyLevel: String = "none",
        readinessForDay: Int = 3,
        hadSleepParalysis: Bool = false,
        hadHallucinations: Bool = false,
        hadAutomaticBehavior: Bool = false,
        fellOutOfBed: Bool = false,
        hadConfusionOnWaking: Bool = false,
        usedSleepTherapy: Bool = false,
        sleepTherapyJson: String? = nil,
        hasSleepEnvironment: Bool = false,
        sleepEnvironmentJson: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.sessionDate = sessionDate
        self.sleepQuality = sleepQuality
        self.feelRested = feelRested
        self.grogginess = grogginess
        self.sleepInertiaDuration = sleepInertiaDuration
        self.dreamRecall = dreamRecall
        self.hasPhysicalSymptoms = hasPhysicalSymptoms
        self.physicalSymptomsJson = physicalSymptomsJson
        self.hasRespiratorySymptoms = hasRespiratorySymptoms
        self.respiratorySymptomsJson = respiratorySymptomsJson
        self.mentalClarity = mentalClarity
        self.mood = mood
        self.anxietyLevel = anxietyLevel
        self.readinessForDay = readinessForDay
        self.hadSleepParalysis = hadSleepParalysis
        self.hadHallucinations = hadHallucinations
        self.hadAutomaticBehavior = hadAutomaticBehavior
        self.fellOutOfBed = fellOutOfBed
        self.hadConfusionOnWaking = hadConfusionOnWaking
        self.usedSleepTherapy = usedSleepTherapy
        self.sleepTherapyJson = sleepTherapyJson
        self.hasSleepEnvironment = hasSleepEnvironment
        self.sleepEnvironmentJson = sleepEnvironmentJson
        self.notes = notes
    }
}

/// Session summary for history views
public struct SessionSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let sessionDate: String
    public let dose1Time: Date?
    public let dose2Time: Date?
    public let dose2Skipped: Bool
    public let snoozeCount: Int
    public let intervalMinutes: Int?
    public let sleepEvents: [StoredSleepEvent]
    public let eventCount: Int
    
    public var skipped: Bool { dose2Skipped }
    
    public init(
        sessionDate: String,
        dose1Time: Date? = nil,
        dose2Time: Date? = nil,
        dose2Skipped: Bool = false,
        snoozeCount: Int = 0,
        sleepEvents: [StoredSleepEvent] = [],
        eventCount: Int? = nil
    ) {
        self.id = sessionDate
        self.sessionDate = sessionDate
        self.dose1Time = dose1Time
        self.dose2Time = dose2Time
        self.dose2Skipped = dose2Skipped
        self.snoozeCount = snoozeCount
        self.sleepEvents = sleepEvents
        self.eventCount = eventCount ?? sleepEvents.count
        
        if let d1 = dose1Time, let d2 = dose2Time {
            self.intervalMinutes = TimeIntervalMath.minutesBetween(start: d1, end: d2)
        } else {
            self.intervalMinutes = nil
        }
    }
}

// MARK: - EventStore Protocol

/// Single source of truth protocol for all event storage operations.
/// UI and business logic should ONLY interact with storage through this protocol.
/// 
/// This eliminates "split brain" bugs where data is written to one store
/// but read from another, causing "I logged it and it vanished" symptoms.
@MainActor
public protocol EventStore: AnyObject {
    
    // MARK: - Session Identity
    
    /// Get the current session key (yyyy-MM-dd format, 6 PM rollover)
    func currentSessionKey() -> String
    
    /// Get all session keys that have data
    func getAllSessionKeys() -> [String]
    
    // MARK: - Sleep Events
    
    /// Insert a sleep event with explicit session key
    func insertSleepEvent(
        id: String,
        eventType: String,
        timestamp: Date,
        sessionKey: String,
        colorHex: String?,
        notes: String?
    )
    
    /// Fetch sleep events for a specific session
    func fetchSleepEvents(sessionKey: String) -> [StoredSleepEvent]
    
    /// Fetch sleep events for tonight's session
    func fetchTonightSleepEvents() -> [StoredSleepEvent]
    
    /// Fetch all sleep events (for export/history)
    func fetchAllSleepEvents(limit: Int) -> [StoredSleepEvent]
    
    /// Delete a sleep event by ID
    func deleteSleepEvent(id: String)
    
    // MARK: - Dose Events
    
    /// Insert a dose event (dose1, dose2, snooze, skip)
    func insertDoseEvent(
        eventType: String,
        timestamp: Date,
        sessionKey: String,
        metadata: String?
    )
    
    /// Fetch dose events for a session
    func fetchDoseEvents(sessionKey: String) -> [StoredDoseEvent]
    
    /// Check if a dose type exists for a session
    func hasDose(type: String, sessionKey: String) -> Bool
    
    // MARK: - Session State (current_session table)
    
    /// Save dose 1 timestamp
    func saveDose1(timestamp: Date)
    
    /// Save dose 2 timestamp
    func saveDose2(timestamp: Date, isEarly: Bool, isExtraDose: Bool)
    
    /// Save dose skip
    func saveDoseSkipped(reason: String?)
    
    /// Save snooze count
    func saveSnooze(count: Int)
    
    /// Clear dose 1 (for undo)
    func clearDose1()
    
    /// Clear dose 2 (for undo)
    func clearDose2()
    
    /// Clear skip (for undo)
    func clearSkip()
    
    /// Load current session state
    func loadCurrentSession() -> (dose1Time: Date?, dose2Time: Date?, snoozeCount: Int, dose2Skipped: Bool)
    
    // MARK: - Pre-Sleep Logs
    
    /// Save pre-sleep log with explicit session key (throws on failure)
    func savePreSleepLogOrThrow(
        sessionKey: String,
        answers: PreSleepLogAnswers,
        completionState: String
    ) throws
    
    /// Fetch most recent pre-sleep log for a session
    func fetchPreSleepLog(sessionKey: String) -> StoredPreSleepLog?
    
    /// Link orphan pre-sleep log to session (migration/backfill)
    func linkPreSleepLogToSession(sessionKey: String)
    
    // MARK: - Morning Check-Ins
    
    /// Save morning check-in
    func saveMorningCheckIn(_ checkIn: StoredMorningCheckIn, sessionKey: String)
    
    /// Fetch morning check-in for a session
    func fetchMorningCheckIn(sessionKey: String) -> StoredMorningCheckIn?
    
    // MARK: - Session Management
    
    /// Fetch recent sessions with summaries
    func fetchRecentSessions(days: Int) -> [SessionSummary]
    
    /// Delete an entire session and all related data
    func deleteSession(sessionKey: String)
    
    /// Clear all data (for testing/reset)
    func clearAllData()
    
    // MARK: - Export
    
    /// Export all data to CSV
    func exportToCSV() -> String
    
    // MARK: - Migration Support
    
    /// Backfill session_id for rows with NULL
    func backfillNullSessionIds()
}
