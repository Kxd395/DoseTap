import Foundation
import DoseCore

enum DashboardWorkBeforeSleep: String, Codable, CaseIterable {
    case work = "Workday", off = "Off day", unknown = "Unknown"
}

extension DashboardAnalyticsModel {
    func workBeforeSleep(for observationID: String) -> DashboardWorkBeforeSleep {
        guard workContextReadReady, workInspectionAsOf == reportingAsOf else { return .unknown }
        switch confirmedWorkClassifications[observationID]?.phase {
        case .between, .after: return .work
        case .entering, .off: return .off
        case .unknown, nil: return .unknown
        }
    }

    var inspectionFilterIssue: String? {
        guard currentReportWindow != nil else { return "Choose a valid reporting period before applying dashboard filters." }
        if inspection.dosePatternFilter != nil && !doseReviewReadReady {
            return "Dose history is awaiting a complete local refresh. The selected filter is retained."
        }
        if inspection.workPhaseFilter != nil && (!workContextReadReady || workInspectionAsOf != reportingAsOf) {
            return workContextIssue ?? "Work context is awaiting a complete local refresh. The selected filter is retained."
        }
        if inspection.contextStratumID != nil && !contextReadReady {
            return "Comparison context is awaiting a complete local refresh. The selected filter is retained."
        }
        return nil
    }

    var visibleInspectionNights: [DashboardNightAggregate] {
        guard inspectionFilterIssue == nil else { return [] }
        return populatedNights.filter { night in
            if let pattern = inspection.dosePatternFilter, night.dosePattern.pattern != pattern { return false }
            if let phase = inspection.workPhaseFilter,
               (workClassification(for: night.id)?.phase ?? .unknown) != phase { return false }
            if let context = inspection.contextStratumID, night.contextStratum(for: sleepSource).id != context { return false }
            return true
        }.sorted { left, right in
            left.sessionDate == right.sessionDate ? left.id < right.id : left.sessionDate > right.sessionDate
        }
    }

    func workClassification(for observationID: String) -> WorkPhaseResult? {
        guard workContextReadReady, workInspectionAsOf == reportingAsOf else { return nil }
        return inspection.workContextBasis == .planned
            ? plannedWorkClassifications[observationID] : confirmedWorkClassifications[observationID]
    }

    func invalidateWorkInspectionContext() {
        workContextReadReady = false; workInspectionContext = nil; workInspectionAsOf = nil
        plannedWorkClassifications = [:]; confirmedWorkClassifications = [:]
        workContextIssue = "Work context is awaiting a complete local refresh. The selected filter is retained."
    }

    func publishWorkInspectionContext(_ value: WorkContextDocument?, nights: [DashboardNightAggregate], asOf: Date) {
        guard value?.isValid != false, asOf.timeIntervalSince1970.isFinite else {
            invalidateWorkInspectionContext()
            workContextIssue = "Work context could not be validated. Refresh before applying work filters."
            return
        }
        let grouped = Dictionary(grouping: nights, by: \.id)
        let ids = Set(grouped.compactMap { id, rows in
            rows.count == 1 && rows.first?.identityNeedsReview == false ? id : nil
        })
        plannedWorkClassifications = value?.classificationsBySleepID(ids, basis: .planned, asOf: asOf) ?? [:]
        confirmedWorkClassifications = value?.classificationsBySleepID(ids, basis: .confirmed, asOf: asOf) ?? [:]
        workInspectionContext = value; workInspectionAsOf = asOf
        workContextIssue = nil; workContextReadReady = true
    }
}
