import SwiftUI

/// WHOOP Settings View for connecting and managing WHOOP integration
struct WHOOPSettingsView: View {
    @StateObject private var whoop = WHOOPService.shared
    @State private var isAuthorizing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showDisconnectConfirm = false
    @State private var sleepHistory: [WHOOPNightSummary] = []
    @State private var isLoadingHistory = false
    
    var body: some View {
        List {
            // Connection Status Section
            Section {
                connectionStatusRow
                
                if whoop.isConnected {
                    if let profile = whoop.userProfile {
                        profileRow(profile)
                    }
                    
                    if let lastSync = whoop.lastSyncTime {
                        HStack {
                            Label("Last Sync", systemImage: "arrow.clockwise")
                            Spacer()
                            Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Label("Connection", systemImage: "link")
            }
            
            // Actions Section
            Section {
                if whoop.isConnected {
                    Button(action: syncNow) {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isLoadingHistory)
                    
                    Button(role: .destructive) {
                        showDisconnectConfirm = true
                    } label: {
                        Label("Disconnect WHOOP", systemImage: "link.badge.minus")
                    }
                } else {
                    Button(action: connectWHOOP) {
                        HStack {
                            Label("Connect WHOOP", systemImage: "link.badge.plus")
                            Spacer()
                            if isAuthorizing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isAuthorizing)
                }
            } header: {
                Label("Actions", systemImage: "hand.tap")
            }
            
            // Sleep History Section (when connected)
            if whoop.isConnected && !sleepHistory.isEmpty {
                Section {
                    ForEach(sleepHistory) { night in
                        sleepNightRow(night)
                    }
                } header: {
                    HStack {
                        Label("Recent Sleep", systemImage: "moon.zzz.fill")
                        Spacer()
                        if isLoadingHistory {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                } footer: {
                    Text("Last 7 nights from WHOOP")
                }
            }
            
            // Info Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("About WHOOP Integration")
                            .font(.subheadline.bold())
                    }
                    
                    Text("Connect your WHOOP to import sleep stages, HRV, and respiratory rate data for enhanced sleep analysis.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Link(destination: URL(string: "https://www.whoop.com")!) {
                        Text("Learn more about WHOOP →")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("WHOOP")
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog("Disconnect WHOOP?", isPresented: $showDisconnectConfirm) {
            Button("Disconnect", role: .destructive) {
                whoop.disconnect()
                sleepHistory = []
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove your WHOOP connection. You can reconnect anytime.")
        }
        .task {
            if whoop.isConnected {
                await loadSleepHistory()
            }
        }
    }
    
    // MARK: - View Components
    
    private var connectionStatusRow: some View {
        HStack {
            Image(systemName: whoop.isConnected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(whoop.isConnected ? .green : .secondary)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(whoop.isConnected ? "Connected" : "Not Connected")
                    .font(.headline)
                if whoop.isConnected {
                    Text("WHOOP account linked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func profileRow(_ profile: WHOOPProfile) -> some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                if let first = profile.firstName, let last = profile.lastName {
                    Text("\(first) \(last)")
                        .font(.subheadline)
                }
                if let email = profile.email {
                    Text(email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func sleepNightRow(_ night: WHOOPNightSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(night.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.bold())
                Spacer()
                Text(night.formattedTotalSleep)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Sleep stage breakdown
            HStack(spacing: 12) {
                stageIndicator(label: "Deep", minutes: night.deepMinutes, color: .indigo)
                stageIndicator(label: "REM", minutes: night.remMinutes, color: .purple)
                stageIndicator(label: "Light", minutes: night.lightMinutes, color: .blue.opacity(0.6))
                stageIndicator(label: "Awake", minutes: night.awakeMinutes, color: .red.opacity(0.6))
            }
            .font(.caption)
            
            // Additional metrics
            HStack(spacing: 16) {
                if let efficiency = night.sleepEfficiency {
                    metricBadge(value: "\(Int(efficiency))%", label: "Efficiency")
                }
                if let rr = night.respiratoryRate {
                    metricBadge(value: String(format: "%.1f", rr), label: "RR")
                }
                if night.disturbanceCount > 0 {
                    metricBadge(value: "\(night.disturbanceCount)", label: "Disturbances")
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func stageIndicator(label: String, minutes: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(minutes)m")
                .foregroundColor(.secondary)
        }
    }
    
    private func metricBadge(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func connectWHOOP() {
        isAuthorizing = true
        
        Task {
            do {
                try await whoop.authorize()
                await loadSleepHistory()
            } catch WHOOPError.userCancelled {
                // User cancelled - no error
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isAuthorizing = false
        }
    }
    
    private func syncNow() {
        Task {
            await loadSleepHistory()
        }
    }
    
    private func loadSleepHistory() async {
        isLoadingHistory = true
        
        do {
            let sleeps = try await whoop.fetchRecentSleep(nights: 7)
            sleepHistory = sleeps.map { $0.toNightSummary() }
        } catch {
            errorMessage = "Failed to load sleep data: \(error.localizedDescription)"
            showError = true
        }
        
        isLoadingHistory = false
    }
}

// MARK: - Compact WHOOP Status for Settings List

struct WHOOPStatusRow: View {
    @StateObject private var whoop = WHOOPService.shared
    
    var body: some View {
        NavigationLink {
            WHOOPSettingsView()
        } label: {
            HStack {
                Image(systemName: "w.circle.fill")
                    .foregroundColor(.black)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("WHOOP")
                        .font(.body)
                    Text(whoop.isConnected ? "Connected" : "Not connected")
                        .font(.caption)
                        .foregroundColor(whoop.isConnected ? .green : .secondary)
                }
                
                Spacer()
                
                if whoop.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct WHOOPSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WHOOPSettingsView()
        }
    }
}
#endif
