import Foundation
import SwiftUI
import DoseCore

/// URL Router for handling deep links
/// Supported URLs:
/// - dosetap://dose1 - Take Dose 1
/// - dosetap://dose2 - Take Dose 2
/// - dosetap://snooze - Snooze alarm (+10 min)
/// - dosetap://skip - Skip Dose 2
/// - dosetap://log?event=bathroom - Log a quick event
/// - dosetap://log?event=bathroom&notes=urgent - Log event with notes
/// - dosetap://tonight - Navigate to Tonight tab
/// - dosetap://history - Navigate to History tab
/// - dosetap://settings - Navigate to Settings tab
@MainActor
public class URLRouter: ObservableObject {
    
    static let shared = URLRouter()
    
    // MARK: - Published State
    @Published var selectedTab: Int = 0
    @Published var lastAction: URLAction?
    @Published var showActionFeedback: Bool = false
    @Published var feedbackMessage: String = ""
    
    // MARK: - Dependencies (set by app)
    weak var core: DoseTapCore?
    weak var eventLogger: EventLogger?
    
    // MARK: - URL Actions
    enum URLAction: Equatable {
        case takeDose1
        case takeDose2
        case snooze
        case skip
        case logEvent(name: String, notes: String?)
        case navigate(tab: Int)
    }
    
    // MARK: - Handle URL
    
    /// Handle incoming URL and return true if handled
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        guard url.scheme == "dosetap" else { return false }
        
        let host = url.host ?? ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        
        print("🔗 URLRouter: Handling \(url.absoluteString)")
        
