import SwiftUI
import DoseCore

// MARK: - Settings View (Full App)
struct SettingsView: View {
    @StateObject private var settings = UserSettingsManager.shared
    @StateObject private var dataStorage = DataStorageService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingExportSheet = false
    @State private var showingClearDataAlert = false
    @State private var exportData = ""
    
    var body: some View {
        NavigationView {
            List {
                // MARK: - Appearance Section
                appearanceSection
                
                // MARK: - Dose Timing Section
                doseTimingSection
                
                // MARK: - Notifications Section
                notificationsSection
                
                // MARK: - Health Integrations
                integrationsSection
                
                // MARK: - Data Management
                dataManagementSection
                
                // MARK: - Privacy
                privacySection
                
                // MARK: - About
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(settings.colorScheme)
        .alert("Clear All Data", isPresented: $showingClearDataAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This will permanently delete all your dose history, sleep events, and settings. This action cannot be undone.")
        }
        .sheet(isPresented: $showingExportSheet) {
            ShareSheet(items: [exportData])
        }
    }
    
    // MARK: - Appearance Section
    private var appearanceSection: some View {
        Section {
            // Theme Picker
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
            
            Toggle(isOn: $settings.highContrastMode) {
                Label("High Contrast", systemImage: "circle.lefthalf.striped.horizontal")
            }
            
            Toggle(isOn: $settings.reducedMotion) {
                Label("Reduce Motion", systemImage: "figure.walk")
            }
        } header: {
            Label("Appearance", systemImage: "paintbrush.fill")
        }
    }
    
    // MARK: - Dose Timing Section
    private var doseTimingSection: some View {
        Section {
            // Target Interval Picker
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
            
            HStack {
                Label("Snooze Duration", systemImage: "clock.badge.plus")
                Spacer()
                Text("\(settings.snoozeDurationMinutes) min")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("Max Snoozes", systemImage: "repeat")
                Spacer()
                Text("\(settings.maxSnoozes) per night")
                    .foregroundColor(.secondary)
            }
            
            // XYWAV Info Card
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("XYWAV Dose Window")
                        .font(.subheadline.bold())
                }
                Text("Window opens at 150 min after Dose 1")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Window closes at 240 min (hard limit)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Snooze disabled when <15 min remain")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .padding(.vertical, 4)
        } header: {
            Label("Dose Timing", systemImage: "timer")
        } footer: {
            Text("Target interval is when you'll be reminded to take Dose 2.")
        }
    }
    
    // MARK: - Notifications Section
    private var notificationsSection: some View {
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
                
                Toggle(isOn: $settings.soundEnabled) {
                    Label("Sound", systemImage: "speaker.wave.2.fill")
                }
                
                Toggle(isOn: $settings.hapticsEnabled) {
                    Label("Haptics", systemImage: "waveform")
                }
            }
        } header: {
            Label("Notifications", systemImage: "bell.badge.fill")
        }
    }
    
    // MARK: - Integrations Section
    private var integrationsSection: some View {
        Section {
            Toggle(isOn: $settings.healthKitEnabled) {
                Label("Apple Health", systemImage: "heart.fill")
            }
            .tint(.red)
            
            if settings.healthKitEnabled {
                NavigationLink {
                    HealthSettingsDetailView()
                } label: {
                    Label("Health Settings", systemImage: "chevron.right")
                }
            }
            
            Toggle(isOn: $settings.whoopEnabled) {
                Label("WHOOP", systemImage: "figure.run")
            }
            .tint(.green)
            
            if settings.whoopEnabled {
                NavigationLink {
                    WHOOPSettingsDetailView()
                } label: {
                    Label("WHOOP Settings", systemImage: "chevron.right")
                }
            }
        } header: {
            Label("Integrations", systemImage: "link")
        }
    }
    
    // MARK: - Data Management Section
    private var dataManagementSection: some View {
        Section {
            Button {
                exportData = dataStorage.exportToCSV()
                showingExportSheet = true
            } label: {
                Label("Export Data (CSV)", systemImage: "square.and.arrow.up")
            }
            
            NavigationLink {
                DataExportView()
            } label: {
                Label("Advanced Export", systemImage: "doc.badge.gearshape")
            }
            
            Button(role: .destructive) {
                showingClearDataAlert = true
            } label: {
                Label("Clear All Data", systemImage: "trash.fill")
            }
        } header: {
            Label("Data Management", systemImage: "externaldrive.fill")
        } footer: {
            Text("Data is stored locally on your device only.")
        }
    }
    
    // MARK: - Privacy Section
    private var privacySection: some View {
        Section {
            Toggle(isOn: $settings.analyticsEnabled) {
                Label("Anonymous Analytics", systemImage: "chart.bar.fill")
            }
            
            Toggle(isOn: $settings.crashReportsEnabled) {
                Label("Crash Reports", systemImage: "ant.fill")
            }
        } header: {
            Label("Privacy", systemImage: "hand.raised.fill")
        } footer: {
            Text("No personal health data is ever transmitted.")
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
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
                AboutDetailView()
            } label: {
                Label("About DoseTap", systemImage: "questionmark.circle")
            }
        } header: {
            Label("About", systemImage: "info.circle.fill")
        }
    }
    
    // MARK: - Helper Methods
    private func formatInterval(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m (\(minutes) min)"
    }
    
    private func clearAllData() {
        // Clear all stored data from both storage systems
        
        // 1. Clear UserDefaults
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        
        // 2. Clear DataStorageService (JSON files + in-memory)
        dataStorage.clearAllData()
        
        // 3. Clear SQLiteStorage (all tables: dose_events, sleep_events, morning_checkins, etc.)
        SQLiteStorage.shared.clearAllData()
        
        // 4. Post notification to refresh any UI that's showing cached data
        NotificationCenter.default.post(name: NSNotification.Name("DataCleared"), object: nil)
        
        print("✅ SettingsView: All data cleared from all storage systems")
    }
}

