import SwiftUI
import Charts
import DoseCore

struct DashboardWorkBlockView: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @State private var document = WorkContextDocument()
    @State private var storedRevision: UUID?
    @State private var loaded = false
    @State private var error: String?
    @State private var editing = false
    @State private var selected: WorkCycleObservation?
    @State private var basis = WorkContextBasis.planned
    @State private var metric = WorkBlockMetric.appleSleep
    @State private var phaseFilter = "All"
    @State private var asOf = Date()
    @State private var observations: [WorkCycleObservation] = []

    private var rows: [WorkCycleObservation] { observations.filter { phaseFilter == "All" || $0.phase.rawValue == phaseFilter } }
    private var positions: [String] {
        WorkPhase.allCases.flatMap { phase in
            Set(rows.filter { $0.phase == phase }.map(\.position)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }
    private var maximum: Double { max(1, (rows.compactMap(\.value).max() ?? 1) * 1.1) }
    var body: some View {
        List {
            Section {
                Text(model.rangeDescription).font(.caption)
                Picker("Context basis", selection: $basis) {
                    Text("Reviewed plan snapshot").tag(WorkContextBasis.planned)
                    Text("Confirmed work history").tag(WorkContextBasis.confirmed)
                }.accessibilityIdentifier("work-context-basis")
                Picker("Outcome (minutes)", selection: $metric) { ForEach(WorkBlockMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Work phase", selection: $phaseFilter) {
                    Text("All including unknown").tag("All")
                    ForEach(WorkPhase.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }
                Text("Plans never establish attendance. Off-block does not mean recovered. Missing values are not zero.").font(.caption)
                if let message = model.errorMessage { Text(message).foregroundStyle(.orange) }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Configure roster or confirm a work date") { load(); editing = loaded }.disabled(!loaded)
                    .accessibilityIdentifier("work-context-configure")
            }
            Section("Work-cycle profile") {
                counts(rows)
                if rows.contains(where: { $0.value != nil }) {
                    Chart {
                        ForEach(rows) { row in
                            if let value = row.value {
                                PointMark(x: .value("Minutes", value), y: .value("Cycle position", row.position))
                                    .foregroundStyle(.secondary).symbolSize(25)
                            }
                        }
                        ForEach(positions, id: \.self) { position in
                            let summary = WorkCycleSummary(observations: rows.filter { $0.position == position })
                            if let low = summary.lowerQuartile, let high = summary.upperQuartile {
                                RuleMark(xStart: .value("Lower quartile", low), xEnd: .value("Upper quartile", high), y: .value("Cycle position", position))
                                    .lineStyle(StrokeStyle(lineWidth: 4)).foregroundStyle(.primary)
                            }
                            if let median = summary.median {
                                PointMark(x: .value("Median", median), y: .value("Cycle position", position)).symbol(.diamond).symbolSize(55).foregroundStyle(.primary)
                            }
                        }
                    }.chartXScale(domain: 0...maximum).chartYScale(domain: positions)
                        .chartXAxisLabel(metric.rawValue + " (minutes)")
                        .frame(height: CGFloat(max(180, positions.count * 55)))
                        .accessibilityLabel("Work-cycle profile. Individual measurements, diamond median and middle 50 percent interval. Exact records follow in the table.")
                } else { Text("No available measurements for this outcome. All observations remain in the table.") }
                Text("Dots: individual observations. Diamond: median. Line: middle 50%, not a confidence interval. No points are connected across blocks.").font(.caption)
                ForEach(positions, id: \.self) { position in
                    VStack(alignment: .leading) {
                        Text(position).font(.headline)
                        counts(rows.filter { $0.position == position })
                    }
                }
            }
            Section("Week-by-week block matrix") { matrix }
            Section("Records and exact values") {
                if rows.isEmpty { Text("No nights in this range. Choose a different range on Dashboard.") }
                ForEach(rows) { row in
                    Button { selected = row } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.sleepDate + " • " + row.phase.label).font(.headline)
                            Text(row.position)
                            if row.isOverride { Text("Reviewed override").font(.caption) }
                            Text(row.value.map { String(format: "%.1f minutes", $0) } ?? "Unavailable")
                        }.foregroundStyle(.primary)
                    }.accessibilityIdentifier("work-context-record-" + row.id)
                }
            }
            Section("Review snapshot") {
                Text("Context as of \(asOf.formatted()). Classification version 1. CSV preserves this range, metric, context basis and revision.").font(.caption)
                ShareLink("Share this comparison CSV", item: WorkCycleSummary.csv(rows, metric: metric.rawValue, basis: basis, range: model.rangeDescription, revision: document.revision, asOf: asOf)).disabled(!loaded)
            }
        }.navigationTitle("Work Block & Sleep")
            .task { load() }
            .refreshable { load() }
            .onReceive(model.$nights) { rebuild($0) }
            .onChange(of: basis) { _ in rebuild(model.populatedNights) }
            .onChange(of: metric) { _ in rebuild(model.populatedNights) }
            .sheet(isPresented: $editing) { WorkContextEditor(document: document, save: save) }
            .sheet(item: $selected) { row in WorkBlockRecordDetail(row: row, document: document, save: save) }
    }
    private func counts(_ values: [WorkCycleObservation]) -> some View {
        let summary = WorkCycleSummary(observations: values)
        return Text("\(summary.availableCount) available • \(summary.missingCount) unavailable • \(summary.distinctBlockCount) distinct known blocks with values • \(summary.unresolvedBlockCount) unresolved block links")
            .font(.caption).foregroundStyle(.secondary)
    }
    private var matrix: some View {
        let blocks = Set(rows.compactMap(\.blockID)).sorted()
        return VStack(alignment: .leading, spacing: 10) {
            Text("Blocks are identified by first-shift date. Phase appears in labels; values share minutes. Blank cells remain missing. Later off-block sleep is not assigned an invented index.").font(.caption)
            if blocks.isEmpty { Text("No resolved block boundaries yet. Review the sleep context and roster or attendance dates.") }
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text("First shift").frame(width: 100)
                        ForEach(positions, id: \.self) { Text($0).frame(width: 150).font(.caption.bold()) }
                    }
                    ForEach(blocks, id: \.self) { block in
                        HStack(alignment: .top) {
                            Text(String(block.suffix(10))).frame(width: 100)
                            ForEach(positions, id: \.self) { position in
                                let cells = rows.filter { $0.blockID == block && $0.position == position }
                                VStack {
                                    if cells.isEmpty { Text("Missing") }
                                    ForEach(cells) { cell in
                                        Button { selected = cell } label: {
                                            Text(cell.sleepDate + "\n" + (cell.value.map { String(format: "%.1f min", $0) } ?? "Unavailable"))
                                        }
                                    }
                                }.frame(width: 150).font(.caption)
                            }
                        }
                    }
                }
            }
        }
    }
    private func load() {
        do {
            let stored = try model.sessionRepo.workContext()
            document = stored ?? WorkContextDocument(); storedRevision = stored?.revision
            loaded = true; error = nil; asOf = Date(); rebuild(model.populatedNights)
        } catch { loaded = false; self.error = error.localizedDescription }
    }
    private func save(_ next: WorkContextDocument) throws {
        try model.sessionRepo.saveWorkContext(next, expectedRevision: storedRevision)
        document = next; storedRevision = next.revision; asOf = Date(); rebuild(model.populatedNights)
    }
    static func scopedNights(_ nights: [DashboardNightAggregate], window: DashboardReportingWindow?) -> [DashboardNightAggregate] {
        guard let window else { return [] }
        return nights.filter { window.contains($0.sessionDate) && ($0.hasAnyData || $0.napSummary.count > 0 || $0.snoozeCount > 0) }
    }
    private func rebuild(_ nights: [DashboardNightAggregate]) {
        let scoped = Self.scopedNights(nights, window: model.currentReportWindow)
        let contexts = document.classifications(scoped.compactMap { document.association(for: $0.id, asOf: asOf) }, basis: basis, asOf: asOf)
        observations = scoped.map { night in
            let association = document.association(for: night.id, asOf: asOf)
            let context = association.flatMap { contexts[$0.id] }
            return WorkCycleObservation(sleepID: night.id, sleepDate: night.sessionDate, phase: context?.phase ?? .unknown, position: context?.positionLabel ?? "Unknown / review", blockID: context?.blockID, value: metric.value(night), rosterID: context?.rosterID, detail: context?.detail ?? "Review this main sleep's adjacent waking dates.", associationID: association?.id, contextSnapshotAt: association.map { basis == .planned ? $0.plannedAt : asOf }, isOverride: context?.isOverride ?? false)
        }.sorted { $0.sleepDate == $1.sleepDate ? $0.id < $1.id : $0.sleepDate > $1.sleepDate }
        if let selected { self.selected = observations.first { $0.id == selected.id } }
    }
}