        switch host {
        case "dose1":
            return handleDose1()
            
        case "dose2":
            return handleDose2()
            
        case "snooze":
            return handleSnooze()
            
        case "skip":
            return handleSkip()
            
        case "log":
            let eventName = queryItems.first(where: { $0.name == "event" })?.value ?? "unknown"
            let notes = queryItems.first(where: { $0.name == "notes" })?.value
            return handleLogEvent(name: eventName, notes: notes)
            
        case "tonight":
            return handleNavigate(tab: 0)
            
        case "details", "timeline":
            return handleNavigate(tab: 1)
            
        case "history":
            return handleNavigate(tab: 2)
            
        case "settings":
            return handleNavigate(tab: 3)
            
        case "oauth":
            // OAuth callback is handled separately by WHOOP integration
            return false
            
        default:
            print("⚠️ URLRouter: Unknown host '\(host)'")
            return false
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleDose1() -> Bool {
        lastAction = .takeDose1
        
        guard let core = core else {
            showFeedback("App not ready")
            return true
        }
        
        guard core.dose1Time == nil else {
            showFeedback("Dose 1 already taken")
            return false
        }
        
        Task {
            let now = Date()
            await core.takeDose()
            SessionRepository.shared.saveDose1(timestamp: now)
            eventLogger?.logEvent(name: "Dose 1", color: .green, cooldownSeconds: 3600 * 8)
            
            // Schedule wake alarm
            let targetMinutes = UserDefaults.standard.integer(forKey: "target_interval_minutes")
            let targetInterval = targetMinutes > 0 ? targetMinutes : 165
            let wakeTime = now.addingTimeInterval(Double(targetInterval) * 60)
            await AlarmService.shared.scheduleWakeAlarm(at: wakeTime, dose1Time: now)
            
            showFeedback("✓ Dose 1 logged")
        }
        return true
    }
    
    private func handleDose2() -> Bool {
        lastAction = .takeDose2
        
        guard let core = core else {
            showFeedback("App not ready")
            return true
        }
        
        guard core.dose1Time != nil else {
            showFeedback("Take Dose 1 first")
            return false
        }
        
        guard core.dose2Time == nil else {
            showFeedback("Dose 2 already taken")
            return false
        }
        
        // Check if window is open
        let status = core.currentStatus
        guard status == .active || status == .nearClose else {
            showFeedback("Window not open yet")
            return false
        }
        
        Task {
            let now = Date()
            await core.takeDose()
            SessionRepository.shared.saveDose2(timestamp: now)
            eventLogger?.logEvent(name: "Dose 2", color: .green, cooldownSeconds: 3600 * 8)
            AlarmService.shared.cancelAllAlarms()
            
            showFeedback("✓ Dose 2 logged")
        }
        return true
    }
    
    private func handleSnooze() -> Bool {
        lastAction = .snooze
        
        guard let core = core else {
            showFeedback("App not ready")
            return true
        }
        
        guard core.snoozeCount < 3 else {
            showFeedback("Max snoozes reached (3/3)")
            return false
        }
        
        let status = core.currentStatus
        guard status == .active || status == .nearClose else {
            showFeedback("Snooze only available in window")
            return false
        }
        
        Task {
            if let newTime = await AlarmService.shared.snoozeAlarm(dose1Time: core.dose1Time) {
                await core.snooze()
                showFeedback("✓ Snoozed to \(newTime.formatted(date: .omitted, time: .shortened))")
            } else {
                await core.snooze()
                showFeedback("✓ Snoozed +10 min")
            }
        }
        return true
    }
    
    private func handleSkip() -> Bool {
        lastAction = .skip
        
        guard let core = core else {
            showFeedback("App not ready")
            return true
        }
        
        guard core.dose1Time != nil else {
            showFeedback("Take Dose 1 first")
            return false
        }
        
        guard core.dose2Time == nil && !core.isSkipped else {
            showFeedback("Dose 2 already taken or skipped")
            return false
        }
        
        // Set immediate feedback to avoid race with async task
        showFeedback("Skipping Dose 2…")
        
        Task {
            await core.skipDose()
            AlarmService.shared.cancelAllAlarms()
            showFeedback("✓ Dose 2 skipped")
        }
        return true
    }
    
    private func handleLogEvent(name: String, notes: String?) -> Bool {
        let normalizedName = name.isEmpty ? "unknown" : name.lowercased()
        lastAction = .logEvent(name: normalizedName, notes: notes)
        
        guard let eventLogger = eventLogger else {
            showFeedback("App not ready")
            return true
        }
        
        // Map common event names to colors but preserve normalized name for action/tests
        let (displayName, color) = mapEventName(normalizedName)
        
        // Check cooldown
        let cooldown = UserSettingsManager.shared.cooldown(for: displayName)
        if let cooldownEnd = eventLogger.cooldownEnd(for: displayName), Date() < cooldownEnd {
            let remaining = Int(cooldownEnd.timeIntervalSince(Date()))
            showFeedback("On cooldown (\(remaining)s)")
            return false
        }
        
        eventLogger.logEvent(name: displayName, color: color, cooldownSeconds: cooldown)
        showFeedback("✓ \(displayName) logged")
        
        return true
    }
    
    private func handleNavigate(tab: Int) -> Bool {
        selectedTab = tab
        lastAction = .navigate(tab: tab)
        return true
    }
    
    // MARK: - Helpers
    
    private func mapEventName(_ name: String) -> (String, Color) {
        let lowercased = name.lowercased()
        switch lowercased {
        case "bathroom", "🚽":
            return ("bathroom", .blue)
        case "water", "💧":
            return ("water", .cyan)
        case "snack", "🍿":
            return ("snack", .orange)
        case "pain", "💊":
            return ("pain", .red)
        case "restless", "😰":
            return ("restless", .purple)
        case "noise", "🔊":
            return ("noise", .yellow)
        case "temp", "temperature", "🌡️":
            return ("temp", .orange)
        case "dream", "💭":
            return ("dream", .indigo)
        case "lightsout", "lights_out", "🌙":
            return ("lights_out", .indigo)
        case "wake", "wakefinal", "wake_final", "☀️":
            return ("wake", .yellow)
        case "unknown":
            return ("unknown", .gray)
        default:
            return (lowercased, .gray)
        }
    }
    
    private func showFeedback(_ message: String) {
        feedbackMessage = message
        showActionFeedback = true
        
        // Auto-hide after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.showActionFeedback = false
        }
    }
}

// MARK: - URL Feedback Banner View

struct URLFeedbackBanner: View {
    @ObservedObject var router = URLRouter.shared
    
    var body: some View {
        if router.showActionFeedback {
            Text(router.feedbackMessage)
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.green))
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.3), value: router.showActionFeedback)
        }
    }
}