// MARK: - User Settings Manager (Shared)
class UserSettingsManager: ObservableObject {
    static let shared = UserSettingsManager()
    
    // MARK: - Appearance
    @AppStorage("appearance_mode") var appearanceMode: AppearanceMode = .dark  // Default to dark mode
    @AppStorage("high_contrast_mode") var highContrastMode: Bool = false
    @AppStorage("reduced_motion") var reducedMotion: Bool = false
    
    // MARK: - Dose Timing (XYWAV Specific)
    @AppStorage("target_interval_minutes") var targetIntervalMinutes: Int = 165
    @AppStorage("snooze_duration_minutes") var snoozeDurationMinutes: Int = 10
    @AppStorage("max_snoozes") var maxSnoozes: Int = 3
    
    // MARK: - Notifications
    @AppStorage("notifications_enabled") var notificationsEnabled: Bool = true
    @AppStorage("critical_alerts_enabled") var criticalAlertsEnabled: Bool = true
    @AppStorage("window_open_alert") var windowOpenAlert: Bool = true
    @AppStorage("fifteen_min_warning") var fifteenMinWarning: Bool = true
    @AppStorage("five_min_warning") var fiveMinWarning: Bool = true
    @AppStorage("haptics_enabled") var hapticsEnabled: Bool = true
    @AppStorage("sound_enabled") var soundEnabled: Bool = true
    
    // MARK: - Integrations
    @AppStorage("healthkit_enabled") var healthKitEnabled: Bool = false
    @AppStorage("whoop_enabled") var whoopEnabled: Bool = false
    
    // MARK: - Privacy
    @AppStorage("analytics_enabled") var analyticsEnabled: Bool = false
    @AppStorage("crash_reports_enabled") var crashReportsEnabled: Bool = true
    
    // Valid target options per SSOT
    let validTargetOptions: [Int] = [165, 180, 195, 210, 225]
    
    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

// MARK: - Appearance Mode Enum
enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - Health Settings Detail View
struct HealthSettingsDetailView: View {
    @State private var syncSleep = true
    @State private var syncHeartRate = true
    @State private var syncHRV = true
    
    var body: some View {
        List {
            Section("Data Types") {
                Toggle("Sleep Analysis", isOn: $syncSleep)
                Toggle("Heart Rate", isOn: $syncHeartRate)
                Toggle("Heart Rate Variability", isOn: $syncHRV)
            }
            
            Section {
                Button("Request Permissions") {
                    // Request HealthKit permissions
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Apple Health")
    }
}

// MARK: - WHOOP Settings Detail View
struct WHOOPSettingsDetailView: View {
    @State private var isConnected = false
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(isConnected ? "Connected" : "Not Connected")
                        .foregroundColor(isConnected ? .green : .secondary)
                }
                
                if isConnected {
                    Button("Disconnect") {
                        isConnected = false
                    }
                    .foregroundColor(.red)
                } else {
                    Button("Connect WHOOP") {
                        isConnected = true
                    }
                }
            }
            
            if isConnected {
                Section("Sync") {
                    Button("Sync Last 7 Days") { }
                    Button("Sync Last 30 Days") { }
                }
            }
        }
        .navigationTitle("WHOOP")
    }
}

// MARK: - About Detail View
struct AboutDetailView: View {
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
                Label("12 sleep event types", systemImage: "bed.double.fill")
                Label("Apple Health integration", systemImage: "heart.text.square")
                Label("WHOOP integration", systemImage: "figure.run")
                Label("Offline-first design", systemImage: "wifi.slash")
            }
            
            Section("Privacy") {
                Label("All data stored locally", systemImage: "lock.shield.fill")
                Label("No account required", systemImage: "person.badge.minus")
                Label("No health data transmitted", systemImage: "hand.raised.fill")
            }
        }
        .navigationTitle("About")
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
        
        SettingsView()
            .preferredColorScheme(.dark)
    }
}
