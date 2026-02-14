import Foundation
import SwiftUI
import DoseCore

enum AppTab: Int, CaseIterable {
    case tonight = 0
    case timeline = 1
    case history = 2
    case dashboard = 3
    case settings = 4

    var icon: String {
        switch self {
        case .tonight: return "moon.fill"
        case .timeline: return "chart.bar.xaxis"
        case .history: return "calendar"
        case .dashboard: return "chart.xyaxis.line"
        case .settings: return "gear"
        }
    }

    var label: String {
        switch self {
        case .tonight: return "Tonight"
        case .timeline: return "Timeline"
        case .history: return "History"
        case .dashboard: return "Dashboard"
        case .settings: return "Settings"
        }
    }

    static let navigationDeepLinks: [(host: String, tab: AppTab)] = [
        ("tonight", .tonight),
        ("timeline", .timeline),
        ("details", .timeline),
        ("history", .history),
        ("dashboard", .dashboard),
        ("settings", .settings),
    ]

    private static let navigationLookup: [String: AppTab] = Dictionary(
        uniqueKeysWithValues: navigationDeepLinks.map { ($0.host, $0.tab) }
    )

    static func tab(forDeepLinkHost host: String) -> AppTab? {
        navigationLookup[host.lowercased()]
    }
}

/// URL Router for handling deep links
/// Supported URLs:
/// - dosetap://dose1 - Take Dose 1
/// - dosetap://dose2 - Take Dose 2
/// - dosetap://snooze - Snooze alarm (+configured minutes)
/// - dosetap://skip - Skip Dose 2
/// - dosetap://log?event=bathroom - Log a quick event
/// - dosetap://log?event=bathroom&notes=urgent - Log event with notes
/// - dosetap://tonight - Navigate to Tonight tab
/// - dosetap://dashboard - Navigate to Dashboard tab
/// - dosetap://history - Navigate to History tab
/// - dosetap://settings - Navigate to Settings tab
@MainActor
public class URLRouter: ObservableObject {
    
    static let shared = URLRouter()
    
    // MARK: - Published State
    @Published var selectedTab: AppTab = .tonight
    @Published var lastAction: URLAction?
    @Published var showActionFeedback: Bool = false
    @Published var feedbackMessage: String = ""
    
    // MARK: - Dependencies (set by app)
    weak var core: DoseTapCore?
    weak var eventLogger: EventLogger?

    func configure(core: DoseTapCore, eventLogger: EventLogger) {
        self.core = core
        self.eventLogger = eventLogger
    }
    
    // MARK: - URL Actions
    enum URLAction: Equatable {
        case takeDose1
        case takeDose2
        case snooze
        case skip
        case logEvent(name: String, notes: String?)
        case navigate(tab: AppTab)
    }
    
    // MARK: - Handle URL
    
    /// Handle incoming URL and return true if handled
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        // Security: Validate deep link before processing
        let validation = InputValidator.validateDeepLink(url)
        guard validation.isValid else {
            #if DEBUG
            print("⚠️ URLRouter: Invalid deep link - \(validation.errors.joined(separator: ", "))")
            #endif
            showFeedback("Invalid link")
            return false
        }
        
        guard url.scheme == "dosetap" else { return false }
        
        let host = url.host ?? ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        
        #if DEBUG
        print("🔗 URLRouter: Handling \(InputValidator.sanitizeForLogging(url.absoluteString))")
        #endif
        
        if let tab = AppTab.tab(forDeepLinkHost: host) {
            return handleNavigate(tab: tab)
        }

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
        guard let core = resolveCore() else { return false }
        
        guard core.dose1Time == nil else {
            showFeedback("Dose 1 already taken")
            return false
        }
        
