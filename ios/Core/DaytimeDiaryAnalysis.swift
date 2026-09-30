import Foundation

public struct DaytimeSamplingGroup: Identifiable, Sendable {
    public let id: String
    public let origin: DaytimeCheckIn.Origin
    public let setting: DaytimeCheckIn.Setting
    public let timeZoneIdentifier: String
    public let samplingProtocolID: UUID?
    public let samplingProtocolLabel: String?
    public let clockBand: Int
    public let observationIDs: [UUID]
    public let entryCount: Int
    public let firstAssessedAt: Date
    public let lastAssessedAt: Date
    public let answeredCount: Int
    public let ratedDays: Int
    public let median: Double?
    public let distribution: [Int: Int]
    public var clockBandLabel: String { String(format: "%02d:00–%02d:59 local", clockBand * 6, clockBand * 6 + 5) }
}

/// Descriptive samples only. Inputs are current revisions, never medication-effect or scale conversions.
public struct DaytimeDiaryAnalysis: Sendable {
    public let calculationVersion = 1
    public let observations: [DaytimeCheckIn]
    public let groups: [DaytimeSamplingGroup]
    public let answeredCount: Int
    public let ratedCalendarDays: Int
    public let calendarDays: Int
    public let unplannedSleepEvents: Int
    public let eventCountsByKind: [DaytimeEvent.Kind: Int]
    public let copingResponseCounts: [DaytimeCheckIn.Coping: Int]
    public let reviewedIntervals: [DateInterval]
    public let reviewedCalendarDays: Int
    public let fullyReviewedCalendarDays: Int
    public let reviewSubmissionDays: Int
    public var partiallyReviewedCalendarDays: Int { reviewedCalendarDays - fullyReviewedCalendarDays }
    public var daysWithoutReviewedInterval: Int { calendarDays - reviewedCalendarDays }

