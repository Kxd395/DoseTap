import Foundation

/// Point-in-time read-only estimates. The repository must invalidate these with their source projection.
public struct ReviewedDoseSleepMetrics: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case available, missing, conflict }
    public enum Reason: String, Codable, Sendable {
        case missingDose, invalidDoseRecords, invalidProjection, alreadyAsleep, boundaryGap
        case conflictingEvidence, missingInitialOnset, missingAwakening, missingReturn
    }
    public enum Source: String, Codable, Sendable { case recordedDose, appleHealthConsensus }
    public struct Metric: Codable, Equatable, Sendable {
        public let status: Status
        public let reason: Reason?
        public let start: Date?
        public let end: Date?
        public let startSource: Source?
        public let endSource: Source?
        public var seconds: Double? {
            guard status == .available, let start, let end else { return nil }
            return end.timeIntervalSince(start)
        }
        fileprivate static func missing(_ reason: Reason) -> Self {
            let conflict = [Reason.invalidDoseRecords, .invalidProjection, .alreadyAsleep, .conflictingEvidence].contains(reason)
            return .init(status: conflict ? .conflict : .missing, reason: reason, start: nil, end: nil,
                         startSource: nil, endSource: nil)
        }
        fileprivate static func value(_ start: Date, _ end: Date, _ from: Source, _ to: Source) -> Self {
            .init(status: .available, reason: nil, start: start, end: end, startSource: from, endSource: to)
        }
    }
    public let derivationVersion: String
    public let projectionVersion: String
    public let evidenceVersion: String
    public let generatedAt: Date
    public let sessionID: String
    public let dose1ToSleep: Metric
    public let awakeningToDose2: Metric
    public let dose2ToSleep: Metric
    public let dose2Awakening: Metric

    public static func calculate(projection: ReviewedNightSleepProjection, doses: [StoredDoseEvent]) -> Self {
        func result(_ initial: Metric, _ pre: Metric, _ post: Metric, _ whole: Metric) -> Self {
            .init(derivationVersion: "reviewed_dose_sleep_v1", projectionVersion: projection.derivationVersion,
                  evidenceVersion: projection.evidenceDerivationVersion, generatedAt: projection.generatedAt,
                  sessionID: projection.window.sessionID, dose1ToSleep: initial, awakeningToDose2: pre,
                  dose2ToSleep: post, dose2Awakening: whole)
        }
        func rejected(_ reason: Reason) -> Self {
            result(.missing(reason), .missing(reason), .missing(reason), .missing(reason))
        }
        let bands = projection.bands
        guard !bands.isEmpty, bands.first?.start == projection.window.start, bands.last?.end == projection.window.end,
              bands.allSatisfy({ $0.start.timeIntervalSinceReferenceDate.isFinite &&
                  $0.end.timeIntervalSinceReferenceDate.isFinite && $0.start < $0.end }),
              zip(bands, bands.dropFirst()).allSatisfy({ $0.end == $1.start && $0.state != $1.state })
        else { return rejected(.invalidProjection) }
        let assessment = ReviewedWindowAssessment.calculate(window: projection.window, sessionID: projection.window.sessionID,
            doses: doses, otherWindows: [], naps: [], now: projection.generatedAt)
        guard assessment.status == .checked,
              !doses.contains(where: { $0.sessionId.map { $0 != projection.window.sessionID } ?? false })
        else { return rejected(.invalidDoseRecords) }
        func obstacle(_ index: Int?, fallback: Reason) -> Reason {
            guard let index, bands.indices.contains(index) else { return fallback }
            switch bands[index].state {
            case .conflict: return .conflictingEvidence
            case .unmeasured: return .boundaryGap
            default: return fallback
            }
        }
        func initial(_ dose: StoredDoseEvent?) -> Metric {
            guard let dose else { return .missing(.missingDose) }
            guard let first = bands.firstIndex(where: { $0.state == .asleep }) else {
                if bands.contains(where: { $0.state == .conflict }) { return .missing(.conflictingEvidence) }
                if bands.contains(where: { $0.state == .unmeasured }) { return .missing(.boundaryGap) }
                return .missing(.missingInitialOnset)
            }
            guard bands[first].start >= dose.timestamp else { return .missing(.alreadyAsleep) }
            guard first > 0 else { return .missing(.missingInitialOnset) }
            let prefix = bands[..<first]
            if prefix.contains(where: { $0.state == .conflict }) { return .missing(.conflictingEvidence) }
            if prefix.contains(where: { $0.state == .unmeasured }) { return .missing(.boundaryGap) }
            return .value(dose.timestamp, bands[first].start, .recordedDose, .appleHealthConsensus)
        }
        let first = initial(doses.first(where: { $0.eventType == "dose1" }))
        guard let dose = doses.first(where: { $0.eventType == "dose2" }) else {
            return result(first, .missing(.missingDose), .missing(.missingDose), .missing(.missingDose))
        }
        // Include an exact return endpoint only for an observed immediately preceding awake episode.
        let index = bands.indices.first { index in
            let band = bands[index]
            let exactReturn = band.end == dose.timestamp && index + 1 < bands.count && bands[index + 1].state == .asleep
            return band.state == .awake && band.start <= dose.timestamp && (band.end > dose.timestamp || exactReturn)
        }
        guard let index else {
            let containing = bands.firstIndex { $0.start <= dose.timestamp && dose.timestamp < $0.end }
            let reason = obstacle(containing, fallback: .alreadyAsleep)
            return result(first, .missing(reason), .missing(reason), .missing(reason))
        }
        guard index > 0, bands[index - 1].state == .asleep else {
            let reason = obstacle(index - 1, fallback: .missingAwakening)
            return result(first, .missing(reason), .missing(reason), .missing(reason))
        }
        let wake = bands[index].start
        let pre = Metric.value(wake, dose.timestamp, .appleHealthConsensus, .recordedDose)
        guard index + 1 < bands.count, bands[index + 1].state == .asleep else {
            let reason = obstacle(index + 1, fallback: .missingReturn)
            return result(first, pre, .missing(reason), .missing(reason))
        }
        let returned = bands[index].end
        return result(first, pre, .value(dose.timestamp, returned, .recordedDose, .appleHealthConsensus),
                      .value(wake, returned, .appleHealthConsensus, .appleHealthConsensus))
    }
}
