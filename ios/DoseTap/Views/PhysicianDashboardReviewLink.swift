import SwiftUI
import DoseCore

/// Explicit preparation owns an isolated query model; saved previews never invoke providers.
struct PhysicianDashboardReviewLink: View {
    @ObservedObject var model: DashboardAnalyticsModel
    var body: some View {
        NavigationLink("Prepare for sleep visit") { PhysicianDashboardReviewRoute(model: model) }
            .accessibilityIdentifier("physician-review-open")
    }
}

private struct PhysicianDashboardReviewRoute: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @StateObject private var source: PhysicianSourcePreparation
    init(model: DashboardAnalyticsModel) {
        self.model = model
        _source = StateObject(wrappedValue: PhysicianSourcePreparation(model: model))
    }
    var body: some View {
        PhysicianReviewView(prepareSources: { period in
            try await source.prepare(period: period, inspection: model.inspection, sleepSource: model.sleepSource)
        }, selectionIdentity: selectionIdentity, selectionDescription: selectionDescription, repository: source.repository)
    }
    private var selectionDescription: String {
        let context = model.inspection.contextStratumID.map { selected in
            model.nights.first { $0.contextStratum(for: model.sleepSource).id == selected }?.contextStratum(for: model.sleepSource).label
                ?? "Selected comparison context; no matching observation in the current dashboard range"
        }
        return PhysicianSourcePreparation.selectionLines(model.inspection, source: model.sleepSource, displayContext: context).joined(separator: "\n")
    }
    private var selectionLines: [String] {
        PhysicianSourcePreparation.selectionLines(model.inspection, source: model.sleepSource)
    }
    private var selectionIdentity: String {
        // Length-prefixing preserves exact identity even if a source key contains separators.
        selectionLines.map { "\($0.utf8.count):\($0)" }.joined()
    }
}

@MainActor
final class PhysicianSourcePreparation: ObservableObject {
    let repository: SessionRepository
    private let access: DashboardProviderAccess
    private let queries: DashboardProviderQueries
    private let clock: () -> Date
    init(model: DashboardAnalyticsModel) {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--physician-review-fixture") {
            let fixture = SessionRepository(storage: .inMemory())
            do {
                let now = Date()
                try fixture.saveDaytimeCheckIn(.init(assessedAt: now.addingTimeInterval(-3600), recordedAt: now,
                    timeZoneIdentifier: TimeZone.current.identifier, response: 0))
                try fixture.saveDaytimeEvent(.init(kind: .unplannedSleep, occurredAt: now.addingTimeInterval(-7200),
                    recordedAt: now, timeZoneIdentifier: TimeZone.current.identifier, note: "Synthetic UI example"))
            } catch { preconditionFailure("Synthetic physician fixture could not be prepared") }
            repository = fixture; access = DashboardProviderAccess(); clock = Date.init
            queries = .init(healthEnabled: { false }, whoopEnabled: { false }, whoopConnected: { false },
                prepareHealth: { .unavailable }, healthHistory: { _ in [] },
                whoopHistory: { _, _ in .init(summaries: [], sleepRecordCount: 0, recoveryRecordCount: 0, recoveryStatus: .completed) })
            return
        }
        #endif
        repository = model.sessionRepo; access = model.providerAccess; queries = model.providerQueries; clock = model.now
    }
    static func selectionLines(_ inspection: DashboardInspectionState, source: DashboardSleepSource, displayContext: String? = nil) -> [String] {
        ["Selected sleep source: " + source.rawValue,
         "Dose pattern: " + (inspection.dosePatternFilter?.label ?? "All patterns"),
         "Work phase: " + (inspection.workPhaseFilter?.label ?? "All phases") + "; basis: " + inspection.workContextBasis.rawValue,
         "Context stratum: " + (displayContext ?? inspection.contextStratumID ?? "All compatible strata, summarized separately"),
         inspection.includePartialMetrics ? "Partial values included by explicit selection." : "Partial values excluded from numeric summaries.",
         "Overnight filters apply to selected sleep/treatment rows. Independent daytime assessments and events retain their own exact occurrence-time period membership."]
    }
    func prepare(period: PhysicianReportPeriod, inspection: DashboardInspectionState,
                 sleepSource: DashboardSleepSource) async throws -> PhysicianPreparedSources {
        try period.validate(); try Task.checkCancellation()
        guard let zone = TimeZone(identifier: period.timeZoneIdentifier) else { throw PhysicianReviewError.invalidPeriod }
        let query = DashboardAnalyticsModel(now: clock, sessionRepo: repository, timeZone: { zone }, providerAccess: access, providerQueries: queries)
        query.inspection = inspection; query.sleepSource = sleepSource
        try query.applyCustomReportingRange(start: period.start, endExclusive: period.endExclusive, timeZone: zone)
        // This new model has no view onChange subscription and no already-custom refresh task.
        await query.performRefresh(days: 730)
        try Task.checkCancellation()
        guard query.reportingPeriod?.start == period.start, query.reportingPeriod?.endExclusive == period.endExclusive,
              query.reportingPeriod?.timeZoneIdentifier == period.timeZoneIdentifier,
              query.inspectionFilterIssue == nil else { throw PhysicianReviewError.invalidPeriod }
        let capturedAt = clock()
        let observations = try query.physicianReportObservations(for: period)
        var contexts = try query.physicianReportContexts(for: period, generatedAt: capturedAt)
        let lines = ["Source capture: " + ISO8601DateFormatter().string(from: capturedAt)] + Self.selectionLines(inspection, source: sleepSource)
        contexts.insert(try .init(id: "report-selection", title: "Report source and selection", lines: lines,
            source: "Explicit dashboard selection and report preparation", definitionVersion: "physician-selection.v1", recordIDs: []), at: 0)
        return .init(period: period, observations: observations, contexts: contexts, capturedAt: capturedAt,
            coverageDescription: query.physicianCoverageDescription, includePartialMetrics: inspection.includePartialMetrics)
    }
}
