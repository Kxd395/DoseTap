import Foundation

// MARK: - Quantities and conversions

/// An exact medication quantity in the unit entered by the user. When the
/// calculation unit differs, `conversionID` selects the exact reviewed
/// conversion version; the engine never chooses one from the unit pair alone.
///
/// Inventory calculations use `Decimal` so a repeated allocation cannot gain or
/// lose medication through binary floating-point rounding.
public struct MedicationInventoryAmount: Codable, Sendable, Equatable {
    public let value: Decimal
    public let unit: AmountUnit
    public let conversionID: String?

    public init(
        value: Decimal,
        unit: AmountUnit,
        conversionID: String? = nil
    ) {
        self.value = value
        self.unit = unit
        self.conversionID = conversionID
    }
}

/// A user-confirmed, versioned conversion. `multiplier` means:
///
///     value in toUnit = value in fromUnit * multiplier
///
/// No conversion, including a mass conversion, is implicit in the inventory
/// engine. Concentration and per-tablet conversions therefore remain auditable.
public struct MedicationInventoryUnitConversion: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let version: String
    public let fromUnit: AmountUnit
    public let toUnit: AmountUnit
    public let multiplier: Decimal

    public init(
        id: String,
        version: String,
        fromUnit: AmountUnit,
        toUnit: AmountUnit,
        multiplier: Decimal
    ) {
        self.id = id
        self.version = version
        self.fromUnit = fromUnit
        self.toUnit = toUnit
        self.multiplier = multiplier
    }
}

// MARK: - Plan and schedule contracts

/// A schedule is evaluated in its named timezone. Weekdays use the Gregorian
/// `Calendar.Component.weekday` convention: Sunday is 1 and Saturday is 7.
public enum MedicationInventorySchedule: Codable, Sendable, Equatable {
    case daily(hour: Int, minute: Int, timeZoneIdentifier: String)
    case selectedWeekdays(
        weekdays: [Int],
        hour: Int,
        minute: Int,
        timeZoneIdentifier: String
    )
    case irregular
}

/// The effective-dated plan values needed by inventory calculations.
/// `effectiveUntil` is an exclusive boundary.
public struct MedicationInventoryPlanVersion: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let effectiveFrom: Date
    public let effectiveUntil: Date?
    public let targetPerDose: MedicationInventoryAmount?
    public let maximumPerDose: MedicationInventoryAmount?
    public let targetPerSession: MedicationInventoryAmount?
    public let maximumPerSession: MedicationInventoryAmount?
    public let schedule: MedicationInventorySchedule

    public init(
        id: String,
        effectiveFrom: Date,
        effectiveUntil: Date? = nil,
        targetPerDose: MedicationInventoryAmount?,
        maximumPerDose: MedicationInventoryAmount? = nil,
        targetPerSession: MedicationInventoryAmount?,
        maximumPerSession: MedicationInventoryAmount?,
        schedule: MedicationInventorySchedule
    ) {
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.effectiveUntil = effectiveUntil
        self.targetPerDose = targetPerDose
        self.maximumPerDose = maximumPerDose
        self.targetPerSession = targetPerSession
        self.maximumPerSession = maximumPerSession
        self.schedule = schedule
    }

    public func isEffective(at date: Date) -> Bool {
        date >= effectiveFrom && (effectiveUntil == nil || date < effectiveUntil!)
    }
}

// MARK: - Inventory inputs

public enum MedicationInventoryContainerState: String, Codable, Sendable, Equatable {
    case openActive
    case unopened
    case orderedNotReceived
    case unavailable

    public var isUsableOnHand: Bool {
        self == .openActive || self == .unopened
    }
}

/// One physical bottle or package. The quantity is the usable quantity at its
/// baseline, before signed adjustments and committed dose allocations.
public struct MedicationInventoryContainer: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let state: MedicationInventoryContainerState
    public let startingUsableQuantity: MedicationInventoryAmount?
    public let receivedAt: Date?
    public let openedAt: Date?

    public init(
        id: String,
        state: MedicationInventoryContainerState,
        startingUsableQuantity: MedicationInventoryAmount?,
        receivedAt: Date? = nil,
        openedAt: Date? = nil
    ) {
        self.id = id
        self.state = state
        self.startingUsableQuantity = startingUsableQuantity
        self.receivedAt = receivedAt
        self.openedAt = openedAt
    }
}

