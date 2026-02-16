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

    /// `"yyyy-MM-dd"` with `.current` timezone — parses and formats session date keys.
    static let sessionDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    // MARK: - Display Dates

    /// `"EEEE, MMM d"` — e.g. "Saturday, Jun 15"
    static let weekdayMedium: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    /// `"MMM d"` — e.g. "Jun 15"
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = .current
        return f
    }()

    /// `.dateStyle = .full` — e.g. "Saturday, June 15, 2025"
    static let fullDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()

    // MARK: - Times

    /// `.timeStyle = .short` — e.g. "9:41 PM"
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    /// `.dateStyle = .medium` + `.timeStyle = .short` — e.g. "Jun 15, 2025 at 9:41 PM"
    static let mediumDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - Export / Filenames

    /// `"yyyy-MM-dd_HHmmss"` — safe for filenames.
    static let exportFilename: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
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
}