        Task {
            let now = Date()
            await core.takeDose()
            eventLogger?.logEvent(name: "Dose 1", color: .green, cooldownSeconds: 3600 * 8, persist: false)
            
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
        guard let core = resolveCore() else { return false }
        
        guard core.dose1Time != nil else {
            showFeedback("Take Dose 1 first")
            return false
        }
        
        guard core.dose2Time == nil else {
            showFeedback("Dose 2 already taken")
            return false
        }
        
        let status = core.currentStatus
        if status == .beforeWindow {
            showFeedback("Window not open yet")
            return false
        }
        if status == .noDose1 || status == .completed || status == .finalizing {
            showFeedback("Dose 2 unavailable right now")
            return false
        }

        Task {
            if status == .closed {
                await core.takeDose(lateOverride: true)
                eventLogger?.logEvent(name: "Dose 2 (Late)", color: .orange, cooldownSeconds: 3600 * 8, persist: false)
                showFeedback("✓ Dose 2 logged late (override)")
            } else {
                await core.takeDose()
                eventLogger?.logEvent(name: "Dose 2", color: .green, cooldownSeconds: 3600 * 8, persist: false)
                showFeedback("✓ Dose 2 logged")
            }
            AlarmService.shared.cancelAllAlarms()
            AlarmService.shared.clearWakeAlarmState()
        }
        return true
    }
    
    private func handleSnooze() -> Bool {
        lastAction = .snooze
        guard let core = resolveCore() else { return false }
        let settings = UserSettingsManager.shared
        let maxSnoozes = max(0, settings.maxSnoozes)
        let snoozeMinutes = max(1, settings.snoozeDurationMinutes)
        
        guard maxSnoozes > 0 else {
            showFeedback("Snooze is disabled in settings")
            return false
        }
        
        guard core.snoozeCount < maxSnoozes else {
            showFeedback("Max snoozes reached (\(maxSnoozes)/\(maxSnoozes))")
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
                showFeedback("Snooze +\(snoozeMinutes)m unavailable right now")
            }
        }
        return true
    }
    
    private func handleSkip() -> Bool {
        lastAction = .skip
        guard let core = resolveCore() else { return false }
        
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
            AlarmService.shared.clearWakeAlarmState()
            showFeedback("✓ Dose 2 skipped")
        }
        return true
    }
    
    private func handleLogEvent(name: String, notes: String?) -> Bool {
        // Security: Validate event type
        let eventValidation = InputValidator.validateEventType(name)
        guard eventValidation.isValid else {
            #if DEBUG
            print("⚠️ URLRouter: Invalid event type - \(eventValidation.errors.joined(separator: ", "))")
            #endif
            showFeedback("Invalid event")
            return false
        }
        
        let normalizedName = InputValidator.sanitizeInput(name.isEmpty ? "unknown" : name.lowercased())
        let sanitizedNotes = notes.flatMap { InputValidator.sanitizeInputOptional($0) }
        lastAction = .logEvent(name: normalizedName, notes: sanitizedNotes)
        
        guard let eventLogger = eventLogger else {
            showFeedback("App not ready")
            return false
        }
        
        // Canonicalize event type for storage + diagnostics while preserving display label.
        let mapped = mapEventName(normalizedName)
        
        // Check cooldown
        let cooldown = UserSettingsManager.shared.cooldown(for: mapped.canonicalType)
        if let cooldownEnd = eventLogger.cooldownEnd(for: mapped.canonicalType), Date() < cooldownEnd {
            let remaining = Int(cooldownEnd.timeIntervalSince(Date()))
            showFeedback("On cooldown (\(remaining)s)")
            return false
        }

        // Wake events must flow through SessionRepository to transition to finalizing state.
        if mapped.canonicalType == "wake_final" {
            let timestamp = Date()
            SessionRepository.shared.setWakeFinalTime(timestamp)
            eventLogger.logEvent(
                name: mapped.displayName,
                color: mapped.color,
                cooldownSeconds: cooldown,
                persist: false,
                eventTypeOverride: mapped.canonicalType
            )
            showFeedback("✓ \(mapped.displayName) logged")
            return true
        }
        
        eventLogger.logEvent(
            name: mapped.displayName,
            color: mapped.color,
            cooldownSeconds: cooldown,
            persist: true,
            notes: sanitizedNotes,
            eventTypeOverride: mapped.canonicalType
        )
        showFeedback("✓ \(mapped.displayName) logged")
        
        return true
    }
    
    private func handleNavigate(tab: AppTab) -> Bool {
        selectedTab = tab
        lastAction = .navigate(tab: tab)
        return true
    }
    
    // MARK: - Helpers
    
    private func mapEventName(_ name: String) -> (canonicalType: String, displayName: String, color: Color) {
        let eventType = EventType(name)
        return (eventType.canonicalString, eventType.displayName, eventType.displayColor)
    }

    private func resolveCore() -> DoseTapCore? {
        guard let core else {
            showFeedback("App not ready")
            return nil
        }
        return core
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
