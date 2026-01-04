import SwiftUI
import DoseCore

/// Detailed view for diagnostic logging settings
struct DiagnosticLoggingSettingsView: View {
    @ObservedObject private var settings = UserSettingsManager.shared
    
    var body: some View {
        List {
            Section {
                Toggle(isOn: $settings.diagnosticLoggingEnabled) {
                    Label("Enable Diagnostic Logging", systemImage: "doc.text")
                }
                .onChange(of: settings.diagnosticLoggingEnabled) { newValue in
                    Task {
                        await DiagnosticLogger.shared.updateSettings(
                            isEnabled: newValue,
                            tier2Enabled: settings.diagnosticTier2Enabled,
                            tier3Enabled: settings.diagnosticTier3Enabled
                        )
                    }
                }
            } footer: {
                Text("Creates local JSONL logs for troubleshooting. All logs stay on your device.")
            }
            
            if settings.diagnosticLoggingEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tier 1: Safety-Critical")
                                    .font(.subheadline.bold())
                                Text("Always logged: app lifecycle, timezone changes, undo actions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $settings.diagnosticTier2Enabled) {
                            HStack {
                                Image(systemName: "2.circle.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Tier 2: Session Context")
                                        .font(.subheadline.bold())
                                    Text("Sleep events, pre-sleep logs, check-ins, session flow")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onChange(of: settings.diagnosticTier2Enabled) { newValue in
                            Task {
                                await DiagnosticLogger.shared.updateSettings(
                                    isEnabled: settings.diagnosticLoggingEnabled,
                                    tier2Enabled: newValue,
                                    tier3Enabled: settings.diagnosticTier3Enabled
                                )
                            }
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $settings.diagnosticTier3Enabled) {
                            HStack {
                                Image(systemName: "3.circle.fill")
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Tier 3: Forensic")
                                        .font(.subheadline.bold())
                                    Text("Full state snapshots (not yet implemented)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onChange(of: settings.diagnosticTier3Enabled) { newValue in
                            Task {
                                await DiagnosticLogger.shared.updateSettings(
                                    isEnabled: settings.diagnosticLoggingEnabled,
                                    tier2Enabled: settings.diagnosticTier2Enabled,
                                    tier3Enabled: newValue
                                )
                            }
                        }
                        .disabled(true) // Not implemented yet
                    }
                    .padding(.vertical, 8)
                } header: {
                    Label("Logging Tiers", systemImage: "chart.bar.fill")
                } footer: {
                    Text("Choose what level of detail to capture. More tiers = larger log files.")
                }
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        Text("Privacy Promise")
                            .font(.subheadline.bold())
                    }
                    
                    Text("• All logs stored locally in Documents/diagnostics/")
                        .font(.caption)
                    Text("• No automatic uploads or transmissions")
                        .font(.caption)
                    Text("• You control when to export and share")
                        .font(.caption)
                    Text("• No personal identifiers included")
                        .font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Diagnostic Logging")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationView {
        DiagnosticLoggingSettingsView()
    }
}
