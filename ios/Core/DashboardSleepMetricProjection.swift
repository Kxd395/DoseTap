import Foundation

/// Shared screen/report policy; arithmetic remains in PostDoseSleepEstimate/SleepIntervalCoverage.
public struct DashboardSleepMetricProjection: Codable, Equatable, Sendable {
    public static let version = "dashboard-sleep-metric.v1"
    public enum Source: String, Codable, Sendable { case appleHealth = "apple-health", whoop }
    public enum Definition: String, Codable, Sendable { case mainProviderEpisode, observedAfterDose2 }
    public enum BoundaryBasis: String, Codable, Sendable { case providerMainEpisode, reportedFinalAwakening, providerLastObservedSleepEnd, unresolved }
    public enum Freshness: String, Codable, Sendable { case current, stale, unavailable }
    public let derivationVersion: String
    public let metric: DashboardMetricValue
    public let source: Source
    public let definition: Definition
    public let boundaryBasis: BoundaryBasis
    public let freshness: Freshness
    public let coveredMinutes: Double?
    public let intervalMinutes: Double?
    public let unmeasuredMinutes: Double?
    private init(value: Double?, state: DashboardMetricState, reason: String, source: Source,
                 definition: Definition, freshness: Freshness, covered: Double? = nil, interval: Double? = nil,
                 boundaryBasis: BoundaryBasis = .providerMainEpisode) {
        derivationVersion = Self.version
        metric = .init(value: value, state: state, reason: reason, unit: "minutes")
        self.source = source; self.definition = definition; self.freshness = freshness
        self.boundaryBasis = boundaryBasis
        coveredMinutes = covered; intervalMinutes = interval
        unmeasuredMinutes = covered.flatMap { value in interval.map { max(0, $0 - value) } }
    }
    public func summaryValue(includePartial: Bool = false) -> Double? {
        metric.state == .available || (includePartial && metric.state == .partial) ? metric.value : nil
    }
    /// Provider-defined main episode total. It does not assert complete reviewed-night coverage.
    public static func providerEpisode(totalMinutes: Double?, source: Source, freshness: Freshness) -> Self {
        guard freshness != .unavailable, let value = totalMinutes else {
            return .init(value: nil, state: .unavailable, reason: "provider_main_episode_unavailable", source: source,
                         definition: .mainProviderEpisode, freshness: freshness)
        }
        guard value.isFinite, value >= 0 else {
            return .init(value: nil, state: .needsReview, reason: "invalid_provider_total", source: source,
                         definition: .mainProviderEpisode, freshness: freshness)
        }
        return .init(value: value, state: freshness == .stale ? .partial : .available,
                     reason: freshness == .stale ? "retained_stale_provider_total" : "provider_main_episode_total",
                     source: source, definition: .mainProviderEpisode, freshness: freshness)
    }
    public static func afterDose2(pattern: DashboardDosePattern, estimate: PostDoseSleepEstimate?,
                                 source: Source, freshness: Freshness, boundaryBasis: BoundaryBasis = .unresolved,
                                 dose2At: Date? = nil, endpointAt: Date? = nil) -> Self {
        func result(_ value: Double?, _ state: DashboardMetricState, _ reason: String,
                    _ estimate: PostDoseSleepEstimate? = nil) -> Self {
            .init(value: value, state: state, reason: reason, source: source, definition: .observedAfterDose2,
                  freshness: freshness, covered: estimate?.coveredMinutes, interval: estimate?.intervalMinutes,
                  boundaryBasis: boundaryBasis)
        }
        guard pattern.postDose2State == .available else {
            return result(nil, pattern.postDose2State, pattern.postDose2State == .notApplicable ? "no_second_administration"
                : pattern.postDose2State == .needsReview ? "post_dose_evidence_needs_review" : "second_administration_time_unresolved")
        }
        guard source == .appleHealth else { return result(nil, .unavailable, "whoop_post_dose_intervals_unavailable") }
        if let start = dose2At, let end = endpointAt,
           !start.timeIntervalSince1970.isFinite || !end.timeIntervalSince1970.isFinite || end <= start {
            return result(nil, .needsReview, "invalid_post_dose_endpoint_window")
        }
        guard freshness != .unavailable else { return result(nil, .unavailable, "provider_observations_unavailable") }
        guard let estimate else { return result(nil, .unavailable, "post_dose_observations_unavailable") }
        guard estimate.asleepMinutes.isFinite, estimate.coveredMinutes.isFinite, estimate.intervalMinutes.isFinite,
              estimate.asleepMinutes >= 0, estimate.coveredMinutes > 0, estimate.asleepMinutes <= estimate.coveredMinutes,
              estimate.coveredMinutes <= estimate.intervalMinutes else { return result(nil, .needsReview, "invalid_measured_coverage") }
        let partial = estimate.coveredMinutes < estimate.intervalMinutes
        return result(estimate.asleepMinutes, partial || freshness == .stale ? .partial : .available,
                      partial ? "observed_sleep_with_unmeasured_time" : freshness == .stale ? "retained_stale_post_dose_sleep" : "observed_post_dose_sleep", estimate)
    }
    /// Accept an already resolved/clipped reviewed coverage value without deriving sleep again.
    public static func afterDose2(pattern: DashboardDosePattern, coverage: SleepIntervalCoverage?,
                                 source: Source, freshness: Freshness, boundaryBasis: BoundaryBasis = .unresolved) -> Self {
        let estimate = coverage.flatMap { value -> PostDoseSleepEstimate? in
            guard let asleep = value.asleepMinutes else { return nil }
            return .init(asleepMinutes: asleep, coveredMinutes: value.coveredMinutes, intervalMinutes: value.intervalMinutes)
        }
        return afterDose2(pattern: pattern, estimate: estimate, source: source, freshness: freshness,
                          boundaryBasis: boundaryBasis, dose2At: coverage?.start, endpointAt: coverage?.end)
    }
}