/// A signed quantity change. Negative values represent spills, discards, short
/// fills, or other unavailable supply. Positive values represent corrections.
public struct MedicationInventoryAdjustment: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let containerID: String
    public let quantityChange: MedicationInventoryAmount
    public let occurredAt: Date

    public init(
        id: String,
        containerID: String,
        quantityChange: MedicationInventoryAmount,
        occurredAt: Date
    ) {
        self.id = id
        self.containerID = containerID
        self.quantityChange = quantityChange
        self.occurredAt = occurredAt
    }
}

/// A committed link between one canonical dose event and its source bottle.
/// A nil container or quantity is retained as incomplete data and is never
/// guessed by the forecast engine.
public struct MedicationInventoryDoseAllocation: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let doseEventID: String
    public let sessionID: String
    public let containerID: String?
    public let quantity: MedicationInventoryAmount?
    public let occurredAt: Date
    public let planVersionID: String?

    public init(
        id: String,
        doseEventID: String,
        sessionID: String,
        containerID: String?,
        quantity: MedicationInventoryAmount?,
        occurredAt: Date,
        planVersionID: String? = nil
    ) {
        self.id = id
        self.doseEventID = doseEventID
        self.sessionID = sessionID
        self.containerID = containerID
        self.quantity = quantity
        self.occurredAt = occurredAt
        self.planVersionID = planVersionID
    }
}

public struct MedicationInventoryTolerancePolicy: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let version: String
    public let percentOfStartingQuantity: Decimal
    public let measurementTolerance: MedicationInventoryAmount?
    public let smallestMeaningfulIncrement: MedicationInventoryAmount

    public init(
        id: String,
        version: String,
        percentOfStartingQuantity: Decimal = Decimal(5) / Decimal(100),
        measurementTolerance: MedicationInventoryAmount? = nil,
        smallestMeaningfulIncrement: MedicationInventoryAmount
    ) {
        self.id = id
        self.version = version
        self.percentOfStartingQuantity = percentOfStartingQuantity
        self.measurementTolerance = measurementTolerance
        self.smallestMeaningfulIncrement = smallestMeaningfulIncrement
    }
}

public enum MedicationInventoryBottleAction: Codable, Sendable, Equatable {
    case receiveUnopened(containerID: String)
    case start(
        containerID: String,
        replacingContainerID: String,
        at: Date
    )
}

public struct MedicationInventoryForecastRequest: Codable, Sendable, Equatable {
    public let medicationID: String
    public let calculationUnit: AmountUnit
    public let planVersions: [MedicationInventoryPlanVersion]
    public let containers: [MedicationInventoryContainer]
    public let adjustments: [MedicationInventoryAdjustment]
    public let allocations: [MedicationInventoryDoseAllocation]
    public let conversions: [MedicationInventoryUnitConversion]
    public let tolerancePolicy: MedicationInventoryTolerancePolicy
    public let proposedBottleAction: MedicationInventoryBottleAction?

    public init(
        medicationID: String,
        calculationUnit: AmountUnit,
        planVersions: [MedicationInventoryPlanVersion],
        containers: [MedicationInventoryContainer],
        adjustments: [MedicationInventoryAdjustment] = [],
        allocations: [MedicationInventoryDoseAllocation] = [],
        conversions: [MedicationInventoryUnitConversion] = [],
        tolerancePolicy: MedicationInventoryTolerancePolicy,
        proposedBottleAction: MedicationInventoryBottleAction? = nil
    ) {
        self.medicationID = medicationID
        self.calculationUnit = calculationUnit
        self.planVersions = planVersions
        self.containers = containers
        self.adjustments = adjustments
        self.allocations = allocations
        self.conversions = conversions
        self.tolerancePolicy = tolerancePolicy
        self.proposedBottleAction = proposedBottleAction
    }
}

// MARK: - Result contracts

public enum MedicationInventoryForecastCompleteness: String, Codable, Sendable, Equatable {
    case complete
    case planBased
    case inventoryNeedsReview
    case planNeedsReview
}

public enum MedicationInventoryForecastIssueDomain: String, Codable, Sendable, Equatable, Hashable {
    case plan
    case inventory
    case doseHistory
    case engine
}

