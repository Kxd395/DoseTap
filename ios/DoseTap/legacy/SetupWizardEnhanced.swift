// iOS/SetupWizardEnhanced.swift
import SwiftUI
import UserNotifications

// iOS/SetupWizardEnhanced.swift
#if os(iOS)
import SwiftUI
import HealthKit
import CoreLocation

// MARK: - Setup Wizard Enhanced Models

struct SetupWizardEnhanced: View {
    @Binding var isSetupComplete: Bool
    @StateObject private var setupManager = SetupWizardManager()
    @State private var currentStep: SetupStep = .welcome
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Progress indicator
                    SetupProgressView(currentStep: currentStep, totalSteps: 6)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    // Step content
                    TabView(selection: $currentStep) {
                        WelcomeStepView()
                            .tag(SetupStep.welcome)
                        
                        SleepScheduleStepView(setupManager: setupManager)
                            .tag(SetupStep.sleepSchedule)
                        
                        MedicationProfileStepView(setupManager: setupManager)
                            .tag(SetupStep.medicationProfile)
                        
                        DoseWindowRulesStepView(setupManager: setupManager)
                            .tag(SetupStep.doseRules)
                        
                        NotificationsStepView(setupManager: setupManager)
                            .tag(SetupStep.notifications)
                        
                        PrivacyStepView(setupManager: setupManager)
                            .tag(SetupStep.privacy)
                        
                        CompletionStepView(onComplete: {
                            completeSetup()
                        })
                        .tag(SetupStep.completion)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .onChange(of: currentStep) { _ in
                        setupManager.validateCurrentStep(currentStep)
                    }
                    
                    // Navigation controls
                    SetupNavigationView(
                        currentStep: $currentStep,
                        canContinue: setupManager.canContinue,
                        onNext: { nextStep() },
                        onBack: { previousStep() },
                        onSkip: { skipStep() }
                    )
                    .padding()
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            setupManager.validateCurrentStep(currentStep)
        }
    }
    
    private func nextStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if let nextStep = SetupStep(rawValue: currentStep.rawValue + 1) {
                currentStep = nextStep
            }
        }
    }
    
    private func previousStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if let prevStep = SetupStep(rawValue: currentStep.rawValue - 1) {
                currentStep = prevStep
            }
        }
    }
    
    private func skipStep() {
        // Handle optional step skipping
        nextStep()
    }
    
    private func completeSetup() {
        setupManager.saveConfiguration()
        isSetupComplete = true
    }
}

// MARK: - Setup Steps Enum

