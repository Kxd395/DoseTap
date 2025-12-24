import SwiftUI
import Foundation

/// First-run setup wizard for configuring DoseTap Studio
struct SetupWizardView: View {
    @ObservedObject var dataStore: DataStore
    @State private var currentStep = 0
    @State private var isCompleted = false
    
    // Step 1: Sleep Schedule
    @State private var bedtime = Calendar.current.date(from: DateComponents(hour: 1, minute: 0)) ?? Date()
    @State private var wakeTime = Calendar.current.date(from: DateComponents(hour: 6, minute: 30)) ?? Date()
    @State private var timeZone = TimeZone.current
    @State private var bedtimeVaries = true
    
    // Step 2: Medication Profile
    @State private var medicationName = "XYWAV"
    @State private var dose1Mg = "450"
    @State private var dose2Mg = "225"
    @State private var dosesPerBottle = "60"
    @State private var bottleMg = "9000"
    
    // Step 3: Dose Window Rules
    @State private var targetInterval = 165
    @State private var snoozeStep = 10
    @State private var maxSnoozes = 3
    @State private var undoWindow = 5  // Per SSOT: 5s default, range 3-10s
    
    // Step 4: Notifications & Permissions
    @State private var allowNotifications = true
    @State private var criticalAlertsEnabled = true
    @State private var autoSnoozeEnabled = true
    @State private var focusOverrideEnabled = false
    
    // Step 5: Privacy & Sync
    @State private var dataStorage = "Local Device Only"
    @State private var iCloudSyncEnabled = false
    @State private var dataRetention = "1 year"
    @State private var analyticsEnabled = true
    
    private let totalSteps = 5
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                ProgressView(value: Double(currentStep + 1), total: Double(totalSteps))
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding()
                
                // Step content
                TabView(selection: $currentStep) {
                    SleepScheduleStep(
                        bedtime: $bedtime,
                        wakeTime: $wakeTime,
                        timeZone: $timeZone,
                        bedtimeVaries: $bedtimeVaries
                    )
                    .tag(0)
                    
                    MedicationProfileStep(
                        medicationName: $medicationName,
                        dose1Mg: $dose1Mg,
                        dose2Mg: $dose2Mg,
                        dosesPerBottle: $dosesPerBottle,
                        bottleMg: $bottleMg
                    )
                    .tag(1)
                    
                    DoseWindowRulesStep(
                        targetInterval: $targetInterval,
                        snoozeStep: $snoozeStep,
                        maxSnoozes: $maxSnoozes,
                        undoWindow: $undoWindow
                    )
                    .tag(2)
                    
                    NotificationsPermissionsStep(
                        allowNotifications: $allowNotifications,
                        criticalAlertsEnabled: $criticalAlertsEnabled,
                        autoSnoozeEnabled: $autoSnoozeEnabled,
                        focusOverrideEnabled: $focusOverrideEnabled
                    )
                    .tag(3)
                    
                    PrivacySyncStep(
                        dataStorage: $dataStorage,
                        iCloudSyncEnabled: $iCloudSyncEnabled,
                        dataRetention: $dataRetention,
                        analyticsEnabled: $analyticsEnabled
                    )
                    .tag(4)
                }
                .tabViewStyle(.automatic)
                
                // Navigation buttons
                HStack {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                    
                    if currentStep < totalSteps - 1 {
                        Button("Continue") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Complete Setup") {
                            completeSetup()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            }
            .navigationTitle("DoseTap Studio Setup")
        }
        .frame(width: 600, height: 500)
    }
    
    private func completeSetup() {
        // Save configuration to data store
        print("🎉 Setup completed with:")
        print("- Bedtime: \(bedtime)")
        print("- Wake time: \(wakeTime)")
        print("- Medication: \(medicationName)")
        print("- Dose 1: \(dose1Mg)mg, Dose 2: \(dose2Mg)mg")
        print("- Target interval: \(targetInterval) minutes")
        
        isCompleted = true
    }
}

