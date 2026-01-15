import SwiftUI
import UserNotifications

struct SetupWizardView: View {
    @StateObject private var setupService = SetupWizardService()
    @Binding var isSetupComplete: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                setupProgressBar
                
                // Content area
                ZStack {
                    Color(UIColor.systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            stepContent
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
                
                // Navigation buttons
                navigationButtons
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            setupService.validateCurrentStep()
        }
        .onChange(of: setupService.userConfig.setupCompleted) { completed in
            if completed {
                isSetupComplete = true
            }
        }
    }
    
    private var setupProgressBar: some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(1...5, id: \.self) { step in
                    Circle()
                        .fill(step <= setupService.currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)
                    
                    if step < 5 {
                        Rectangle()
                            .fill(step < setupService.currentStep ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Text("Step \(setupService.currentStep) of 5")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 16)
        .background(Color(UIColor.systemBackground))
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch setupService.currentStep {
        case 1:
            SleepScheduleStepView(config: $setupService.userConfig.sleepSchedule)
        case 2:
            MedicationStepView(config: $setupService.userConfig.medicationProfile)
        case 3:
            DoseWindowStepView(config: $setupService.userConfig.doseWindow)
        case 4:
            NotificationStepView(
                config: $setupService.userConfig.notifications,
                requestPermissions: setupService.requestNotificationPermissions
            )
        case 5:
            PrivacyStepView(config: $setupService.userConfig.privacy)
        default:
            EmptyView()
        }
    }
    
    private var navigationButtons: some View {
        VStack(spacing: 12) {
            // Validation errors
            if !setupService.validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(setupService.validationErrors, id: \.self) { error in
                        Label(error, systemImage: error.hasPrefix("Warning:") ? "exclamationmark.triangle" : "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(error.hasPrefix("Warning:") ? .orange : .red)
                    }
                }
                .padding(.horizontal, 20)
            }
            
            // Navigation buttons
            HStack(spacing: 16) {
                if setupService.canGoBack {
                    Button("Back") {
                        setupService.previousStep()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(setupService.isLoading)
                }
                
                Spacer()
                
                Button(setupService.currentStep == 5 ? "Complete Setup" : "Continue") {
                    setupService.nextStep()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!setupService.canProceed)
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Step Views

struct SleepScheduleStepView: View {
    @Binding var config: SleepScheduleConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeaderView(
                title: "Sleep Schedule",
                subtitle: "Help us understand your typical sleep pattern for optimal dose timing"
            )
            
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Usual Bedtime")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        DatePicker("", selection: $config.usualBedtime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(CompactDatePickerStyle())
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        Text("Usual Wake Time")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        DatePicker("", selection: $config.usualWakeTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(CompactDatePickerStyle())
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("My bedtime varies significantly", isOn: $config.varyBedtime)
                        .font(.subheadline)
                    
                    if config.varyBedtime {
                        Text("We'll provide flexible timing recommendations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            
            InfoBoxView(
                message: "Your sleep schedule helps determine safe dosing windows. XYWAV should only be taken when you can remain in bed for at least 4 hours.",
                type: .info
            )
        }
    }
}

struct MedicationStepView: View {
    @Binding var config: WizardMedicationConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeaderView(
                title: "Medication Profile",
                subtitle: "Configure your XYWAV prescription details for accurate tracking"
            )
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Medication Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("XYWAV", text: $config.medicationName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dose 1 (mg)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("450", value: $config.doseMgDose1, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dose 2 (mg)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("225", value: $config.doseMgDose2, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bottle Information")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Doses per bottle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("60", value: $config.dosesPerBottle, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total mg per bottle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("9000", value: $config.bottleMgTotal, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.numberPad)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
            
            InfoBoxView(
                message: "This information helps track your medication supply and ensures accurate dosing records for your healthcare provider.",
                type: .info
            )
        }
    }
}

struct DoseWindowStepView: View {
    @Binding var config: DoseWindowConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeaderView(
                title: "Dose Timing",
                subtitle: "Customize your dose window preferences within safe medical limits"
            )
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Dose 2 Target Interval")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(config.minMinutes) min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("\(config.defaultTargetMinutes) min")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Text("\(config.maxMinutes) min")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(config.defaultTargetMinutes) },
                                set: { config.defaultTargetMinutes = Int($0) }
                            ),
                            in: Double(config.minMinutes)...Double(config.maxMinutes),
                            step: 5
                        )
                        .accentColor(.blue)
                        
                        Text("Time between Dose 1 and Dose 2")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Snooze Step")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("", selection: $config.snoozeStepMinutes) {
                            Text("5 min").tag(5)
                            Text("10 min").tag(10)
                            Text("15 min").tag(15)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Max Snoozes")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("", selection: $config.maxSnoozes) {
                            Text("1").tag(1)
                            Text("2").tag(2)
                            Text("3").tag(3)
                            Text("5").tag(5)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            
            InfoBoxView(
                message: "The 150-240 minute window is medically required for XYWAV safety. Your target time can be adjusted within this range.",
                type: .warning
            )
        }
    }
}

struct NotificationStepView: View {
    @Binding var config: NotificationConfig
    let requestPermissions: () async -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeaderView(
                title: "Notifications",
                subtitle: "Configure alerts and reminders for safe medication timing"
            )
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Notifications")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Required for dose reminders")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if config.notificationsAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Grant Permission") {
                                Task {
                                    await requestPermissions()
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                if config.notificationsAuthorized {
                    VStack(spacing: 12) {
                        Toggle("Auto-snooze when appropriate", isOn: $config.autoSnoozeEnabled)
                            .font(.subheadline)
                        
                        Toggle("Override Focus/Do Not Disturb", isOn: $config.focusModeOverride)
                            .font(.subheadline)
                        
                        HStack {
                            Text("Notification Sound")
                                .font(.subheadline)
                            
                            Spacer()
                            
                            Picker("Sound", selection: $config.notificationSound) {
                                Text("Default").tag("default")
                                Text("Gentle").tag("gentle")
                                Text("Urgent").tag("urgent")
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }
            
            if config.focusModeOverride {
                InfoBoxView(
                    message: "Critical alerts require special permission and are intended for medical safety. This feature requires App Store approval.",
                    type: .warning
                )
            }
        }
    }
}

struct PrivacyStepView: View {
    @Binding var config: PrivacyConfig
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeaderView(
                title: "Privacy & Data",
                subtitle: "Control how your health data is stored and shared"
            )
            
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Toggle("Enable iCloud Sync", isOn: $config.icloudSyncEnabled)
                        .font(.subheadline)
                    
                    if config.icloudSyncEnabled {
                        Text("Your dose data will sync across your devices using iCloud")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Data Retention")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("Retention Period", selection: $config.dataRetentionDays) {
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                        Text("2 years").tag(730)
                        Text("Forever").tag(Int.max)
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    Text("How long to keep your dose history")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                VStack(spacing: 12) {
                    Toggle("Anonymous Usage Analytics", isOn: $config.analyticsEnabled)
                        .font(.subheadline)
                    
                    Text("Help improve the app with anonymous usage data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            
            InfoBoxView(
                message: "All health data stays on your device unless you enable iCloud sync. We never share personal medical information with third parties.",
                type: .info
            )
        }
    }
}

// MARK: - Supporting Views

struct StepHeaderView: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

struct InfoBoxView: View {
    let message: String
    let type: InfoType
    
    enum InfoType {
        case info, warning, error
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "exclamationmark.circle"
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)
                .font(.system(size: 16))
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .background(type.color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(configuration.isPressed ? Color.blue.opacity(0.8) : Color.blue)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.blue)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

struct SetupWizardView_Previews: PreviewProvider {
    static var previews: some View {
        SetupWizardView(isSetupComplete: .constant(false))
    }
}
