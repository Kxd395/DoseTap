import SwiftUI
import DoseCore
import os.log
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

private let settingsLog = Logger(subsystem: "com.dosetap.app", category: "SettingsView")

// UserSettingsManager and AppearanceMode are defined in UserSettingsManager.swift

// MARK: - Settings View
struct SettingsView: View {
    @StateObject private var settings = UserSettingsManager.shared
    @State private var showingResetConfirmation = false
    @State private var showingExportSuccess = false
    @State private var showingExportSheet = false
    @State private var showingExportError = false
    @State private var exportErrorMessage = ""
    @State private var showingNotificationPermissionAlert = false
    @State private var notificationPermissionMessage = ""
    @State private var exportURL: URL?
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
                    DatePicker("Sleep Start", selection: sleepStartBinding, displayedComponents: .hourAndMinute)
                    DatePicker("Wake Time", selection: wakeTimeBinding, displayedComponents: .hourAndMinute)

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
                    Text("These times control session rollover. Midnight is not a boundary; the morning check-in (or cutoff) closes the night.")
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
                    
                    WHOOPStatusRow()
                } header: {
                    Label("Integrations", systemImage: "link")
                } footer: {
                    Text("Connect with Apple Health to sync sleep data and view integrated insights.")
                }
                
                // MARK: - Data Management
                Section {
                    Button {
                        exportData()
                    } label: {
                        Label("Export Data (CSV)", systemImage: "square.and.arrow.up")
                    }
                    
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
                            urlRouter.selectedTab = .tonight
                        }
                    }
                }
            }
        }
        .preferredColorScheme(settings.colorScheme)
        .alert("Clear All Data", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This will permanently delete all your dose history, sleep events, and settings. This action cannot be undone.")
        }
        .alert("Export Complete", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your data has been exported to the Files app.")
        }
        .alert("Export Failed", isPresented: $showingExportError) {
            Button("Try Again") { exportData() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Could not export your data: \(exportErrorMessage). Check available storage and try again.")
        }
        .sheet(isPresented: $showingExportSheet) {
            if let url = exportURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .onChange(of: settings.notificationsEnabled) { enabled in
            guard enabled else { return }
            Task {
                await validateNotificationAuthorization()
            }
        }
        .alert("Notifications Disabled in iOS", isPresented: $showingNotificationPermissionAlert) {
            Button("Open Settings") {
                openSystemNotificationSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(notificationPermissionMessage)
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
        return AppFormatters.shortTime.string(from: cutoff)
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

    @MainActor
    private func validateNotificationAuthorization() async {
        let status = await notificationAuthorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            let granted = await AlarmService.shared.requestPermission()
            if !granted {
                settings.notificationsEnabled = false
                notificationPermissionMessage = "DoseTap cannot play notification alarms until you grant notification permission."
                showingNotificationPermissionAlert = true
            }
        case .denied:
            settings.notificationsEnabled = false
            notificationPermissionMessage = "Notifications are denied for DoseTap in iOS Settings. Enable them to receive wake alarms when the app is backgrounded or the phone is locked."
            showingNotificationPermissionAlert = true
        @unknown default:
            settings.notificationsEnabled = false
            notificationPermissionMessage = "DoseTap could not verify notification permission. Please enable notifications in iOS Settings."
            showingNotificationPermissionAlert = true
        }
    }

    private func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private func openSystemNotificationSettings() {
        #if canImport(UIKit)
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
        #endif
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
        settingsLog.info("Requesting HealthKit permissions")
    }
    
    private func exportData() {
        let csvContent = SessionRepository.shared.exportToCSV()
        
        // Create temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "DoseTap_Export_\(DateFormatter.exportDateFormatter.string(from: Date())).csv"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            exportURL = fileURL
            showingExportSheet = true
            settingsLog.info("Export file created: \(fileURL.lastPathComponent, privacy: .private)")
        } catch {
            settingsLog.error("Failed to create export file: \(error.localizedDescription, privacy: .public)")
            exportErrorMessage = error.localizedDescription
            showingExportError = true
        }
    }
    
    private func clearAllData() {
        // Clear all data sources - SSOT pattern
        #if DEBUG
        settingsLog.debug("Clearing all data")
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
        settingsLog.debug("All data cleared successfully")
        #endif
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