public enum MedicationInventoryForecastIssueCode: String, Codable, Sendable, Equatable, Hashable {
    case missingPlan
    case missingTargetPerDose
    case missingTargetPerSession
    case missingMaximumPerSession
    case irregularSchedule
    case unknownTimeZone
    case missingUnitConversion
    case missingStartingQuantity
    case missingReceivedAt
    case missingOpenedAt
    case missingDoseAmount
    case unallocatedDose
    case unknownAdjustmentContainer
    case unknownAllocationContainer
    case proposedContainerNotFound
    case previousContainerNotFound
    case negativePlanBalance
    case negativeLedgerBalance
    case planCoverageGap
    case forecastHorizonExceeded
}

public struct MedicationInventoryForecastIssue: Codable, Sendable, Equatable, Hashable {
    public let domain: MedicationInventoryForecastIssueDomain
    public let code: MedicationInventoryForecastIssueCode
    public let recordID: String?
    public let field: String?

    public init(
        domain: MedicationInventoryForecastIssueDomain,
        code: MedicationInventoryForecastIssueCode,
        recordID: String? = nil,
        field: String? = nil
    ) {
        self.domain = domain
        self.code = code
        self.recordID = recordID
        self.field = field
    }
}

public struct MedicationInventoryProjection: Codable, Sendable, Equatable {
    public let fullTreatmentSessions: Int?
    public let runoutAt: Date?

    public init(fullTreatmentSessions: Int?, runoutAt: Date?) {
        self.fullTreatmentSessions = fullTreatmentSessions
        self.runoutAt = runoutAt
    }
}

public enum MedicationInventoryEarlyBottleClassification: String, Codable, Sendable, Equatable {
    case notApplicable
    case noWarning
    case caution
    case strongWarning
    case reviewRequired
}

public struct MedicationInventoryEarlyBottleReview: Codable, Sendable, Equatable {
    public let classification: MedicationInventoryEarlyBottleClassification
    public let previousContainerID: String?
    public let availableQuantity: MedicationInventoryAmount?
    public let remainingAtTarget: MedicationInventoryAmount?
    public let remainingAtMaximum: MedicationInventoryAmount?
    public let ledgerRemaining: MedicationInventoryAmount?
    public let tolerance: MedicationInventoryAmount?
    public let scheduledTreatmentSessions: Int?
    public let planVersionIDs: [String]
    public let issues: [MedicationInventoryForecastIssue]

    public init(
        classification: MedicationInventoryEarlyBottleClassification,
        previousContainerID: String?,
        availableQuantity: MedicationInventoryAmount?,
        remainingAtTarget: MedicationInventoryAmount?,
        remainingAtMaximum: MedicationInventoryAmount?,
        ledgerRemaining: MedicationInventoryAmount?,
        tolerance: MedicationInventoryAmount?,
        scheduledTreatmentSessions: Int?,
        planVersionIDs: [String],
        issues: [MedicationInventoryForecastIssue]
    ) {
        self.classification = classification
        self.previousContainerID = previousContainerID
        self.availableQuantity = availableQuantity
        self.remainingAtTarget = remainingAtTarget
        self.remainingAtMaximum = remainingAtMaximum
        self.ledgerRemaining = ledgerRemaining
        self.tolerance = tolerance
        self.scheduledTreatmentSessions = scheduledTreatmentSessions
        self.planVersionIDs = planVersionIDs
        self.issues = issues
    }
}

public struct MedicationInventoryForecastProvenance: Codable, Sendable, Equatable {
    public let asOf: Date
    public let inputRecordIDs: [String]
    public let planVersionIDs: [String]
    public let conversionIDs: [String]
    public let conversionVersions: [String: String]
    public let tolerancePolicyID: String
    public let tolerancePolicyVersion: String

    public init(
        asOf: Date,
        inputRecordIDs: [String],
        planVersionIDs: [String],
        conversionIDs: [String],
        conversionVersions: [String: String],
        tolerancePolicyID: String,
        tolerancePolicyVersion: String
    ) {
        self.asOf = asOf
        self.inputRecordIDs = inputRecordIDs
        self.planVersionIDs = planVersionIDs
        self.conversionIDs = conversionIDs
        self.conversionVersions = conversionVersions
        self.tolerancePolicyID = tolerancePolicyID
        self.tolerancePolicyVersion = tolerancePolicyVersion
    }
}

/// Deterministic review text. This is diagnostic/product-review output, not
/// clinical advice and not a substitute for localized UI copy.
public struct MedicationInventoryForecastExplanation: Codable, Sendable, Equatable {
    public let summary: String
    public let lines: [String]

    public init(summary: String, lines: [String]) {
        self.summary = summary
        self.lines = lines
    }
}

