import SwiftUI
import Charts
import DoseCore

struct DashboardWorkBlockView: View {
    @ObservedObject var model: DashboardAnalyticsModel
    private var loaded: Bool { model.workContextReadReady && model.workInspectionAsOf == asOf }
    private struct EditorSnapshot: Identifiable {
        let id = UUID()
        let document: WorkContextDocument
        let expectedRevision: UUID?
    }
    @State private var editorSnapshot: EditorSnapshot?
    @State private var rosterEditor: EditorSnapshot?
    @State private var shiftEditor: EditorSnapshot?
    @State private var controlsVisible = false
    @State private var detailVisible = false
    @State private var metric = WorkCycleMetric.mainSleep
    private var basis: WorkContextBasis { model.inspection.workContextBasis }
    private var phaseFilter: String { model.inspection.workPhaseFilter?.rawValue ?? "All" }
    @State private var visualization = "Profile"
    @State private var monthlySummary = true
    @State private var grouping = WorkComparisonGrouping.none
    @State private var matrixEncoding = "Value intensity"
    @State private var positionFilter = "All"
    @State private var candidates: [WorkCycleObservation] = []
    private var asOf: Date { model.reportingAsOf }
    @State private var comparison: WorkCycleComparison?
    @State private var projectionTask: Task<Void, Never>?
    @State private var profileNames: [String: String] = [:]
    private var observations: [WorkCycleObservation] { comparison?.observations ?? [] }
    @State private var axisRows: [WorkCycleObservation] = []
    private var selected: WorkCycleObservation? { rows.first { $0.id == model.inspection.selectedObservationID } }
    private func select(_ row: WorkCycleObservation) {
        prepareEditorSnapshot()
        model.inspection.selectedObservationID = row.id; detailVisible = true
    }

