import Foundation

public enum WorkContextBasis: String, Codable, CaseIterable, Sendable { case planned, confirmed }
public enum WorkAttendance: String, Codable, CaseIterable, Sendable { case unknown, worked, notWorked }
public enum WorkPhase: String, Codable, CaseIterable, Sendable {
    case entering, between, after, off, unknown
    public var label: String {
        switch self {
        case .entering: return "Entering block"
        case .between: return "Between shifts"
        case .after: return "After block"
        case .off: return "Off-block"
        case .unknown: return "Unknown / review"
        }
    }
}

public struct WorkRoster: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var effectiveFrom: String
    public var effectiveTo: String
    public var timeZoneIdentifier: String
    public var weekdays: Set<Int>
    public var plannedShiftMinutes: Int?
    public var recordedAt: Date
    public init(effectiveFrom: String, effectiveTo: String, timeZoneIdentifier: String, weekdays: Set<Int>, plannedShiftMinutes: Int? = nil, recordedAt: Date) {
        self.effectiveFrom = effectiveFrom; self.effectiveTo = effectiveTo
        self.timeZoneIdentifier = timeZoneIdentifier; self.weekdays = weekdays
        self.plannedShiftMinutes = plannedShiftMinutes; self.recordedAt = recordedAt
    }
    public var isValid: Bool {
        WorkContextDocument.day(effectiveFrom, zone: timeZoneIdentifier) != nil && WorkContextDocument.day(effectiveTo, zone: timeZoneIdentifier) != nil
            && effectiveFrom <= effectiveTo && weekdays.allSatisfy { (1...7).contains($0) }
            && (plannedShiftMinutes.map { (1...1440).contains($0) } ?? true) && recordedAt.timeIntervalSince1970.isFinite
    }
}

public struct WorkOccurrence: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var workDate: String
    public var timeZoneIdentifier: String
    public var plannedWorking: Bool?
    public var attendance: WorkAttendance?
    public var scheduledStart: Date?, scheduledEnd: Date?, plannedBreakAt: Date?
    public var scheduledTimesReviewed: Bool?, breakReviewed: Bool?, actualTimesReviewed: Bool?
    public var actualStart: Date?
    public var actualEnd: Date?
    public var reason: String
    public var recordedAt: Date
    public init(workDate: String, timeZoneIdentifier: String, plannedWorking: Bool? = nil, attendance: WorkAttendance? = nil, reason: String = "", recordedAt: Date) {
        self.workDate = workDate; self.timeZoneIdentifier = timeZoneIdentifier
        self.plannedWorking = plannedWorking; self.attendance = attendance
        self.reason = reason; self.recordedAt = recordedAt
    }
    public var isValid: Bool {
        guard WorkContextDocument.day(workDate, zone: timeZoneIdentifier) != nil, reason.count <= 1000,
              recordedAt.timeIntervalSince1970.isFinite else { return false }
        guard [actualStart, actualEnd, scheduledStart, scheduledEnd, plannedBreakAt].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }) else { return false }
        guard [actualStart, actualEnd].compactMap({ $0 }).allSatisfy({ $0 <= recordedAt }) else { return false }
        if let scheduledStart, let scheduledEnd, scheduledEnd <= scheduledStart { return false }
        if let actualStart, let actualEnd, actualEnd <= actualStart { return false }
        return true
    }
}

