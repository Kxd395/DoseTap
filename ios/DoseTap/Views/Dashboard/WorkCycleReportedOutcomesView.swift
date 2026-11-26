import SwiftUI
import DoseCore

struct WorkCycleReportedOutcomesView: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @State private var metric = ContextMorningMetric.quality
    @State private var monthly = true
    @State private var categories: WorkCycleCategoryReport?
    @State private var naps: WorkCycleNapDayReport?
    @State private var issue: String?
    @State private var publication: Task<Void, Never>?
    var body: some View {
        List {
            Section("Selected comparison") {
                Text(model.rangeDescription)
                Text("Work basis: " + model.inspection.workContextBasis.rawValue).font(.caption)
                Picker("Reported outcome", selection: $metric) {
                    ForEach(ContextMorningMetric.allCases.filter { !$0.duration }) { Text($0.rawValue).tag($0) }
                }
                Toggle("Separate calendar months", isOn: $monthly)
                Text("Original categories remain categories. Unconfirmed legacy answers are visible for review and do not enter distributions.").font(.caption)
                if let issue { Text(issue).foregroundStyle(.orange) }
            }
            if let categories {
                Section("Categorical observations by work position") {
                    Text("\(categories.comparison.eligibleCount) eligible • \(categories.comparison.excludedCount) excluded • \(categories.knownBlockCount) known blocks • \(categories.unknownWorkCount) unknown work observations").font(.caption)
                    ForEach(categories.comparison.groups) { group in
                        VStack(alignment: .leading) {
                            Text(group.context).font(.headline); Text(group.stratum).font(.caption)
                            Text("\(group.eligible.count) eligible / \(group.observations.count) recorded • \(categories.knownBlocks(for: group.eligible.map(\.id)).count) known blocks").font(.caption)
                            ForEach(group.categoryCounts.keys.sorted(), id: \.self) { answer in
                                Text(answer + ": " + String(group.categoryCounts[answer] ?? 0))
                            }
                            ForEach(group.observations) { row in
                                Text(row.treatmentDate + " • " + (row.category ?? "Answer unavailable") + " • " + row.state.rawValue).font(.caption)
                            }
                        }
                    }
                }
                if let csv = categories.csv { ShareLink("Share category comparison CSV", item: csv) }
            }
            Section("Independent assessed nap days") {
                Text("Original civil days remain Unknown work context: no day-to-work association was collected. Night dose, work-phase and regimen filters cannot establish a nap-day association. This separate panel uses only the selected civil period.").font(.caption)
                if let naps {
                    Text("\(naps.assessedDayCount) assessed full days / \(naps.rows.count) recorded day records • \(naps.unknownWorkDayCount) unknown work-context days")
                    ShareLink("Share assessed nap days CSV", item: naps.csv)
                    ForEach(naps.rows) { row in
                        VStack(alignment: .leading) {
                            Text(row.day + " • " + row.timeZoneID).font(.headline)
                            Text(row.recordCount.map { "\($0) reviewed episode records" } ?? "Full-day count unavailable")
                            Text(row.reason).font(.caption)
                            ForEach([NapIntent.planned, .unplanned, .rest, .unknown], id: \.self) { intent in
                                Text(intent.rawValue + ": " + String(row.intentCounts[intent] ?? 0)).font(.caption)
                            }
                        }
                    }
                } else { Text("Nap assessments are unavailable until a complete read succeeds.") }
            }
        }.navigationTitle("Reported work outcomes")
            .task { rebuild() }.onReceive(model.objectWillChange) { _ in rebuild() }
            .onChange(of: metric) { _ in rebuild() }.onChange(of: monthly) { _ in rebuild() }
            .onDisappear { publication?.cancel() }
    }
    private func rebuild() {
        publication?.cancel(); categories = nil; naps = nil; issue = nil
        publication = Task { @MainActor in
            await Task.yield(); guard !Task.isCancelled else { return }
            categories = model.workCycleCategoryReport(metric: metric, period: model.reportingPeriod, monthly: monthly)
            issue = model.workCycleComparisonIssue(metric: .doseInterval)
            do { naps = try model.workCycleNapDayReport() }
            catch { issue = "Nap day assessments could not be read completely. Refresh before sharing." }
        }
    }
}