    private var rows: [WorkCycleObservation] { observations.filter { positionFilter == "All" || $0.position == positionFilter } }
    private var positions: [String] {
        WorkPhase.allCases.flatMap { phase in
            Set(observations.filter { $0.phase == phase }.map(\.position)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
    }
    private var selectedExportContext: WorkCycleExportContext {
        let provider: DashboardProviderAccess.Provider = model.sleepSource == .appleHealth ? .health : .whoop
        let hasSnapshot = model.sleepSource == .appleHealth ? model.healthSnapshot != nil : model.whoopSnapshot != nil
        let definition = !metric.isProviderSleep && metric != .doseInterval ? (metric == .dose2ToRequiredWake ? DashboardRecordedWakeTarget.version : "actual_shift_intervals_v1") : metric == .doseInterval ? DashboardDosePattern.version
            : DashboardSleepMetricProjection.version + ":" + (metric == .mainSleep ? "mainProviderEpisode" : "observedAfterDose2")
        return .init(selectedSource: metric.isProviderSleep ? model.sleepSource.rawValue : "Reported administration / work evidence", selectedDefinition: definition,
            timeZoneIdentifier: model.reportingTimeZone.identifier,
            periodStart: model.reportingPeriod?.start ?? model.currentReportWindow?.start,
            periodEndExclusive: model.reportingPeriod?.endExclusive ?? model.currentReportWindow?.endExclusive,
            dosePatternFilter: model.inspection.dosePatternFilter?.rawValue,
            contextStratumFilter: model.inspection.contextStratumID, includePartialMetrics: model.inspection.includePartialMetrics,
            selectedObservationID: model.inspection.selectedObservationID, visualization: visualization,
            monthlySummaries: visualization == "Summaries" && monthlySummary,
            periodPolicy: model.reportingPeriod == nil ? "treatment_date_membership" : "reviewed_exact",
            providerSnapshotState: !metric.isProviderSleep ? "not_applicable" : model.providerSnapshotIsCurrent(provider) ? "current" : hasSnapshot ? "stale" : "unavailable")
    }
    private func profileLabel(_ row: WorkCycleObservation) -> String {
        let index = profileNames[row.stratumID ?? "unknown:" + row.id] ?? "Unknown"
        return row.position + " • " + (row.stratumLabel ?? "Context unknown, " + row.sleepDate) + " [" + index + "]"
    }
    private var profileLabels: [String] { Array(Set(rows.map(profileLabel))).sorted() }
    private var maximum: Double { max(1, (axisRows.compactMap(\.value).max() ?? 1) * 1.1) }
    var body: some View {
        List {
            Section {
                Text(model.rangeDescription).font(.caption)
                Text((basis == .planned ? "Reviewed plan snapshot" : "Confirmed work history") + " • " + metric.rawValue + " • " + model.sleepSource.rawValue).font(.caption)
                Text("Phase: " + (model.inspection.workPhaseFilter?.label ?? "All") + " • Position: " + positionFilter).font(.caption)
                Button("Comparison controls") { controlsVisible = true }.accessibilityIdentifier("work-comparison-controls")
                if metric == .recordedWork24h { Text("Recorded shift minutes only; unlogged attendance is unknown, not zero.").font(.caption) }
                if metric == .dose2ToRequiredWake { Text("Uses a saved required-wake target, not actual awakening or today’s schedule.").font(.caption) }
                Text("Plans never establish attendance. Off-block does not mean recovered. Missing values are not zero.").font(.caption)
                if let message = model.errorMessage { Text(message).foregroundStyle(.orange) }
                if let issue = model.workCycleComparisonIssue(metric: metric) { Text(issue).foregroundStyle(.orange) }
                if let notice = model.inspection.selectionStatus(visibleIDs: rows.map(\.id), knownIDs: model.nights.map(\.id)).explanation {
                    Text(notice).accessibilityIdentifier("work-selection-notice")
                }
                if let selected { Button("Open selected observation: " + selected.sleepDate) { prepareEditorSnapshot(); detailVisible = true } }

                NavigationLink("Reported categories and assessed nap days") { WorkCycleReportedOutcomesView(model: model) }.accessibilityIdentifier("work-reported-outcomes")
                Button("Record or correct a work shift") { prepareEditorSnapshot(); if loaded { shiftEditor = editorSnapshot } }
                    .disabled(!loaded).accessibilityIdentifier("work-shift-edit")
                Button("Configure roster or confirm a work date") { prepareEditorSnapshot(); if loaded { rosterEditor = editorSnapshot } }.disabled(!loaded)
                    .accessibilityIdentifier("work-context-configure")
            }
            if visualization == "Profile" { Section("Work-cycle profile") {
                if metric == .doseInterval { Text("Built-in spacing reference: 150–240 minutes, inclusive; not a prescription.").font(.caption) }
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
                if metric == .doseInterval { Text("Choose a sleep outcome in Comparison controls to compare it against dose interval.") } else { scatter }
            } }
            if visualization == "Matrix" { Section("Week-by-week block matrix") {
                Picker("Cell fill represents", selection: $matrixEncoding) {
                    Text("Value intensity").tag("Value intensity")
                    Text("Work phase").tag("Work phase")
                }.accessibilityIdentifier("work-matrix-encoding")
                matrix
            } }
            if visualization == "Summaries" { comparisonSummaries }
            Section("Records and exact values") {
                if rows.isEmpty { Text("No nights in this range. Choose a different range on Dashboard.") }
                ForEach(rows) { row in
                    Button { select(row) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.sleepDate + " • " + row.phase.label).font(.headline)
                            Text(row.position)
                            Text("Group: " + row.groupLabel(grouping) + " • " + row.groupSymbol(grouping)).font(.caption)
                            if row.isOverride { Text("Reviewed override").font(.caption) }
                            Text(row.value.map { String(format: "%.1f minutes contributed", $0) } ?? "No numeric contribution")
                            Text((row.metricEvidence?.metric.state.rawValue ?? "unavailable") + " • " + row.contributionReason).font(.caption)
                        }.foregroundStyle(.primary)
                    }.accessibilityIdentifier("work-context-record-" + row.id)
                }
            }
            Section("Review snapshot") {
                Text("Context as of \(asOf.formatted()). Classification versions: \(Set(rows.map(\.classificationVersion)).sorted().map(String.init).joined(separator: ", ")). CSV preserves this range, metric, context basis and revision.").font(.caption)
                ShareLink("Share this comparison CSV", item: WorkCycleSummary.csv(rows, metric: metric.rawValue, basis: basis, range: model.rangeDescription, revision: model.workInspectionContext?.revision, asOf: asOf, grouping: grouping, phaseFilter: phaseFilter, positionFilter: positionFilter, matrixEncoding: matrixEncoding, exportContext: selectedExportContext)).disabled(!loaded || comparison == nil)
            }
        }.navigationTitle("Work Block & Sleep")
            .task { scheduleProjection() }
            .onReceive(model.objectWillChange) { _ in scheduleProjection() }
            .onDisappear { projectionTask?.cancel() }
            .refreshable { await model.refreshAndWait() }
            .onChange(of: basis) { _ in candidates = [] }
            .onChange(of: metric) { _ in scheduleProjection() }
            .onChange(of: model.lastRefresh) { _ in candidates = [] }
            .onChange(of: phaseFilter) { _ in candidates = [] }
            .onChange(of: positionFilter) { _ in candidates = [] }
            .onChange(of: grouping) { _ in candidates = [] }
            .onChange(of: visualization) { _ in grouping = .none; candidates = [] }
            .sheet(isPresented: $controlsVisible) {
                NavigationStack { Form { comparisonControls }.navigationTitle("Work comparisons")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { controlsVisible = false } } } }
            }
            .sheet(item: $rosterEditor) { snapshot in
                WorkContextEditor(document: snapshot.document) { try save($0, expectedRevision: snapshot.expectedRevision) }
            }
            .sheet(item: $shiftEditor) { snapshot in
                WorkShiftEventEditor(document: snapshot.document) { try save($0, expectedRevision: snapshot.expectedRevision) }
            }
            .sheet(isPresented: $detailVisible) {
                if let selected, let snapshot = editorSnapshot {
                    WorkBlockRecordDetail(row: selected, grouping: grouping, siblings: rows, select: select, document: snapshot.document) {
                        try save($0, expectedRevision: snapshot.expectedRevision)
                    }
                }
                else { Text("The selected observation is outside the current view. Its selection is retained.").padding() }
            }
    }
    private var comparisonControls: some View {
        Group {
                Picker("Context basis", selection: $model.inspection.workContextBasis) {
                    Text("Reviewed plan snapshot").tag(WorkContextBasis.planned)
                    Text("Confirmed work history").tag(WorkContextBasis.confirmed)
                }.accessibilityIdentifier("work-context-basis")
                Picker("Outcome (minutes)", selection: $metric) { ForEach(WorkCycleMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Sleep source", selection: $model.sleepSource) {
                    ForEach(DashboardSleepSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Work phase", selection: $model.inspection.workPhaseFilter) {
                    Text("All including unknown").tag(Optional<WorkPhase>.none)
                    ForEach(WorkPhase.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
                }.accessibilityIdentifier("work-phase-filter")
                Toggle("Include partial metric contributions", isOn: $model.inspection.includePartialMetrics)

                Picker("Display", selection: $visualization) {
                    Text("Profile").tag("Profile"); Text("Block matrix").tag("Matrix"); Text("Interval scatter").tag("Scatter")
                    Text("Period summaries").tag("Summaries")
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
        return Text("\(summary.availableCount) contributing / \(summary.eligibleCount) eligible • \(summary.missingCount) unavailable • \(summary.notApplicableCount) not applicable • \(summary.partialIncludedCount)/\(summary.partialCount) partial included • \(summary.distinctBlockCount) distinct known blocks with values • \(summary.unresolvedBlockCount) unresolved block links")
            .font(.caption).foregroundStyle(.secondary)
    }
    private var comparisonSummaries: some View {
        let comparison = WorkCycleComparison(observations: rows)
        let groups = monthlySummary ? comparison.monthly : comparison.selectedPeriod
        return Section("Compatible work-cycle summaries") {
            Toggle("Separate calendar months", isOn: $monthlySummary)
            Text("Uses the selected dashboard period, including six-month or since-visit ranges. First post-block sleep and later off-block positions remain separate. Context changes, sources and metric definitions are never pooled.").font(.caption)
            Text("Recorded dates show observation coverage only. Missing calendar dates do not establish expected work, attendance, sleep, or recovery.").font(.caption)
            if groups.isEmpty { Text("No observations match this summary. Current filters remain selected.") }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 5) {
                    Text((group.month ?? model.rangeDescription) + " • " + group.phase.label).font(.headline)
                    Text(group.position + " • " + group.stratumLabel)
                    Text(group.source + " • " + group.definitionVersion).font(.caption)
                    Text("\(group.representedDateCount) recorded dates • \(group.rows.count) observations • \(group.needsReviewCount) need review").font(.caption)
                    counts(group.rows)
                    let summary = group.summary
                    Text(summary.median.map { String(format: "Median %.1f %@", $0, group.unit) } ?? "Median unavailable")
                    if let lower = summary.lowerQuartile, let upper = summary.upperQuartile {
                        Text(String(format: "Middle 50%%: %.1f–%.1f %@", lower, upper, group.unit)).font(.caption)
                    }
                    Text("Descriptive observations; not a confidence interval or a recovery assessment.").font(.caption)
                }
            }
        }
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
                            let dates = Set(rows.filter { $0.blockID == block }.compactMap(\.firstShiftDate))
                            Text(dates.count == 1 ? dates.first! : "First date unknown").frame(width: 100)
                            ForEach(positions, id: \.self) { position in
                                let cells = rows.filter { $0.blockID == block && $0.position == position }
                                VStack {
                                    if cells.isEmpty { Text("Missing") }
                                    ForEach(cells) { cell in
                                        Button { select(cell) } label: {
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
    private var intervalMaximum: Double { max(300, (axisRows.compactMap(\.intervalMinutes).max() ?? 300) * 1.1) }
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
                Button(row.sleepDate + " • " + row.groupLabel(grouping)) { select(row) }
            }
        }
    }
    private func scheduleProjection() {
        projectionTask?.cancel()
        comparison = nil; axisRows = []; profileNames = [:]; candidates = []
        projectionTask = Task { @MainActor in
            // Published values emit before mutation; coalesce the completed publication once.
            await Task.yield()
            guard !Task.isCancelled else { return }
            comparison = model.workCycleComparison(metric: metric, period: model.reportingPeriod)
            axisRows = model.workCycleAxisObservations(metric: metric) ?? []
            let strata = Set(axisRows.map { $0.stratumID ?? "unknown:" + $0.id }).sorted()
            profileNames = Dictionary(uniqueKeysWithValues: strata.enumerated().map { ($0.element, "S" + String($0.offset + 1)) })
        }
    }
    private func prepareEditorSnapshot() {
        editorSnapshot = EditorSnapshot(document: model.workInspectionContext ?? WorkContextDocument(), expectedRevision: model.workInspectionContext?.revision)
    }
    private func save(_ next: WorkContextDocument, expectedRevision: UUID?) throws {
        try model.sessionRepo.saveWorkContext(next, expectedRevision: expectedRevision)
        model.invalidateWorkInspectionContext()
        model.refresh()
    }
    static func scopedNights(_ nights: [DashboardNightAggregate], window: DashboardReportingWindow?) -> [DashboardNightAggregate] {
        guard let window else { return [] }
        return nights.filter { window.contains($0.sessionDate) && ($0.hasAnyData || $0.napSummary.count > 0 || $0.snoozeCount > 0) }
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
                Text(row.value.map { String(format: "%.3f minutes contributed", $0) } ?? "No numeric contribution")
                if let evidence = row.metricEvidence {
                    Text("Recorded state: " + evidence.metric.state.rawValue)
                    Text(evidence.metric.value.map { "Recorded value: " + String($0) + " " + evidence.metric.unit } ?? "Recorded value unavailable")
                    Text(evidence.source + " • " + evidence.definitionVersion)
                }
                Text("Contribution state: " + row.contributionState.rawValue)
                Text("Contribution: " + row.contributionReason)
                Text("Block first shift: " + (row.firstShiftDate ?? "Unresolved"))
                Text("Classifier version: " + String(row.classificationVersion))
                Text("Roster revision: " + (row.rosterID?.uuidString ?? "Unavailable"))
                if let associationID = row.associationID, let association = document.associations.first(where: { $0.id == associationID }) {
                    Text("Waking dates: \(association.precedingDate) → \(association.followingDate)")
                    Text(association.timeZoneIdentifier)
                    if let context = association.eventContext {
                        Text("Reviewed main sleep: " + (context.mainSleepStart?.formatted() ?? "Start unknown") + " → " + (context.mainSleepEnd?.formatted() ?? "End unknown"))
                        ForEach([context.precedingShiftID, context.followingShiftID].compactMap { $0 }, id: \.self) { id in
                            if let shift = document.shiftEvents?.first(where: { $0.shiftID == id && row.metricSourceRecordIDs.contains($0.id.uuidString) }) ?? document.latestShiftEvents(asOf: row.contextSnapshotAt ?? association.recordedAt).first(where: { $0.shiftID == id }) {
                                Text(shift.positionLabel + " • " + shift.status.rawValue)
                                Text("Actual: " + (shift.actualStart?.formatted() ?? "Start unknown") + " → " + (shift.actualEnd?.formatted() ?? "End unknown")).font(.caption)
                            }
                        }
                    }
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
