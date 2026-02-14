import SwiftUI
import Combine
import DoseCore
import UIKit
import os.log
#if canImport(Charts)
import Charts
#endif
#if canImport(CloudKit)
import CloudKit
#endif

private let appLogger = Logger(subsystem: "com.dosetap.app", category: "UI")

// MARK: - Shared Event Logger (Observable with SQLite persistence)
@MainActor
class EventLogger: ObservableObject {
    static let shared = EventLogger()
    
    @Published var events: [LoggedEvent] = []
    @Published var cooldowns: [String: Date] = [:]
    
    private let sessionRepo = SessionRepository.shared
    private var sessionChangeCancellable: AnyCancellable?
    
    private init() {
        // Load persisted events from SQLite on startup
        loadEventsFromStorage()
        
        // Refresh events when session changes (rollover/delete)
        sessionChangeCancellable = SessionRepository.shared.sessionDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.loadEventsFromStorage()
            }
    }
    
    /// Load events from SQLite for tonight's session
    private func loadEventsFromStorage() {
        let storedEvents = sessionRepo.fetchTonightSleepEvents()
        events = storedEvents.map { stored in
            LoggedEvent(
                id: UUID(uuidString: stored.id) ?? UUID(),
                name: Self.displayName(forEventType: stored.eventType),
                time: stored.timestamp,
                color: stored.colorHex.flatMap { Color(hex: $0) } ?? .gray
            )
        }
        appLogger.debug("Loaded \(self.events.count) events from SQLite")
    }
    
    func logEvent(
        name: String,
        color: Color,
        cooldownSeconds: TimeInterval,
        persist: Bool = true,
        notes: String? = nil,
        eventTypeOverride: String? = nil
    ) {
        let now = Date()
        let cooldownKey = Self.canonicalEventType(name)
        let persistedEventType = eventTypeOverride ?? cooldownKey
        
        // Check cooldown
        if let end = cooldowns[cooldownKey], now < end {
            return // Still in cooldown
        }
        
        // Create and add event
        let eventId = UUID()
        let event = LoggedEvent(id: eventId, name: name, time: now, color: color)
        events.insert(event, at: 0)
        
        // Set cooldown
        cooldowns[cooldownKey] = now.addingTimeInterval(cooldownSeconds)
        
        if persist {
            // Persist to SQLite via SessionRepository
            sessionRepo.insertSleepEvent(
                id: eventId.uuidString,
                eventType: persistedEventType,
                timestamp: now,
                colorHex: color.toHex(),
                notes: notes
            )
        }
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    func isOnCooldown(_ name: String) -> Bool {
        guard let end = cooldowns[Self.canonicalEventType(name)] else { return false }
        return Date() < end
    }
    
    func cooldownEnd(for name: String) -> Date? {
        cooldowns[Self.canonicalEventType(name)]
    }
    
    /// Clear cooldown for a specific event (for undo)
    func clearCooldown(for name: String) {
        let cooldownKey = Self.canonicalEventType(name)
        cooldowns.removeValue(forKey: cooldownKey)
        // Also remove the event from the in-memory list
        events.removeAll { Self.canonicalEventType($0.name) == cooldownKey }
    }
    
    /// Delete a specific event by ID
    func deleteEvent(id: UUID) {
        events.removeAll { $0.id == id }
        sessionRepo.deleteSleepEvent(id: id.uuidString)
    }
    
    /// Refresh events from storage
    func refresh() {
        loadEventsFromStorage()
    }
    
    /// Clear tonight's events
    func clearTonight() {
        events.removeAll()
        cooldowns.removeAll()
        sessionRepo.clearTonightsEvents()
    }

    private static func canonicalEventType(_ raw: String) -> String {
        EventType(raw).canonicalString
    }

    private static func displayName(forEventType raw: String) -> String {
        EventType(raw).displayName
    }
}

// MARK: - Main Tab View with Swipe Navigation
struct ContentView: View {
    @StateObject private var core = DoseTapCore()
    @StateObject private var settings = UserSettingsManager.shared
    @StateObject private var eventLogger = EventLogger.shared
    @StateObject private var sessionRepo = SessionRepository.shared
    @StateObject private var undoState = UndoStateManager()
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var alarmService = AlarmService.shared
    @ObservedObject private var urlRouter = URLRouter.shared
    @State private var sharedPageImage: UIImage?
    @State private var showPageShareSheet = false
    @State private var isPreparingPageShare = false
    @State private var pageShareErrorMessage: String?
    private let tabBarHeight: CGFloat = 64
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Swipeable Page View
            TabView(selection: $urlRouter.selectedTab) {
                LegacyTonightView(core: core, eventLogger: eventLogger, undoState: undoState)
                    .environmentObject(themeManager)
                    .tag(AppTab.tonight)
                
                DetailsView(core: core, eventLogger: eventLogger)
                    .environmentObject(themeManager)
                    .tag(AppTab.timeline)
                
                HistoryView()
                    .environmentObject(themeManager)
                    .tag(AppTab.history)

                DashboardTabView(core: core, eventLogger: eventLogger)
                    .environmentObject(themeManager)
                    .tag(AppTab.dashboard)
                
                SettingsView()
                    .environmentObject(themeManager)
                    .tag(AppTab.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: tabBarHeight)
            }
            
            // Custom Tab Bar
            CustomTabBar(selectedTab: $urlRouter.selectedTab)
                .frame(height: tabBarHeight)
            
            // Undo Snackbar Overlay
            UndoOverlayView(stateManager: undoState)
            
            // URL Action Feedback Banner
            VStack {
                URLFeedbackBanner()
                Spacer()
            }
            .padding(.top, 50)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        shareVisiblePage()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 52, height: 52)
                            if isPreparingPageShare {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 22, weight: .semibold))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isPreparingPageShare)
                    .accessibilityLabel("Share current page screenshot")
                }
                .padding(.top, 54)
                .padding(.trailing, 16)
                Spacer()
            }
        }
        .preferredColorScheme(themeManager.currentTheme == .night ? .dark : (themeManager.currentTheme.colorScheme ?? settings.colorScheme))
        .accentColor(themeManager.currentTheme.accentColor)
        .applyNightModeFilter(themeManager.currentTheme)
        .fullScreenCover(isPresented: $alarmService.isAlarmRinging) {
            AlarmRingingView()
        }
        .sheet(isPresented: $showPageShareSheet) {
            if let sharedPageImage {
                ActivityViewController(activityItems: [sharedPageImage])
            }
        }
        .alert("Unable to Share Screen", isPresented: Binding(
            get: { pageShareErrorMessage != nil },
            set: { if !$0 { pageShareErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                pageShareErrorMessage = nil
            }
        } message: {
            Text(pageShareErrorMessage ?? "Unknown error.")
        }
        .onAppear {
            // P0 FIX: Wire DoseTapCore to SessionRepository (single source of truth)
            // All state reads/writes now go through SessionRepository
            core.setSessionRepository(sessionRepo)
            
            // Wire URLRouter dependencies for deep link handling
            urlRouter.core = core
            urlRouter.eventLogger = eventLogger
            
            // Setup undo callbacks
            setupUndoCallbacks()
        }
    }

    private func shareVisiblePage() {
        guard !isPreparingPageShare else { return }
        isPreparingPageShare = true
        pageShareErrorMessage = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let image = captureCurrentWindowScreenshot() {
                sharedPageImage = image
                showPageShareSheet = true
            } else {
                pageShareErrorMessage = "Could not capture the current screen."
            }
            isPreparingPageShare = false
        }
    }

    private func captureCurrentWindowScreenshot() -> UIImage? {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(bounds: keyWindow.bounds, format: format)
        return renderer.image { _ in
            keyWindow.drawHierarchy(in: keyWindow.bounds, afterScreenUpdates: true)
        }
    }
    
    private func setupUndoCallbacks() {
        // On commit: the action stays (do nothing, already saved)
        undoState.onCommit = { action in
            appLogger.info("Action committed: \(String(describing: action), privacy: .private)")
        }
        
        // On undo: revert the action
        undoState.onUndo = { action in
            Task { @MainActor in
                switch action {
                case .takeDose1(let time):
                    // Revert Dose 1
                    sessionRepo.clearDose1()
                    appLogger.info("Undid Dose 1 taken at \(time, privacy: .private)")
                    
                case .takeDose2(let time):
                    // Revert Dose 2
                    sessionRepo.clearDose2()
                    appLogger.info("Undid Dose 2 taken at \(time, privacy: .private)")
                    
                case .skipDose(let seq, _):
                    // Revert skip
                    sessionRepo.clearSkip()
                    appLogger.info("Undid skip of dose \(seq)")
                    
                case .snooze(let mins):
                    // Revert snooze (decrement count)
                    sessionRepo.decrementSnoozeCount()
                    appLogger.info("Undid snooze of \(mins) minutes")
                }
            }
        }
    }
}

