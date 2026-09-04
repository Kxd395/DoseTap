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

    /// Display-only signed minutes between absolute instants. Reversed instants
    /// remain negative; calendar-day rollover must never repair invalid history.
    public static func minutesBetween(start: Date, end: Date) -> Int {
        let delta = end.timeIntervalSince(start)
        guard delta.isFinite else { return -1 }
        return delta < 0 ? Int(floor(delta / 60)) : Int(delta / 60)
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
