import Foundation
import DoseCore

@MainActor
public extension SessionRepository {
    static func parseSessionDate(_ sessionDate: String, in timeZone: TimeZone) -> Date? {
        let parts = sessionDate.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    /// Evaluate session boundaries driven by schedule (prep time + missed check-in cutoff).
    func evaluateSessionBoundaries(reason: String) {
        guard activeSessionId != nil, let sessionDate = activeSessionDate else { return }
        guard activeSessionEnd == nil else { return }

        let now = clock()
        let prep = prepTime(for: now)
        let scheduledStart = scheduledSleepStart(for: sessionDate)
        let start = activeSessionStart ?? dose1Time ?? scheduledStart ?? now
        let cutoff = cutoffTime(for: start)

        if now >= cutoff {
            closeActiveSession(
                at: now,
                terminalState: "incomplete_missed_checkin",
                reason: "missed_checkin_cutoff.\(reason)"
            )
            #if canImport(OSLog)
            logger.info("SessionRepo: Auto-closed session \(sessionDate, privacy: .public) (cutoff reached)")
            #endif
            return
        }

        if now >= prep && start < prep {
            closeActiveSession(
                at: now,
                terminalState: "incomplete_prep_rollover",
                reason: "prep_time.\(reason)"
            )
            #if canImport(OSLog)
            logger.info("SessionRepo: Soft rollover at prep time for session \(sessionDate, privacy: .public)")
            #endif
        }
    }

    /// Check if timezone has changed since Dose 1 was taken.
    func checkTimezoneChange() -> String? {
        guard let referenceOffset = dose1TimezoneOffsetMinutes else {
            return nil
        }
        let now = clock()
        guard let delta = timezoneDelta(from: referenceOffset, at: now) else {
            return nil
        }
        return timezoneChangeDescription(delta: delta)
    }

    /// Check if timezone has changed (boolean convenience).
    var hasTimezoneChanged: Bool {
        guard let referenceOffset = dose1TimezoneOffsetMinutes else {
            return false
        }
        let now = clock()
        return timezoneDelta(from: referenceOffset, at: now) != nil
    }
}

@MainActor
extension SessionRepository {
    func timeFromMinutes(_ minutes: Int, on date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let day = calendar.startOfDay(for: date)
        let hour = minutes / 60
        let minute = minutes % 60
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    func nextOccurrence(of minutes: Int, after date: Date, timeZone: TimeZone) -> Date {
        let candidate = timeFromMinutes(minutes, on: date, timeZone: timeZone)
        if candidate > date {
            return candidate
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let nextDay = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return timeFromMinutes(minutes, on: nextDay, timeZone: timeZone)
    }

    func prepTime(for date: Date) -> Date {
        let minutes = UserSettingsManager.shared.prepTimeMinutes
        return timeFromMinutes(minutes, on: date, timeZone: timeZoneProvider())
    }

    func sessionDateToDate(_ sessionDate: String) -> Date? {
        Self.parseSessionDate(sessionDate, in: timeZoneProvider())
    }

    func scheduledSleepStart(for sessionDate: String) -> Date? {
        guard let day = sessionDateToDate(sessionDate) else { return nil }
        let minutes = UserSettingsManager.shared.sleepStartMinutes
        return timeFromMinutes(minutes, on: day, timeZone: timeZoneProvider())
    }

    func cutoffTime(for sessionStart: Date) -> Date {
        let settings = UserSettingsManager.shared
        let wake = nextOccurrence(of: settings.wakeTimeMinutes, after: sessionStart, timeZone: timeZoneProvider())
        return wake.addingTimeInterval(TimeInterval(settings.missedCheckInCutoffHours * 3600))
    }

    func timezoneOffsets(at date: Date) -> [Int] {
        let primary = timeZoneProvider().secondsFromGMT(for: date) / 60
        let defaultOffset = NSTimeZone.default.secondsFromGMT(for: date) / 60
        if primary == defaultOffset {
            return [primary]
        }
        return [primary, defaultOffset]
    }

    func timezoneDelta(from referenceOffset: Int, at date: Date) -> Int? {
        for offset in timezoneOffsets(at: date) {
            let delta = offset - referenceOffset
            if delta != 0 {
                return delta
            }
        }
        return nil
    }

    func timezoneChangeDescription(delta: Int) -> String {
        let hours = abs(delta) / 60
        let minutes = abs(delta) % 60
        let direction = delta > 0 ? "east" : "west"

        if hours == 0 {
            return "Timezone shifted \(minutes) minutes \(direction)"
        } else if minutes == 0 {
            let hourWord = hours == 1 ? "hour" : "hours"
            return "Timezone shifted \(hours) \(hourWord) \(direction)"
        } else {
            let hourWord = hours == 1 ? "hour" : "hours"
            return "Timezone shifted \(hours) \(hourWord) \(minutes) minutes \(direction)"
        }
    }
}
