import SwiftUI
import Charts
import DoseCore

/// Read-only inspection. Selecting or checking coverage never records a medication or changes alarms.
struct DashboardReplayView: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @StateObject private var coverage = TimelineDoseSleepModel()
    @State private var selectedID: String?
    @State private var page = "Replay"
    @State private var alignment = DashboardReplaySnapshot.Alignment.clock
    @State private var preset = DashboardIntervalPreset.dose1ToDose2
    @State private var intervalMode = "By date"
    @State private var export: ReplayExportPreview?
    @Environment(\.dashboardPalette) private var palette

    private var snapshots: [DashboardReplaySnapshot] {
        model.populatedNights.map { model.replaySnapshot(for: $0,
            reviewed: $0.replayID == selectedID ? coverage.result : nil) }
    }
    private var selected: DashboardReplaySnapshot? { snapshots.first { $0.sessionID == selectedID } }
    private var available: [(snapshot: DashboardReplaySnapshot, value: Double)] {
        snapshots.compactMap { snap in snap.interval(preset).minutes.map { (snap, $0) } }
    }
    private var selectedIndex: Int? { snapshots.firstIndex { $0.sessionID == selectedID } }
    private var sleepPairCount: Int {
        available.filter { pair in
            guard let night = model.populatedNights.first(where: { $0.replayID == pair.snapshot.sessionID }) else { return false }
            return (model.sleepSource == .appleHealth ? night.appleHealthSleepMinutes : night.whoopSleepMinutes) != nil
        }.count
    }
    private var bins: [Int: Int] { Dictionary(grouping: available, by: { Int(floor($0.value / 30)) }).mapValues(\.count) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.rangeDescription).font(.caption).foregroundStyle(.secondary)
                if let error = model.errorMessage { Label(error, systemImage: "exclamationmark.triangle").font(.caption) }
                Picker("Inspection", selection: $page) {
                    ForEach(["Replay", "Intervals", "Coverage"], id: \.self) { Text($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("dashboard-replay-page")
                Picker("Selected session", selection: $selectedID) {
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
                    if page == "Replay" { replay(snap) }
                    else if page == "Intervals" { intervals }
                    else { coveragePanel(snap) }
                    Button("Preview selected session export") { export = ReplayExportPreview(snapshot: snap) }
                        .accessibilityIdentifier("dashboard-replay-export")
                } else {
                    Text(selectedID == nil ? "Choose a session to inspect its recorded occurrences. Missing endpoints remain unavailable."
                         : "The selected session is no longer in the current source or filter results. Choose another session; no replacement was selected automatically.")
                }
            }.padding()
        }
        .navigationTitle("Replay & intervals")
        .onAppear { if selectedID == nil { selectedID = snapshots.first?.sessionID } }
        .onChange(of: selectedID) { _ in coverage.invalidate() }
        .onReceive(model.objectWillChange) { _ in coverage.invalidate() }
        .onReceive(model.sessionRepo.sessionDidChange) { _ in coverage.invalidate() }
        .onReceive(model.providerAccess.changes) { _ in coverage.invalidate() }
        .sheet(item: $export) { $0 }
    }

    @ViewBuilder private func replay(_ snap: DashboardReplaySnapshot) -> some View {
        Picker("Alignment", selection: $alignment) {
            ForEach(DashboardReplaySnapshot.Alignment.allCases) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.menu)
        Text(alignment == .clock ? "Local clock labels include date and UTC offset; elapsed intervals use UTC."
             : "Minutes from the selected administration; negative values occurred before it.").font(.caption)
        if !snap.markers.isEmpty, snap.position(of: snap.markers[0].occurredAt, alignment: alignment) != nil {
            Chart(snap.markers) { marker in
                if let x = snap.position(of: marker.occurredAt, alignment: alignment) {
                    PointMark(x: .value("Position", x), y: .value("Event", marker.kind.label))
                        .foregroundStyle(palette.timing).symbol(.diamond)
                        .accessibilityLabel(marker.kind.label + ", " + stamp(marker.occurredAt, snap))
                }
            }.frame(height: max(180, CGFloat(Set(snap.markers.map(\.kind)).count) * 36))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(); AxisValueLabel {
                        if let x = value.as(Double.self) {
                            Text(alignment == .clock ? stamp(Date(timeIntervalSince1970: x * 60), snap) : String(format: "%.0f min", x))
                        }
                    }
                } }
        } else { Text("No usable alignment endpoint. Select Clock time or review the dose occurrences.") }
        Text("Exact event table").font(.headline)
        Text("Events at the same plotted position remain separate below. Patient wake, device ending and recording times are distinct.").font(.caption)
        ForEach(snap.markers) { marker in
            VStack(alignment: .leading, spacing: 3) {
                Text(marker.kind.label).font(.subheadline.bold())
                Text(stamp(marker.occurredAt, snap))
                Text(marker.source).font(.caption).foregroundStyle(.secondary)
                if let recorded = marker.recordedAt { Text("Recorded \(stamp(recorded, snap))").font(.caption) }
            }.accessibilityElement(children: .combine)
        }
        Text("Aligned session comparison").font(.headline)
        Text("Same alignment across \(snapshots.count) sessions. The table and session picker retain overlapping events.").font(.caption)
        Chart {
            ForEach(snapshots, id: \.sessionID) { row in
                ForEach(row.markers.filter { [.dose1, .dose2, .reportedWake, .deviceSleepEnd].contains($0.kind) }) { marker in
                    if let x = row.position(of: marker.occurredAt, alignment: alignment) {
                        PointMark(x: .value("Position", x), y: .value("Session", label(row)))
                            .symbol(by: .value("Endpoint", marker.kind.label)).foregroundStyle(palette.timing)
                    }
                }
            }
        }.frame(height: max(180, CGFloat(snapshots.count) * 28))
        Text("Dose and final-wake endpoints; all recorded event types remain in the selected session table.").font(.caption)
        ForEach(snapshots, id: \.sessionID) { row in
            Button { selectedID = row.sessionID } label: {
                HStack { Text(label(row)); Spacer(); Text(row.interval(.dose1ToDose2).minutes.map { String(format: "%.1f min D1–D2", $0) } ?? row.interval(.dose1ToDose2).state.rawValue) }
            }
        }
    }

    private var intervals: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Curated interval", selection: $preset) {
                ForEach(DashboardIntervalPreset.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("dashboard-interval-preset")
            Picker("Interval display", selection: $intervalMode) {
                ForEach(["By date", "Distribution", "Compare sleep"], id: \.self) { Text($0) }
            }.pickerStyle(.menu)
            Text("\(available.count) available / \(snapshots.count) selected sessions. Each interval uses its named occurrence endpoints; elapsed minutes are not sleep duration.").font(.caption)
            if preset == .dose1ToDose2 {
                Text("150–240 minutes: built-in reference only, inclusive boundaries; not a prescription or safety range. Shorter and longer observations remain separate.").font(.caption.bold())
            }
            if available.isEmpty { Text("No eligible pairs for this preset. Exact missing dependencies appear in the table.") }
            else if intervalMode == "Distribution" {
                Chart(bins.keys.sorted(), id: \.self) { bin in
                    BarMark(x: .value("Minutes", "\(bin * 30)–<\((bin + 1) * 30)"), y: .value("Sessions", bins[bin] ?? 0))
                        .foregroundStyle(palette.timing)
                }.frame(height: 220)
            } else if intervalMode == "Compare sleep" {
                Text("\(sleepPairCount) of \(available.count) interval pairs also have selected main-episode sleep from \(model.sleepSource.rawValue). Sleep availability is independent.").font(.caption)
                Chart(available, id: \.snapshot.sessionID) { pair in
                    if let night = model.populatedNights.first(where: { $0.replayID == pair.snapshot.sessionID }),
                       let sleep = model.sleepSource == .appleHealth ? night.appleHealthSleepMinutes : night.whoopSleepMinutes {
                        PointMark(x: .value("Interval minutes", pair.value), y: .value("Main sleep minutes", sleep))
                            .foregroundStyle(palette.sleep)
                    }
                }.frame(height: 240)
            } else {
                Chart(available, id: \.snapshot.sessionID) { pair in
                    PointMark(x: .value("Session", label(pair.snapshot)), y: .value("Minutes", pair.value))
                        .foregroundStyle(palette.timing)
                }.frame(height: 240)
            }
            Text("Exact interval table").font(.headline)
            ForEach(snapshots, id: \.sessionID) { snap in
                let result = snap.interval(preset)
                Button { selectedID = snap.sessionID } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label(snap)).font(.subheadline.bold())
                        Text(result.minutes.map { String(format: "%.2f minutes", $0) } ?? result.state.rawValue)
                        if let reference = result.referenceGroup { Text(reference).font(.caption.bold()) }
                        Text(result.reason).font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private func coveragePanel(_ snap: DashboardReplaySnapshot) -> some View {
        Text("Reviewed-window coverage").font(.headline)
        Text("This separately checked window does not replace the selected main-episode sleep total. Missing time is not awake time.").font(.caption)
        Button(coverage.isLoading ? "Checking coverage…" : "Check Apple Health coverage") {
            Task { await coverage.refresh(sessionDate: snap.treatmentDate) { _ in
                await model.replayCoverage(sessionID: snap.sessionID)
            } }
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
    private func label(_ snap: DashboardReplaySnapshot) -> String { "\(snap.treatmentDate) · \(snap.sessionID.suffix(6))" }
    private func amount(_ value: Double?) -> String { value.map { String(format: "%.1f min", $0) } ?? "unavailable" }
    private func move(_ delta: Int) {
        guard let index = selectedIndex, snapshots.indices.contains(index + delta) else { return }
        selectedID = snapshots[index + delta].sessionID
    }
    private func stamp(_ date: Date, _ snap: DashboardReplaySnapshot) -> String {
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: snap.timeZoneID)
        formatter.dateFormat = "MMM d HH:mm ZZZZZ"; return formatter.string(from: date)
    }
}

private struct ReplayExportPreview: View, Identifiable {
    let id = UUID()
    let snapshot: DashboardReplaySnapshot
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Selected session snapshot").font(.headline)
                    Text("Review the session, source, filters, exact endpoints and coverage before sharing. No notes or names are included. Later corrections require a new snapshot.")
                    Text(snapshot.csv).font(.caption.monospaced()).textSelection(.enabled)
                    ShareLink("Share CSV text", item: snapshot.csv)
                    if let data = try? snapshot.jsonData(), let json = String(data: data, encoding: .utf8) {
                        ShareLink("Share JSON snapshot", item: json)
                    }
                }.padding()
            }.navigationTitle("Export preview").toolbar { Button("Close") { dismiss() } }
        }
    }
}