struct AlarmRingingView: View {
    @ObservedObject private var alarmService = AlarmService.shared

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.red.opacity(0.9), .orange.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
                Text("Wake Alarm")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Text("It is time to wake up and complete your morning check-in.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.95))
                    .padding(.horizontal, 24)
                Button {
                    alarmService.stopRinging(acknowledge: true)
                } label: {
                    Text("Stop Alarm")
                        .font(.headline)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: AppTab
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                        Text(tab.label)
                            .font(.caption2)
                    }
                    .foregroundColor(selectedTab == tab ? .blue : .gray)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 6)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
        )
    }
}

// MARK: - Legacy Tonight View
struct LegacyTonightView: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var undoState: UndoStateManager
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @ObservedObject private var sleepPlanStore = SleepPlanStore.shared
    @State private var overrideEnabled: Bool = false
    @State private var overrideWake: Date = Date()
    @State private var showEarlyDoseAlert = false
    @State private var showOverrideConfirmation = false
    @State private var earlyDoseMinutesRemaining: Int = 0
    @State private var showMorningCheckIn = false
    @State private var showPreSleepLog = false
    @State private var showExtraDoseWarning = false  // For second dose 2 attempt
    @State private var incompleteSessionDate: String? = nil
    @State private var showIncompleteCheckIn = false
    @State private var preSleepLog: StoredPreSleepLog? = nil
    @State private var preSleepEditingLog: StoredPreSleepLog? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header - add extra top padding to account for safe area in page-style TabView
                VStack(spacing: 2) {
                    ZStack {
                        Text("DoseTap")
                            .font(.largeTitle.bold())
                        HStack {
                            Spacer()
                            QuickThemeSwitchButton()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    TonightDateLabel()
                    
                    // Show scheduled wake alarm when dose 1 taken
                    AlarmIndicatorView(dose1Time: core.dose1Time)
                        .padding(.top, 4)
                }
                .padding(.top, 50) // Safe area offset for page-style TabView
                
                if let message = sessionRepo.awaitingRolloverMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.orange)
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
            
            if let plan = sleepPlanSummary {
                SleepPlanSummaryCard(
                    wakeBy: plan.wakeBy,
                    recommendedInBed: plan.recommendedInBed,
                    windDown: plan.windDown,
                    expectedSleepMinutes: plan.expectedSleepMinutes
                )
                .padding(.horizontal)
                .padding(.top, 8)
                
                SleepPlanOverrideCard(
                    overrideEnabled: $overrideEnabled,
                    overrideWake: $overrideWake,
                    onUpdate: { date in
                        sleepPlanStore.setTonightOverride(sessionKey: sessionRepo.currentSessionKey, wakeBy: date)
                    },
                    onClear: {
                        sleepPlanStore.setTonightOverride(sessionKey: sessionRepo.currentSessionKey, wakeBy: nil)
                    },
                    baselineWake: plan.wakeBy
                )
                .padding(.horizontal)
                .padding(.top, 4)
            }
            
            // Incomplete Session Banner (if previous night wasn't completed)
            if let sessionDate = incompleteSessionDate {
                IncompleteSessionBanner(
                    sessionDate: sessionDate,
                    onComplete: {
                        showIncompleteCheckIn = true
                    },
                    onDismiss: {
                        incompleteSessionDate = nil
                    }
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
            Spacer().frame(height: 12)
            
            // Combined Status + Timer Card (compact)
            CompactStatusCard(core: core)
            
            Spacer().frame(height: 12)
            
            // Pre-Sleep Log Card (CTA or logged state)
            if preSleepLog != nil || core.dose1Time == nil {
                PreSleepCard(
                    state: PreSleepCardState(log: preSleepLog),
                    onAction: { action in
                        switch action {
                        case .start:
                            preSleepEditingLog = nil
                            showPreSleepLog = true
                        case .edit(let id):
                            if preSleepLog?.id == id {
                                preSleepEditingLog = preSleepLog
                            } else {
                                preSleepEditingLog = nil
                            }
                            showPreSleepLog = true
                        }
                    }
                )
                .padding(.horizontal)
                
                Spacer().frame(height: 12)
            }
            
            // Main Dose Button
            CompactDoseButton(
                core: core,
                eventLogger: eventLogger,
                undoState: undoState,
                sessionRepo: sessionRepo,
                showEarlyDoseAlert: $showEarlyDoseAlert,
                earlyDoseMinutes: $earlyDoseMinutesRemaining,
                showExtraDoseWarning: $showExtraDoseWarning
            )
            
            Spacer().frame(height: 12)
            
            // Quick Event Log
            QuickEventPanel(eventLogger: eventLogger)
                .padding(.horizontal)
            
            Spacer().frame(height: 12)
            
            // Wake Up & End Session Button (prominent)
            WakeUpButton(
                eventLogger: eventLogger,
                showMorningCheckIn: $showMorningCheckIn
            )
            .padding(.horizontal)
            
            Spacer().frame(height: 12)
            
            // Compact Session Summary (tap events to expand list)
            CompactSessionSummary(core: core, eventLogger: eventLogger)
                .padding(.horizontal)
            
            Spacer().frame(height: 12)
            
            // Inter-dose intervals for this session
            LiveDoseIntervalsCard(sessionRepo: sessionRepo)
                .padding(.horizontal)
            
            Spacer()
                .frame(height: 100) // Space for tab bar (increased from 80)
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showMorningCheckIn) {
            MorningCheckInView(
                sessionId: sessionRepo.currentSessionIdString(),
                sessionDate: sessionRepo.currentSessionDateString(),
                onComplete: {
                    appLogger.info("Morning check-in complete")
                }
            )
        }
        .sheet(isPresented: $showPreSleepLog) {
                PreSleepLogView(
                    existingLog: preSleepEditingLog,
                    onComplete: { answers in
                        let log = try sessionRepo.savePreSleepLog(
                            answers: answers,
                            completionState: "complete",
                            existingLog: preSleepEditingLog
                        )
                        if preSleepLog == nil {
                            sessionRepo.insertSleepEvent(
                                id: UUID().uuidString,
                                eventType: "lightsOut",
                                timestamp: Date(),
                                colorHex: "#6366F1", // Indigo for sleep cycle events
                                notes: "Pre-sleep check completed"
                            )
                        }
                        preSleepLog = log
                        preSleepEditingLog = log
                    },
                    onSkip: {
                        let log = try sessionRepo.savePreSleepLog(
                            answers: PreSleepLogAnswers(),
                            completionState: "skipped",
                            existingLog: preSleepEditingLog
                        )
                        if preSleepLog == nil {
                            sessionRepo.insertSleepEvent(
                                id: UUID().uuidString,
                                eventType: "lightsOut",
                                timestamp: Date(),
                                colorHex: "#6366F1",
                                notes: "Pre-sleep check skipped"
                            )
                        }
                        preSleepLog = log
                        preSleepEditingLog = log
                    }
                )
            }
        // Early dose alerts
        .alert("⚠️ Early Dose Warning", isPresented: $showEarlyDoseAlert) {
            Button("Cancel", role: .cancel) { }
            Button("I Understand the Risk", role: .destructive) {
                showOverrideConfirmation = true
            }
        } message: {
            Text("The dose window hasn't opened yet.\n\n\(TimeIntervalMath.formatMinutes(earlyDoseMinutesRemaining)) remaining until window opens.\n\nTaking Dose 2 too early may reduce effectiveness.")
        }
        .sheet(isPresented: $showOverrideConfirmation) {
            EarlyDoseOverrideSheet(
                minutesRemaining: earlyDoseMinutesRemaining,
                onConfirm: {
                    Task {
                        // Taking Dose 2 early with explicit override
                        await core.takeDose(earlyOverride: true)
                        // Log dose as event with Early badge for Details tab
                        eventLogger.logEvent(name: "Dose 2 (Early)", color: .orange, cooldownSeconds: 3600 * 8, persist: false)
                    }
                    showOverrideConfirmation = false
                },
                onCancel: { showOverrideConfirmation = false }
            )
        }
        // Extra dose warning (attempting second dose 2)
        .alert("⚠️ STOP - Dose 2 Already Taken", isPresented: $showExtraDoseWarning) {
            Button("Cancel", role: .cancel) { }
            Button("I Accept Full Responsibility", role: .destructive) {
                // Record as extra_dose with explicit user confirmation
                Task {
                    let now = Date()
                    // Save as extra_dose (does NOT update dose2_time)
                    sessionRepo.saveDose2(timestamp: now, isExtraDose: true)
                    // Log with warning color
                    eventLogger.logEvent(name: "Extra Dose ⚠️", color: .red, cooldownSeconds: 0, persist: false)
                    appLogger.warning("Extra dose logged at \(now, privacy: .private) - user confirmed")
                }
            }
        } message: {
            Text("You have already taken Dose 2 tonight at \(core.dose2Time?.formatted(date: .omitted, time: .shortened) ?? "unknown").\n\n⛔️ TAKING ADDITIONAL DOSES CAN BE DANGEROUS.\n\nThis action will be logged but will NOT replace your original Dose 2 time.\n\nDo NOT proceed unless absolutely necessary.")
        }
        // Incomplete session check-in sheet
        .sheet(isPresented: $showIncompleteCheckIn) {
            if let sessionDate = incompleteSessionDate {
                let sessionId = sessionRepo.fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
                MorningCheckInView(
                    sessionId: sessionId,
                    sessionDate: sessionDate,
                    onComplete: {
                        appLogger.info("Incomplete session check-in complete for: \(sessionDate, privacy: .private)")
                        incompleteSessionDate = nil
                    }
                )
            }
        }
        .onAppear {
            // Check for incomplete sessions on view appear
            incompleteSessionDate = sessionRepo.mostRecentIncompleteSession()
            syncOverrideState()
            reloadPreSleepLog()
        }
        .onChange(of: sessionRepo.currentSessionKey) { _ in
            syncOverrideState()
            reloadPreSleepLog()
        }
        .onReceive(sessionRepo.sessionDidChange) { _ in
            reloadPreSleepLog()
        }
        .onChange(of: showPreSleepLog) { newValue in
            if !newValue {
                preSleepEditingLog = nil
                reloadPreSleepLog()
            }
        }
    }

    private func syncOverrideState() {
        let key = sessionRepo.currentSessionKey
        sleepPlanStore.clearObsoleteOverrides(currentSessionKey: key)
        if let override = sleepPlanStore.overrideForSession(key) {
            overrideEnabled = true
            overrideWake = override
        } else {
            overrideEnabled = false
            let base = sleepPlanStore.wakeByDate(for: key)
            overrideWake = base
        }
    }
    
    private var sleepPlanSummary: (wakeBy: Date, recommendedInBed: Date, windDown: Date, expectedSleepMinutes: Double)? {
        let key = sessionRepo.currentSessionKey
        return sleepPlanStore.plan(for: key, now: Date(), tz: TimeZone.current)
    }
    
    private func reloadPreSleepLog() {
        let key = sessionRepo.preSleepLogSessionKey(for: Date())
        preSleepLog = sessionRepo.fetchMostRecentPreSleepLog(sessionId: key)
        if preSleepLog == nil {
            preSleepEditingLog = nil
        }
    }
}

