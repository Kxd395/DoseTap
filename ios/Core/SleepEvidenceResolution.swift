import Foundation

/// Unclipped provider observation. Optional origin fields remain missing when not supplied.
public struct SleepEvidenceSample: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Hashable, Sendable {
        case asleep, core, deep, rem, awake, inBed, unknown
    }
    public struct Origin: Codable, Equatable, Sendable {
        public var sourceName: String
        public var bundleIdentifier: String?
        public var sourceVersion: String?
        public var productType: String?
        public var operatingSystemVersion: String?
        public var deviceName: String?
        public var deviceManufacturer: String?
        public var deviceModel: String?
        public var deviceHardwareVersion: String?
        public var deviceFirmwareVersion: String?
        public var deviceSoftwareVersion: String?
        public var timeZoneID: String?
        public var receivedAt: Date?

        public init(sourceName: String, bundleIdentifier: String?) {
            self.sourceName = sourceName; self.bundleIdentifier = bundleIdentifier
        }
    }
    public let sampleID: String?
    public let start: Date
    public let end: Date
    public let rawCategory: Int
    public let stage: Stage
    public let origin: Origin

    public init(sampleID: String?, start: Date, end: Date, rawCategory: Int, stage: Stage, origin: Origin) {
        self.sampleID = sampleID; self.start = start; self.end = end
        self.rawCategory = rawCategory; self.stage = stage; self.origin = origin
    }
}

/// Conservative consensus, not a ranking of source accuracy or a persisted import ledger.
public struct SleepEvidenceResolution: Equatable, Sendable {
    public enum Status: String, Sendable { case available, partial, unavailable, conflict }
    public struct Slice: Equatable, Sendable {
        public enum State: String, Sendable { case asleep, awake, unmeasured, conflict }
        public let start: Date
        public let end: Date
        public let state: State
        public let sampleIDs: [String]
    }
    public let derivationVersion: String
    public let samples: [SleepEvidenceSample]
    public let slices: [Slice]
    public let coverage: SleepIntervalCoverage
    public let conflictMinutes: Double
    public let rejectedSampleCount: Int
    public var status: Status {
        if conflictMinutes > 0 { return .conflict }
        switch coverage.status {
        case .available: return .available
        case .partial: return .partial
        case .unavailable: return .unavailable
        }
    }

    public static func calculate(start: Date, end: Date, samples: [SleepEvidenceSample]) -> Self? {
        guard SleepIntervalCoverage.calculate(start: start, end: end, intervals: []) != nil else { return nil }
        let valid = samples.filter {
            $0.start.timeIntervalSinceReferenceDate.isFinite && $0.end.timeIntervalSinceReferenceDate.isFinite &&
            $0.end.timeIntervalSince($0.start).isFinite && $0.start < $0.end
        }
        let overlapping = valid.filter { $0.start < end && $0.end > start }
        let boundaries = Set([start, end] + overlapping.flatMap { [max(start, $0.start), min(end, $0.end)] }).sorted()
        var slices: [Slice] = [], measured: [RecordedSleepInterval] = []
        var conflictSeconds = 0.0
        for (lower, upper) in zip(boundaries, boundaries.dropFirst()) {
            let active = overlapping.filter { $0.start < upper && $0.end > lower }
            let stages = Set(active.map(\.stage)).subtracting([.inBed])
            let detailed = stages.intersection([.core, .deep, .rem])
            let hasSleep = stages.contains(.asleep) || !detailed.isEmpty
            let hasAwake = stages.contains(.awake)
            let conflict = detailed.count > 1 || (hasSleep && hasAwake) ||
                (stages.contains(.unknown) && (hasSleep || hasAwake))
            let state: Slice.State = conflict ? .conflict : (hasAwake ? .awake : (hasSleep ? .asleep : .unmeasured))
            slices.append(.init(start: lower, end: upper, state: state,
                                sampleIDs: Set(active.compactMap(\.sampleID)).sorted()))
            if conflict { conflictSeconds += upper.timeIntervalSince(lower) }
            if state == .asleep || state == .awake {
                measured.append(.init(start: lower, end: upper, asleep: state == .asleep))
            }
        }
        guard let coverage = SleepIntervalCoverage.calculate(start: start, end: end, intervals: measured) else { return nil }
        return .init(derivationVersion: "sleep_evidence_consensus_v1", samples: samples, slices: slices,
                     coverage: coverage, conflictMinutes: conflictSeconds / 60,
                     rejectedSampleCount: samples.count - valid.count)
    }
}
