import SwiftUI
import DoseCore
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

// UserSettingsManager and AppearanceMode are defined in UserSettingsManager.swift

private enum SettingsExportFormat: String, CaseIterable {
    case csv = "CSV"
    case json = "JSON"

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        }
    }

    var description: String {
        switch self {
        case .csv: return "Spreadsheet-friendly table export"
        case .json: return "Structured export for tooling and automation"
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @StateObject private var settings = UserSettingsManager.shared
    @StateObject private var whoopService = WHOOPService.shared
    @ObservedObject private var alarmService = AlarmService.shared
    @AppStorage(SetupWizardService.setupCompletedKey) private var setupCompleted = true
    @State private var showingResetConfirmation = false
    @State private var showingSetupWizardConfirmation = false
    @State private var showingExportSuccess = false
    @State private var showingExportSheet = false
    @State private var showingExportConfigurator = false
    @State private var isExportingData = false
    @State private var exportURL: URL?
    @State private var exportSuccessMessage = "Your data was exported."
    @State private var exportErrorMessage: String?
    @State private var notificationPermissionMessage: String?
    @State private var selectedExportFormat: SettingsExportFormat = .csv
    @State private var redactSensitiveExportData = true
    @State private var exportPreviewText = ""
    @State private var exportEstimatedBytes = 0
    @State private var exportEstimatedRecords = 0
    @State private var isPreparingExportPreview = false
    @ObservedObject private var urlRouter = URLRouter.shared
    @ObservedObject private var sleepPlanStore = SleepPlanStore.shared
    private let tabBarInsetHeight: CGFloat = 64
    
    var body: some View {
        NavigationView {
            List {
                // MARK: - Dose & Timing (Most Important)
                Section {
                    targetIntervalPicker
                    
                    NavigationLink {
                        WeeklyPlannerView()
                    } label: {
                        HStack {
                            Label("Weekly Planner", systemImage: "calendar.badge.clock")
                            Spacer()
                            if let target = WeeklyPlanner.shared.todayTarget() {
                                Text("\(target) min today")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    undoSpeedPicker
                    
                    // Info card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("XYWAV Dose Window")
                                .font(.subheadline.bold())
                        }
                        Text("• Window opens at 150 min after Dose 1")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Window closes at 240 min (hard limit)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Snooze disabled when <15 min remain")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("• Max snoozes: \(settings.maxSnoozes) per night")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Dose & Timing", systemImage: "timer")
                        .font(.headline)
                } footer: {
                    Text("Configure when you'll be reminded to take Dose 2, and how long you have to undo actions.")
                }

                // MARK: - Night Schedule
                Section {
                    DatePicker("Default Sleep Start", selection: sleepStartBinding, displayedComponents: .hourAndMinute)
                    DatePicker("Default Wake Time", selection: wakeTimeBinding, displayedComponents: .hourAndMinute)

                    NavigationLink {
                        SleepPlanDetailView()
                    } label: {
                        HStack {
                            Label("Weekly Wake Setup", systemImage: "calendar.badge.clock")
                            Spacer()
                            Text(weeklyScheduleSummary)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle("After check-in, show upcoming night", isOn: $settings.plannerUsesUpcomingNightAfterCheckIn)

                    DisclosureGroup("Evening Prep & Auto-Close") {
                        DatePicker("Prep Time", selection: prepTimeBinding, displayedComponents: .hourAndMinute)
                        Stepper("Missed check-in cutoff +\(settings.missedCheckInCutoffHours)h", value: $settings.missedCheckInCutoffHours, in: 1...12)
                        Text("Auto-close at \(cutoffTimeText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Night Schedule", systemImage: "moon.stars.fill")
                        .font(.headline)
                } footer: {
                    Text("Default times control session rollover. Enable upcoming-night mode if you want Tonight to flip to the next day right after morning check-in.")
                }
                
                // MARK: - Notifications
                Section {
                    Toggle(isOn: $settings.notificationsEnabled) {
                        Label("Enable Notifications", systemImage: "bell.fill")
                    }
                    
                    if settings.notificationsEnabled {
                        Toggle(isOn: $settings.criticalAlertsEnabled) {
                            Label("Critical Alerts", systemImage: "exclamationmark.triangle.fill")
                        }
                        .tint(.red)
                        
                        Toggle(isOn: $settings.windowOpenAlert) {
                            Label("Window Open (150 min)", systemImage: "door.left.hand.open")
                        }
                        
                        Toggle(isOn: $settings.fifteenMinWarning) {
                            Label("15 Min Warning", systemImage: "clock.badge.exclamationmark")
                        }
                        
                        Toggle(isOn: $settings.fiveMinWarning) {
                            Label("5 Min Warning", systemImage: "exclamationmark.circle")
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $settings.soundEnabled) {
                            Label("Sound", systemImage: "speaker.wave.2.fill")
                        }
                        
                        Toggle(isOn: $settings.hapticsEnabled) {
                            Label("Haptics", systemImage: "waveform")
                        }
                    }
                } header: {
                    Label("Notifications & Alerts", systemImage: "bell.badge.fill")
                        .font(.headline)
                } footer: {
                    Text("Critical alerts can override Do Not Disturb for important dose reminders.")
                }
                
                // MARK: - Sleep Planning
                Section {
                    NavigationLink {
                        SleepPlanDetailView()
                    } label: {
                        HStack {
                            Label("Typical Week Schedule", systemImage: "calendar.badge.clock")
                            Spacer()
                            Text("Configure")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    SleepPlanSettingsRow(
                        title: "Target Sleep",
                        minutes: sleepPlanStore.settings.targetSleepMinutes,
                        step: 30,
                        range: 300...600
                    ) { newValue in
                        sleepPlanStore.updateSettings(targetSleepMinutes: newValue)
                    }
                    
                    SleepPlanSettingsRow(
                        title: "Sleep Latency",
                        minutes: sleepPlanStore.settings.sleepLatencyMinutes,
                        step: 5,
                        range: 0...120
                    ) { newValue in
                        sleepPlanStore.updateSettings(sleepLatencyMinutes: newValue)
                    }
                    
                    SleepPlanSettingsRow(
                        title: "Wind Down",
                        minutes: sleepPlanStore.settings.windDownMinutes,
                        step: 5,
                        range: 0...120
                    ) { newValue in
                        sleepPlanStore.updateSettings(windDownMinutes: newValue)
                    }
                } header: {
                    Label("Sleep Planning", systemImage: "bed.double.fill")
                        .font(.headline)
                } footer: {
                    Text("Set your typical wake times and sleep goals. These feed the Tonight planner and do not change the dose window.")
                }
                
                // MARK: - Appearance
                Section {
                    NavigationLink {
                        ThemeSettingsView()
                    } label: {
                        HStack {
                            Label("Theme", systemImage: "paintpalette.fill")
                            Spacer()
                            Text(ThemeManager.shared.currentTheme.rawValue)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    appearancePicker
                    
                    Toggle(isOn: $settings.highContrastMode) {
                        Label("High Contrast", systemImage: "circle.lefthalf.striped.horizontal")
                    }
                    
                    Toggle(isOn: $settings.reducedMotion) {
                        Label("Reduce Motion", systemImage: "figure.walk")
                    }
                } header: {
                    Label("Appearance", systemImage: "paintbrush.fill")
                } footer: {
                    Text("Night Mode uses red/amber tones to reduce blue light exposure and protect your sleep cycle.")
                }
                
                // MARK: - Medications
                Section {
                    NavigationLink {
                        MedicationSettingsView()
                    } label: {
                        HStack {
                            Label("My Medications", systemImage: "pills.fill")
                            Spacer()
                            Text(medicationSummary)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("Medications", systemImage: "cross.case.fill")
                } footer: {
                    Text("Configure which medications you take and default doses.")
                }
                
                // MARK: - Event Logging
                Section {
                    NavigationLink {
                        QuickLogCustomizationView()
                    } label: {
                        HStack {
                            Label("QuickLog Buttons", systemImage: "square.grid.2x2")
                            Spacer()
                            Text("\(settings.quickLogButtons.count)/16")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    NavigationLink {
                        EventCooldownSettingsView()
                    } label: {
                        HStack {
                            Label("Event Cooldowns", systemImage: "timer")
                            Spacer()
                            Text("Customize")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("Event Logging", systemImage: "list.bullet.clipboard")
                } footer: {
                    Text("Customize which events appear in your quick log grid and how often you can log them.")
                }
                
                // MARK: - Integrations
                Section {
                    NavigationLink {
                        HealthKitSettingsView()
                    } label: {
                        HStack {
                            Label("Apple Health", systemImage: "heart.fill")
                            Spacer()
                            if settings.healthKitEnabled {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    NavigationLink {
                        InstallHealthCheckView()
                    } label: {
                        Label("Install Health Check", systemImage: "checklist")
                    }

                    NavigationLink {
                        WHOOPSettingsView()
                    } label: {
                        HStack {
                            Label("WHOOP", systemImage: "figure.run")
                            Spacer()
                            if whoopService.isConnected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                } header: {
                    Label("Integrations", systemImage: "link")
                } footer: {
                    Text("Connect Apple Health and WHOOP to sync sleep data and view integrated insights.")
                }
                
                // MARK: - Data Management
                Section {
                    Button {
                        showingExportConfigurator = true
                        Task { await refreshExportPreview() }
                    } label: {
                        HStack {
                            Label("Export Data", systemImage: "square.and.arrow.up")
                            if isExportingData {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isExportingData)
                    
                    NavigationLink {
                        DiagnosticExportView()
                    } label: {
                        Label("Export Session Diagnostics", systemImage: "doc.text.magnifyingglass")
                    }
                    
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        Label("Manage History", systemImage: "clock.arrow.circlepath")
                    }

                    Button {
                        showingSetupWizardConfirmation = true
                    } label: {
                        Label("Run Setup Wizard Again", systemImage: "wand.and.stars")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Clear All Data", systemImage: "trash.fill")
                    }
                } header: {
                    Label("Data Management", systemImage: "externaldrive.fill")
                } footer: {
                    Text("Export your data for backup or analysis. All data is stored locally on your device only.")
                }
                
                // MARK: - Privacy & Diagnostics
                Section {
                    Toggle(isOn: $settings.analyticsEnabled) {
                        Label("Anonymous Analytics", systemImage: "chart.bar.fill")
                    }
                    
                    Toggle(isOn: $settings.crashReportsEnabled) {
                        Label("Crash Reports", systemImage: "ant.fill")
                    }
                    
                    NavigationLink {
                        DiagnosticLoggingSettingsView()
                    } label: {
                        HStack {
                            Label("Diagnostic Logging", systemImage: "stethoscope")
                            Spacer()
                            if settings.diagnosticLoggingEnabled {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                } header: {
                    Label("Privacy & Diagnostics", systemImage: "hand.raised.fill")
                } footer: {
                    Text("No personal health data is ever transmitted. Diagnostic logs are stored locally for troubleshooting.")
                }
                
                // MARK: - About
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Label("Build", systemImage: "hammer")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About DoseTap", systemImage: "questionmark.circle")
                    }
                } header: {
                    Label("About", systemImage: "info.circle.fill")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                // Add padding to prevent tab bar from covering content
                Color.clear.frame(height: tabBarInsetHeight)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Navigate back to Tonight tab
                        withAnimation {
                            urlRouter.selectedTab = 0
                        }
                    }
                }
            }
        }
        .alert("Clear All Data", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This will permanently delete all your dose history, sleep events, and settings. This action cannot be undone.")
        }
        .alert("Run Setup Wizard Again", isPresented: $showingSetupWizardConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Continue", role: .destructive) {
                rerunSetupWizard()
            }
        } message: {
            Text("This will reopen the setup wizard and re-check install configuration.")
        }
        .alert("Export Complete", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportSuccessMessage)
        }
        .sheet(isPresented: $showingExportSheet, onDismiss: {
            cleanupExportFile()
        }) {
            if let url = exportURL {
                ExportActivityViewController(activityItems: [url]) { completed, error in
                    handleExportShareCompletion(completed: completed, error: error)
                }
            }
        }
        .sheet(isPresented: $showingExportConfigurator) {
            exportConfigurationSheet
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("Retry") {
                Task { await exportData() }
            }
            Button("Cancel", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "Unable to export data.")
        }
        .alert("Notification Permission", isPresented: Binding(
            get: { notificationPermissionMessage != nil },
            set: { if !$0 { notificationPermissionMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                notificationPermissionMessage = nil
            }
        } message: {
            Text(notificationPermissionMessage ?? "Notifications are unavailable.")
        }
        .onChange(of: settings.notificationsEnabled) { enabled in
            Task { await handleNotificationToggle(enabled) }
        }
        .onChange(of: settings.criticalAlertsEnabled) { enabled in
            guard settings.notificationsEnabled else { return }
            Task { await handleCriticalAlertToggle(enabled) }
        }
        .onChange(of: settings.windowOpenAlert) { _ in
            Task { await resyncDose2RemindersIfNeeded() }
        }
        .onChange(of: settings.fifteenMinWarning) { _ in
            Task { await resyncDose2RemindersIfNeeded() }
        }
        .onChange(of: settings.fiveMinWarning) { _ in
            Task { await resyncDose2RemindersIfNeeded() }
        }
        .onChange(of: settings.soundEnabled) { _ in
            Task { await applyNotificationConfigLive() }
        }
        .onChange(of: settings.hapticsEnabled) { _ in
            refreshActiveRingingFeedback()
        }
    }

    // MARK: - Night Schedule Bindings
    private var sleepStartBinding: Binding<Date> {
        Binding(
            get: { settings.dateFromMinutes(settings.sleepStartMinutes) },
            set: { settings.sleepStartMinutes = settings.minutesFromDate($0) }
        )
    }

    private var wakeTimeBinding: Binding<Date> {
        Binding(
            get: { settings.dateFromMinutes(settings.wakeTimeMinutes) },
            set: { settings.wakeTimeMinutes = settings.minutesFromDate($0) }
        )
    }

    private var prepTimeBinding: Binding<Date> {
        Binding(
            get: { settings.dateFromMinutes(settings.prepTimeMinutes) },
            set: { settings.prepTimeMinutes = settings.minutesFromDate($0) }
        )
    }

    private var cutoffTimeText: String {
        let wake = settings.dateFromMinutes(settings.wakeTimeMinutes)
        let cutoff = Calendar.current.date(byAdding: .hour, value: settings.missedCheckInCutoffHours, to: wake) ?? wake
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: cutoff)
    }

    private var weeklyScheduleSummary: String {
        let entries = sleepPlanStore.schedule.entries
        let enabledEntries = entries.filter(\.enabled)
        let uniqueTimes = Set(enabledEntries.map { "\($0.wakeByHour):\($0.wakeByMinute)" })

        switch uniqueTimes.count {
        case 0:
            return "No days enabled"
        case 1:
            return "\(enabledEntries.count)d same"
        default:
            return "\(enabledEntries.count)d custom"
        }
    }

    // MARK: - Appearance Picker
    private var appearancePicker: some View {
        HStack {
            Label("Theme", systemImage: settings.appearanceMode.icon)
            Spacer()
            Menu {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button {
                        settings.appearanceMode = mode
                    } label: {
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                            if settings.appearanceMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(settings.appearanceMode.rawValue)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Target Interval Picker
    private var targetIntervalPicker: some View {
        HStack {
            Label("Target Interval", systemImage: "target")
            Spacer()
            Menu {
                ForEach(settings.validTargetOptions, id: \.self) { minutes in
                    Button {
                        settings.targetIntervalMinutes = minutes
                    } label: {
                        HStack {
                            Text(formatInterval(minutes))
                            if settings.targetIntervalMinutes == minutes {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(formatInterval(settings.targetIntervalMinutes))
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Undo Speed Picker
    private var undoSpeedPicker: some View {
        HStack {
            Label("Undo Window", systemImage: "timer")
            Spacer()
            Menu {
                ForEach(settings.validUndoWindowOptions, id: \.self) { seconds in
                    Button {
                        settings.undoWindowSeconds = seconds
                    } label: {
                        HStack {
                            Text(formatUndoWindow(seconds))
                            if settings.undoWindowSeconds == seconds {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(formatUndoWindow(settings.undoWindowSeconds))
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Medication Summary
    private var medicationSummary: String {
        let meds = settings.userMedications
        if meds.isEmpty {
            return "None"
        } else if meds.count == 1 {
            return medicationDisplayName(meds[0])
        } else {
            return "\(meds.count) medications"
        }
    }
    
    private func medicationDisplayName(_ id: String) -> String {
        switch id {
        case "adderall_ir": return "Adderall IR"
        case "adderall_xr": return "Adderall XR"
        default: return id
        }
    }
    
    // MARK: - Helper Methods
    private func formatInterval(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m (\(minutes) min)"
    }
    
    private func formatUndoWindow(_ seconds: Double) -> String {
        let intSeconds = Int(seconds)
        if intSeconds == 3 {
            return "Fast (3s)"
        } else if intSeconds == 5 {
            return "Normal (5s)"
        } else if intSeconds == 7 {
            return "Slow (7s)"
        } else {
            return "Very Slow (10s)"
        }
    }
    
    private func requestHealthKitPermissions() {
        // In real app, this would request HealthKit authorization
        print("Requesting HealthKit permissions...")
    }

    private var exportConfigurationSheet: some View {
        NavigationView {
            Form {
                Section("Format") {
                    Picker("Format", selection: $selectedExportFormat) {
                        ForEach(SettingsExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(selectedExportFormat.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Privacy") {
                    Toggle("Redact sensitive identifiers", isOn: $redactSensitiveExportData)
                    Text("When enabled, timestamps, UUIDs, and email-like strings are masked in the shared export.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Estimated Size") {
                    HStack {
                        Label("File Size", systemImage: "internaldrive")
                        Spacer()
                        if isPreparingExportPreview {
                            ProgressView()
                        } else {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(exportEstimatedBytes), countStyle: .file))
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Label("Records", systemImage: "number")
                        Spacer()
                        Text("\(exportEstimatedRecords)")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Redaction Preview") {
                    if isPreparingExportPreview {
                        ProgressView("Building preview...")
                    } else if exportPreviewText.isEmpty {
                        Text("No preview available yet.")
                            .foregroundColor(.secondary)
                    } else {
                        Text(exportPreviewText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingExportConfigurator = false
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await exportData()
                            if exportErrorMessage == nil {
                                showingExportConfigurator = false
                            }
                        }
                    } label: {
                        if isExportingData {
                            ProgressView()
                        } else {
                            Text("Share")
                        }
                    }
                    .disabled(isExportingData || isPreparingExportPreview || exportEstimatedRecords == 0)
                }
            }
        }
        .onAppear {
            Task { await refreshExportPreview() }
        }
        .onChange(of: selectedExportFormat) { _ in
            Task { await refreshExportPreview() }
        }
        .onChange(of: redactSensitiveExportData) { _ in
            Task { await refreshExportPreview() }
        }
    }

    private func exportData() async {
        await exportData(format: selectedExportFormat, redactSensitive: redactSensitiveExportData)
    }

    private func exportData(format: SettingsExportFormat, redactSensitive: Bool) async {
        guard !isExportingData else { return }
        isExportingData = true
        defer { isExportingData = false }
        exportErrorMessage = nil
        cleanupExportFile()

        let exportBuild = buildExportContent(format: format, redactSensitive: redactSensitive)
        guard exportBuild.recordCount > 0 else {
            exportErrorMessage = "No exportable history yet. Log at least one session before exporting."
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "DoseTap_Export_\(DateFormatter.exportDateFormatter.string(from: Date())).\(format.fileExtension)"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try exportBuild.content.write(to: fileURL, atomically: true, encoding: .utf8)
            exportURL = fileURL
            showingExportSheet = true
            print("✅ Export file created: \(fileURL.lastPathComponent)")
        } catch {
            print("❌ Failed to create export file: \(error)")
            exportErrorMessage = "Could not write export file. \(error.localizedDescription)"
        }
    }

    private func refreshExportPreview() async {
        isPreparingExportPreview = true
        defer { isPreparingExportPreview = false }

        let exportBuild = buildExportContent(
            format: selectedExportFormat,
            redactSensitive: redactSensitiveExportData
        )
        exportEstimatedBytes = exportBuild.byteCount
        exportEstimatedRecords = exportBuild.recordCount
        exportPreviewText = previewText(for: exportBuild.content, format: selectedExportFormat)
    }

    private func buildExportContent(
        format: SettingsExportFormat,
        redactSensitive: Bool
    ) -> (content: String, byteCount: Int, recordCount: Int) {
        let rawContent: String
        let recordCount: Int

        switch format {
        case .csv:
            let csvContent = SessionRepository.shared.exportToCSVv2()
            rawContent = csvContent
            recordCount = max(0, csvContent.split(whereSeparator: \.isNewline).count - 1)
        case .json:
            let document = buildJSONExportDocument()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = (try? encoder.encode(document)) ?? Data()
            rawContent = String(data: data, encoding: .utf8) ?? "{}"
            recordCount = document.sessions.count + document.sleepEvents.count
        }

        let finalContent = redactSensitive ? redactSensitiveData(in: rawContent) : rawContent
        let byteCount = finalContent.lengthOfBytes(using: .utf8)
        return (finalContent, byteCount, recordCount)
    }

    private func buildJSONExportDocument() -> SettingsJSONExportDocument {
        let repo = SessionRepository.shared
        let sessions = repo.fetchRecentSessions(days: 365).map { session in
            SettingsJSONExportSession(
                sessionDate: session.sessionDate,
                dose1Time: session.dose1Time,
                dose2Time: session.dose2Time,
                dose2Skipped: session.dose2Skipped,
                snoozeCount: session.snoozeCount,
                intervalMinutes: session.intervalMinutes,
                eventCount: session.eventCount
            )
        }
        let sleepEvents = repo.fetchAllSleepEvents(limit: 10_000).map { event in
            SettingsJSONExportSleepEvent(
                id: event.id,
                eventType: event.eventType,
                timestamp: event.timestamp,
                sessionDate: event.sessionDate,
                notes: event.notes
            )
        }

        return SettingsJSONExportDocument(
            generatedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            sessions: sessions,
            sleepEvents: sleepEvents
        )
    }

    private func redactSensitiveData(in content: String) -> String {
        var redacted = DataRedactor(config: .default).redact(content).redactedText
        redacted = redacted.replacingOccurrences(
            of: #"\d{4}-\d{2}-\d{2}[T\s]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})"#,
            with: "[redacted-timestamp]",
            options: [.regularExpression]
        )
        return redacted
    }

    private func previewText(for content: String, format: SettingsExportFormat) -> String {
        let maxLines = format == .csv ? 8 : 16
        let lines = content.components(separatedBy: .newlines)
            .prefix(maxLines)
            .joined(separator: "\n")
        if lines.isEmpty {
            return "No preview available."
        }
        return lines
    }

    private func handleExportShareCompletion(completed: Bool, error: Error?) {
        let fileName = exportURL?.lastPathComponent ?? "DoseTap export file"

        if let error {
            exportErrorMessage = "Export file was created but sharing failed. \(error.localizedDescription)"
        } else if completed {
            exportSuccessMessage = "Shared \(fileName) successfully."
            showingExportSuccess = true
        }
    }

    private func cleanupExportFile() {
        guard let url = exportURL else { return }
        try? FileManager.default.removeItem(at: url)
        exportURL = nil
    }

    private func handleNotificationToggle(_ enabled: Bool) async {
        if enabled {
            let granted = await AlarmService.shared.requestPermission()
            if !granted {
                settings.notificationsEnabled = false
                notificationPermissionMessage = "iOS notification permission is denied. Enable notifications in system settings to receive dose reminders."
            } else {
                await applyNotificationConfigLive()
            }
            return
        }

        AlarmService.shared.stopRinging(acknowledge: false)
        AlarmService.shared.cancelAllAlarms()
    }

    private func handleCriticalAlertToggle(_ enabled: Bool) async {
        if enabled {
            let granted = await AlarmService.shared.requestPermission()
            if !granted {
                settings.criticalAlertsEnabled = false
                notificationPermissionMessage = "Critical alerts were not granted. Standard alerts will be used when available."
                return
            }
        }
        await applyNotificationConfigLive()
    }

    private func applyNotificationConfigLive() async {
        refreshActiveRingingFeedback()
        await resyncWakeAlarmIfNeeded()
        await resyncDose2RemindersIfNeeded()
    }

    private func refreshActiveRingingFeedback() {
        guard alarmService.isAlarmRinging else { return }
        alarmService.stopRinging(acknowledge: false)
        if settings.soundEnabled || settings.hapticsEnabled {
            alarmService.startRinging()
        }
    }

    private func resyncWakeAlarmIfNeeded() async {
        guard settings.notificationsEnabled else { return }
        guard let targetWakeTime = alarmService.targetWakeTime else { return }
        guard targetWakeTime > Date(), let dose1Time = SessionRepository.shared.dose1Time else { return }
        await alarmService.scheduleWakeAlarm(at: targetWakeTime, dose1Time: dose1Time)
    }

    private func resyncDose2RemindersIfNeeded() async {
        guard settings.notificationsEnabled else { return }
        let repo = SessionRepository.shared
        guard let dose1Time = repo.dose1Time else { return }
        guard repo.dose2Time == nil, !repo.dose2Skipped else { return }
        alarmService.cancelDose2Reminders()
        await alarmService.scheduleDose2Reminders(dose1Time: dose1Time)
    }

    private func rerunSetupWizard() {
        setupCompleted = false
    }
    
    private func clearAllData() {
        // Clear all data sources - SSOT pattern
        #if DEBUG
        print("🗑️ Clearing all data...")
        #endif
        
        // 1. Clear EventStorage (database)
        SessionRepository.shared.clearAllData()
        
        // 2. Clear UserDefaults
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }
        
        // 3. Reset UserSettingsManager to defaults
        settings.resetToDefaults()
        
        // 4. Clear SleepPlanStore
        sleepPlanStore.resetToDefaults()
        
        // 5. Reload SessionRepository to reflect cleared state
        SessionRepository.shared.reload()
        
        #if DEBUG
        print("✅ All data cleared successfully")
        #endif
    }
}

private struct SettingsJSONExportDocument: Codable {
    let generatedAt: Date
    let appVersion: String
    let sessions: [SettingsJSONExportSession]
    let sleepEvents: [SettingsJSONExportSleepEvent]
}

private struct SettingsJSONExportSession: Codable {
    let sessionDate: String
    let dose1Time: Date?
    let dose2Time: Date?
    let dose2Skipped: Bool
    let snoozeCount: Int
    let intervalMinutes: Int?
    let eventCount: Int
}

private struct SettingsJSONExportSleepEvent: Codable {
    let id: String
    let eventType: String
    let timestamp: Date
    let sessionDate: String
    let notes: String?
}

private enum InstallCheckState: Equatable {
    case pass
    case warning
    case fail

    var color: Color {
        switch self {
        case .pass: return .green
        case .warning: return .orange
        case .fail: return .red
        }
    }

    var icon: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        }
    }
}

private struct InstallCheckItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let state: InstallCheckState
}

struct InstallHealthCheckView: View {
    @AppStorage(SetupWizardService.setupCompletedKey) private var setupCompleted = false
    @ObservedObject private var appSettings = UserSettingsManager.shared
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @ObservedObject private var alarmService = AlarmService.shared
    @ObservedObject private var healthKit = HealthKitService.shared
    @Environment(\.openURL) private var openURL

    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var criticalAlertSetting: UNNotificationSetting = .notSupported
    @State private var pendingDoseTapNotificationCount = 0
    @State private var pendingWakeNotificationCount = 0
    @State private var isRefreshing = false
    @State private var lastCheckedAt: Date?
    @State private var actionStatusMessage: String?

    var body: some View {
        List {
            Section("Overall") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Install Readiness")
                        Spacer()
                        Text("\(passingChecks)/\(checkItems.count)")
                            .font(.headline)
                    }
                    ProgressView(value: checkScore)
                    if let lastCheckedAt {
                        Text("Last checked \(relativeTimeText(for: lastCheckedAt))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    Task { await refreshChecks() }
                } label: {
                    HStack {
                        Label("Run Health Check", systemImage: "arrow.clockwise")
                        if isRefreshing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRefreshing)
            }

            Section("Checks") {
                ForEach(checkItems) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.state.icon)
                            .foregroundColor(item.state.color)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Text(item.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Actions") {
                Button("Open iOS Settings") {
                    openSystemSettings()
                }
                Button {
                    Task { await runNotificationAutoRepair() }
                } label: {
                    HStack {
                        Label("Run Auto-Repair", systemImage: "wrench.and.screwdriver")
                        if isRefreshing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRefreshing)
                Button {
                    Task { await sendTestReminder() }
                } label: {
                    Label("Send Test Reminder", systemImage: "bell.badge")
                }
                .disabled(isRefreshing)
                Button("Run Setup Wizard Again") {
                    setupCompleted = false
                }
            }
        }
        .navigationTitle("Install Health Check")
        .alert("Install Health Check", isPresented: Binding(
            get: { actionStatusMessage != nil },
            set: { if !$0 { actionStatusMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                actionStatusMessage = nil
            }
        } message: {
            Text(actionStatusMessage ?? "")
        }
        .onAppear {
            Task { await refreshChecks() }
        }
    }

    private var checkItems: [InstallCheckItem] {
        [
            checkSetupCompletion,
            checkNotifications,
            checkNotificationQueue,
            checkCriticalAlerts,
            checkReminderCoverage,
            checkHealthKitAvailability,
            checkHealthKitPermission,
            checkHealthDataFreshness,
            checkBackgroundRefresh,
            checkTimeZone
        ]
    }

    private var passingChecks: Int {
        checkItems.filter { $0.state == .pass }.count
    }

    private var checkScore: Double {
        guard !checkItems.isEmpty else { return 0 }
        return Double(passingChecks) / Double(checkItems.count)
    }

    private var checkSetupCompletion: InstallCheckItem {
        if setupCompleted {
            return InstallCheckItem(
                id: "setup_completed",
                title: "Setup wizard completed",
                detail: "Install flow has been completed on this device.",
                state: .pass
            )
        }
        return InstallCheckItem(
            id: "setup_incomplete",
            title: "Setup wizard incomplete",
            detail: "DoseTap install setup has not been completed.",
            state: .fail
        )
    }

    private var checkNotifications: InstallCheckItem {
        let authorized = notificationAuthorizationStatus == .authorized || notificationAuthorizationStatus == .provisional
        if appSettings.notificationsEnabled && authorized {
            return InstallCheckItem(
                id: "notifications_ok",
                title: "Notifications",
                detail: "Enabled in app and granted by iOS.",
                state: .pass
            )
        }
        if !appSettings.notificationsEnabled {
            return InstallCheckItem(
                id: "notifications_disabled_app",
                title: "Notifications disabled in app",
                detail: "Dose reminders are currently disabled in Settings.",
                state: .warning
            )
        }
        return InstallCheckItem(
            id: "notifications_denied_ios",
            title: "Notifications denied by iOS",
            detail: "Enable notifications in iOS Settings to receive reminders.",
            state: .fail
        )
    }

    private var checkNotificationQueue: InstallCheckItem {
        if !appSettings.notificationsEnabled && pendingDoseTapNotificationCount == 0 {
            return InstallCheckItem(
                id: "queue_off_clean",
                title: "Notification queue",
                detail: "Notifications are off and no pending DoseTap reminders were found.",
                state: .pass
            )
        }

        if !appSettings.notificationsEnabled && pendingDoseTapNotificationCount > 0 {
            return InstallCheckItem(
                id: "queue_off_stale",
                title: "Stale notifications queued",
                detail: "\(pendingDoseTapNotificationCount) DoseTap notification(s) still pending while notifications are disabled.",
                state: .warning
            )
        }

        if pendingDoseTapNotificationCount > 0 {
            return InstallCheckItem(
                id: "queue_active",
                title: "Notification queue",
                detail: "\(pendingDoseTapNotificationCount) DoseTap reminder(s) pending (\(pendingWakeNotificationCount) wake alarm).",
                state: .pass
            )
        }

        if alarmService.alarmScheduled {
            return InstallCheckItem(
                id: "queue_missing_wake",
                title: "Wake alarm state mismatch",
                detail: "Alarm marked scheduled in app state, but no pending wake notification was found.",
                state: .fail
            )
        }

        if sessionRepo.dose1Time != nil && sessionRepo.dose2Time == nil && !sessionRepo.dose2Skipped {
            return InstallCheckItem(
                id: "queue_expected_missing",
                title: "No reminders queued for active session",
                detail: "Dose 1 exists and Dose 2 is pending, but no queued reminder notifications were found.",
                state: .warning
            )
        }

        return InstallCheckItem(
            id: "queue_empty",
            title: "No pending notifications",
            detail: "No DoseTap reminders are currently queued for delivery.",
            state: .warning
        )
    }

    private var checkCriticalAlerts: InstallCheckItem {
        guard appSettings.criticalAlertsEnabled else {
            return InstallCheckItem(
                id: "critical_off",
                title: "Critical alerts disabled",
                detail: "Only standard notifications will be used.",
                state: .warning
            )
        }
        if criticalAlertSetting == .enabled {
            return InstallCheckItem(
                id: "critical_enabled",
                title: "Critical alerts",
                detail: "Critical alert permission is enabled.",
                state: .pass
            )
        }
        return InstallCheckItem(
            id: "critical_not_granted",
            title: "Critical alerts not granted",
            detail: "App requests critical alerts but iOS has not granted them.",
            state: .warning
        )
    }

    private var checkReminderCoverage: InstallCheckItem {
        if appSettings.criticalAlertsEnabled && !appSettings.notificationsEnabled {
            return InstallCheckItem(
                id: "coverage_inconsistent_critical",
                title: "Settings mismatch",
                detail: "Critical alerts are enabled while notifications are disabled.",
                state: .fail
            )
        }

        guard appSettings.notificationsEnabled else {
            return InstallCheckItem(
                id: "coverage_notifications_off",
                title: "Reminder coverage",
                detail: "Notifications are disabled, so reminder coverage checks are skipped.",
                state: .warning
            )
        }

        let warningTogglesEnabled = appSettings.windowOpenAlert || appSettings.fifteenMinWarning || appSettings.fiveMinWarning
        if warningTogglesEnabled {
            return InstallCheckItem(
                id: "coverage_ok",
                title: "Reminder coverage",
                detail: "At least one dose-window reminder warning is enabled.",
                state: .pass
            )
        }

        return InstallCheckItem(
            id: "coverage_none",
            title: "No dose-window warnings enabled",
            detail: "Window-open, 15m, and 5m warnings are all off.",
            state: .warning
        )
    }

    private var checkHealthKitAvailability: InstallCheckItem {
        if healthKit.isAvailable {
            return InstallCheckItem(
                id: "healthkit_available",
                title: "HealthKit availability",
                detail: "HealthKit APIs are available on this install.",
                state: .pass
            )
        }
        return InstallCheckItem(
            id: "healthkit_unavailable",
            title: "HealthKit unavailable",
            detail: "Common on simulator/unsigned builds; timeline falls back to local events.",
            state: .warning
        )
    }

    private var checkHealthKitPermission: InstallCheckItem {
        if appSettings.healthKitEnabled && healthKit.isAuthorized {
            return InstallCheckItem(
                id: "healthkit_permission_ok",
                title: "HealthKit permission",
                detail: "Sleep data access is enabled and authorized.",
                state: .pass
            )
        }
        if !appSettings.healthKitEnabled {
            return InstallCheckItem(
                id: "healthkit_permission_disabled",
                title: "HealthKit disabled in app",
                detail: "Timeline will not load Apple Health sleep stages until enabled.",
                state: .warning
            )
        }
        return InstallCheckItem(
            id: "healthkit_permission_missing",
            title: "HealthKit authorization missing",
            detail: "App expects HealthKit but authorization is not granted.",
            state: .fail
        )
    }

    private var checkHealthDataFreshness: InstallCheckItem {
        guard appSettings.healthKitEnabled && healthKit.isAuthorized else {
            return InstallCheckItem(
                id: "health_freshness_na",
                title: "Health data freshness",
                detail: "Not applicable until HealthKit is enabled and authorized.",
                state: .warning
            )
        }
        guard let syncAt = healthKit.lastTimelineSyncAt else {
            return InstallCheckItem(
                id: "health_freshness_missing",
                title: "Health data not synced yet",
                detail: "Open Timeline once to perform initial HealthKit sync.",
                state: .warning
            )
        }
        let minutes = max(0, Int(Date().timeIntervalSince(syncAt) / 60))
        if minutes <= 120 {
            return InstallCheckItem(
                id: "health_freshness_ok",
                title: "Health data freshness",
                detail: "Last timeline sync was \(minutes)m ago.",
                state: .pass
            )
        }
        return InstallCheckItem(
            id: "health_freshness_stale",
            title: "Health data may be stale",
            detail: "Last timeline sync was \(minutes)m ago.",
            state: .warning
        )
    }

    private var checkBackgroundRefresh: InstallCheckItem {
        #if canImport(UIKit)
        let status = UIApplication.shared.backgroundRefreshStatus
        switch status {
        case .available:
            return InstallCheckItem(
                id: "bg_refresh_available",
                title: "Background refresh",
                detail: "Background refresh is available.",
                state: .pass
            )
        case .restricted:
            return InstallCheckItem(
                id: "bg_refresh_restricted",
                title: "Background refresh restricted",
                detail: "System policies may delay reminders and sync.",
                state: .warning
            )
        case .denied:
            return InstallCheckItem(
                id: "bg_refresh_denied",
                title: "Background refresh denied",
                detail: "Enable Background App Refresh for better reliability.",
                state: .warning
            )
        @unknown default:
            return InstallCheckItem(
                id: "bg_refresh_unknown",
                title: "Background refresh unknown",
                detail: "Unable to determine background refresh state.",
                state: .warning
            )
        }
        #else
        return InstallCheckItem(
            id: "bg_refresh_unavailable",
            title: "Background refresh",
            detail: "Unavailable on this platform.",
            state: .warning
        )
        #endif
    }

    private var checkTimeZone: InstallCheckItem {
        let current = TimeZone.current.identifier
        let auto = TimeZone.autoupdatingCurrent.identifier
        if current == auto {
            return InstallCheckItem(
                id: "timezone_consistent",
                title: "Timezone consistency",
                detail: "Current timezone is \(current).",
                state: .pass
            )
        }
        return InstallCheckItem(
            id: "timezone_mismatch",
            title: "Timezone mismatch detected",
            detail: "Current: \(current), auto-updating: \(auto).",
            state: .warning
        )
    }

    private func refreshChecks() async {
        isRefreshing = true
        defer { isRefreshing = false }

        healthKit.checkAuthorizationStatus()
        let notificationSettings = await loadNotificationSettings()
        notificationAuthorizationStatus = notificationSettings.authorizationStatus
        criticalAlertSetting = notificationSettings.criticalAlertSetting
        let pendingRequests = await loadPendingNotificationRequests()
        pendingDoseTapNotificationCount = pendingRequests.count
        pendingWakeNotificationCount = pendingRequests.filter { $0.identifier == "dosetap_wake_alarm" }.count
        lastCheckedAt = Date()
    }

    private func loadNotificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func loadPendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                let doseTapRequests = requests.filter {
                    $0.identifier.hasPrefix("dosetap_") && !$0.identifier.hasPrefix("dosetap_install_test_")
                }
                continuation.resume(returning: doseTapRequests)
            }
        }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #endif
    }

    private func runNotificationAutoRepair() async {
        isRefreshing = true
        defer { isRefreshing = false }

        alarmService.stopRinging(acknowledge: false)
        alarmService.cancelAllAlarms()

        var repairedItems: [String] = ["Cleared pending DoseTap notifications"]

        if appSettings.notificationsEnabled,
           let dose1Time = sessionRepo.dose1Time,
           sessionRepo.dose2Time == nil,
           !sessionRepo.dose2Skipped {
            if let targetWake = alarmService.targetWakeTime, targetWake > Date() {
                await alarmService.scheduleWakeAlarm(at: targetWake, dose1Time: dose1Time)
                repairedItems.append("Rescheduled wake alarm")
            }
            await alarmService.scheduleDose2Reminders(dose1Time: dose1Time)
            repairedItems.append("Rescheduled dose-window reminders")
        }

        await refreshChecks()
        actionStatusMessage = repairedItems.joined(separator: "\n").prependedBulletList
    }

    private func sendTestReminder() async {
        guard appSettings.notificationsEnabled else {
            actionStatusMessage = "Enable notifications in Settings first, then run test reminder."
            return
        }

        let granted = await alarmService.requestPermission()
        guard granted else {
            actionStatusMessage = "iOS notification permission is denied. Enable it in system settings, then retry."
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "DoseTap Install Test"
        content.body = "If you received this, local notification delivery is working."
        content.sound = appSettings.soundEnabled ? .default : nil
        content.interruptionLevel = appSettings.criticalAlertsEnabled ? .timeSensitive : .active

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let id = "dosetap_install_test_\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
            actionStatusMessage = "Test reminder scheduled for ~3 seconds from now."
            await refreshChecks()
        } catch {
            actionStatusMessage = "Failed to schedule test reminder: \(error.localizedDescription)"
        }
    }

    private func relativeTimeText(for date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        return "\(minutes)m ago"
    }
}

private extension String {
    var prependedBulletList: String {
        split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                if line.hasPrefix("•") {
                    return String(line.drop(while: { $0 == "•" || $0 == " " }))
                }
                return line
            }
            .map { "• \($0)" }
            .joined(separator: "\n")
    }
}

private struct ExportActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: @MainActor (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            Task { @MainActor in
                completion(completed, error)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

// MARK: - HealthKit Settings View
struct HealthKitSettingsView: View {
    @StateObject private var healthKit = HealthKitService.shared
    @StateObject private var settings = UserSettingsManager.shared
    @State private var isLoading = false
    @State private var showingBaseline = false
    private let defaultProvider: any HealthKitProviding = HealthKitProviderFactory.makeDefault()
    
    var body: some View {
        List {
            if defaultProvider is NoOpHealthKitProvider {
                Section {
                    Label("HealthKit is disabled (simulator or missing entitlements)", systemImage: "heart.slash")
                        .foregroundColor(.secondary)
                } footer: {
                    Text("On simulator and unsigned builds, HealthKit is unavailable. App defaults to NoOp provider for safety.")
                }
            } else {
                Section {
                    HStack {
                        Label("Status", systemImage: "heart.fill")
                        Spacer()
                        if healthKit.isAuthorized {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .labelStyle(.titleOnly)
                        } else {
                            Text("Not Connected")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if !healthKit.isAuthorized {
                        Button {
                            connectToHealthKit()
                        } label: {
                            HStack {
                                Label("Connect Apple Health", systemImage: "link")
                                if isLoading {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isLoading)
                    } else {
                        Toggle(isOn: $settings.healthKitEnabled) {
                            Label("Use Sleep Data", systemImage: "bed.double.fill")
                        }
                    }
                } header: {
                    Label("Apple Health", systemImage: "heart.text.square")
                } footer: {
                    if let error = healthKit.lastError {
                        Text(error)
                            .foregroundColor(.red)
                    } else {
                        Text("DoseTap reads sleep data to learn your patterns and optimize wake times.")
                    }
                }
                
                if healthKit.isAuthorized && settings.healthKitEnabled {
                    Section {
                        Button {
                            Task {
                                isLoading = true
                                await healthKit.computeTTFWBaseline(days: 14)
                                isLoading = false
                                showingBaseline = true
                            }
                        } label: {
                            HStack {
                                Label("Compute Sleep Baseline", systemImage: "chart.line.uptrend.xyaxis")
                                if isLoading {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isLoading)
                        
                        if let baseline = healthKit.ttfwBaseline {
                            HStack {
                                Label("Avg Time to First Wake", systemImage: "clock.fill")
                                Spacer()
                                Text("\(Int(baseline)) min")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }
                            
                            if let nudge = healthKit.calculateNudgeSuggestion() {
                                HStack {
                                    Label("Suggested Nudge", systemImage: "arrow.left.arrow.right")
                                    Spacer()
                                    Text(nudge >= 0 ? "+\(nudge) min" : "\(nudge) min")
                                        .foregroundColor(nudge >= 0 ? .green : .orange)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    } header: {
                        Label("Sleep Analysis", systemImage: "waveform.path.ecg")
                    } footer: {
                        Text("Analyzes 14 nights of sleep data to find your natural wake rhythm.")
                    }
                    
                    if !healthKit.sleepHistory.isEmpty {
                        Section {
                            ForEach(healthKit.sleepHistory.prefix(7)) { night in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(night.date, style: .date)
                                            .font(.subheadline)
                                        Text("\(Int(night.totalSleepMinutes / 60))h \(Int(night.totalSleepMinutes.truncatingRemainder(dividingBy: 60)))m sleep")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if let ttfw = night.ttfwMinutes {
                                        VStack(alignment: .trailing) {
                                            Text("\(Int(ttfw)) min")
                                                .font(.subheadline.bold())
                                            Text("TTFW")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    } else {
                                        Text("No data")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        } header: {
                            Label("Recent Nights", systemImage: "calendar")
                        }
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("What We Read")
                                .font(.subheadline.bold())
                        }
                        Text("• Sleep analysis (bed time, sleep stages, wake times)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Used to calculate TTFW (Time to First Wake)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Data stays on your device")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                if let error = healthKit.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle("Apple Health")
        .onAppear {
            // Reset loading state when view appears (in case it got stuck)
            isLoading = false
            healthKit.checkAuthorizationStatus()
        }
        .onChange(of: healthKit.isAuthorized) { _ in
            // Always stop loading when authorization state changes
            isLoading = false
        }
    }
    
    private func connectToHealthKit() {
        guard !isLoading else { return }
        
        Task {
            isLoading = true
            settings.healthKitEnabled = true
            
            let authorized = await healthKit.requestAuthorization()
            
            // Ensure we're back on main thread and reset loading
            await MainActor.run {
                isLoading = false
                if !authorized {
                    healthKit.checkAuthorizationStatus()
                }
            }
        }
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "pills.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("DoseTap")
                        .font(.title.bold())
                    
                    Text("XYWAV Dose Timer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            
            Section("Core Features") {
                Label("150-240 minute dose window", systemImage: "timer")
                Label("Smart notifications", systemImage: "bell.badge")
                Label("Sleep event tracking", systemImage: "bed.double.fill")
                Label("Health data integration", systemImage: "heart.text.square")
                Label("Offline-first design", systemImage: "wifi.slash")
            }
            
            Section("Privacy") {
                Label("All data stored locally", systemImage: "lock.shield.fill")
                Label("No account required", systemImage: "person.badge.minus")
                Label("No health data transmitted", systemImage: "hand.raised.fill")
            }
            
            Section {
                Link(destination: URL(string: "https://dosetap.com/privacy")!) {
                    Label("Privacy Policy", systemImage: "doc.text")
                }
                
                Link(destination: URL(string: "https://dosetap.com/support")!) {
                    Label("Support", systemImage: "questionmark.circle")
                }
            }
        }
        .navigationTitle("About")
    }
}

// MARK: - Event Cooldown Settings View
struct EventCooldownSettingsView: View {
    @StateObject private var settings = UserSettingsManager.shared
    
    var body: some View {
        List {
            // Info section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("About Cooldowns")
                            .font(.subheadline.bold())
                    }
                    Text("Cooldowns prevent accidental double-taps. Shorter = can log more frequently. Longer = fewer duplicates.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // Physical Events
            Section {
                CooldownPicker(
                    label: "Bathroom",
                    icon: "toilet.fill",
                    color: .blue,
                    value: $settings.cooldownBathroom
                )
                
                CooldownPicker(
                    label: "Water",
                    icon: "drop.fill",
                    color: .cyan,
                    value: $settings.cooldownWater
                )
                
                CooldownPicker(
                    label: "Snack",
                    icon: "fork.knife",
                    color: .green,
                    value: $settings.cooldownSnack
                )
            } header: {
                Label("Physical", systemImage: "figure.walk")
            }
            
            // Sleep Cycle Events
            Section {
                CooldownPicker(
                    label: "Lights Out",
                    icon: "light.max",
                    color: .indigo,
                    value: $settings.cooldownLightsOut
                )
                
                CooldownPicker(
                    label: "Wake Up",
                    icon: "sun.max.fill",
                    color: .yellow,
                    value: $settings.cooldownWakeUp
                )
                
                CooldownPicker(
                    label: "Brief Wake",
                    icon: "moon.zzz.fill",
                    color: .indigo,
                    value: $settings.cooldownBriefWake
                )
            } header: {
                Label("Sleep Cycle", systemImage: "bed.double.fill")
            }
            
            // Mental Events
            Section {
                CooldownPicker(
                    label: "Anxiety",
                    icon: "brain.head.profile",
                    color: .purple,
                    value: $settings.cooldownAnxiety
                )
                
                CooldownPicker(
                    label: "Dream",
                    icon: "cloud.moon.fill",
                    color: .pink,
                    value: $settings.cooldownDream
                )
                
                CooldownPicker(
                    label: "Heart Racing",
                    icon: "heart.fill",
                    color: .red,
                    value: $settings.cooldownHeartRacing
                )
            } header: {
                Label("Mental", systemImage: "brain")
            }
            
            // Environment Events
            Section {
                CooldownPicker(
                    label: "Noise",
                    icon: "speaker.wave.3.fill",
                    color: .orange,
                    value: $settings.cooldownNoise
                )
                
                CooldownPicker(
                    label: "Temperature",
                    icon: "thermometer.medium",
                    color: .teal,
                    value: $settings.cooldownTemperature
                )
                
                CooldownPicker(
                    label: "Pain",
                    icon: "bandage.fill",
                    color: .red,
                    value: $settings.cooldownPain
                )
            } header: {
                Label("Environment", systemImage: "house")
            }
            
            // Reset to defaults
            Section {
                Button(role: .destructive) {
                    resetCooldownsToDefaults()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Event Cooldowns")
    }
    
    private func resetCooldownsToDefaults() {
        settings.cooldownBathroom = 30
        settings.cooldownWater = 30
        settings.cooldownBriefWake = 60
        settings.cooldownAnxiety = 60
        settings.cooldownDream = 30
        settings.cooldownNoise = 30
        settings.cooldownLightsOut = 1800
        settings.cooldownWakeUp = 1800
        settings.cooldownSnack = 300
        settings.cooldownHeartRacing = 60
        settings.cooldownTemperature = 60
        settings.cooldownPain = 60
    }
}

// MARK: - Cooldown Picker Row
struct CooldownPicker: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var value: Int
    
    // Options: 10s, 30s, 1m, 2m, 5m, 10m, 30m, 1h
    private let options: [(seconds: Int, label: String)] = [
        (10, "10 sec"),
        (30, "30 sec"),
        (60, "1 min"),
        (120, "2 min"),
        (300, "5 min"),
        (600, "10 min"),
        (1800, "30 min"),
        (3600, "1 hour")
    ]
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(label)
            
            Spacer()
            
            Picker("", selection: $value) {
                ForEach(options, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

// MARK: - Data Management View
struct DataManagementView: View {
    @State private var sessions: [SessionSummary] = []
    @State private var selectedSessions: Set<String> = []
    @State private var isSelecting = false
    @State private var showDeleteConfirmation = false
    @State private var showClearTonightConfirmation = false
    @State private var showClearAllEventsConfirmation = false
    @State private var showClearOldDataConfirmation = false
    
    private let sessionRepo = SessionRepository.shared
    
    var body: some View {
        List {
            // Quick Actions Section
            Section {
                Button {
                    showClearTonightConfirmation = true
                } label: {
                    Label("Clear Tonight's Events", systemImage: "moon.stars")
                }
                
                Button {
                    showClearOldDataConfirmation = true
                } label: {
                    Label("Clear Data Older Than 30 Days", systemImage: "calendar.badge.minus")
                }
                
                Button(role: .destructive) {
                    showClearAllEventsConfirmation = true
                } label: {
                    Label("Clear All Event History", systemImage: "trash")
                }
            } header: {
                Text("Quick Actions")
            }
            
            // Session List Section
            Section {
                if sessions.isEmpty {
                    Text("No session history")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(sessions, id: \.sessionDate) { session in
                        SessionDeleteRow(
                            session: session,
                            isSelecting: isSelecting,
                            isSelected: selectedSessions.contains(session.sessionDate),
                            onToggle: {
                                if selectedSessions.contains(session.sessionDate) {
                                    selectedSessions.remove(session.sessionDate)
                                } else {
                                    selectedSessions.insert(session.sessionDate)
                                }
                            }
                        )
                    }
                    .onDelete(perform: deleteSessions)
                }
            } header: {
                HStack {
                    Text("Sessions (\(sessions.count))")
                    Spacer()
                    if !sessions.isEmpty {
                        Button(isSelecting ? "Done" : "Select") {
                            withAnimation {
                                isSelecting.toggle()
                                if !isSelecting {
                                    selectedSessions.removeAll()
                                }
                            }
                        }
                        .font(.subheadline)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if isSelecting && !selectedSessions.isEmpty {
                        Text("\(selectedSessions.count) selected")
                        
                        // Prominent delete button when items are selected
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete \(selectedSessions.count) Session\(selectedSessions.count == 1 ? "" : "s")")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Swipe to delete individual sessions, or tap Select for multi-delete.")
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Manage History")
        .toolbar {
            if isSelecting && !selectedSessions.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete \(selectedSessions.count) Sessions", systemImage: "trash")
                    }
                }
            }
        }
        .onAppear { loadSessions() }
        // Delete Selected Confirmation
        .alert("Delete Selected Sessions?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete \(selectedSessions.count)", role: .destructive) {
                deleteSelectedSessions()
            }
        } message: {
            Text("This will permanently delete \(selectedSessions.count) session(s) and their events. This cannot be undone.")
        }
        // Clear Tonight Confirmation
        .alert("Clear Tonight's Events?", isPresented: $showClearTonightConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearTonightsEvents()
            }
        } message: {
            Text("This will delete all events logged tonight. Dose data will be preserved.")
        }
        // Clear All Events Confirmation
        .alert("Clear All Event History?", isPresented: $showClearAllEventsConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearAllEvents()
            }
        } message: {
            Text("This will permanently delete all sleep events from all sessions. Dose logs will be preserved.")
        }
        // Clear Old Data Confirmation
        .alert("Clear Old Data?", isPresented: $showClearOldDataConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearOldData()
            }
        } message: {
            Text("This will delete all sessions and events older than 30 days.")
        }
    }
    
    private func loadSessions() {
        sessions = sessionRepo.fetchRecentSessions(days: 365) // Get up to a year
    }
    
    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            // Use SessionRepository to broadcast changes to Tonight tab
            sessionRepo.deleteSession(sessionDate: session.sessionDate)
        }
        sessions.remove(atOffsets: offsets)
    }
    
    private func deleteSelectedSessions() {
        for sessionDate in selectedSessions {
            // Use SessionRepository to broadcast changes to Tonight tab
            sessionRepo.deleteSession(sessionDate: sessionDate)
        }
        sessions.removeAll { selectedSessions.contains($0.sessionDate) }
        selectedSessions.removeAll()
        isSelecting = false
    }
    
    private func clearTonightsEvents() {
        // Use SessionRepository to clear tonight and broadcast
        sessionRepo.clearTonight()
        loadSessions()
    }
    
    private func clearAllEvents() {
        sessionRepo.clearAllSleepEvents()
        loadSessions()
    }
    
    private func clearOldData() {
        sessionRepo.clearOldData(olderThanDays: 30)
        loadSessions()
    }
}

struct SessionDeleteRow: View {
    let session: SessionSummary
    let isSelecting: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            if isSelecting {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.subheadline.bold())
                
                HStack(spacing: 12) {
                    if session.dose1Time != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "1.circle.fill")
                                .font(.caption2)
                            Text(session.dose1Time!.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                        }
                        .foregroundColor(.green)
                    }
                    
                    if session.dose2Time != nil {
                        HStack(spacing: 2) {
                            Image(systemName: "2.circle.fill")
                                .font(.caption2)
                            Text(session.dose2Time!.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                        }
                        .foregroundColor(.green)
                    } else if session.skipped {
                        Text("Skipped")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    if session.eventCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "list.bullet")
                                .font(.caption2)
                            Text("\(session.eventCount)")
                                .font(.caption)
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggle()
            }
        }
    }
    
    private var formattedDate: String {
        // Convert session date string to formatted display
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: session.sessionDate) {
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: date)
        }
        return session.sessionDate
    }
}

// MARK: - QuickLog Customization View
struct QuickLogCustomizationView: View {
    @ObservedObject var settings = UserSettingsManager.shared
    @State private var showAddSheet = false
    @Environment(\.editMode) private var editMode
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    private var availableToAdd: [QuickLogButtonConfig] {
        let currentIds = Set(settings.quickLogButtons.map { $0.id })
        return UserSettingsManager.allAvailableEvents.filter { !currentIds.contains($0.id) }
    }
    
    var body: some View {
        List {
            // Preview Section
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(settings.quickLogButtons) { button in
                            QuickLogPreviewButton(config: button)
                        }
                        
                        // Empty slots - tappable to show add sheet
                        ForEach(0..<(16 - settings.quickLogButtons.count), id: \.self) { _ in
                            Button(action: {
                                showAddSheet = true
                            }) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.systemGray5))
                                    .frame(height: 50)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .foregroundColor(.blue)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("QuickLog Grid (4×4)")
            } footer: {
                Text("\(settings.quickLogButtons.count) of 16 slots used. Tap + to add events.")
            }
            
            // Current Buttons (Editable)
            Section {
                ForEach(settings.quickLogButtons) { button in
                    HStack(spacing: 12) {
                        Image(systemName: button.icon)
                            .font(.title3)
                            .foregroundColor(button.color)
                            .frame(width: 30)
                        
                        Text(button.name)
                        
                        Spacer()
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let button = settings.quickLogButtons[index]
                        settings.removeQuickLogButton(id: button.id)
                    }
                }
                .onMove { source, destination in
                    settings.moveQuickLogButton(from: source, to: destination)
                }
            } header: {
                HStack {
                    Text("Active Buttons")
                    Spacer()
                    EditButton()
                        .font(.caption)
                }
            } footer: {
                Text("Swipe to remove. Drag to reorder.")
            }
            
            // Add Buttons Section
            Section {
                ForEach(availableToAdd) { button in
                    Button {
                        settings.addQuickLogButton(button)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: button.icon)
                                .font(.title3)
                                .foregroundColor(button.color)
                                .frame(width: 30)
                            
                            Text(button.name)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    .disabled(settings.quickLogButtons.count >= 16)
                }
            } header: {
                Text("Available Events")
            } footer: {
                if settings.quickLogButtons.count >= 16 {
                    Text("Maximum 16 buttons reached. Remove one to add another.")
                        .foregroundColor(.orange)
                }
            }
            
            // Reset Section
            Section {
                Button(role: .destructive) {
                    settings.resetQuickLogButtons()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Customize QuickLog")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            AddQuickLogEventSheet(
                availableEvents: availableToAdd,
                onAdd: { button in
                    settings.addQuickLogButton(button)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Add QuickLog Event Sheet
struct AddQuickLogEventSheet: View {
    let availableEvents: [QuickLogButtonConfig]
    let onAdd: (QuickLogButtonConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if availableEvents.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("All Events Added!")
                            .font(.headline)
                        Text("You've added all available event types to your QuickLog panel.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(availableEvents) { button in
                            Button {
                                onAdd(button)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: button.icon)
                                        .font(.title3)
                                        .foregroundColor(button.color)
                                        .frame(width: 30)
                                    
                                    Text(button.name)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Add Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - QuickLog Preview Button
struct QuickLogPreviewButton: View {
    let config: QuickLogButtonConfig
    
    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 10)
                .fill(config.color.opacity(0.15))
                .frame(height: 40)
                .overlay(
                    Image(systemName: config.icon)
                        .font(.system(size: 16))
                        .foregroundColor(config.color)
                )
            
            Text(config.name)
                .font(.system(size: 9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - DateFormatter Extension for Export
extension DateFormatter {
    static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter
    }()
}

// MARK: - Typical Week Helpers
private struct TypicalWeekRow: View {
    let weekday: Int
    let entry: TypicalWeekEntry
    var onChange: (Date, Bool) -> Void
    
    @State private var wakeTime: Date
    
    init(weekday: Int, entry: TypicalWeekEntry, onChange: @escaping (Date, Bool) -> Void) {
        self.weekday = weekday
        self.entry = entry
        self.onChange = onChange
        _wakeTime = State(initialValue: TypicalWeekRow.makeDate(from: entry))
    }
    
    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { entry.enabled },
                set: { newValue in onChange(wakeTime, newValue) }
            )) {
                Text(weekdayName(weekday))
            }
            .toggleStyle(.switch)
            
            DatePicker(
                "",
                selection: Binding(
                    get: { wakeTime },
                    set: { newValue in
                        wakeTime = newValue
                        onChange(newValue, entry.enabled)
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .onChange(of: entry) { newEntry in
            wakeTime = TypicalWeekRow.makeDate(from: newEntry)
        }
    }
    
    private func weekdayName(_ index: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let normalized = (index - 1 + symbols.count) % symbols.count
        return symbols[normalized]
    }
    
    private static func makeDate(from entry: TypicalWeekEntry) -> Date {
        var comps = DateComponents()
        comps.hour = entry.wakeByHour
        comps.minute = entry.wakeByMinute
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
}

private struct SleepPlanSettingsRow: View {
    let title: String
    let minutes: Int
    let step: Int
    let range: ClosedRange<Int>
    var onChange: (Int) -> Void
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: Binding(
                get: { minutes },
                set: { newValue in onChange(newValue) }
            ), in: range, step: step) {
                Text("\(minutes) min")
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
        
        SettingsView()
            .preferredColorScheme(.dark)
        
        NavigationView {
            EventCooldownSettingsView()
        }
        
        NavigationView {
            QuickLogCustomizationView()
        }
    }
}
