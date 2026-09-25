import Foundation

public enum MedicationPresetError: Error, Equatable {
    case unsupportedVersion, invalidIdentity, invalidComponents, invalidAmount, inexactArithmetic, invalidTime
}

/// This boundary is patient-entered data, not a dose recommendation or prescription verification.
public enum MedicationPresetSource: String, Codable, Sendable { case patientEnteredLabel }
public enum MedicationReleaseProfile: String, Codable, Sendable {
    case immediateRelease, extendedRelease, other, unknown
}
public enum MedicationSolidForm: String, Codable, Sendable { case tablet, capsule }
public enum MedicationPresetSchedule: String, Codable, Sendable { case scheduled, asNeeded }

public struct MedicationPresetComponent: Codable, Equatable, Sendable {
    public let id: UUID
    public let form: MedicationSolidForm
    public let strengthMilligrams: Decimal
    public let unitCount: Decimal

    public init(id: UUID, form: MedicationSolidForm, strengthMilligrams: Decimal, unitCount: Decimal) throws {
        self.id = id
        self.form = form
        self.strengthMilligrams = strengthMilligrams
        self.unitCount = unitCount
        _ = try total()
    }

    public var totalMilligrams: Decimal { get throws { try total() } }

    private func total() throws -> Decimal {
        guard strengthMilligrams.isFinite, unitCount.isFinite,
              strengthMilligrams > 0, unitCount > 0 else { throw MedicationPresetError.invalidAmount }
        var strength = strengthMilligrams, count = unitCount, result = Decimal()
        guard NSDecimalMultiply(&result, &strength, &count, .plain) == .noError,
              result.isFinite, result > 0 else { throw MedicationPresetError.inexactArithmetic }
        // Some Foundation versions report success after extreme exponent underflow.
        // Verify the exact inverse rather than trusting the status alone.
        var recoveredCount = Decimal()
        guard NSDecimalDivide(&recoveredCount, &result, &strength, .plain) == .noError,
              recoveredCount == count else { throw MedicationPresetError.inexactArithmetic }
        return result
    }

    private enum CodingKeys: String, CodingKey { case id, form, strengthMilligrams, unitCount }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(UUID.self, forKey: .id), form: c.decode(MedicationSolidForm.self, forKey: .form),
            strengthMilligrams: c.decode(Decimal.self, forKey: .strengthMilligrams),
            unitCount: c.decode(Decimal.self, forKey: .unitCount))
    }
}

/// Immutable context for ONE ingredient/release profile. Components cannot import another preset.
/// Persistence must enforce unique revision IDs and predecessor consistency transactionally.
public struct MedicationPresetRevision: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let presetID: UUID
    public let revisionID: UUID
    public let supersedesRevisionID: UUID?
    public let labelName: String
    public let ingredient: String
    public let releaseProfile: MedicationReleaseProfile
    public let releaseDetails: String?
    public let components: [MedicationPresetComponent]
    public let instructions: String
    public let schedule: MedicationPresetSchedule
    public let effectiveFrom: Date
    public let effectiveUntil: Date?
    public let recordedAt: Date
    public let source: MedicationPresetSource

    public init(presetID: UUID, revisionID: UUID, supersedesRevisionID: UUID?, labelName: String,
                ingredient: String, releaseProfile: MedicationReleaseProfile, releaseDetails: String? = nil,
                components: [MedicationPresetComponent], instructions: String, schedule: MedicationPresetSchedule,
                effectiveFrom: Date, effectiveUntil: Date?, recordedAt: Date) throws {
        schemaVersion = 1
        self.presetID = presetID
        self.revisionID = revisionID
        self.supersedesRevisionID = supersedesRevisionID
        self.labelName = labelName
        self.ingredient = ingredient
        self.releaseProfile = releaseProfile
        self.releaseDetails = releaseDetails
        self.components = components
        self.instructions = instructions
        self.schedule = schedule
        self.effectiveFrom = effectiveFrom
        self.effectiveUntil = effectiveUntil
        self.recordedAt = recordedAt
        source = .patientEnteredLabel
        try validate()
    }

    public var totalMilligrams: Decimal { get throws { try Self.total(components) } }

    /// Half-open interval; not an instruction to take medication or proof it was taken.
    public func isEffective(at date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date >= effectiveFrom && (effectiveUntil.map { date < $0 } ?? true)
    }

    static func total(_ components: [MedicationPresetComponent]) throws -> Decimal {
        guard !components.isEmpty, Set(components.map(\.id)).count == components.count else {
            throw MedicationPresetError.invalidComponents
        }
        var total = Decimal.zero
        for component in components {
            var amount = try component.totalMilligrams, result = Decimal()
            guard NSDecimalAdd(&result, &total, &amount, .plain) == .noError,
                  result.isFinite else { throw MedicationPresetError.inexactArithmetic }
            total = result
        }
        return total
    }

    private func validate() throws {
        guard schemaVersion == 1 else { throw MedicationPresetError.unsupportedVersion }
        guard supersedesRevisionID != revisionID,
              [labelName, ingredient, instructions].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw MedicationPresetError.invalidIdentity }
        if releaseProfile == .other && (releaseDetails?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            throw MedicationPresetError.invalidIdentity
        }
        guard effectiveFrom.timeIntervalSince1970.isFinite, recordedAt.timeIntervalSince1970.isFinite,
              effectiveUntil.map({ $0.timeIntervalSince1970.isFinite && $0 > effectiveFrom }) ?? true
        else { throw MedicationPresetError.invalidTime }
        _ = try Self.total(components)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, presetID, revisionID, supersedesRevisionID, labelName, ingredient, releaseProfile
        case releaseDetails, components, instructions, schedule, effectiveFrom, effectiveUntil, recordedAt, source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        presetID = try c.decode(UUID.self, forKey: .presetID)
        revisionID = try c.decode(UUID.self, forKey: .revisionID)
        supersedesRevisionID = try c.decodeIfPresent(UUID.self, forKey: .supersedesRevisionID)
        labelName = try c.decode(String.self, forKey: .labelName)
        ingredient = try c.decode(String.self, forKey: .ingredient)
        releaseProfile = try c.decode(MedicationReleaseProfile.self, forKey: .releaseProfile)
        releaseDetails = try c.decodeIfPresent(String.self, forKey: .releaseDetails)
        components = try c.decode([MedicationPresetComponent].self, forKey: .components)
        instructions = try c.decode(String.self, forKey: .instructions)
        schedule = try c.decode(MedicationPresetSchedule.self, forKey: .schedule)
        effectiveFrom = try c.decode(Date.self, forKey: .effectiveFrom)
        effectiveUntil = try c.decodeIfPresent(Date.self, forKey: .effectiveUntil)
        recordedAt = try c.decode(Date.self, forKey: .recordedAt)
        source = try c.decode(MedicationPresetSource.self, forKey: .source)
        try validate()
    }
}
