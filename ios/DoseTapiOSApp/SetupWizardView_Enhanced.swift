import SwiftUI
import UserNotifications

struct SetupWizardView: View {
    @Binding var isSetupComplete: Bool
    @StateObject private var configManager = UserConfigurationManager.shared
    @State private var currentStep: SetupStep = .sleepSchedule
    @State private var canContinue: Bool = false
    
    // Step 1: Sleep Schedule
    @State private var bedtime = Calendar.current.date(from: DateComponents(hour: 1))!
    @State private var wakeTime = Calendar.current.date(from: DateComponents(hour: 6, minute: 30))!
    @State private var timeZone = TimeZone.current
    @State private var bedtimeVaries = true
    
    // Step 2: Medication Profile
    @State private var medicationName = "XYWAV"
    @State private var dose1Amount = "450"
    @State private var dose2Amount = "225"
    @State private var dosesPerBottle = "60"
    @State private var bottleMg = "9000"
    
    // Step 3: Dose Window Rules
    @State private var targetInterval = 165
    @State private var snoozeStep = 10
    @State private var maxSnoozes = 3
    @State private var undoWindow = 5  // Per SSOT: 5s default, range 3-10s
    @State private var enableNotifications = true
    
    // Step 4: Notifications
    @State private var allowNotifications = true
    @State private var criticalAlerts = true
    @State private var autoSnooze = true
    @State private var focusOverride = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    
    // Step 5: Privacy
    @State private var dataStorage: DataStorageOption = .localOnly
    @State private var iCloudSync = false
    @State private var dataRetention: RetentionPeriod = .oneYear
    @State private var analytics = true
    @State private var showingPrivacyPolicy = false
    
    enum SetupStep: Int, CaseIterable {
        case sleepSchedule = 1
        case medicationProfile = 2
        case doseRules = 3
        case notifications = 4
        case privacy = 5
        
        var title: String {
            switch self {
            case .sleepSchedule: return "Sleep Schedule"
            case .medicationProfile: return "Medication Profile"
            case .doseRules: return "Dose Window Rules"
            case .notifications: return "Notifications & Alerts"
            case .privacy: return "Privacy & Data Sync"
            }
        }
    }
    
    enum DataStorageOption: String, CaseIterable {
        case localOnly = "Local Device Only"
        case iCloudSync = "iCloud Sync Enabled"
    }
    
    enum RetentionPeriod: String, CaseIterable {
        case sixMonths = "6 months"
        case oneYear = "1 year"
        case twoYears = "2 years"
        case forever = "Forever"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                ProgressView(value: Double(currentStep.rawValue), total: 5.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding()
                
                // Step indicator
                Text("Step \(currentStep.rawValue) of 5")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Step \(currentStep.rawValue) of 5")
                
                // Main content
                ScrollView {
                    VStack(spacing: 24) {
                        stepContent
                    }
                    .padding()
                }
                
                // Navigation buttons
                HStack {
                    if currentStep.rawValue > 1 {
                        Button("Back") {
                            withAnimation {
                                currentStep = SetupStep(rawValue: currentStep.rawValue - 1)!
                                updateCanContinue()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                    
                    Button(currentStep == .privacy ? "Complete Setup" : "Continue") {
                        if currentStep == .privacy {
                            completeSetup()
                        } else {
                            withAnimation {
                                currentStep = SetupStep(rawValue: currentStep.rawValue + 1)!
                                updateCanContinue()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
                }
                .padding()
            }
            .navigationTitle(currentStep.title)
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                updateCanContinue()
                checkNotificationStatus()
            }
        }
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .sleepSchedule:
            SleepScheduleStep(
                bedtime: $bedtime,
                wakeTime: $wakeTime,
                timeZone: $timeZone,
                bedtimeVaries: $bedtimeVaries
            )
        case .medicationProfile:
            MedicationProfileStep(
                medicationName: $medicationName,
                dose1Amount: $dose1Amount,
                dose2Amount: $dose2Amount,
                dosesPerBottle: $dosesPerBottle,
                bottleMg: $bottleMg
            )
        case .doseRules:
            DoseRulesStep(
                targetInterval: $targetInterval,
                snoozeStep: $snoozeStep,
                maxSnoozes: $maxSnoozes,
                undoWindow: $undoWindow,
                enableNotifications: $enableNotifications
            )
        case .notifications:
            NotificationsStep(
                allowNotifications: $allowNotifications,
                criticalAlerts: $criticalAlerts,
                autoSnooze: $autoSnooze,
                focusOverride: $focusOverride,
                notificationStatus: $notificationStatus
            )
        case .privacy:
            PrivacyStep(
                dataStorage: $dataStorage,
                iCloudSync: $iCloudSync,
                dataRetention: $dataRetention,
                analytics: $analytics,
                showingPrivacyPolicy: $showingPrivacyPolicy
            )
        }
    }
    
    private func updateCanContinue() {
        switch currentStep {
        case .sleepSchedule:
            canContinue = true // Basic validation passed
        case .medicationProfile:
            canContinue = !medicationName.isEmpty && !dose1Amount.isEmpty && !dose2Amount.isEmpty
        case .doseRules:
            canContinue = targetInterval >= 150 && targetInterval <= 240
        case .notifications:
            canContinue = true // Optional permissions
        case .privacy:
            canContinue = true // All privacy options are valid
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationStatus = settings.authorizationStatus
            }
        }
    }
    
    private func completeSetup() {
        // Save all configuration
        configManager.setBedtimeSchedule(bedtime: bedtime, wakeTime: wakeTime, varies: bedtimeVaries)
        configManager.setMedicationProfile(
            name: medicationName,
            dose1: Int(dose1Amount) ?? 450,
            dose2: Int(dose2Amount) ?? 225
        )
        configManager.setDoseRules(
            targetInterval: targetInterval,
            snoozeStep: snoozeStep,
            maxSnoozes: maxSnoozes
        )
        configManager.setNotificationPreferences(
            enabled: allowNotifications,
            criticalAlerts: criticalAlerts
        )
        configManager.setPrivacySettings(
            localOnly: dataStorage == .localOnly,
            analytics: analytics,
            retention: dataRetention.rawValue
        )
        
        // Mark setup as complete
        configManager.markSetupComplete()
        isSetupComplete = true
    }
}

// MARK: - Step Views

struct SleepScheduleStep: View {
    @Binding var bedtime: Date
    @Binding var wakeTime: Date
    @Binding var timeZone: TimeZone
    @Binding var bedtimeVaries: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Let's set up your nightly schedule")
                .font(.title2)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Bedtime")
                        .frame(width: 80, alignment: .leading)
                    DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel("Bedtime")
                }
                
