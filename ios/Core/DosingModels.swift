//
//  DosingModels.swift
//  DoseTap
//
//  Created: January 19, 2026
//  Purpose: Core data models for dosing amount tracking
//
//  Architecture Overview:
//  ----------------------
//  This file implements a two-layer model for dose tracking:
//
//  1. REGIMEN LAYER (the plan/prescription)
//     - What the user is supposed to take
//     - Total nightly amount, split configuration
//     - Can change over time (date-bounded)
//
//  2. EVENT LAYER (what actually happened)
//     - Each dose administration with timestamp and amount
//     - Grouped into bundles for split dose tracking
//     - Supports analytics and adherence calculations
//
//  Key insight: Without amounts, half-life math is meaningless.
//  "Dose 1 happened" tells us nothing about medication exposure.
//

import Foundation

// MARK: - Amount Unit

/// Supported units for medication amounts.
/// Store the original unit to preserve meaning, normalize internally.
public enum AmountUnit: String, Codable, CaseIterable, Sendable {
    case mg = "mg"           // Milligrams (most common)
    case g = "g"             // Grams (less common)
    case mL = "mL"           // Milliliters (liquids)
    case mcg = "mcg"         // Micrograms (potent meds)
    case tablet = "tablet"   // Count-based (when dose is fixed per unit)
    
    public var displayName: String {
        switch self {
        case .mg: return "mg"
        case .g: return "g"
        case .mL: return "mL"
        case .mcg: return "mcg"
        case .tablet: return "tablet(s)"
        }
    }
    
    /// Convert any supported unit to milligrams for normalization.
    /// Returns nil if conversion is not meaningful (e.g., mL without concentration).
    public func toMilligrams(value: Double, concentration: Double? = nil) -> Double? {
        switch self {
        case .mg:
            return value
        case .g:
            return value * 1000.0
        case .mcg:
            return value / 1000.0
        case .mL:
            // Requires concentration (mg/mL)
            guard let conc = concentration else { return nil }
            return value * conc
        case .tablet:
            // Cannot convert without knowing dose per tablet
            return nil
        }
    }
}

// MARK: - Split Mode

/// How the total nightly dose is divided across administrations.
public enum SplitMode: String, Codable, CaseIterable, Sendable {
    case none = "none"           // Single dose, no split
    case equal = "equal"         // Equal parts (50/50 for 2 parts)
    case custom = "custom"       // Custom ratio specified in split_parts_ratio
    
    public var displayName: String {
        switch self {
        case .none: return "No Split (Single Dose)"
        case .equal: return "Equal Split"
        case .custom: return "Custom Split"
        }
    }
}

// MARK: - Event Source

/// Provenance of a dose event for analytics filtering.
public enum DoseEventSource: String, Codable, CaseIterable, Sendable {
    case manual = "manual"           // User logged it manually
    case automatic = "automatic"     // System logged it (e.g., from notification action)
    case migrated = "migrated"       // Legacy data without amount
    case imported = "imported"       // Imported from export/backup
    
    public var displayName: String {
        switch self {
        case .manual: return "Manual Entry"
        case .automatic: return "Automatic"
        case .migrated: return "Migrated (Legacy)"
        case .imported: return "Imported"
        }
    }
    
    /// Whether this source has reliable amount data
    public var hasReliableAmount: Bool {
        switch self {
        case .manual, .automatic, .imported:
            return true
        case .migrated:
            return false
        }
    }
}

// MARK: - Regimen (The Prescription/Plan)

