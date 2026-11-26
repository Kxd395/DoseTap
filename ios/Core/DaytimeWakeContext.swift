import Foundation

public struct DaytimeWakeReference: Equatable, Hashable, Sendable {
    public let sourceID: String
    public let revision: String
    public let at: Date
    public init(sourceID: String, revision: String, at: Date) throws {
        guard !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, sourceID.count <= 300, !sourceID.contains("\0"),
              revision.count == 64, revision.allSatisfy({ "0123456789abcdef".contains($0) }), at.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.invalid }
        self.sourceID = sourceID; self.revision = revision; self.at = at
    }
}
public struct DaytimeWakeEvidence: Equatable, Sendable {
    public let reference: DaytimeWakeReference
    public let recordedAt: Date
    public init(reference: DaytimeWakeReference, recordedAt: Date) throws {
        guard recordedAt.timeIntervalSince1970.isFinite, reference.at <= recordedAt else { throw DaytimeDiaryError.invalid }
        self.reference = reference; self.recordedAt = recordedAt
    }
}

/// Descriptive elapsed-hour bands, never physiological labels or validated clinical thresholds.
public struct DaytimeWakeContext: Equatable, Sendable {
    public enum Status: String, Sendable { case current, revised, notLinked, unavailable, ambiguous, afterAssessment }
    public let definitionVersion = 1
    public let observationID: UUID
    public let observationRevisionID: UUID
    public let assessedAt: Date
    public let asOf: Date
    public let originalReferences: [DaytimeWakeReference]
    public let currentSource: DaytimeWakeEvidence?
    public let status: Status
    public let elapsedSeconds: TimeInterval?
    public let elapsedHourBand: Int?
    public var groupingKey: String {
        if let elapsedHourBand { return "wake_hours_v1:\(elapsedHourBand)" }
        return "wake_hours_v1:\(status.rawValue):\(observationID.uuidString)"
    }
    public var sourceRecordIDs: [String] {
        Array(Set(originalReferences.flatMap { [$0.sourceID, $0.revision] } + (currentSource.map { [$0.reference.sourceID, $0.reference.revision] } ?? []))).sorted()
    }
    public var label: String {
        if let elapsedSeconds, let elapsedHourBand {
            let change = status == .revised ? "; corrected source" : ""
            return "\(String(format: "%.2f", elapsedSeconds / 3600)) hours after reported main wake · \(elapsedHourBand)–<\(elapsedHourBand + 1) hour band (v1)\(change)"
        }
        switch status {
        case .notLinked: return "Main wake not linked; elapsed time unknown"
        case .ambiguous: return "Main-wake references conflict; elapsed time unknown"
        case .afterAssessment: return "Current main wake is after this assessment; elapsed time unavailable"
        default: return "Exact main-wake source unavailable; elapsed time unknown"
        }
    }
    public init(observation: DaytimeCheckIn, references: [DaytimeWakeReference]?, sources: [DaytimeWakeEvidence]?, asOf: Date) throws {
        try observation.validate()
        guard asOf.timeIntervalSince1970.isFinite, observation.recordedAt <= asOf,
              references.map({ $0.count <= 33 && $0.allSatisfy { $0.at <= asOf } }) ?? true,
              sources.map({ Set($0.map { $0.reference.sourceID }).count == $0.count && $0.allSatisfy { $0.recordedAt <= asOf } }) ?? true else { throw DaytimeDiaryError.invalid }
        observationID = observation.id; observationRevisionID = observation.revisionID
        assessedAt = observation.assessedAt; self.asOf = asOf
        originalReferences = Array(Set(references ?? [])).sorted {
            if $0.sourceID != $1.sourceID { return $0.sourceID < $1.sourceID }
            return $0.revision == $1.revision ? $0.at < $1.at : $0.revision < $1.revision
        }
        let identities = Set(originalReferences.map { "\($0.sourceID.utf8.count):\($0.sourceID)|\($0.revision)" })
        var state: Status = .unavailable, source: DaytimeWakeEvidence?, elapsed: TimeInterval?, band: Int?
        if references != nil && originalReferences.isEmpty { state = .notLinked }
        else if identities.count > 1 { state = .ambiguous }
        else if let original = originalReferences.first, let match = sources?.first(where: { $0.reference.sourceID == original.sourceID }) {
            source = match
            if match.reference.at > assessedAt { state = .afterAssessment }
            else {
                let seconds = assessedAt.timeIntervalSince(match.reference.at), hours = floor(seconds / 3600)
                guard seconds.isFinite, hours >= 0, hours < Double(Int.max - 1) else { throw DaytimeDiaryError.invalid }
                elapsed = seconds; band = Int(hours)
                state = original.revision == match.reference.revision ? .current : .revised
            }
        }
        status = state; currentSource = source; elapsedSeconds = elapsed; elapsedHourBand = band
    }
}
