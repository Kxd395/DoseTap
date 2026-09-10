import Foundation

/// Versioned diary amounts. Volume and caffeine mass are independent observations.
public struct CaffeineAmounts: Codable, Hashable, Sendable {
    public enum Source: String, Codable, CaseIterable, Sendable {
        case userReported = "user_reported", labelReported = "label_reported"
        case estimated, unknown
    }

    public var version: Int = 1
    public var source: Source = .userReported
    public var lastVolumeUSFlOz: Double?
    public var dailyVolumeUSFlOz: Double?
    public var lastCaffeineMg: Double?
    public var dailyCaffeineMg: Double?

    public init() {}

    public var validationError: String? {
        guard version == 1 else { return "This caffeine amount format is not supported. Update DoseTap before editing it." }
        let values = [lastVolumeUSFlOz, dailyVolumeUSFlOz, lastCaffeineMg, dailyCaffeineMg].compactMap { $0 }
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            return "Caffeine amounts must be finite, non-negative numbers. Leave unknown amounts blank."
        }
        for (last, daily) in [(lastVolumeUSFlOz, dailyVolumeUSFlOz), (lastCaffeineMg, dailyCaffeineMg)] {
            if let last, let daily, daily < last { return "Each daily total must be at least its last recorded amount." }
        }
        return nil
    }
}