/// Represents the intended dosing regimen for a medication.
/// This is "the plan" - what the user is supposed to take.
///
/// Regimens are date-bounded to support prescription changes:
/// - When a doctor increases dose, create a new regimen with new start date
/// - Query the active regimen at a specific date to get the intended protocol
///
/// Example:
///   - Xyrem 4.5g total, split 50/50, two doses
///   - Effective 2026-01-01 through ongoing (end_at = nil)
public struct Regimen: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let medicationId: String
    public let createdAt: Date
    
    // Effective date range
    public let startAt: Date
    public let endAt: Date?  // nil = currently active
    
    // Target dosing
    public let targetTotalAmountValue: Double
    public let targetTotalAmountUnit: AmountUnit
    
    // Split configuration
    public let splitMode: SplitMode
    public let splitPartsCount: Int  // 1 = no split, 2 = typical split
    public let splitPartsRatio: [Double]  // e.g., [0.5, 0.5] or [0.6, 0.4]
    
    // Optional context
    public let notes: String?
    public let prescribedBy: String?  // Doctor name
    
    public init(
        id: String = UUID().uuidString,
        medicationId: String,
        createdAt: Date = Date(),
        startAt: Date,
        endAt: Date? = nil,
        targetTotalAmountValue: Double,
        targetTotalAmountUnit: AmountUnit = .mg,
        splitMode: SplitMode,
        splitPartsCount: Int = 2,
        splitPartsRatio: [Double] = [0.5, 0.5],
        notes: String? = nil,
        prescribedBy: String? = nil
    ) {
        self.id = id
        self.medicationId = medicationId
        self.createdAt = createdAt
        self.startAt = startAt
        self.endAt = endAt
        self.targetTotalAmountValue = targetTotalAmountValue
        self.targetTotalAmountUnit = targetTotalAmountUnit
        self.splitMode = splitMode
        self.splitPartsCount = splitPartsCount
        self.splitPartsRatio = splitPartsRatio
        self.notes = notes
        self.prescribedBy = prescribedBy
    }
    
    /// Is this regimen active at the given date?
    public func isActive(at date: Date) -> Bool {
        let afterStart = date >= startAt
        let beforeEnd = endAt == nil || date <= endAt!
        return afterStart && beforeEnd
    }
    
    /// Calculate the target amount for a specific part index (0-based).
    public func targetAmountForPart(_ partIndex: Int) -> Double {
        guard partIndex >= 0 && partIndex < splitPartsRatio.count else {
            return 0
        }
        return targetTotalAmountValue * splitPartsRatio[partIndex]
    }
    
    /// Validate that split ratios sum to 1.0 (with tolerance).
    public var hasValidSplitRatio: Bool {
        guard splitMode != .none else { return true }
        let sum = splitPartsRatio.reduce(0, +)
        return abs(sum - 1.0) < 0.001
    }
    
    /// Common presets for split ratios
    public static func equalSplitRatio(parts: Int) -> [Double] {
        let ratio = 1.0 / Double(parts)
        return Array(repeating: ratio, count: parts)
    }
    
    public static var fiftyFiftySplit: [Double] { [0.5, 0.5] }
    public static var sixtyFortySplit: [Double] { [0.6, 0.4] }
    public static var biggerEarlierSplit: [Double] { [0.6, 0.4] }  // Alias
    public static var biggerLaterSplit: [Double] { [0.4, 0.6] }
}

// MARK: - Dose Bundle (Groups Split Parts)

/// Groups multiple dose events that belong to the same intended dose window.
/// This is the audit anchor for split doses.
///
/// Example: A bedtime dosing session might have:
///   - Bundle: "2026-01-19 bedtime", target 4.5g, 50/50 split
///   - Event 1: 2.25g at 10:00 PM (part 0)
///   - Event 2: 2.25g at 2:30 AM (part 1)
///
/// Without bundles, you lose the relationship between split parts.
public struct DoseBundle: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let regimenId: String?  // Link to the regimen at time of creation
    public let sessionId: String
    public let sessionDate: String  // YYYY-MM-DD
    
    // Snapshot of target at bundle creation (in case regimen changes)
    public let targetTotalAmountValue: Double
    public let targetTotalAmountUnit: AmountUnit
    public let targetSplitRatio: [Double]
    
    // Timing
    public let bundleStartedAt: Date
    public let bundleCompletedAt: Date?  // Set when all parts logged
    
    // Label for UI
    public let bundleLabel: String  // "Bedtime", "Second Dose", "Booster"
    
    public let createdAt: Date
    public let notes: String?
    
    public init(
        id: String = UUID().uuidString,
        regimenId: String? = nil,
        sessionId: String,
        sessionDate: String,
        targetTotalAmountValue: Double,
        targetTotalAmountUnit: AmountUnit = .mg,
        targetSplitRatio: [Double] = [0.5, 0.5],
        bundleStartedAt: Date = Date(),
        bundleCompletedAt: Date? = nil,
        bundleLabel: String = "Bedtime",
        createdAt: Date = Date(),
        notes: String? = nil
    ) {
        self.id = id
        self.regimenId = regimenId
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.targetTotalAmountValue = targetTotalAmountValue
        self.targetTotalAmountUnit = targetTotalAmountUnit
        self.targetSplitRatio = targetSplitRatio
        self.bundleStartedAt = bundleStartedAt
        self.bundleCompletedAt = bundleCompletedAt
        self.bundleLabel = bundleLabel
        self.createdAt = createdAt
        self.notes = notes
    }
    
    /// Expected number of dose parts based on split ratio
    public var expectedPartsCount: Int {
        targetSplitRatio.count
    }
    
    /// Target amount for a specific part index
    public func targetAmountForPart(_ partIndex: Int) -> Double {
        guard partIndex >= 0 && partIndex < targetSplitRatio.count else { return 0 }
        return targetTotalAmountValue * targetSplitRatio[partIndex]
    }
}

