import SwiftUI
import Charts
import DoseCore

enum DashboardReplayMode: String, CaseIterable, Identifiable {
    case replay = "Replay", intervals = "Intervals", opportunity = "Sleep opportunity"
    case medication = "Medication", coverage = "Reviewed coverage"
    var id: String { rawValue }
}

/// Read-only inspection. Selecting or checking coverage never records a medication or changes alarms.
struct DashboardReplayView: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @ObservedObject private var coverage: TimelineDoseSleepModel
    private let initialMode: DashboardReplayMode?
    init(model: DashboardAnalyticsModel, initialMode: DashboardReplayMode? = nil) {
        self.model = model; self.initialMode = initialMode
        _coverage = ObservedObject(wrappedValue: model.replayCoverageState)
    }
    private var page: DashboardReplayMode { model.replayPresentation.mode }
    private var alignment: DashboardReplaySnapshot.Alignment { model.replayPresentation.alignment }
    private var preset: DashboardIntervalPreset { model.replayPresentation.preset }
    private var intervalMode: String { model.replayPresentation.intervalMode }
    private var opportunityEndpoint: DashboardIntervalPreset { model.replayPresentation.opportunityEndpoint }
    private var medicationLabels: [String: String] {
        get { model.replayPresentation.medicationLabels }
        nonmutating set { model.replayPresentation.medicationLabels = newValue }
    }
    private var selectionNotice: String? {
        get { model.replayPresentation.selectionNotice }
        nonmutating set { model.replayPresentation.selectionNotice = newValue }
    }
    private var endpointSelections: [String: [DashboardReplayMarker]] {
        get { model.replayPresentation.endpointSelections }
        nonmutating set { model.replayPresentation.endpointSelections = newValue }
    }
    private var selectedID: String? {
        get { model.selectedReplayID }
        nonmutating set { model.selectReplayID(newValue) }
    }
    @State private var export: ReplayExportPreview?
    @Environment(\.dashboardPalette) private var palette

    private var snapshots: [DashboardReplaySnapshot] { model.replayDisplaySnapshots }
    private var selectionIsInvalid: Bool {
        guard let night = model.populatedNights.first(where: { $0.replayID == selectedID }) else { return false }
        return hasInvalidEndpoints(night)
    }
    private func hasInvalidEndpoints(_ night: DashboardNightAggregate) -> Bool {
        (try? model.applyingReplayChoices(model.replaySnapshot(for: night))) == nil
    }
    private var selected: DashboardReplaySnapshot? { snapshots.first { $0.sessionID == selectedID } }
    private var alignedRows: [DashboardReplaySnapshot] {
        let start = selectedIndex ?? 0
        return Array(snapshots.dropFirst(start).prefix(28))
    }
    private var selectedIndex: Int? { snapshots.firstIndex { $0.sessionID == selectedID } }
    private var filteredIntervalSnapshots: [DashboardReplaySnapshot] {
        guard page == .intervals else { return snapshots }
        return snapshots.filter {
            guard let row = model.replayComparison(for: $0, outcome: model.replayPresentation.comparedOutcome, preset: preset) else { return false }
            return (model.replayPresentation.selectedBinLower == nil || row.binLower == model.replayPresentation.selectedBinLower)
                && (model.replayPresentation.timingWorkFilter == nil || row.workBeforeSleep == model.replayPresentation.timingWorkFilter)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.rangeDescription).font(.caption).foregroundStyle(.secondary)
                if let issue = model.inspectionFilterIssue { Text(issue).font(.caption) }
                if let error = model.errorMessage { Label(error, systemImage: "exclamationmark.triangle").font(.caption) }
                Picker("Inspection", selection: $model.replayPresentation.mode) {
                    ForEach(DashboardReplayMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("dashboard-replay-page")
                Picker("Selected session", selection: Binding(get: { selectedID }, set: { selectedID = $0 })) {
                    Text("Choose a session").tag(String?.none)
                    ForEach(snapshots, id: \.sessionID) { snap in
                        Text(label(snap)).tag(Optional(snap.sessionID))
                    }
                }.accessibilityIdentifier("dashboard-replay-selection")
                HStack {
                    Button("Previous") { move(-1) }.disabled(selectedIndex == nil || selectedIndex == 0)
                    Spacer()
                    Button("Next") { move(1) }.disabled(selectedIndex == nil || selectedIndex == snapshots.count - 1)
                }
                if let snap = selected {
                    Text("\(snap.sourcePolicy) • \(snap.timeZoneID)").font(.caption)
                    Text("As of \(stamp(snap.asOf, snap)) • one row is one session").font(.caption).foregroundStyle(.secondary)
                    if !snap.identityResolved { Label("Session association needs review. No interval is inferred.", systemImage: "questionmark.diamond") }
                    if let notice = selectionNotice { Text(notice).font(.caption) }
                    if selectionIsInvalid {
                        Label("Selected endpoints are no longer valid. Clear them and select current records before exporting.", systemImage: "exclamationmark.triangle")
                        Button("Clear selected endpoints") { endpointSelections[snap.sessionID] = []; model.replayPresentation.dosePairs[snap.sessionID] = nil }
                    }
                    dosePairPicker(snap)
                    DashboardReplayEndpoints(model: model, snapshot: snap, selected: Binding(
                        get: { endpointSelections[snap.sessionID] ?? [] }, set: {
                            endpointSelections[snap.sessionID] = $0; selectionNotice = nil
                        }), onRecords: { records in medicationLabels = Dictionary(records.map { ($0.id, $0.name + " · " + $0.formulation) }, uniquingKeysWith: { left, right in left == right ? left : "Conflicting medication labels" }) })
                    if page == .replay || page == .medication { replay(snap) }
                    else if page == .intervals { DashboardIntervalExplorer(model: model, snapshots: snapshots) }
                    else if page == .opportunity { opportunity(snap) }
                    else { coveragePanel(snap) }
                    if page == .medication { reminderDeviations }
                    Button("Preview selected session export") {
                        export = ReplayExportPreview(export: makeExport([snap], scope: "Selected observation"))
                    }
                        .accessibilityIdentifier("dashboard-replay-export")
                        .disabled(selectionIsInvalid || !filteredIntervalSnapshots.contains(where: { $0.sessionID == snap.sessionID }))
                } else {
                    Text(model.inspection.selectionStatus(visibleIDs: model.visibleInspectionNights.map(\.id), knownIDs: model.nights.map(\.id)).explanation
                         ?? "Choose a session to inspect its recorded occurrences. Missing endpoints remain unavailable.")
                }
                if page == .intervals, selected == nil { DashboardIntervalExplorer(model: model, snapshots: snapshots) }
                Button("Preview filtered observations export") {
                    export = ReplayExportPreview(export: makeExport(filteredIntervalSnapshots, scope: "All filtered observations"))
                }.accessibilityIdentifier("dashboard-replay-export-filtered")
                    .disabled(filteredIntervalSnapshots.isEmpty || !model.invalidReplayEndpointIDs.isEmpty || model.isLoading)
            }.padding()
        }
        .navigationTitle("Replay & intervals")
        .onAppear {
            model.replayPresentation.open(initialMode: initialMode)
            if model.inspection.selectedObservationID == nil { selectedID = snapshots.first?.sessionID }
        }
        .sheet(item: $export) { $0 }
    }

    @ViewBuilder private func replay(_ snap: DashboardReplaySnapshot) -> some View {
        Picker("Alignment", selection: $model.replayPresentation.alignment) {
            ForEach(DashboardReplaySnapshot.Alignment.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu)
        Text(alignment == .clock ? "Local clock labels include date and UTC offset; elapsed intervals use UTC."
             : "Minutes from the selected administration; negative values occurred before it.").font(.caption)
        if !snap.markers.isEmpty, snap.position(of: snap.markers[0].occurredAt, alignment: alignment) != nil {
            Chart {
                ForEach(snap.markers) { marker in
                if let x = snap.position(of: marker.occurredAt, alignment: alignment) {
                    PointMark(x: .value("Position", x), y: .value("Event", lane(marker)))
                        .foregroundStyle(palette.timing).symbol(by: .value("Evidence", marker.kind == .reminder ? "Saved schedule" : marker.kind == .requiredWake ? "Saved required wake" : "Recorded occurrence"))
                        .accessibilityLabel(marker.kind.label + ", " + stamp(marker.occurredAt, snap))
                }
                }
                if let evidence = snap.mainEpisodeEvidence {
                    ForEach(Array(evidence.slices.enumerated()), id: \.offset) { _, band in
                        if let start = snap.position(of: band.start, alignment: alignment), let end = snap.position(of: band.end, alignment: alignment) {
                            BarMark(xStart: .value("Position", start), xEnd: .value("Position", end),
                                    y: .value("Event", "Observed " + band.state.rawValue)).foregroundStyle(palette.sleep)
                        }
                    }
                }
            }.frame(height: max(240, CGFloat(Set(snap.markers.map(lane)).count + 3) * 36))
                .accessibilityIdentifier(page == .medication ? "dashboard-medication-chart" : "dashboard-replay-chart")
                .chartXScale(domain: replayDomain(snap))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(); AxisValueLabel {
                        if let x = value.as(Double.self) {
                            Text(alignment == .clock ? stamp(Date(timeIntervalSince1970: x * 60), snap) : String(format: "%.0f min", x))
                        }
                    }
                } }
        } else { Text("No usable alignment endpoint. Select Clock time or review the dose occurrences.") }
        if let evidence = snap.mainEpisodeEvidence {
            Text("Imported main-episode intervals; \(amount(evidence.coverage.unmeasuredMinutes)) unmeasured, including \(amount(evidence.conflictMinutes)) conflicting. No stage sequence is inferred.").font(.caption)
            ForEach(Array(evidence.slices.enumerated()), id: \.offset) { _, band in
                Text("\(band.state.rawValue): \(stamp(band.start, snap)) to \(stamp(band.end, snap))").font(.caption)
            }
        }
        Text("Exact event table").font(.headline)
        Text("Events at the same plotted position remain separate below. Patient wake, device ending and recording times are distinct.").font(.caption)
        ForEach(snap.markers) { marker in
            VStack(alignment: .leading, spacing: 3) {
                Text(lane(marker)).font(.subheadline.bold())
                Text(stamp(marker.occurredAt, snap))
                Text(marker.kind.label + " · " + marker.source).font(.caption).foregroundStyle(.secondary)
                if let quality = marker.evidenceQuality {
                    Text("\(quality.state.rawValue): \(quality.reason)").font(.caption)
                    if let captured = quality.capturedAt { Text("Source captured \(stamp(captured, snap))").font(.caption) }
                }
                if let amount = marker.amountDescription { Text("Actual amount: " + amount).font(.caption) }
                if let formulation = marker.formulation { Text("Formulation: " + formulation).font(.caption) }
                if let recorded = marker.recordedAt { Text("Recorded \(stamp(recorded, snap))").font(.caption) }
            }.accessibilityElement(children: .combine)
        }
        if page != .medication {
        Text("Aligned session comparison").font(.headline)
        Text("Same alignment for up to 28 sessions from the selection (\(alignedRows.count) shown). The table and session picker retain overlapping events.").font(.caption)
        Chart {
            ForEach(alignedRows, id: \.sessionID) { row in
                ForEach(row.markers.filter { [.dose1, .dose2, .reportedWake, .deviceSleepEnd].contains($0.kind) }) { marker in
                    if let x = alignedPosition(marker.occurredAt, row) {
                        PointMark(x: .value("Position", x), y: .value("Session", label(row)))
                            .symbol(by: .value("Endpoint", lane(marker))).foregroundStyle(palette.timing)
                    }
                }
            }
        }.frame(height: max(180, CGFloat(alignedRows.count) * 28))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(); AxisValueLabel {
                    if let x = value.as(Double.self) {
                        Text(alignment == .clock ? String(format: "%02d:%02d", Int(x / 60) % 24, Int(x) % 60) : String(format: "%.0f min", x))
                    }
                }
            } }
        Text("Clock comparison uses local noon through the following noon. Repeated clock times remain separate records in the exact table; elapsed alignment uses UTC. Dose and final-wake endpoints are shown.").font(.caption)
        ForEach(alignedRows, id: \.sessionID) { row in
            Button { selectedID = row.sessionID } label: {
                HStack { Text(label(row)); Spacer(); Text(row.interval(.dose1ToDose2).minutes.map { String(format: "%.1f min D1–D2", $0) } ?? row.interval(.dose1ToDose2).state.rawValue) }
            }
        }
        }
    }

    private func lane(_ marker: DashboardReplayMarker) -> String {
        if let id = marker.sourceRecordID, let label = medicationLabels[id] { return label }
        if marker.kind == .event { return marker.source }
        if page == .medication && [.dose1, .dose2, .extraDose, .reminder].contains(marker.kind) {
            return "Nightly administration · name/formulation not recorded"
        }
        return marker.kind.label
    }

    @ViewBuilder private func dosePairPicker(_ snap: DashboardReplaySnapshot) -> some View {
        if snap.markers.filter({ $0.kind == .dose1 || $0.kind == .dose2 }).count > 2 || model.replayPresentation.dosePairs[snap.sessionID] != nil {
            Text("Choose an explicit D1–D2 pair for this inspection. All recorded administrations remain visible; this does not change the dose pattern.").font(.caption)
            ForEach([DashboardReplayMarker.Kind.dose1, .dose2], id: \.rawValue) { kind in
                Picker("Selected " + kind.label, selection: Binding<String?>(get: {
                    let choice = model.replayPresentation.dosePairs[snap.sessionID]
                    return kind == .dose1 ? choice?.dose1ID : choice?.dose2ID
                }, set: { id in
                    var choice = model.replayPresentation.dosePairs[snap.sessionID] ?? .init()
                    if kind == .dose1 { choice.dose1ID = id } else { choice.dose2ID = id }
                    model.replayPresentation.dosePairs[snap.sessionID] = choice
                })) {
                    Text("Choose recorded occurrence").tag(String?.none)
                    ForEach(snap.markers.filter { $0.kind == kind }) { marker in
                        Text(stamp(marker.occurredAt, snap) + " · " + marker.id).tag(Optional(marker.id))
                    }
                }.accessibilityIdentifier("dashboard-replay-pair-" + kind.rawValue)
            }
        }
    }

    private func makeExport(_ values: [DashboardReplaySnapshot], scope: String) -> ReplayInspectionExport {
        let context = "View: \(page.rawValue); preset: \(preset.rawValue); alignment: \(alignment.rawValue); display: \(intervalMode); outcome: \(model.replayPresentation.comparedOutcome.rawValue); bin: \(model.replayPresentation.selectedBinLower.map(ReplayComparisonRow.binLabel) ?? "all"); pattern: \(model.inspection.dosePatternFilter?.rawValue ?? "all"); work: \(model.inspection.workPhaseFilter?.rawValue ?? "all"); work basis: \(model.inspection.workContextBasis.rawValue); context: \(model.inspection.contextStratumID ?? "all"); include partial: \(model.inspection.includePartialMetrics)"
        return .init(scope: scope, selectedObservationID: model.inspection.selectedObservationID, rows: values.compactMap { snap in
            guard let night = model.nights.first(where: { $0.replayID == snap.sessionID }) else { return nil }
            return .init(observationID: night.id, snapshot: snap.withViewContext(context), recordedWakeTarget: model.replayWakeTarget(for: night),
                comparison: model.replayComparison(for: snap, outcome: model.replayPresentation.comparedOutcome, preset: preset))
        })
    }

    @ViewBuilder private func opportunity(_ snap: DashboardReplaySnapshot) -> some View {
        let value = DashboardPostDoseCoverage.calculate(snapshot: snap, preset: opportunityEndpoint)
        Text("Sleep opportunity and continuity").font(.headline)
        Picker("Named endpoint", selection: $model.replayPresentation.opportunityEndpoint) {
            ForEach([DashboardIntervalPreset.dose2ToDeviceEnd, .dose2ToReportedWake, .dose2ToRequiredWake]) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("dashboard-opportunity-endpoint")
        Text("One selected session. Elapsed time, observed asleep time and coverage have distinct meanings.").font(.caption)
        Button(coverage.isLoading ? "Checking coverage…" : "Check Apple Health reviewed coverage") { checkCoverage(snap) }
            .disabled(coverage.isLoading || !snap.identityResolved)
        Chart {
            ForEach(Array(value.bands.enumerated()), id: \.offset) { _, band in
                BarMark(xStart: .value("Start", band.start), xEnd: .value("End", band.end), y: .value("Span", "Recorded coverage"))
                    .foregroundStyle(by: .value("Coverage state", band.state.rawValue))
            }
            ForEach(snap.markers.filter { [.dose2, opportunityEndpoint.endpoints.1, .requiredWake].contains($0.kind) }) { marker in
                if snap.hasValidBoundary, marker.occurredAt.timeIntervalSinceReferenceDate.isFinite {
                    RuleMark(x: .value("Endpoint", marker.occurredAt)).foregroundStyle(palette.timing)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: marker.kind == .requiredWake ? [5, 3] : []))
                        .annotation(position: .top, spacing: marker.kind == .requiredWake ? 24 : 4) { Text(marker.kind == .requiredWake ? "Required wake" : marker.kind == .dose2 ? "D2" : "Endpoint").font(.caption2) }
                }
            }
        }.chartForegroundStyleScale(["asleep": palette.sleep, "awake": palette.timing, "unmeasured": Color.gray, "conflict": Color.orange])
            .frame(height: 190).padding(.top, 28).accessibilityIdentifier("dashboard-opportunity-chart")
        Text("\(value.state.rawValue): \(value.reason)").font(.caption)
        Text("Named interval: \(amount(value.elapsedMinutes)); asleep: \(amount(value.asleepMinutes)); awake: \(amount(value.awakeMinutes)); unmeasured: \(amount(value.unmeasuredMinutes))")
        Text("Conflicting \(amount(value.conflictMinutes)) is already included in unmeasured time. Required wake is a saved requirement, not actual awakening or measured future sleep.").font(.caption)
        if let night = model.nights.first(where: { $0.replayID == snap.sessionID }) {
            let target = model.replayWakeTarget(for: night)
            Text("Required wake: \(target.state.rawValue) · \(target.reason)").font(.caption)
            ForEach(Array(target.sources.enumerated()), id: \.offset) { _, source in
                Text("\(stamp(source.requiredWake, snap)) · source \(source.eventID) · revision \(source.revision.uuidString)").font(.caption)
            }
        }
        ForEach(Array(value.bands.enumerated()), id: \.offset) { _, band in
            Text("\(band.state.rawValue): \(stamp(band.start, snap)) to \(stamp(band.end, snap))").font(.caption)
        }
    }

    private var reminderDeviations: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actual minus saved reminder").font(.headline)
            Text("Signed minutes for recorded historical targets. Positive and negative describe timing; neither is a safety or adherence category. Daytime formulation-specific schedules are unavailable unless their original target was recorded.").font(.caption)
            Chart {
                RuleMark(y: .value("Scheduled time", 0)).foregroundStyle(.secondary)
                ForEach(snapshots, id: \.sessionID) { snap in
                    if let minutes = snap.interval(.reminderDeviation).minutes {
                        PointMark(x: .value("Session date", plotDate(snap)), y: .value("Signed minutes", minutes)).foregroundStyle(palette.timing)
                    }
                }
            }.frame(height: 200).accessibilityIdentifier("dashboard-medication-deviation")
            ForEach(snapshots, id: \.sessionID) { snap in
                let value = snap.interval(.reminderDeviation)
                Button { selectedID = snap.sessionID } label: {
                    Text("\(label(snap)): \(amount(value.minutes)) · \(value.state.rawValue) · \(value.reason)")
                }.font(.caption)
            }
        }
    }

    private func checkCoverage(_ snap: DashboardReplaySnapshot) {
        Task { await coverage.refresh(sessionDate: snap.treatmentDate) { _ in await model.replayCoverage(sessionID: snap.sessionID) } }
    }

    @ViewBuilder private func coveragePanel(_ snap: DashboardReplaySnapshot) -> some View {
        Text("Reviewed-window coverage").font(.headline)
        Text("This separately checked window does not replace the selected main-episode sleep total. Missing time is not awake time.").font(.caption)
        Button(coverage.isLoading ? "Checking coverage…" : "Check Apple Health coverage") {
            checkCoverage(snap)
        }.disabled(coverage.isLoading || !snap.identityResolved)
        if let result = coverage.result { Text(result.explanation).font(.callout) }
        else { Text("Use History to save a reviewed sleep window for this session, then explicitly check it here.").font(.caption) }
        if let projection = snap.reviewedProjection {
            Chart(Array(projection.bands.enumerated()), id: \.offset) { _, band in
                BarMark(xStart: .value("Start", band.start), xEnd: .value("End", band.end), y: .value("State", band.state.rawValue))
                    .foregroundStyle(palette.sleep)
            }.frame(height: 180)
            Text("Asleep: \(amount(projection.coverage.asleepMinutes)); awake: \(amount(projection.coverage.awakeMinutes)); unmeasured: \(amount(projection.coverage.unmeasuredMinutes))")
            Text("Conflicting \(amount(projection.conflictMinutes)) is already included in unmeasured time.").font(.caption)
            ForEach(Array(projection.bands.enumerated()), id: \.offset) { _, band in
                Text("\(band.state.rawValue): \(stamp(band.start, snap)) to \(stamp(band.end, snap))")
                    .font(.caption).accessibilityElement(children: .combine)
            }
        }
    }
    private func replayDomain(_ snap: DashboardReplaySnapshot) -> ClosedRange<Double> {
        let dates = snap.markers.map(\.occurredAt) + (snap.mainEpisodeEvidence?.slices.flatMap { [$0.start, $0.end] } ?? [])
        let values = dates.compactMap { snap.position(of: $0, alignment: alignment) }.filter(\.isFinite)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        return (low - 5)...(high + 5)
    }
    private func alignedPosition(_ date: Date, _ snap: DashboardReplaySnapshot) -> Double? {
        guard snap.hasValidBoundary else { return nil }
        guard alignment == .clock else { return snap.position(of: date, alignment: alignment) }
        guard date.timeIntervalSince1970.isFinite else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: snap.timeZoneID) ?? .current
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        guard let hour = parts.hour, let minute = parts.minute, let second = parts.second else { return nil }
        let position = Double(hour * 60 + minute) + Double(second) / 60
        return position < 720 ? position + 1440 : position
    }
    private func plotDate(_ snap: DashboardReplaySnapshot) -> Date {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: snap.timeZoneID)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.date(from: snap.treatmentDate) ?? snap.asOf
    }
    private func label(_ snap: DashboardReplaySnapshot) -> String { "\(snap.treatmentDate) · \(snap.sessionID.suffix(6))" }
    private func amount(_ value: Double?) -> String { value.map { String(format: "%.1f min", $0) } ?? "unavailable" }
    private func move(_ delta: Int) {
        guard let index = selectedIndex, snapshots.indices.contains(index + delta) else { return }
        selectedID = snapshots[index + delta].sessionID
    }
    private func stamp(_ date: Date, _ snap: DashboardReplaySnapshot) -> String {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return "Invalid timestamp — review required" }
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: snap.timeZoneID)
        formatter.dateFormat = "MMM d HH:mm ZZZZZ"; return formatter.string(from: date)
    }
}

private struct ReplayExportPreview: View, Identifiable {
    let id = UUID()
    let export: ReplayInspectionExport
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(export.scope): \(export.rows.count) observations").font(.headline)
                    Text("Review the session, source, filters, exact endpoints and coverage before sharing. Notes are excluded. Medication labels, source IDs and timing are included. Later corrections require a new snapshot.")
                    if export.csv.count > 40_000 { Text("Preview shortened; shared files contain all selected observations.").font(.caption) }
                    Text(String(export.csv.prefix(40_000))).font(.caption.monospaced()).textSelection(.enabled)
                    ShareLink("Share CSV text", item: export.csv)
                    if let data = try? export.jsonData(), let json = String(data: data, encoding: .utf8) {
                        ShareLink("Share JSON snapshot", item: json)
                    }
                }.padding()
            }.navigationTitle("Export preview").toolbar { Button("Close") { dismiss() } }
        }
    }
}
