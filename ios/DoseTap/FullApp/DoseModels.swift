import Foundation

/// Unified dose event model for DoseTap
public struct DoseEvent: Codable, Identifiable, Equatable {
    public let id: UUID
    public let type: DoseEventType
    public let timestamp: Date
    public let metadata: [String: String]
    public var eventType: String { type.rawValue }
    
    public init(type: DoseEventType, timestamp: Date = Date(), metadata: [String: String] = [:]) {
        self.id = UUID()
        self.type = type
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

/// Supported dose and sleep event types
public enum DoseEventType: String, Codable, CaseIterable {
    case dose1 = "dose1"
    case dose2 = "dose2"
    case snooze = "snooze"
    case skip = "skip"
    case bathroom = "bathroom"
    case lightsOut = "lights_out"
    case wakeFinal = "wake_final"
}

/// Result of a sleep event logging attempt
public enum SleepEventLogResult {
    case success(timestamp: Date, eventType: String)
    case rateLimited(remainingSeconds: Int)
    case error(String)
    
    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - Compatibility Extensions
import DoseCore

extension DoseWindowContext {
    public var primaryCTA: String {
        switch primary {
        case .takeNow: return "Take Dose 2"
        case .takeBeforeWindowEnds(let rem): return "Take Dose 2 (\(Int(rem/60))m left)"
        case .waitingUntilEarliest(let rem): return "Wait (\(Int(rem/60))m left)"
        case .takeWithOverride: return "Take Dose 2 (Override)"
        case .disabled(let reason): return reason
        }
    }
    
    public var snoozeEnabled: Bool {
        if case .snoozeEnabled = snooze { return true }
        return false
    }
    
    public var skipEnabled: Bool {
        if case .skipEnabled = skip { return true }
        return false
    }
    
    public var timeRemaining: TimeInterval? { remainingToMax }
    public var timeElapsed: TimeInterval? { elapsedSinceDose1 }
}

/// Compatibility record for SQLiteStorage
public struct SQLiteEventRecord: Codable {
    public let type: String
    public let timestamp: Date
    public let metadata: String?
    
    public init(type: String, timestamp: Date, metadata: String? = nil) {
        self.type = type
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

/// Morning check-in record for SQLiteStorage
public struct SQLiteStoredMorningCheckIn: Codable {
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
        sleepQuality: Int,
        feelRested: String,
        grogginess: String,
        sleepInertiaDuration: String,
        dreamRecall: String,
        hasPhysicalSymptoms: Bool,
        physicalSymptomsJson: String?,
        hasRespiratorySymptoms: Bool,
        respiratorySymptomsJson: String?,
        mentalClarity: Int,
        mood: String,
        anxietyLevel: String,
        readinessForDay: Int,
        hadSleepParalysis: Bool,
        hadHallucinations: Bool,
        hadAutomaticBehavior: Bool,
        fellOutOfBed: Bool,
        hadConfusionOnWaking: Bool,
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

/// Medication entry record for SQLiteStorage
public struct SQLiteStoredMedicationEntry: Codable, Identifiable {
    public let id: String
    public let sessionId: String?
    public let sessionDate: String
    public let medicationId: String
    public let doseMg: Int
    public let doseUnit: String
    public let formulation: String
    public let takenAtUTC: Date
    public let localOffsetMinutes: Int
    public let notes: String?
    public let confirmedDuplicate: Bool
    public let createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        sessionId: String?,
        sessionDate: String,
        medicationId: String,
        doseMg: Int,
        takenAtUTC: Date,
        doseUnit: String = "mg",
        formulation: String = "IR",
        localOffsetMinutes: Int = 0,
        notes: String? = nil,
        confirmedDuplicate: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.medicationId = medicationId
        self.doseMg = doseMg
        self.doseUnit = doseUnit
        self.formulation = formulation
        self.takenAtUTC = takenAtUTC
        self.localOffsetMinutes = localOffsetMinutes
        self.notes = notes
        self.confirmedDuplicate = confirmedDuplicate
        self.createdAt = createdAt
    }
}