// MARK: - Dose Bundle Status

/// Computed status of a dose bundle based on logged events.
public struct DoseBundleStatus: Sendable {
    public let bundle: DoseBundle
    public let loggedEvents: [DoseEventWithAmount]
    
    public init(bundle: DoseBundle, loggedEvents: [DoseEventWithAmount]) {
        self.bundle = bundle
        self.loggedEvents = loggedEvents
    }
    
    /// Sum of amounts actually taken
    public var totalAmountTaken: Double {
        loggedEvents
            .compactMap { $0.amountValue }
            .reduce(0, +)
    }
    
    /// Number of parts logged
    public var partsLogged: Int {
        loggedEvents.count
    }
    
    /// Adherence status relative to target
    public var adherenceStatus: AdherenceStatus {
        let ratio = totalAmountTaken / bundle.targetTotalAmountValue
        let tolerance = 0.05  // 5% tolerance
        
        if ratio < 1.0 - tolerance {
            return .underTarget(percentage: ratio * 100)
        } else if ratio > 1.0 + tolerance {
            return .overTarget(percentage: ratio * 100)
        } else {
            return .onTarget
        }
    }
    
    /// Is this bundle complete? (all expected parts logged)
    public var isComplete: Bool {
        partsLogged >= bundle.expectedPartsCount
    }
    
    /// Remaining amount to reach target
    public var remainingAmount: Double {
        max(0, bundle.targetTotalAmountValue - totalAmountTaken)
    }
}

// MARK: - Adherence Status

/// Represents how well actual dosing matches the target.
public enum AdherenceStatus: Sendable, Equatable {
    case onTarget
    case underTarget(percentage: Double)
    case overTarget(percentage: Double)
    case unknown  // For legacy data without amounts
    
    public var displayText: String {
        switch self {
        case .onTarget:
            return "On Target"
        case .underTarget(let pct):
            return String(format: "Under (%.0f%%)", pct)
        case .overTarget(let pct):
            return String(format: "Over (%.0f%%)", pct)
        case .unknown:
            return "Unknown"
        }
    }
    
    public var isOnTarget: Bool {
        if case .onTarget = self { return true }
        return false
    }
}

// MARK: - Dose Event With Amount

/// A dose event that includes the actual amount taken.
/// This extends the existing dose_events concept with the critical "how much" data.
///
/// Key fields:
/// - amountValue: The numeric amount (nil for legacy/migrated data)
/// - amountUnit: The unit of measurement
/// - source: Where this event came from (manual, migrated, etc.)
/// - bundleId: Links to the parent bundle for split dose tracking
/// - partIndex: Which part of the split (0 = first dose, 1 = second dose)
public struct DoseEventWithAmount: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let eventType: String  // "dose1", "dose2", "dose_extra", etc.
    public let occurredAt: Date
    public let sessionId: String
    public let sessionDate: String
    
    // THE CRITICAL MISSING PIECE: Amount data
    public let amountValue: Double?  // nil for legacy/unknown
    public let amountUnit: AmountUnit?
    
    // Provenance
    public let source: DoseEventSource
    
    // Bundle relationship (for split tracking)
    public let bundleId: String?
    public let partIndex: Int?  // 0-based: 0 = first dose, 1 = second dose
    public let partsCount: Int?  // Total expected parts in this bundle
    
    // Metadata
    public let medicationId: String?
    public let notes: String?
    public let createdAt: Date
    
    // Hazard flag (from existing schema)
    public let isHazard: Bool
    
    public init(
        id: String = UUID().uuidString,
        eventType: String,
        occurredAt: Date,
        sessionId: String,
        sessionDate: String,
        amountValue: Double?,
        amountUnit: AmountUnit? = .mg,
        source: DoseEventSource = .manual,
        bundleId: String? = nil,
        partIndex: Int? = nil,
        partsCount: Int? = nil,
        medicationId: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        isHazard: Bool = false
    ) {
        self.id = id
        self.eventType = eventType
        self.occurredAt = occurredAt
        self.sessionId = sessionId
        self.sessionDate = sessionDate
        self.amountValue = amountValue
        self.amountUnit = amountUnit
        self.source = source
        self.bundleId = bundleId
        self.partIndex = partIndex
        self.partsCount = partsCount
        self.medicationId = medicationId
        self.notes = notes
        self.createdAt = createdAt
        self.isHazard = isHazard
    }
    
    /// Whether this event has a known amount
    public var hasKnownAmount: Bool {
        amountValue != nil
    }
    
    /// Formatted amount string for display
    public var formattedAmount: String {
        guard let value = amountValue, let unit = amountUnit else {
            return "Unknown"
        }
        
        // Format nicely (no trailing zeros for whole numbers)
        if value == value.rounded() {
            return "\(Int(value)) \(unit.displayName)"
        } else {
            return String(format: "%.1f %@", value, unit.displayName)
        }
    }
    
    /// Part label for split doses (e.g., "Part 1 of 2")
    public var partLabel: String? {
        guard let index = partIndex, let count = partsCount else {
            return nil
        }
        return "Part \(index + 1) of \(count)"
    }
}

