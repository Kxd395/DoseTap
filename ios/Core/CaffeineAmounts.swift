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

    public var reportFields: [(key: String, label: String, value: String)] {
        if let error = validationError { return [("status", "Caffeine amounts", error)] }
        var fields = [("version", "Caffeine amount format", String(version)), ("source", "Caffeine amount source", source.rawValue)]
        for (key, label, value) in [
            ("last_volume_us_fl_oz", "Last beverage (US fl oz)", lastVolumeUSFlOz),
            ("daily_volume_us_fl_oz", "Daily beverages (US fl oz)", dailyVolumeUSFlOz),
            ("last_caffeine_mg", "Last caffeine (mg)", lastCaffeineMg),
            ("daily_caffeine_mg", "Daily caffeine (mg)", dailyCaffeineMg)
        ] {
            if let value { fields.append((key, label, String(value))) }
        }
        return fields
    }

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
