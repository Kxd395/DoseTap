import SwiftUI

// Extracted from SettingsView.swift — Event cooldown configuration

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
