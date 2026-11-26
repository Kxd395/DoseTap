import Foundation

public enum WorkWakingStatus: String, Codable, Sendable { case work, off, unknown }

/// Explicit main-sleep/waking-period review. Links are stable shift identities, not calendar joins.
public struct WorkSleepEventContext: Codable, Equatable, Sendable {
    public var mainSleepStart: Date?, mainSleepEnd: Date?
    public var precedingStatus: WorkWakingStatus, followingStatus: WorkWakingStatus
    public var precedingShiftID: UUID?, followingShiftID: UUID?
    public var wakingPeriodsReviewed: Bool
    public var postBlockMainSleepIndex: Int?
    public var postBlockReferenceShiftID: UUID?
    public init(mainSleepStart: Date?, mainSleepEnd: Date?, precedingStatus: WorkWakingStatus,
                followingStatus: WorkWakingStatus, precedingShiftID: UUID? = nil, followingShiftID: UUID? = nil,
                wakingPeriodsReviewed: Bool) {
        self.mainSleepStart = mainSleepStart; self.mainSleepEnd = mainSleepEnd
        self.precedingStatus = precedingStatus; self.followingStatus = followingStatus
        self.precedingShiftID = precedingShiftID; self.followingShiftID = followingShiftID
        self.wakingPeriodsReviewed = wakingPeriodsReviewed
    }
    func isValid(recordedAt: Date) -> Bool {
        [mainSleepStart, mainSleepEnd].compactMap { $0 }.allSatisfy { $0.timeIntervalSince1970.isFinite && $0 <= recordedAt }
            && mainSleepStart.flatMap { start in mainSleepEnd.map { start < $0 } } != false
            && postBlockMainSleepIndex.map { (2...366).contains($0) } != false
            && (precedingShiftID == nil || precedingShiftID != followingShiftID)
    }
}

/// Construct once per classification batch; each sleep examines only its explicitly linked histories.
struct WorkShiftHistoryIndex {
    let entries: [UUID: [(offset: Int, event: WorkShiftEvent)]]
    init(_ events: [WorkShiftEvent]) {
        entries = Dictionary(grouping: events.enumerated().map { (offset: $0.offset, event: $0.element) }, by: { $0.event.shiftID })
    }
    func latest(_ id: UUID?, cutoff: Date, prefix: Int?) -> WorkShiftEvent? {
        guard let id else { return nil }
        return entries[id]?.filter { entry in entry.event.recordedAt <= cutoff && (prefix.map { entry.offset < $0 } ?? true) }
            .max { left, right in
                left.event.recordedAt == right.event.recordedAt ? left.offset < right.offset : left.event.recordedAt < right.event.recordedAt
            }?.event
    }
}

