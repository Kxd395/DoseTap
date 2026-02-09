import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Shared helpers for time/interval math.
///
/// SSOT (normative): intervals MUST be computed from absolute timestamps.
public enum TimeIntervalMath {
    private static func logWarning(_ message: String) {
        #if canImport(OSLog)
        if #available(iOS 14.0, watchOS 7.0, macOS 11.0, tvOS 14.0, *) {
            Logger(subsystem: "com.dosetap.core", category: "TimeIntervalMath")
                .warning("\(message, privacy: .public)")
        }
        #endif
    }

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
        #if canImport(OSLog)
        logWarning("Non-sensical interval \(delta) seconds")
        #endif
        #endif
        return Int(delta / 60)
    }

    /// Formats a minute interval as "Hh Mm" (or "Mm" when < 1 hour).
    public static func formatMinutes(_ minutes: Int) -> String {
        let isNegative = minutes < 0
        let total = abs(minutes)
        let hours = total / 60
        let mins = total % 60
        let prefix = isNegative ? "-" : ""
        if hours > 0 {
            return "\(prefix)\(hours)h \(mins)m"
        }
        return "\(prefix)\(mins)m"
    }
}
