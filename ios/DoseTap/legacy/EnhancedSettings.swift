// iOS/EnhancedSettings.swift
#if os(iOS)
import SwiftUI
import CoreData

// MARK: - Enhanced Settings ModelS/EnhancedSettings.swift
import SwiftUI
import CoreData

// MARK: - Enhanced Settings View

struct EnhancedSettingsView: View {
    @State private var selectedTab = 0
    @State private var showingAbout = false
    @State private var showingDataExport = false
    
    var body: some View {
        NavigationView {
            List {
                // Quick Actions Section
                Section {
                    QuickActionsRow()
                }
                
                // Core Settings
                Section("Dosing") {
                    NavigationLink(destination: DosingSettingsView()) {
                        SettingsRow(
                            icon: "pills.fill",
                            iconColor: .blue,
                            title: "Dose Schedule",
                            subtitle: "Timing and reminders"
                        )
                    }
                    
                    NavigationLink(destination: InventoryManagementView()) {
                        SettingsRow(
                            icon: "chart.bar.doc.horizontal",
                            iconColor: .green,
                            title: "Inventory Tracking",
                            subtitle: "Monitor medication supply"
                        )
                    }
                }
                
                // Health & Safety
                Section("Health & Safety") {
                    NavigationLink(destination: EmergencyContactsView()) {
                        SettingsRow(
                            icon: "phone.fill.badge.plus",
                            iconColor: .red,
                            title: "Emergency Contacts",
                            subtitle: "Healthcare provider info"
                        )
                    }
                    
                    NavigationLink(destination: TimeZoneDetectionView()) {
                        SettingsRow(
                            icon: "globe",
                            iconColor: .orange,
                            title: "Travel Mode",
                            subtitle: "Time zone management"
                        )
                    }
                }
                
                // Privacy & Data
                Section("Privacy & Data") {
                    NavigationLink(destination: PrivacySettingsView()) {
                        SettingsRow(
                            icon: "hand.raised.fill",
                            iconColor: .purple,
                            title: "Privacy Settings",
                            subtitle: "Data collection preferences"
                        )
                    }
                    
                    Button(action: {
                        showingDataExport = true
                    }) {
                        SettingsRow(
                            icon: "square.and.arrow.up",
                            iconColor: .blue,
                            title: "Export Data",
                            subtitle: "Download your information"
                        )
                    }
                    .foregroundColor(.primary)
                }
                
                // Accessibility
                Section("Accessibility") {
                    NavigationLink(destination: AccessibilitySettingsView()) {
                        SettingsRow(
                            icon: "accessibility",
                            iconColor: .blue,
                            title: "Accessibility",
                            subtitle: "VoiceOver and display options"
                        )
                    }
                    
                    NavigationLink(destination: NotificationSettingsView()) {
                        SettingsRow(
                            icon: "bell.fill",
                            iconColor: .orange,
                            title: "Notifications",
                            subtitle: "Alerts and reminders"
                        )
                    }
                }
                
                // Support
                Section("Support") {
                    NavigationLink(destination: SupportBundleExportView()) {
                        SettingsRow(
                            icon: "doc.zipper",
                            iconColor: .gray,
                            title: "Support Bundle",
                            subtitle: "Send diagnostic data"
                        )
                    }
                    
                    NavigationLink(destination: HelpCenterView()) {
                        SettingsRow(
                            icon: "questionmark.circle.fill",
                            iconColor: .blue,
                            title: "Help Center",
                            subtitle: "FAQs and guidance"
                        )
                    }
                    
                    Button(action: {
                        showingAbout = true
                    }) {
                        SettingsRow(
                            icon: "info.circle.fill",
                            iconColor: .gray,
                            title: "About DoseTap",
                            subtitle: "Version and legal info"
                        )
                    }
                    .foregroundColor(.primary)
                }
                
                // Developer Options (Debug builds only)
                #if DEBUG
                Section("Developer") {
                    NavigationLink(destination: DeveloperOptionsView()) {
                        SettingsRow(
                            icon: "wrench.fill",
                            iconColor: .gray,
                            title: "Developer Options",
                            subtitle: "Debug tools and settings"
                        )
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .listStyle(InsetGroupedListStyle())
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingDataExport) {
                DataExportView()
            }
        }
    }
}

// MARK: - Settings Row Component

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let showChevron: Bool
    
    init(icon: String, iconColor: Color, title: String, subtitle: String, showChevron: Bool = true) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.showChevron = showChevron
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconColor)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

// MARK: - Quick Actions Row

struct QuickActionsRow: View {
    @State private var showingDoseLog = false
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Quick Actions")
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack(spacing: 16) {
                QuickActionButton(
                    icon: "pills.fill",
                    title: "Log Dose",
                    color: .blue
                ) {
                    showingDoseLog = true
                }
                
                QuickActionButton(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "View Stats",
                    color: .green
                ) {
                    // Navigate to stats
                }
                
                QuickActionButton(
                    icon: "bell.badge.fill",
                    title: "Reminders",
                    color: .orange
                ) {
                    showingSettings = true
                }
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showingDoseLog) {
            DoseLogSheet()
        }
        .sheet(isPresented: $showingSettings) {
            NotificationSettingsView()
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(color)
                    )
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // App Icon and Name
                    VStack(spacing: 16) {
                        Image(systemName: "pills.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.blue)
                        
                        VStack(spacing: 4) {
                            Text("DoseTap")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Version \(appVersion) (\(buildNumber))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Description
                    Text("Your trusted companion for XYWAV medication management. Designed to help you maintain consistent dosing schedules and track your medication safely.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    // Links
                    VStack(spacing: 12) {
                        AboutLinkRow(title: "Privacy Policy", systemImage: "hand.raised.fill")
                        AboutLinkRow(title: "Terms of Service", systemImage: "doc.text.fill")
                        AboutLinkRow(title: "Support", systemImage: "questionmark.circle.fill")
                        AboutLinkRow(title: "Rate App", systemImage: "star.fill")
                    }
                    
                    // Copyright
                    Text("© 2024 DoseTap. All rights reserved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top)
                }
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AboutLinkRow: View {
    let title: String
    let systemImage: String
    
    var body: some View {
        Button(action: {
            // Handle link tap
        }) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Data Export View

struct DataExportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat = ExportFormat.json
    @State private var includePersonalData = false
    @State private var dateRange = DateRange.all
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    
    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case csv = "CSV"
        case pdf = "PDF Report"
        
        var description: String {
            switch self {
            case .json: return "Machine-readable format"
            case .csv: return "Spreadsheet compatible"
            case .pdf: return "Human-readable report"
            }
        }
    }
    
    enum DateRange: String, CaseIterable {
        case week = "Last 7 days"
        case month = "Last 30 days"
        case year = "Last year"
        case all = "All data"
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Export Format") {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.rawValue)
                                    .fontWeight(.medium)
                                Text(format.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if selectedFormat == format {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFormat = format
                        }
                    }
                }
                
                Section("Date Range") {
                    Picker("Date Range", selection: $dateRange) {
                        ForEach(DateRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Section("Privacy Options") {
                    Toggle("Include personal identifiers", isOn: $includePersonalData)
                    
                    Text("Personal identifiers include device ID and timestamps. Disable to anonymize your export.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isExporting {
                    Section {
                        VStack(spacing: 12) {
                            Text("Exporting data...")
                                .fontWeight(.medium)
                            
                            ProgressView(value: exportProgress, total: 1.0)
                            
                            Text("\(Int(exportProgress * 100))% complete")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export") {
                        startExport()
                    }
                    .disabled(isExporting)
                }
            }
        }
    }
    
    private func startExport() {
        isExporting = true
        exportProgress = 0
        
        // Simulate export progress
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            exportProgress += 0.05
            if exportProgress >= 1.0 {
                timer.invalidate()
                completeExport()
            }
        }
    }
    
    private func completeExport() {
        // Handle export completion
        isExporting = false
        dismiss()
    }
}

// MARK: - Placeholder Views for Navigation

struct DosingSettingsView: View {
    var body: some View {
        Text("Dosing Settings")
            .navigationTitle("Dose Schedule")
            .navigationBarTitleDisplayMode(.large)
    }
}

struct EmergencyContactsView: View {
    var body: some View {
        Text("Emergency Contacts")
            .navigationTitle("Emergency Contacts")
            .navigationBarTitleDisplayMode(.large)
    }
}

struct PrivacySettingsView: View {
    var body: some View {
        Text("Privacy Settings")
            .navigationTitle("Privacy Settings")
            .navigationBarTitleDisplayMode(.large)
    }
}

struct AccessibilitySettingsView: View {
    var body: some View {
        Text("Accessibility Settings")
            .navigationTitle("Accessibility")
            .navigationBarTitleDisplayMode(.large)
    }
}

struct NotificationSettingsView: View {
    var body: some View {
        Text("Notification Settings")
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
    }
}

struct HelpCenterView: View {
    var body: some View {
        Text("Help Center")
            .navigationTitle("Help Center")
            .navigationBarTitleDisplayMode(.large)
    }
}

struct DoseLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Text("Dose Log Entry")
                .navigationTitle("Log Dose")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

#if DEBUG
struct DeveloperOptionsView: View {
    var body: some View {
        Text("Developer Options")
            .navigationTitle("Developer Options")
            .navigationBarTitleDisplayMode(.large)
    }
}
#endif

#endif // os(iOS)
