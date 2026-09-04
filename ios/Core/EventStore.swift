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
    public let sessionId: String?
    
    public init(id: String, eventType: String, timestamp: Date, sessionDate: String, metadata: String? = nil, sessionId: String? = nil) {
        self.id = id
        self.eventType = eventType
        self.timestamp = timestamp
        self.sessionDate = sessionDate
        self.metadata = metadata
        self.sessionId = sessionId
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
    public let sleepQuality: Double
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
    public let stressLevel: Int?
    public let stressContextJson: String?
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
    public let timingContextJson: String?
    public let notes: String?
    
    public init(
        id: String,
        sessionId: String,
        timestamp: Date,
        sessionDate: String,
        sleepQuality: Double = 3,
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
        stressLevel: Int? = nil,
        stressContextJson: String? = nil,
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
        timingContextJson: String? = nil,
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
        self.stressLevel = stressLevel
        self.stressContextJson = stressContextJson
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
        self.timingContextJson = timingContextJson
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

// MARK: - Medication Mutation Results

/// Canonical operation names for medication writes. These values are suitable
/// for diagnostics; user-facing copy comes from `MedicationMutationFailure`.
public enum MedicationMutationOperation: String, Equatable, Sendable {
    case databaseInitialization = "database_initialization"
    case dose1 = "dose1"
    case dose2 = "dose2"
    case extraDose = "extra_dose"
    case skipDose2 = "skip_dose2"
    case snooze = "snooze"
    case clearDoseSequence = "clear_dose_sequence"
    case clearDose2 = "clear_dose2"
    case clearSkip = "clear_skip"
    case rollbackSnooze = "rollback_snooze"
    case updateDose1Time = "update_dose1_time"
    case updateDose2Time = "update_dose2_time"
    case reconcileDoseState = "reconcile_dose_state"
    case workSchedule = "work_schedule"
}

public struct MedicationMutationReceipt: Equatable, Sendable {
    public let operation: MedicationMutationOperation
    public let sessionId: String
    public let sessionDate: String
    public let timestamp: Date?

    public init(
        operation: MedicationMutationOperation,
        sessionId: String,
        sessionDate: String,
        timestamp: Date?
    ) {
        self.operation = operation
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.timestamp = timestamp
    }
}

public struct MedicationMutationFailure: Error, Equatable, Sendable {
    public enum Code: String, Equatable, Sendable {
        case databaseUnavailable = "database_unavailable"
        case diskFull = "disk_full"
        case corrupted = "corrupted"
        case constraint = "constraint"
        case busy = "busy"
        case io = "io"
        case statement = "statement"
        case transaction = "transaction"
        case precondition = "precondition"
        case unknown = "unknown"
    }

    public enum Stage: String, Equatable, Sendable {
        case open
        case preflight
        case begin
        case delete
        case insert
        case update
        case commit
        case rollback
    }

    public let operation: MedicationMutationOperation
    public let code: Code
    public let stage: Stage
    public let sqliteCode: Int32?
    public let detail: String

    public init(
        operation: MedicationMutationOperation,
        code: Code,
        stage: Stage,
        sqliteCode: Int32? = nil,
        detail: String
    ) {
        self.operation = operation
        self.code = code
        self.stage = stage
        self.sqliteCode = sqliteCode
        self.detail = detail
    }

    public var isRetryable: Bool {
        switch code {
        case .corrupted, .constraint, .precondition:
            return false
        case .databaseUnavailable, .diskFull, .busy, .io, .statement, .transaction, .unknown:
            return true
        }
    }

    public var userMessage: String {
        switch code {
        case .databaseUnavailable:
            return "DoseTap storage is unavailable. Unlock the device or reopen the app, then retry."
        case .diskFull:
            return "The dose was not saved because device storage is full. Free space, then retry."
        case .corrupted:
            return "The dose was not saved because the local database could not be read safely. Restart DoseTap and contact support if this continues."
        case .busy:
            return "The dose was not saved because storage is temporarily busy. Retry now."
        case .precondition:
            return detail
        case .constraint, .io, .statement, .transaction, .unknown:
            return "The dose was not saved. Retry and confirm it appears before relying on it."
        }
    }
}

public enum MedicationMutationResult: Equatable, Sendable {
    case committed(MedicationMutationReceipt)
    case failed(MedicationMutationFailure)

    public var receipt: MedicationMutationReceipt? {
        if case .committed(let receipt) = self { return receipt }
        return nil
    }

    public var failure: MedicationMutationFailure? {
        if case .failed(let failure) = self { return failure }
        return nil
    }

    public var isCommitted: Bool {
        receipt != nil
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
    @discardableResult func saveDose1(timestamp: Date) -> MedicationMutationResult
    
    /// Save dose 2 timestamp
    @discardableResult func saveDose2(timestamp: Date, isEarly: Bool, isExtraDose: Bool) -> MedicationMutationResult
    
    /// Save dose skip
    @discardableResult func saveDoseSkipped(reason: String?) -> MedicationMutationResult
    
    /// Save snooze count
    @discardableResult func saveSnooze(count: Int) -> MedicationMutationResult
    
    /// Clear dose 1 (for undo)
    @discardableResult func clearDose1() -> MedicationMutationResult
    
    /// Clear dose 2 (for undo)
    @discardableResult func clearDose2() -> MedicationMutationResult
    
    /// Clear skip (for undo)
    @discardableResult func clearSkip() -> MedicationMutationResult
    
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
