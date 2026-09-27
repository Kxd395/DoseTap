import SwiftUI
import Charts
import DoseCore
import DoseTapNearby

struct DashboardRoot: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var connection: NearbyReportingSession
    @State private var section = "Overview"
    @State private var days = 180
    private let sections = ["Overview", "Medications", "Night review", "Connection"]
    private var nights: [DashboardReportDoseDay] {
        guard let report = model.report else { return [] }
        guard days > 0 else { return report.doseDays }
        let date = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date()
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let first = formatter.string(from: date), last = formatter.string(from: Date())
        return report.doseDays.filter { $0.treatmentDate >= first && $0.treatmentDate <= last }
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
                        else {
                            Picker("Treatment dates", selection: $days) {
                                ForEach([7, 30, 90, 180, 365, 0], id: \.self) { value in
                                    Text(value == 0 ? "All time" : value == 180 ? "6 months" : "\(value) days").tag(value)
                                }
                            }.pickerStyle(.segmented)
                            if section == "Overview" { overview(report) } else { nightList }
                        }
                    } else {
                        ContentUnavailableView("Connect your iPhone", systemImage: "ipad.and.iphone", description: Text("Receive a read-only report from DoseTap. Your iPhone keeps control of logging and alarms."))
                        Button("Set up connection") { section = "Connection" }.buttonStyle(.borderedProminent)
                    }
                }.padding(28).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
            }.navigationTitle(section)
        }.tint(.teal)
    }
    @ViewBuilder private func overview(_ report: DashboardReportProjection) -> some View {
        let usable = nights.compactMap(\.intervalMinutes).sorted()
        let median = usable.isEmpty ? nil : (usable[(usable.count - 1) / 2] + usable[usable.count / 2]) / 2
        ViewThatFits(in: .horizontal) {
            HStack { metric("Dates with dose records", "\(nights.count)"); metric("Usable dose pairs", "\(usable.count)"); metric("Median recorded spacing", median.map(duration) ?? "Not available") }
            VStack { metric("Dates with dose records", "\(nights.count)"); metric("Usable dose pairs", "\(usable.count)"); metric("Median recorded spacing", median.map(duration) ?? "Not available") }
        }
        GroupBox("Recorded Dose 1 → Dose 2 spacing") {
            if usable.isEmpty { Text("No unambiguous positive pairs in this range.").padding() }
            else {
                Chart(nights.reversed()) { night in
                    if let minutes = night.intervalMinutes {
                        PointMark(x: .value("Treatment date", night.treatmentDate), y: .value("Minutes", minutes))
                            .accessibilityLabel("\(night.treatmentDate): \(duration(minutes))")
                    }
                }.chartYAxisLabel("Elapsed minutes").chartXAxis(.hidden).frame(height: 260).padding()
                Text("\(nights.last?.treatmentDate ?? "") through \(nights.first?.treatmentDate ?? "") · \(usable.count) usable pairs of \(nights.count) recorded dates")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Text("Spacing uses reported occurrence times. Missing, skipped and conflicting pairs are excluded. This chart describes recorded timing, not medication effectiveness or dosing advice.").font(.footnote)
        GroupBox("Available reporting evidence") {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(report.medications.count) medication records across all available dates; \(report.unknownMedicationTimeCount) have unknown occurrence time.")
                Text("Apple Health and WHOOP measurements are not included in this first nearby report. No sleep averages are inferred from medication logs.")
                Text("Questionnaire and event source records are retained in the report. Additional verified summaries will be added separately.")
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading) { Text(label).font(.subheadline); Text(value).font(.title2.bold()).foregroundStyle(.teal) }
            .frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }
    private var nightList: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Text("Dates below are treatment-night dates, not medication calendar dates.").font(.footnote)
            ForEach(nights) { night in
                GroupBox {
                    HStack { VStack(alignment: .leading) { Text(night.treatmentDate).bold(); Text(night.status).foregroundStyle(.secondary) }; Spacer(); Text(night.intervalMinutes.map(duration) ?? "Not calculable") }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
            }
        }
    }
    private func medicationList(_ report: DashboardReportProjection) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Text("All available medications, newest occurrence first. Calendar dates use the saved occurrence offset. Times below use this iPad’s current time zone (\(TimeZone.current.identifier)). Recorded time never substitutes for an unknown taken time.").font(.footnote)
            ForEach(report.medications) { medication in
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
    private func duration(_ minutes: Double) -> String { let value = Int(minutes.rounded()); return "\(value / 60)h \(value % 60)m" }
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
            Text("DoseTap Dashboard 0.1.0 (3)").font(.caption).foregroundStyle(.secondary)
        }.confirmationDialog("Remove this iPad’s reporting copy? Your iPhone records stay unchanged.", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget report", role: .destructive) { model.forgetReport() }
        }
    }
}
