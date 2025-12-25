import Foundation

// MARK: - Medication Configuration (from SSOT constants.json)

/// Configuration for medication logging feature.
/// All values derived from docs/SSOT/constants.json "medications" section.
public struct MedicationConfig {
    public static let duplicateGuardMinutes: Int = 5
    
    public static let types: [MedicationType] = [
        MedicationType(
            id: "adderall_ir",
            displayName: "Adderall",
            category: .stimulant,
            formulation: .immediateRelease,
            defaultDoseMg: 10,
            validDoses: [5, 10, 15, 20, 25, 30],
            iconName: "pill.fill",
            colorHex: "#FF6B35"
        ),
        MedicationType(
            id: "adderall_xr",
            displayName: "Adderall XR",
            category: .stimulant,
            formulation: .extendedRelease,
            defaultDoseMg: 20,
            validDoses: [5, 10, 15, 20, 25, 30],
            iconName: "pill.circle.fill",
            colorHex: "#4ECDC4"
        )
    ]
    
    public static func type(for id: String) -> MedicationType? {
        types.first { $0.id == id }
    }
}

// MARK: - Medication Type Definition

public struct MedicationType: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let category: MedicationCategory
    public let formulation: MedicationFormulation
    public let defaultDoseMg: Int
    public let validDoses: [Int]
    public let iconName: String
    public let colorHex: String
    
    public init(
        id: String,
        displayName: String,
        category: MedicationCategory,
        formulation: MedicationFormulation,
        defaultDoseMg: Int,
        validDoses: [Int],
        iconName: String,
        colorHex: String
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.formulation = formulation
        self.defaultDoseMg = defaultDoseMg
        self.validDoses = validDoses
        self.iconName = iconName
        self.colorHex = colorHex
    }
}

public enum MedicationCategory: String, Codable, Sendable {
    case stimulant
}

public enum MedicationFormulation: String, Codable, Sendable {
    case immediateRelease = "immediate_release"
    case extendedRelease = "extended_release"
}

// MARK: - Medication Entry (Database Model)

/// A logged medication event, stored in medication_events table.
public struct MedicationEntry: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let sessionId: String?  // FK to dose_sessions, nullable for unlinked entries
    public let sessionDate: String // Computed session date (6PM boundary), always present
    public let medicationId: String
    public let doseMg: Int
    public let takenAtUTC: Date
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
        notes: String? = nil,
        confirmedDuplicate: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.medicationId = medicationId
        self.doseMg = doseMg
        self.takenAtUTC = takenAtUTC
        self.notes = notes
        self.confirmedDuplicate = confirmedDuplicate
        self.createdAt = createdAt
    }
    
    /// Computed display name from medication type
    public var displayName: String {
        MedicationConfig.type(for: medicationId)?.displayName ?? medicationId
    }
}

// MARK: - Duplicate Guard Result

public struct DuplicateGuardResult: Equatable, Sendable {
    public let isDuplicate: Bool
    public let existingEntry: MedicationEntry?
    public let minutesDelta: Int
    
    public init(isDuplicate: Bool, existingEntry: MedicationEntry?, minutesDelta: Int) {
        self.isDuplicate = isDuplicate
        self.existingEntry = existingEntry
        self.minutesDelta = minutesDelta
    }
    
    public static let notDuplicate = DuplicateGuardResult(isDuplicate: false, existingEntry: nil, minutesDelta: 0)
}
