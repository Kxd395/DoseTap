import Foundation

/// Optional diary context. Presence never implies monitoring or medication permission.
public struct SleepingSetup: Codable, Equatable, Sendable {
    public enum Arrangement: String, Codable, CaseIterable, Sendable {
        case alone = "Alone in the room"
        case partnerSameBed = "Partner in the same bed"
        case partnerSeparateBeds = "Partner in the room, separate beds"
        case otherPeople = "Another person or other people"
        case other = "Other arrangement"
        case unsure = "Unsure"
        case preferNot = "Prefer not to answer"
    }
    public enum SharedSpace: String, Codable, CaseIterable, Sendable {
        case sameBed = "Same bed", sameRoom = "Same room, separate sleeping spaces"
        case variable = "Changes during the sleep period", other = "Other", unsure = "Unsure"
    }
    public enum Pets: String, Codable, CaseIterable, Sendable {
        case none = "No pets", onBed = "On the bed", offBed = "In the room, off the bed"
        case variable = "Both or variable", unsure = "Unsure"
    }
    public enum Location: String, Codable, CaseIterable, Sendable {
        case usual = "Usual bed at home", different = "Different bed or room at home"
        case away = "Away from home", other = "Other", preferNot = "Prefer not to answer"
    }
    public var version = 1
    public var arrangement: Arrangement?
    public var sharedSpace: SharedSpace?
    public var pets: Pets?
    public var location: Location?
    public init() {}
    public var isEmpty: Bool { arrangement == nil && sharedSpace == nil && pets == nil && location == nil }
    public var needsSharedDetail: Bool { arrangement == .otherPeople || arrangement == .other }
    public var normalized: Self {
        var result = self
        if !needsSharedDetail { result.sharedSpace = nil }
        return result
    }
    public var summary: String {
        [arrangement?.rawValue, normalized.sharedSpace?.rawValue, pets.map { "Pets: " + $0.rawValue }, location?.rawValue]
            .compactMap { $0 }.joined(separator: " · ")
    }
    public func applyingMissing(from saved: Self) -> Self {
        var result = self
        result.arrangement = result.arrangement ?? saved.arrangement
        result.sharedSpace = result.sharedSpace ?? saved.sharedSpace
        result.pets = result.pets ?? saved.pets
        result.location = result.location ?? saved.location
        return result.normalized
    }
}

/// A plan snapshot and a fresh morning observation, never a reusable preference.
public struct MorningSleepingContext: Codable, Equatable, Sendable {
    public enum Confirmation: String, Codable, CaseIterable, Sendable {
        case same = "Same as planned", changed = "Different / enter actual setup"
        case unsure = "Unsure", preferNot = "Prefer not to answer"
    }
    public enum Impact: String, Codable, CaseIterable, Sendable {
        case noEffect = "No noticeable effect", helped = "Helped", disrupted = "Disrupted"
        case both = "Both", unsure = "Unsure", notApplicable = "Not applicable"
    }
    public enum Factor: String, Codable, CaseIterable, Sendable {
        case noise = "Snoring or noise", movement = "Movement", schedules = "Different schedules or alarms"
        case care = "Care responsibilities", pets = "Pets", comfort = "Comfort or support", other = "Other"
    }
    public var version = 1
    public var plan: SleepingSetup?
    public var confirmation: Confirmation?
    public var actual: SleepingSetup?
    public var impact: Impact?
    public var factors: [Factor]?
    public init() {}
    public var isEmpty: Bool { confirmation == nil && actual == nil && impact == nil }
    public var allowsFactors: Bool { impact == .helped || impact == .disrupted || impact == .both }
    public mutating func selectConfirmation(_ choice: Confirmation?) {
        confirmation = choice
        actual = nil
        if choice == .same {
            guard let plan, !plan.isEmpty else { confirmation = nil; return }
            actual = plan.normalized
        }
    }
    public var normalized: Self {
        var result = self
        result.plan = plan?.normalized
        if confirmation == .same { result.actual = plan?.normalized }
        else if confirmation != .changed { result.actual = nil }
        else { result.actual = actual?.normalized }
        result.factors = allowsFactors ? Factor.allCases.filter { factors?.contains($0) == true } : nil
        if result.factors?.isEmpty == true { result.factors = nil }
        return result
    }
}
