import SwiftUI

// MARK: - Color Hex Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r, g, b: Double
        switch hexSanitized.count {
        case 6:
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
        case 8:
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
        default:
            return nil
        }
        
        self.init(red: r, green: g, blue: b)
    }
    
    /// Convert Color to hex string
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        
        let r, g, b: CGFloat
        if components.count >= 3 {
            r = components[0]
            g = components[1]
            b = components[2]
        } else {
            // Grayscale
            r = components[0]
            g = components[0]
            b = components[0]
        }
        
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - User Settings Manager
// Shared singleton for persisting user preferences across the app
class UserSettingsManager: ObservableObject {
    static let shared = UserSettingsManager()
    
    // MARK: - Appearance
    @AppStorage("appearance_mode") var appearanceMode: AppearanceMode = .system
    @AppStorage("high_contrast_mode") var highContrastMode: Bool = false
    @AppStorage("reduced_motion") var reducedMotion: Bool = false
    
    // MARK: - Dose Timing (XYWAV Specific)
    // Per SSOT: Window 150-240 min, valid targets: 165, 180, 195, 210, 225
    @AppStorage("target_interval_minutes") var targetIntervalMinutes: Int = 165
    @AppStorage("snooze_duration_minutes") var snoozeDurationMinutes: Int = 10
    @AppStorage("max_snoozes") var maxSnoozes: Int = 3
    
    // MARK: - Undo Settings
    // How long the undo snackbar appears after dose actions (seconds)
    @AppStorage("undo_window_seconds") var undoWindowSeconds: Double = 5.0
    
    // Valid undo window options (seconds)
    let validUndoWindowOptions: [Double] = [3.0, 5.0, 7.0, 10.0]
    
    // MARK: - Medication Settings
    // Which medications the user takes (stored as JSON array of medication IDs)
    @AppStorage("user_medications_json") private var userMedicationsJSON: String = ""
    @AppStorage("default_adderall_dose") var defaultAdderallDose: Int = 10
    @AppStorage("default_adderall_formulation") var defaultAdderallFormulation: String = "ir"
    
    // MARK: - Event Log Cooldowns (in seconds)
    // Shorter = can log same event more frequently
    @AppStorage("cooldown_bathroom") var cooldownBathroom: Int = 30
    @AppStorage("cooldown_water") var cooldownWater: Int = 30
    @AppStorage("cooldown_brief_wake") var cooldownBriefWake: Int = 60
    @AppStorage("cooldown_anxiety") var cooldownAnxiety: Int = 60
    @AppStorage("cooldown_dream") var cooldownDream: Int = 30
    @AppStorage("cooldown_noise") var cooldownNoise: Int = 30
    @AppStorage("cooldown_lights_out") var cooldownLightsOut: Int = 1800  // 30 min
    @AppStorage("cooldown_wake_up") var cooldownWakeUp: Int = 1800       // 30 min
    @AppStorage("cooldown_snack") var cooldownSnack: Int = 300           // 5 min
    @AppStorage("cooldown_heart_racing") var cooldownHeartRacing: Int = 60
    @AppStorage("cooldown_temperature") var cooldownTemperature: Int = 60
    @AppStorage("cooldown_pain") var cooldownPain: Int = 60
    
    // MARK: - Notifications
    @AppStorage("notifications_enabled") var notificationsEnabled: Bool = true
    @AppStorage("critical_alerts_enabled") var criticalAlertsEnabled: Bool = true
    @AppStorage("window_open_alert") var windowOpenAlert: Bool = true
    @AppStorage("fifteen_min_warning") var fifteenMinWarning: Bool = true
    @AppStorage("five_min_warning") var fiveMinWarning: Bool = true
    @AppStorage("haptics_enabled") var hapticsEnabled: Bool = true
    @AppStorage("sound_enabled") var soundEnabled: Bool = true
    
    // MARK: - Integrations
    @AppStorage("healthkit_enabled") var healthKitEnabled: Bool = false
    @AppStorage("whoop_enabled") var whoopEnabled: Bool = false
    
    // MARK: - Privacy
    @AppStorage("analytics_enabled") var analyticsEnabled: Bool = false
    @AppStorage("crash_reports_enabled") var crashReportsEnabled: Bool = true
    
    // MARK: - QuickLog Panel Customization
    // Stores the list of event types to show in the QuickLog grid (up to 16)
    @AppStorage("quicklog_buttons_json") private var quickLogButtonsJSON: String = ""
    
    // Default QuickLog buttons (8 most common)
    private let defaultQuickLogButtons: [QuickLogButtonConfig] = [
        QuickLogButtonConfig(id: "bathroom", name: "Bathroom", icon: "toilet.fill", colorHex: "#007AFF"),
        QuickLogButtonConfig(id: "water", name: "Water", icon: "drop.fill", colorHex: "#00CED1"),
        QuickLogButtonConfig(id: "lightsOut", name: "Lights Out", icon: "light.max", colorHex: "#5856D6"),
        QuickLogButtonConfig(id: "wakeTemp", name: "Brief Wake", icon: "moon.zzz.fill", colorHex: "#5856D6"),
        QuickLogButtonConfig(id: "anxiety", name: "Anxiety", icon: "brain.head.profile", colorHex: "#AF52DE"),
        QuickLogButtonConfig(id: "noise", name: "Noise", icon: "speaker.wave.3.fill", colorHex: "#FF9500"),
        QuickLogButtonConfig(id: "pain", name: "Pain", icon: "bandage.fill", colorHex: "#FF3B30"),
        QuickLogButtonConfig(id: "dream", name: "Dream", icon: "cloud.moon.fill", colorHex: "#FF2D55")
    ]
    
