import Foundation

public enum MedicationPresetDraftError: Error { case missingChoice, reviewRequired, invalidDecimal }

/// Transient label entry; never an administration or a persisted draft.
public struct MedicationPresetDraft: Equatable {
    public struct Component: Identifiable, Equatable {
        public var id: UUID = UUID()
        public var form: MedicationSolidForm?
        public var strength = ""
        public var count = ""
        public init() {}
    }
    public let presetID: UUID
    public let predecessor: UUID?
    public var labelName = ""
    public var ingredient = ""
    public var releaseProfile: MedicationReleaseProfile?
    public var releaseDetails = ""
    public var components = [Component()]
    public var instructions = ""
    public var schedule: MedicationPresetSchedule?
    public var effectiveFrom: Date
    public var effectiveUntil: Date?

    public init(effectiveFrom: Date) {
        presetID = UUID(); predecessor = nil; self.effectiveFrom = effectiveFrom
    }
    public init(revising value: MedicationPresetRevision, separator: String) {
        presetID = value.presetID; predecessor = value.revisionID
        labelName = value.labelName; ingredient = value.ingredient
        releaseProfile = value.releaseProfile; releaseDetails = value.releaseDetails ?? ""
        instructions = value.instructions; schedule = value.schedule
        effectiveFrom = value.effectiveFrom; effectiveUntil = value.effectiveUntil
        components = value.components.map { value in
            var c = Component(); c.id = value.id; c.form = value.form
            c.strength = NSDecimalNumber(decimal: value.strengthMilligrams).stringValue.replacingOccurrences(of: ".", with: separator)
            c.count = NSDecimalNumber(decimal: value.unitCount).stringValue.replacingOccurrences(of: ".", with: separator)
            return c
        }
    }
    public func revision(recordedAt: Date, separator: String, reviewed: Bool) throws -> MedicationPresetRevision {
        guard reviewed else { throw MedicationPresetDraftError.reviewRequired }
        guard let releaseProfile, let schedule else { throw MedicationPresetDraftError.missingChoice }
        let values = try components.map { component in
            guard let form = component.form else { throw MedicationPresetDraftError.missingChoice }
            return try MedicationPresetComponent(id: component.id, form: form,
                strengthMilligrams: Self.amount(component.strength, separator: separator),
                unitCount: Self.amount(component.count, separator: separator))
        }
        return try MedicationPresetRevision(presetID: presetID, revisionID: UUID(), supersedesRevisionID: predecessor,
            labelName: labelName.trimmingCharacters(in: .whitespacesAndNewlines),
            ingredient: ingredient.trimmingCharacters(in: .whitespacesAndNewlines), releaseProfile: releaseProfile,
            releaseDetails: releaseProfile == .other ? releaseDetails : nil, components: values,
            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines), schedule: schedule,
            effectiveFrom: effectiveFrom, effectiveUntil: effectiveUntil, recordedAt: recordedAt)
    }
    public static func amount(_ input: String, separator: String) throws -> Decimal {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map { scalar in
            if scalar.properties.generalCategory == .decimalNumber,
               let digit = scalar.properties.numericValue {
                return String(Int(digit))
            }
            return String(scalar)
        }.joined()
        guard !separator.isEmpty else { throw MedicationPresetDraftError.invalidDecimal }
        let pattern = "^[0-9]+(?:" + NSRegularExpression.escapedPattern(for: separator) + "[0-9]+)?$"
        guard text.range(of: pattern, options: .regularExpression) != nil else { throw MedicationPresetDraftError.invalidDecimal }
        let normalized = text.replacingOccurrences(of: separator, with: ".")
        let digits = normalized.filter { $0 != "." }.drop(while: { $0 == "0" })
        guard digits.count <= 38, let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              value.isFinite, value > 0,
              canonical(normalized) == canonical(NSDecimalNumber(decimal: value).stringValue)
        else { throw MedicationPresetDraftError.invalidDecimal }
        return value
    }
    private static func canonical(_ text: String) -> String {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0].drop(while: { $0 == "0" }))
        var fraction = parts.count == 2 ? String(parts[1]) : ""
        while fraction.last == "0" { fraction.removeLast() }
        return (whole.isEmpty ? "0" : whole) + (fraction.isEmpty ? "" : "." + fraction)
    }
    /// The chain leaf, including future-effective revisions. Call with a validated ledger.
    public static func latest(in values: [MedicationPresetRevision]) -> [MedicationPresetRevision] {
        let predecessors = Set(values.compactMap(\.supersedesRevisionID))
        return values.filter { !predecessors.contains($0.revisionID) }.sorted {
            if $0.labelName != $1.labelName { return $0.labelName < $1.labelName }
            return $0.presetID.uuidString < $1.presetID.uuidString
        }
    }
}