// MARK: - Default Regimen Presets

extension Regimen {
    // Xyrem/Xywav dosing range:
    // - FDA approved: 4.5g to 9g total nightly dose
    // - Most common starting: 4.5g (2.25g + 2.25g)
    // - Maximum: 9g (4.5g + 4.5g)
    // - Increments: 0.25g (250mg) at a time
    
    /// Create a Xyrem/Xywav regimen with custom total dose.
    /// - Parameter totalGrams: Total nightly dose in grams (range: 2.25g to 9g)
    /// - Parameter splitRatio: How to split the doses (default: 50/50)
    /// - Parameter startAt: When this regimen becomes effective
    public static func xyrem(
        totalGrams: Double,
        splitRatio: [Double] = [0.5, 0.5],
        startAt: Date = Date()
    ) -> Regimen {
        let totalMg = totalGrams * 1000
        let splitMode: SplitMode = splitRatio == [0.5, 0.5] ? .equal : .custom
        return Regimen(
            medicationId: "xyrem",
            startAt: startAt,
            targetTotalAmountValue: totalMg,
            targetTotalAmountUnit: .mg,
            splitMode: splitMode,
            splitPartsCount: splitRatio.count,
            splitPartsRatio: splitRatio,
            notes: String(format: "Xyrem %.2fg total", totalGrams)
        )
    }
    
    /// Common preset: Xyrem 4.5g 50/50 split (starting dose)
    public static func xyremDefault(startAt: Date = Date()) -> Regimen {
        xyrem(totalGrams: 4.5, startAt: startAt)
    }
    
    /// Common preset: Xyrem at maximum dose 9g 50/50 split
    public static func xyremMax(startAt: Date = Date()) -> Regimen {
        xyrem(totalGrams: 9.0, startAt: startAt)
    }

    /// Bigger earlier dose (60/40 split)
    public static func biggerEarlier(
        medicationId: String,
        totalMg: Double,
        startAt: Date = Date()
    ) -> Regimen {
        Regimen(
            medicationId: medicationId,
            startAt: startAt,
            targetTotalAmountValue: totalMg,
            targetTotalAmountUnit: .mg,
            splitMode: .custom,
            splitPartsCount: 2,
            splitPartsRatio: [0.6, 0.4],
            notes: "Bigger first dose (60/40)"
        )
    }
    /// Single dose, no split
    public static func singleDose(
        medicationId: String,
        amountMg: Double,
        startAt: Date = Date()
    ) -> Regimen {
        Regimen(
            medicationId: medicationId,
            startAt: startAt,
            targetTotalAmountValue: amountMg,
            targetTotalAmountUnit: .mg,
            splitMode: .none,
            splitPartsCount: 1,
            splitPartsRatio: [1.0]
        )
    }
}

// MARK: - Validation Helpers

extension DoseEventWithAmount {
    /// Validate that event has required fields
    public var isValid: Bool {
        // Amount must be positive if present
        if let value = amountValue, value <= 0 {
            return false
        }
        // Part index must match parts count
        if let index = partIndex, let count = partsCount {
            if index < 0 || index >= count {
                return false
            }
        }
        // Event type must not be empty
        if eventType.isEmpty {
            return false
        }
        return true
    }
}

extension Regimen {
    /// Validate regimen configuration
    public var isValid: Bool {
        // Amount must be positive
        guard targetTotalAmountValue > 0 else { return false }
        
        // Parts count must match ratio array length
        guard splitPartsCount == splitPartsRatio.count else { return false }
        
        // For split modes, ratios must sum to 1.0
        guard hasValidSplitRatio else { return false }
        
        // Parts count must be at least 1
        guard splitPartsCount >= 1 else { return false }
        
        // End date must be after start date if present
        if let end = endAt {
            guard end > startAt else { return false }
        }
        
        return true
    }
}
