import SwiftUI
import Charts
import DoseCore
import DoseTapNearby

struct DashboardRoot: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var connection: NearbyReportingSession
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var section = "Overview"
    @State private var days = 180
    @State private var selectedNight: DashboardReportDoseDay?
    @State private var medicationSearch = ""
    private let sections = ["Overview", "Medications", "Night review", "Report contents", "Connection"]
    private var nights: [DashboardReportDoseDay] {
        guard let report = model.report else { return [] }
        return DashboardReportStatistics.selected(report.doseDays, count: days,
            capturedAt: report.capturedAt, timeZone: .current)
    }

    var body: some View {
        NavigationSplitView {
            List(sections, id: \.self) { item in
                Button(item) { section = item }.foregroundStyle(section == item ? .teal : .primary)
            }
                .navigationTitle("DoseTap Dashboard")
            Text("Read-only companion").font(.footnote).foregroundStyle(.secondary).padding()
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = model.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("dashboard.error") }
                    Text("Saved reporting copy · \(String(describing: connection.state)) · Refresh manually")
                        .font(.footnote).foregroundStyle(.secondary)
                    if section == "Connection" { DashboardConnection(model: model, connection: model.connection) }
                    else if let report = model.report {
                        Text("Report captured \(report.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if section == "Medications" { medicationList(report) }
                        else if section == "Report contents", let snapshot = model.snapshot { ReportContentsView(snapshot: snapshot) }
                        else {
                            if typeSize.isAccessibilitySize { rangePicker.pickerStyle(.menu) }
                            else { rangePicker.pickerStyle(.segmented) }
                            Text("Treatment-night ranges use the 6 p.m. rollover at report capture in \(TimeZone.current.identifier). Refresh to include later records.")
                                .font(.caption).foregroundStyle(.secondary)
                            if section == "Overview" { DoseTimingOverview(nights: nights) { selectedNight = $0 } } else { nightList }
                        }
                    } else {
                        ContentUnavailableView("Connect your iPhone", systemImage: "ipad.and.iphone", description: Text("Receive a read-only report from DoseTap. Your iPhone keeps control of logging and alarms."))
                        Button("Set up connection") { section = "Connection" }.buttonStyle(.borderedProminent)
                    }
                }.padding(28).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
            }.navigationTitle(section)
        }.tint(.teal)
            .sheet(item: $selectedNight) { DoseNightDetail(night: $0) }
    }
    private var rangePicker: some View {
        Picker("Treatment dates", selection: $days) {
            ForEach([7, 30, 90, 180, 365, 0], id: \.self) { value in
                Text(value == 0 ? "All time" : value == 180 ? "6 months" : "\(value) days").tag(value)
            }
        }
    }
    private var nightList: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Text("Dates below are treatment-night dates, not medication calendar dates.").font(.footnote)
            if nights.isEmpty {
                ContentUnavailableView("No dose records in this range", systemImage: "calendar.badge.exclamationmark", description: Text("Widen the range or refresh the report from your iPhone."))
            }
            ForEach(nights) { night in
                Button { selectedNight = night } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) { Text(night.treatmentDate).bold(); Text(night.status).font(.subheadline).foregroundStyle(.secondary) }
                        Spacer(); Text(night.intervalMinutes.map(intervalText) ?? "Not calculable")
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(18).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityIdentifier("night-review-\(night.treatmentDate)")
            }
        }
    }
    private func medicationList(_ report: DashboardReportProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Text("All available medications, newest occurrence first. Calendar dates use the saved occurrence offset. Times below use this iPad’s current time zone (\(TimeZone.current.identifier)). Recorded time never substitutes for an unknown taken time.").font(.footnote)
            TextField("Filter medications by name", text: $medicationSearch).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("medication-filter")
            Text("\(filteredMedications(report).count) of \(report.medications.count) records · \(report.unknownMedicationTimeCount) with unknown taken time overall")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(filteredMedications(report)) { medication in
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(medication.name) · \(medication.amount)").font(.headline)
                        Text("Taken: \(medication.occurredAt?.formatted(date: .abbreviated, time: .shortened) ?? "Time unknown")")
                        Text("Occurrence calendar date: \(medication.calendarDate ?? "Not available") · \(medication.timePrecision)")
                        Text("\(medication.sourceTable == "medication_events" ? "Stored creation (may be import time)" : "Recorded"): \(medication.recordedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not available")").foregroundStyle(.secondary)
                        Text("Source: \(medication.sourceTable)").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
            }
        }
    }
    private func filteredMedications(_ report: DashboardReportProjection) -> [DashboardReportMedicationEntry] {
        let query = medicationSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return report.medications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }
}

struct DashboardConnection: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var connection: NearbyReportingSession
    @State private var confirmForget = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Nearby iPhone connection").font(.title2.bold())
            Text("On your iPhone, open Settings → Connect iPad Dashboard. Start nearby reporting. Select your phone below and accept its invitation. Then confirm the same six digits on both devices. Keep both apps open; no copying or typing is needed.")
            Text("Status: \(String(describing: connection.state))").font(.headline)
            if let message = connection.errorMessage { Text(message).foregroundStyle(.red) }
            if connection.state == .stopped || connection.state == .failed {
                Button("Find my iPhone") { connection.start() }.buttonStyle(.borderedProminent)
            }
            if connection.state == .discovering {
                if connection.discoveredPeers.isEmpty {
                    Text("No iPhone found yet. On your iPhone, open DoseTap → Settings → Data Management → Connect iPad Dashboard → Start nearby reporting. Allow Local Network access and keep both apps open nearby. Finding devices does not start sharing on the phone automatically.")
                }
                ForEach(connection.discoveredPeers, id: \.self) { peer in
                    Button("Connect to \(peer.displayName)") {
                        do { try connection.connect(to: peer) }
                        catch { model.presentConnectionError("Could not start the connection. Start discovery again.") }
                    }.buttonStyle(.bordered)
                }
                Text("Device names are discovery labels. Compare the six digits on both devices before confirming.").font(.footnote)
            }
            if let code = connection.pairingCode {
                Text(code).font(.system(.largeTitle, design: .monospaced)).bold().privacySensitive()
                Text("Do these six digits match the code on your iPhone?")
                Button("Codes match") { connection.confirmMatchingCode() }
                    .buttonStyle(.borderedProminent).disabled(connection.codeConfirmed)
                if connection.codeConfirmed { Text("Confirmed here. Confirm on the iPhone too.") }
                Button("Codes do not match", role: .destructive) { connection.stop() }
            }
            if connection.state == .paired { Button("Refresh report from iPhone") { model.request() }.buttonStyle(.borderedProminent) }
            if connection.state != .stopped { Button("End connection") { connection.stop() } }
            Text("This app stores a protected local reporting copy, excluded from backup. It cannot edit iPhone records, log a dose or operate alarms. Nearby refresh currently requires both apps in the foreground; background or cloud updates are not enabled.").font(.footnote).foregroundStyle(.secondary)
            Button("Forget downloaded report", role: .destructive) { confirmForget = true }
            Text("DoseTap Dashboard 0.1.0 (4)").font(.caption).foregroundStyle(.secondary)
        }.confirmationDialog("Remove this iPad’s reporting copy? Your iPhone records stay unchanged.", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget report", role: .destructive) { model.forgetReport() }
        }
    }
}
