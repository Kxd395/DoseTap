import Foundation
import CryptoKit

public enum NapCompleteness: String, Codable, CaseIterable, Sendable {
    case unreviewed = "Not reviewed", partial = "Partial logging", complete = "All naps reviewed", none = "No naps confirmed"
}
public enum NapIntent: String, Codable, CaseIterable, Sendable {
    case unknown = "Not answered", planned = "Planned nap", unplanned = "Unplanned sleep", rest = "Rest attempt"
}
public struct NapEpisode: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var revision = UUID()
    public var predecessor: UUID?
    public var day: String
    public var timeZoneID: String
    public var start: Date?
    public var end: Date?
    public var estimatedSleepMinutes: Double?
    public var intent = NapIntent.unknown
    public var benefitRating: Int?
    public var sourceEventIDs: [String] = []
    public var sourceEvidenceKey: String?
    public var sourceNeedsReview = false
    private enum CodingKeys: String, CodingKey { case id, revision, predecessor, day, timeZoneID, start, end, estimatedSleepMinutes, intent, benefitRating, sourceEventIDs, sourceEvidenceKey, duplicateOf, reason, recordedAt }
    public var duplicateOf: String?
    public var reason = ""
    public var recordedAt: Date
    public init(id: String = UUID().uuidString, day: String, timeZoneID: String, start: Date? = nil,
                end: Date? = nil, estimatedSleepMinutes: Double? = nil, recordedAt: Date) {
        self.id = id; self.day = day; self.timeZoneID = timeZoneID; self.start = start; self.end = end
        self.estimatedSleepMinutes = estimatedSleepMinutes; self.recordedAt = recordedAt
    }
    public var restMinutes: Double? {
        guard let start, let end, end > start else { return nil }; return end.timeIntervalSince(start) / 60
    }
    public var isValid: Bool {
        guard !sourceNeedsReview, !id.isEmpty, id.count <= 300, TimeZone(identifier: timeZoneID) != nil,
              DashboardReportingWindow.isValidDateKey(day), recordedAt.timeIntervalSince1970.isFinite,
              day <= Self.day(recordedAt, timeZoneID),
              [start, end].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite && $0 <= recordedAt }),
              (start ?? end).map({ Self.day($0, timeZoneID) == day }) ?? true,
              restMinutes.map({ $0 <= 1440 }) ?? (start == nil || end == nil), reason.count <= 1000,
              Set(sourceEventIDs).count == sourceEventIDs.count, sourceEventIDs.allSatisfy({ !$0.isEmpty && $0.count <= 300 }),
              duplicateOf == nil || (duplicateOf != id && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
              benefitRating.map({ (0...10).contains($0) }) ?? true,
              predecessor == nil || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return estimatedSleepMinutes.map { $0.isFinite && $0 >= 0 && $0 <= (restMinutes ?? 1440) } ?? true
    }
    public static func day(_ date: Date, _ zone: String) -> String {
        guard date.timeIntervalSince1970.isFinite, let timeZone = TimeZone(identifier: zone) else { return "" }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard parts.era == 1, let year = parts.year, (1...9999).contains(year), let month = parts.month, let day = parts.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
public extension NapEpisode {
    var evidenceKey: String {
        let values = [id, day, timeZoneID, start.map { String($0.timeIntervalSince1970) } ?? "",
                      end.map { String($0.timeIntervalSince1970) } ?? "", estimatedSleepMinutes.map(String.init(describing:)) ?? "",
                      intent.rawValue, benefitRating.map(String.init) ?? "", duplicateOf ?? "", reason, sourceEvidenceKey ?? "", String(sourceNeedsReview)] + sourceEventIDs.sorted()
        guard let bytes = try? JSONEncoder().encode(values) else { return "" }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
public struct NapDayReview: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public let day: String
    public let timeZoneID: String
    public let status: NapCompleteness
    public let recordedAt: Date
    public let reviewedEvidence: [String]
    public init(day: String, timeZoneID: String, status: NapCompleteness, recordedAt: Date, episodes: [NapEpisode] = []) {
        reviewedEvidence = episodes.filter { $0.day == day && $0.timeZoneID == timeZoneID }.map(\.evidenceKey).sorted()
        self.day = day; self.timeZoneID = timeZoneID; self.status = status; self.recordedAt = recordedAt
    }
}
public struct NapDiaryDocument: Codable, Equatable, Sendable {
    public var version = 1
    public var revision = UUID()
    public var episodes: [NapEpisode] = []
    public var reviews: [NapDayReview] = []
    public init() {}
    public var current: [NapEpisode] {
        let superseded = Set(episodes.compactMap(\.predecessor))
        return episodes.filter { !superseded.contains($0.revision) }.sorted { $0.day == $1.day ? $0.id < $1.id : $0.day > $1.day }
    }
    public var isValid: Bool {
        guard version == 1, episodes.count <= 50000, reviews.count <= 50000,
              episodes.allSatisfy(\.isValid), Set(episodes.map(\.revision)).count == episodes.count,
              Set(reviews.map(\.id)).count == reviews.count,
              reviews.allSatisfy({ DashboardReportingWindow.isValidDateKey($0.day) && TimeZone(identifier: $0.timeZoneID) != nil && $0.recordedAt.timeIntervalSince1970.isFinite && $0.day <= NapEpisode.day($0.recordedAt, $0.timeZoneID) }) else { return false }
        var previous: [String: NapEpisode] = [:]
        for value in episodes {
            guard value.predecessor == previous[value.id]?.revision,
                  previous[value.id].map({ $0.recordedAt <= value.recordedAt }) ?? true else { return false }
            previous[value.id] = value
        }
        for value in previous.values {
            var visited = Set([value.id]); var cursor = value.duplicateOf
            while let id = cursor {
                guard visited.insert(id).inserted else { return false }; cursor = previous[id]?.duplicateOf
            }
        }
        return true
    }
    public func status(day: String, zone: String, episodes: [NapEpisode]) -> NapCompleteness {
        guard let review = reviews.last(where: { $0.day == day && $0.timeZoneID == zone }) else { return .unreviewed }
        let evidence = episodes.filter { $0.day == day && $0.timeZoneID == zone }.map(\.evidenceKey).sorted()
        if [.complete, .none].contains(review.status), evidence != review.reviewedEvidence { return .partial }
        return review.status
    }
    public func merging(_ source: [NapEpisode]) -> [NapEpisode] {
        let revised = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        let originals = Dictionary(grouping: source, by: \.id)
        return source.filter { revised[$0.id] == nil } + current.map { stored in
            var value = stored
            value.sourceNeedsReview = !value.sourceEventIDs.isEmpty && (originals[value.id]?.count != 1 || originals[value.id]?.first?.evidenceKey != value.sourceEvidenceKey)
            return value
        }
    }
}
/// Reported duration totals never become provider-measured sleep or a complete-day claim.
public struct NapDayProjection: Sendable {
    public let day: String
    public let episodes: [NapEpisode]
    public let overlapIDs: Set<String>
    public let unresolvedDuplicateIDs: Set<String>
    public let review: NapCompleteness
    public let reviewConflict: Bool
    public var episodeCount: Int { episodes.count }
    public var completenessLabel: String {
        if reviewConflict { return "No-naps confirmation conflicts with episode evidence" }
        if review == .complete && unavailableCount > 0 { return "Naps reviewed; some durations remain unavailable" }
        if review == .unreviewed && episodes.isEmpty { return "No nap records or day review collected" }
        return review.rawValue
    }
    public var unavailableCount: Int { episodes.filter { $0.sourceNeedsReview || $0.estimatedSleepMinutes == nil || overlapIDs.contains($0.id) || unresolvedDuplicateIDs.contains($0.id) }.count }
    public var estimatedMinutesByIntent: [NapIntent: Double] {
        var totals: [NapIntent: Double] = [:]
        for episode in episodes where !episode.sourceNeedsReview && !overlapIDs.contains(episode.id) && !unresolvedDuplicateIDs.contains(episode.id) {
            if let minutes = episode.estimatedSleepMinutes { totals[episode.intent, default: 0] += minutes }
        }
        return totals
    }
    public var estimatedMinutes: Double? {
        if episodes.isEmpty { return review == .none && !reviewConflict ? 0 : nil }
        let values = episodes.filter { !$0.sourceNeedsReview && !overlapIDs.contains($0.id) && !unresolvedDuplicateIDs.contains($0.id) }.compactMap(\.estimatedSleepMinutes)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    public init(timeZoneID: String, day: String, episodes: [NapEpisode], review: NapCompleteness) {
        let inputs = episodes.filter { $0.timeZoneID == timeZoneID }
        self.day = day; self.review = review
        let groups = Dictionary(grouping: inputs, by: \.id)
        let byID = groups.compactMapValues(\.first)
        let conflicting = Set(groups.filter { Set($0.value.map(\.evidenceKey)).count > 1 }.keys)
        var resolution: [String: Bool] = [:]
        func resolves(_ value: NapEpisode) -> Bool {
            var path: [String] = []; var visited = Set<String>(); var cursor = value
            var valid = false
            while visited.insert(cursor.id).inserted {
                if let known = resolution[cursor.id] { valid = known; break }
                path.append(cursor.id)
                guard !conflicting.contains(cursor.id) else { break }
                guard let next = cursor.duplicateOf else { valid = true; break }
                guard let target = byID[next], !conflicting.contains(next) else { break }
                let compatible: Bool
                if let a = cursor.start, let b = cursor.end, let c = target.start, let d = target.end { compatible = a < d && c < b }
                else { compatible = cursor.day == target.day && cursor.timeZoneID == target.timeZoneID }
                guard compatible else { break }
                cursor = target
            }
            path.forEach { resolution[$0] = valid }; return valid
        }
        let resolved = Set(byID.values.filter { $0.duplicateOf != nil && resolves($0) }.map(\.id))
        let unresolved = conflicting.union(byID.values.filter { $0.duplicateOf != nil && !resolved.contains($0.id) }.map(\.id))
        let retained = byID.values.filter { !resolved.contains($0.id) }.sorted { $0.id < $1.id }
        var overlap = Set<String>(); var sources: [String: String] = [:]
        for value in retained {
            for source in value.sourceEventIDs {
                if let previous = sources[source] { overlap.insert(previous); overlap.insert(value.id) }
                sources[source] = value.id
            }
        }
        // A sweep marks every overlapping interval without an all-history pair scan.
        let timed = retained.filter { $0.start != nil && $0.end != nil }.sorted { $0.start! < $1.start! }
        var furthest: NapEpisode?
        for value in timed {
            if let previous = furthest, value.start! < previous.end! { overlap.insert(previous.id); overlap.insert(value.id) }
            if furthest == nil || value.end! > furthest!.end! { furthest = value }
        }
        self.episodes = retained.filter { $0.day == day }
        overlapIDs = overlap; unresolvedDuplicateIDs = unresolved
        reviewConflict = review == .none && !self.episodes.isEmpty
    }
}

public struct NapTimerMarker: Sendable {
    public let id: String
    public let sessionID: String?
    public let date: Date
    public let isStart: Bool
    public init(id: String, sessionID: String?, date: Date, isStart: Bool) {
        self.id = id; self.sessionID = sessionID; self.date = date; self.isStart = isStart
    }
}
public extension NapEpisode {
    /// Pair only one pending start with one subsequent end in the same durable session.
    /// Consecutive starts are ambiguous; retain them as incomplete observations.
    static func timers(_ markers: [NapTimerMarker], zone: String, asOf: Date) -> [NapEpisode] {
        var output: [NapEpisode] = []
        let groups = Dictionary(grouping: markers.filter { $0.date <= asOf && $0.date.timeIntervalSince1970.isFinite },
                                by: { $0.sessionID ?? "unresolved:" + $0.id })
        for (identity, values) in groups {
            var pending: [NapTimerMarker] = []
            func record(_ start: NapTimerMarker?, _ end: NapTimerMarker?) {
                guard let source = start ?? end else { return }
                var value = NapEpisode(id: "timer:" + source.id, day: day(source.date, zone), timeZoneID: zone,
                                       start: start?.date, end: end?.date, recordedAt: asOf)
                value.sourceEventIDs = [start?.id, end?.id].compactMap { $0 }
                value.reason = identity.hasPrefix("unresolved:") ? "Session association requires review" : "Recorded nap timer; elapsed rest is not measured asleep time"
                output.append(value)
            }
            for marker in values.sorted(by: { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }) {
                if marker.isStart { pending.append(marker) }
                else if pending.count == 1, let start = pending.first, marker.date > start.date, marker.date.timeIntervalSince(start.date) <= 86400 {
                    record(start, marker); pending.removeAll()
                } else {
                    pending.forEach { record($0, nil) }; pending.removeAll(); record(nil, marker)
                }
            }
            pending.forEach { record($0, nil) }
        }
        return output.sorted { $0.day == $1.day ? $0.id < $1.id : $0.day > $1.day }
    }
}

/// A descriptive interval between two explicitly selected actual occurrences; no proximity pairing.
public struct NapDoseInterval: Equatable, Sendable {
    public let napID: String
    public let doseID: String
    public let sessionID: String
    public let start: Date
    public let end: Date
    public var minutes: Double { end.timeIntervalSince(start) / 60 }
    public init?(episode: NapEpisode, dose: StoredDoseEvent, sessionID: String, asOf: Date) {
        guard episode.isValid, episode.duplicateOf == nil, let end = episode.end,
              !sessionID.isEmpty, dose.sessionId == sessionID, !dose.id.isEmpty,
              ["dose1", "dose2", "extra_dose"].contains(dose.eventType),
              asOf.timeIntervalSince1970.isFinite, dose.timestamp.timeIntervalSince1970.isFinite,
              end < dose.timestamp, dose.timestamp <= asOf, episode.recordedAt <= asOf else { return nil }
        napID = episode.id; doseID = dose.id; self.sessionID = sessionID
        start = end; self.end = dose.timestamp
    }
}
