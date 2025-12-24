import SwiftUI

@main
struct DoseTapiOSApp: App {
    @StateObject private var dataStorage = DataStorageService.shared
    @StateObject private var healthService = HealthDataService.shared
    @StateObject private var whoopService = WHOOPDataService.shared
    @StateObject private var configManager = UserConfigurationManager.shared
    
    var body: some Scene {
        WindowGroup {
            Group {
                if configManager.isConfigured {
                    MainTabView()
                        .environmentObject(dataStorage)
                        .environmentObject(healthService)
                        .environmentObject(whoopService)
                        .environmentObject(configManager)
                        .onAppear {
                            // Auto-sync health data on app launch
                            Task {
                                await syncHealthData()
                            }
                        }
                } else {
                    SetupWizardView(isSetupComplete: Binding(
                        get: { configManager.isConfigured },
                        set: { _ in configManager.loadConfiguration() }
                    ))
                    .environmentObject(configManager)
                }
            }
        }
    }
    
    private func syncHealthData() async {
        // Sync health data in background
        if healthService.isAuthorized {
            try? await healthService.fetchRecentSleepData()
            await healthService.syncWithCurrentSession()
        }
        
        if whoopService.isConnected {
            try? await whoopService.fetchRecentSleepData()
            await whoopService.syncWithCurrentSession()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var dataStorage: DataStorageService
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Image(systemName: "pills.fill")
                    Text("Dose")
                }
                .tag(0)
            
            DashboardView()
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Dashboard")
                }
                .tag(1)
            
            InventoryView()
                .tabItem {
                    Image(systemName: "list.clipboard.fill")
                    Text("Inventory")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(3)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var dataStorage: DataStorageService
    @EnvironmentObject private var healthService: HealthDataService
    @EnvironmentObject private var whoopService: WHOOPDataService
    
    @State private var showingDoseHistory = false
    @State private var showingExitConfirmation = false
    
    private var currentSession: DoseSessionData? {
        dataStorage.currentSession
    }
    
    private var dose1Time: Date? {
        currentSession?.events.first { $0.type == .dose1 }?.timestamp
    }
    
    private var dose2Time: Date? {
        currentSession?.events.first { $0.type == .dose2 }?.timestamp
    }
    
    private var snoozeCount: Int {
        currentSession?.events.filter { $0.type == .snooze }.count ?? 0
    }
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text("DoseTap")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if let session = currentSession {
                        Text("Session: \(session.startTime, style: .date)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                
                // Main Dose Interface
                VStack(spacing: 20) {
                    if dose1Time == nil {
                        // Initial state - no dose taken
                        VStack(spacing: 16) {
                            Text("Ready to start your dose schedule")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                            
                            Button("Take Dose 1") {
                                takeDose1()
                            }
                            .font(.title2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    } else {
                        // Dose 1 taken - show status and next actions
                        VStack(spacing: 16) {
                            // Dose 1 Status
                            VStack(spacing: 8) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.title2)
                                    Text("Dose 1 Complete")
                                        .font(.headline)
                                        .fontWeight(.medium)
                                }
                                
                                Text("Taken at \(dose1Time!, formatter: timeFormatter)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                            
                            if dose2Time == nil {
                                // Waiting for dose 2
                                VStack(spacing: 12) {
                                    Text("Next dose window: 2.5-4 hours")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                    
                                    if let nextDoseTime = calculateNextDoseWindow() {
                                        Text("Optimal time: \(nextDoseTime, formatter: timeFormatter)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(spacing: 16) {
                                        Button("Take Dose 2") {
                                            takeDose2()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .font(.headline)
                                        
                                        Button("Snooze \(snoozeCount > 0 ? "(\(snoozeCount))" : "")") {
                                            snooze()
                                        }
                                        .buttonStyle(.bordered)
                                        
                                        Button("Bathroom") {
                                            logBathroom()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding()
                            } else {
                                // Both doses taken - session complete
                                VStack(spacing: 12) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.title2)
                                        Text("Session Complete")
                                            .font(.headline)
                                            .fontWeight(.medium)
                                    }
                                    
                                    Text("Dose 2 taken at \(dose2Time!, formatter: timeFormatter)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    if let interval = calculateInterval() {
                                        HStack {
                                            Text("Interval:")
                                            Text(formatDuration(interval))
                                                .fontWeight(.medium)
                                                .foregroundColor(intervalColor(interval))
                                        }
                                        .font(.subheadline)
                                    }
                                    
                                    Button("Start New Session") {
                                        startNewSession()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .padding(.top)
                                }
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Quick Actions
                VStack(spacing: 12) {
                    Button("View History") {
                        showingDoseHistory = true
                    }
                    .foregroundColor(.blue)

#if DEBUG
                    Button("Close App") {
                        showingExitConfirmation = true
                    }
                    .foregroundColor(.red)
                    .font(.caption)
#endif
                }
            }
            .padding()
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingDoseHistory) {
            NavigationView {
                EventHistoryView()
                    .navigationTitle("Dose History")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingDoseHistory = false
                            }
                        }
                    }
            }
        }
        .alert("Close DoseTap", isPresented: $showingExitConfirmation) {
            Button("Cancel", role: .cancel) { }
#if DEBUG
            Button("Close App", role: .destructive) {
                closeApp()
            }
#endif
        } message: {
            Text("All data will be saved before closing. Are you sure you want to exit?")
        }
    }
    
    // MARK: - Actions
    private func takeDose1() {
        dataStorage.logEvent(.dose1)
        
        // Sync health data for better timing recommendations
        Task {
            if healthService.isAuthorized {
                try? await healthService.fetchRecentSleepData()
                await healthService.syncWithCurrentSession()
            }
            
            if whoopService.isConnected {
                try? await whoopService.fetchRecentSleepData()
                await whoopService.syncWithCurrentSession()
            }
        }
    }
    
    private func takeDose2() {
        dataStorage.logEvent(.dose2)
        dataStorage.completeCurrentSession()
    }
    
    private func snooze() {
        dataStorage.logEvent(.snooze, metadata: ["count": "\(snoozeCount + 1)"])
    }
    
    private func logBathroom() {
        dataStorage.logEvent(.bathroom)
    }
    
    private func startNewSession() {
        dataStorage.startNewSession()
    }
    
    private func closeApp() {
        // Ensure all data is saved
        // Note: In iOS, apps don't typically programmatically exit
        // This is more of a visual confirmation for the user
    #if DEBUG
    exit(0)
    #else
    // In release builds, do nothing. SSOT requires no process termination control.
    #endif
    }
    
    // MARK: - Calculations
    private func calculateNextDoseWindow() -> Date? {
        guard let dose1Time = dose1Time else { return nil }
        // Optimal time is 2.75 hours (165 minutes) after dose 1
        return dose1Time.addingTimeInterval(165 * 60)
    }
    
    private func calculateInterval() -> TimeInterval? {
        guard let d1 = dose1Time, let d2 = dose2Time else { return nil }
        return d2.timeIntervalSince(d1)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    private func intervalColor(_ duration: TimeInterval) -> Color {
        let minutes = duration / 60
        if minutes >= 150 && minutes <= 240 {
            return .green
        } else if minutes >= 120 && minutes < 150 {
            return .orange
        } else {
            return .red
        }
    }
}

#Preview {
    ContentView()
}