extension WorkContextDocument {
    func classifyEvent(_ association: WorkSleepAssociation, basis: WorkContextBasis, asOf: Date,
                       documentIsValid: Bool, shifts: WorkShiftHistoryIndex) -> WorkPhaseResult {
        let context = association.eventContext
        func result(_ phase: WorkPhase, _ detail: String, before: WorkShiftEvent? = nil,
                    after: WorkShiftEvent? = nil, postBlock: WorkShiftEvent? = nil, override: Bool = false) -> WorkPhaseResult {
            let reference = phase == .entering ? after : phase == .off ? postBlock : before
            return .init(classificationVersion: 2, phase: phase, basis: basis, rosterID: nil,
                blockID: override ? nil : reference?.blockID, firstShiftDate: override ? nil : reference?.firstShiftDate,
                precedingPosition: override ? nil : before?.position, followingPosition: override ? nil : after?.position,
                postBlockMainSleepIndex: override ? nil : phase == .after ? 1 : phase == .off ? context?.postBlockMainSleepIndex : nil,
                isOverride: override, detail: detail)
        }
        guard documentIsValid, asOf.timeIntervalSince1970.isFinite, association.isValid,
              association.recordedAt <= asOf, association.isMainSleep, let context, context.wakingPeriodsReviewed,
              let start = context.mainSleepStart, let end = context.mainSleepEnd, start < end, end <= asOf else {
            return result(.unknown, "Reviewed main-sleep boundaries and waking-period links are required.")
        }
        let snapshot = basis == .planned ? association.planSnapshotID.flatMap { id in planSnapshots?.first { $0.id == id } } : nil
        if basis == .planned && association.planSnapshotID != nil && snapshot.map({ $0.capturedAt <= start && $0.capturedAt <= association.recordedAt }) != true {
            return result(.unknown, "The referenced prospective plan is unavailable or was captured after sleep started.")
        }
        if let phase = association.overridePhase { return result(phase, association.overrideReason, override: true) }
        let cutoff = basis == .planned ? min(snapshot?.capturedAt ?? association.plannedAt, asOf) : asOf
        let prefix = snapshot.map { $0.shiftEventCount ?? 0 }
        let before = shifts.latest(context.precedingShiftID, cutoff: cutoff, prefix: prefix)
        let after = shifts.latest(context.followingShiftID, cutoff: cutoff, prefix: prefix)
        let zone = TimeZone(identifier: association.timeZoneIdentifier)!
        for event in [before, after].compactMap({ $0 }) where TimeZone(identifier: event.timeZoneIdentifier)?.identifier != zone.identifier {
            return result(.unknown, "Linked shift timezone differs from the reviewed sleep association.")
        }
        func capturedPlan(_ date: String) -> Bool? {
            let records = occurrences.prefix(snapshot?.occurrenceCount ?? occurrences.count).filter {
                $0.workDate == date && TimeZone(identifier: $0.timeZoneIdentifier)?.identifier == zone.identifier && $0.recordedAt <= cutoff && $0.plannedWorking != nil
            }
            if let record = records.max(by: { $0.recordedAt < $1.recordedAt }) { return record.plannedWorking }
            guard let day = Self.day(date, zone: zone.identifier), let roster = rosters.prefix(snapshot?.rosterCount ?? rosters.count).filter({
                $0.effectiveFrom <= date && date <= $0.effectiveTo && TimeZone(identifier: $0.timeZoneIdentifier)?.identifier == zone.identifier && $0.recordedAt <= cutoff
            }).max(by: { $0.recordedAt < $1.recordedAt }) else { return nil }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            return roster.weekdays.contains(calendar.component(.weekday, from: day))
        }
        func working(_ reported: WorkWakingStatus, linkedID: UUID?, event: WorkShiftEvent?, date: String) -> Bool? {
            if linkedID != nil {
                guard let event else { return nil }
                if basis == .confirmed {
                    guard event.attendanceConfirmed else { return nil }
                    return event.status == .worked ? true : event.status == .notWorked ? false : nil
                }
                if event.status == .scheduled { return true }
                if event.status == .worked { return event.scheduledStart != nil || event.scheduledEnd != nil ? true : nil }
                return event.status == .cancelled || event.status == .notWorked ? false : nil
            }
            if basis == .planned, snapshot != nil { return capturedPlan(date) }
            return reported == .off ? false : nil
        }
        guard let priorWork = working(context.precedingStatus, linkedID: context.precedingShiftID, event: before, date: association.precedingDate),
              let nextWork = working(context.followingStatus, linkedID: context.followingShiftID, event: after, date: association.followingDate) else {
            return result(.unknown, "Linked attendance or captured planning evidence is unresolved.")
        }
        let priorEnd = basis == .confirmed ? before?.actualEnd : before?.scheduledEnd
        let nextStart = basis == .confirmed ? after?.actualStart : after?.scheduledStart
        guard !priorWork || priorEnd.map({ $0 <= start }) != false,
              !nextWork || nextStart.map({ $0 >= end }) != false else {
            return result(.unknown, "Recorded shift times overlap the reviewed main-sleep association.")
        }
        if priorWork && nextWork {
            guard let block = before?.blockID, block == after?.blockID,
                  before?.firstShiftDate == after?.firstShiftDate,
                  before?.position.flatMap({ p in after?.position.map { $0 > p } }) != false else {
                return result(.unknown, "Between-shift sleep requires one explicitly reviewed work block.")
            }
            return result(.between, "Reviewed main-sleep links within one explicit work block.", before: before, after: after)
        }
        var priorBlock: WorkShiftEvent?
        if !priorWork && !nextWork, let referenceID = context.postBlockReferenceShiftID {
            guard let event = shifts.latest(referenceID, cutoff: cutoff, prefix: prefix),
                  event.blockID != nil, event.position != nil, event.position == event.blockShiftCount,
                  TimeZone(identifier: event.timeZoneIdentifier)?.identifier == zone.identifier,
                  basis == .planned ? (event.status == .scheduled || event.status == .worked) : (event.status == .worked && event.attendanceConfirmed),
                  (basis == .planned ? event.scheduledEnd : event.actualEnd).map({ $0 <= start }) == true else {
                return result(.unknown, "The selected previous block endpoint needs review.")
            }
            priorBlock = event
        }
        return result(priorWork ? .after : nextWork ? .entering : .off,
            "Reviewed main-sleep and adjacent waking-period evidence; no recovery inference.", before: priorWork ? before : nil, after: nextWork ? after : nil, postBlock: priorBlock)
    }
}
