import SwiftUI

/// Sidebar navigation for different views and data summary
struct SidebarView: View {
    @ObservedObject var dataStore: DataStore
    
    var body: some View {
        let analytics = dataStore.analytics
        
        List {
            // Data Summary Section
            Section("Data Summary") {
                Label("\(analytics.totalEvents) Events", systemImage: "list.bullet")
                Label("\(analytics.totalSessions) Sessions", systemImage: "clock")
                
                if let inventory = dataStore.currentInventory {
                    Label("\(inventory.dosesRemaining) Doses Left", systemImage: "pills")
                }
            }
            
            // Navigation Section
            Section("Analytics") {
                NavigationLink(destination: DashboardView(dataStore: dataStore)) {
                    Label("Dashboard", systemImage: "chart.bar")
                }
                
                NavigationLink(destination: TimelineView(dataStore: dataStore)) {
                    Label("Timeline", systemImage: "clock")
                }
                
                NavigationLink(destination: AdherenceView(dataStore: dataStore)) {
                    Label("Adherence", systemImage: "checkmark.circle")
                }
            }
            
            // Enhanced Features
            Section("Management") {
                NavigationLink(destination: EnhancedInventoryView(dataStore: dataStore)) {
                    Label("Enhanced Inventory", systemImage: "pills.fill")
                }
                
                NavigationLink(destination: InventoryView(dataStore: dataStore)) {
                    Label("Basic Inventory", systemImage: "pills")
                }
                
                NavigationLink(destination: TimeZoneManagementView()) {
                    Label("Travel & Time Zones", systemImage: "globe")
                }
                
                NavigationLink(destination: SupportDiagnosticsView()) {
                    Label("Support & Diagnostics", systemImage: "wrench.and.screwdriver")
                }
                
                NavigationLink(destination: ExportView(dataStore: dataStore)) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            
            // Configuration
            Section("Setup") {
                NavigationLink(destination: SetupWizardView(dataStore: dataStore)) {
                    Label("Setup Wizard", systemImage: "gear.circle")
                }
                
                NavigationLink(destination: SettingsView(dataStore: dataStore)) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            
            // Status Section
            Section("Status") {
                switch dataStore.importStatus {
                case .none:
                    Label("No data loaded", systemImage: "xmark.circle")
                        .foregroundColor(.secondary)
                case .importing:
                    Label("Importing...", systemImage: "arrow.clockwise")
                        .foregroundColor(.blue)
                case .success(let count):
                    Label("\(count) events imported", systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                case .error(let message):
                    Label("Error: \(message)", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.red)
                }
                
                if let lastImported = dataStore.lastImported {
                    Label(
                        "Updated \(lastImported.formatted(date: .omitted, time: .shortened))",
                        systemImage: "clock"
                    )
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
            }
            
            // Demo & Testing
            Section("Demo Features") {
                NavigationLink(destination: NotificationDemoView()) {
                    Label("Notification Banners", systemImage: "bell.badge")
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        .navigationTitle("DoseTap Studio")
    }
}

#Preview {
    SidebarView(dataStore: DataStore())
}
