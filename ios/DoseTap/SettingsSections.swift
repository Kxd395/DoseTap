import SwiftUI
import DoseCore

extension SettingsView {
    var settingsContent: some View {
        List {
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

            Section {
                AppleHealthStatusRow()
                WHOOPStatusRow()
            } header: {
                Label("Integrations", systemImage: "link")
            } footer: {
                Text("Connect with Apple Health to sync sleep data and view integrated insights.")
            }

            Section {
                Button {
                    exportData()
                } label: {
                    Label("Export Data (CSV)", systemImage: "square.and.arrow.up")
                }

                Toggle(isOn: Binding(
                    get: { AutoExportService.shared.isEnabled },
                    set: { AutoExportService.shared.isEnabled = $0 }
                )) {
                    Label("Scheduled Export", systemImage: "clock.arrow.2.circlepath")
                }

                if AutoExportService.shared.isEnabled {
                    Picker(selection: Binding(
                        get: { AutoExportService.shared.frequency },
                        set: { AutoExportService.shared.frequency = $0 }
                    )) {
                        ForEach(AutoExportService.Frequency.allCases) { frequency in
                            Text(frequency.rawValue).tag(frequency)
                        }
                    } label: {
                        Label("Frequency", systemImage: "calendar")
                    }

                    if let lastExportDate = AutoExportService.shared.lastExportDate {
                        HStack {
                            Label("Last Export", systemImage: "checkmark.circle")
                            Spacer()
                            Text(lastExportDate, style: .relative)
                                .foregroundColor(.secondary)
                        }
                    }
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
            Color.clear.frame(height: tabBarInsetHeight)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    withAnimation {
                        urlRouter.selectedTab = .tonight
                    }
                }
            }
        }
        .preferredColorScheme(settings.colorScheme)
        .alert("Clear All Data", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This will permanently delete all your dose history, sleep events, and settings. This action cannot be undone.")
        }
        .alert("Export Complete", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data has been exported to the Files app.")
        }
        .alert("Export Failed", isPresented: $showingExportError) {
            Button("Try Again") { exportData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Could not export your data: \(exportErrorMessage). Check available storage and try again.")
        }
        .sheet(isPresented: $showingExportSheet) {
            if let exportURL {
                ActivityViewController(activityItems: [exportURL])
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
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(notificationPermissionMessage)
        }
    }

    var sleepStartBinding: Binding<Date> {
        Binding(
            get: { settings.dateFromMinutes(settings.sleepStartMinutes) },
            set: { settings.sleepStartMinutes = settings.minutesFromDate($0) }
        )
    }

    var wakeTimeBinding: Binding<Date> {
        Binding(
            get: { settings.dateFromMinutes(settings.wakeTimeMinutes) },
            set: { settings.wakeTimeMinutes = settings.minutesFromDate($0) }
        )
    }

    var prepTimeBinding: Binding<Date> {
        Binding(
            get: { settings.dateFromMinutes(settings.prepTimeMinutes) },
            set: { settings.prepTimeMinutes = settings.minutesFromDate($0) }
        )
    }

    var cutoffTimeText: String {
        let wake = settings.dateFromMinutes(settings.wakeTimeMinutes)
        let cutoff = Calendar.current.date(byAdding: .hour, value: settings.missedCheckInCutoffHours, to: wake) ?? wake
        return AppFormatters.shortTime.string(from: cutoff)
    }

    var appearancePicker: some View {
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

    var targetIntervalPicker: some View {
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

    var undoSpeedPicker: some View {
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

    var medicationSummary: String {
        let medications = settings.userMedications
        if medications.isEmpty {
            return "None"
        }
        if medications.count == 1 {
            return medicationDisplayName(medications[0])
        }
        return "\(medications.count) medications"
    }

    func medicationDisplayName(_ id: String) -> String {
        switch id {
        case "adderall_ir":
            return "Adderall IR"
        case "adderall_xr":
            return "Adderall XR"
        default:
            return id
        }
    }

    func formatInterval(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return "\(hours)h \(remainder)m (\(minutes) min)"
    }

    func formatUndoWindow(_ seconds: Double) -> String {
        switch Int(seconds) {
        case 3:
            return "Fast (3s)"
        case 5:
            return "Normal (5s)"
        case 7:
            return "Slow (7s)"
        default:
            return "Very Slow (10s)"
        }
    }
}
