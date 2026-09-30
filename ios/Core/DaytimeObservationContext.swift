import Foundation
import CryptoKit

/// Point-in-time work evidence. Temporal thirds describe clock position, never workload.
public struct DaytimeWorkContext: Equatable, Sendable {
    public enum Status: String, Sendable { case matched, reportedOffWork, unknown, ambiguous }
    public let definitionVersion = 1
    public let status: Status
    public let basis: WorkContextBasis
    public let documentRevision: UUID?
    public let candidates: [WorkShiftEvent]
    public let groupingKey: String
    public let label: String
    public let shiftThird: Int?
    public var shiftID: UUID? { status == .matched ? candidates.first?.shiftID : nil }
    public var shiftRevisionID: UUID? { status == .matched ? candidates.first?.id : nil }
    public var sourceRecordIDs: [String] {
        [documentRevision?.uuidString].compactMap { $0 } + candidates.flatMap { [$0.shiftID.uuidString, $0.id.uuidString] }
    }

    public init(at: Date, sourceRecordID: String, reportedSetting: DaytimeCheckIn.Setting?,
                work: WorkContextDocument?, basis: WorkContextBasis, asOf: Date) throws {
        guard at.timeIntervalSince1970.isFinite, asOf.timeIntervalSince1970.isFinite, at <= asOf,
              !sourceRecordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sourceRecordID.contains("\0"), sourceRecordID.utf8.count <= 4096,
              work?.isValid ?? true else { throw DaytimeDiaryError.invalid }
        self.basis = basis; documentRevision = work?.revision
        candidates = work?.shiftContexts(at: at, basis: basis, asOf: asOf) ?? []
        let prefix = basis == .planned ? "Planned" : "Confirmed"
        if candidates.count > 1 || (!candidates.isEmpty && reportedSetting == .offWork) {
            status = .ambiguous; shiftThird = nil
            label = "Work context needs review — overlapping or conflicting evidence"
            groupingKey = daytimeContextKey(["ambiguous", basis.rawValue, sourceRecordID])
        } else if let shift = candidates.first, let interval = shift.interval(basis: basis),
                  interval.duration.isFinite, interval.duration > 0,
                  let zone = TimeZone(identifier: shift.timeZoneIdentifier) {
            status = .matched
            let third = min(2, Int((at.timeIntervalSince(interval.start) / interval.duration) * 3))
            shiftThird = third
            let location = ["first", "middle", "final"][third]
            label = "\(prefix) · \(shift.positionLabel) · \(location) third of shift time"
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let fields = calendar.dateComponents([.hour, .minute, .second], from: interval.start)
            let clock = "\(fields.hour ?? 0):\(fields.minute ?? 0):\(fields.second ?? 0)"
            groupingKey = daytimeContextKey(["matched", basis.rawValue, shift.timeZoneIdentifier,
                shift.position.map(String.init) ?? "unknown:\(sourceRecordID)",
                shift.blockShiftCount.map(String.init) ?? "cardinality unknown", clock,
                String(interval.duration), String(third)])
        } else if reportedSetting == .offWork {
            status = .reportedOffWork; shiftThird = nil
            label = "Reported off work at this observation; daily attendance not established"
            groupingKey = daytimeContextKey(["reportedOffWork", basis.rawValue])
        } else {
            status = .unknown; shiftThird = nil
            label = "Work context unknown — kept separate"
            groupingKey = daytimeContextKey(["unknown", basis.rawValue, sourceRecordID])
        }
    }
}

/// Recomputed evidence projection. The source observation and its explicitly selected links stay immutable.
public struct DaytimeObservationContext: Equatable, Sendable {
    public let definitionVersion = 1
    public let observationID: UUID
    public let observationRevisionID: UUID
    public let assessedAt: Date
    public let asOf: Date
    public let work: DaytimeWorkContext
    public let medication: DashboardContextStratum
    public let groupingKey: String
    public var workStatus: DaytimeWorkContext.Status { work.status }
    public var shiftID: UUID? { work.shiftID }
    public var shiftRevisionID: UUID? { work.shiftRevisionID }
    public var shiftThird: Int? { work.shiftThird }
    public var workLabel: String { work.label }
    public var label: String { work.label + " · " + medication.label }
    public var sourceRecordIDs: [String] { Array(Set(work.sourceRecordIDs + medication.sourceRecordIDs)).sorted() }

    public init(observation: DaytimeCheckIn, work: WorkContextDocument?, basis: WorkContextBasis,
                medication: DashboardContextTimeline?, asOf: Date) throws {
        try observation.validate()
        guard observation.recordedAt <= asOf, medication.map({ $0.capturedAt == asOf }) ?? true else { throw DaytimeDiaryError.invalid }
        observationID = observation.id; observationRevisionID = observation.revisionID
        assessedAt = observation.assessedAt; self.asOf = asOf
        self.work = try DaytimeWorkContext(at: assessedAt, sourceRecordID: observation.revisionID.uuidString,
            reportedSetting: observation.setting, work: work, basis: basis, asOf: asOf)
        let content = try DashboardContentObservation(sourceRecordID: observation.revisionID.uuidString,
            instrumentID: observation.instrumentID, contentVersion: observation.contentVersion,
            language: observation.language, observedAt: assessedAt)
        self.medication = medication?.stratum(observationID: observation.id.uuidString, start: assessedAt, end: nil, content: [content])
            ?? .unknown(observationID: observation.id.uuidString)
        groupingKey = daytimeContextKey(["daytime_context_v1", self.work.groupingKey, self.medication.id])
    }
}

private func daytimeContextKey(_ fields: [String]) -> String {
    let value = fields.map { "\($0.utf8.count):\($0)" }.joined()
    return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}