    // All available event types
    static let allAvailableEvents: [QuickLogButtonConfig] = [
        // Physical
        QuickLogButtonConfig(id: "bathroom", name: "Bathroom", icon: "toilet.fill", colorHex: "#007AFF"),
        QuickLogButtonConfig(id: "water", name: "Water", icon: "drop.fill", colorHex: "#00CED1"),
        QuickLogButtonConfig(id: "snack", name: "Snack", icon: "fork.knife", colorHex: "#34C759"),
        // Sleep Cycle
        QuickLogButtonConfig(id: "lightsOut", name: "Lights Out", icon: "light.max", colorHex: "#5856D6"),
        QuickLogButtonConfig(id: "wakeTemp", name: "Brief Wake", icon: "moon.zzz.fill", colorHex: "#5856D6"),
        QuickLogButtonConfig(id: "inBed", name: "In Bed", icon: "bed.double.fill", colorHex: "#5856D6"),
        // Mental
        QuickLogButtonConfig(id: "anxiety", name: "Anxiety", icon: "brain.head.profile", colorHex: "#AF52DE"),
        QuickLogButtonConfig(id: "dream", name: "Dream", icon: "cloud.moon.fill", colorHex: "#FF2D55"),
        QuickLogButtonConfig(id: "heartRacing", name: "Heart Racing", icon: "heart.fill", colorHex: "#FF3B30"),
        // Environment
        QuickLogButtonConfig(id: "noise", name: "Noise", icon: "speaker.wave.3.fill", colorHex: "#FF9500"),
        QuickLogButtonConfig(id: "temperature", name: "Temperature", icon: "thermometer.medium", colorHex: "#30B0C7"),
        QuickLogButtonConfig(id: "pain", name: "Pain", icon: "bandage.fill", colorHex: "#FF3B30")
    ]
    
    var quickLogButtons: [QuickLogButtonConfig] {
        get {
            if quickLogButtonsJSON.isEmpty {
                return defaultQuickLogButtons
            }
            guard let data = quickLogButtonsJSON.data(using: .utf8),
                  let buttons = try? JSONDecoder().decode([QuickLogButtonConfig].self, from: data) else {
                return defaultQuickLogButtons
            }
            return buttons
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                quickLogButtonsJSON = json
                objectWillChange.send()
            }
        }
    }
    
    func addQuickLogButton(_ button: QuickLogButtonConfig) {
        guard quickLogButtons.count < 16 else { return }
        guard !quickLogButtons.contains(where: { $0.id == button.id }) else { return }
        var buttons = quickLogButtons
        buttons.append(button)
        quickLogButtons = buttons
    }
    
    func removeQuickLogButton(id: String) {
        var buttons = quickLogButtons
        buttons.removeAll { $0.id == id }
        quickLogButtons = buttons
    }
    
    func moveQuickLogButton(from source: IndexSet, to destination: Int) {
        var buttons = quickLogButtons
        buttons.move(fromOffsets: source, toOffset: destination)
        quickLogButtons = buttons
    }
    
    func resetQuickLogButtons() {
        quickLogButtons = defaultQuickLogButtons
    }

    // Computed: Valid target options per SSOT
    let validTargetOptions: [Int] = [165, 180, 195, 210, 225]
    
    // Computed: Valid cooldown options (in seconds)
    let cooldownOptions: [Int] = [10, 30, 60, 120, 300, 600, 1800, 3600]
    
    // Helper: Format seconds to human readable
    func formatCooldown(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)m"
        } else {
            return "\(seconds / 3600)h"
        }
    }
    
    // Get cooldown for event name
    func cooldown(for eventName: String) -> TimeInterval {
        switch eventName {
        case "Bathroom": return TimeInterval(cooldownBathroom)
        case "Water": return TimeInterval(cooldownWater)
        case "Brief Wake": return TimeInterval(cooldownBriefWake)
        case "Anxiety": return TimeInterval(cooldownAnxiety)
        case "Dream": return TimeInterval(cooldownDream)
        case "Noise": return TimeInterval(cooldownNoise)
        case "Lights Out": return TimeInterval(cooldownLightsOut)
        case "Wake Up": return TimeInterval(cooldownWakeUp)
        case "Snack": return TimeInterval(cooldownSnack)
        case "Heart Racing": return TimeInterval(cooldownHeartRacing)
        case "Temperature": return TimeInterval(cooldownTemperature)
        case "Pain": return TimeInterval(cooldownPain)
        default: return 30
        }
    }
    
    // Computed: Color scheme
    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
    
    // MARK: - Medication Management
    
    // Available doses for Adderall (mg)
    let adderallDoseOptions: [Int] = [5, 10, 15, 20, 25, 30]
    
    // Get user's configured medications
    var userMedications: [String] {
        get {
            if userMedicationsJSON.isEmpty {
                return ["adderall_ir"] // Default to Adderall IR
            }
            guard let data = userMedicationsJSON.data(using: .utf8),
                  let meds = try? JSONDecoder().decode([String].self, from: data) else {
                return ["adderall_ir"]
            }
            return meds
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                userMedicationsJSON = json
                objectWillChange.send()
            }
        }
    }
    
    func toggleMedication(_ medicationId: String) {
        var meds = userMedications
        if meds.contains(medicationId) {
            meds.removeAll { $0 == medicationId }
        } else {
            meds.append(medicationId)
        }
        userMedications = meds
    }
    
    func hasMedication(_ medicationId: String) -> Bool {
        userMedications.contains(medicationId)
    }
}

// MARK: - Appearance Mode
enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - QuickLog Button Configuration
struct QuickLogButtonConfig: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let colorHex: String
    
    var color: Color {
        Color(hex: colorHex) ?? .gray
    }
}
