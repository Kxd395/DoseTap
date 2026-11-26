import Foundation
import DoseCore

/// Independent original civil-day assessments; no sleep-session or work-phase join is manufactured.
struct WorkCycleNapDayReport {
    struct Row: Identifiable {
        let id: String, day: String, timeZoneID: String
        let reviewID: UUID?, review: NapCompleteness, recordedAt: Date?
        let episodeIDs: [String], evidenceKeys: [String], sourceEventIDs: [String]
        let intentCounts: [NapIntent: Int], recordCount: Int?
        let completePeriodCoverage: Bool, reason: String
        var phase: WorkPhase { .unknown }
    }
    let rows: [Row]
    let documentRevision: UUID?
    let window: DashboardDaytimeWindow
    var assessedDayCount: Int { rows.filter { $0.recordCount != nil }.count }
    var unknownWorkDayCount: Int { rows.count }
    var csv: String {
        let headers = ["day", "original_timezone", "work_context", "review_id", "review_state", "review_recorded_at_utc", "recorded_episode_count", "recorded_planned", "recorded_unplanned", "recorded_rest_attempt", "recorded_unknown_intent", "complete_day_coverage", "eligibility_reason", "episode_ids", "evidence_keys", "source_event_ids", "document_revision", "as_of_utc", "period_start_utc", "period_end_exclusive_utc", "assessed_days", "recorded_days", "definition", "document_revision_state"]
        let stamp: (Date?) -> String = { value in value.map { ISO8601DateFormatter().string(from: $0) } ?? "" }
        let metadata = [documentRevision?.uuidString ?? "", stamp(window.asOf), stamp(window.start), stamp(window.endExclusive), String(assessedDayCount), String(rows.count), "original_civil_day_nap_records_v1", documentRevision == nil ? "unavailable" : "available"]
        let records = rows.map { row -> String in
            let identity = [row.day, row.timeZoneID, "Unknown; no independently reviewed work-day association", row.reviewID?.uuidString ?? "", row.review.rawValue, stamp(row.recordedAt), row.recordCount.map(String.init) ?? ""]
            let counts = [NapIntent.planned, .unplanned, .rest, .unknown].map { String(row.intentCounts[$0] ?? 0) }
            return ReportCSV.row(identity + counts + [String(row.completePeriodCoverage), row.reason, row.episodeIDs.joined(separator: "|"), row.evidenceKeys.joined(separator: "|"), row.sourceEventIDs.joined(separator: "|")] + metadata)
        }
        let body = records.isEmpty ? [ReportCSV.row(Array(repeating: "", count: 16) + metadata)] : records
        return ([ReportCSV.row(headers)] + body).joined(separator: "\r\n") + "\r\n"
    }
    init(document: NapDiaryDocument, merged: [NapEpisode], window: DashboardDaytimeWindow, hasStoredDocument: Bool = true) {
        self.documentRevision = hasStoredDocument ? document.revision : nil; self.window = window
        let evidence = merged.filter { $0.recordedAt <= window.asOf }
        let reviews = document.reviews.filter { $0.recordedAt <= window.asOf }
        var frozen = document; frozen.reviews = reviews
        let keys = Set(evidence.map { [$0.day, $0.timeZoneID] } + reviews.map { [$0.day, $0.timeZoneID] })
        rows = keys.sorted { $0.lexicographicallyPrecedes($1) }.compactMap { key in
            let day = key[0], zone = key[1]
            guard let lower = window.start, let bounds = NapPeriodEligibility.dayBounds(day: day, timeZoneID: zone),
                  bounds.0 < window.endExclusive, bounds.1 > lower else { return nil }
            let status = frozen.status(day: day, zone: zone, episodes: evidence)
            let projection = NapDayProjection(timeZoneID: zone, day: day, episodes: evidence, review: status)
            let covered = bounds.0 >= lower && bounds.1 <= window.endExclusive
            let dayIDs = Set(projection.episodes.map(\.id))
            let reliable = !projection.reviewConflict && projection.overlapIDs.isDisjoint(with: dayIDs) && projection.unresolvedDuplicateIDs.isDisjoint(with: dayIDs)
                && projection.episodes.allSatisfy { !$0.sourceNeedsReview && $0.isValid }
            let assessed = covered && reliable && ((status == .none && projection.episodes.isEmpty)
                || (status == .complete && !projection.episodes.isEmpty))
            let review = reviews.last { $0.day == day && $0.timeZoneID == zone }
            return Row(id: "nap-day:" + zone + ":" + day, day: day, timeZoneID: zone,
                reviewID: review?.id, review: status, recordedAt: review?.recordedAt,
                episodeIDs: projection.episodes.map(\.id), evidenceKeys: projection.episodes.map(\.evidenceKey),
                sourceEventIDs: Array(Set(projection.episodes.flatMap(\.sourceEventIDs))).sorted(),
                intentCounts: Dictionary(grouping: projection.episodes, by: \.intent).mapValues(\.count),
                recordCount: assessed ? projection.episodeCount : nil, completePeriodCoverage: covered,
                reason: !covered ? "Partial civil day; full-day count withheld" : assessed ? "Reviewed episode records; intent categories remain separate" : projection.completenessLabel)
        }
    }
}

extension DashboardAnalyticsModel {
    func workCycleNapDayReport(period: PhysicianReportPeriod? = nil) throws -> WorkCycleNapDayReport {
        _ = try validatedSharedDaytimeSelection()
        let stored = try sessionRepo.napDiary()
        var document = stored ?? NapDiaryDocument()
        document.episodes = document.episodes.filter { $0.recordedAt <= reportingAsOf }
        document.reviews = document.reviews.filter { $0.recordedAt <= reportingAsOf }
        let source = try sessionRepo.napDiarySources(document: document, asOf: reportingAsOf, defaultTimeZoneID: reportingTimeZone.identifier)
        let episodes = document.merging(source)
        let first = (episodes.compactMap { NapPeriodEligibility.dayBounds($0)?.0 }
            + document.reviews.compactMap { NapPeriodEligibility.dayBounds(day: $0.day, timeZoneID: $0.timeZoneID)?.0 }).min()
        let exact = period ?? reportingPeriod
        let range = exact.map { $0.completedVisitID == nil ? DashboardReportingRange.custom : .sinceCompletedVisit } ?? selectedRange
        let window = try range.daytimeWindow(asOf: reportingAsOf, timeZone: reportingTimeZone, reviewedPeriod: exact, earliestEvidenceAt: first)
        return .init(document: document, merged: episodes, window: window, hasStoredDocument: stored != nil)
    }
}
