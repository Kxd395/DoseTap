import Foundation

/// Recorded actual intervals only. These values do not establish attendance on unrecorded days.
public struct WorkShiftTimingEvidence: Sendable {
    public let shiftEndToMainSleep: WorkCycleMetricEvidence
    public let betweenShifts: WorkCycleMetricEvidence
    public let recordedWorkMinutes: WorkCycleMetricEvidence
    public let sourceRevisionIDs: [UUID]
}

public extension WorkContextDocument {
    func timingEvidence(for association: WorkSleepAssociation, lookbackStart: Date, lookbackEnd: Date,
                        asOf: Date) -> WorkShiftTimingEvidence {
        .project(association: association, events: latestShiftEvents(asOf: asOf), documentIsValid: isValid,
                 lookbackStart: lookbackStart, lookbackEnd: lookbackEnd, asOf: asOf)
    }
    func timingEvidences(for associations: [WorkSleepAssociation], lookbackSeconds: TimeInterval,
                         asOf: Date) -> [UUID: WorkShiftTimingEvidence] {
        let valid = isValid, events = latestShiftEvents(asOf: asOf)
        return associations.reduce(into: [:]) { result, association in
            let end = association.eventContext?.mainSleepStart ?? asOf
            result[association.id] = .project(association: association, events: events,
                documentIsValid: valid && lookbackSeconds.isFinite && lookbackSeconds > 0,
                lookbackStart: end.addingTimeInterval(-lookbackSeconds), lookbackEnd: end, asOf: asOf)
        }
    }
}

private extension WorkShiftTimingEvidence {
    static func project(association: WorkSleepAssociation, events: [WorkShiftEvent], documentIsValid: Bool,
                        lookbackStart: Date, lookbackEnd: Date, asOf: Date) -> Self {
        func evidence(_ id: String, value: Double? = nil, start: Date? = nil, end: Date? = nil,
                      state: DashboardMetricState = .unavailable, reason: String) -> WorkCycleMetricEvidence {
            .init(metricID: id, source: "reviewed_actual_shift_events", definitionVersion: "actual_shift_intervals_v1",
                  metric: .init(value: value, state: state, reason: reason, unit: "minutes"), start: start, end: end)
        }
        func unavailable(_ reason: String, state: DashboardMetricState = .unavailable) -> WorkShiftTimingEvidence {
            .init(shiftEndToMainSleep: evidence("actual_shift_end_to_main_sleep", state: state, reason: reason),
                  betweenShifts: evidence("actual_time_between_shifts", state: state, reason: reason),
                  recordedWorkMinutes: evidence("recorded_actual_work_minutes", state: state, reason: reason), sourceRevisionIDs: [])
        }
        guard documentIsValid, association.isValid, association.isMainSleep, association.recordedAt <= asOf,
              [asOf, lookbackStart, lookbackEnd].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              lookbackStart < lookbackEnd, lookbackEnd <= asOf else { return unavailable("invalid_actual_context", state: .needsReview) }
        guard let context = association.eventContext, context.wakingPeriodsReviewed else { return unavailable("reviewed_main_sleep_links_unavailable") }
        let before = events.first { $0.shiftID == context.precedingShiftID }, after = events.first { $0.shiftID == context.followingShiftID }
        guard [before, after].compactMap({ $0 }).allSatisfy({ TimeZone(identifier: $0.timeZoneIdentifier)?.identifier == TimeZone(identifier: association.timeZoneIdentifier)?.identifier }) else {
            return unavailable("linked_shift_timezone_conflict", state: .needsReview)
        }
        let start = context.mainSleepStart
        func gap(_ id: String, start: Date?, end: Date?) -> WorkCycleMetricEvidence {
            guard let start, let end else { return evidence(id, reason: "actual_endpoints_unavailable") }
            guard start <= end, end <= asOf else { return evidence(id, state: .needsReview, reason: "actual_endpoints_conflict") }
            return evidence(id, value: end.timeIntervalSince(start) / 60, start: start, end: end, state: .available, reason: "recorded_actual_endpoints")
        }
        let preceding = before?.interval(basis: .confirmed), following = after?.interval(basis: .confirmed)
        let first = gap("actual_shift_end_to_main_sleep", start: preceding?.end, end: start)
        let second = gap("actual_time_between_shifts", start: preceding?.end, end: following?.start)
        let worked = events.filter { $0.status == .worked && $0.attendanceConfirmed }
        let missing = worked.contains { event in
            guard event.interval(basis: .confirmed) == nil else { return false }
            if let end = event.actualEnd, end <= lookbackStart { return false }
            if let start = event.actualStart, start >= lookbackEnd { return false }
            return true
        }
        let intervals = worked.compactMap { $0.interval(basis: .confirmed) }.filter { $0.start < lookbackEnd && $0.end > lookbackStart }.sorted { $0.start < $1.start }
        let overlap = zip(intervals, intervals.dropFirst()).contains { $0.0.end > $0.1.start }
        let total: WorkCycleMetricEvidence
        if context.mainSleepStart == nil {
            total = evidence("recorded_actual_work_minutes", reason: "main_sleep_anchor_unavailable")
        } else if missing || intervals.isEmpty {
            total = evidence("recorded_actual_work_minutes", reason: "actual_work_coverage_unavailable")
        } else if overlap {
            total = evidence("recorded_actual_work_minutes", state: .needsReview, reason: "overlapping_actual_shift_intervals")
        } else {
            let minutes = intervals.reduce(0.0) { $0 + min($1.end, lookbackEnd).timeIntervalSince(max($1.start, lookbackStart)) / 60 }
            total = evidence("recorded_actual_work_minutes", value: minutes, start: lookbackStart, end: lookbackEnd,
                             state: .available, reason: "recorded_shift_minutes_only_not_complete_attendance")
        }
        let sources = Set([before?.id, after?.id].compactMap { $0 } + worked.filter { event in
            event.interval(basis: .confirmed).map { $0.start < lookbackEnd && $0.end > lookbackStart } ?? true
        }.map(\.id))
        return .init(shiftEndToMainSleep: first, betweenShifts: second, recordedWorkMinutes: total,
                     sourceRevisionIDs: sources.sorted { $0.uuidString < $1.uuidString })
    }
}