public struct MedicationInventoryForecastResult: Codable, Sendable, Equatable {
    public let medicationID: String
    public let asOf: Date
    public let calculationUnit: AmountUnit
    public let completeness: MedicationInventoryForecastCompleteness
    public let issues: [MedicationInventoryForecastIssue]
    public let usableQuantityBeforeConsumption: MedicationInventoryAmount?
    public let orderedNotReceivedQuantity: MedicationInventoryAmount?
    public let prescriptionTargetRemaining: MedicationInventoryAmount?
    public let prescriptionMaximumRemaining: MedicationInventoryAmount?
    public let ledgerRemaining: MedicationInventoryAmount?
    public let activeForecastRemaining: MedicationInventoryAmount?
    public let targetProjection: MedicationInventoryProjection?
    public let maximumProjection: MedicationInventoryProjection?
    public let ledgerProjection: MedicationInventoryProjection?
    public let activeProjection: MedicationInventoryProjection?
    public let earlyBottleReview: MedicationInventoryEarlyBottleReview?
    public let provenance: MedicationInventoryForecastProvenance
    public let explanation: MedicationInventoryForecastExplanation

    public init(
        medicationID: String,
        asOf: Date,
        calculationUnit: AmountUnit,
        completeness: MedicationInventoryForecastCompleteness,
        issues: [MedicationInventoryForecastIssue],
        usableQuantityBeforeConsumption: MedicationInventoryAmount?,
        orderedNotReceivedQuantity: MedicationInventoryAmount?,
        prescriptionTargetRemaining: MedicationInventoryAmount?,
        prescriptionMaximumRemaining: MedicationInventoryAmount?,
        ledgerRemaining: MedicationInventoryAmount?,
        activeForecastRemaining: MedicationInventoryAmount?,
        targetProjection: MedicationInventoryProjection?,
        maximumProjection: MedicationInventoryProjection?,
        ledgerProjection: MedicationInventoryProjection?,
        activeProjection: MedicationInventoryProjection?,
        earlyBottleReview: MedicationInventoryEarlyBottleReview?,
        provenance: MedicationInventoryForecastProvenance,
        explanation: MedicationInventoryForecastExplanation
    ) {
        self.medicationID = medicationID
        self.asOf = asOf
        self.calculationUnit = calculationUnit
        self.completeness = completeness
        self.issues = issues
        self.usableQuantityBeforeConsumption = usableQuantityBeforeConsumption
        self.orderedNotReceivedQuantity = orderedNotReceivedQuantity
        self.prescriptionTargetRemaining = prescriptionTargetRemaining
        self.prescriptionMaximumRemaining = prescriptionMaximumRemaining
        self.ledgerRemaining = ledgerRemaining
        self.activeForecastRemaining = activeForecastRemaining
        self.targetProjection = targetProjection
        self.maximumProjection = maximumProjection
        self.ledgerProjection = ledgerProjection
        self.activeProjection = activeProjection
        self.earlyBottleReview = earlyBottleReview
        self.provenance = provenance
        self.explanation = explanation
    }
}

// MARK: - Invalid input failures

public enum MedicationInventoryForecastError: Error, Sendable, Equatable {
    case duplicateRecordID(String)
    case invalidAmount(recordID: String, field: String)
    case invalidConversion(String)
    case invalidPlanRange(String)
    case overlappingPlanVersions(first: String, second: String)
    case invalidPlanRelationship(planID: String, field: String)
    case invalidSchedule(planID: String)
    case multipleActiveContainers
    case invalidBottleActionTimeline(containerID: String)
}

extension MedicationInventoryForecastError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .duplicateRecordID(let id):
            return "Duplicate inventory record ID: \(id)"
        case .invalidAmount(let recordID, let field):
            return "Invalid amount for \(recordID).\(field)"
        case .invalidConversion(let id):
            return "Invalid unit conversion: \(id)"
        case .invalidPlanRange(let id):
            return "Invalid effective range for plan \(id)"
        case .overlappingPlanVersions(let first, let second):
            return "Plan versions overlap: \(first), \(second)"
        case .invalidPlanRelationship(let planID, let field):
            return "Invalid plan relationship for \(planID).\(field)"
        case .invalidSchedule(let planID):
            return "Invalid schedule for plan \(planID)"
        case .multipleActiveContainers:
            return "More than one active inventory container was supplied"
        case .invalidBottleActionTimeline(let containerID):
            return "Bottle action precedes the opening of container \(containerID)"
        }
    }
}
