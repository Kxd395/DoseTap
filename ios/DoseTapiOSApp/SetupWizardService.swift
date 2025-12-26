import SwiftUI
import Combine

// MARK: - Setup Wizard Models

struct UserConfig: Codable {
    var schemaVersion: Int = 1
    var setupCompleted: Bool = false
    var setupCompletedAt: Date?
    
    var sleepSchedule: SleepScheduleConfig = SleepScheduleConfig()
    var medicationProfile: WizardMedicationConfig = WizardMedicationConfig()
    var doseWindow: DoseWindowConfig = DoseWindowConfig()
    var notifications: NotificationConfig = NotificationConfig()
    var privacy: PrivacyConfig = PrivacyConfig()
}

struct SleepScheduleConfig: Codable {
    var usualBedtime: Date = Calendar.current.date(from: DateComponents(hour: 1, minute: 0)) ?? Date()
    var usualWakeTime: Date = Calendar.current.date(from: DateComponents(hour: 6, minute: 30)) ?? Date()
    var timezone: String = TimeZone.current.identifier
    var varyBedtime: Bool = true
}

struct WizardMedicationConfig: Codable {
    var medicationName: String = "XYWAV"
    var doseMgDose1: Int = 450
    var doseMgDose2: Int = 225
    var dosesPerBottle: Int = 60
    var bottleMgTotal: Int = 9000
}

struct DoseWindowConfig: Codable {
    var minMinutes: Int = 150  // Core invariant - not user configurable
    var maxMinutes: Int = 240  // Core invariant - not user configurable
    var nearWindowThreshold: Int = 15  // Snooze disabled threshold
    
    var defaultTargetMinutes: Int = 165
    var snoozeStepMinutes: Int = 10
    var maxSnoozes: Int = 3
    var undoWindowSeconds: Int = 5  // Per SSOT: 5s default, range 3-10s
}

struct NotificationConfig: Codable {
    var autoSnoozeEnabled: Bool = true
    var notificationSound: String = "default"
    var focusModeOverride: Bool = false
    var notificationsAuthorized: Bool = false
    var criticalAlertsAuthorized: Bool = false
}

struct PrivacyConfig: Codable {
    var icloudSyncEnabled: Bool = false
    var dataRetentionDays: Int = 365
    var analyticsEnabled: Bool = true
}

// MARK: - Setup Wizard Service

@MainActor
class SetupWizardService: ObservableObject {
    @Published var userConfig = UserConfig()
    @Published var currentStep: Int = 1
    @Published var isLoading = false
    @Published var validationErrors: [String] = []
    
    private let maxSteps = 5
    
    var canProceed: Bool {
        validationErrors.isEmpty && !isLoading
    }
    
    var canGoBack: Bool {
        currentStep > 1
    }
    
    func validateCurrentStep() {
        validationErrors.removeAll()
        
        switch currentStep {
        case 1: validateSleepSchedule()
        case 2: validateMedicationProfile()
        case 3: validateDoseWindow()
        case 4: validateNotifications()
        case 5: validatePrivacy()
        default: break
        }
    }
    
    private func validateSleepSchedule() {
        let bedtime = userConfig.sleepSchedule.usualBedtime
        let wakeTime = userConfig.sleepSchedule.usualWakeTime
        
        // Calculate time difference accounting for overnight sleep
        let calendar = Calendar.current
        let bedHour = calendar.component(.hour, from: bedtime)
        let wakeHour = calendar.component(.hour, from: wakeTime)
        
        let sleepDuration: Int
        if wakeHour >= bedHour {
            sleepDuration = wakeHour - bedHour
        } else {
            sleepDuration = (24 - bedHour) + wakeHour
        }
        
        if sleepDuration < 4 {
            validationErrors.append("Sleep duration must be at least 4 hours")
        }
        
        if sleepDuration > 12 {
            validationErrors.append("Sleep duration seems unusually long (>12 hours)")
        }
    }
    
    private func validateMedicationProfile() {
        if userConfig.medicationProfile.medicationName.isEmpty {
            validationErrors.append("Medication name is required")
        }
        
        if userConfig.medicationProfile.doseMgDose1 <= 0 {
            validationErrors.append("Dose 1 amount must be positive")
        }
        
        if userConfig.medicationProfile.doseMgDose2 <= 0 {
            validationErrors.append("Dose 2 amount must be positive")
        }
        
        if userConfig.medicationProfile.doseMgDose2 > userConfig.medicationProfile.doseMgDose1 {
            validationErrors.append("Warning: Dose 2 is typically smaller than Dose 1")
        }
        
        if userConfig.medicationProfile.dosesPerBottle <= 0 {
            validationErrors.append("Doses per bottle must be positive")
        }
    }
    
    private func validateDoseWindow() {
        let target = userConfig.doseWindow.defaultTargetMinutes
        
        if target < userConfig.doseWindow.minMinutes || target > userConfig.doseWindow.maxMinutes {
            validationErrors.append("Target interval must be between \(userConfig.doseWindow.minMinutes)-\(userConfig.doseWindow.maxMinutes) minutes")
        }
        
        if target <= userConfig.doseWindow.minMinutes + 10 {
            validationErrors.append("Warning: Target is very close to minimum window")
        }
        
        if target >= userConfig.doseWindow.maxMinutes - 10 {
            validationErrors.append("Warning: Target is very close to maximum window")
        }
    }
    
    private func validateNotifications() {
        // Validation happens during permission requests
        // No additional validation needed for this step
    }
    
    private func validatePrivacy() {
        // No validation required for privacy settings
        // All options are valid choices
    }
    
    func nextStep() {
        guard canProceed else { return }
        
        if currentStep < maxSteps {
            currentStep += 1
            validateCurrentStep()
        } else {
            completeSetup()
        }
    }
    
    func previousStep() {
        guard canGoBack else { return }
        currentStep -= 1
        validateCurrentStep()
    }
    
    func completeSetup() {
        isLoading = true
        
        Task {
            do {
                // Save configuration
                userConfig.setupCompleted = true
                userConfig.setupCompletedAt = Date()
                
                // Persist to UserDefaults (later syncs with SQLite EventStorage)
                let data = try JSONEncoder().encode(userConfig)
                UserDefaults.standard.set(data, forKey: "DoseTapUserConfig")
                
                // Schedule initial notifications if authorized
                if userConfig.notifications.notificationsAuthorized {
                    await scheduleInitialNotifications()
                }
                
                await MainActor.run {
                    isLoading = false
                    // Setup complete - will trigger navigation to main app
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    validationErrors.append("Failed to save configuration: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func scheduleInitialNotifications() async {
        // Placeholder for notification scheduling
        // Will be implemented with full notification system
        print("Scheduling initial notifications...")
    }
    
    func requestNotificationPermissions() async {
        isLoading = true
        
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            await MainActor.run {
                userConfig.notifications.notificationsAuthorized = granted
                
                // Try to request critical alerts if basic notifications granted
                if granted && userConfig.notifications.focusModeOverride {
                    Task {
                        await requestCriticalAlerts()
                    }
                }
                
                isLoading = false
                validateCurrentStep()
            }
        } catch {
            await MainActor.run {
                validationErrors.append("Failed to request notification permissions: \(error.localizedDescription)")
                isLoading = false
            }
        }
    }
    
    private func requestCriticalAlerts() async {
        // Critical alerts require special entitlement
        // For now, just mark as attempted
        userConfig.notifications.criticalAlertsAuthorized = false
        print("Critical alerts would be requested here (requires entitlement)")
    }
}
