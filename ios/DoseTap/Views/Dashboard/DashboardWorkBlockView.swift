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
    @State private var controlsVisible = false
    @State private var selected: WorkCycleObservation?
    @State private var basis = WorkContextBasis.planned
    @State private var metric = WorkBlockMetric.appleSleep
    @State private var phaseFilter = "All"
    @State private var visualization = "Profile"
    @State private var grouping = WorkComparisonGrouping.none
    @State private var matrixEncoding = "Value intensity"
    @State private var positionFilter = "All"
    @State private var profileNames: [String: String] = [:]
    @State private var candidates: [WorkCycleObservation] = []
    private var asOf: Date { model.reportingAsOf }
    @State private var observations: [WorkCycleObservation] = []

    private var rows: [WorkCycleObservation] { observations.filter { (phaseFilter == "All" || $0.phase.rawValue == phaseFilter) && (positionFilter == "All" || $0.position == positionFilter) } }
    private var positions: [String] {
        WorkPhase.allCases.flatMap { phase in
            Set(observations.filter { $0.phase == phase }.map(\.position)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }
    private func profileLabel(_ row: WorkCycleObservation) -> String {
        let key = row.stratumID ?? "unknown:" + row.id
        return row.position + " • " + (row.stratumLabel ?? "Context unknown, " + row.sleepDate) + " [" + (profileNames[key] ?? "Unknown") + "]"
    }
    private var profileLabels: [String] { Array(Set(rows.map(profileLabel))).sorted() }
    private var maximum: Double { max(1, (observations.compactMap(\.value).max() ?? 1) * 1.1) }
    var body: some View {
        List {
            Section {
                Text(model.rangeDescription).font(.caption)
                Text((basis == .planned ? "Reviewed plan snapshot" : "Confirmed work history") + " • " + metric.rawValue).font(.caption)
                Text("Phase: " + phaseFilter + " • Position: " + positionFilter).font(.caption)
                Button("Comparison controls") { controlsVisible = true }.accessibilityIdentifier("work-comparison-controls")
                Text("Plans never establish attendance. Off-block does not mean recovered. Missing values are not zero.").font(.caption)
                if let message = model.errorMessage { Text(message).foregroundStyle(.orange) }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Configure roster or confirm a work date") { load(); editing = loaded }.disabled(!loaded)
                    .accessibilityIdentifier("work-context-configure")
            }
            if visualization == "Profile" { Section("Work-cycle profile") {
                if metric == .interval { Text("Built-in spacing reference: 150–240 minutes, inclusive; not a prescription.").font(.caption) }
                counts(rows)
                if rows.contains(where: { $0.value != nil }) {
                    Chart {
                        ForEach(rows) { row in
                            if let value = row.value {
                                PointMark(x: .value("Minutes", value), y: .value("Cycle position", profileLabel(row)))
                                    .foregroundStyle(Color.secondary).symbolSize(25)
                            }
                        }
                        ForEach(profileLabels, id: \.self) { position in
                            let summary = WorkCycleSummary(observations: rows.filter { profileLabel($0) == position })
                            if let low = summary.lowerQuartile, let high = summary.upperQuartile {
                                RuleMark(xStart: .value("Lower quartile", low), xEnd: .value("Upper quartile", high), y: .value("Cycle position", position))
                                    .lineStyle(StrokeStyle(lineWidth: 4)).foregroundStyle(Color.primary)
                            }
                            if let median = summary.median {
                                PointMark(x: .value("Median", median), y: .value("Cycle position", position)).symbol(.diamond).symbolSize(55).foregroundStyle(Color.primary)
                            }
                        }
                    }.chartXScale(domain: 0...maximum).chartYScale(domain: profileLabels)
                        .chartXAxisLabel(metric.rawValue + " (minutes)")
                        .frame(height: CGFloat(max(180, profileLabels.count * 55)))
                        .accessibilityLabel("Work-cycle profile. Individual measurements, diamond median and middle 50 percent interval. Exact records follow in the table.")
                } else { Text("No available measurements for this outcome. All observations remain in the table.") }
                Text("Unknown regimen/questionnaire context remains separate by observation. Dots: individual observations. Diamond: median. Line: middle 50%, not a confidence interval. No points are connected across blocks.").font(.caption)
                ForEach(profileLabels, id: \.self) { position in
                    VStack(alignment: .leading) {
                        Text(position).font(.headline)
                        counts(rows.filter { profileLabel($0) == position })
                    }
                }
            }
            }
            if visualization == "Scatter" { Section("Interval versus selected outcome") {
                if metric == .interval { Text("Choose a sleep outcome in Comparison controls to compare it against dose interval.") } else { scatter }
            } }
            if visualization == "Matrix" { Section("Week-by-week block matrix") {
                Picker("Cell fill represents", selection: $matrixEncoding) {
                    Text("Value intensity").tag("Value intensity")
                    Text("Work phase").tag("Work phase")
                }.accessibilityIdentifier("work-matrix-encoding")
                matrix
            } }
            Section("Records and exact values") {
                if rows.isEmpty { Text("No nights in this range. Choose a different range on Dashboard.") }
                ForEach(rows) { row in
                    Button { selected = row } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.sleepDate + " • " + row.phase.label).font(.headline)
                            Text(row.position)
                            Text("Group: " + row.groupLabel(grouping) + " • " + row.groupSymbol(grouping)).font(.caption)
                            if row.isOverride { Text("Reviewed override").font(.caption) }
                            Text(row.value.map { String(format: "%.1f minutes", $0) } ?? "Unavailable")
                        }.foregroundStyle(.primary)
                    }.accessibilityIdentifier("work-context-record-" + row.id)
                }
            }
            Section("Review snapshot") {
                Text("Context as of \(asOf.formatted()). Classification version 1. CSV preserves this range, metric, context basis and revision.").font(.caption)
                ShareLink("Share this comparison CSV", item: WorkCycleSummary.csv(rows, metric: metric.rawValue, basis: basis, range: model.rangeDescription, revision: document.revision, asOf: asOf, grouping: grouping, phaseFilter: phaseFilter, positionFilter: positionFilter, matrixEncoding: matrixEncoding)).disabled(!loaded)
            }
        }.navigationTitle("Work Block & Sleep")
            .task { load() }
            .refreshable { load() }
            .onReceive(model.$nights) { rebuild($0) }
            .onChange(of: basis) { _ in rebuild(model.populatedNights) }
            .onChange(of: metric) { _ in rebuild(model.populatedNights) }
            .onChange(of: phaseFilter) { _ in candidates = [] }
            .onChange(of: positionFilter) { _ in candidates = [] }
            .onChange(of: grouping) { _ in candidates = [] }
            .onChange(of: visualization) { _ in grouping = .none; candidates = [] }
            .sheet(isPresented: $controlsVisible) {
                NavigationStack { Form { comparisonControls }.navigationTitle("Work comparisons")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { controlsVisible = false } } } }
            }
            .sheet(isPresented: $editing) { WorkContextEditor(document: document, save: save) }
            .sheet(item: $selected) { row in WorkBlockRecordDetail(row: row, grouping: grouping, siblings: rows, select: { selected = $0 }, document: document, save: save) }
    }
    private var comparisonControls: some View {
        Group {
                Picker("Context basis", selection: $basis) {
                    Text("Reviewed plan snapshot").tag(WorkContextBasis.planned)
                    Text("Confirmed work history").tag(WorkContextBasis.confirmed)
                }.accessibilityIdentifier("work-context-basis")
                Picker("Outcome (minutes)", selection: $metric) { ForEach(WorkBlockMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Work phase", selection: $phaseFilter) {
                    Text("All including unknown").tag("All")
                    ForEach(WorkPhase.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Display", selection: $visualization) {
                    Text("Profile").tag("Profile"); Text("Block matrix").tag("Matrix"); Text("Interval scatter").tag("Scatter")
                }.accessibilityIdentifier("work-display")
                Picker("Shift position", selection: $positionFilter) {
                    Text("All positions").tag("All")
                    ForEach(positions, id: \.self) { Text($0).tag($0) }
                }
                if visualization == "Scatter" { Picker("Scatter group by", selection: $grouping) {
                    Text("None").tag(WorkComparisonGrouping.none)
                    Text("Work phase").tag(WorkComparisonGrouping.workPhase)
                    Text("Spacing reference").tag(WorkComparisonGrouping.spacingReference)
                }.accessibilityIdentifier("work-comparison-grouping") }
        }
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
                                            Text(cell.sleepDate + "\n" + cell.phase.label + "\n" + (cell.value.map { String(format: "%.1f min", $0) } ?? "Unavailable"))
                                                .foregroundStyle(.primary).padding(6).frame(maxWidth: .infinity)
                                                .background(cellFill(cell)).clipShape(RoundedRectangle(cornerRadius: 6))
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
    private var intervalMaximum: Double { max(300, (observations.compactMap(\.intervalMinutes).max() ?? 300) * 1.1) }
    private var groupLabels: [String] {
        switch grouping {
        case .none: return ["All observations"]
        case .workPhase: return WorkPhase.allCases.map(\.label)
        case .spacingReference: return ["Shorter than reference", "Within reference", "Longer than reference", "Interval unavailable"]
        }
    }
    private func phaseColor(_ phase: WorkPhase) -> Color {
        switch phase { case .entering: return .blue; case .between: return .purple; case .after: return .orange; case .off: return .teal; case .unknown: return .gray }
    }
    private var groupColors: [Color] {
        grouping == .workPhase ? WorkPhase.allCases.map(phaseColor) : groupLabels.map { _ in Color.primary }
    }
    private var groupSymbolNames: [String] {
        switch grouping {
        case .none: return ["circle"]
        case .workPhase: return WorkPhase.allCases.map(\.comparisonSymbol)
        case .spacingReference: return ["diamond", "circle", "triangle", "cross"]
        }
    }
    private var groupShapes: [BasicChartSymbolShape] {
        groupSymbolNames.map { name in
            switch name { case "square": return .square; case "triangle": return .triangle; case "diamond": return .diamond; case "cross": return .cross; default: return .circle }
        }
    }
    private func cellFill(_ row: WorkCycleObservation) -> Color {
        if matrixEncoding == "Work phase" { return phaseColor(row.phase).opacity(0.22) }
        guard let value = row.value else { return Color.secondary.opacity(0.06) }
        return Color.primary.opacity(0.06 + 0.24 * min(1, value / maximum))
    }
    private var scatter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("X: recorded D1–D2 interval. Y: \(metric.rawValue), minutes. Common axes remain fixed when filtering phases or positions.").font(.caption)
            Text("Built-in spacing reference; not a prescription.").font(.caption.bold())
            let eligible = rows.filter { $0.intervalMinutes != nil && $0.value != nil }
            Text("\(eligible.count) eligible pairs • \(rows.count - eligible.count) unavailable pairs • \(Set(eligible.compactMap(\.blockID)).count) distinct known blocks").font(.caption)
            Chart {
                RectangleMark(xStart: .value("Reference start", 150), xEnd: .value("Reference end", 240), yStart: .value("Minimum", 0), yEnd: .value("Maximum", maximum)).foregroundStyle(Color.secondary.opacity(0.1))
                ForEach(eligible) { row in
                    PointMark(x: .value("D1–D2 minutes", row.intervalMinutes!), y: .value(metric.rawValue, row.value!))
                        .foregroundStyle(by: .value("Group", row.groupLabel(grouping)))
                        .symbol(by: .value("Group", row.groupLabel(grouping))).symbolSize(65)
                        .accessibilityLabel(row.sleepDate + ", " + row.groupLabel(grouping))
                        .accessibilityValue(String(format: "Interval %.1f, outcome %.1f minutes", row.intervalMinutes!, row.value!))
                }
            }.chartXScale(domain: 0...intervalMaximum).chartYScale(domain: 0...maximum)
                .chartForegroundStyleScale(domain: groupLabels, range: groupColors)
                .chartSymbolScale(domain: groupLabels, range: groupShapes)
                .chartLegend(.hidden)
                .chartXAxisLabel("D1–D2 interval (minutes)").chartYAxisLabel(metric.rawValue + " (minutes)")
                .frame(height: 260)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onEnded { gesture in
                            let frame = geometry[proxy.plotAreaFrame]
                            let x = gesture.location.x - frame.minX, y = gesture.location.y - frame.minY
                            guard frame.width > 0, frame.height > 0, x >= 0, y >= 0, x <= frame.width, y <= frame.height else { return }
                            candidates = eligible.filter { row in
                                guard let px = proxy.position(forX: row.intervalMinutes!), let py = proxy.position(forY: row.value!) else { return false }
                                return abs(px - x) <= 22 && abs(py - y) <= 22
                            }
                        })
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(groupLabels.indices, id: \.self) { index in
                    Label(groupLabels[index], systemImage: groupSymbolNames[index] == "cross" ? "xmark" : groupSymbolNames[index] + ".fill")
                        .foregroundStyle(groupColors[index]).font(.caption)
                }
            }.accessibilityElement(children: .combine)
            Text("Tap near a marker to list every nearby observation. The exact-value table provides the same records without chart gestures.").font(.caption)
            ForEach(candidates) { row in
                Button(row.sleepDate + " • " + row.groupLabel(grouping)) { selected = row }
            }
        }
    }
    private func load() {
        do {
            let stored = try model.sessionRepo.workContext()
            document = stored ?? WorkContextDocument(); storedRevision = stored?.revision
            loaded = true; error = nil; rebuild(model.populatedNights)
        } catch { loaded = false; self.error = error.localizedDescription }
    }
    private func save(_ next: WorkContextDocument) throws {
        try model.sessionRepo.saveWorkContext(next, expectedRevision: storedRevision)
        document = next; storedRevision = next.revision; rebuild(model.populatedNights)
    }
    static func scopedNights(_ nights: [DashboardNightAggregate], window: DashboardReportingWindow?) -> [DashboardNightAggregate] {
        guard let window else { return [] }
        return nights.filter { window.contains($0.sessionDate) && ($0.hasAnyData || $0.napSummary.count > 0 || $0.snoozeCount > 0) }
    }
    private func rebuild(_ nights: [DashboardNightAggregate]) {
        let scoped = Self.scopedNights(nights, window: model.currentReportWindow)
        let associations = document.associationsBySleepID(Set(scoped.map(\.id)), asOf: asOf)
        let contexts = document.classifications(Array(associations.values), basis: basis, asOf: asOf)
        observations = scoped.map { night in
            let association = associations[night.id]
            let context = association.flatMap { contexts[$0.id] }
            return WorkCycleObservation(sleepID: night.id, sleepDate: night.sessionDate, phase: context?.phase ?? .unknown, position: context?.positionLabel ?? "Unknown / review", blockID: context?.blockID, value: metric.value(night), rosterID: context?.rosterID, detail: context?.detail ?? "Review this main sleep's adjacent waking dates.", associationID: association?.id, contextSnapshotAt: association.map { basis == .planned ? $0.plannedAt : asOf }, isOverride: context?.isOverride ?? false, intervalMinutes: night.exactIntervalMinutes, stratumID: "unknown:" + night.id)
        }.sorted { $0.sleepDate == $1.sleepDate ? $0.id < $1.id : $0.sleepDate > $1.sleepDate }
        let strata = Set(observations.map { $0.stratumID ?? "unknown:" + $0.id }).sorted()
        profileNames = Dictionary(uniqueKeysWithValues: strata.enumerated().map { ($0.element, "S" + String($0.offset + 1)) })
        candidates = candidates.compactMap { candidate in observations.first { $0.id == candidate.id } }
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
    let grouping: WorkComparisonGrouping
    let siblings: [WorkCycleObservation]
    let select: (WorkCycleObservation) -> Void
    let document: WorkContextDocument
    let save: (WorkContextDocument) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reviewing = false
    var body: some View {
        NavigationStack {
            Form {
                if let index = siblings.firstIndex(where: { $0.id == row.id }) {
                    HStack {
                        Button("Previous record") { select(siblings[index - 1]) }.disabled(index == 0)
                        Spacer()
                        Button("Next record") { select(siblings[index + 1]) }.disabled(index + 1 >= siblings.count)
                    }
                }
                Text(row.sleepDate).font(.headline)
                Text(row.phase.label); Text(row.position)
                Text("Group: " + row.groupLabel(grouping) + " • " + row.groupSymbol(grouping))
                Text(row.intervalMinutes.map { String(format: "D1–D2: %.3f minutes", $0) } ?? "D1–D2 interval unavailable")
                if row.isOverride { Text("Reviewed override").font(.headline) }; Text(row.detail)
                Text(row.value.map { String(format: "%.3f minutes", $0) } ?? "Measurement unavailable")
                Text("Block: " + (row.blockID.map { String($0.suffix(10)) } ?? "Unresolved"))
                Text("Roster revision: " + (row.rosterID?.uuidString ?? "Unavailable"))
                if let associationID = row.associationID, let association = document.associations.first(where: { $0.id == associationID }) {
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
