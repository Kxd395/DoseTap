import Foundation

/// Point-in-time consumer snapshot, not a validity certificate or a raw provider export.
/// The caller must assess current local records and invalidate this after relevant changes.
public struct ReviewedNightSleepProjection: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case available, partial, unavailable, conflict }
    public struct Band: Codable, Equatable, Sendable {
        public enum State: String, Codable, Sendable { case asleep, awake, unmeasured, conflict }
        public let start: Date
        public let end: Date
        public let state: State
    }

    public let derivationVersion: String
    public let evidenceDerivationVersion: String
    public let generatedAt: Date
    public let window: ReviewedSleepWindow
    public let coverage: SleepIntervalCoverage
    /// Conflicting minutes are already included in coverage.unmeasuredMinutes.
    public let conflictMinutes: Double
    public let status: Status
    public let bands: [Band]

    /// Does not infer session bounds, final awakening, onset latency or awakening counts.
    /// Coalescing adjacent states removes provider/stage boundaries, not unmeasured gaps.
    public static func calculate(window: ReviewedSleepWindow, evidence: SleepEvidenceResolution,
                                 generatedAt: Date) -> Self? {
        guard generatedAt.timeIntervalSinceReferenceDate.isFinite,
              window.validationError(now: generatedAt) == nil,
              evidence.coverage.start == window.start, evidence.coverage.end == window.end,
              evidence.rejectedSampleCount == 0 else { return nil }
        var bands: [Band] = []
        for slice in evidence.slices {
            let state: Band.State
            switch slice.state {
            case .asleep: state = .asleep
            case .awake: state = .awake
            case .unmeasured: state = .unmeasured
            case .conflict: state = .conflict
            }
            if let last = bands.last, last.end == slice.start, last.state == state {
                bands[bands.count - 1] = .init(start: last.start, end: slice.end, state: state)
            } else {
                bands.append(.init(start: slice.start, end: slice.end, state: state))
            }
        }
        let status: Status
        switch evidence.status {
        case .available: status = .available
        case .partial: status = .partial
        case .unavailable: status = .unavailable
        case .conflict: status = .conflict
        }
        return .init(derivationVersion: "reviewed_night_projection_v1",
                     evidenceDerivationVersion: evidence.derivationVersion,
                     generatedAt: generatedAt, window: window, coverage: evidence.coverage,
                     conflictMinutes: evidence.conflictMinutes, status: status, bands: bands)
    }
}
