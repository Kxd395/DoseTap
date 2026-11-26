import SwiftUI
import DoseCore

@MainActor
struct MorningDoseHistoryReviewSection: View {
    @ObservedObject var viewModel: MorningCheckInViewModel
    @StateObject private var model: DashboardAnalyticsModel
    @State private var loaded = false
    @State private var reviewObservation: DashboardNightAggregate?

    init(viewModel: MorningCheckInViewModel) {
        self.viewModel = viewModel
        let local = DashboardProviderQueries(healthEnabled: { false }, whoopEnabled: { false }, whoopConnected: { false },
            prepareHealth: { .unavailable }, healthHistory: { _ in throw CancellationError() },
            whoopHistory: { _, _ in throw CancellationError() })
        let reader = DashboardAnalyticsModel(providerQueries: local); reader.selectedRange = .all
        _model = StateObject(wrappedValue: reader)
    }
    private var night: DashboardNightAggregate? {
        model.nights.first { $0.sessionID == viewModel.sessionId && $0.sessionDate == viewModel.sessionDate }
    }
    static func offersUnresolvedReview(_ night: DashboardNightAggregate) -> Bool {
        !night.identityNeedsReview && night.dosePattern.pattern != .needsReview && !night.dosePattern.countComplete
            && night.dosePattern.reportedCount == 1 && night.dose1Time != nil && night.dose2Time == nil && !night.dose2Skipped
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !loaded || model.isLoading { ProgressView("Reading this session's medication reports") }
            else if !model.doseReviewReadReady {
                Text(model.errorMessage ?? "Medication reports could not be read completely. Your morning answers can still be saved.")
                Button("Retry reading medication reports") { Task { await reload() } }
            } else {
                if viewModel.hasCommittedDoseReconciliation {
                    Text("Medication choices will not be reapplied. Retrying saves only your morning answers. Use History for further medication corrections.")
                        .font(.footnote).accessibilityIdentifier("morning-medication-review-saved")
                } else if let night, night.dosePattern.countComplete && night.dosePattern.pattern != .needsReview
                    && !viewModel.reconcileDose1Taken && viewModel.dose2Reconciliation == .leaveAsIs {
                    Text("\(night.dosePattern.pattern.label). The complete count was already reported; these morning answers do not add administrations. Use History to enter an actual missing occurrence or correct medication records.")
                        .font(.footnote).accessibilityIdentifier("morning-dose-count-already-reported")
                } else { MorningCheckInDoseReconciliationSection(viewModel: viewModel) }
                if let night, Self.offersUnresolvedReview(night) {
                    Text("Only Dose 1 is logged. You can separately report a complete count or historical plan, including when occurrence details are unknown.")
                    Button("Review unresolved dose history") { reviewObservation = night }
                        .accessibilityIdentifier("morning-dose-history-review")
                    Text("Optional; answer later if unsure. This review does not resolve a pending medication action or create an administration. Existing dose confirmation above records actual occurrences only when you choose it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: viewModel.sessionId) { await reload() }
        .sheet(item: $reviewObservation) { DosePatternReviewSheet(model: model, night: $0, unansweredOnly: true) }
    }
    private func reload() async {
        loaded = false; await model.performRefresh(days: 730, includeProviders: false); loaded = true
    }
}
