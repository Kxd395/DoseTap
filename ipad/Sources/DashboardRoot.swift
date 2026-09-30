import SwiftUI
import Charts
import DoseCore
import DoseTapNearby

struct DashboardRoot: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var connection: NearbyReportingSession
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var section = "Overview"
    @State private var range: DashboardReportingRange = .sixMonths
    @State private var inspection = DashboardInspectionState()
    @State private var period: PhysicianReportPeriod?
    @State private var rangeIssue: String?
    @State private var customRangePresented = false
    @State private var customStart = Date()
    @State private var customEnd = Date()
    @State private var reportTimeZone = TimeZone.current
    @State private var capturedReportKey: String?
    @State private var selectedNight: DashboardReportDoseDay?
    @State private var medicationSearch = ""
    private let sections = ["Overview", "Sleep & dose pattern", "Dose timing", "Apple Health evidence", "Sleep & check-ins", "Wake & sleepiness", "Medications", "Night review", "Report contents", "Connection"]
    private var diaryPoints: [DashboardDiaryPoint] {
        let dates = Set(selectedQuestionnaires.map(\.treatmentDate))
        return model.diary?.points.filter { dates.contains($0.treatmentDate) } ?? []
    }
    private var nights: [DashboardReportDoseDay] {
        guard let report = model.report else { return [] }
        return report.doseDays.filter { reportWindow?.contains($0.treatmentDate) == true }
    }

    var body: some View {
        NavigationSplitView {
            List(sections, id: \.self) { item in
                Button(item) { section = item }.foregroundStyle(section == item ? .teal : .primary)
            }
                .accessibilityIdentifier("dashboard-sidebar")
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
                        else if section == "Apple Health evidence", let snapshot = model.snapshot { AppleSleepEvidenceView(snapshot: snapshot) }
                        else {
                            if typeSize.isAccessibilitySize { rangePicker.pickerStyle(.menu) }
                            else { rangePicker.pickerStyle(.segmented) }
                            HStack {
                                Button("Custom period") {
                                    customEnd = report.capturedAt
                                    customStart = Calendar.current.date(byAdding: .day, value: -28, to: customEnd) ?? customEnd
                                    customRangePresented = true
                                }
                                Button("Since completed visit") { applyPeriod(.sinceCompletedVisit) }
                            }
                            if let rangeIssue { Text(rangeIssue).foregroundStyle(.red) }
                            Text(rangeDescription(capturedAt: report.capturedAt))
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("dashboard-report-range-span")
                            if section == "Sleep & dose pattern", let companion = model.companion {
                                companionFilters(companion)
                                CompanionSleepPatterns(report: companion, nights: visibleNights(companion), inspection: $inspection)
                            }
                            else if section == "Overview" { ReportOverview(report: report, nights: nights, diaryPoints: diaryPoints) { section = $0 } }
                            else if section == "Dose timing" { DoseTimingOverview(nights: nights) { selectedNight = $0 } }
                            else if section == "Wake & sleepiness" { DiaryOverview(points: diaryPoints, generation: model.diary?.sequence ?? 0) }
                            else if section == "Sleep & check-ins", let answers = model.questionnaires {
                                QuestionnaireOverview(days: selectedQuestionnaires,
                                                      unassignedSourceRowCount: answers.unassignedSourceRowCount)
                            } else { nightList }
                        }
                    } else {
                        ContentUnavailableView("Connect your iPhone", systemImage: "ipad.and.iphone", description: Text("Receive a read-only report from DoseTap. Your iPhone keeps control of logging and alarms."))
                        Button("Set up connection") { section = "Connection" }.buttonStyle(.borderedProminent)
                    }
                }.padding(28).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("dashboard-content").navigationTitle(section)
        }.tint(.teal)
            .onAppear { captureReportZone() }
            .onChange(of: model.snapshot?.sequence) { _, _ in captureReportZone() }
            .onChange(of: range) { _, value in if DashboardReportingRange.presetCases.contains(value) { period = nil; rangeIssue = nil } }
            .sheet(isPresented: $customRangePresented) {
                NavigationStack {
                    Form {
                        DatePicker("Start inclusive", selection: $customStart)
                        DatePicker("End exclusive", selection: $customEnd)
                        Text("The end must be no later than the saved report capture. Time zone: \(reportTimeZone.identifier).")
                        if let rangeIssue { Text(rangeIssue).foregroundStyle(.red) }
                        Button("Apply custom period") { if applyPeriod(.custom(start: customStart, endExclusive: customEnd)) { customRangePresented = false } }
                            .accessibilityIdentifier("companion-apply-period")
                    }.navigationTitle("Reporting period").toolbar { Button("Cancel") { customRangePresented = false } }
                }
            }
            .sheet(item: $selectedNight) { DoseNightDetail(night: $0) }
    }
    private func captureReportZone() {
        guard let snapshot = model.snapshot else { capturedReportKey = nil; period = nil; return }
        let key = "\(snapshot.sourceID):\(snapshot.sequence)"
        guard key != capturedReportKey else { return }
        capturedReportKey = key
        reportTimeZone = model.snapshot?.reportingTimeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
        if period != nil {
            period = nil
            rangeIssue = "A new reporting copy arrived. Recheck the custom or completed-visit period against its capture before using it."
        }
    }
    private var reportWindow: DashboardReportingWindow? {
        model.report.flatMap { range.window(asOf: $0.capturedAt, timeZone: reportTimeZone, reviewedPeriod: period) }
    }
    private var selectedQuestionnaires: [DashboardQuestionnaireDay] {
        model.questionnaires?.days.filter { reportWindow?.contains($0.treatmentDate) == true } ?? []
    }
    private func visibleNights(_ report: DashboardCompanionProjection) -> [DashboardCompanionProjection.Night] {
        report.visible(range: range, period: period, timeZone: reportTimeZone, inspection: inspection)
    }
    @discardableResult private func applyPeriod(_ selection: PhysicianReportRange) -> Bool {
        guard let report = model.companion else { return false }
        do {
            let resolved = try PhysicianReportPeriod.resolve(selection, ledger: report.completedVisits ?? PhysicianVisitLedger(), asOf: report.capturedAt, timeZone: reportTimeZone)
            period = resolved; range = resolved.completedVisitID == nil ? .custom : .sinceCompletedVisit
            rangeIssue = nil; return true
        } catch {
            rangeIssue = "The requested period is unavailable. Use valid bounds ending by report capture, or record a completed visit on the phone and refresh."
            return false
        }
    }
    private func companionFilters(_ report: DashboardCompanionProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Dose pattern filter", selection: $inspection.dosePatternFilter) {
                Text("All dose patterns").tag(Optional<DashboardDosePattern.Pattern>.none)
                ForEach(DashboardDosePattern.Pattern.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }.accessibilityIdentifier("companion-dose-filter")
            Picker("Work phase filter", selection: $inspection.workPhaseFilter) {
                Text("All work phases").tag(Optional<WorkPhase>.none)
                ForEach(WorkPhase.allCases, id: \.self) { Text($0.label).tag(Optional($0)) }
            }
            Button("Reset comparison filters") { inspection.resetFilters() }
            if let issue = report.workIssue, inspection.workPhaseFilter != nil { Text(issue).foregroundStyle(.orange) }
            let status = inspection.selectionStatus(visibleIDs: visibleNights(report).map(\.id), knownIDs: report.nights.map(\.id))
            if let explanation = status.explanation { Text(explanation).foregroundStyle(.orange) }
            Text("\(report.unassignedIdentityRowCount) unassigned source rows · Read-only; edit source records on the phone and refresh.").font(.caption)
        }
    }
    private var rangePicker: some View {
        Picker("Treatment dates", selection: $range) {
            ForEach(DashboardReportingRange.presetCases + ([.custom, .sinceCompletedVisit].contains(range) ? [range] : [])) { value in
                Text(value.rawValue).tag(value).accessibilityLabel(value.label)
            }
        }.accessibilityIdentifier("dashboard-report-range")
    }
    private func rangeDescription(capturedAt: Date) -> String {
        let zone = reportTimeZone
        guard let window = range.window(asOf: capturedAt, timeZone: zone, reviewedPeriod: period) else {
            return "Treatment-date range unavailable for this report."
        }
        let dates = window.firstTreatmentDate.map { "\($0) through \(window.lastTreatmentDate)" }
            ?? "All available dates through \(window.lastTreatmentDate)"
        return "Treatment dates: \(dates) · \(model.snapshot?.reportingTimeZoneID == nil ? "Legacy report: iPad zone fixed at load" : "Phone capture zone") · \(zone.identifier) · 18:00 rollover at report capture. Refresh to include later records."
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
            Text("DoseTap Dashboard \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"))")
                .font(.caption).foregroundStyle(.secondary)
        }.confirmationDialog("Remove this iPad’s reporting copy? Your iPhone records stay unchanged.", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget report", role: .destructive) { model.forgetReport() }
        }
    }
}