    public init(observations input: [DaytimeCheckIn], events: [DaytimeEvent], start: Date, end: Date, now: Date, timeZone: TimeZone, includesEnd: Bool = true) throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        func supported(_ date: Date) -> Bool {
            guard date.timeIntervalSince1970.isFinite else { return false }
            let fields = calendar.dateComponents([.era, .year], from: date)
            return fields.era == 1 && fields.year.map { (1...9999).contains($0) } == true
        }
        guard supported(start), supported(end), supported(now), start <= end, (includesEnd || start < end), end <= now,
              Set(input.map(\.id)).count == input.count, Set(events.map(\.id)).count == events.count,
              input.allSatisfy({ $0.recordedAt <= now }), events.allSatisfy({ $0.recordedAt <= now }) else { throw DaytimeDiaryError.invalid }
        for value in input { try value.validate() }; for value in events { try value.validate() }
        let firstDay = calendar.startOfDay(for: start)
        func dayIndex(_ date: Date) -> Int { calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: date)).day ?? 0 }
        func inRange(_ date: Date) -> Bool { date >= start && (includesEnd ? date <= end : date < end) }
        calendarDays = dayIndex(end) + 1 - (!includesEnd && end == calendar.startOfDay(for: end) ? 1 : 0)
        observations = input.filter { inRange($0.assessedAt) }.sorted {
            $0.assessedAt == $1.assessedAt ? $0.id.uuidString < $1.id.uuidString : $0.assessedAt < $1.assessedAt
        }
        let rated = observations.filter { $0.response != nil }
        answeredCount = rated.count; ratedCalendarDays = Set(rated.map { dayIndex($0.assessedAt) }).count
        eventCountsByKind = Dictionary(grouping: events.filter { inRange($0.occurredAt) }, by: \.kind).mapValues(\.count)
        unplannedSleepEvents = eventCountsByKind[.unplannedSleep] ?? 0
        copingResponseCounts = Dictionary(grouping: observations, by: \.coping).mapValues(\.count)
        let definite = input.filter { $0.eventReview.map { $0.status == .noneReported || $0.status == .eventsReported } == true }
        reviewSubmissionDays = Set(definite.filter { inRange($0.recordedAt) }.map { dayIndex($0.recordedAt) }).count
        let clipped = definite.compactMap { value -> DateInterval? in
            guard let review = value.eventReview else { return nil }
            let lower = max(start, review.from), upper = min(end, review.to)
            return lower < upper ? DateInterval(start: lower, end: upper) : nil
        }.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for interval in clipped {
            if let last = merged.last, last.end >= interval.start {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else { merged.append(interval) }
        }
        reviewedIntervals = merged
        var touched: [ClosedRange<Int>] = []
        var fullDays = 0
        for interval in merged {
            let endDay = calendar.startOfDay(for: interval.end)
            let lastIndex = dayIndex(interval.end) - (interval.end == endDay ? 1 : 0)
            touched.append(dayIndex(interval.start)...max(dayIndex(interval.start), lastIndex))
            let first = calendar.startOfDay(for: interval.start)
            guard let fullStart = interval.start == first ? first : calendar.date(byAdding: .day, value: 1, to: first) else { throw DaytimeDiaryError.invalid }
            fullDays += max(0, calendar.dateComponents([.day], from: fullStart, to: endDay).day ?? 0)
        }
        var dayRanges: [ClosedRange<Int>] = []
        for range in touched {
            if let last = dayRanges.last, range.lowerBound <= last.upperBound + 1 {
                dayRanges[dayRanges.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else { dayRanges.append(range) }
        }
        reviewedCalendarDays = dayRanges.reduce(0) { $0 + $1.upperBound - $1.lowerBound + 1 }
        fullyReviewedCalendarDays = fullDays
        var buckets: [String: [DaytimeCheckIn]] = [:]
        for row in observations {
            guard let zone = TimeZone(identifier: row.timeZoneIdentifier) else { throw DaytimeDiaryError.invalid }
            var local = Calendar(identifier: .gregorian); local.timeZone = zone
            let band = local.component(.hour, from: row.assessedAt) / 6
            let protocolKey = row.samplingProtocolID?.uuidString ?? (row.origin == .scheduled ? (row.promptID ?? row.id).uuidString : "unscheduled")
            let key = [row.origin.rawValue, row.setting.rawValue, row.timeZoneIdentifier, String(band), protocolKey,
                row.samplingProtocolLabel ?? "", row.instrumentID, row.contentVersion, row.language].joined(separator: "|")
            buckets[key, default: []].append(row)
        }
        groups = buckets.keys.sorted().compactMap { key in
            guard let rows = buckets[key], let first = rows.first, let zone = TimeZone(identifier: first.timeZoneIdentifier) else { return nil }
            var local = Calendar(identifier: .gregorian); local.timeZone = zone
            let scores = rows.compactMap(\.response).sorted()
            let middle = scores.count / 2
            let median = scores.isEmpty ? nil : scores.count.isMultiple(of: 2) ? Double(scores[middle - 1] + scores[middle]) / 2 : Double(scores[middle])
            return DaytimeSamplingGroup(id: key, origin: first.origin, setting: first.setting, timeZoneIdentifier: first.timeZoneIdentifier,
                samplingProtocolID: first.samplingProtocolID, samplingProtocolLabel: first.samplingProtocolLabel,
                clockBand: local.component(.hour, from: first.assessedAt) / 6, observationIDs: rows.map(\.id), entryCount: rows.count,
                firstAssessedAt: rows.map(\.assessedAt).min() ?? first.assessedAt, lastAssessedAt: rows.map(\.assessedAt).max() ?? first.assessedAt, answeredCount: scores.count,
                ratedDays: Set(rows.filter { $0.response != nil }.map { local.startOfDay(for: $0.assessedAt) }).count,
                median: median, distribution: Dictionary(grouping: scores, by: { $0 }).mapValues(\.count))
        }
    }
}
