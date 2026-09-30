import SwiftUI
import DoseCore

struct DaytimeInspectionState: Equatable {
    var selectedObservationID: UUID?
    var offeredCandidateIDs: [UUID] = []
    var origin: DaytimeCheckIn.Origin?
    var setting: DaytimeCheckIn.Setting?
    static func ordered(_ rows: [DaytimeCheckIn]) -> [DaytimeCheckIn] {
        rows.sorted { $0.assessedAt == $1.assessedAt ? $0.id.uuidString < $1.id.uuidString : $0.assessedAt < $1.assessedAt }
    }
    func selected(in rows: [DaytimeCheckIn]) -> DaytimeCheckIn? { rows.first { $0.id == selectedObservationID } }
    mutating func select(_ id: UUID) { selectedObservationID = id; offeredCandidateIDs = [] }
    mutating func resetSelection() { selectedObservationID = nil; offeredCandidateIDs = [] }
    mutating func resetFilters() { origin = nil; setting = nil }
    mutating func offer(at: Date, observations: [DaytimeCheckIn], tolerance: TimeInterval = 0) {
        let rows = Self.ordered(observations.filter { $0.response != nil })
        guard at.timeIntervalSince1970.isFinite, tolerance.isFinite, tolerance >= 0, let distance = rows.map({ abs($0.assessedAt.timeIntervalSince(at)) }).min() else { offeredCandidateIDs = []; return }
        let candidates = rows.filter { abs($0.assessedAt.timeIntervalSince(at)) <= distance + tolerance + 0.000001 }
        if candidates.count == 1, let candidate = candidates.first { select(candidate.id) }
        else { offeredCandidateIDs = candidates.map(\.id) }
    }
    func neighbor(_ step: Int, observations: [DaytimeCheckIn]) -> UUID? {
        let rows = Self.ordered(observations)
        guard step == -1 || step == 1, let index = rows.firstIndex(where: { $0.id == selectedObservationID }), rows.indices.contains(index + step) else { return nil }
        return rows[index + step].id
    }
    mutating func move(_ step: Int, observations: [DaytimeCheckIn]) {
        if let id = neighbor(step, observations: observations) { select(id) }
    }
}

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
            DaytimeTrendsView(repository: model.sessionRepo, sharedSelection: selection, sharedInspection: $model.daytimeInspection, refreshShared: { model.refresh() })
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
