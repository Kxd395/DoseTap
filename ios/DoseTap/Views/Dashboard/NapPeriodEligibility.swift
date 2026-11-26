import Foundation
import DoseCore
/// A reviewed civil date is a range/navigation boundary, never an invented nap timestamp.
enum NapPeriodEligibility {
    static func stamp(_ date: Date, zone: String) -> String { date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: zone) ?? .current)) }
    static func dayBounds(_ episode: NapEpisode) -> (Date, Date)? {
        dayBounds(day: episode.day, timeZoneID: episode.timeZoneID)
    }
    static func dayBounds(day: String, timeZoneID: String) -> (Date, Date)? {
        guard let zone = TimeZone(identifier: timeZoneID) else { return nil }
        let fields = day.split(separator: "-").compactMap { Int($0) }
        guard fields.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard let start = calendar.date(from: DateComponents(year: fields[0], month: fields[1], day: fields[2])),
              NapEpisode.day(start, timeZoneID) == day,
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return (start, end)
    }
    static func isVisible(_ episode: NapEpisode, in window: DashboardDaytimeWindow?) -> Bool {
        guard let window, let start = window.start, let bounds = dayBounds(episode) else { return false }
        return bounds.0 < window.endExclusive && bounds.1 > start
    }
    static func exclusion(_ episode: NapEpisode, in window: DashboardDaytimeWindow?) -> String? {
        guard let window, !window.isEmpty else { return "Civil reporting period unavailable" }
        if let start = episode.start { return window.contains(start) ? nil : "Actual nap start is outside the exact selected period" }
        guard let lower = window.start, let bounds = dayBounds(episode), bounds.0 >= lower, bounds.1 <= window.endExclusive else {
            return "Clock start unknown on a partial boundary day; estimate excluded from this period"
        }
        return nil
    }
}
