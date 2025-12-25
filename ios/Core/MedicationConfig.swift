import Foundation

// MARK: - Medication Configuration (from SSOT constants.json)

/// Configuration for medication logging feature.
/// All values derived from docs/SSOT/constants.json "medications" section.
/// Includes all FDA-approved narcolepsy medications.
public struct MedicationConfig {
    public static let duplicateGuardMinutes: Int = 5
    
    // MARK: - All Narcolepsy Medications
    
    public static let types: [MedicationType] = [
        // === STIMULANTS ===
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
        ),
        MedicationType(
            id: "ritalin_ir",
            displayName: "Ritalin",
            category: .stimulant,
            formulation: .immediateRelease,
            defaultDoseMg: 10,
            validDoses: [5, 10, 15, 20],
            iconName: "pill.fill",
            colorHex: "#9B59B6"
        ),
        MedicationType(
            id: "ritalin_la",
            displayName: "Ritalin LA",
            category: .stimulant,
            formulation: .extendedRelease,
            defaultDoseMg: 20,
            validDoses: [10, 20, 30, 40],
            iconName: "pill.circle.fill",
            colorHex: "#8E44AD"
        ),
        MedicationType(
            id: "concerta",
            displayName: "Concerta",
            category: .stimulant,
            formulation: .extendedRelease,
            defaultDoseMg: 36,
            validDoses: [18, 27, 36, 54],
            iconName: "pill.circle.fill",
            colorHex: "#3498DB"
        ),
        MedicationType(
            id: "vyvanse",
            displayName: "Vyvanse",
            category: .stimulant,
            formulation: .extendedRelease,
            defaultDoseMg: 30,
            validDoses: [10, 20, 30, 40, 50, 60, 70],
            iconName: "capsule.fill",
            colorHex: "#E74C3C"
        ),
        MedicationType(
            id: "dexedrine",
            displayName: "Dexedrine",
            category: .stimulant,
            formulation: .immediateRelease,
            defaultDoseMg: 10,
            validDoses: [5, 10, 15],
            iconName: "pill.fill",
            colorHex: "#F39C12"
        ),
        
        // === WAKEFULNESS AGENTS ===
        MedicationType(
            id: "modafinil",
            displayName: "Modafinil",
            category: .wakefulnessAgent,
            formulation: .immediateRelease,
            defaultDoseMg: 200,
            validDoses: [100, 200],
            iconName: "sun.max.fill",
            colorHex: "#F1C40F"
        ),
        MedicationType(
            id: "provigil",
            displayName: "Provigil",
            category: .wakefulnessAgent,
            formulation: .immediateRelease,
            defaultDoseMg: 200,
            validDoses: [100, 200],
            iconName: "sun.max.fill",
            colorHex: "#F1C40F"
        ),
        MedicationType(
            id: "armodafinil",
            displayName: "Armodafinil",
            category: .wakefulnessAgent,
            formulation: .immediateRelease,
            defaultDoseMg: 150,
            validDoses: [50, 150, 200, 250],
            iconName: "sunrise.fill",
            colorHex: "#E67E22"
        ),
        MedicationType(
            id: "nuvigil",
            displayName: "Nuvigil",
            category: .wakefulnessAgent,
            formulation: .immediateRelease,
            defaultDoseMg: 150,
            validDoses: [50, 150, 200, 250],
            iconName: "sunrise.fill",
            colorHex: "#E67E22"
        ),
        MedicationType(
            id: "sunosi",
            displayName: "Sunosi",
            category: .wakefulnessAgent,
            formulation: .immediateRelease,
            defaultDoseMg: 75,
            validDoses: [75, 150],
            iconName: "sun.horizon.fill",
            colorHex: "#1ABC9C"
        ),
        
        // === HISTAMINE MODULATORS ===
        MedicationType(
            id: "wakix",
            displayName: "Wakix",
            category: .histamineModulator,
            formulation: .immediateRelease,
            defaultDoseMg: 35,
            validDoses: [5, 9, 18, 35],
            iconName: "sparkles",
            colorHex: "#9B59B6"
        ),
        
        // === SODIUM OXYBATE (Night medications) ===
        MedicationType(
            id: "xywav",
            displayName: "XYWAV",
            category: .sodiumOxybate,
            formulation: .liquid,
            defaultDoseMg: 4500,  // 4.5g shown as mg
            validDoses: [2250, 3000, 3750, 4500, 6000, 7500, 9000],
            iconName: "drop.fill",
            colorHex: "#2980B9"
        ),
        MedicationType(
            id: "xyrem",
            displayName: "Xyrem",
            category: .sodiumOxybate,
            formulation: .liquid,
            defaultDoseMg: 4500,  // 4.5g shown as mg
            validDoses: [2250, 3000, 3750, 4500, 6000, 7500, 9000],
            iconName: "drop.fill",
            colorHex: "#3498DB"
        ),
        MedicationType(
            id: "lumryz",
            displayName: "Lumryz",
            category: .sodiumOxybate,
            formulation: .extendedRelease,  // Extended-release oral suspension
            defaultDoseMg: 6000,  // 6g typical dose, once nightly
            validDoses: [4500, 6000, 7500, 9000],  // Extended-release doses
            iconName: "moon.fill",
            colorHex: "#6C5CE7"
        ),
    ]
    
    // MARK: - Filtered Lists
    
    /// Daytime medications (stimulants + wakefulness agents)
    public static var daytimeMedications: [MedicationType] {
        types.filter { $0.category != .sodiumOxybate }
    }
    
    /// Night medications (sodium oxybate)
    public static var nightMedications: [MedicationType] {
        types.filter { $0.category == .sodiumOxybate }
    }
    
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
    case wakefulnessAgent = "wakefulness_agent"
    case histamineModulator = "histamine_modulator"
    case sodiumOxybate = "sodium_oxybate"
    
    public var displayName: String {
        switch self {
        case .stimulant: return "Stimulant"
        case .wakefulnessAgent: return "Wakefulness Agent"
        case .histamineModulator: return "Histamine Modulator"
        case .sodiumOxybate: return "Sodium Oxybate"
        }
    }
}

public enum MedicationFormulation: String, Codable, Sendable {
    case immediateRelease = "immediate_release"
    case extendedRelease = "extended_release"
    case liquid
    
    public var displayName: String {
        switch self {
        case .immediateRelease: return "Immediate Release"
        case .extendedRelease: return "Extended Release"
        case .liquid: return "Liquid"
        }
    }
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
