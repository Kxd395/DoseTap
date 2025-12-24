import SwiftUI
import DoseCore

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var core = DoseTapCore()
    @StateObject private var settings = UserSettingsManager.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Status Header
                    StatusCard(status: core.currentStatus)
                    
                    // Main Dose Buttons
                    DoseButtonsSection(core: core)
                    
                    // Session Info
                    SessionInfoSection(core: core)
                }
                .padding()
            }
            .navigationTitle("DoseTap")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .preferredColorScheme(settings.colorScheme)
    }
}

// MARK: - Status Card
struct StatusCard: View {
    let status: DoseStatus
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: statusIcon)
                    .font(.title2)
                Text(statusTitle)
                    .font(.headline)
            }
            .foregroundColor(statusColor)
            
            Text(statusDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(statusColor.opacity(0.1))
        )
    }
    
    private var statusIcon: String {
        switch status {
        case .noDose1: return "1.circle"
        case .beforeWindow: return "clock"
        case .active: return "checkmark.circle"
        case .nearClose: return "exclamationmark.triangle"
        case .closed: return "xmark.circle"
        case .completed: return "checkmark.seal.fill"
        }
    }
    
    private var statusTitle: String {
        switch status {
        case .noDose1: return "Ready for Dose 1"
        case .beforeWindow: return "Waiting for Window"
        case .active: return "Window Open"
        case .nearClose: return "Window Closing Soon"
        case .closed: return "Window Closed"
        case .completed: return "Complete"
        }
    }
    
    private var statusDescription: String {
        switch status {
        case .noDose1: return "Take Dose 1 to start your session"
        case .beforeWindow: return "Wait for the dosing window to open (150 min)"
        case .active: return "Dosing window is open - Take Dose 2"
        case .nearClose: return "Less than 15 minutes remaining"
        case .closed: return "Window has closed (240 min max)"
        case .completed: return "Both doses taken successfully"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .noDose1: return .blue
        case .beforeWindow: return .orange
        case .active: return .green
        case .nearClose: return .red
        case .closed: return .gray
        case .completed: return .purple
        }
    }
}

// MARK: - Dose Buttons Section
struct DoseButtonsSection: View {
    @ObservedObject var core: DoseTapCore
    
    var body: some View {
        VStack(spacing: 12) {
            // Primary Dose Button
            Button(action: { Task { await core.takeDose() } }) {
                Text(primaryButtonText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(primaryButtonColor)
                    .cornerRadius(12)
            }
            .disabled(core.currentStatus == .completed || core.currentStatus == .closed)
            
            // Secondary Actions
            HStack(spacing: 12) {
                Button("Snooze +10m") {
                    Task { await core.snooze() }
                }
                .buttonStyle(.bordered)
                .disabled(!snoozeEnabled)
                
                Button("Skip Dose") {
                    Task { await core.skipDose() }
                }
                .buttonStyle(.bordered)
                .disabled(!skipEnabled)
            }
        }
    }
    
    private var primaryButtonText: String {
        switch core.currentStatus {
        case .noDose1: return "Take Dose 1"
        case .beforeWindow: return "Waiting..."
        case .active, .nearClose: return "Take Dose 2"
        case .closed: return "Window Closed"
        case .completed: return "Complete ✓"
        }
    }
    
    private var primaryButtonColor: Color {
        switch core.currentStatus {
        case .noDose1: return .blue
        case .beforeWindow: return .gray
        case .active: return .green
        case .nearClose: return .orange
        case .closed: return .gray
        case .completed: return .purple
        }
    }
    
    private var snoozeEnabled: Bool {
        (core.currentStatus == .active || core.currentStatus == .nearClose) && core.snoozeCount < 3
    }
    
    private var skipEnabled: Bool {
        core.currentStatus == .active || core.currentStatus == .nearClose
    }
}

// MARK: - Session Info Section
struct SessionInfoSection: View {
    @ObservedObject var core: DoseTapCore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Info")
                .font(.headline)
            
            HStack {
                InfoRow(label: "Dose 1", value: core.dose1Time?.formatted(date: .omitted, time: .shortened) ?? "Not taken")
                Spacer()
                InfoRow(label: "Dose 2", value: core.dose2Time?.formatted(date: .omitted, time: .shortened) ?? (core.isSkipped ? "Skipped" : "Pending"))
            }
            
            HStack {
                InfoRow(label: "Snoozes", value: "\(core.snoozeCount)/3")
                Spacer()
                InfoRow(label: "Status", value: statusText)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    private var statusText: String {
        switch core.currentStatus {
        case .noDose1: return "Waiting"
        case .beforeWindow: return "Pre-window"
        case .active: return "Active"
        case .nearClose: return "Closing"
        case .closed: return "Closed"
        case .completed: return "Done"
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
