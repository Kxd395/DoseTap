import SwiftUI

/// Placeholder views for navigation - to be implemented in Sprint B

struct TimelineView: View {
    @ObservedObject var dataStore: DataStore
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Timeline View")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Coming in Sprint B:")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Interactive dose timeline with window shading", systemImage: "timeline.selection")
                Label("Drag to adjust time ranges and zoom levels", systemImage: "hand.draw")
                Label("Overlay WHOOP metrics on timeline", systemImage: "heart.circle")
                Label("Export timeline as PDF reports", systemImage: "doc.richtext")
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Timeline")
    }
}

struct AdherenceView: View {
    @ObservedObject var dataStore: DataStore
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Adherence Analysis")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Coming in Sprint B:")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Detailed adherence trends and patterns", systemImage: "chart.line.uptrend.xyaxis")
                Label("Window timing distribution charts", systemImage: "chart.bar")
                Label("Correlation with sleep and recovery data", systemImage: "bed.double")
                Label("Predictive adherence scoring", systemImage: "brain.head.profile")
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Adherence")
    }
}

struct InventoryView: View {
    @ObservedObject var dataStore: DataStore
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Inventory Management")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Coming in Sprint B:")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("Inventory usage trends and forecasting", systemImage: "chart.xyaxis.line")
                Label("Automated refill reminder scheduling", systemImage: "calendar.badge.plus")
                Label("Waste tracking and optimization", systemImage: "minus.circle")
                Label("Insurance and cost analysis", systemImage: "dollarsign.circle")
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
            
            if let inventory = dataStore.currentInventory {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current Status")
                        .font(.headline)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(inventory.dosesRemaining)")
                                .font(.title)
                                .fontWeight(.bold)
                            Text("Doses Remaining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if let daysLeft = inventory.estimatedDaysLeft {
                            VStack(alignment: .trailing) {
                                Text("\(daysLeft)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(daysLeft < 7 ? .red : .primary)
                                Text("Days Left")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(12)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Inventory")
    }
}

struct ExportView: View {
    @ObservedObject var dataStore: DataStore
    
    var body: some View {
        let analytics = dataStore.analytics
        
        VStack(spacing: 20) {
            Text("Export & Reports")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Coming in Sprint B:")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("PDF reports with charts and insights", systemImage: "doc.richtext")
                Label("CSV exports for further analysis", systemImage: "tablecells")
                Label("Healthcare provider summary reports", systemImage: "person.crop.circle.badge.plus")
                Label("Insurance claim documentation", systemImage: "doc.text.below.ecg")
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
            
            // Basic export stats for now
            VStack(alignment: .leading, spacing: 12) {
                Text("Available Data")
                    .font(.headline)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(analytics.totalEvents)")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Total Events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        Text("\(analytics.totalSessions)")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Total Sessions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        Text("\(dataStore.inventory.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Inventory Snapshots")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Export")
    }
}

/// Settings view for app configuration
/// Enhanced Settings View with organized sections matching ASCII specifications
struct SettingsView: View {
    @ObservedObject var dataStore: DataStore
    @State private var iCloudSyncEnabled = false
    @State private var dataRetentionPeriod = "1 year"
    @State private var inventoryTrackingEnabled = true
    @State private var refillReminderThreshold = "10 days"
    @State private var doseRemindersEnabled = true
    @State private var criticalAlertsEnabled = true
    @State private var autoSnoozeEnabled = true
    @State private var autoDetectTimezone = true
    @State private var currentTimezone = "America/New_York"
    
    private let dataRetentionOptions = ["6 months", "1 year", "2 years", "Forever"]
    private let refillReminderOptions = ["5 days", "7 days", "10 days", "14 days", "21 days"]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    syncBackupSection
                    medicationInventorySection
                    notificationsAlertsSection
                    travelTimeZoneSection
                    supportPrivacySection
                    doneButtonSection
                }
                .padding()
            }
            .navigationTitle("Settings")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Settings")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            
            Text("Configure DoseTap to match your preferences")
                .font(.body)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var syncBackupSection: some View {
        settingsSection(title: "Sync & Backup") {
            VStack(spacing: 16) {
                settingsRow(
                    title: "Sync with iCloud",
                    value: iCloudSyncEnabled ? "ON" : "OFF",
                    valueColor: iCloudSyncEnabled ? .green : .secondary
                ) {
                    Toggle("", isOn: $iCloudSyncEnabled)
                        .toggleStyle(SwitchToggleStyle())
                }
                
                Text("(Private iCloud only)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                settingsRow(
                    title: "Data retention",
                    value: dataRetentionPeriod,
                    valueColor: .blue
                ) {
                    Picker("", selection: $dataRetentionPeriod) {
                        ForEach(dataRetentionOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }
    
    private var medicationInventorySection: some View {
        settingsSection(title: "Medication & Inventory") {
            VStack(spacing: 16) {
                navigationRow(
                    title: "Medication profile",
                    value: "XYWAV",
                    destination: AnyView(Text("Medication Profile"))
                )
                
                settingsRow(
                    title: "Inventory tracking",
                    value: inventoryTrackingEnabled ? "ON" : "OFF",
                    valueColor: inventoryTrackingEnabled ? .green : .secondary
                ) {
                    Toggle("", isOn: $inventoryTrackingEnabled)
                        .toggleStyle(SwitchToggleStyle())
                }
                
                settingsRow(
                    title: "Refill reminders",
                    value: refillReminderThreshold,
                    valueColor: .blue
                ) {
                    Picker("", selection: $refillReminderThreshold) {
                        ForEach(refillReminderOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }
    
    private var notificationsAlertsSection: some View {
        settingsSection(title: "Notifications & Alerts") {
            VStack(spacing: 16) {
                settingsRow(
                    title: "Dose reminders",
                    value: doseRemindersEnabled ? "ON" : "OFF",
                    valueColor: doseRemindersEnabled ? .green : .secondary
                ) {
                    Toggle("", isOn: $doseRemindersEnabled)
                        .toggleStyle(SwitchToggleStyle())
                }
                
                settingsRow(
                    title: "Critical alerts",
                    value: criticalAlertsEnabled ? "Enabled" : "Disabled",
                    valueColor: criticalAlertsEnabled ? .green : .secondary
                ) {
                    Toggle("", isOn: $criticalAlertsEnabled)
                        .toggleStyle(SwitchToggleStyle())
                }
                
                settingsRow(
                    title: "Auto-snooze",
                    value: autoSnoozeEnabled ? "ON" : "OFF",
                    valueColor: autoSnoozeEnabled ? .green : .secondary
                ) {
                    Toggle("", isOn: $autoSnoozeEnabled)
                        .toggleStyle(SwitchToggleStyle())
                }
            }
        }
    }
    
    private var travelTimeZoneSection: some View {
        settingsSection(title: "Travel & Time Zones") {
            VStack(spacing: 16) {
                settingsRow(
                    title: "Auto-detect changes",
                    value: autoDetectTimezone ? "ON" : "OFF",
                    valueColor: autoDetectTimezone ? .green : .secondary
                ) {
                    Toggle("", isOn: $autoDetectTimezone)
                        .toggleStyle(SwitchToggleStyle())
                }
                
                HStack {
                    Text("Current timezone")
                        .font(.body)
                    
                    Spacer()
                    
                    Text(currentTimezone)
                        .font(.body)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlColor))
                        .cornerRadius(6)
                }
            }
        }
    }
    
    private var supportPrivacySection: some View {
        settingsSection(title: "Support & Privacy") {
            VStack(spacing: 16) {
                navigationRow(
                    title: "Export support bundle",
                    value: "",
                    destination: AnyView(SupportDiagnosticsView())
                )
                
                navigationRow(
                    title: "Privacy policy",
                    value: "",
                    destination: AnyView(Text("Privacy Policy"))
                )
                
                navigationRow(
                    title: "About & version",
                    value: "",
                    destination: AnyView(Text("About DoseTap Studio v1.0"))
                )
            }
        }
    }
    
    private var doneButtonSection: some View {
        Button("Done") {
            // Handle done action
            print("⚙️ Settings saved")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.accentColor)
        .foregroundColor(.white)
        .cornerRadius(8)
        .accessibilityLabel("Done with settings")
        .padding(.top, 8)
    }
    
    // MARK: - Helper Views
    
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .fontWeight(.medium)
                .accessibilityAddTraits(.isHeader)
            
            VStack(spacing: 12) {
                content()
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func settingsRow<Control: View>(
        title: String,
        value: String,
        valueColor: Color = .secondary,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            Text(title)
                .font(.body)
            
            Spacer()
            
            if !value.isEmpty {
                Text(value)
                    .font(.body)
                    .foregroundColor(valueColor)
                    .padding(.trailing, 8)
            }
            
            control()
        }
    }
    
    private func navigationRow(title: String, value: String, destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if !value.isEmpty {
                    Text(value)
                        .font(.body)
                        .foregroundColor(.blue)
                        .padding(.trailing, 8)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