struct QuickThemeSwitchButton: View {
    @EnvironmentObject var themeManager: ThemeManager

    private var nextTheme: AppTheme {
        switch themeManager.currentTheme {
        case .light:
            return .dark
        case .dark:
            return .night
        case .night:
            return .light
        }
    }

    var body: some View {
        Button {
            themeManager.applyTheme(nextTheme)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: themeManager.currentTheme.icon)
                    .font(.caption.bold())
                Text(themeManager.currentTheme.rawValue)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                Capsule()
                    .stroke(themeManager.currentTheme.accentColor.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Theme quick switch")
        .accessibilityHint("Switches to \(nextTheme.rawValue)")
        .contextMenu {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    themeManager.applyTheme(theme)
                } label: {
                    Label(theme.rawValue, systemImage: theme.icon)
                }
            }
        }
    }
}

// MARK: - Tonight Date Label
struct TonightDateLabel: View {
    @ObservedObject private var sessionRepo = SessionRepository.shared
    
    var body: some View {
        Text(tonightDateString)
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    
    private var tonightDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        
        // Use the session key to determine the "Tonight" date
        // If the session key is 2025-12-26, we want to show Friday, Dec 26
        let key = sessionRepo.currentSessionKey
        let keyFormatter = DateFormatter()
        keyFormatter.dateFormat = "yyyy-MM-dd"
        keyFormatter.timeZone = TimeZone.current
        
        if let date = keyFormatter.date(from: key) {
            return "Tonight – " + formatter.string(from: date)
        }
        
        return "Tonight – " + formatter.string(from: Date())
    }
}

// MARK: - Sleep Plan UI
private struct SleepPlanSummaryCard: View {
    let wakeBy: Date
    let recommendedInBed: Date
    let windDown: Date
    let expectedSleepMinutes: Double
    
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        f.timeZone = TimeZone.current
        return f
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Sleep Plan", systemImage: "bed.double.fill")
                    .font(.headline)
                Spacer()
                Text("Wake by \(timeFormatter.string(from: wakeBy))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended in bed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(timeFormatter.string(from: recommendedInBed))
                        .font(.body.bold())
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wind down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(timeFormatter.string(from: windDown))
                        .font(.body.bold())
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("If in bed now")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(expectedSleepMinutes)) min")
                        .font(.body.bold())
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

private struct SleepPlanOverrideCard: View {
    @Binding var overrideEnabled: Bool
    @Binding var overrideWake: Date
    let onUpdate: (Date) -> Void
    let onClear: () -> Void
    let baselineWake: Date
    
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        f.timeZone = TimeZone.current
        return f
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Just for tonight", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $overrideEnabled)
                    .labelsHidden()
                    .onChange(of: overrideEnabled) { newValue in
                        if newValue {
                            onUpdate(overrideWake)
                        } else {
                            onClear()
                        }
                    }
            }
            