enum SetupStep: Int, CaseIterable {
    case welcome = 0
    case sleepSchedule = 1
    case medicationProfile = 2
    case doseRules = 3
    case notifications = 4
    case privacy = 5
    case completion = 6
    
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .sleepSchedule: return "Sleep Schedule"
        case .medicationProfile: return "Medication Profile"
        case .doseRules: return "Dose Window Rules"
        case .notifications: return "Notifications"
        case .privacy: return "Privacy"
        case .completion: return "All Set!"
        }
    }
    
    var description: String {
        switch self {
        case .welcome: return "Get started with DoseTap"
        case .sleepSchedule: return "Set your nightly schedule"
        case .medicationProfile: return "Configure your medication"
        case .doseRules: return "Define dose timing rules"
        case .notifications: return "Enable dose reminders"
        case .privacy: return "Choose your data preferences"
        case .completion: return "Setup complete"
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // App icon
            Image(systemName: "pills.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 16) {
                Text("Welcome to DoseTap")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Your trusted companion for XYWAV medication management")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 12) {
                FeatureRow(icon: "clock", title: "Smart Timing", description: "Optimal dose window management")
                FeatureRow(icon: "bell.badge", title: "Gentle Reminders", description: "Non-intrusive notifications")
                FeatureRow(icon: "lock.shield", title: "Privacy First", description: "Your data stays private")
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Welcome to DoseTap. Your trusted companion for medication management.")
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Sleep Schedule Step

struct SleepScheduleStepView: View {
    @ObservedObject var setupManager: SetupWizardManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SetupStepHeader(
                    title: "Sleep Schedule",
                    description: "Set your typical bedtime and wake time"
                )
                
                VStack(spacing: 20) {
                    // Bedtime
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bedtime")
                            .font(.headline)
                        
                        DatePicker("Bedtime", selection: $setupManager.bedtime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(WheelDatePickerStyle())
                            .labelsHidden()
                    }
                    
                    // Wake time
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Wake time")
                            .font(.headline)
                        
                        DatePicker("Wake time", selection: $setupManager.wakeTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(WheelDatePickerStyle())
                            .labelsHidden()
                    }
                    
                    // Time zone
                    HStack {
                        Text("Time zone")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button("Change") {
                            // Handle time zone change
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                    
                    Text(setupManager.timeZone.identifier)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Bedtime varies toggle
                    Toggle("Bedtime varies (±30 minutes)", isOn: $setupManager.bedtimeVaries)
                        .font(.headline)
                }
                .padding(.horizontal)
                
                Spacer(minLength: 100)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sleep schedule configuration. Set bedtime, wake time, and time zone.")
    }
}

// MARK: - Medication Profile Step

struct MedicationProfileStepView: View {
    @ObservedObject var setupManager: SetupWizardManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SetupStepHeader(
                    title: "Medication Profile",
                    description: "Configure your medication details"
                )
                
                VStack(spacing: 20) {
                    // Medication name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Medication")
                            .font(.headline)
                        
                        HStack {
                            TextField("Medication name", text: $setupManager.medicationName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            Button("XYWAV") {
                                setupManager.medicationName = "XYWAV"
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }
                    }
                    
                    // Dose amounts
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dose 1 (mg)")
                                .font(.headline)
                            TextField("450", text: $setupManager.dose1Amount)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dose 2 (mg)")
                                .font(.headline)
                            TextField("225", text: $setupManager.dose2Amount)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                    }
                    
                    // Bottle information
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Doses per bottle")
                                .font(.headline)
                            TextField("60", text: $setupManager.dosesPerBottle)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bottle mg")
                                .font(.headline)
                            TextField("9000", text: $setupManager.bottleMg)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer(minLength: 100)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Medication profile. Configure medication name and dosage amounts.")
    }
}

// MARK: - Dose Window Rules Step

struct DoseWindowRulesStepView: View {
    @ObservedObject var setupManager: SetupWizardManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SetupStepHeader(
                    title: "Dose Window Rules",
                    description: "Define timing and snooze settings"
                )
                
                VStack(spacing: 20) {
                    // Target interval
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target interval")
                            .font(.headline)
                        
                        Text("\(setupManager.targetInterval) minutes")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                        
                        Slider(value: Binding(
                            get: { Double(setupManager.targetInterval) },
                            set: { setupManager.targetInterval = Int($0) }
                        ), in: 150...240, step: 5)
                    }
                    
                    // Window range
                    Text("Allowed window: 150–240 minutes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Snooze settings
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Snooze step")
                                .font(.headline)
                            Picker("Snooze step", selection: $setupManager.snoozeStep) {
                                Text("5m").tag(5)
                                Text("10m").tag(10)
                                Text("15m").tag(15)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Max snoozes")
                                .font(.headline)
                            Picker("Max snoozes", selection: $setupManager.maxSnoozes) {
                                Text("1").tag(1)
                                Text("2").tag(2)
                                Text("3").tag(3)
                                Text("5").tag(5)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }
                    
                    // Undo window
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Undo window")
                            .font(.headline)
                        Picker("Undo window", selection: $setupManager.undoWindow) {
                            Text("10s").tag(10)
                            Text("15s").tag(15)
                            Text("30s").tag(30)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    // Note about snooze limitation
                    Text("Snooze will be disabled when less than 15 minutes remain in the dose window.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                
                Spacer(minLength: 100)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dose window rules. Configure target interval and snooze settings.")
    }
}

// MARK: - Notifications Step

struct NotificationsStepView: View {
    @ObservedObject var setupManager: SetupWizardManager
    @State private var showingPermissionAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SetupStepHeader(
                    title: "Notifications & Alerts",
                    description: "Enable dose reminders and alerts"
                )
                
                VStack(spacing: 20) {
                    // Notification settings
                    VStack(spacing: 16) {
                        Toggle("Allow Notifications", isOn: $setupManager.allowNotifications)
                            .font(.headline)
                        
                        Toggle("Critical Alerts", isOn: $setupManager.criticalAlerts)
                            .font(.headline)
                            .disabled(!setupManager.allowNotifications)
                        
                        Toggle("Auto-snooze", isOn: $setupManager.autoSnooze)
                            .font(.headline)
                            .disabled(!setupManager.allowNotifications)
                        
                        Toggle("Focus override", isOn: $setupManager.focusOverride)
                            .font(.headline)
                            .disabled(!setupManager.allowNotifications)
                    }
                    
                    if setupManager.allowNotifications {
                        // Sample notification preview
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sample notification:")
                                .font(.headline)
                            
                            NotificationPreview()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    if setupManager.allowNotifications {
                        Button("Enable Notifications") {
                            requestNotificationPermission()
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                Spacer(minLength: 100)
            }
        }
        .alert("Notification Permission", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To receive dose reminders, please enable notifications in Settings.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notifications and alerts configuration. Enable notifications for dose reminders.")
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    setupManager.notificationPermissionGranted = true
                } else {
                    showingPermissionAlert = true
                }
            }
        }
    }
}

struct NotificationPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("DoseTap")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Text("now")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("Take Dose 2 — 42m left")
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack(spacing: 8) {
                NotificationButton(title: "Take Now", style: .primary)
                NotificationButton(title: "Snooze", style: .secondary)
                NotificationButton(title: "Skip", style: .secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct NotificationButton: View {
    let title: String
    let style: ButtonStyle
    
    enum ButtonStyle {
        case primary, secondary
    }
    
    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(style == .primary ? .white : .blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(style == .primary ? Color.blue : Color.blue.opacity(0.1))
            )
    }
}

// MARK: - Privacy Step

struct PrivacyStepView: View {
    @ObservedObject var setupManager: SetupWizardManager
    @State private var showingPrivacyPolicy = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SetupStepHeader(
                    title: "Privacy & Data Sync",
                    description: "Choose your data preferences"
                )
                
                VStack(spacing: 20) {
                    // Data storage
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Data Storage")
                            .font(.headline)
                        
                        Picker("Data Storage", selection: $setupManager.dataStorage) {
                            Text("Local Device Only").tag(DataStorageOption.localOnly)
                            Text("iCloud Sync").tag(DataStorageOption.iCloudSync)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    // Settings toggles
                    VStack(spacing: 16) {
                        Toggle("iCloud Sync", isOn: $setupManager.iCloudSync)
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Data Retention")
                                .font(.headline)
                            Picker("Data Retention", selection: $setupManager.dataRetention) {
                                Text("6 months").tag(RetentionPeriod.sixMonths)
                                Text("1 year").tag(RetentionPeriod.oneYear)
                                Text("2 years").tag(RetentionPeriod.twoYears)
                                Text("Forever").tag(RetentionPeriod.forever)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        Toggle("Analytics", isOn: $setupManager.analytics)
                            .font(.headline)
                    }
                    
                    // Privacy information
                    VStack(spacing: 12) {
                        Text("Your data stays on your device by default.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("Health data is never synced or shared.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    
                    Button("Privacy Policy") {
                        showingPrivacyPolicy = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal)
                
                Spacer(minLength: 100)
            }
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Privacy and data sync settings. Configure data storage and retention preferences.")
    }
}

// MARK: - Completion Step

struct CompletionStepView: View {
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            VStack(spacing: 16) {
                Text("All Set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("DoseTap is configured and ready to help you manage your medication schedule.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Start Using DoseTap") {
                onComplete()
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(10)
            .padding(.horizontal)
            
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup complete. Start using DoseTap.")
    }
}

// MARK: - Supporting Views

struct SetupStepHeader: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(description)
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
}

struct SetupProgressView: View {
    let currentStep: SetupStep
    let totalSteps: Int
    
    var progress: Double {
        Double(currentStep.rawValue + 1) / Double(totalSteps)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Step \(currentStep.rawValue + 1) of \(totalSteps)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
    }
}

struct SetupNavigationView: View {
    @Binding var currentStep: SetupStep
    let canContinue: Bool
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        HStack {
            if currentStep.rawValue > 0 {
                Button("Back") {
                    onBack()
                }
                .font(.headline)
                .foregroundColor(.blue)
            }
            
            Spacer()
            
            if currentStep == .completion {
                // Handled in completion view
            } else if currentStep.rawValue < SetupStep.allCases.count - 2 {
                Button("Continue") {
                    onNext()
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canContinue ? Color.blue : Color.gray)
                )
                .disabled(!canContinue)
            }
        }
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text("Privacy Policy content would go here...")
                    .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Data Models

enum DataStorageOption {
    case localOnly, iCloudSync
}

enum RetentionPeriod {
    case sixMonths, oneYear, twoYears, forever
}

// MARK: - Setup Wizard Manager

class SetupWizardManager: ObservableObject {
    // Sleep Schedule
    @Published var bedtime = Calendar.current.date(from: DateComponents(hour: 1)) ?? Date()
    @Published var wakeTime = Calendar.current.date(from: DateComponents(hour: 6, minute: 30)) ?? Date()
    @Published var timeZone = TimeZone.current
    @Published var bedtimeVaries = true
    
    // Medication Profile
    @Published var medicationName = "XYWAV"
    @Published var dose1Amount = "450"
    @Published var dose2Amount = "225"
    @Published var dosesPerBottle = "60"
    @Published var bottleMg = "9000"
    
    // Dose Rules
    @Published var targetInterval = 165
    @Published var snoozeStep = 10
    @Published var maxSnoozes = 3
    @Published var undoWindow = 15
    
    // Notifications
    @Published var allowNotifications = true
    @Published var criticalAlerts = true
    @Published var autoSnooze = true
    @Published var focusOverride = false
    @Published var notificationPermissionGranted = false
    
    // Privacy
    @Published var dataStorage: DataStorageOption = .localOnly
    @Published var iCloudSync = false
    @Published var dataRetention: RetentionPeriod = .oneYear
    @Published var analytics = true
    
    // Validation
    @Published var canContinue = true
    
    func validateCurrentStep(_ step: SetupStep) {
        switch step {
        case .welcome:
            canContinue = true
        case .sleepSchedule:
            canContinue = true // Always valid with default values
        case .medicationProfile:
            canContinue = !medicationName.isEmpty && 
                         !dose1Amount.isEmpty && 
                         !dose2Amount.isEmpty
        case .doseRules:
            canContinue = targetInterval >= 150 && targetInterval <= 240
        case .notifications:
            canContinue = true
        case .privacy:
            canContinue = true
        case .completion:
            canContinue = true
        }
    }
    
    func saveConfiguration() {
        // Save configuration to UserDefaults or Core Data
        UserDefaults.standard.set(true, forKey: "setupComplete")
        
        // Save individual settings
        let bedtimeComponents = Calendar.current.dateComponents([.hour, .minute], from: bedtime)
        let wakeTimeComponents = Calendar.current.dateComponents([.hour, .minute], from: wakeTime)
        
        UserDefaults.standard.set(bedtimeComponents.hour, forKey: "bedtimeHour")
        UserDefaults.standard.set(bedtimeComponents.minute, forKey: "bedtimeMinute")
        UserDefaults.standard.set(wakeTimeComponents.hour, forKey: "wakeTimeHour")
        UserDefaults.standard.set(wakeTimeComponents.minute, forKey: "wakeTimeMinute")
        
        UserDefaults.standard.set(medicationName, forKey: "medicationName")
        UserDefaults.standard.set(dose1Amount, forKey: "dose1Amount")
        UserDefaults.standard.set(dose2Amount, forKey: "dose2Amount")
        
        UserDefaults.standard.set(targetInterval, forKey: "targetInterval")
        UserDefaults.standard.set(snoozeStep, forKey: "snoozeStep")
        UserDefaults.standard.set(maxSnoozes, forKey: "maxSnoozes")
        
        UserDefaults.standard.set(allowNotifications, forKey: "allowNotifications")
        UserDefaults.standard.set(analytics, forKey: "analytics")
    }
}

#endif // os(iOS)
