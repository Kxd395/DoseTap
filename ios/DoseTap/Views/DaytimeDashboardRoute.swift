import SwiftUI
import DoseCore

struct DaytimeTrendSelection {
    let range: DashboardReportingRange
    let asOf: Date
    let timeZone: TimeZone
    let reviewedPeriod: PhysicianReportPeriod?
    let work: WorkContextDocument?
    let medication: DashboardContextTimeline?
    let basis: WorkContextBasis
    let contextIssue: String?
    var identity: String {
        "\(range.rawValue)|\(asOf.timeIntervalSince1970)|\(timeZone.identifier)|\(reviewedPeriod?.start.timeIntervalSince1970 ?? 0)|\(reviewedPeriod?.endExclusive.timeIntervalSince1970 ?? 0)|\(basis.rawValue)|\(work?.revision.uuidString ?? "")|\(contextIssue ?? "")"
    }
    func window(earliestEvidenceAt: Date?) throws -> DashboardDaytimeWindow {
        try range.daytimeWindow(asOf: asOf, timeZone: timeZone, reviewedPeriod: reviewedPeriod, earliestEvidenceAt: earliestEvidenceAt)
    }
}

enum DaytimeSelectionIssue: LocalizedError {
    case updating, unavailable
    var errorDescription: String? {
        self == .updating ? "Dashboard dates are updating. The selected period is retained." : "Dashboard dates are not ready. Refresh the dashboard to use the selected period."
    }
}

extension DashboardAnalyticsModel {
    func validatedSharedDaytimeSelection() throws -> DaytimeTrendSelection {
        guard !isLoading else { throw DaytimeSelectionIssue.updating }
        guard lastRefresh == reportingAsOf, reportingTimeZone == timeZone() else { throw DaytimeSelectionIssue.unavailable }
        let reviewed = selectedRange == .custom || selectedRange == .sinceCompletedVisit ? reportingPeriod : nil
        if selectedRange == .custom {
            guard publishedCustomReportingRange == customReportingRange,
                  case let .custom(start, end)? = customReportingRange,
                  reviewed?.start == start, reviewed?.endExclusive == end else { throw DaytimeSelectionIssue.unavailable }
        }
        _ = try selectedRange.daytimeWindow(asOf: reportingAsOf, timeZone: reportingTimeZone, reviewedPeriod: reviewed)
        let workReady = workContextReadReady && workInspectionAsOf == reportingAsOf
        let medicationReady = contextReadReady && contextTimeline?.capturedAt == reportingAsOf
        return DaytimeTrendSelection(range: selectedRange, asOf: reportingAsOf, timeZone: reportingTimeZone,
            reviewedPeriod: reviewed, work: workReady ? workInspectionContext : nil,
            medication: medicationReady ? contextTimeline : nil, basis: inspection.workContextBasis,
            contextIssue: workReady && medicationReady ? nil : "Comparison context is unavailable. Raw observations remain visible; matched comparisons are withheld until Refresh succeeds.")
    }
}

struct DashboardDaytimeRoute: View {
    @ObservedObject var model: DashboardAnalyticsModel
    var body: some View {
        switch Result(catching: { try model.validatedSharedDaytimeSelection() }) {
        case .success(let selection):
            DaytimeTrendsView(repository: model.sessionRepo, sharedSelection: selection, refreshShared: { model.refresh() })
                .id(selection.identity)
        case .failure(let error):
            VStack(spacing: 16) {
                Text(error.localizedDescription)
                Button("Refresh dashboard") { model.refresh() }.disabled(model.isLoading)
            }.padding().navigationTitle("Daytime trends").accessibilityIdentifier("daytime-shared-unavailable")
        }
    }
}

struct DaytimeTrendRecords {
    let observations: [DaytimeCheckIn]
    let events: [DaytimeEvent]
    var earliestEvidenceAt: Date? {
        (observations.map(\.assessedAt) + observations.compactMap { $0.eventReview?.from } + events.map(\.occurredAt)).min()
    }
    @MainActor init(repository: SessionRepository, asOf: Date) throws {
        guard asOf.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.invalid }
        observations = try DaytimeCheckInLedger(revisions: repository.daytimeCheckIns().revisions.filter { $0.recordedAt <= asOf }).current
        events = try DaytimeEventLedger(revisions: repository.daytimeEvents().revisions.filter { $0.recordedAt <= asOf }).current
    }
}