            if overrideEnabled {
                DatePicker(
                    "Wake by",
                    selection: $overrideWake,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .onChange(of: overrideWake) { newValue in
                    onUpdate(newValue)
                }
                
                Button(role: .destructive) {
                    overrideWake = baselineWake
                    overrideEnabled = false
                    onClear()
                } label: {
                    Label("Reset to schedule (\(timeFormatter.string(from: baselineWake)))", systemImage: "arrow.uturn.backward")
                }
                .font(.caption)
            } else {
                Text("Uses your Typical Week wake time (\(timeFormatter.string(from: baselineWake)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))
    }
}

enum PreSleepCardAction: Equatable {
    case start
    case edit(id: String)
}

struct PreSleepCardState: Equatable {
    let logId: String?
    let completionState: String?
    let createdAtUtc: String?
    let localOffsetMinutes: Int?
    
    init(log: StoredPreSleepLog?) {
        logId = log?.id
        completionState = log?.completionState
        createdAtUtc = log?.createdAtUtc
        localOffsetMinutes = log?.localOffsetMinutes
    }
    
    var isLogged: Bool {
        logId != nil
    }
    
    var action: PreSleepCardAction {
        if let logId = logId {
            return .edit(id: logId)
        }
        return .start
    }
}

struct PreSleepCard: View {
    let state: PreSleepCardState
    let onAction: (PreSleepCardAction) -> Void
    
    private var titleText: String {
        if state.isLogged {
            return state.completionState == "skipped" ? "Pre-sleep skipped" : "Pre-sleep logged"
        }
        return "Pre-Sleep Check"
    }
    
    private var subtitleText: String {
        if state.isLogged {
            return "At \(timestamp)"
        }
        return "Quick 30-second check-in"
    }
    
    private var iconName: String {
        if state.isLogged {
            return state.completionState == "skipped" ? "minus.circle.fill" : "checkmark.seal.fill"
        }
        return "moon.stars.fill"
    }
    
    private var iconColor: Color {
        if state.isLogged {
            return state.completionState == "skipped" ? .orange : .green
        }
        return .indigo
    }
    
    private var timestamp: String {
        guard let createdAtUtc = state.createdAtUtc else {
            return "unknown"
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: createdAtUtc) else {
            return "unknown"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        if let offset = state.localOffsetMinutes {
            formatter.timeZone = TimeZone(secondsFromGMT: offset * 60) ?? .current
        }
        return formatter.string(from: date)
    }
    
    var body: some View {
        Button {
            onAction(state.action)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(iconColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.bold())
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if state.isLogged {
                    Text("Edit")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                        )
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(state.isLogged ? Color(.secondarySystemBackground) : Color.indigo.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                state.isLogged ? Color(.separator) : Color.indigo.opacity(0.3),
                                lineWidth: 1
                            )
                    )
            )
            .foregroundColor(state.isLogged ? .primary : .indigo)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Alarm Indicator View
/// Shows scheduled wake alarm time (dose 2 target) when dose 1 has been taken
struct AlarmIndicatorView: View {
    let dose1Time: Date?
    @ObservedObject private var alarmService = AlarmService.shared
    @AppStorage("target_interval_minutes") private var targetIntervalMinutes: Int = 165
    
    var body: some View {
        if let d1 = dose1Time {
            // Use AlarmService's target time if available (accounts for snoozes)
            // Otherwise fall back to calculated time
            let alarmTime = alarmService.targetWakeTime ?? d1.addingTimeInterval(Double(targetIntervalMinutes) * 60)
            let snoozeCount = alarmService.snoozeCount
            
            HStack(spacing: 4) {
                Image(systemName: alarmService.alarmScheduled ? "alarm.fill" : "alarm")
                    .font(.caption)
                    .foregroundColor(alarmService.alarmScheduled ? .orange : .gray)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("Wake: \(formattedTime(alarmTime))")
                        .font(.caption.bold())
                        .foregroundColor(alarmService.alarmScheduled ? .orange : .gray)
                    
                    if snoozeCount > 0 {
                        Text("(+\(snoozeCount * 10)m)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(alarmService.alarmScheduled ? 0.15 : 0.05))
            .cornerRadius(8)
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Incomplete Session Banner
struct IncompleteSessionBanner: View {
    let sessionDate: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Incomplete Session")
                    .font(.subheadline.bold())
                Text("Complete check-in for \(formattedDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Complete") {
                onComplete()
            }
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.orange))
            
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var formattedDate: String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = inputFormatter.date(from: sessionDate) else {
            return sessionDate
        }
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMM d"
        return outputFormatter.string(from: date)
    }
}


// MARK: - Hard Stop Countdown View
/// Prominent countdown UI shown when window is closing (<15 min remaining)
struct HardStopCountdownView: View {
    let timeRemaining: TimeInterval
    
    var body: some View {
        VStack(spacing: 4) {
            // Pulsing warning icon
            HStack(spacing: 8) {
                warningIcon
                Text("HARD STOP")
                    .font(.caption.bold())
                    .tracking(2)
                warningIcon
            }
            .foregroundColor(.red)
            
            // Large countdown timer
            Text(formatCountdown)
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundColor(urgencyColor)
                .monospacedDigit()
                .animation(.easeInOut(duration: 0.3), value: timeRemaining)
            
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(urgencyColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }
            .frame(width: 100, height: 100)
            .overlay(
                VStack(spacing: 0) {
                    Text("time left")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(TimeIntervalMath.formatMinutes(Int(timeRemaining / 60)))
                        .font(.title.bold())
                        .foregroundColor(urgencyColor)
                    Text(" ")
                        .font(.caption2)
                        .foregroundColor(.clear)
                }
            )
            
            // Urgency message
            Text(urgencyMessage)
                .font(.subheadline.bold())
                .foregroundColor(urgencyColor)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
    }
    
    @ViewBuilder
    private var warningIcon: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .symbolEffect(.pulse)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
        }
    }
    
    private var formatCountdown: String {
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var progress: CGFloat {
        // 15 minutes = 900 seconds is 100%
        CGFloat(timeRemaining / 900)
    }
    
    private var urgencyColor: Color {
        let minutes = timeRemaining / 60
        if minutes < 2 {
            return .red
        } else if minutes < 5 {
            return .orange
        } else {
            return .yellow
        }
    }
    
    private var urgencyMessage: String {
        let minutes = Int(timeRemaining / 60)
        if minutes < 2 {
            return "⚠️ TAKE DOSE NOW!"
        } else if minutes < 5 {
            return "Window closing very soon!"
        } else {
            return "Take Dose 2 before window closes"
        }
    }
}

// MARK: - Compact Status Card (combines status + timer)
struct CompactStatusCard: View {
    @ObservedObject var core: DoseTapCore
    @EnvironmentObject var themeManager: ThemeManager
    @State private var timeRemaining: TimeInterval = 0
    @State private var windowCloseRemaining: TimeInterval = 0
    @State private var lastAnnouncedMinute: Int = -1
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private let windowOpenMinutes: TimeInterval = 150
    private let windowCloseMinutes: TimeInterval = 240
    
    var body: some View {
        VStack(spacing: 8) {
            // Status with icon
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.title3)
                Text(statusTitle)
                    .font(.headline)
            }
            .foregroundColor(statusColor)
            
            // Timer (waiting for window to open)
            if core.currentStatus == .beforeWindow, core.dose1Time != nil {
                Text(formatTimeRemaining)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                    .monospacedDigit()
                    .accessibilityLabel(accessibleTimeRemaining)
                
                Text("Window opens at \(formatWindowOpenTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            // Hard Stop Countdown (near close - <15 min)
            else if core.currentStatus == .nearClose, core.dose1Time != nil {
                HardStopCountdownView(timeRemaining: windowCloseRemaining)
            }
            else {
                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(statusColor.opacity(0.1))
        )
        .padding(.horizontal)
        // Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityStatusLabel)
        .accessibilityHint(accessibilityStatusHint)
        .onAppear { updateTimeRemaining() }
        .onReceive(timer) { _ in 
            updateTimeRemaining()
            announceTimeIfNeeded()
        }
    }
    
    private func updateTimeRemaining() {
        guard let dose1 = core.dose1Time else { return }
        let windowOpenTime = dose1.addingTimeInterval(windowOpenMinutes * 60)
        let windowCloseTime = dose1.addingTimeInterval(windowCloseMinutes * 60)
        timeRemaining = max(0, windowOpenTime.timeIntervalSince(Date()))
        windowCloseRemaining = max(0, windowCloseTime.timeIntervalSince(Date()))
    }
    
    /// Announce time at key intervals for VoiceOver users
    private func announceTimeIfNeeded() {
        let currentMinute = Int(timeRemaining) / 60
        guard currentMinute != lastAnnouncedMinute else { return }
        
        // Announce at 60, 30, 15, 10, 5, 1 minute marks
        let announceMinutes = [60, 30, 15, 10, 5, 1]
        if announceMinutes.contains(currentMinute) && UIAccessibility.isVoiceOverRunning {
            let announcement = "\(spokenMinutes(currentMinute)) remaining until dose window opens"
            UIAccessibility.post(notification: .announcement, argument: announcement)
            lastAnnouncedMinute = currentMinute
        }
    }
    
    private var formatTimeRemaining: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    
    private var accessibleTimeRemaining: String {
        spokenMinutes(Int(timeRemaining / 60)) + " remaining"
    }
    
    private var accessibilityStatusLabel: String {
        switch core.currentStatus {
        case .noDose1: 
            return "Ready for Dose 1. Tap the button below to take your first dose."
        case .beforeWindow:
            return "Waiting for window. \(accessibleTimeRemaining)"
        case .active:
            return "Dose window is open. You can take Dose 2 now."
        case .nearClose:
            let minutes = Int(windowCloseRemaining / 60)
            return "Warning: Window closing soon! Only \(spokenMinutes(minutes)) remaining."
        case .closed:
            return "Window has closed. Dose 2 was not taken in time."
        case .completed:
            return "Session complete. Both doses taken successfully."
        case .finalizing:
            return "Finalizing session. Complete your morning check-in."
        }
    }
    
    private var accessibilityStatusHint: String {
        switch core.currentStatus {
        case .noDose1: return "Double tap to take Dose 1"
        case .beforeWindow: return "Wait for the countdown to finish"
        case .active, .nearClose: return "Double tap to take Dose 2"
        case .closed: return "Session has expired"
        case .completed, .finalizing: return ""
        }
    }

    private func spokenMinutes(_ minutes: Int) -> String {
        let isNegative = minutes < 0
        let total = abs(minutes)
        let hours = total / 60
        let mins = total % 60
        let prefix = isNegative ? "minus " : ""
        if hours > 0 {
            if mins > 0 {
                return "\(prefix)\(hours) hours \(mins) minutes"
            }
            return "\(prefix)\(hours) hours"
        }
        return "\(prefix)\(mins) minutes"
    }
    
    private var formatWindowOpenTime: String {
        guard let dose1 = core.dose1Time else { return "" }
        return dose1.addingTimeInterval(windowOpenMinutes * 60).formatted(date: .omitted, time: .shortened)
    }
    
    private var statusIcon: String {
        switch core.currentStatus {
        case .noDose1: return "1.circle"
        case .beforeWindow: return "clock"
        case .active: return "checkmark.circle"
        case .nearClose: return "exclamationmark.triangle"
        case .closed: return "xmark.circle"
        case .completed: return "checkmark.seal.fill"
        case .finalizing: return "sunrise.fill"
        }
    }
    
    private var statusTitle: String {
        switch core.currentStatus {
        case .noDose1: return "Ready for Dose 1"
        case .beforeWindow: return "Waiting for Window"
        case .active: return "Window Open"
        case .nearClose: return "Closing Soon!"
        case .closed: return "Window Closed"
        case .completed: return "Complete"
        case .finalizing: return "Finalizing Session"
        }
    }
    
    private var statusDescription: String {
        switch core.currentStatus {
        case .noDose1: return "Tap below to start"
        case .beforeWindow: return "Wait for optimal timing"
        case .active: return "Take Dose 2 now"
        case .nearClose: return "Less than \(TimeIntervalMath.formatMinutes(15)) left!"
        case .closed: return "Window has closed"
        case .completed: return "Both doses taken ✓"
        case .finalizing: return "Complete morning check-in"
        }
    }
    
    private var statusColor: Color {
        let theme = themeManager.currentTheme
        switch core.currentStatus {
        case .noDose1: return theme == .night ? theme.accentColor : .blue
        case .beforeWindow: return theme == .night ? theme.warningColor : .orange
        case .active: return theme == .night ? theme.successColor : .green
        case .nearClose: return theme == .night ? theme.errorColor : .red
        case .closed: return .gray
        case .completed: return theme == .night ? Color(red: 0.6, green: 0.3, blue: 0.2) : .purple
        case .finalizing: return theme == .night ? theme.warningColor : .yellow
        }
    }
}

// MARK: - Compact Dose Button
struct CompactDoseButton: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var undoState: UndoStateManager
    @ObservedObject var sessionRepo: SessionRepository
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var showEarlyDoseAlert: Bool
    @Binding var earlyDoseMinutes: Int
    @Binding var showExtraDoseWarning: Bool  // For second dose 2 attempt
    @State private var showWindowExpiredOverride = false  // For taking dose after window expired
    
    private let windowOpenMinutes: Double = 150
    
    var body: some View {
        VStack(spacing: 8) {
            Button(action: handlePrimaryButtonTap) {
                Text(primaryButtonText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)  // Minimum 44pt tap target per Apple HIG
                    .background(primaryButtonColor)
                    .cornerRadius(12)
            }
            // Accessibility
            .accessibilityLabel(primaryButtonAccessibilityLabel)
            .accessibilityHint(primaryButtonAccessibilityHint)
            // Allow tapping even when completed (for extra dose warning) or closed (for override)
            .padding(.horizontal)
            .alert("Window Expired", isPresented: $showWindowExpiredOverride) {
                Button("Cancel", role: .cancel) { }
                Button("Take Dose 2 Anyway", role: .destructive) {
                    takeDose2WithOverride()
                }
            } message: {
                Text("The 240-minute window has passed. Taking Dose 2 late may affect efficacy. Are you sure you want to proceed?")
            }
            
            // Secondary buttons row
            if core.currentStatus != .noDose1 && core.currentStatus != .completed {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            // Snooze the alarm (+10 min) and increment count
                            if let newTime = await AlarmService.shared.snoozeAlarm(dose1Time: core.dose1Time) {
                                await core.snooze()
                                appLogger.info("Snoozed to \(newTime.formatted(date: .omitted, time: .shortened))")
                            } else {
                                // Still increment count even if alarm couldn't be rescheduled
                                await core.snooze()
                            }
                        }
                    } label: {
                        Label("Snooze +10m", systemImage: "bell.badge")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!snoozeEnabled)
                    
                    Button {
                        Task {
                            await core.skipDose()
                            // Cancel wake alarm since Dose 2 was skipped
                            AlarmService.shared.cancelAllAlarms()
                        }
                    } label: {
                        Label("Skip", systemImage: "forward.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!skipEnabled)
                }
            }
        }
    }
    
    private func handlePrimaryButtonTap() {
        guard core.dose1Time != nil else {
            Task {
                let now = Date()
                await core.takeDose()
                // Log Dose 1 as event for Details tab
                eventLogger.logEvent(name: "Dose 1", color: .green, cooldownSeconds: 3600 * 8, persist: false)
                // Register for undo
                undoState.register(.takeDose1(at: now))
                
                // Schedule wake alarm for default target time (165 min after Dose 1)
                let targetMinutes = UserDefaults.standard.integer(forKey: "target_interval_minutes")
                let targetInterval = targetMinutes > 0 ? targetMinutes : 165
                let wakeTime = now.addingTimeInterval(Double(targetInterval) * 60)
                await AlarmService.shared.scheduleWakeAlarm(at: wakeTime, dose1Time: now)
                
                // Schedule Dose 2 reminders (window open, 15 min warning, 5 min warning)
                await AlarmService.shared.scheduleDose2Reminders(dose1Time: now)
            }
            return
        }
        
        // SAFETY: Check if Dose 2 already taken (extra dose starts at dose 3+)
        let doseCount = sessionRepo.fetchDoseEventsForActiveSession()
            .filter { event in
                switch event.eventType {
                case "dose1", "dose2", "extra_dose":
                    return true
                default:
                    return false
                }
            }
            .count
        if doseCount >= 2 {
            showExtraDoseWarning = true
            return
        }
        
        // Window expired - show override confirmation
        if core.currentStatus == .closed {
            showWindowExpiredOverride = true
            return
        }
        
        if core.currentStatus == .beforeWindow {
            if let dose1Time = core.dose1Time {
                let remaining = dose1Time.addingTimeInterval(windowOpenMinutes * 60).timeIntervalSince(Date())
                earlyDoseMinutes = max(1, Int(ceil(remaining / 60)))
            }
            showEarlyDoseAlert = true
            return
        }
        
        Task {
            let now = Date()
            await core.takeDose()
            // Log Dose 2 as event for Details tab
            eventLogger.logEvent(name: "Dose 2", color: .green, cooldownSeconds: 3600 * 8, persist: false)
            // Register for undo
            undoState.register(.takeDose2(at: now))
            // Cancel wake alarm since Dose 2 was taken
            AlarmService.shared.cancelAllAlarms()
        }
    }
    
    /// Take Dose 2 after window expired with explicit user override
    private func takeDose2WithOverride() {
        Task {
            let now = Date()
            await core.takeDose(lateOverride: true)
            // Log with late indicator
            eventLogger.logEvent(name: "Dose 2 (Late)", color: .orange, cooldownSeconds: 3600 * 8, persist: false)
            // Register for undo (late doses can also be undone)
            undoState.register(.takeDose2(at: now))
        }
    }
    
    private var primaryButtonText: String {
        switch core.currentStatus {
        case .noDose1: return "Take Dose 1"
        case .beforeWindow: return "Waiting..."
        case .active, .nearClose: return "Take Dose 2"
        case .closed: return "Take Dose 2 (Late)"
        case .completed: return "Complete ✓"
        case .finalizing: return "Check-In"
        }
    }
    
    private var primaryButtonAccessibilityLabel: String {
        switch core.currentStatus {
        case .noDose1: return "Take Dose 1 button"
        case .beforeWindow: return "Waiting for dose window to open"
        case .active: return "Take Dose 2 button. Window is open."
        case .nearClose: return "Take Dose 2 button. Warning: window closing soon!"
        case .closed: return "Take Dose 2 late button. Window has closed."
        case .completed: return "Session complete. Both doses taken."
        case .finalizing: return "Complete morning check-in button"
        }
    }
    
    private var primaryButtonAccessibilityHint: String {
        switch core.currentStatus {
        case .noDose1: return "Double tap to take Dose 1"
        case .beforeWindow: return "Wait for the countdown to finish"
        case .active: return "Double tap to take Dose 2"
        case .nearClose: return "Double tap now to take your second dose before the window closes"
        case .closed: return "Double tap to take dose late. You will be asked to confirm."
        case .completed: return ""
        case .finalizing: return "Double tap to complete your session"
        }
    }
    
    private var primaryButtonColor: Color {
        let theme = themeManager.currentTheme
        switch core.currentStatus {
        case .noDose1: return theme == .night ? theme.buttonBackground : .blue
        case .beforeWindow: return .gray
        case .active: return theme == .night ? theme.successColor : .green
        case .nearClose: return theme == .night ? theme.warningColor : .orange
        case .closed: return theme == .night ? theme.errorColor : .red
        case .completed: return theme == .night ? Color(red: 0.6, green: 0.3, blue: 0.2) : .purple
        case .finalizing: return theme == .night ? theme.warningColor : .yellow
        }
    }
    
    private var snoozeEnabled: Bool {
        (core.currentStatus == .active || core.currentStatus == .nearClose) && core.snoozeCount < 3
    }
    
    private var skipEnabled: Bool {
        core.currentStatus == .active || core.currentStatus == .nearClose || core.currentStatus == .closed
    }
}

// MARK: - Compact Session Summary (horizontal)
struct CompactSessionSummary: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @State private var showEventsPopover = false
    
    var body: some View {
        HStack(spacing: 16) {
            CompactSummaryItem(
                icon: "1.circle.fill",
                value: core.dose1Time?.formatted(date: .omitted, time: .shortened) ?? "–",
                label: "Dose 1",
                color: core.dose1Time != nil ? .green : .gray
            )
            
            Divider()
                .frame(height: 36)
            
            CompactSummaryItem(
                icon: "2.circle.fill",
                value: dose2Value,
                label: "Dose 2",
                color: dose2Color
            )
            
            Divider()
                .frame(height: 36)
            
            // Tappable Events item - opens sheet/popover
            Button(action: {
                showEventsPopover = true
            }) {
                VStack(spacing: 2) {
                    Image(systemName: "list.bullet")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("\(eventLogger.events.count)")
                        .font(.caption.bold())
                    Text("Events")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            
            Divider()
                .frame(height: 36)
            
            CompactSummaryItem(
                icon: "bell.fill",
                value: "\(core.snoozeCount)/3",
                label: "Snooze",
                color: core.snoozeCount > 0 ? .orange : .gray
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .sheet(isPresented: $showEventsPopover) {
            TonightEventsSheet(events: eventLogger.events, onDelete: { id in
                eventLogger.deleteEvent(id: id)
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
    
    private var dose2Value: String {
        if let time = core.dose2Time {
            return time.formatted(date: .omitted, time: .shortened)
        }
        if core.isSkipped { return "Skip" }
        return "–"
    }
    
    private var dose2Color: Color {
        if core.dose2Time != nil { return .green }
        if core.isSkipped { return .orange }
        return .gray
    }
}

// MARK: - Live Dose Intervals Card
struct LiveDoseIntervalsCard: View {
    @ObservedObject var sessionRepo: SessionRepository
    @State private var doseEvents: [DoseCore.StoredDoseEvent] = []

    var body: some View {
        DoseIntervalsCard(doseEvents: doseEvents)
            .onAppear { load() }
            .onReceive(sessionRepo.sessionDidChange) { _ in load() }
    }

    private func load() {
        doseEvents = sessionRepo.fetchDoseEventsForActiveSession()
    }
}

// MARK: - Dose Intervals Card
struct DoseIntervalsCard: View {
    let doseEvents: [DoseCore.StoredDoseEvent]

    private struct DoseEventDisplay: Identifiable {
        let id: String
        let index: Int
        let timestamp: Date
        let isExtra: Bool
        let isLate: Bool
        let isEarly: Bool
    }

    private struct DoseIntervalDisplay: Identifiable {
        let id = UUID()
        let from: DoseEventDisplay
        let to: DoseEventDisplay
        let minutes: Int
    }

    private var doseDisplays: [DoseEventDisplay] {
        let filtered = doseEvents.filter { event in
            switch event.eventType {
            case "dose1", "dose2", "extra_dose":
                return true
            default:
                return false
            }
        }
        let sorted = filtered.sorted { $0.timestamp < $1.timestamp }
        return sorted.enumerated().map { index, event in
            let flags = parseDoseMetadata(event.metadata)
            let isExtra = event.eventType == "extra_dose" || (index + 1) >= 3
            return DoseEventDisplay(
                id: event.id,
                index: index + 1,
                timestamp: event.timestamp,
                isExtra: isExtra,
                isLate: flags.isLate,
                isEarly: flags.isEarly
            )
        }
    }

    private var intervalDisplays: [DoseIntervalDisplay] {
        guard doseDisplays.count >= 2 else { return [] }
        var intervals: [DoseIntervalDisplay] = []
        for idx in 1..<doseDisplays.count {
            let from = doseDisplays[idx - 1]
            let to = doseDisplays[idx]
            let minutes = TimeIntervalMath.minutesBetween(start: from.timestamp, end: to.timestamp)
            intervals.append(DoseIntervalDisplay(from: from, to: to, minutes: minutes))
        }
        return intervals
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dose Intervals")
                .font(.headline)

            if intervalDisplays.isEmpty {
                Text("No dose intervals yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(intervalDisplays) { interval in
                    HStack(spacing: 8) {
                        Text("\(doseLabel(for: interval.from)) -> \(doseLabel(for: interval.to))")
                            .font(.subheadline)
                        Spacer()
                        Text(TimeIntervalMath.formatMinutes(interval.minutes))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func doseLabel(for dose: DoseEventDisplay) -> String {
        var label = "Dose \(dose.index)"
        if dose.index == 2 {
            if dose.isLate { label += " (Late)" }
            if dose.isEarly { label += " (Early)" }
        } else if dose.isExtra {
            label += " (Extra)"
        }
        return label
    }

    private func parseDoseMetadata(_ metadata: String?) -> (isLate: Bool, isEarly: Bool) {
        guard let metadata = metadata,
              let data = metadata.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, false)
        }
        let isLate = json["is_late"] as? Bool ?? false
        let isEarly = json["is_early"] as? Bool ?? false
        return (isLate, isEarly)
    }
}

struct CompactSummaryItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(value)
                .font(.caption.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tonight Events Sheet (Popover replacement for better visibility)
struct TonightEventsSheet: View {
    let events: [LoggedEvent]
    let onDelete: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if events.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No events logged tonight")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Use the Quick Log buttons to track sleep events")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(events.sorted(by: { $0.time > $1.time })) { event in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(event.color)
                                    .frame(width: 12, height: 12)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.name)
                                        .font(.body)
                                    Text(event.time.formatted(date: .omitted, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { indexSet in
                            let sorted = events.sorted(by: { $0.time > $1.time })
                            for index in indexSet {
                                onDelete(sorted[index].id)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Tonight's Events")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Quick Event Panel (Compact)
struct QuickEventPanel: View {
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var settings = UserSettingsManager.shared
    
    // Get quick events (max 15)
    private var quickEvents: [(name: String, icon: String, color: Color)] {
        let all = settings.quickLogButtons.map { ($0.name, $0.icon, $0.color) }
        return Array(all.prefix(15))
    }
    
    /// Dynamic grid layout based on icon count:
    /// - 9 icons = 3x3
    /// - 10 icons = 5x2
    /// - 12 icons = 4x3
    /// - 11-15 icons = 5x3
    private var columnsForCount: Int {
        let count = quickEvents.count
        switch count {
        case 0...3: return count  // Single row
        case 4: return 4          // 4x1
        case 5: return 5          // 5x1
        case 6: return 3          // 3x2
        case 7...8: return 4      // 4x2
        case 9: return 3          // 3x3
        case 10: return 5         // 5x2
        case 11...12: return 4    // 4x3
        default: return 5         // 5x3 for 13-15
        }
    }
    
    // Split into rows based on dynamic column count
    private var eventRows: [[(name: String, icon: String, color: Color)]] {
        let cols = columnsForCount
        var rows: [[(name: String, icon: String, color: Color)]] = []
        var currentRow: [(name: String, icon: String, color: Color)] = []
        
        for (index, event) in quickEvents.enumerated() {
            currentRow.append(event)
            if currentRow.count == cols || index == quickEvents.count - 1 {
                rows.append(currentRow)
                currentRow = []
            }
        }
        return rows
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Quick Log")
                    .font(.caption.bold())
                Spacer()
                if !eventLogger.events.isEmpty {
                    Text("\(eventLogger.events.count) tonight")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Display rows with dynamic column count
            ForEach(0..<eventRows.count, id: \.self) { rowIndex in
                HStack(spacing: 4) {
                    ForEach(eventRows[rowIndex], id: \.name) { event in
                        quickButton(for: event)
                    }
                    // Fill remaining space if row is incomplete
                    let cols = columnsForCount
                    if eventRows[rowIndex].count < cols {
                        ForEach(0..<(cols - eventRows[rowIndex].count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
        )
    }
    
    @ViewBuilder
    private func quickButton(for event: (name: String, icon: String, color: Color)) -> some View {
        let cooldown = settings.cooldown(for: event.name)
        CompactQuickButton(
            name: event.name,
            icon: event.icon,
            color: event.color,
            cooldownSeconds: cooldown,
            cooldownEnd: eventLogger.cooldownEnd(for: event.name),
            onTap: {
                eventLogger.logEvent(name: event.name, color: event.color, cooldownSeconds: cooldown)
            }
        )
    }
}

// MARK: - Compact Quick Event Button
struct CompactQuickButton: View {
    let name: String
    let icon: String
    let color: Color
    let cooldownSeconds: TimeInterval
    let cooldownEnd: Date?
    let onTap: () -> Void
    
    @State private var progress: CGFloat = 1.0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    private var isOnCooldown: Bool {
        guard let end = cooldownEnd else { return false }
        return Date() < end
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isOnCooldown ? 0.2 : 0.15))
                        .frame(width: 44, height: 44)  // Minimum 44pt tap target
                    
                    if isOnCooldown {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(color.opacity(0.5), lineWidth: 2)
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                    }
                    
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(isOnCooldown ? color.opacity(0.4) : color)
                }
                
                Text(name)
                    .font(.system(size: 9))
                    .foregroundColor(isOnCooldown ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .disabled(isOnCooldown)
        .frame(maxWidth: .infinity)
        // Accessibility
        .accessibilityLabel("\(name) event button")
        .accessibilityHint(isOnCooldown ? "Button on cooldown. Wait to log again." : "Double tap to log \(name) event")
        .accessibilityAddTraits(isOnCooldown ? .isButton : [.isButton])
        .onReceive(timer) { _ in
            updateProgress()
        }
    }
    
    private func updateProgress() {
        guard let end = cooldownEnd else { progress = 1.0; return }
        let now = Date()
        if now >= end {
            progress = 1.0
        } else {
            let remaining = end.timeIntervalSince(now)
            progress = 1.0 - CGFloat(remaining / cooldownSeconds)
        }
    }
}

// MARK: - Wake Up & End Session Button
struct WakeUpButton: View {
    @ObservedObject var eventLogger: EventLogger
    @Binding var showMorningCheckIn: Bool
    @ObservedObject var settings = UserSettingsManager.shared
    private let sessionRepo = SessionRepository.shared
    @State private var showConfirmation = false
    
    // Wake Up cooldown (1 hour per SSOT)
    private let cooldownSeconds: TimeInterval = 3600
    
    var body: some View {
        Button {
            // Show confirmation dialog first
            showConfirmation = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundColor(.yellow)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake Up & End Session")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Complete your morning check-in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.yellow.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .disabled(isOnCooldown)
        .opacity(isOnCooldown ? 0.5 : 1.0)
        .confirmationDialog(
            "End Sleep Session?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Wake Up & Start Check-In") {
                logWakeAndShowCheckIn()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will log your wake time and open the morning check-in.")
        }
    }
    
    private func logWakeAndShowCheckIn() {
        // Log the Wake Up event for UI cooldown only (sessionRepo handles persistence)
        eventLogger.logEvent(
            name: "Wake Up",
            color: .yellow,
            cooldownSeconds: cooldownSeconds,
            persist: false
        )

        // Persist wake event + mark session finalizing
        sessionRepo.setWakeFinalTime(Date())
        
        // Show check-in immediately (slight delay to let confirmation dismiss)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showMorningCheckIn = true
        }
    }
    
    private var isOnCooldown: Bool {
        guard let end = eventLogger.cooldownEnd(for: "Wake Up") else { return false }
        return Date() < end
    }
}

// MARK: - Legacy Undo Snackbar (unused - real impl in Views/UndoSnackbarView.swift)
#if false
struct UndoSnackbarView: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void
    
    @State private var timeRemaining: Int = 5
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .foregroundColor(.white)
            
            Spacer()
            
            Text("\(timeRemaining)s")
                .foregroundColor(.white.opacity(0.7))
                .font(.caption)
                .monospacedDigit()
            
            Button("Undo") {
                onUndo()
            }
            .foregroundColor(.yellow)
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
        )
        .padding(.horizontal)
        .onReceive(timer) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            }
        }
    }
}
#endif

// MARK: - Session Summary Card
struct SessionSummaryCard: View {
    @ObservedObject var core: DoseTapCore
    let eventCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tonight's Session")
                .font(.headline)
            
            HStack(spacing: 20) {
                SummaryItem(
                    icon: "1.circle.fill",
                    label: "Dose 1",
                    value: core.dose1Time?.formatted(date: .omitted, time: .shortened) ?? "–",
                    color: core.dose1Time != nil ? .green : .gray
                )
                
                SummaryItem(
                    icon: "2.circle.fill",
                    label: "Dose 2",
                    value: doseValue,
                    color: dose2Color
                )
                
                SummaryItem(
                    icon: "list.bullet",
                    label: "Events",
                    value: "\(eventCount)",
                    color: .blue
                )
                
                SummaryItem(
                    icon: "bell.fill",
                    label: "Snoozes",
                    value: "\(core.snoozeCount)/3",
                    color: core.snoozeCount > 0 ? .orange : .gray
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
    
    private var doseValue: String {
        if let time = core.dose2Time {
            return time.formatted(date: .omitted, time: .shortened)
        }
        if core.isSkipped {
            return "Skipped"
        }
        return "–"
    }
    
    private var dose2Color: Color {
        if core.dose2Time != nil { return .green }
        if core.isSkipped { return .orange }
        return .gray
    }
}

struct SummaryItem: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Logged Event Model
enum DoseEventDisplay {
    static func displayNameAndColor(for event: DoseCore.StoredDoseEvent) -> (String, Color) {
        switch event.eventType {
        case "dose1":
            return ("Dose 1", .blue)
        case "dose2":
            return ("Dose 2", .green)
        case "extra_dose":
            return ("Extra Dose", .orange)
        case "snooze":
            return ("Snooze", .yellow)
        case "skip":
            return ("Dose Skipped", .orange)
        default:
            return (event.eventType.replacingOccurrences(of: "_", with: " ").capitalized, .gray)
        }
    }
}

enum EventDisplayName {
    static func displayName(for eventType: String) -> String {
        switch eventType {
        case "bathroom": return "Bathroom"
        case "water": return "Water"
        case "lightsOut", "lights_out": return "Lights Out"
        case "inBed", "in_bed": return "In Bed"
        case "wakeFinal", "wake_final": return "Wake Up"
        case "wakeTemp", "wake_temp": return "Brief Wake"
        case "anxiety": return "Anxiety"
        case "pain": return "Pain"
        case "noise": return "Noise"
        case "snack": return "Snack"
        case "dream": return "Dream"
        case "temperature": return "Temperature"
        case "heartRacing", "heart_racing": return "Heart Racing"
        default:
            return eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct LoggedEvent: Identifiable {
    let id: UUID
    let name: String
    let time: Date
    let color: Color
    
    init(id: UUID = UUID(), name: String, time: Date, color: Color) {
        self.id = id
        self.name = name
        self.time = time
        self.color = color
    }

    static func fromDoseEvent(_ event: DoseCore.StoredDoseEvent) -> LoggedEvent? {
        let (displayName, color) = DoseEventDisplay.displayNameAndColor(for: event)
        return LoggedEvent(
            id: UUID(uuidString: event.id) ?? UUID(),
            name: displayName,
            time: event.timestamp,
            color: color
        )
    }
}

// MARK: - Details View (Second Tab)
private enum TimelineMode: String, CaseIterable, Identifiable {
    case live = "Live"
    case review = "Review"

    var id: String { rawValue }
}

struct DetailsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @ObservedObject var settings = UserSettingsManager.shared
    @State private var selectedMode: TimelineMode = .live
    @State private var showLiveEventsSheet = false
    @State private var showPlanForTonight = false
    @State private var reviewSessions: [SessionSummary] = []
    @State private var selectedReviewSessionKey: String?
    @State private var reviewEvents: [StoredSleepEvent] = []
    @State private var reviewNightDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var reviewShareImage: UIImage?
    @State private var showReviewShareSheet = false
    @State private var isPreparingReviewShare = false
    @State private var reviewShareErrorMessage: String?
    
    // Use customized QuickLog buttons from settings
    private var quickLogEventTypes: [(name: String, icon: String, color: Color)] {
        settings.quickLogButtons.map { ($0.name, $0.icon, $0.color) }
    }

    private var reviewSession: SessionSummary? {
        guard let selectedReviewSessionKey else {
            return reviewSessions.first
        }
        return reviewSessions.first(where: { $0.sessionDate == selectedReviewSessionKey }) ?? reviewSessions.first
    }

    private var selectedReviewIndex: Int? {
        guard let selectedReviewSessionKey else { return nil }
        return reviewSessions.firstIndex(where: { $0.sessionDate == selectedReviewSessionKey })
    }

    private var canGoToOlderReviewNight: Bool {
        guard let index = selectedReviewIndex else { return false }
        return index < (reviewSessions.count - 1)
    }

    private var canGoToNewerReviewNight: Bool {
        guard let index = selectedReviewIndex else { return false }
        return index > 0
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                if selectedMode == .review {
                    VStack(spacing: 20) {
                        Picker("Timeline Mode", selection: $selectedMode) {
                            ForEach(TimelineMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        reviewContent
                    }
                    .padding()
                    .padding(.bottom, 80)
                } else {
                    VStack(spacing: 20) {
                        Picker("Timeline Mode", selection: $selectedMode) {
                            ForEach(TimelineMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        liveContent
                    }
                    .padding()
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedMode == .review, reviewSession != nil {
                        Button {
                            shareReviewSnapshot()
                        } label: {
                            if isPreparingReviewShare {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .disabled(isPreparingReviewShare)
                        .accessibilityLabel("Share review screenshot")
                    }
                }
            }
            .onAppear {
                refreshReviewContext()
                selectedMode = defaultMode()
            }
            .onReceive(sessionRepo.sessionDidChange) { _ in
                refreshReviewContext()
                if selectedMode == .review, reviewSession == nil {
                    selectedMode = .live
                }
            }
            .sheet(isPresented: $showLiveEventsSheet) {
                TonightEventsSheet(events: eventLogger.events, onDelete: { id in
                    eventLogger.deleteEvent(id: id)
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showReviewShareSheet) {
                if let reviewShareImage {
                    ActivityViewController(activityItems: [reviewShareImage])
                }
            }
            .alert("Unable to Share Review", isPresented: Binding(
                get: { reviewShareErrorMessage != nil },
                set: { if !$0 { reviewShareErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    reviewShareErrorMessage = nil
                }
            } message: {
                Text(reviewShareErrorMessage ?? "Unknown error.")
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var liveContent: some View {
        LiveNextActionCard(core: core)

        TonightTimelineProgressCard(core: core, events: eventLogger.events)

        FullEventLogGrid(
            eventTypes: quickLogEventTypes,
            eventLogger: eventLogger,
            settings: settings
        )

        LiveEventsPreviewCard(
            events: eventLogger.events,
            onViewAll: { showLiveEventsSheet = true }
        )
    }

    @ViewBuilder
    private var reviewContent: some View {
        if let session = reviewSession {
            VStack(spacing: 20) {
                ReviewStickyHeaderBar(
                    session: session,
                    events: reviewEvents,
                    nightDate: reviewNightDate,
                    hasMorningCheckIn: sessionRepo.fetchMorningCheckIn(for: session.sessionDate) != nil,
                    canGoToOlderNight: canGoToOlderReviewNight,
                    canGoToNewerNight: canGoToNewerReviewNight,
                    nightPositionText: reviewNightPositionText,
                    onGoOlder: goToOlderReviewNight,
                    onGoNewer: goToNewerReviewNight
                )

                CoachSummaryCard(
                    session: session,
                    events: reviewEvents
                )

                MergedNightTimelineCard(
                    session: session,
                    events: reviewEvents,
                    nightDate: reviewNightDate,
                    fullViewDestination: AnyView(
                        TimelineReviewDetailView(
                            core: core,
                            initialSessionKey: session.sessionDate
                        )
                    ),
                    fullViewLabel: "Full view"
                )

                ReviewKeyMetricsCard(session: session, events: reviewEvents)

                ReviewEventsAndNotesCard(
                    events: reviewEvents,
                    onKeepEvent: { event, group in
                        keepDuplicateEvent(event, in: group)
                    },
                    onDeleteEvent: { event in
                        deleteDuplicateEvent(event)
                    },
                    onMergeGroup: { group in
                        mergeDuplicateEvents(in: group)
                    }
                )

                DisclosureGroup(isExpanded: $showPlanForTonight) {
                    FullSessionDetails(core: core)
                        .padding(.top, 10)
                } label: {
                    Text("Plan for Tonight")
                        .font(.headline)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                )
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "moon.zzz")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("No completed night to review yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Switch to Live mode to track tonight's session.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
        }
    }

    private func refreshReviewContext() {
        let fetchedSessions = sessionRepo.fetchRecentSessions(days: 120)
        var sessionByKey: [String: SessionSummary] = [:]
        for session in fetchedSessions {
            sessionByKey[session.sessionDate] = session
        }

        let calendar = Calendar.current
        let candidates: [SessionSummary] = (1...90).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else {
                return nil
            }
            let key = sessionRepo.sessionDateString(for: eveningAnchorDate(for: date))
            return sessionByKey[key] ?? SessionSummary(sessionDate: key)
        }

        reviewSessions = candidates
        if let key = selectedReviewSessionKey, candidates.contains(where: { $0.sessionDate == key }) {
            selectedReviewSessionKey = key
        } else {
            selectedReviewSessionKey = candidates.first?.sessionDate
        }
        loadSelectedReviewSessionData()
    }

    private func loadSelectedReviewSessionData() {
        guard let selected = reviewSession else {
            reviewEvents = []
            reviewNightDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            return
        }

        reviewEvents = sessionRepo.fetchSleepEvents(for: selected.sessionDate).sorted(by: { $0.timestamp < $1.timestamp })
        reviewNightDate = Self.sessionDateFormatter.date(from: selected.sessionDate)
            ?? Calendar.current.date(byAdding: .day, value: -1, to: Date())
            ?? Date()
    }

    private func defaultMode() -> TimelineMode {
        if core.currentStatus == .completed || core.currentStatus == .finalizing || core.currentStatus == .closed {
            return .review
        }
        let hour = Calendar.current.component(.hour, from: Date())
        if (7...15).contains(hour), reviewSession != nil, core.dose1Time == nil {
            return .review
        }
        return .live
    }

    private func keepDuplicateEvent(_ keep: StoredSleepEvent, in group: StoredEventDuplicateGroup) {
        for event in group.events where event.id != keep.id {
            sessionRepo.deleteSleepEvent(id: event.id)
        }
        refreshReviewContext()
    }

    private func deleteDuplicateEvent(_ event: StoredSleepEvent) {
        sessionRepo.deleteSleepEvent(id: event.id)
        refreshReviewContext()
    }

    private func mergeDuplicateEvents(in group: StoredEventDuplicateGroup) {
        guard let canonical = group.events.sorted(by: { $0.timestamp < $1.timestamp }).first else {
            return
        }
        keepDuplicateEvent(canonical, in: group)
    }

    private var reviewNightPositionText: String {
        guard let index = selectedReviewIndex else { return "" }
        return "\(index + 1) of \(reviewSessions.count)"
    }

    private func goToOlderReviewNight() {
        guard let index = selectedReviewIndex, canGoToOlderReviewNight else { return }
        selectedReviewSessionKey = reviewSessions[index + 1].sessionDate
        loadSelectedReviewSessionData()
    }

    private func goToNewerReviewNight() {
        guard let index = selectedReviewIndex, canGoToNewerReviewNight else { return }
        selectedReviewSessionKey = reviewSessions[index - 1].sessionDate
        loadSelectedReviewSessionData()
    }

    private func shareReviewSnapshot() {
        guard let session = reviewSession else { return }
        isPreparingReviewShare = true
        reviewShareErrorMessage = nil

        Task { @MainActor in
            let snapshotTimeline = await fetchSnapshotSleepTimeline(for: reviewNightDate)
            InsightsCalculator.shared.computeInsights()

            let content = TimelineReviewShareSnapshotView(
                session: session,
                events: reviewEvents,
                nightDate: reviewNightDate,
                hasMorningCheckIn: sessionRepo.fetchMorningCheckIn(for: session.sessionDate) != nil,
                core: core,
                snapshotTimeline: snapshotTimeline
            )
            .frame(width: UIScreen.main.bounds.width - 24)
            .padding(.vertical, 8)
            .environment(\.colorScheme, colorScheme)
            .preferredColorScheme(colorScheme)

            let renderer = ImageRenderer(content: content)
            renderer.scale = UIScreen.main.scale

            if let image = renderer.uiImage {
                reviewShareImage = image
                showReviewShareSheet = true
            } else {
                reviewShareErrorMessage = "Could not generate a screenshot for this review."
            }

            isPreparingReviewShare = false
        }
    }

    private func fetchSnapshotSleepTimeline(for nightDate: Date) async -> ReviewSnapshotSleepTimeline? {
        let healthKit = HealthKitService.shared
        guard UserSettingsManager.shared.healthKitEnabled else { return nil }
        healthKit.checkAuthorizationStatus()
        guard healthKit.isAuthorized else { return nil }

        let queryStart = eveningAnchorDate(for: nightDate, hour: 18)
        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: nightDate) else { return nil }
        let queryEnd = eveningAnchorDate(for: nextDay, hour: 12)

        do {
            let segments = try await healthKit.fetchSegmentsForTimeline(from: queryStart, to: queryEnd)
            let stages = segments
                .map { segment in
                    SleepStageBand(
                        stage: mapHealthStageToTimeline(segment.stage),
                        startTime: segment.start,
                        endTime: segment.end
                    )
                }
                .sorted(by: { $0.startTime < $1.startTime })
            let filteredStages = primaryNightSleepBands(from: stages)

            guard !filteredStages.isEmpty else { return nil }

            let start = filteredStages.map(\.startTime).min() ?? queryStart
            let end = filteredStages.map(\.endTime).max() ?? queryEnd
            return ReviewSnapshotSleepTimeline(stages: filteredStages, start: start, end: end)
        } catch {
            return nil
        }
    }

    private func mapHealthStageToTimeline(_ stage: HealthKitService.SleepStage) -> SleepStage {
        switch HealthKitService.mapToDisplayStage(stage) {
        case .awake:
            return .awake
        case .light, .core:
            return .light
        case .deep:
            return .deep
        case .rem:
            return .rem
        }
    }

    private static let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}

// MARK: - Dashboard Date Range

