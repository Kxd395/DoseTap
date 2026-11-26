import Foundation
import DoseCore

@MainActor
extension DashboardAnalyticsModel {
    func physicianNapSources(for period: PhysicianReportPeriod) throws -> [PhysicianReportObservation] {
        let stored = try sessionRepo.napDiary()
        var document = stored ?? NapDiaryDocument()
        document.episodes = document.episodes.filter { $0.recordedAt <= reportingAsOf }
        document.reviews = document.reviews.filter { $0.recordedAt <= reportingAsOf }
        guard document.isValid else { throw PhysicianReviewError.invalidRevision }
        let sources = try sessionRepo.napDiarySources(document: document, asOf: reportingAsOf, defaultTimeZoneID: period.timeZoneIdentifier)
        let merged = document.merging(sources)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
        func dayOverlaps(_ day: String, _ zoneID: String) throws -> Bool {
            guard let zone = TimeZone(identifier: zoneID) else { throw PhysicianReviewError.invalidPeriod }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let formatter = DateFormatter(); formatter.calendar = calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"
            guard let start = formatter.date(from: day), formatter.string(from: start) == day,
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { throw PhysicianReviewError.invalidPeriod }
            return start < period.endExclusive && end > period.start
        }
        func raw<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        let currentRevisions = Set(document.current.map(\.revision))
        let entries = document.episodes.filter { !currentRevisions.contains($0.revision) }.map { ($0, false) }
            + merged.map { ($0, true) }
        var result: [PhysicianReportObservation] = []
        var projections: [String: NapDayProjection] = [:]
        for (episode, current) in entries {
            guard try dayOverlaps(episode.day, episode.timeZoneID), episode.start.map(period.contains) ?? true else { continue }
            let status = document.status(day: episode.day, zone: episode.timeZoneID, episodes: merged)
            let key = episode.day + "|" + episode.timeZoneID
            let projection = projections[key] ?? NapDayProjection(timeZoneID: episode.timeZoneID, day: episode.day, episodes: merged, review: status)
            projections[key] = projection
            let needsReview = episode.sourceNeedsReview || projection.overlapIDs.contains(episode.id)
                || projection.unresolvedDuplicateIDs.contains(episode.id) || projection.reviewConflict
            let persisted = document.episodes.contains { $0.revision == episode.revision }
            let identity = persisted ? episode.revision.uuidString : "source:" + episode.evidenceKey
            var shareable = episode; shareable.reason = ""
            let lines = [current ? "Current nap evidence at source cutoff." : "Historical immutable nap revision; not a current count.",
                "Original day: \(episode.day); timezone: \(episode.timeZoneID). Work context unknown; no reviewed nap-to-work association exists.",
                "Reported sleep estimate and elapsed rest remain distinct. Missing estimate is unknown; rest attempt and unknown intent are not confirmed sleep.",
                "Source evidence key: \(episode.evidenceKey); source needs review: \(episode.sourceNeedsReview).",
                persisted ? "Persisted revision: \(episode.revision)." : "Timer projection revision is transient; source event IDs and evidence key identify the evidence.",
                "Read document revision: \(stored?.revision.uuidString ?? "unavailable"); historical rows filtered at frozen source cutoff. Correction reason omitted from sharing.",
                "Original payload (Unix-second timestamps): " + (try raw(shareable))]
            result.append(.init(id: "nap:" + episode.id + ":" + identity, observedAt: episode.start,
                metricID: "Independent nap record • " + episode.intent.rawValue, value: nil,
                state: needsReview ? .needsReview : .notApplicable, unit: "record", source: "Reported nap diary and original timer evidence",
                definitionVersion: "nap-report.v1", detail: lines.joined(separator: "\n"),
                recordIDs: [episode.id, episode.evidenceKey] + episode.sourceEventIDs + (persisted ? [episode.revision.uuidString] : []),
                requiresReview: needsReview, detailOnly: true))
        }
        for review in document.reviews where try dayOverlaps(review.day, review.timeZoneID) {
            result.append(.init(id: "nap-day-review:" + review.id.uuidString, observedAt: nil,
                metricID: "Nap day review • " + review.status.rawValue, value: nil, state: .notApplicable, unit: "record",
                source: "Explicit original-day nap review", definitionVersion: "nap-report.v1",
                detail: "Original civil day and timezone are retained; assessment time is not an episode occurrence. This raw review alone does not establish a fully assessed report day or a zero nap count. Reviewed evidence may have changed. Work context unknown.\nOriginal payload (Unix-second timestamps): " + (try raw(review)),
                recordIDs: [review.id.uuidString] + review.reviewedEvidence, detailOnly: true))
        }
        return result
    }
}
