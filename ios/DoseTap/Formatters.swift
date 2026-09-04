import Foundation

/// Shared, pre-configured date formatters.
///
/// `DateFormatter` allocation is expensive (~4 µs each). These static instances
/// are created once and reused throughout the app. They are safe for read-only
/// use on the main thread (all SwiftUI view bodies execute on `@MainActor`).
///
/// > Important: Never mutate these formatters at a call site.
enum AppFormatters {

    // MARK: - Session Key  ("2025-06-15")

    /// `"yyyy-MM-dd"` with the autoupdating device timezone — parses and formats session date keys.
    static let sessionDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    // MARK: - Display Dates

    /// `"EEEE, MMM d"` — e.g. "Saturday, Jun 15"
    static let weekdayMedium: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    /// `"MMM d"` — e.g. "Jun 15"
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    /// `.dateStyle = .full` — e.g. "Saturday, June 15, 2025"
    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    // MARK: - Times

    /// `.timeStyle = .short` — e.g. "9:41 PM"
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    /// `.dateStyle = .medium` + `.timeStyle = .short` — e.g. "Jun 15, 2025 at 9:41 PM"
    static let mediumDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    /// `"EEE, MMM d"` — e.g. "Sat, Jun 15"
    static let shortWeekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    /// `"h:mm:ss a"` — e.g. "9:41:05 PM" (alarm/notification diagnostics)
    static let detailedTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    static func compactRating(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded(.towardZero) {
            return String(Int(rounded))
        }
        if (rounded * 10) == (rounded * 10).rounded(.towardZero) {
            return String(format: "%.1f", rounded)
        }
        return String(format: "%.2f", rounded)
    }

    static func timeZoneLabel(
        timeZone: TimeZone = .autoupdatingCurrent,
        at date: Date = Date()
    ) -> String {
        "\(timeZone.identifier) (\(utcOffsetLabel(timeZone: timeZone, at: date)))"
    }

    static func utcOffsetLabel(timeZone: TimeZone, at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds >= 0 ? "+" : "-"
        let absoluteMinutes = abs(seconds) / 60
        return String(
            format: "UTC%@%02d:%02d",
            sign,
            absoluteMinutes / 60,
            absoluteMinutes % 60
        )
    }

    // MARK: - Export / Filenames

    /// `"yyyy-MM-dd_HHmmss"` — safe for filenames.
    static let exportFilename: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.timeZone = .autoupdatingCurrent
        return f
    }()

    // MARK: - ISO 8601

    /// Standard ISO 8601 (no fractional seconds).
    static let iso8601: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    /// ISO 8601 with fractional seconds.
    static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Flexible Parsing

    /// Parse an ISO 8601 string, trying fractional seconds first then plain.
    /// Avoids creating new formatter instances on each call.
    static func parseISO8601Flexible(_ string: String) -> Date? {
        iso8601Fractional.date(from: string) ?? iso8601.date(from: string)
    }
}
