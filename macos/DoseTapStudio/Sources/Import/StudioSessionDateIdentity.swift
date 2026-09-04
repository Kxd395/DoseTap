import Foundation

/// Resolves every imported row to DoseTap's canonical dosing-night identity.
///
/// `events.csv.device_time` is historically named but contains the frozen
/// `yyyy-MM-dd` session date emitted by the iOS app. Prefer it because it
/// survives travel and later imports in a different timezone. Older exports
/// without that value fall back to the shared 6 PM rollover rule in UTC. That
/// deterministic legacy fallback avoids silently reinterpreting an old export
/// in whatever timezone the Mac happens to use at import time.
enum StudioSessionDateIdentity {
    static let rolloverHour = 18
    private static let legacyFallbackTimeZone = TimeZone(secondsFromGMT: 0)!

    static func key(
        for event: DoseEvent,
        timeZone: TimeZone = legacyFallbackTimeZone
    ) -> String {
        validatedSessionDate(event.deviceTime)
            ?? key(for: event.occurredAtUTC, timeZone: timeZone)
    }

    static func key(
        for session: DoseSession,
        events: [DoseEvent],
        timeZone: TimeZone = legacyFallbackTimeZone
    ) -> String {
        if let dose1 = events.first(where: {
            $0.eventType == .dose1_taken
                && abs($0.occurredAtUTC.timeIntervalSince(session.startedUTC)) < 1
        }) {
            return key(for: dose1, timeZone: timeZone)
        }
        return key(for: session.startedUTC, timeZone: timeZone)
    }

    static func key(
        for date: Date,
        timeZone: TimeZone = legacyFallbackTimeZone
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let localHour = calendar.component(.hour, from: date)
        let sessionDate: Date
        if localHour < rolloverHour {
            sessionDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        } else {
            sessionDate = date
        }

        let components = calendar.dateComponents([.year, .month, .day], from: sessionDate)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func validatedSessionDate(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let parts = candidate.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            return nil
        }
        return candidate
    }
}
