import Foundation
import Combine

// MARK: - User Configuration Manager

@MainActor
class UserConfigurationManager: ObservableObject {
    static let shared = UserConfigurationManager()
    
    @Published var userConfig: UserConfig?
    @Published var isConfigured: Bool = false
    
    private let configKey = "DoseTapUserConfig"
    
    private init() {
        loadConfiguration()
    }
    
    func loadConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(UserConfig.self, from: data) else {
            userConfig = nil
            isConfigured = false
            return
        }
        
        userConfig = config
        isConfigured = config.setupCompleted
    }
    
    func saveConfiguration(_ config: UserConfig) throws {
        let data = try JSONEncoder().encode(config)
        UserDefaults.standard.set(data, forKey: configKey)
        
        userConfig = config
        isConfigured = config.setupCompleted
    }
    
    func resetConfiguration() {
        UserDefaults.standard.removeObject(forKey: configKey)
        userConfig = nil
        isConfigured = false
    }
    
    // MARK: - Configuration Access Helpers
    
    var doseWindowConfig: DoseWindowConfig {
        userConfig?.doseWindow ?? DoseWindowConfig()
    }
    
    var medicationConfig: MedicationConfig {
        userConfig?.medicationProfile ?? MedicationConfig()
    }
    
    var notificationConfig: NotificationConfig {
        userConfig?.notifications ?? NotificationConfig()
    }
    
    var sleepScheduleConfig: SleepScheduleConfig {
        userConfig?.sleepSchedule ?? SleepScheduleConfig()
    }
    
    var privacyConfig: PrivacyConfig {
        userConfig?.privacy ?? PrivacyConfig()
    }
    
    // MARK: - Migration Support
    
    func migrateLegacyData() {
        // This will be used when migrating from JSON to Core Data
        // For now, just ensure we have valid configuration
        if userConfig == nil {
            userConfig = UserConfig()
        }
    }
    
    // MARK: - Validation
    
    func validateConfiguration() -> [String] {
        guard let config = userConfig else {
            return ["No configuration found"]
        }
        
        var errors: [String] = []
        
        // Validate dose window
        let target = config.doseWindow.defaultTargetMinutes
        if target < config.doseWindow.minMinutes || target > config.doseWindow.maxMinutes {
            errors.append("Invalid dose window target: \(target) minutes")
        }
        
        // Validate medication profile
        if config.medicationProfile.medicationName.isEmpty {
            errors.append("Medication name is required")
        }
        
        if config.medicationProfile.doseMgDose1 <= 0 || config.medicationProfile.doseMgDose2 <= 0 {
            errors.append("Invalid medication doses")
        }
        
        return errors
    }
}

// MARK: - Configuration Extensions

extension UserConfig {
    static func createDefault() -> UserConfig {
        return UserConfig()
    }
    
    var formattedBedtime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: sleepSchedule.usualBedtime)
    }
    
    var formattedWakeTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: sleepSchedule.usualWakeTime)
    }
    
    var totalDosePerNight: Int {
        return medicationProfile.doseMgDose1 + medicationProfile.doseMgDose2
    }
    
    var estimatedBottleDuration: Int {
        let dosesPerNight = 2 // Always 2 doses per night for XYWAV
        return medicationProfile.dosesPerBottle / dosesPerNight
    }
}

extension DoseWindowConfig {
    var targetIntervalFormatted: String {
        let hours = defaultTargetMinutes / 60
        let minutes = defaultTargetMinutes % 60
        
        if minutes == 0 {
            return "\(hours)h"
        } else {
            return "\(hours)h \(minutes)m"
        }
    }
    
    var windowRangeFormatted: String {
        let minHours = minMinutes / 60
        let minMins = minMinutes % 60
        let maxHours = maxMinutes / 60
        let maxMins = maxMinutes % 60
        
        let minString = minMins == 0 ? "\(minHours)h" : "\(minHours)h \(minMins)m"
        let maxString = maxMins == 0 ? "\(maxHours)h" : "\(maxHours)h \(maxMins)m"
        
        return "\(minString) - \(maxString)"
    }
}

extension MedicationConfig {
    var doseRatio: Double {
        guard doseMgDose1 > 0 else { return 0 }
        return Double(doseMgDose2) / Double(doseMgDose1)
    }
    
    var isTypicalRatio: Bool {
        // Typical XYWAV ratio is around 0.5 (e.g., 450mg -> 225mg)
        let ratio = doseRatio
        return ratio >= 0.4 && ratio <= 0.6
    }
}

// MARK: - SwiftUI Integration

extension View {
    func withUserConfiguration() -> some View {
        self.environmentObject(UserConfigurationManager.shared)
    }
}
