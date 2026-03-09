import Foundation
import DoseCore

/// Event record for compatibility with legacy code
public struct EventRecord: Identifiable {
    public let id: UUID
    public let type: String
    public let timestamp: Date
    public let metadata: String?
    
    public init(type: String, timestamp: Date, metadata: String? = nil) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

// MARK: - Storage Data Models

/// Stored medication entry model for EventStorage
public typealias StoredMedicationEntry = SQLiteStoredMedicationEntry

/// Stored pre-sleep log model for EventStorage
public struct StoredPreSleepLog: Identifiable {
    public let id: String
    public let sessionId: String?
    public let createdAtUtc: String
    public let localOffsetMinutes: Int
    public let completionState: String
    public let answers: PreSleepLogAnswers?
    
    public init(id: String, sessionId: String?, createdAtUtc: String, localOffsetMinutes: Int, completionState: String, answers: PreSleepLogAnswers?) {
        self.id = id
        self.sessionId = sessionId
        self.createdAtUtc = createdAtUtc
        self.localOffsetMinutes = localOffsetMinutes
        self.completionState = completionState
        self.answers = answers
    }
}

/// Stored normalized questionnaire submission for pre-night and morning check-ins.
public struct StoredCheckInSubmission: Identifiable {
    public let id: String
    public let sourceRecordId: String
    public let sessionId: String?
    public let sessionDate: String
    public let checkInType: EventStorage.CheckInType
    public let questionnaireVersion: String
    public let userId: String
    public let submittedAtUTC: Date
    public let localOffsetMinutes: Int
    public let responsesJson: String

    public init(
        id: String,
        sourceRecordId: String,
        sessionId: String?,
        sessionDate: String,
        checkInType: EventStorage.CheckInType,
        questionnaireVersion: String,
        userId: String,
        submittedAtUTC: Date,
        localOffsetMinutes: Int,
        responsesJson: String
    ) {
        self.id = id
        self.sourceRecordId = sourceRecordId
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.checkInType = checkInType
        self.questionnaireVersion = questionnaireVersion
        self.userId = userId
        self.submittedAtUTC = submittedAtUTC
        self.localOffsetMinutes = localOffsetMinutes
        self.responsesJson = responsesJson
    }
}

/// Pre-sleep log model for creating new logs (input model)
public struct PreSleepLog: Identifiable {
    public let id: String
    public let sessionId: String?
    public let answers: PreSleepLogAnswers
    public let completionState: String
    public let createdAt: Date
    
    public init(answers: PreSleepLogAnswers, completionState: String = "complete", sessionId: String? = nil) {
        self.id = UUID().uuidString
        self.sessionId = sessionId
        self.answers = answers
        self.completionState = completionState
        self.createdAt = Date()
    }
}

/// Pending outbound CloudKit delete marker.
public struct CloudKitTombstone: Identifiable {
    public let key: String
    public let recordType: String
    public let recordName: String
    public let createdAt: Date

    public var id: String { key }

    public init(key: String, recordType: String, recordName: String, createdAt: Date) {
        self.key = key
        self.recordType = recordType
        self.recordName = recordName
        self.createdAt = createdAt
    }
}

/// Stored sleep event model for EventStorage
public struct StoredSleepEvent: Identifiable {
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

/// Stored dose log model - represents a complete session's dose data
public struct StoredDoseLog: Identifiable {
    public let id: String
    public let sessionDate: String
    public let dose1Time: Date
    public let dose2Time: Date?
    public let dose2Skipped: Bool
    public let snoozeCount: Int
    
    public init(id: String, sessionDate: String, dose1Time: Date, dose2Time: Date? = nil, dose2Skipped: Bool = false, snoozeCount: Int = 0) {
        self.id = id
        self.sessionDate = sessionDate
        self.dose1Time = dose1Time
        self.dose2Time = dose2Time
        self.dose2Skipped = dose2Skipped
        self.snoozeCount = snoozeCount
    }
    
