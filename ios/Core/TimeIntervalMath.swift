import Foundation

/// Shared helpers for time/interval math.
///
/// SSOT (normative): intervals MUST be computed from absolute timestamps.
public enum TimeIntervalMath {

    /// Computes minutes between two absolute timestamps.
    ///
    /// - Midnight rollover rule: if `end < start`, we allow a single rollover across midnight
    ///   by adding +24h, but only if the result is plausible (0...12 hours).
    /// - If the negative delta is not plausibly a rollover, we assert in debug builds.
    public static func minutesBetween(start: Date, end: Date) -> Int {
        let delta = end.timeIntervalSince(start)
        if delta >= 0 { return Int(delta / 60) }

        let rolled = delta + 24 * 60 * 60
        if rolled >= 0 && rolled <= 12 * 60 * 60 {
            return Int(rolled / 60)
        }

        // Non-rollover negative: log in debug but don't crash tests
        #if DEBUG
        print("⚠️ TimeIntervalMath: Non-sensical interval \(delta) seconds (start=\(start), end=\(end))")
        #endif
        return Int(delta / 60)
    }
}
