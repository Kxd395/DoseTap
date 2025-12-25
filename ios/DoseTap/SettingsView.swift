import SwiftUI

// UserSettingsManager and AppearanceMode are defined in UserSettingsManager.swift

// MARK: - Settings View
struct SettingsView: View {
    @StateObject private var settings = UserSettingsManager.shared
    @State private var showingResetConfirmation = false
    @State private var showingExportSuccess = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                // MARK: - Appearance Section
                Section {
                    appearancePicker
                    
                    Toggle(isOn: $settings.highContrastMode) {
                        Label("High Contrast", systemImage: "circle.lefthalf.striped.horizontal")
                    }
                    
                    Toggle(isOn: $settings.reducedMotion) {
                        Label("Reduce Motion", systemImage: "figure.walk")
                    }
                } header: {
                    Label("Appearance", systemImage: "paintbrush.fill")
                }
                
                // MARK: - Dose Timing Section (XYWAV Specific)
                Section {
                    targetIntervalPicker
                    
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
                    
                    // Info card
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
                
                // MARK: - Notifications Section
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
                
                // MARK: - QuickLog Customization Section
                Section {
                    NavigationLink {
                        QuickLogCustomizationView()
                    } label: {
                        HStack {
                            Label("Customize QuickLog Buttons", systemImage: "square.grid.2x2")
                            Spacer()
                            Text("\(settings.quickLogButtons.count)/16")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("QuickLog Panel", systemImage: "hand.tap.fill")
                } footer: {
                    Text("Choose which event buttons appear in your 4×4 quick log grid (up to 16).")
                }
                
                // MARK: - Event Log Cooldowns Section
                Section {
                    NavigationLink {
                        EventCooldownSettingsView()
                    } label: {
                        HStack {
                            Label("Event Log Cooldowns", systemImage: "timer")
                            Spacer()
                            Text("Customize")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("Event Logging", systemImage: "list.bullet.clipboard")
                } footer: {
                    Text("Adjust how often you can log the same sleep event.")
                }
                
                // MARK: - Integrations Section
                Section {
                    Toggle(isOn: $settings.healthKitEnabled) {
                        Label("Apple Health", systemImage: "heart.fill")
                    }
                    .onChange(of: settings.healthKitEnabled) { enabled in
                        if enabled {
                            // Request HealthKit permissions
                            requestHealthKitPermissions()
                        }
                    }
                    
                    Toggle(isOn: $settings.whoopEnabled) {
                        Label("WHOOP", systemImage: "figure.run")
                    }
                    
                    if settings.whoopEnabled {
                        NavigationLink {
                            WHOOPSettingsView()
                        } label: {
                            Label("WHOOP Settings", systemImage: "chevron.right")
                        }
                    }
                } header: {
                    Label("Integrations", systemImage: "link")
                }
                
                // MARK: - Data Management Section
                Section {
                    Button {
                        exportData()
                    } label: {
                        Label("Export Data (CSV)", systemImage: "square.and.arrow.up")
                    }
                    
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        Label("Manage History", systemImage: "clock.arrow.circlepath")
                    }
                    
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Clear All Data", systemImage: "trash.fill")
                    }
                } header: {
                    Label("Data Management", systemImage: "externaldrive.fill")
                } footer: {
                    Text("Data is stored locally on your device only.")
                }
                
                // MARK: - Privacy Section
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
                
                // MARK: - About Section
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
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
    
    // MARK: - Helper Methods
    private func formatInterval(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m (\(minutes) min)"
    }
    
    private func requestHealthKitPermissions() {
        // In real app, this would request HealthKit authorization
        print("Requesting HealthKit permissions...")
    }
    
    private func exportData() {
        // In real app, this would export to Files
        print("Exporting data...")
        showingExportSuccess = true
    }
    
    private func clearAllData() {
        // In real app, this would clear all data
        print("Clearing all data...")
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
    }
}

// MARK: - WHOOP Settings View
struct WHOOPSettingsView: View {
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
                    Button("Disconnect WHOOP") {
                        isConnected = false
                    }
                    .foregroundColor(.red)
                } else {
                    Button("Connect WHOOP") {
                        // OAuth flow would go here
                        isConnected = true
                    }
                }
            }
            
            if isConnected {
                Section("Data Sync") {
                    Button("Sync Last 7 Days") {
                        // Sync logic
                    }
                    
                    Button("Sync Last 30 Days") {
                        // Sync logic
                    }
                }
            }
        }
        .navigationTitle("WHOOP")
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
    
    private let storage = EventStorage.shared
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
        sessions = storage.fetchRecentSessions(days: 365) // Get up to a year
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
        storage.clearAllSleepEvents()
        loadSessions()
    }
    
    private func clearOldData() {
        storage.clearOldData(olderThanDays: 30)
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