public struct WorkSleepAssociation: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var sleepID: String
    public var precedingDate: String
    public var followingDate: String
    public var timeZoneIdentifier: String
    public var plannedAt: Date
    public var recordedAt: Date
    public var isMainSleep = true
    public var daytimeAssociationReviewed = true
    public var planSnapshotID: UUID?
    public var overridePhase: WorkPhase?
    public var overrideReason = ""
    public init(sleepID: String, precedingDate: String, followingDate: String, timeZoneIdentifier: String, plannedAt: Date, recordedAt: Date) {
        self.sleepID = sleepID; self.precedingDate = precedingDate; self.followingDate = followingDate
        self.timeZoneIdentifier = timeZoneIdentifier; self.plannedAt = plannedAt; self.recordedAt = recordedAt
    }
    public var isValid: Bool {
        !sleepID.isEmpty && sleepID.count <= 300 && WorkContextDocument.day(precedingDate, zone: timeZoneIdentifier) != nil
            && WorkContextDocument.day(followingDate, zone: timeZoneIdentifier) != nil
            && plannedAt.timeIntervalSince1970.isFinite && recordedAt.timeIntervalSince1970.isFinite && plannedAt <= recordedAt
            && overrideReason.count <= 1000 && (overridePhase == nil || !overrideReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

public struct WorkPhaseResult: Codable, Equatable, Sendable {
    public let classificationVersion: Int
    public let phase: WorkPhase
    public let basis: WorkContextBasis
    public let rosterID: UUID?
    public let blockID: String?
    public let firstShiftDate: String?
    public let precedingPosition: Int?
    public let followingPosition: Int?
    public let postBlockMainSleepIndex: Int?
    public let isOverride: Bool
    public let detail: String
}

public struct WorkPlanSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public let preSleepLogID: String
    public let sessionID: String?
    public let capturedAt: Date
    public let contextRevision: UUID
    public let rosterCount: Int
    public let occurrenceCount: Int
    public var shiftEventCount: Int?
    public var isValid: Bool {
        !preSleepLogID.isEmpty && preSleepLogID.count <= 300 && (sessionID.map { !$0.isEmpty && $0.count <= 300 } ?? true)
            && capturedAt.timeIntervalSince1970.isFinite && rosterCount >= 0 && occurrenceCount >= 0 && (shiftEventCount.map { $0 >= 0 } ?? true)
    }
}

public struct WorkContextDocument: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var revision = UUID()
    public var rosters: [WorkRoster] = []
    public var occurrences: [WorkOccurrence] = []
    public var associations: [WorkSleepAssociation] = []
    public var planSnapshots: [WorkPlanSnapshot]?
    public var shiftEvents: [WorkShiftEvent]?
    public init() {}
    public var isValid: Bool {
        (schemaVersion == 1 || schemaVersion == 2) && (((planSnapshots ?? []).isEmpty && (shiftEvents ?? []).isEmpty) || schemaVersion == 2)
            && (shiftEvents ?? []).count <= 50000 && (shiftEvents ?? []).allSatisfy(\.isValid) && Set((shiftEvents ?? []).map(\.id)).count == (shiftEvents ?? []).count
            && (planSnapshots ?? []).count <= 50000 && (planSnapshots ?? []).allSatisfy { $0.isValid && $0.rosterCount <= rosters.count && $0.occurrenceCount <= occurrences.count && ($0.shiftEventCount ?? 0) <= (shiftEvents ?? []).count }
            && Set((planSnapshots ?? []).map(\.id)).count == (planSnapshots ?? []).count
            && Set((planSnapshots ?? []).map(\.preSleepLogID)).count == (planSnapshots ?? []).count
            && rosters.count <= 2000 && occurrences.count <= 50000 && associations.count <= 50000
            && rosters.allSatisfy(\.isValid) && occurrences.allSatisfy(\.isValid) && associations.allSatisfy(\.isValid)
            && Set(rosters.map(\.id)).count == rosters.count && Set(occurrences.map(\.id)).count == occurrences.count
            && Set(associations.map(\.id)).count == associations.count
    }
    public mutating func capturePlan(preSleepLogID: String, sessionID: String?, at: Date) -> WorkPlanSnapshot? {
        guard isValid else { return nil }
        if let existing = planSnapshots?.first(where: { $0.preSleepLogID == preSleepLogID }) { return existing }
        guard (planSnapshots ?? []).count < 50000 else { return nil }
        var snapshot = WorkPlanSnapshot(preSleepLogID: preSleepLogID, sessionID: sessionID, capturedAt: at, contextRevision: revision, rosterCount: rosters.count, occurrenceCount: occurrences.count)
        snapshot.shiftEventCount = (shiftEvents ?? []).count
        guard snapshot.isValid else { return nil }
        planSnapshots = (planSnapshots ?? []) + [snapshot]; schemaVersion = 2; revision = UUID()
        return snapshot
    }
    public static func day(_ value: String, zone: String) -> Date? {
        guard let timezone = TimeZone(identifier: zone), value.count == 10 else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = timezone
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let result = formatter.date(from: value), formatter.string(from: result) == value else { return nil }
        return result
    }
    public func association(for sleepID: String, asOf: Date) -> WorkSleepAssociation? {
        associations.filter { $0.sleepID == sleepID && $0.recordedAt <= asOf }.max { $0.recordedAt < $1.recordedAt }
    }
    public func classify(_ association: WorkSleepAssociation, basis: WorkContextBasis, asOf: Date) -> WorkPhaseResult {
        classify(association, basis: basis, asOf: asOf, documentIsValid: isValid)
    }
    public func classificationsBySleepID(_ sleepIDs: Set<String>, basis: WorkContextBasis, asOf: Date) -> [String: WorkPhaseResult] {
        let indexed = associationsBySleepID(sleepIDs, asOf: asOf)
        let results = classifications(Array(indexed.values), basis: basis, asOf: asOf)
        return indexed.reduce(into: [:]) { $0[$1.key] = results[$1.value.id] }
    }
    public func associationsBySleepID(_ sleepIDs: Set<String>, asOf: Date) -> [String: WorkSleepAssociation] {
        var indexed: [String: WorkSleepAssociation] = [:]
        for association in associations where sleepIDs.contains(association.sleepID) && association.recordedAt <= asOf {
            if indexed[association.sleepID].map({ $0.recordedAt < association.recordedAt }) ?? true { indexed[association.sleepID] = association }
        }
        return indexed
    }
    public func classifications(_ inputs: [WorkSleepAssociation], basis: WorkContextBasis, asOf: Date) -> [UUID: WorkPhaseResult] {
        let valid = isValid
        return inputs.reduce(into: [:]) { output, association in
            output[association.id] = classify(association, basis: basis, asOf: asOf, documentIsValid: valid)
        }
    }
    private func classify(_ association: WorkSleepAssociation, basis: WorkContextBasis, asOf: Date, documentIsValid: Bool) -> WorkPhaseResult {
        func result(_ phase: WorkPhase, _ detail: String, roster: UUID? = nil, block: String? = nil, first: String? = nil, before: Int? = nil, after: Int? = nil, override: Bool = false) -> WorkPhaseResult {
            WorkPhaseResult(classificationVersion: 1, phase: phase, basis: basis, rosterID: roster, blockID: block, firstShiftDate: first, precedingPosition: before, followingPosition: after, postBlockMainSleepIndex: phase == .after && !override ? 1 : nil, isOverride: override, detail: detail)
        }
        guard documentIsValid, asOf.timeIntervalSince1970.isFinite, association.isValid, association.recordedAt <= asOf, association.isMainSleep,
              association.daytimeAssociationReviewed, let zone = TimeZone(identifier: association.timeZoneIdentifier),
              let previous = Self.day(association.precedingDate, zone: zone.identifier),
              let following = Self.day(association.followingDate, zone: zone.identifier) else {
            return result(.unknown, "A reviewed main-sleep and waking-period association is required.")
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard calendar.date(byAdding: .day, value: 1, to: previous) == following else {
            return result(.unknown, "Waking periods are not adjacent; review the sleep association.")
        }
        let snapshot = basis == .planned ? association.planSnapshotID.flatMap { id in planSnapshots?.first { $0.id == id } } : nil
        if basis == .planned && association.planSnapshotID != nil && (snapshot.map { $0.capturedAt <= association.recordedAt } != true) {
            return result(.unknown, "Referenced prospective plan snapshot is unavailable or later than this review.")
        }
        if let override = association.overridePhase { return result(override, association.overrideReason, override: true) }
        let cutoff = basis == .planned ? min(snapshot?.capturedAt ?? association.plannedAt, asOf) : asOf
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"
        func roster(_ date: String) -> WorkRoster? {
            rosters.prefix(snapshot?.rosterCount ?? rosters.count).filter { TimeZone(identifier: $0.timeZoneIdentifier)?.identifier == zone.identifier && $0.effectiveFrom <= date && $0.effectiveTo >= date && $0.recordedAt <= cutoff }.max { $0.recordedAt < $1.recordedAt }
        }
        func status(_ date: Date) -> Bool? {
            let key = formatter.string(from: date)
            let records = occurrences.prefix(snapshot?.occurrenceCount ?? occurrences.count).filter { $0.workDate == key && TimeZone(identifier: $0.timeZoneIdentifier)?.identifier == zone.identifier && $0.recordedAt <= cutoff }
            if basis == .confirmed {
                guard let record = records.filter({ $0.attendance != nil }).max(by: { $0.recordedAt < $1.recordedAt }) else { return nil }
                return record.attendance == .unknown ? nil : record.attendance == .worked
            }
            if let record = records.filter({ $0.plannedWorking != nil }).max(by: { $0.recordedAt < $1.recordedAt }) { return record.plannedWorking }
            return roster(key).map { $0.weekdays.contains(calendar.component(.weekday, from: date)) }
        }
        guard let before = status(previous), let after = status(following) else {
            return result(.unknown, basis == .planned ? "No effective reviewed roster or planned exception." : "Attendance is unanswered for an adjacent waking date.")
        }
        let phase: WorkPhase = before ? (after ? .between : .after) : (after ? .entering : .off)
        var reference = before ? previous : following
        if phase == .off {
            reference = previous
            var found = false
            for _ in 0..<366 {
                guard let prior = calendar.date(byAdding: .day, value: -1, to: reference), let worked = status(prior) else { break }
                reference = prior
                if worked { found = true; break }
            }
            guard found else { return result(.off, "Previous block and later main-sleep index are unresolved.") }
        }
        let referenceRoster = roster(formatter.string(from: reference))
        if before && after && roster(association.precedingDate)?.id != roster(association.followingDate)?.id {
            return result(.unknown, "Adjacent work dates cross roster revisions; review block membership.")
        }
        var first = reference
        var position = 1
        var knownBoundary = false
        for _ in 0..<366 {
            guard let prior = calendar.date(byAdding: .day, value: -1, to: first), let worked = status(prior) else { break }
            if !worked { knownBoundary = true; break }
            guard roster(formatter.string(from: prior))?.id == referenceRoster?.id else { break }
            first = prior; position += 1
        }
        let firstKey = knownBoundary ? formatter.string(from: first) : nil
        let block = firstKey.map { "\(basis.rawValue):\(zone.identifier):\(referenceRoster?.id.uuidString ?? "attendance"):\($0)" }
        return result(phase, knownBoundary ? (phase == .off ? "Previous block linked; later main-sleep index remains unresolved." : "Consecutive work dates; actual shift hours remain separate.") : "Phase known; block boundary unresolved.", roster: referenceRoster?.id, block: block, first: firstKey, before: before && knownBoundary ? position : nil, after: after && knownBoundary ? (before ? position + 1 : 1) : nil)
    }
}

public struct WorkDateResolution: Sendable {
    public let workDate: String, timeZoneIdentifier: String
    public let documentRevision: UUID
    public let plannedWorking: Bool?, attendance: WorkAttendance?
    public let plannedSourceID: UUID?, shiftSourceID: UUID?, breakSourceID: UUID?, actualSourceID: UUID?
    public let scheduledStart: Date?, scheduledEnd: Date?, plannedBreakAt: Date?, actualStart: Date?, actualEnd: Date?
}

public extension WorkContextDocument {
    func resolvedWorkDate(_ workDate: String, timeZoneIdentifier: String, asOf: Date) -> WorkDateResolution? {
        guard isValid, asOf.timeIntervalSince1970.isFinite, let day = Self.day(workDate, zone: timeZoneIdentifier), let zone = TimeZone(identifier: timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let records = occurrences.filter { $0.workDate == workDate && TimeZone(identifier: $0.timeZoneIdentifier)?.identifier == zone.identifier && $0.recordedAt <= asOf }.sorted { $0.recordedAt < $1.recordedAt }
        let roster = rosters.filter { TimeZone(identifier: $0.timeZoneIdentifier)?.identifier == zone.identifier && $0.effectiveFrom <= workDate && $0.effectiveTo >= workDate && $0.recordedAt <= asOf }.max { $0.recordedAt < $1.recordedAt }
        let plan = records.last { $0.plannedWorking != nil }
        let working = plan?.plannedWorking ?? roster.map { $0.weekdays.contains(calendar.component(.weekday, from: day)) }
        let shift = records.last { $0.scheduledTimesReviewed == true || $0.scheduledStart != nil || $0.scheduledEnd != nil }
        let pause = records.last { $0.breakReviewed == true || $0.plannedBreakAt != nil }
        let actual = records.last { $0.actualTimesReviewed == true || $0.actualStart != nil || $0.actualEnd != nil }
        return WorkDateResolution(workDate: workDate, timeZoneIdentifier: timeZoneIdentifier, documentRevision: revision, plannedWorking: working, attendance: records.last { $0.attendance != nil }?.attendance, plannedSourceID: plan?.id ?? roster?.id, shiftSourceID: shift?.id, breakSourceID: pause?.id, actualSourceID: actual?.id, scheduledStart: working == true ? shift?.scheduledStart : nil, scheduledEnd: working == true ? shift?.scheduledEnd : nil, plannedBreakAt: working == true ? pause?.plannedBreakAt : nil, actualStart: actual?.actualStart, actualEnd: actual?.actualEnd)
    }
}
