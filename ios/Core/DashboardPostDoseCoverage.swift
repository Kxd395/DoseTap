import Foundation

/// Coverage for a named post-administration span, retaining its independent endpoint meaning.
public struct DashboardPostDoseCoverage: Codable, Equatable, Sendable {
    public static let version = "dashboard_postdose_coverage_v1"
    public struct Band: Codable, Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let state: ReviewedNightSleepProjection.Band.State
    }
    public let derivationVersion: String
    public let projectionVersion: String?
    public let preset: DashboardIntervalPreset
    public let state: DashboardMetricState
    public let reason: String
    public let startID: String?
    public let endID: String?
    public let elapsedMinutes: Double?
    public let asleepMinutes: Double?
    public let awakeMinutes: Double?
    public let unmeasuredMinutes: Double?
    public let conflictMinutes: Double?
    public let bands: [Band]

    public static func calculate(snapshot: DashboardReplaySnapshot, preset: DashboardIntervalPreset) -> Self {
        let interval = snapshot.interval(preset)
        func result(_ state: DashboardMetricState, _ reason: String, coverage: SleepIntervalCoverage? = nil,
                    conflicts: Double? = nil, bands: [Band] = []) -> Self {
            .init(derivationVersion: version, projectionVersion: snapshot.reviewedProjection?.derivationVersion,
                preset: preset, state: state, reason: reason, startID: interval.startID, endID: interval.endID,
                elapsedMinutes: interval.minutes, asleepMinutes: coverage?.asleepMinutes,
                awakeMinutes: coverage?.awakeMinutes, unmeasuredMinutes: coverage?.unmeasuredMinutes,
                conflictMinutes: conflicts, bands: bands)
        }
        guard [.dose2ToDeviceEnd, .dose2ToReportedWake, .dose2ToRequiredWake].contains(preset) else {
            return result(.notApplicable, "Choose a named final endpoint for post-Dose-2 coverage")
        }
        guard interval.state == .available else { return result(interval.state, interval.reason) }
        guard let start = snapshot.markers.first(where: { $0.id == interval.startID && $0.kind == preset.endpoints.0 })?.occurredAt,
              let end = snapshot.markers.first(where: { $0.id == interval.endID && $0.kind == preset.endpoints.1 })?.occurredAt, end > start else {
            return result(.needsReview, "The endpoint does not follow Dose 2; signed target timing remains separate")
        }
        guard end <= snapshot.asOf else { return result(.unavailable, "A future wake target has no observed future coverage") }
        guard let projection = snapshot.reviewedProjection else {
            return result(.unavailable, "Check reviewed-window coverage explicitly before inspecting this span")
        }
        let bands = projection.bands
        guard snapshot.hasValidBoundary, projection.window.sessionID == snapshot.sessionID,
              projection.generatedAt.timeIntervalSinceReferenceDate.isFinite, projection.generatedAt <= snapshot.asOf,
              projection.window.validationError(now: snapshot.asOf) == nil,
              !bands.isEmpty, bands.first?.start == projection.window.start, bands.last?.end == projection.window.end,
              bands.allSatisfy({ $0.start.timeIntervalSinceReferenceDate.isFinite && $0.end.timeIntervalSinceReferenceDate.isFinite && $0.end > $0.start }),
              zip(bands, bands.dropFirst()).allSatisfy({ $0.end == $1.start }) else {
            return result(.needsReview, "Reviewed projection identity or time partition is invalid")
        }
        let measured = bands.compactMap { band -> RecordedSleepInterval? in
            guard band.state == .asleep || band.state == .awake else { return nil }
            return .init(start: band.start, end: band.end, asleep: band.state == .asleep)
        }
        guard let coverage = SleepIntervalCoverage.calculate(start: start, end: end, intervals: measured) else {
            return result(.needsReview, "The requested span cannot be measured with finite elapsed time")
        }
        var clipped: [Band] = []
        var cursor = start
        for band in bands {
            let lower = max(start, band.start), upper = min(end, band.end)
            guard upper > lower else { continue }
            if lower > cursor { clipped.append(.init(start: cursor, end: lower, state: .unmeasured)) }
            clipped.append(.init(start: lower, end: upper, state: band.state)); cursor = upper
        }
        if cursor < end { clipped.append(.init(start: cursor, end: end, state: .unmeasured)) }
        let conflicts = clipped.filter { $0.state == .conflict }.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 60 }
        let state: DashboardMetricState = coverage.status == .available ? .available : coverage.status == .partial ? .partial : .unavailable
        return result(state, "Exact named span; conflicts are included in unmeasured; outside the checked window is unmeasured",
                      coverage: coverage, conflicts: conflicts, bands: clipped)
    }
}
