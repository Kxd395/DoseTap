import Foundation
import CryptoKit
import DoseCore

struct DaytimeSourceCandidate: Identifiable {
    let link: DaytimeSourceLink
    let label: String
    var id: String { link.id }
    func matches(_ saved: DaytimeSourceLink) -> Bool {
        link.kind == saved.kind && link.sourceID == saved.sourceID && link.sourceRevisionID == saved.sourceRevisionID &&
        link.evidenceKey == saved.evidenceKey && link.sourceEventIDs == saved.sourceEventIDs &&
        link.sourceCalendarDay == saved.sourceCalendarDay && link.timeZoneIdentifier == saved.timeZoneIdentifier &&
        link.start == saved.start && link.end == saved.end && link.timePrecision == saved.timePrecision
    }
}

enum DaytimeSourceSelectionError: LocalizedError {
    case changed
    var errorDescription: String? { "A selected source changed or is unavailable. Your observation is not saved. Keep the entry, choose Edit entry before retry, and review the selected sources." }
}

@MainActor
extension SessionRepository {
    func daytimeSourceCandidates(kind: DaytimeSourceLink.Kind, asOf: Date, inTransaction: Bool = false) throws -> [DaytimeSourceCandidate] {
        guard asOf.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.invalid }
        var values: [DaytimeSourceCandidate] = []
        switch kind {
        case .nap:
            let document = try napDiary()
            let durable = Dictionary(uniqueKeysWithValues: (document?.current ?? []).map { ($0.id, $0) })
            let episodes = try reviewedNapEpisodes(asOf: asOf, defaultTimeZoneID: timeZoneProvider().identifier, inTransaction: inTransaction)
            let days = Dictionary(grouping: episodes, by: { "\($0.timeZoneID.utf8.count):\($0.timeZoneID)|\($0.day)" })
            let blocked = days.values.reduce(into: Set<String>()) { result, values in
                guard let first = values.first else { return }
                let projection = NapDayProjection(timeZoneID: first.timeZoneID, day: first.day, episodes: episodes, review: .unreviewed)
                result.formUnion(projection.overlapIDs); result.formUnion(projection.unresolvedDuplicateIDs)
            }
            for episode in episodes where episode.isValid && episode.duplicateOf == nil && !episode.sourceNeedsReview && !blocked.contains(episode.id) && episode.recordedAt <= asOf {
                let link = try DaytimeSourceLink(kind: .nap, sourceID: episode.id, sourceRevisionID: durable[episode.id]?.revision.uuidString,
                    evidenceKey: episode.evidenceKey, sourceEventIDs: episode.sourceEventIDs, sourceCalendarDay: episode.day,
                    timeZoneIdentifier: episode.timeZoneID, start: episode.start, end: episode.end,
                    timePrecision: episode.start == nil && episode.end == nil ? .unknown : .reported, selectedAt: asOf)
                let bounds = "\(link.daytimeTimestamp(episode.start)) – \(link.daytimeTimestamp(episode.end))"
                values.append(.init(link: link, label: "\(episode.day) · \(episode.timeZoneID) · \(episode.intent.rawValue) · \(bounds)"))
            }
        case .mainWake:
            for source in try daytimeMainWakeSources(asOf: asOf) {
                let link = try DaytimeSourceLink(kind: .mainWake, sourceID: source.id, sourceRevisionID: source.revision,
                    evidenceKey: source.revision, sourceEventIDs: [source.id], start: source.at, timePrecision: .reported, selectedAt: asOf)
                values.append(.init(link: link, label: "Reported main wake · \(link.daytimeTimestamp(source.at))"))
            }
        case .medication:
            func digest<T: Encodable>(_ row: T) throws -> String {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
                return SHA256.hash(data: try encoder.encode(row)).map { String(format: "%02x", $0) }.joined()
            }
            for record in try medicationHistory() {
                switch record {
                case .quick(let row):
                    guard row.createdAt <= asOf, row.takenAtUTC <= asOf else { continue }
                    let link = try DaytimeSourceLink(kind: .medication, sourceID: record.id, evidenceKey: digest(row), sourceEventIDs: [row.id],
                        start: row.takenAtUTC, timePrecision: .recordedOccurrence, selectedAt: asOf)
                    values.append(.init(link: link, label: "\(record.searchText) · \(row.doseMg) \(row.doseUnit) · \(link.daytimeTimestamp(row.takenAtUTC))"))
                case .preset(let row):
                    guard row.recordedAt <= asOf, row.occurredAt.map({ $0 <= asOf }) ?? true else { continue }
                    let precision: DaytimeSourceLink.TimePrecision = row.precision == .unknown ? .unknown : (row.precision == .approximate ? .approximate : .reported)
                    let link = try DaytimeSourceLink(kind: .medication, sourceID: record.id, sourceRevisionID: row.preset.revisionID.uuidString,
                        evidenceKey: digest(row), sourceEventIDs: [row.id.uuidString], timeZoneIdentifier: row.timeZoneIdentifier,
                        start: row.occurredAt, timePrecision: precision, selectedAt: asOf)
                    values.append(.init(link: link, label: "\(record.searchText) · \(try row.totalMilligrams) mg · \(link.daytimeTimestamp(row.occurredAt))"))
                }
            }
        }
        guard Set(values.map(\.id)).count == values.count else { throw DaytimeDiaryError.unreadable }
        return values.sorted { ($0.link.start ?? .distantPast) == ($1.link.start ?? .distantPast) ? $0.id < $1.id : ($0.link.start ?? .distantPast) > ($1.link.start ?? .distantPast) }
    }
    func validateDaytimeSourceSelection(_ links: [DaytimeSourceLink], asOf: Date) throws {
        for kind in [DaytimeSourceLink.Kind.nap, .medication, .mainWake] {
            let selected = links.filter { $0.kind == kind }
            guard !selected.isEmpty else { continue }
            let candidates = try daytimeSourceCandidates(kind: kind, asOf: asOf, inTransaction: true)
            for link in selected {
                guard link.selectedAt <= asOf, candidates.contains(where: { $0.matches(link) }) else { throw DaytimeSourceSelectionError.changed }
            }
        }
    }
}

extension DaytimeSourceLink {
    func daytimeTimestamp(_ date: Date?) -> String {
        guard let date else { return "Occurrence time unknown" }
        let zone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        let formatter = DateFormatter(); formatter.timeZone = zone; formatter.dateStyle = .medium; formatter.timeStyle = .medium
        return formatter.string(from: date) + " (" + zone.identifier + ")"
    }
    var daytimePrecisionLabel: String {
        switch timePrecision {
        case .unknown: return "Time unknown"
        case .approximate: return "Approximate time"
        case .reported: return "Reported time"
        case .recordedOccurrence: return "Recorded occurrence time"
        }
    }
}