private enum WorkBlockMetric: String, CaseIterable {
    case appleSleep = "Apple Health main sleep", whoopSleep = "WHOOP main sleep", interval = "D1–D2 interval", afterDose2 = "Observed sleep after Dose 2"
    func value(_ night: DashboardNightAggregate) -> Double? {
        switch self {
        case .appleSleep: return night.appleHealthSleepMinutes
        case .whoopSleep: return night.whoopSleepMinutes
        case .interval: return night.exactIntervalMinutes
        case .afterDose2: return night.postDoseSleep?.asleepMinutes
        }
    }
}

private struct WorkBlockRecordDetail: View {
    let row: WorkCycleObservation
    let document: WorkContextDocument
    let save: (WorkContextDocument) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reviewing = false
    var body: some View {
        NavigationStack {
            Form {
                Text(row.sleepDate).font(.headline)
                Text(row.phase.label); Text(row.position)
                if row.isOverride { Text("Reviewed override").font(.headline) }; Text(row.detail)
                Text(row.value.map { String(format: "%.3f minutes", $0) } ?? "Measurement unavailable")
                Text("Block: " + (row.blockID.map { String($0.suffix(10)) } ?? "Unresolved"))
                Text("Roster revision: " + (row.rosterID?.uuidString ?? "Unavailable"))
                if let association = document.association(for: row.id, asOf: Date()) {
                    Text("Waking dates: \(association.precedingDate) → \(association.followingDate)")
                    Text(association.timeZoneIdentifier)
                    Text("Reviewed plan snapshot: \(association.plannedAt.formatted())")
                }
                Text("Built-in spacing reference; not a prescription. Work context cannot change doses, alarms or sleep records.").font(.caption)
                Button("Review main-sleep work context") { reviewing = true }
            }.navigationTitle("Work context detail")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $reviewing, onDismiss: { dismiss() }) {
                    WorkSleepContextEditor(sleepID: row.id, sleepDate: row.sleepDate, document: document, save: save)
                }
        }
    }
}