    public var intervalMinutes: Int? {
        guard let dose2Time else { return nil }
        return TimeIntervalMath.minutesBetween(start: dose1Time, end: dose2Time)
    }
    
    public var skipped: Bool { dose2Skipped }
}

/// Session summary for history views
public struct SessionSummary: Identifiable {
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
    
    public init(sessionDate: String, dose1Time: Date? = nil, dose2Time: Date? = nil, dose2Skipped: Bool = false, snoozeCount: Int = 0, sleepEvents: [StoredSleepEvent] = [], eventCount: Int? = nil) {
        self.id = sessionDate
        self.sessionDate = sessionDate
        self.dose1Time = dose1Time
        self.dose2Time = dose2Time
        self.dose2Skipped = dose2Skipped
        self.snoozeCount = snoozeCount
        self.sleepEvents = sleepEvents
        self.eventCount = eventCount ?? sleepEvents.count
        
        if let dose1Time, let dose2Time {
            self.intervalMinutes = TimeIntervalMath.minutesBetween(start: dose1Time, end: dose2Time)
        } else {
            self.intervalMinutes = nil
        }
    }
}

/// Stored morning check-in model for EventStorage
public struct StoredMorningCheckIn: Identifiable {
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
    public let notes: String?
    
    public var hasNarcolepsySymptoms: Bool {
        hadSleepParalysis || hadHallucinations || hadAutomaticBehavior || fellOutOfBed || hadConfusionOnWaking
    }
    
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
        self.notes = notes
    }
}

public struct MorningStressContext: Equatable {
    public let drivers: [CommonStressDriver]
    public let progression: CommonStressProgression?
    public let notes: String?

    public var primaryDriver: CommonStressDriver? {
        drivers.first
    }
}

public extension StoredMorningCheckIn {
    var resolvedStressContext: MorningStressContext? {
        guard let stressContextJson, let data = stressContextJson.data(using: .utf8) else {
            return nil
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let drivers = ((json["drivers"] as? [String]) ?? [])
            .compactMap(CommonStressDriver.init(rawValue:))
        let progression = (json["progression"] as? String)
            .flatMap(CommonStressProgression.init(rawValue:))
        let notes = (json["notes"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !drivers.isEmpty || progression != nil || !(notes?.isEmpty ?? true) else {
            return nil
        }

        return MorningStressContext(
            drivers: drivers,
            progression: progression,
            notes: notes?.isEmpty == true ? nil : notes
        )
    }

    var resolvedStressDrivers: [CommonStressDriver] {
        resolvedStressContext?.drivers ?? []
    }

    var primaryStressDriver: CommonStressDriver? {
        resolvedStressContext?.primaryDriver
    }

    var stressProgression: CommonStressProgression? {
        resolvedStressContext?.progression
    }

    var stressNotes: String? {
        resolvedStressContext?.notes
    }
}

public enum CommonStressDriver: String, Codable, CaseIterable {
    case work = "work"
    case family = "family"
    case relationship = "relationship"
    case health = "health"
    case pain = "pain"
    case sleep = "sleep"
    case medication = "medication"
    case environment = "environment"
    case schedule = "schedule"
    case financial = "financial"
    case other = "other"

    public var displayText: String {
        switch self {
        case .work: return "Work"
        case .family: return "Family"
        case .relationship: return "Relationship"
        case .health: return "Health"
        case .pain: return "Pain"
        case .sleep: return "Sleep"
        case .medication: return "Medication"
        case .environment: return "Environment"
        case .schedule: return "Schedule"
        case .financial: return "Financial"
        case .other: return "Other"
        }
    }
}

public enum CommonStressProgression: String, Codable, CaseIterable {
    case muchBetter = "much_better"
    case better = "better"
    case same = "same"
    case worse = "worse"
    case muchWorse = "much_worse"

    public var displayText: String {
        switch self {
        case .muchBetter: return "Much Better"
        case .better: return "Better"
        case .same: return "About The Same"
        case .worse: return "Worse"
        case .muchWorse: return "Much Worse"
        }
    }
}