                HStack {
                    Text("Wake time")
                        .frame(width: 80, alignment: .leading)
                    DatePicker("", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel("Wake time")
                }
                
                HStack {
                    Text("Time zone")
                        .frame(width: 80, alignment: .leading)
                    Text(timeZone.identifier)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Change") {
                        // Time zone picker would go here
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                
                Toggle("Bedtime varies", isOn: $bedtimeVaries)
                    .accessibilityLabel("Bedtime varies plus or minus 30 minutes")
                
                if bedtimeVaries {
                    Text("±30 minutes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct MedicationProfileStep: View {
    @Binding var medicationName: String
    @Binding var dose1Amount: String
    @Binding var dose2Amount: String
    @Binding var dosesPerBottle: String
    @Binding var bottleMg: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Medication Profile")
                .font(.title2)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Name")
                        .frame(width: 100, alignment: .leading)
                    Menu {
                        Button("XYWAV") { medicationName = "XYWAV" }
                        Button("Add custom") { /* Custom entry */ }
                    } label: {
                        HStack {
                            Text(medicationName)
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                }
                
                HStack {
                    Text("Dose 1 (mg)")
                        .frame(width: 100, alignment: .leading)
                    TextField("450", text: $dose1Amount)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }
                
                HStack {
                    Text("Dose 2 (mg)")
                        .frame(width: 100, alignment: .leading)
                    TextField("225", text: $dose2Amount)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Doses per bottle")
                        TextField("60", text: $dosesPerBottle)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Bottle mg")
                        TextField("9000", text: $bottleMg)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct DoseRulesStep: View {
    @Binding var targetInterval: Int
    @Binding var snoozeStep: Int
    @Binding var maxSnoozes: Int
    @Binding var undoWindow: Int
    @Binding var enableNotifications: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Dose Window Rules")
                .font(.title2)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Target interval")
                        .frame(width: 120, alignment: .leading)
                    Text("\(targetInterval) minutes")
                        .foregroundColor(.secondary)
                }
                
                Text("Allowed window: 150–240 minutes")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Snooze step")
                        Menu {
                            Button("5m") { snoozeStep = 5 }
                            Button("10m") { snoozeStep = 10 }
                            Button("15m") { snoozeStep = 15 }
                        } label: {
                            HStack {
                                Text("\(snoozeStep)m")
                                Image(systemName: "chevron.down")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Max snoozes")
                        Menu {
                            ForEach(1...5, id: \.self) { count in
                                Button("\(count)") { maxSnoozes = count }
                            }
                        } label: {
                            HStack {
                                Text("\(maxSnoozes)")
                                Image(systemName: "chevron.down")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                        }
                    }
                }
                
                HStack {
                    Text("Undo window")
                        .frame(width: 120, alignment: .leading)
                    Menu {
                        Button("3s") { undoWindow = 3 }
                        Button("5s") { undoWindow = 5 }
                        Button("10s") { undoWindow = 10 }
                    } label: {
                        HStack {
                            Text("\(undoWindow)s")
                            Image(systemName: "chevron.down")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Button(enableNotifications ? "✓ Enable Notifications" : "Enable Notifications") {
                        enableNotifications.toggle()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(enableNotifications ? .green : .blue)
                    
                    if !enableNotifications {
                        Button("Not now") {
                            // Continue without notifications
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Text("Snooze disabled with less than 15 minutes remaining.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Note: Snooze disabled with less than 15 minutes remaining.")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct NotificationsStep: View {
    @Binding var allowNotifications: Bool
    @Binding var criticalAlerts: Bool
    @Binding var autoSnooze: Bool
    @Binding var focusOverride: Bool
    @Binding var notificationStatus: UNAuthorizationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Notifications & Alerts")
                .font(.title2)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 16) {
                Button(allowNotifications ? "✓ Allow Notifications" : "Enable Notifications") {
                    requestNotificationPermission()
                }
                .buttonStyle(.borderedProminent)
                .tint(allowNotifications ? .green : .blue)
                
                if notificationStatus == .denied {
                    Text("Please enable notifications in Settings")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Button(criticalAlerts ? "✓ Critical Alerts Enabled" : "Request Critical Alerts") {
                    requestCriticalAlerts()
                }
                .buttonStyle(.bordered)
                .disabled(!allowNotifications)
                
                Text("(Medical necessity)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("Auto-snooze", isOn: $autoSnooze)
                    .disabled(!allowNotifications)
                
                Toggle("Focus override", isOn: $focusOverride)
                    .disabled(!allowNotifications)
                
                Divider()
                
                Text("Sample notification:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                // Mock notification preview
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("DoseTap")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    
                    Text("Take Dose 2 — 42m left")
                        .font(.subheadline)
                    
                    HStack(spacing: 12) {
                        Button("Take Now") { }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                        
                        Button("Snooze") { }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        
                        Button("Skip") { }
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                allowNotifications = granted
                if granted {
                    notificationStatus = .authorized
                }
            }
        }
    }
    
    private func requestCriticalAlerts() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { granted, _ in
            DispatchQueue.main.async {
                criticalAlerts = granted
            }
        }
    }
}

struct PrivacyStep: View {
    @Binding var dataStorage: SetupWizardView.DataStorageOption
    @Binding var iCloudSync: Bool
    @Binding var dataRetention: SetupWizardView.RetentionPeriod
    @Binding var analytics: Bool
    @Binding var showingPrivacyPolicy: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Privacy & Data Sync")
                .font(.title2)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Data Storage")
                        .frame(width: 120, alignment: .leading)
                    Text(dataStorage.rawValue)
                        .foregroundColor(.secondary)
                }
                
                Toggle("iCloud Sync", isOn: $iCloudSync)
                    .onChange(of: iCloudSync) { enabled in
                        dataStorage = enabled ? .iCloudSync : .localOnly
                    }
                
                Text("(Enable later in Settings)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Data Retention")
                        .frame(width: 120, alignment: .leading)
                    Menu {
                        ForEach(SetupWizardView.RetentionPeriod.allCases, id: \.self) { period in
                            Button(period.rawValue) { dataRetention = period }
                        }
                    } label: {
                        HStack {
                            Text(dataRetention.rawValue)
                            Image(systemName: "chevron.down")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                }
                
                Toggle("Analytics", isOn: $analytics)
                
                Text("(Local processing only)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your data stays on your device by default.")
                        .font(.subheadline)
                    
                    Text("Health data is never synced or shared.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Button("Privacy Policy") {
                    showingPrivacyPolicy = true
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("DoseTap Privacy Policy")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Your privacy is fundamental to how DoseTap works.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Privacy policy content would go here
                    Text("All dose timing data is stored locally on your device by default. No personal health information is transmitted to external servers unless you explicitly enable iCloud sync.")
                        .padding(.vertical)
                    
                    // More privacy policy sections...
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
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

#Preview {
    SetupWizardView(isSetupComplete: .constant(false))
}