/// Step 1: Sleep Schedule Configuration
struct SleepScheduleStep: View {
    @Binding var bedtime: Date
    @Binding var wakeTime: Date
    @Binding var timeZone: TimeZone
    @Binding var bedtimeVaries: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to DoseTap Studio")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Let's set up your nightly schedule")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Bedtime")
                        .frame(width: 120, alignment: .leading)
                    
                    DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                
                HStack {
                    Text("Wake time")
                        .frame(width: 120, alignment: .leading)
                    
                    DatePicker("", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                
                HStack {
                    Text("Time zone")
                        .frame(width: 120, alignment: .leading)
                    
                    Text(timeZone.identifier)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                    
                    Button("Change") {
                        // Show time zone picker
                    }
                    .buttonStyle(.bordered)
                }
                
                HStack {
                    Text("Bedtime varies")
                        .frame(width: 120, alignment: .leading)
                    
                    Toggle("", isOn: $bedtimeVaries)
                        .labelsHidden()
                    
                    Text("(±30 minutes)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Step 2: Medication Profile
struct MedicationProfileStep: View {
    @Binding var medicationName: String
    @Binding var dose1Mg: String
    @Binding var dose2Mg: String
    @Binding var dosesPerBottle: String
    @Binding var bottleMg: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Medication Profile")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Configure your medication details")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Name")
                        .frame(width: 140, alignment: .leading)
                    
                    Menu {
                        Button("XYWAV") { medicationName = "XYWAV" }
                        Button("Xyrem") { medicationName = "Xyrem" }
                        Button("Custom...") { /* Show custom input */ }
                    } label: {
                        HStack {
                            Text(medicationName)
                            Image(systemName: "chevron.down")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
                
                HStack {
                    Text("Dose 1 (mg)")
                        .frame(width: 140, alignment: .leading)
                    
                    TextField("450", text: $dose1Mg)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                HStack {
                    Text("Dose 2 (mg)")
                        .frame(width: 140, alignment: .leading)
                    
                    TextField("225", text: $dose2Mg)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                HStack {
                    Text("Doses per bottle")
                        .frame(width: 140, alignment: .leading)
                    
                    TextField("60", text: $dosesPerBottle)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    
                    Text("Bottle mg")
                        .padding(.leading, 20)
                    
                    TextField("9000", text: $bottleMg)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Step 3: Dose Window Rules
struct DoseWindowRulesStep: View {
    @Binding var targetInterval: Int
    @Binding var snoozeStep: Int
    @Binding var maxSnoozes: Int
    @Binding var undoWindow: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dose Window Rules")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Configure timing and notification preferences")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Target interval")
                        .frame(width: 140, alignment: .leading)
                    
                    Text("\(targetInterval) minutes")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                }
                
                HStack {
                    Text("Allowed window")
                        .frame(width: 140, alignment: .leading)
                    
                    Text("150–240 minutes")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                }
                
                HStack {
                    Text("Snooze step")
                        .frame(width: 140, alignment: .leading)
                    
                    Menu {
                        Button("5m") { snoozeStep = 5 }
                        Button("10m") { snoozeStep = 10 }
                        Button("15m") { snoozeStep = 15 }
                    } label: {
                        HStack {
                            Text("\(snoozeStep)m")
                            Image(systemName: "chevron.down")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    
                    Text("Max snoozes")
                        .padding(.leading, 20)
                    
                    Menu {
                        Button("1") { maxSnoozes = 1 }
                        Button("2") { maxSnoozes = 2 }
                        Button("3") { maxSnoozes = 3 }
                        Button("5") { maxSnoozes = 5 }
                    } label: {
                        HStack {
                            Text("\(maxSnoozes)")
                            Image(systemName: "chevron.down")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
                
                HStack {
                    Text("Undo window")
                        .frame(width: 140, alignment: .leading)
                    
                    Menu {
                        Button("3s") { undoWindow = 3 }
                        Button("5s") { undoWindow = 5 }
                        Button("10s") { undoWindow = 10 }
                    } label: {
                        HStack {
                            Text("\(undoWindow)s")
                            Image(systemName: "chevron.down")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Snooze disabled with less than 15 minutes remaining.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Step 4: Notifications & Permissions
struct NotificationsPermissionsStep: View {
    @Binding var allowNotifications: Bool
    @Binding var criticalAlertsEnabled: Bool
    @Binding var autoSnoozeEnabled: Bool
    @Binding var focusOverrideEnabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notifications & Alerts")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Configure notification preferences for dose reminders")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 20) {
                toggleRow(
                    title: "Allow Notifications",
                    description: "Enable dose reminders and alerts",
                    isOn: $allowNotifications
                )
                
                toggleRow(
                    title: "Critical Alerts",
                    description: "Medical necessity alerts that bypass Do Not Disturb",
                    isOn: $criticalAlertsEnabled
                )
                
                toggleRow(
                    title: "Auto-snooze",
                    description: "Automatically snooze after missed reminders",
                    isOn: $autoSnoozeEnabled
                )
                
                toggleRow(
                    title: "Focus override",
                    description: "Bypass Focus modes for dose reminders",
                    isOn: $focusOverrideEnabled
                )
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Sample notification:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                sampleNotificationView
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func toggleRow(title: String, description: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: isOn)
                    .toggleStyle(SwitchToggleStyle())
            }
        }
        .padding(.vertical, 4)
    }
    
    private var sampleNotificationView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("DoseTap")
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack {
                Text("Take Dose 2 — 42m left")
                    .font(.body)
                Spacer()
            }
            
            HStack(spacing: 8) {
                Button("Take Now") {}
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                
                Button("Snooze") {}
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(.controlColor))
                    .cornerRadius(6)
                
                Button("Skip") {}
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(.controlColor))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }
}

/// Step 5: Privacy & Sync  
struct PrivacySyncStep: View {
    @Binding var dataStorage: String
    @Binding var iCloudSyncEnabled: Bool
    @Binding var dataRetention: String
    @Binding var analyticsEnabled: Bool
    
    private let dataRetentionOptions = ["6 months", "1 year", "2 years"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy & Data Sync")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Choose how your data is stored and managed")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 20) {
                dataStorageSection
                syncSettingsSection
                analyticsSection
                privacyNotesSection
            }
            
            HStack {
                Button("Privacy Policy") {
                    // Open privacy policy
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.controlColor))
                .cornerRadius(6)
                
                Spacer()
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var dataStorageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Data Storage")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(dataStorage)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    .foregroundColor(.blue)
            }
            
            Text("Your data stays on your device by default")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var syncSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Sync")
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text("Enable later in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $iCloudSyncEnabled)
                    .toggleStyle(SwitchToggleStyle())
                    .disabled(true) // Disabled for initial setup
            }
            
            HStack {
                Text("Data Retention")
                    .font(.body)
                    .fontWeight(.medium)
                
                Spacer()
                
                Menu {
                    ForEach(dataRetentionOptions, id: \.self) { option in
                        Button(option) {
                            dataRetention = option
                        }
                    }
                } label: {
                    HStack {
                        Text(dataRetention)
                        Image(systemName: "chevron.down")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
    }
    
    private var analyticsSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Analytics")
                    .font(.body)
                    .fontWeight(.medium)
                
                Text("Local processing only")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $analyticsEnabled)
                .toggleStyle(SwitchToggleStyle())
        }
    }
    
    private var privacyNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your data stays on your device by default.")
                .font(.body)
                .fontWeight(.medium)
            
            Text("Health data is never synced or shared.")
                .font(.body)
                .fontWeight(.medium)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    SetupWizardView(dataStore: DataStore())
}
