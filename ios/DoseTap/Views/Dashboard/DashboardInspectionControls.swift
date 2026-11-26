import SwiftUI
import DoseCore

/// These controls edit presentation state only. Original records and selection are preserved.
struct DashboardInspectionControls: View {
    @ObservedObject var model: DashboardAnalyticsModel
    private var contexts: [DashboardContextStratum] {
        guard model.contextReadReady else { return [] }
        return Dictionary(grouping: model.populatedNights.map { $0.contextStratum(for: model.sleepSource) }, by: \.id)
            .compactMap { $0.value.first }.sorted { $0.label == $1.label ? $0.id < $1.id : $0.label < $1.label }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Sleep source", selection: $model.sleepSource) {
                ForEach(DashboardSleepSource.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("dashboard-sleep-source")
            DisclosureGroup("Shared filters and summary policy") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Dose pattern", selection: $model.inspection.dosePatternFilter) {
                        Text("All patterns").tag(DashboardDosePattern.Pattern?.none)
                        ForEach(DashboardDosePattern.Pattern.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }.pickerStyle(.menu).accessibilityIdentifier("dashboard-dose-filter")
                    Picker("Work phase", selection: $model.inspection.workPhaseFilter) {
                        Text("All phases").tag(WorkPhase?.none)
                        ForEach(WorkPhase.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                    }.pickerStyle(.menu).accessibilityIdentifier("dashboard-work-filter")
                    Picker("Work evidence", selection: $model.inspection.workContextBasis) {
                        ForEach(WorkContextBasis.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }.pickerStyle(.menu)
                    Picker("Comparison context", selection: $model.inspection.contextStratumID) {
                        Text("All contexts").tag(String?.none)
                        ForEach(contexts, id: \.id) { Text($0.label).tag(Optional($0.id)) }
                        if let selected = model.inspection.contextStratumID, !contexts.contains(where: { $0.id == selected }) {
                            Text("Retained context outside current results").tag(Optional(selected))
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("dashboard-context-filter")
                    Toggle("Include partial values in compatible summaries", isOn: $model.inspection.includePartialMetrics)
                        .accessibilityIdentifier("dashboard-partial-policy")
                    Text("Partial records remain visible. Missing values are not zero. Sources, endpoint definitions and reference versions remain separate.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Reset shared filters") { model.inspection.resetFilters() }
                        .accessibilityIdentifier("dashboard-reset-filters")
                }.padding(.top, 8)
            }
            if let issue = model.inspectionFilterIssue { Text(issue).foregroundStyle(.orange) }
            Text("\(model.visibleInspectionNights.count) of \(model.populatedNights.count) session or provider observations match. Daytime and nap views state which night filters do not apply to their independent records.")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("dashboard-filter-count")
            if let explanation = model.inspection.selectionStatus(visibleIDs: model.visibleInspectionNights.map(\.id), knownIDs: model.nights.map(\.id)).explanation {
                Text(explanation).font(.callout).accessibilityIdentifier("dashboard-retained-selection")
            }
            if model.inspection.selectedObservationID != nil {
                Button("Clear selected night/provider observation") { model.inspection.selectedObservationID = nil }
                    .accessibilityIdentifier("dashboard-clear-selection")
            }
        }
    }
}
