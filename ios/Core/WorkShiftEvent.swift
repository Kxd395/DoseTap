import Foundation

public enum WorkShiftStatus: String, Codable, Sendable { case scheduled, worked, cancelled, notWorked, uncertain }
public enum WorkShiftSource: String, Codable, Sendable { case userEntered, calendarImported, templateDerived, other }
public enum WorkActualTimePrecision: String, Codable, Sendable { case reportedMinute, approximate, unknown }

public struct WorkShiftEvent: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var shiftID = UUID()
    public var timeZoneIdentifier: String
    public var status = WorkShiftStatus.scheduled
    public var source = WorkShiftSource.userEntered
    public var attendanceConfirmed = false
    public var actualTimePrecision = WorkActualTimePrecision.unknown
    public var scheduledStart: Date?, scheduledEnd: Date?, actualStart: Date?, actualEnd: Date?
    public var workDate: String?
    public var blockID: String?, firstShiftDate: String?
    public var position: Int?, blockShiftCount: Int?
    public var recordedAt: Date
    public init(timeZoneIdentifier: String, recordedAt: Date) {
        self.timeZoneIdentifier = timeZoneIdentifier; self.recordedAt = recordedAt
    }
    public var isValid: Bool {
        guard TimeZone(identifier: timeZoneIdentifier) != nil, recordedAt.timeIntervalSince1970.isFinite,
              [scheduledStart, scheduledEnd, actualStart, actualEnd].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              [actualStart, actualEnd].compactMap({ $0 }).allSatisfy({ $0 <= recordedAt }),
              position.map({ (1...366).contains($0) }) ?? true, blockShiftCount.map({ (1...366).contains($0) }) ?? true,
              blockID.map({ !$0.isEmpty && $0.count <= 300 }) ?? true,
              workDate.map({ WorkContextDocument.day($0, zone: timeZoneIdentifier) != nil }) ?? true,
              firstShiftDate.map({ WorkContextDocument.day($0, zone: timeZoneIdentifier) != nil }) ?? true else { return false }
        if let scheduledStart, let scheduledEnd, scheduledEnd <= scheduledStart { return false }
        if let actualStart, let actualEnd, actualEnd <= actualStart { return false }
        if let position, let blockShiftCount, position > blockShiftCount { return false }
        return (status != .worked && status != .notWorked) || attendanceConfirmed
    }
    public var positionLabel: String {
        guard let position else { return "Position unknown" }
        return blockShiftCount.map { "Shift \(position) of \($0)" } ?? "Shift \(position)"
    }
    public var actualMinutes: Double? { interval(basis: .confirmed).map { $0.duration / 60 } }
    public func interval(basis: WorkContextBasis) -> DateInterval? {
        guard isValid else { return nil }
        if basis == .planned {
            guard status == .scheduled || status == .worked, let scheduledStart, let scheduledEnd else { return nil }
            return DateInterval(start: scheduledStart, end: scheduledEnd)
        }
        guard status == .worked, attendanceConfirmed, actualTimePrecision == .reportedMinute, let actualStart, let actualEnd else { return nil }
        return DateInterval(start: actualStart, end: actualEnd)
    }
}

public extension WorkContextDocument {
    func latestShiftEvents(asOf: Date, snapshotID: UUID? = nil) -> [WorkShiftEvent] {
        guard isValid, asOf.timeIntervalSince1970.isFinite else { return [] }
        let snapshot = snapshotID.flatMap { id in planSnapshots?.first { $0.id == id } }
        guard snapshotID == nil || snapshot != nil else { return [] }
        let cutoff = min(asOf, snapshot?.capturedAt ?? asOf)
        var latest: [UUID: WorkShiftEvent] = [:]
        for event in (shiftEvents ?? []).prefix(snapshot.map { $0.shiftEventCount ?? 0 } ?? (shiftEvents ?? []).count) where event.recordedAt <= cutoff {
            if latest[event.shiftID].map({ $0.recordedAt <= event.recordedAt }) ?? true { latest[event.shiftID] = event }
        }
        return latest.values.sorted { $0.shiftID.uuidString < $1.shiftID.uuidString }
    }
    func shiftContexts(at: Date, basis: WorkContextBasis, asOf: Date) -> [WorkShiftEvent] {
        guard at.timeIntervalSince1970.isFinite else { return [] }
        return latestShiftEvents(asOf: asOf).filter { event in
            guard let interval = event.interval(basis: basis) else { return false }
            return at >= interval.start && at < interval.end
        }
    }
}
