import Foundation
import SwiftUI
import DoseCore
import UIKit
import os.log

private let urlRouterLog = Logger(subsystem: "com.dosetap.app", category: "URLRouter")

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

enum URLDeepLinkRoute: Equatable {
    case takeDose1
    case takeDose2
    case snooze
    case skip
    case log
    case oauth
    case navigate(tab: AppTab)

    init?(host rawHost: String) {
        let host = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let tab = AppTab.tab(forDeepLinkHost: host) {
            self = .navigate(tab: tab)
            return
        }

        switch host {
        case "dose1":
            self = .takeDose1
        case "dose2":
            self = .takeDose2
        case "snooze":
            self = .snooze
        case "skip":
            self = .skip
        case "log":
            self = .log
        case "oauth":
            self = .oauth
        default:
            return nil
        }
    }

    var isStateChanging: Bool {
        switch self {
        case .takeDose1, .takeDose2, .snooze, .skip, .log:
            return true
        case .oauth, .navigate:
            return false
        }
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

    typealias ApplicationStateProvider = @MainActor () -> UIApplication.State
    typealias ProtectedDataProvider = @MainActor () -> Bool
    
    // MARK: - Published State
    @Published var selectedTab: AppTab = .tonight
    @Published var lastAction: URLAction?
    @Published var showActionFeedback: Bool = false
    @Published var feedbackMessage: String = ""
    
    // MARK: - Dependencies (set by app)
    weak var core: DoseTapCore?
    weak var eventLogger: EventLogger?
    weak var coordinator: DoseActionCoordinator?
    var applicationStateProvider: ApplicationStateProvider = { UIApplication.shared.applicationState }
    var protectedDataProvider: ProtectedDataProvider = { UIApplication.shared.isProtectedDataAvailable }
    private var pendingActionTasks: [UUID: Task<Void, Never>] = [:]

    func configure(core: DoseTapCore, eventLogger: EventLogger, coordinator: DoseActionCoordinator) {
        self.core = core
        self.eventLogger = eventLogger
        self.coordinator = coordinator
    }

    func resetTestOverrides() {
        applicationStateProvider = { UIApplication.shared.applicationState }
        protectedDataProvider = { UIApplication.shared.isProtectedDataAvailable }
    }

    func waitForPendingActions() async {
        let tasks = Array(pendingActionTasks.values)
        for task in tasks {
            await task.value
        }
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
            urlRouterLog.warning("Invalid deep link: \(validation.errors.joined(separator: ", "), privacy: .public)")
            #endif
            showFeedback("Invalid link")
            return false
        }
        
        guard url.scheme == "dosetap" else { return false }
        
        let host = url.host ?? ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        
        #if DEBUG
        urlRouterLog.debug("Handling deep link: \(InputValidator.sanitizeForLogging(url.absoluteString), privacy: .private)")
        #endif
        
        guard let route = URLDeepLinkRoute(host: host) else {
            urlRouterLog.warning("Unknown deep-link host: \(host, privacy: .public)")
            return false
        }

        // P0-5 FIX: State-changing deep links require foreground + unlocked
        if route.isStateChanging {
            guard applicationStateProvider() == .active else {
                urlRouterLog.warning("Blocked state-changing deep link '\(host, privacy: .public)' - app not in foreground")
                return false
            }
            guard protectedDataProvider() else {
                urlRouterLog.warning("Blocked state-changing deep link '\(host, privacy: .public)' - device locked")
                return false
            }
        }

        switch route {
        case .takeDose1:
            return handleDose1()
            
        case .takeDose2:
            return handleDose2()
            
        case .snooze:
            return handleSnooze()
            
        case .skip:
            return handleSkip()
            
        case .log:
            let eventName = queryItems.first(where: { $0.name == "event" })?.value ?? "unknown"
            let notes = queryItems.first(where: { $0.name == "notes" })?.value
            return handleLogEvent(name: eventName, notes: notes)
            
        case .oauth:
            // OAuth callback is handled separately by WHOOP integration
            return false

        case .navigate(let tab):
            return handleNavigate(tab: tab)
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleDose1() -> Bool {
        lastAction = .takeDose1
        guard let coordinator = resolveCoordinator() else { return false }
        
        enqueueAction { [self] in
            let result = await coordinator.takeDose1(surface: .deepLink)
            self.showFeedback(for: result)
        }
        return true
    }
    
    private func handleDose2() -> Bool {
        lastAction = .takeDose2
        guard let coordinator = resolveCoordinator() else { return false }

        enqueueAction { [self] in
            let result = await coordinator.takeDose2(surface: .deepLink)
            self.showFeedback(for: result)
        }
        return true
    }
    
    private func handleSnooze() -> Bool {
        lastAction = .snooze
        guard let coordinator = resolveCoordinator() else { return false }
        
        enqueueAction { [self] in
            let result = await coordinator.snooze(surface: .deepLink)
            self.showFeedback(for: result)
        }
        return true
    }
    
    private func handleSkip() -> Bool {
        lastAction = .skip
        guard let coordinator = resolveCoordinator() else { return false }
        
        // Set immediate feedback to avoid race with async task
        showFeedback("Skipping Dose 2…")
        
        enqueueAction { [self] in
            let result = await coordinator.skipDose(surface: .deepLink)
            self.showFeedback(for: result)
        }
        return true
    }
    
    private func handleLogEvent(name: String, notes: String?) -> Bool {
        // Security: Validate event type
        let eventValidation = InputValidator.validateEventType(name)
        guard eventValidation.isValid else {
            #if DEBUG
            urlRouterLog.warning("Invalid event type: \(eventValidation.errors.joined(separator: ", "), privacy: .public)")
            #endif
            showFeedback("Invalid event")
            return false
        }
        
        let normalizedName = InputValidator.sanitizeInput(name.isEmpty ? "unknown" : name.lowercased())
        let sanitizedNotes = notes.flatMap { InputValidator.sanitizeInputOptional($0) }

        guard CanonicalDoseEventType(canonicalizing: normalizedName) == nil else {
            urlRouterLog.warning("Blocked dose event through log deep link: \(normalizedName, privacy: .public)")
            showFeedback("Use dose action link")
            return false
        }

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

    private func resolveCoordinator() -> DoseActionCoordinator? {
        guard let coordinator else {
            showFeedback("App not ready")
            return nil
        }
        return coordinator
    }

    private func showFeedback(for result: DoseActionCoordinator.ActionResult) {
        switch result {
        case .success(let message):
            showFeedback(message)
        case .attentionRequired(let message):
            showFeedback(message)
        case .retryRequired(let message):
            showFeedback(message)
        case .blocked(let reason):
            showFeedback(reason)
        case .needsConfirm(let type):
            switch type {
            case .workWake:
                showFeedback("Work/wake warning - review in the app")
            case .earlyDose:
                showFeedback("Window not open yet")
            case .outsideWindowOccurrence:
                showFeedback("Open the app to record the actual Dose 2 time")
            case .afterSkip:
                showFeedback("After skip - open app to confirm")
            case .extraDose:
                showFeedback("Extra dose - open app to confirm")
            }
        }
    }

    private func enqueueAction(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.pendingActionTasks.removeValue(forKey: id) }
            await operation()
        }
        pendingActionTasks[id] = task
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
