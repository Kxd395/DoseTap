import SwiftUI
import Combine
import DoseCore
import UIKit
#if canImport(Charts)
import Charts
#endif
#if canImport(CloudKit)
import CloudKit
#endif

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
        print("📦 Loaded \(events.count) events from SQLite")
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
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "lightsout", "lights_out":
            return "lights_out"
        case "wakefinal", "wake_final", "wake", "wakeup", "wake_up":
            return "wake_final"
        case "waketemp", "wake_temp", "brief_wake":
            return "wake_temp"
        case "inbed", "in_bed":
            return "in_bed"
        case "temp", "temperature":
            return "temperature"
        case "heartracing", "heart_racing":
            return "heart_racing"
        case "napstart", "nap_start":
            return "nap_start"
        case "napend", "nap_end":
            return "nap_end"
        default:
            return normalized
        }
    }

    private static func displayName(forEventType raw: String) -> String {
        switch canonicalEventType(raw) {
        case "bathroom": return "Bathroom"
        case "water": return "Water"
        case "snack": return "Snack"
        case "lights_out": return "Lights Out"
        case "wake_temp": return "Brief Wake"
        case "in_bed": return "In Bed"
        case "wake_final": return "Wake Up"
        case "anxiety": return "Anxiety"
        case "dream": return "Dream"
        case "heart_racing": return "Heart Racing"
        case "noise": return "Noise"
        case "temperature": return "Temperature"
        case "pain": return "Pain"
        case "nap_start": return "Nap Start"
        case "nap_end": return "Nap End"
        default:
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
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
            print("✅ Action committed: \(action)")
        }
        
        // On undo: revert the action
        undoState.onUndo = { action in
            Task { @MainActor in
                switch action {
                case .takeDose1(let time):
                    // Revert Dose 1
                    sessionRepo.clearDose1()
                    print("↩️ Undid Dose 1 taken at \(time)")
                    
                case .takeDose2(let time):
                    // Revert Dose 2
                    sessionRepo.clearDose2()
                    print("↩️ Undid Dose 2 taken at \(time)")
                    
                case .skipDose(let seq, _):
                    // Revert skip
                    sessionRepo.clearSkip()
                    print("↩️ Undid skip of dose \(seq)")
                    
                case .snooze(let mins):
                    // Revert snooze (decrement count)
                    sessionRepo.decrementSnoozeCount()
                    print("↩️ Undid snooze of \(mins) minutes")
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
                    // Session ended - could trigger a session reset here
                    print("✅ Morning check-in complete")
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
                    print("⚠️ Extra dose logged at \(now) - user confirmed")
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
                        print("✅ Incomplete session check-in complete for: \(sessionDate)")
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
                                print("✅ Snoozed to \(newTime.formatted(date: .omitted, time: .shortened))")
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
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
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

                InsightsSummaryCard(title: "Key Metrics", showDefinitions: true)

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

            guard !stages.isEmpty else { return nil }

            let start = stages.map(\.startTime).min() ?? queryStart
            let end = stages.map(\.endTime).max() ?? queryEnd
            return ReviewSnapshotSleepTimeline(stages: stages, start: start, end: end)
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

private struct DashboardNightAggregate: Identifiable {
    let sessionDate: String
    let dose1Time: Date?
    let dose2Time: Date?
    let dose2Skipped: Bool
    let snoozeCount: Int
    let extraDoseCount: Int
    let events: [StoredSleepEvent]
    let morningCheckIn: StoredMorningCheckIn?
    let preSleepLog: StoredPreSleepLog?
    let healthSummary: HealthKitService.SleepNightSummary?
    let duplicateClusterCount: Int
    let napSummary: SessionRepository.NapSummary

    var id: String { sessionDate }

    var intervalMinutes: Int? {
        guard let dose1Time, let dose2Time else { return nil }
        let minutes = TimeIntervalMath.minutesBetween(start: dose1Time, end: dose2Time)
        return minutes >= 0 ? minutes : nil
    }

    var onTimeDosing: Bool? {
        guard let intervalMinutes else { return nil }
        return (150...240).contains(intervalMinutes)
    }

    var totalSleepMinutes: Double? { healthSummary?.totalSleepMinutes }
    var ttfwMinutes: Double? { healthSummary?.ttfwMinutes }
    var wakeCount: Int? { healthSummary?.wakeCount }

    var bathroomEventCount: Int {
        events.filter { normalizeStoredEventType($0.eventType) == "bathroom" }.count
    }

    var hasAnyData: Bool {
        dose1Time != nil || dose2Time != nil || dose2Skipped || !events.isEmpty || morningCheckIn != nil || preSleepLog != nil || healthSummary != nil
    }

    var dataCompletenessScore: Double {
        var score = 0.0
        if dose1Time != nil && (dose2Time != nil || dose2Skipped) { score += 0.25 }
        if healthSummary != nil { score += 0.25 }
        if morningCheckIn != nil { score += 0.25 }
        if preSleepLog != nil { score += 0.25 }
        return score
    }

    var qualityFlags: [String] {
        var flags: [String] = []
        if duplicateClusterCount > 0 {
            flags.append("Duplicate event cluster")
        }
        if dose1Time != nil && dose2Time == nil && !dose2Skipped {
            flags.append("Dose 2 outcome missing")
        }
        if healthSummary == nil {
            flags.append("No HealthKit sleep summary")
        }
        if morningCheckIn == nil {
            flags.append("No morning check-in")
        }
        return flags
    }
}

private struct DashboardIntegrationState: Identifiable {
    let id: String
    let name: String
    let status: String
    let detail: String
    let color: Color
}

private struct DashboardMetricCategory: Identifiable {
    let id: String
    let title: String
    let metrics: [String]
}

@MainActor
private final class DashboardAnalyticsModel: ObservableObject {
    @Published var nights: [DashboardNightAggregate] = []
    @Published var integrationStates: [DashboardIntegrationState] = []
    @Published var isLoading = false
    @Published var lastRefresh: Date?
    @Published var errorMessage: String?

    private let sessionRepo = SessionRepository.shared
    private let settings = UserSettingsManager.shared
    private let healthKit = HealthKitService.shared
    private let whoop = WHOOPService.shared
    private let cloudSync = CloudKitSyncService.shared

    var populatedNights: [DashboardNightAggregate] {
        nights.filter(\.hasAnyData)
    }

    var trendNights: [DashboardNightAggregate] {
        Array(populatedNights.prefix(14))
    }

    var onTimePercentage: Double? {
        let values = populatedNights.compactMap(\.onTimeDosing)
        guard !values.isEmpty else { return nil }
        let onTime = values.filter { $0 }.count
        return (Double(onTime) / Double(values.count)) * 100
    }

    var averageIntervalMinutes: Double? {
        let intervals = populatedNights.compactMap(\.intervalMinutes)
        guard !intervals.isEmpty else { return nil }
        return Double(intervals.reduce(0, +)) / Double(intervals.count)
    }

    var completionRate: Double? {
        let eligible = populatedNights.filter { $0.dose1Time != nil }
        guard !eligible.isEmpty else { return nil }
        let completed = eligible.filter { $0.dose2Time != nil || $0.dose2Skipped }.count
        return (Double(completed) / Double(eligible.count)) * 100
    }

    var averageSnoozeCount: Double? {
        guard !populatedNights.isEmpty else { return nil }
        let total = populatedNights.reduce(0) { $0 + $1.snoozeCount }
        return Double(total) / Double(populatedNights.count)
    }

    var averageSleepMinutes: Double? {
        let values = populatedNights.compactMap(\.totalSleepMinutes)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageTTFW: Double? {
        let values = populatedNights.compactMap(\.ttfwMinutes)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageWakeCount: Double? {
        let values = populatedNights.compactMap(\.wakeCount).map(Double.init)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var averageBathroomWakeMinutes: Double? {
        let nightsWithBathroom = populatedNights.filter { $0.bathroomEventCount > 0 }
        guard !nightsWithBathroom.isEmpty else { return nil }
        let estimatedMinutes = nightsWithBathroom.reduce(0) { $0 + ($1.bathroomEventCount * 5) }
        return Double(estimatedMinutes) / Double(nightsWithBathroom.count)
    }

    var duplicateNightCount: Int {
        populatedNights.filter { $0.duplicateClusterCount > 0 }.count
    }

    var missingHealthSummaryCount: Int {
        populatedNights.filter { $0.healthSummary == nil }.count
    }

    var highConfidenceNightCount: Int {
        populatedNights.filter { $0.dataCompletenessScore >= 0.75 }.count
    }

    var qualityIssueCount: Int {
        populatedNights.reduce(0) { $0 + $1.qualityFlags.count }
    }

    let metricsCatalog: [DashboardMetricCategory] = [
        DashboardMetricCategory(
            id: "dosing",
            title: "Dosing & Timing",
            metrics: [
                "Dose 1 timestamp",
                "Dose 2 timestamp",
                "Dose 2 skipped status",
                "Inter-dose interval (minutes)",
                "On-time dosing (150-240m window)",
                "Snooze count",
                "Extra dose count"
            ]
        ),
        DashboardMetricCategory(
            id: "sleep",
            title: "Sleep (HealthKit + Manual)",
            metrics: [
                "Total sleep minutes",
                "Time to first wake (TTFW)",
                "Wake count (HealthKit)",
                "Sleep source",
                "Bathroom wake count",
                "Lights Out and Wake Up events",
                "Nap count and duration"
            ]
        ),
        DashboardMetricCategory(
            id: "checkins",
            title: "Check-Ins & Symptoms",
            metrics: [
                "Morning check-in completion",
                "Sleep quality and restedness",
                "Grogginess and sleep inertia",
                "Dream recall",
                "Physical and respiratory symptom flags",
                "Mood, anxiety, readiness",
                "Sleep therapy and environment flags"
            ]
        ),
        DashboardMetricCategory(
            id: "quality",
            title: "Data Quality & Reliability",
            metrics: [
                "Duplicate event cluster count",
                "Completeness score (0.0-1.0)",
                "Missing Dose 2 outcome",
                "Missing HealthKit summary",
                "Missing morning check-in",
                "Integration authorization state"
            ]
        )
    ]

    func refresh(days: Int = 90) async {
        isLoading = true
        errorMessage = nil

        let sessions = sessionRepo.fetchRecentSessions(days: days)
        var sessionByKey: [String: SessionSummary] = [:]
        for session in sessions {
            sessionByKey[session.sessionDate] = session
        }

        var healthByKey: [String: HealthKitService.SleepNightSummary] = [:]
        if settings.healthKitEnabled {
            healthKit.checkAuthorizationStatus()
            if healthKit.isAuthorized {
                await healthKit.computeTTFWBaseline(days: max(14, min(days, 120)))
                for summary in healthKit.sleepHistory {
                    let key = sessionRepo.sessionDateString(for: eveningAnchorDate(for: summary.date))
                    if healthByKey[key] == nil {
                        healthByKey[key] = summary
                    }
                }
            } else if let lastError = healthKit.lastError, !lastError.isEmpty {
                errorMessage = lastError
            }
        }

        let calendar = Calendar.current
        let sessionKeys: [String] = (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return sessionRepo.sessionDateString(for: eveningAnchorDate(for: date))
        }

        let aggregates: [DashboardNightAggregate] = sessionKeys.map { key in
            let summary = sessionByKey[key] ?? SessionSummary(sessionDate: key)
            let doseLog = sessionRepo.fetchDoseLog(forSession: key)
            let doseEvents = sessionRepo.fetchDoseEvents(forSessionDate: key)
            let extraDoseCount = doseEvents.filter {
                $0.eventType.lowercased().contains("extra")
            }.count
            let events = sessionRepo.fetchSleepEvents(for: key).sorted { $0.timestamp < $1.timestamp }
            let duplicateClusters = buildStoredEventDuplicateGroups(events: events).count
            let sessionId = sessionRepo.fetchSessionId(forSessionDate: key) ?? key

            return DashboardNightAggregate(
                sessionDate: key,
                dose1Time: summary.dose1Time ?? doseLog?.dose1Time,
                dose2Time: summary.dose2Time ?? doseLog?.dose2Time,
                dose2Skipped: summary.dose2Skipped || doseLog?.dose2Skipped == true,
                snoozeCount: summary.snoozeCount,
                extraDoseCount: extraDoseCount,
                events: events,
                morningCheckIn: sessionRepo.fetchMorningCheckIn(for: key),
                preSleepLog: sessionRepo.fetchMostRecentPreSleepLog(sessionId: sessionId),
                healthSummary: healthByKey[key],
                duplicateClusterCount: duplicateClusters,
                napSummary: sessionRepo.napSummary(for: key)
            )
        }

        nights = aggregates.sorted { $0.sessionDate > $1.sessionDate }
        integrationStates = buildIntegrationStates(healthMatches: healthByKey.count)
        lastRefresh = Date()
        isLoading = false
    }

    private func buildIntegrationStates(healthMatches: Int) -> [DashboardIntegrationState] {
        let healthState = DashboardIntegrationState(
            id: "healthkit",
            name: "Apple HealthKit",
            status: settings.healthKitEnabled
                ? (healthKit.isAuthorized ? "Connected" : "Needs Authorization")
                : "Disabled",
            detail: settings.healthKitEnabled
                ? (healthKit.isAuthorized
                    ? "\(healthMatches) nights with sleep summaries mapped"
                    : (healthKit.lastError ?? "Enable read access for sleep analysis"))
                : "Enable in Settings to ingest sleep stages automatically.",
            color: settings.healthKitEnabled ? (healthKit.isAuthorized ? .green : .orange) : .gray
        )

        let whoopState = DashboardIntegrationState(
            id: "whoop",
            name: "WHOOP",
            status: settings.whoopEnabled
                ? (whoop.isConnected ? "Connected" : "Not Connected")
                : "Disabled",
            detail: settings.whoopEnabled
                ? (whoop.isConnected
                    ? "OAuth active\(whoop.lastSyncTime.map { " • Last sync \($0.formatted(date: .omitted, time: .shortened))" } ?? "")"
                    : "Connect in Settings to ingest recovery/strain metrics.")
                : "Turn on WHOOP integration in Settings when ready.",
            color: settings.whoopEnabled ? (whoop.isConnected ? .green : .orange) : .gray
        )

        let cloudState = DashboardIntegrationState(
            id: "cloud",
            name: "Cloud Sync",
            status: cloudSync.cloudSyncAvailableInBuild
                ? (cloudSync.lastSyncDate == nil ? "Not Synced" : "Active")
                : "Disabled",
            detail: cloudSync.cloudSyncAvailableInBuild
                ? (cloudSync.lastSyncDate == nil
                    ? cloudSync.statusMessage
                    : "Last sync \(cloudSync.lastSyncDate?.formatted(date: .omitted, time: .shortened) ?? "") • \(cloudSync.statusMessage)")
                : "Cloud sync requires iCloud entitlements and a paid Apple Developer team profile.",
            color: cloudSync.cloudSyncAvailableInBuild
                ? (cloudSync.lastSyncDate == nil ? .orange : .green)
                : .gray
        )

        let exportState = DashboardIntegrationState(
            id: "export",
            name: "Share & Export",
            status: "Ready",
            detail: "Timeline review snapshot sharing is active (theme-aware export).",
            color: .teal
        )

        return [healthState, whoopState, cloudState, exportState]
    }
}

@MainActor
private final class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var statusMessage: String = "Not synced yet"

    private let sessionRepo = SessionRepository.shared
    private let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    #if canImport(CloudKit)
    private let container = CKContainer.default()
    private lazy var db = container.privateCloudDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "DoseTapZone", ownerName: CKCurrentUserDefaultName)
    private let zoneChangeTokenDefaultsKey = "cloudkit.zone.token.dosetap.v1"
    private let sessionRecordType = "DoseTapSession"
    private let sleepEventRecordType = "DoseTapSleepEvent"
    private let doseEventRecordType = "DoseTapDoseEvent"
    private let morningCheckInRecordType = "DoseTapMorningCheckIn"

    private struct ZoneDeletedRecord {
        let recordID: CKRecord.ID
        let recordType: String?
    }

    private struct ZoneChangeBatch {
        let changedRecords: [CKRecord]
        let deletedRecords: [ZoneDeletedRecord]
        let newToken: CKServerChangeToken?
    }

    private lazy var hasCloudKitEntitlement: Bool = {
        // iOS does not provide a public entitlements API here.
        // Prefer explicit config if present; otherwise allow runtime account checks
        // to decide availability.
        if let flag = Bundle.main.object(forInfoDictionaryKey: "DoseTapCloudSyncEnabled") {
            if let boolValue = flag as? Bool {
                return boolValue
            }
            if let numberValue = flag as? NSNumber {
                return numberValue.boolValue
            }
            if let stringValue = flag as? String {
                return ["1", "true", "yes"].contains(stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
        }
        return true
    }()
    #endif

    enum SyncError: LocalizedError {
        case cloudKitUnavailable
        case accountNotAvailable
        case zoneSetupFailed
        case syncDisabledByBuild

        var errorDescription: String? {
            switch self {
            case .cloudKitUnavailable:
                return "CloudKit is unavailable on this platform build."
            case .accountNotAvailable:
                return "iCloud account is not available for private database sync."
            case .zoneSetupFailed:
                return "Could not initialize CloudKit zone."
            case .syncDisabledByBuild:
                return "Cloud sync is disabled for this build."
            }
        }
    }

    var cloudSyncAvailableInBuild: Bool {
        #if canImport(CloudKit)
        return hasCloudKitEntitlement
        #else
        return false
        #endif
    }

    func syncNow(days: Int = 120) async throws {
        guard days > 0 else { return }
        isSyncing = true
        defer { isSyncing = false }

        #if canImport(CloudKit)
        guard hasCloudKitEntitlement else {
            statusMessage = "Cloud sync unavailable in this build (missing iCloud entitlement)."
            throw SyncError.syncDisabledByBuild
        }

        statusMessage = "Checking iCloud account…"
        let accountStatus = try await fetchAccountStatus()
        guard accountStatus == .available else {
            throw SyncError.accountNotAvailable
        }

        statusMessage = "Preparing CloudKit zone…"
        try await ensureZoneExists()

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let cutoffKey = sessionDateFormatter.string(from: cutoffDate)

        statusMessage = "Uploading local records…"
        let uploadRecords = buildUploadRecords(cutoffKey: cutoffKey)
        try await saveRecordsInChunks(uploadRecords, chunkSize: 200)

        statusMessage = "Uploading deletions…"
        let tombstones = sessionRepo.fetchCloudKitTombstones(limit: 5000)
        let clearedTombstoneKeys = try await applyCloudKitDeletesInChunks(tombstones, chunkSize: 200)
        if !clearedTombstoneKeys.isEmpty {
            sessionRepo.clearCloudKitTombstones(keys: Array(clearedTombstoneKeys))
        }

        statusMessage = "Downloading incremental changes…"
        let previousToken = loadServerChangeToken()
        let changes = try await fetchZoneChangesWithRecovery(previousToken: previousToken)

        applyChangedRecords(changes.changedRecords)
        applyDeletedRecords(changes.deletedRecords)
        sessionRepo.finalizeSyncImport()
        saveServerChangeToken(changes.newToken)

        lastSyncDate = Date()
        statusMessage = "Sync complete (\(uploadRecords.count) up, \(clearedTombstoneKeys.count) outbound deletes, \(changes.changedRecords.count) changed, \(changes.deletedRecords.count) inbound deletes)"
        #else
        throw SyncError.cloudKitUnavailable
        #endif
    }

    #if canImport(CloudKit)
    private func buildUploadRecords(cutoffKey: String) -> [CKRecord] {
        let keys = sessionRepo
            .allSessionDatesForSync()
            .filter { $0 >= cutoffKey }

        var records: [CKRecord] = []
        for sessionDate in keys {
            let sessionId = sessionRepo.fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
            let doseLog = sessionRepo.fetchDoseLog(forSession: sessionDate)
            let sleepEvents = sessionRepo.fetchSleepEvents(for: sessionDate)
            let doseEvents = sessionRepo.fetchDoseEvents(forSessionDate: sessionDate)
            let morningCheckIn = sessionRepo.fetchMorningCheckIn(for: sessionDate)

            if doseLog != nil || !sleepEvents.isEmpty || !doseEvents.isEmpty || morningCheckIn != nil {
                records.append(sessionRecord(
                    sessionDate: sessionDate,
                    sessionId: sessionId,
                    doseLog: doseLog,
                    sleepEvents: sleepEvents.count,
                    doseEvents: doseEvents.count,
                    hasMorningCheckIn: morningCheckIn != nil
                ))
            }

            for event in sleepEvents {
                records.append(sleepEventRecord(event: event, sessionId: sessionId))
            }

            for event in doseEvents {
                records.append(doseEventRecord(event: event, sessionId: sessionId))
            }

            if let checkIn = morningCheckIn {
                records.append(morningCheckInRecord(checkIn: checkIn))
            }
        }
        return records
    }

    private func sessionRecord(
        sessionDate: String,
        sessionId: String,
        doseLog: StoredDoseLog?,
        sleepEvents: Int,
        doseEvents: Int,
        hasMorningCheckIn: Bool
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: sessionDate, zoneID: zoneID)
        let record = CKRecord(recordType: sessionRecordType, recordID: recordID)
        record["sessionDate"] = sessionDate as CKRecordValue
        record["sessionId"] = sessionId as CKRecordValue
        record["dose1At"] = doseLog?.dose1Time as CKRecordValue?
        record["dose2At"] = doseLog?.dose2Time as CKRecordValue?
        record["dose2Skipped"] = (doseLog?.dose2Skipped ?? false) as CKRecordValue
        record["snoozeCount"] = (doseLog?.snoozeCount ?? 0) as CKRecordValue
        record["sleepEventCount"] = sleepEvents as CKRecordValue
        record["doseEventCount"] = doseEvents as CKRecordValue
        record["hasMorningCheckIn"] = hasMorningCheckIn as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        return record
    }

    private func sleepEventRecord(event: StoredSleepEvent, sessionId: String) -> CKRecord {
        let recordID = CKRecord.ID(recordName: event.id, zoneID: zoneID)
        let record = CKRecord(recordType: sleepEventRecordType, recordID: recordID)
        record["eventType"] = event.eventType as CKRecordValue
        record["timestamp"] = event.timestamp as CKRecordValue
        record["sessionDate"] = event.sessionDate as CKRecordValue
        record["sessionId"] = sessionId as CKRecordValue
        record["colorHex"] = event.colorHex as CKRecordValue?
        record["notes"] = event.notes as CKRecordValue?
        record["updatedAt"] = Date() as CKRecordValue
        return record
    }

    private func doseEventRecord(event: DoseCore.StoredDoseEvent, sessionId: String) -> CKRecord {
        let recordID = CKRecord.ID(recordName: event.id, zoneID: zoneID)
        let record = CKRecord(recordType: doseEventRecordType, recordID: recordID)
        record["eventType"] = event.eventType as CKRecordValue
        record["timestamp"] = event.timestamp as CKRecordValue
        record["sessionDate"] = event.sessionDate as CKRecordValue
        record["sessionId"] = sessionId as CKRecordValue
        record["metadata"] = event.metadata as CKRecordValue?
        record["updatedAt"] = Date() as CKRecordValue
        return record
    }

    private func morningCheckInRecord(checkIn: StoredMorningCheckIn) -> CKRecord {
        let recordID = CKRecord.ID(recordName: checkIn.id, zoneID: zoneID)
        let record = CKRecord(recordType: morningCheckInRecordType, recordID: recordID)
        record["sessionId"] = checkIn.sessionId as CKRecordValue
        record["sessionDate"] = checkIn.sessionDate as CKRecordValue
        record["timestamp"] = checkIn.timestamp as CKRecordValue
        record["sleepQuality"] = checkIn.sleepQuality as CKRecordValue
        record["feelRested"] = checkIn.feelRested as CKRecordValue
        record["grogginess"] = checkIn.grogginess as CKRecordValue
        record["sleepInertiaDuration"] = checkIn.sleepInertiaDuration as CKRecordValue
        record["dreamRecall"] = checkIn.dreamRecall as CKRecordValue
        record["hasPhysicalSymptoms"] = checkIn.hasPhysicalSymptoms as CKRecordValue
        record["physicalSymptomsJson"] = checkIn.physicalSymptomsJson as CKRecordValue?
        record["hasRespiratorySymptoms"] = checkIn.hasRespiratorySymptoms as CKRecordValue
        record["respiratorySymptomsJson"] = checkIn.respiratorySymptomsJson as CKRecordValue?
        record["mentalClarity"] = checkIn.mentalClarity as CKRecordValue
        record["mood"] = checkIn.mood as CKRecordValue
        record["anxietyLevel"] = checkIn.anxietyLevel as CKRecordValue
        record["readinessForDay"] = checkIn.readinessForDay as CKRecordValue
        record["hadSleepParalysis"] = checkIn.hadSleepParalysis as CKRecordValue
        record["hadHallucinations"] = checkIn.hadHallucinations as CKRecordValue
        record["hadAutomaticBehavior"] = checkIn.hadAutomaticBehavior as CKRecordValue
        record["fellOutOfBed"] = checkIn.fellOutOfBed as CKRecordValue
        record["hadConfusionOnWaking"] = checkIn.hadConfusionOnWaking as CKRecordValue
        record["usedSleepTherapy"] = checkIn.usedSleepTherapy as CKRecordValue
        record["sleepTherapyJson"] = checkIn.sleepTherapyJson as CKRecordValue?
        record["hasSleepEnvironment"] = checkIn.hasSleepEnvironment as CKRecordValue
        record["sleepEnvironmentJson"] = checkIn.sleepEnvironmentJson as CKRecordValue?
        record["notes"] = checkIn.notes as CKRecordValue?
        record["updatedAt"] = Date() as CKRecordValue
        return record
    }

    private func applySleepRecords(_ records: [CKRecord]) {
        for record in records {
            guard
                let eventType = record["eventType"] as? String,
                let timestamp = record["timestamp"] as? Date,
                let sessionDate = record["sessionDate"] as? String
            else {
                continue
            }
            let sessionId = record["sessionId"] as? String
            let colorHex = record["colorHex"] as? String
            let notes = record["notes"] as? String
            sessionRepo.upsertSleepEventFromSync(
                id: record.recordID.recordName,
                eventType: eventType,
                timestamp: timestamp,
                sessionDate: sessionDate,
                sessionId: sessionId,
                colorHex: colorHex,
                notes: notes
            )
        }
    }

    private func applyDoseRecords(_ records: [CKRecord]) {
        for record in records {
            guard
                let eventType = record["eventType"] as? String,
                let timestamp = record["timestamp"] as? Date,
                let sessionDate = record["sessionDate"] as? String
            else {
                continue
            }
            let sessionId = record["sessionId"] as? String
            let metadata = record["metadata"] as? String
            sessionRepo.upsertDoseEventFromSync(
                id: record.recordID.recordName,
                eventType: eventType,
                timestamp: timestamp,
                sessionDate: sessionDate,
                sessionId: sessionId,
                metadata: metadata
            )
        }
    }

    private func applyMorningCheckInRecords(_ records: [CKRecord]) {
        for record in records {
            guard
                let sessionId = record["sessionId"] as? String,
                let sessionDate = record["sessionDate"] as? String,
                let timestamp = record["timestamp"] as? Date
            else {
                continue
            }

            let checkIn = StoredMorningCheckIn(
                id: record.recordID.recordName,
                sessionId: sessionId,
                timestamp: timestamp,
                sessionDate: sessionDate,
                sleepQuality: record["sleepQuality"] as? Int ?? 3,
                feelRested: record["feelRested"] as? String ?? "moderate",
                grogginess: record["grogginess"] as? String ?? "mild",
                sleepInertiaDuration: record["sleepInertiaDuration"] as? String ?? "fiveToFifteen",
                dreamRecall: record["dreamRecall"] as? String ?? "none",
                hasPhysicalSymptoms: record["hasPhysicalSymptoms"] as? Bool ?? false,
                physicalSymptomsJson: record["physicalSymptomsJson"] as? String,
                hasRespiratorySymptoms: record["hasRespiratorySymptoms"] as? Bool ?? false,
                respiratorySymptomsJson: record["respiratorySymptomsJson"] as? String,
                mentalClarity: record["mentalClarity"] as? Int ?? 5,
                mood: record["mood"] as? String ?? "neutral",
                anxietyLevel: record["anxietyLevel"] as? String ?? "none",
                readinessForDay: record["readinessForDay"] as? Int ?? 3,
                hadSleepParalysis: record["hadSleepParalysis"] as? Bool ?? false,
                hadHallucinations: record["hadHallucinations"] as? Bool ?? false,
                hadAutomaticBehavior: record["hadAutomaticBehavior"] as? Bool ?? false,
                fellOutOfBed: record["fellOutOfBed"] as? Bool ?? false,
                hadConfusionOnWaking: record["hadConfusionOnWaking"] as? Bool ?? false,
                usedSleepTherapy: record["usedSleepTherapy"] as? Bool ?? false,
                sleepTherapyJson: record["sleepTherapyJson"] as? String,
                hasSleepEnvironment: record["hasSleepEnvironment"] as? Bool ?? false,
                sleepEnvironmentJson: record["sleepEnvironmentJson"] as? String,
                notes: record["notes"] as? String
            )
            sessionRepo.upsertMorningCheckInFromSync(checkIn)
        }
    }

    private func applyChangedRecords(_ records: [CKRecord]) {
        var sleepRecords: [CKRecord] = []
        var doseRecords: [CKRecord] = []
        var morningRecords: [CKRecord] = []

        for record in records {
            switch record.recordType {
            case sleepEventRecordType:
                sleepRecords.append(record)
            case doseEventRecordType:
                doseRecords.append(record)
            case morningCheckInRecordType:
                morningRecords.append(record)
            default:
                continue
            }
        }

        applySleepRecords(sleepRecords)
        applyDoseRecords(doseRecords)
        applyMorningCheckInRecords(morningRecords)
    }

    private func applyDeletedRecords(_ records: [ZoneDeletedRecord]) {
        guard !records.isEmpty else { return }

        for deleted in records {
            switch deleted.recordType {
            case sessionRecordType:
                let key = deleted.recordID.recordName
                if looksLikeSessionDate(key) {
                    sessionRepo.deleteSessionFromSync(sessionDate: key)
                }
            case sleepEventRecordType:
                sessionRepo.deleteSleepEventFromSync(id: deleted.recordID.recordName)
            case doseEventRecordType:
                sessionRepo.deleteDoseEventFromSync(id: deleted.recordID.recordName)
            case morningCheckInRecordType:
                sessionRepo.deleteMorningCheckInFromSync(id: deleted.recordID.recordName)
            default:
                let key = deleted.recordID.recordName
                if looksLikeSessionDate(key) {
                    sessionRepo.deleteSessionFromSync(sessionDate: key)
                }
            }
        }
    }

    private func fetchAccountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func ensureZoneExists() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        try await withCheckedThrowingContinuation { continuation in
            let op = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            op.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    print("⚠️ CloudKit zone ensure failed: \(error.localizedDescription)")
                    continuation.resume(throwing: SyncError.zoneSetupFailed)
                }
            }
            db.add(op)
        }
    }

    private func saveRecordsInChunks(_ records: [CKRecord], chunkSize: Int) async throws {
        guard !records.isEmpty else { return }
        var index = 0
        while index < records.count {
            let end = min(index + chunkSize, records.count)
            let chunk = Array(records[index..<end])
            try await withCheckedThrowingContinuation { continuation in
                let op = CKModifyRecordsOperation(recordsToSave: chunk, recordIDsToDelete: nil)
                op.savePolicy = .changedKeys
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: ())
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                db.add(op)
            }
            index = end
        }
    }

    private func applyCloudKitDeletesInChunks(_ tombstones: [CloudKitTombstone], chunkSize: Int) async throws -> Set<String> {
        guard !tombstones.isEmpty else { return [] }

        var clearedKeys: Set<String> = []
        var index = 0
        while index < tombstones.count {
            let end = min(index + chunkSize, tombstones.count)
            let chunk = Array(tombstones[index..<end])
            let succeeded = try await deleteCloudKitChunk(chunk)
            clearedKeys.formUnion(succeeded)
            index = end
        }

        return clearedKeys
    }

    private func deleteCloudKitChunk(_ chunk: [CloudKitTombstone]) async throws -> Set<String> {
        guard !chunk.isEmpty else { return [] }

        let ids = chunk.map { CKRecord.ID(recordName: $0.recordName, zoneID: zoneID) }
        var keyByRecordID: [CKRecord.ID: String] = [:]
        for tombstone in chunk {
            let recordID = CKRecord.ID(recordName: tombstone.recordName, zoneID: zoneID)
            keyByRecordID[recordID] = tombstone.key
        }

        return try await withCheckedThrowingContinuation { continuation in
            let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: Set(chunk.map(\.key)))
                case .failure(let error):
                    if let ckError = error as? CKError {
                        if ckError.code == .unknownItem {
                            continuation.resume(returning: Set(chunk.map(\.key)))
                            return
                        }

                        if ckError.code == .partialFailure,
                           let partial = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                            var failedKeys: Set<String> = []
                            for (key, itemError) in partial {
                                guard let recordID = key as? CKRecord.ID else { continue }
                                if let itemCKError = itemError as? CKError, itemCKError.code == .unknownItem {
                                    continue
                                }
                                if let tombstoneKey = keyByRecordID[recordID] {
                                    failedKeys.insert(tombstoneKey)
                                }
                            }

                            let allKeys = Set(chunk.map(\.key))
                            let succeeded = allKeys.subtracting(failedKeys)
                            if !succeeded.isEmpty {
                                continuation.resume(returning: succeeded)
                                return
                            }
                        }
                    }
                    continuation.resume(throwing: error)
                }
            }
            db.add(op)
        }
    }

    private func fetchZoneChangesWithRecovery(previousToken: CKServerChangeToken?) async throws -> ZoneChangeBatch {
        do {
            return try await fetchZoneChanges(previousToken: previousToken)
        } catch let ckError as CKError where ckError.code == .changeTokenExpired {
            statusMessage = "Cloud history token expired, refreshing full state…"
            clearServerChangeToken()
            return try await fetchZoneChanges(previousToken: nil)
        }
    }

    private func fetchZoneChanges(previousToken: CKServerChangeToken?) async throws -> ZoneChangeBatch {
        try await withCheckedThrowingContinuation { continuation in
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = previousToken

            let op = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )

            let lock = NSLock()
            var changedRecords: [CKRecord] = []
            var deletedRecords: [ZoneDeletedRecord] = []
            var newestToken: CKServerChangeToken? = previousToken

            op.recordWasChangedBlock = { _, result in
                if case let .success(record) = result {
                    lock.lock()
                    changedRecords.append(record)
                    lock.unlock()
                }
            }

            op.recordWithIDWasDeletedBlock = { recordID, recordType in
                lock.lock()
                deletedRecords.append(ZoneDeletedRecord(recordID: recordID, recordType: recordType))
                lock.unlock()
            }

            op.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
                guard let token else { return }
                lock.lock()
                newestToken = token
                lock.unlock()
            }

            op.recordZoneFetchResultBlock = { _, result in
                if case let .success(zoneResult) = result {
                    let token = zoneResult.serverChangeToken
                    lock.lock()
                    newestToken = token
                    lock.unlock()
                }
            }

            op.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    lock.lock()
                    let output = ZoneChangeBatch(
                        changedRecords: changedRecords,
                        deletedRecords: deletedRecords,
                        newToken: newestToken
                    )
                    lock.unlock()
                    continuation.resume(returning: output)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            db.add(op)
        }
    }

    private func looksLikeSessionDate(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        return sessionDateFormatter.date(from: value) != nil
    }

    private func loadServerChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: zoneChangeTokenDefaultsKey) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveServerChangeToken(_ token: CKServerChangeToken?) {
        guard let token else {
            clearServerChangeToken()
            return
        }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: zoneChangeTokenDefaultsKey)
        }
    }

    private func clearServerChangeToken() {
        UserDefaults.standard.removeObject(forKey: zoneChangeTokenDefaultsKey)
    }
    #endif
}

struct DashboardTabView: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var model = DashboardAnalyticsModel()
    @StateObject private var cloudSync = CloudKitSyncService.shared
    @State private var resolvingDuplicateGroup: StoredEventDuplicateGroup?
    @State private var cloudSyncError: String?

    private var isWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || horizontalSizeClass == .regular
    }

    private var columns: [GridItem] {
        isWideLayout
            ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible())]
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    DashboardExecutiveSummaryCard(model: model, core: core)
                        .gridCellColumns(columns.count)

                    DashboardDosingSnapshotCard(model: model)
                    DashboardSleepSnapshotCard(model: model)
                    DashboardDataQualityCard(model: model)
                    DashboardIntegrationsCard(states: model.integrationStates)

                    DashboardTrendChartsCard(model: model)
                        .gridCellColumns(columns.count)

                    DashboardRecentNightsCard(
                        nights: model.trendNights,
                        onResolveDuplicateGroup: { group in
                            resolvingDuplicateGroup = group
                        }
                    )
                        .gridCellColumns(columns.count)

                    DashboardCapturedMetricsCard(categories: model.metricsCatalog)
                        .gridCellColumns(columns.count)
                }
                .padding()
                .padding(.bottom, 90)
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if cloudSync.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task {
                                do {
                                    try await cloudSync.syncNow(days: 120)
                                    await model.refresh()
                                } catch {
                                    cloudSyncError = error.localizedDescription
                                }
                            }
                        } label: {
                            Image(systemName: "icloud.and.arrow.up")
                        }
                        .accessibilityLabel("Sync with iCloud")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh dashboard")
                    }
                }
            }
            .overlay {
                if model.isLoading && model.nights.isEmpty {
                    ProgressView("Building dashboard…")
                }
            }
            .task {
                await model.refresh()
            }
            .onReceive(sessionRepo.sessionDidChange) { _ in
                Task { await model.refresh() }
            }
            .sheet(item: $resolvingDuplicateGroup) { group in
                DuplicateResolutionSheet(
                    group: group,
                    onKeepEvent: { keep in
                        for event in group.events where event.id != keep.id {
                            sessionRepo.deleteSleepEvent(id: event.id)
                        }
                        Task { await model.refresh() }
                    },
                    onDeleteEvent: { event in
                        sessionRepo.deleteSleepEvent(id: event.id)
                        Task { await model.refresh() }
                    },
                    onMergeGroup: {
                        if let canonical = group.events.sorted(by: { $0.timestamp < $1.timestamp }).first {
                            for event in group.events where event.id != canonical.id {
                                sessionRepo.deleteSleepEvent(id: event.id)
                            }
                            Task { await model.refresh() }
                        }
                    }
                )
            }
            .alert("Cloud Sync", isPresented: Binding(
                get: { cloudSyncError != nil },
                set: { if !$0 { cloudSyncError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cloudSyncError ?? "Unknown cloud sync error")
            }
        }
    }
}

private struct DashboardExecutiveSummaryCard: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @ObservedObject var core: DoseTapCore

    private var nextActionText: String {
        switch core.currentStatus {
        case .noDose1:
            return "Tonight: Take Dose 1 to start session tracking."
        case .beforeWindow:
            return "Tonight: Dose 2 window has not opened yet."
        case .active, .nearClose:
            return "Tonight: Dose 2 is active. Keep interval in the 150-240m range."
        case .closed:
            return "Tonight: Dose 2 window closed. Review trend for drift."
        case .completed, .finalizing:
            return "Tonight: Session complete. Use review findings to adjust next night."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Operations Snapshot")
                .font(.headline)
            Text("Nights with any data: \(model.populatedNights.count)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                dashboardKPI(
                    title: "On-Time",
                    value: model.onTimePercentage.map { String(format: "%.0f%%", $0) } ?? "No data",
                    color: .green
                )
                dashboardKPI(
                    title: "Completion",
                    value: model.completionRate.map { String(format: "%.0f%%", $0) } ?? "No data",
                    color: .blue
                )
                dashboardKPI(
                    title: "High Confidence",
                    value: "\(model.highConfidenceNightCount)",
                    color: .purple
                )
            }

            Text(nextActionText)
                .font(.caption)
                .foregroundColor(.secondary)

            if let lastRefresh = model.lastRefresh {
                Text("Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func dashboardKPI(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct DashboardDosingSnapshotCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dosing Performance")
                .font(.headline)
            metricRow(title: "Avg Interval", value: formatInterval(minutes: model.averageIntervalMinutes))
            metricRow(title: "Avg Snoozes", value: model.averageSnoozeCount.map { String(format: "%.1f", $0) } ?? "No data")
            metricRow(title: "Duplicate Nights", value: "\(model.duplicateNightCount)")
            metricRow(title: "Quality Issues", value: "\(model.qualityIssueCount)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }

    private func formatInterval(minutes: Double?) -> String {
        guard let minutes else { return "No data" }
        return TimeIntervalMath.formatMinutes(Int(minutes.rounded()))
    }
}

private struct DashboardSleepSnapshotCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sleep Outcomes")
                .font(.headline)
            metricRow(title: "Avg Total Sleep", value: formatMinutes(model.averageSleepMinutes))
            metricRow(title: "Avg TTFW", value: formatMinutes(model.averageTTFW))
            metricRow(title: "Avg Wake Count", value: model.averageWakeCount.map { String(format: "%.1f", $0) } ?? "No data")
            metricRow(title: "Avg Bathroom Wake", value: formatMinutes(model.averageBathroomWakeMinutes))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }

    private func formatMinutes(_ value: Double?) -> String {
        guard let value else { return "No data" }
        return TimeIntervalMath.formatMinutes(Int(value.rounded()))
    }
}

private struct DashboardDataQualityCard: View {
    @ObservedObject var model: DashboardAnalyticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data Quality")
                .font(.headline)
            Text("Nights missing HealthKit summary: \(model.missingHealthSummaryCount)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Nights with duplicate event clusters: \(model.duplicateNightCount)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("High confidence nights (>=0.75 completeness): \(model.highConfidenceNightCount)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let error = model.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private struct DashboardIntegrationsCard: View {
    let states: [DashboardIntegrationState]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Integrations")
                .font(.headline)

            if states.isEmpty {
                Text("No integration states available yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(states) { state in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Circle()
                                .fill(state.color)
                                .frame(width: 8, height: 8)
                            Text(state.name)
                                .font(.subheadline.bold())
                            Spacer()
                            Text(state.status)
                                .font(.caption)
                                .foregroundColor(state.color)
                        }
                        Text(state.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private enum DashboardTrendMode: String, CaseIterable, Identifiable {
    case intervalVsSleep = "Interval vs Sleep"
    case cohorts = "Cohorts"
    case weekday = "Weekday"

    var id: String { rawValue }
}

private struct DashboardTrendChartsCard: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @State private var trendMode: DashboardTrendMode = .intervalVsSleep

    private struct IntervalSleepPoint: Identifiable {
        let id = UUID()
        let intervalMinutes: Double
        let sleepMinutes: Double
        let onTime: Bool
    }

    private struct NamedValue: Identifiable {
        let id = UUID()
        let name: String
        let value: Double
    }

    private var intervalSleepPoints: [IntervalSleepPoint] {
        model.populatedNights.compactMap { night in
            guard let interval = night.intervalMinutes, let sleep = night.totalSleepMinutes else { return nil }
            return IntervalSleepPoint(intervalMinutes: Double(interval), sleepMinutes: sleep, onTime: night.onTimeDosing ?? false)
        }
    }

    private var cohortSleepValues: [NamedValue] {
        let withScreens = model.populatedNights.filter {
            guard let screens = $0.preSleepLog?.answers?.screensInBed else { return false }
            return screens != .none && $0.totalSleepMinutes != nil
        }
        let withoutScreens = model.populatedNights.filter {
            guard let screens = $0.preSleepLog?.answers?.screensInBed else { return false }
            return screens == .none && $0.totalSleepMinutes != nil
        }
        let withAvg = averageSleep(for: withScreens)
        let withoutAvg = averageSleep(for: withoutScreens)
        return [
            NamedValue(name: "Screens", value: withAvg),
            NamedValue(name: "No Screens", value: withoutAvg)
        ]
    }

    private var weekdayOnTimeValues: [NamedValue] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let weekdaySymbols = calendar.shortWeekdaySymbols

        var buckets: [Int: [Bool]] = [:]
        for night in model.populatedNights {
            guard let onTime = night.onTimeDosing, let date = formatter.date(from: night.sessionDate) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            buckets[weekday, default: []].append(onTime)
        }

        return (1...7).map { weekday in
            let values = buckets[weekday] ?? []
            let ratio = values.isEmpty ? 0 : (Double(values.filter { $0 }.count) / Double(values.count)) * 100
            return NamedValue(name: weekdaySymbols[weekday - 1], value: ratio)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Interactive Trends")
                    .font(.headline)
                Spacer()
                Picker("Trend", selection: $trendMode) {
                    ForEach(DashboardTrendMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            #if canImport(Charts)
            chartBody
                .frame(height: 220)
            #else
            Text("Charts are unavailable on this platform build.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    #if canImport(Charts)
    @ViewBuilder
    private var chartBody: some View {
        switch trendMode {
        case .intervalVsSleep:
            if intervalSleepPoints.isEmpty {
                emptyChartState("Need nights with both interval and sleep data.")
            } else {
                Chart(intervalSleepPoints) { point in
                    PointMark(
                        x: .value("Interval (min)", point.intervalMinutes),
                        y: .value("Total Sleep (min)", point.sleepMinutes)
                    )
                    .foregroundStyle(point.onTime ? .green : .orange)
                }
                .chartXAxisLabel("Dose Interval")
                .chartYAxisLabel("Sleep Minutes")
            }

        case .cohorts:
            let values = cohortSleepValues
            if values.allSatisfy({ $0.value <= 0 }) {
                emptyChartState("Need pre-sleep screen/no-screen data with sleep totals.")
            } else {
                Chart(values) { entry in
                    BarMark(
                        x: .value("Cohort", entry.name),
                        y: .value("Avg Sleep (min)", entry.value)
                    )
                    .foregroundStyle(entry.name == "No Screens" ? .green : .indigo)
                }
                .chartYAxisLabel("Avg Sleep Minutes")
            }

        case .weekday:
            if weekdayOnTimeValues.allSatisfy({ $0.value == 0 }) {
                emptyChartState("Need completed dose intervals to compute on-time weekdays.")
            } else {
                Chart(weekdayOnTimeValues) { entry in
                    BarMark(
                        x: .value("Weekday", entry.name),
                        y: .value("On-Time %", entry.value)
                    )
                    .foregroundStyle(.blue.gradient)
                }
                .chartYScale(domain: 0...100)
                .chartYAxisLabel("On-Time %")
            }
        }
    }

    private func emptyChartState(_ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title3)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    private func averageSleep(for nights: [DashboardNightAggregate]) -> Double {
        let values = nights.compactMap(\.totalSleepMinutes)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

private struct DashboardRecentNightsCard: View {
    let nights: [DashboardNightAggregate]
    var onResolveDuplicateGroup: (StoredEventDuplicateGroup) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Night Aggregates")
                .font(.headline)

            if nights.isEmpty {
                Text("No nights with dashboard data yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(nights) { night in
                    HStack(spacing: 10) {
                        Text(shortDate(night.sessionDate))
                            .font(.caption.bold())
                            .frame(width: 58, alignment: .leading)

                        Text(intervalText(night))
                            .font(.caption)
                            .foregroundColor(night.onTimeDosing == true ? .green : .secondary)
                            .frame(width: 88, alignment: .leading)

                        Text(sleepText(night))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 84, alignment: .leading)

                        Text("Q \(Int((night.dataCompletenessScore * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundColor(night.dataCompletenessScore >= 0.75 ? .green : .orange)
                            .frame(width: 50, alignment: .leading)

                        Spacer()

                        let duplicates = buildStoredEventDuplicateGroups(events: night.events)
                        if let firstGroup = duplicates.first {
                            Button {
                                onResolveDuplicateGroup(firstGroup)
                            } label: {
                                Label("\(duplicates.count)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Resolve duplicates for \(night.sessionDate)")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }

    private func shortDate(_ sessionDate: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        input.timeZone = .current
        let output = DateFormatter()
        output.dateFormat = "MMM d"
        output.timeZone = .current
        guard let date = input.date(from: sessionDate) else { return sessionDate }
        return output.string(from: date)
    }

    private func intervalText(_ night: DashboardNightAggregate) -> String {
        if night.dose2Skipped {
            return "Skipped"
        }
        if let interval = night.intervalMinutes {
            return TimeIntervalMath.formatMinutes(interval)
        }
        return "No interval"
    }

    private func sleepText(_ night: DashboardNightAggregate) -> String {
        guard let totalSleepMinutes = night.totalSleepMinutes else { return "No sleep data" }
        return TimeIntervalMath.formatMinutes(Int(totalSleepMinutes.rounded()))
    }
}

private struct DashboardCapturedMetricsCard: View {
    let categories: [DashboardMetricCategory]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Captured Metrics Inventory")
                .font(.headline)
            Text("This is the complete metric surface currently modeled for dashboarding.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(categories) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.title)
                        .font(.subheadline.bold())
                    ForEach(category.metrics, id: \.self) { metric in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(metric)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private struct LiveNextActionCard: View {
    @ObservedObject var core: DoseTapCore

    private var headline: String {
        switch core.currentStatus {
        case .noDose1:
            return "Next Action: Take Dose 1"
        case .beforeWindow:
            return "Next Action: Wait for Dose 2 Window"
        case .active, .nearClose:
            return "Next Action: Take Dose 2"
        case .closed:
            return "Dose 2 Window Closed"
        case .completed, .finalizing:
            return "Session Complete"
        }
    }

    private var detail: String {
        guard let dose1 = core.dose1Time else {
            return "Start tonight's session to unlock timeline guidance."
        }
        let windowOpen = dose1.addingTimeInterval(150 * 60)
        let windowClose = dose1.addingTimeInterval(240 * 60)
        switch core.currentStatus {
        case .beforeWindow:
            return "Dose 2 window opens at \(windowOpen.formatted(date: .omitted, time: .shortened))."
        case .active, .nearClose:
            return "Sleep window: \(windowOpen.formatted(date: .omitted, time: .shortened)) - \(windowClose.formatted(date: .omitted, time: .shortened))."
        case .closed:
            return "Window closed at \(windowClose.formatted(date: .omitted, time: .shortened))."
        case .completed, .finalizing:
            return "Review last night for tonight's adjustments."
        case .noDose1:
            return "Take Dose 1 when you're ready to begin."
        }
    }

    private var accent: Color {
        switch core.currentStatus {
        case .active: return .green
        case .nearClose: return .orange
        case .closed: return .red
        case .completed, .finalizing: return .blue
        default: return .indigo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline)
                .font(.headline)
                .foregroundColor(accent)
            Text(detail)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(accent.opacity(0.12))
        )
    }
}

private struct LiveTimelineItem: Identifiable {
    let id: String
    let title: String
    let time: Date
    let color: Color
    let isUpcoming: Bool
}

private struct TonightTimelineProgressCard: View {
    @ObservedObject var core: DoseTapCore
    let events: [LoggedEvent]

    private var items: [LiveTimelineItem] {
        var markers: [LiveTimelineItem] = []

        if let dose1 = core.dose1Time {
            markers.append(LiveTimelineItem(
                id: "dose1",
                title: "Dose 1",
                time: dose1,
                color: .blue,
                isUpcoming: false
            ))

            let windowOpen = dose1.addingTimeInterval(150 * 60)
            let windowClose = dose1.addingTimeInterval(240 * 60)
            markers.append(LiveTimelineItem(
                id: "window_open",
                title: "Window Opens",
                time: windowOpen,
                color: .orange,
                isUpcoming: windowOpen > Date()
            ))
            markers.append(LiveTimelineItem(
                id: "window_close",
                title: "Window Closes",
                time: windowClose,
                color: .red,
                isUpcoming: windowClose > Date()
            ))
        }

        if let dose2 = core.dose2Time {
            markers.append(LiveTimelineItem(
                id: "dose2",
                title: "Dose 2",
                time: dose2,
                color: .green,
                isUpcoming: false
            ))
        }

        for event in events {
            markers.append(LiveTimelineItem(
                id: event.id.uuidString,
                title: EventDisplayName.displayName(for: event.name),
                time: event.time,
                color: event.color,
                isUpcoming: false
            ))
        }

        return markers.sorted(by: { $0.time < $1.time })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tonight Timeline (So Far)")
                .font(.headline)

            if items.isEmpty {
                Text("No timeline events yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(item.color.opacity(item.isUpcoming ? 0.45 : 1))
                            .frame(width: 10, height: 10)
                        Text(item.title)
                            .font(.subheadline)
                        Spacer()
                        Text(item.time.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if item.isUpcoming {
                            Text("Up next")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private struct LiveEventsPreviewCard: View {
    let events: [LoggedEvent]
    let onViewAll: () -> Void

    private var duplicateGroups: [LoggedEventDuplicateGroup] {
        buildLoggedEventDuplicateGroups(events: events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tonight's Events")
                    .font(.headline)
                Spacer()
                Button("View All") {
                    onViewAll()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            if !duplicateGroups.isEmpty {
                ForEach(duplicateGroups) { group in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Possible duplicate: \(group.displayName) (\(group.events.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if events.isEmpty {
                Text("No events logged tonight")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(events.sorted(by: { $0.time > $1.time }).prefix(6)) { event in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(event.color)
                            .frame(width: 10, height: 10)
                        Text(EventDisplayName.displayName(for: event.name))
                            .font(.subheadline)
                        Spacer()
                        Text(event.time.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private struct ReviewHeaderCard: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let nightDate: Date
    let hasMorningCheckIn: Bool

    private var titleText: String {
        let dateText = nightDate.formatted(date: .abbreviated, time: .omitted)
        if Calendar.current.isDateInYesterday(nightDate) {
            return "Last Night - \(dateText)"
        }
        return "Review - \(dateText)"
    }

    private var subtitleText: String {
        let start = session.dose1Time ?? events.first?.timestamp
        let end = events.last?.timestamp ?? session.dose2Time
        let status = hasMorningCheckIn ? "Session complete" : "Session recorded"

        if let start, let end {
            return "\(status) • \(start.formatted(date: .omitted, time: .shortened))-\(end.formatted(date: .omitted, time: .shortened))"
        }
        return status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleText)
                .font(.headline)
            Text(subtitleText)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private struct ReviewStickyHeaderBar: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let nightDate: Date
    let hasMorningCheckIn: Bool
    let canGoToOlderNight: Bool
    let canGoToNewerNight: Bool
    let nightPositionText: String
    let onGoOlder: () -> Void
    let onGoNewer: () -> Void

    private var titleText: String {
        let dateText = nightDate.formatted(date: .abbreviated, time: .omitted)
        if Calendar.current.isDateInYesterday(nightDate) {
            return "Last Night - \(dateText)"
        }
        return "Review - \(dateText)"
    }

    private var subtitleText: String {
        let start = session.dose1Time ?? events.first?.timestamp
        let end = events.last?.timestamp ?? session.dose2Time
        let status = hasMorningCheckIn ? "Session complete" : "Session recorded"
        if let start, let end {
            return "\(status) • \(start.formatted(date: .omitted, time: .shortened))-\(end.formatted(date: .omitted, time: .shortened))"
        }
        if session.dose1Time == nil, session.dose2Time == nil, events.isEmpty {
            return "No data recorded for this night"
        }
        return status
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: onGoOlder) {
                    Image(systemName: "chevron.left")
                        .font(.caption.bold())
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .disabled(!canGoToOlderNight)
                .opacity(canGoToOlderNight ? 1 : 0.35)
                .accessibilityLabel("Older night")

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.bold())
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text((canGoToOlderNight || canGoToNewerNight) ? nightPositionText : "Only night")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))

                Button(action: onGoNewer) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .disabled(!canGoToNewerNight)
                .opacity(canGoToNewerNight ? 1 : 0.35)
                .accessibilityLabel("Newer night")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private struct CoachSummaryCard: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]

    private var doseWindow: (open: Date, close: Date)? {
        guard let dose1 = session.dose1Time else { return nil }
        return (dose1.addingTimeInterval(150 * 60), dose1.addingTimeInterval(240 * 60))
    }

    private var lightsOutTime: Date? {
        events
            .filter { normalizeStoredEventType($0.eventType) == "lights_out" }
            .map(\.timestamp)
            .min()
    }

    private var totalInBedText: String {
        guard
            let lightsOut = lightsOutTime,
            let wake = events
                .filter({ normalizeStoredEventType($0.eventType) == "wake_final" })
                .map(\.timestamp)
                .max()
        else {
            return session.intervalMinutes.map { "Dose interval was \(TimeIntervalMath.formatMinutes($0))." }
                ?? "Session data captured."
        }
        return "Top outcome: \(TimeIntervalMath.formatMinutes(TimeIntervalMath.minutesBetween(start: lightsOut, end: wake))) in bed."
    }

    private var frictionText: String {
        let disruptions = events.filter {
            let normalized = normalizeStoredEventType($0.eventType)
            return normalized == "bathroom" || normalized == "wake_temp" || normalized == "noise" || normalized == "pain"
        }
        if disruptions.isEmpty {
            return "Biggest friction: no major disruptions logged."
        }
        return "Biggest friction: \(disruptions.count) overnight disruptions logged."
    }

    private var actions: [String] {
        var suggestions: [String] = []

        if let window = doseWindow, let lightsOut = lightsOutTime {
            if lightsOut < window.open || lightsOut > window.close {
                suggestions.append("Aim lights-out inside the window (\(window.open.formatted(date: .omitted, time: .shortened))-\(window.close.formatted(date: .omitted, time: .shortened))).")
            }
        }

        if let interval = session.intervalMinutes, !(150...240).contains(interval) {
            suggestions.append("Move Dose 2 toward the 150-240 minute window after Dose 1.")
        }

        let duplicates = buildStoredEventDuplicateGroups(events: events)
        if !duplicates.isEmpty {
            suggestions.append("Resolve duplicate event logs before relying on trend metrics.")
        }

        if suggestions.isEmpty {
            suggestions.append("Keep timing consistent tonight and log only meaningful wake events.")
        }

        return Array(suggestions.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coach Summary")
                .font(.headline)
            Text(totalInBedText)
                .font(.subheadline)
            Text(frictionText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Divider()
            Text("Tonight's focus")
                .font(.subheadline.bold())
            ForEach(actions, id: \.self) { action in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                        .padding(.top, 2)
                    Text(action)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private struct MergedNightTimelineItem: Identifiable {
    let id: String
    let title: String
    let time: Date
    let color: Color
}

private struct MergedNightTimelineCard: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let nightDate: Date
    var showFullViewLink: Bool = true
    var fullViewDestination: AnyView?
    var fullViewLabel: String = "Full view"
    var snapshotTimeline: ReviewSnapshotSleepTimeline?
    var allowLiveTimelineFallback: Bool = true

    private var mergedItems: [MergedNightTimelineItem] {
        var rows: [MergedNightTimelineItem] = []

        if let dose1 = session.dose1Time {
            rows.append(MergedNightTimelineItem(id: "dose1", title: "Dose 1", time: dose1, color: .blue))
            rows.append(MergedNightTimelineItem(id: "window_open", title: "Window Opens", time: dose1.addingTimeInterval(150 * 60), color: .orange))
            rows.append(MergedNightTimelineItem(id: "window_close", title: "Window Closes", time: dose1.addingTimeInterval(240 * 60), color: .red))
        }
        if let dose2 = session.dose2Time {
            rows.append(MergedNightTimelineItem(id: "dose2", title: "Dose 2", time: dose2, color: .green))
        }

        for event in events {
            rows.append(
                MergedNightTimelineItem(
                    id: event.id,
                    title: EventDisplayName.displayName(for: event.eventType),
                    time: event.timestamp,
                    color: Color(hex: event.colorHex ?? "#888888") ?? .gray
                )
            )
        }

        return rows.sorted(by: { $0.time < $1.time })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Night Timeline (Merged)")
                    .font(.headline)
                Spacer()
                if showFullViewLink {
                    NavigationLink(
                        destination: fullViewDestination ?? AnyView(SleepTimelineContainer())
                    ) {
                        Text(fullViewLabel)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            if let snapshotTimeline {
                SleepStageTimeline(
                    stages: snapshotTimeline.stages,
                    events: [],
                    startTime: snapshotTimeline.start,
                    endTime: snapshotTimeline.end
                )
                StageSummaryCard(stages: snapshotTimeline.stages)
            } else if allowLiveTimelineFallback {
                LiveSleepTimelineView(nightDate: nightDate)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Sleep timeline unavailable for this export.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
            }

            if !mergedItems.isEmpty {
                Divider()
                ForEach(mergedItems) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 8, height: 8)
                        Text(item.title)
                            .font(.caption)
                        Spacer()
                        Text(item.time.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private struct TimelineReviewDetailView: View {
    @ObservedObject var core: DoseTapCore
    let initialSessionKey: String
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @State private var reviewSessions: [SessionSummary] = []
    @State private var selectedReviewSessionKey: String?
    @State private var reviewEvents: [StoredSleepEvent] = []
    @State private var reviewNightDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var showPlanForTonight = false

    init(core: DoseTapCore, initialSessionKey: String) {
        self.core = core
        self.initialSessionKey = initialSessionKey
        _selectedReviewSessionKey = State(initialValue: initialSessionKey)
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

    private var reviewNightPositionText: String {
        guard let index = selectedReviewIndex else { return "" }
        return "\(index + 1) of \(reviewSessions.count)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let session = reviewSession {
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
                        showFullViewLink: false
                    )

                    InsightsSummaryCard(title: "Key Metrics", showDefinitions: true)

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
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "moon.zzz")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No completed night to review yet")
                            .font(.subheadline)
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
            .padding()
            .padding(.bottom, 24)
        }
        .navigationTitle("Full Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .onAppear {
            refreshReviewContext()
        }
        .onReceive(sessionRepo.sessionDidChange) { _ in
            refreshReviewContext()
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
        } else if candidates.contains(where: { $0.sessionDate == initialSessionKey }) {
            selectedReviewSessionKey = initialSessionKey
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

    private static let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}

private struct ReviewSnapshotSleepTimeline {
    let stages: [SleepStageBand]
    let start: Date
    let end: Date
}

private struct TimelineReviewShareSnapshotView: View {
    let session: SessionSummary
    let events: [StoredSleepEvent]
    let nightDate: Date
    let hasMorningCheckIn: Bool
    @ObservedObject var core: DoseTapCore
    let snapshotTimeline: ReviewSnapshotSleepTimeline?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DoseTap Timeline Review")
                .font(.headline)
            Text("Generated \(Date().formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.secondary)

            ReviewHeaderCard(
                session: session,
                events: events,
                nightDate: nightDate,
                hasMorningCheckIn: hasMorningCheckIn
            )

            CoachSummaryCard(session: session, events: events)

            MergedNightTimelineCard(
                session: session,
                events: events,
                nightDate: nightDate,
                showFullViewLink: false,
                snapshotTimeline: snapshotTimeline,
                allowLiveTimelineFallback: false
            )

            InsightsSummaryCard(title: "Key Metrics", showDefinitions: true)

            ReviewEventsSnapshotCard(events: events)

            VStack(alignment: .leading, spacing: 10) {
                Text("Plan for Tonight")
                    .font(.headline)
                FullSessionDetails(core: core)
                    .padding(.top, 4)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
        }
        .padding(16)
        .background(Color(.systemBackground))
    }
}

private struct ReviewEventsSnapshotCard: View {
    let events: [StoredSleepEvent]

    private var duplicateGroups: [StoredEventDuplicateGroup] {
        buildStoredEventDuplicateGroups(events: events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Events & Notes")
                .font(.headline)

            if !duplicateGroups.isEmpty {
                ForEach(duplicateGroups) { group in
                    Text("Possible duplicate: \(group.displayName) (\(group.events.count))")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            if events.isEmpty {
                Text("No review events for this night.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(events.sorted(by: { $0.timestamp > $1.timestamp }).prefix(20), id: \.id) { event in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: event.colorHex ?? "#888888") ?? .gray)
                            .frame(width: 8, height: 8)
                        Text(EventDisplayName.displayName(for: event.eventType))
                            .font(.caption)
                        Spacer()
                        Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

private struct ReviewEventsAndNotesCard: View {
    let events: [StoredSleepEvent]
    let onKeepEvent: (StoredSleepEvent, StoredEventDuplicateGroup) -> Void
    let onDeleteEvent: (StoredSleepEvent) -> Void
    let onMergeGroup: (StoredEventDuplicateGroup) -> Void
    @State private var selectedDuplicateGroup: StoredEventDuplicateGroup?

    private var duplicateGroups: [StoredEventDuplicateGroup] {
        buildStoredEventDuplicateGroups(events: events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Events & Notes")
                .font(.headline)

            if !duplicateGroups.isEmpty {
                ForEach(duplicateGroups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Possible duplicate: \(group.displayName) (\(group.events.count))", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Spacer()
                            Button("Resolve") {
                                selectedDuplicateGroup = group
                            }
                            .font(.caption)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.12))
                    )
                }
            }

            if events.isEmpty {
                Text("No review events for this night.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(events.sorted(by: { $0.timestamp > $1.timestamp }), id: \.id) { event in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: event.colorHex ?? "#888888") ?? .gray)
                            .frame(width: 10, height: 10)
                        Text(EventDisplayName.displayName(for: event.eventType))
                            .font(.subheadline)
                        Spacer()
                        Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .sheet(item: $selectedDuplicateGroup) { group in
            DuplicateResolutionSheet(
                group: group,
                onKeepEvent: { event in
                    onKeepEvent(event, group)
                },
                onDeleteEvent: onDeleteEvent,
                onMergeGroup: {
                    onMergeGroup(group)
                }
            )
        }
    }
}

private struct DuplicateResolutionSheet: View {
    let group: StoredEventDuplicateGroup
    let onKeepEvent: (StoredSleepEvent) -> Void
    let onDeleteEvent: (StoredSleepEvent) -> Void
    let onMergeGroup: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var sortedEvents: [StoredSleepEvent] {
        group.events.sorted(by: { $0.timestamp < $1.timestamp })
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Resolve these \(group.events.count) \(group.displayName) logs.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Merge") {
                        onMergeGroup()
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }

                Section("Choose an event") {
                    ForEach(sortedEvents, id: \.id) { event in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline.bold())
                                Spacer()
                                if let notes = event.notes, !notes.isEmpty {
                                    Text("Has notes")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack(spacing: 8) {
                                Button("Keep this") {
                                    onKeepEvent(event)
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Delete") {
                                    onDeleteEvent(event)
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Resolve Duplicates")
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

private struct LoggedEventDuplicateGroup: Identifiable {
    let id: String
    let displayName: String
    let events: [LoggedEvent]
}

private struct StoredEventDuplicateGroup: Identifiable {
    let id: String
    let displayName: String
    let events: [StoredSleepEvent]
}

private func buildLoggedEventDuplicateGroups(events: [LoggedEvent], threshold: TimeInterval = 30 * 60) -> [LoggedEventDuplicateGroup] {
    let grouped = Dictionary(grouping: events.sorted(by: { $0.time < $1.time })) { normalizeLoggedEventName($0.name) }
    var duplicates: [LoggedEventDuplicateGroup] = []

    for (normalizedName, group) in grouped {
        let clusters = clusterEventsByTime(events: group, threshold: threshold)
        for cluster in clusters where cluster.count > 1 {
            duplicates.append(
                LoggedEventDuplicateGroup(
                    id: "\(normalizedName)-\(cluster.first?.id.uuidString ?? UUID().uuidString)",
                    displayName: EventDisplayName.displayName(for: normalizedName),
                    events: cluster
                )
            )
        }
    }
    return duplicates.sorted(by: { ($0.events.first?.time ?? .distantPast) > ($1.events.first?.time ?? .distantPast) })
}

private func buildStoredEventDuplicateGroups(events: [StoredSleepEvent], threshold: TimeInterval = 30 * 60) -> [StoredEventDuplicateGroup] {
    let grouped = Dictionary(grouping: events.sorted(by: { $0.timestamp < $1.timestamp })) { normalizeStoredEventType($0.eventType) }
    var duplicates: [StoredEventDuplicateGroup] = []

    for (normalizedType, group) in grouped {
        let clusters = clusterEventsByTime(events: group, threshold: threshold)
        for cluster in clusters where cluster.count > 1 {
            duplicates.append(
                StoredEventDuplicateGroup(
                    id: "\(normalizedType)-\(cluster.first?.id ?? UUID().uuidString)",
                    displayName: EventDisplayName.displayName(for: normalizedType),
                    events: cluster
                )
            )
        }
    }
    return duplicates.sorted(by: { ($0.events.first?.timestamp ?? .distantPast) > ($1.events.first?.timestamp ?? .distantPast) })
}

private func clusterEventsByTime(events: [LoggedEvent], threshold: TimeInterval) -> [[LoggedEvent]] {
    var clusters: [[LoggedEvent]] = []
    var current: [LoggedEvent] = []

    for event in events.sorted(by: { $0.time < $1.time }) {
        guard let last = current.last else {
            current = [event]
            continue
        }
        if event.time.timeIntervalSince(last.time) <= threshold {
            current.append(event)
        } else {
            clusters.append(current)
            current = [event]
        }
    }

    if !current.isEmpty {
        clusters.append(current)
    }
    return clusters
}

private func clusterEventsByTime(events: [StoredSleepEvent], threshold: TimeInterval) -> [[StoredSleepEvent]] {
    var clusters: [[StoredSleepEvent]] = []
    var current: [StoredSleepEvent] = []

    for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
        guard let last = current.last else {
            current = [event]
            continue
        }
        if event.timestamp.timeIntervalSince(last.timestamp) <= threshold {
            current.append(event)
        } else {
            clusters.append(current)
            current = [event]
        }
    }

    if !current.isEmpty {
        clusters.append(current)
    }
    return clusters
}

private func normalizeLoggedEventName(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: " ", with: "_")
}

private func normalizeStoredEventType(_ raw: String) -> String {
    let normalized = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: " ", with: "_")

    switch normalized {
    case "lightsout", "lights_out":
        return "lights_out"
    case "wakefinal", "wake_final", "wake":
        return "wake_final"
    case "inbed":
        return "in_bed"
    default:
        return normalized
    }
}

private func eveningAnchorDate(for date: Date, hour: Int = 20, timeZone: TimeZone = .current) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var components = calendar.dateComponents([.year, .month, .day], from: date)
    components.hour = hour
    components.minute = 0
    components.second = 0
    return calendar.date(from: components) ?? date
}

// MARK: - History View (Past Days)
struct HistoryView: View {
    @State private var selectedDate = Date()
    @State private var pastSessions: [SessionSummary] = []
    @State private var showDeleteDayConfirmation = false
    @State private var refreshTrigger = false  // Toggled to force SelectedDayView refresh
    
    private let sessionRepo = SessionRepository.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Trends
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trends")
                            .font(.headline)
                        InsightsSummaryCard()
                    }
                    
                    // Date Picker
                    DatePicker(
                        "Select Date",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray6))
                    )
                    
                    // Selected Day Summary with Delete Option
                    SelectedDayView(
                        date: selectedDate,
                        refreshTrigger: refreshTrigger,
                        onDeleteRequested: { showDeleteDayConfirmation = true }
                    )
                    
                    // Recent Sessions List
                    RecentSessionsList()
                }
                .padding()
                .padding(.bottom, 80)
            }
            .navigationTitle("History")
            .onAppear { loadHistory() }
            .alert("Delete This Day's Data?", isPresented: $showDeleteDayConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteSelectedDay()
                }
            } message: {
                Text("This will delete all dose data and events for this day. This cannot be undone.")
            }
        }
    }
    
    private func loadHistory() {
        pastSessions = sessionRepo.fetchRecentSessions(days: 7)
    }
    
    private func deleteSelectedDay() {
        let sessionDate = sessionRepo.sessionDateString(for: eveningAnchorDate(for: selectedDate))
        // Use SessionRepository to delete - this broadcasts change to Tonight tab
        sessionRepo.deleteSession(sessionDate: sessionDate)
        refreshTrigger.toggle()  // Force SelectedDayView to reload
        loadHistory()
    }
}

// MARK: - Selected Day View
struct SelectedDayView: View {
    let date: Date
    var refreshTrigger: Bool = false  // External trigger to force reload
    var onDeleteRequested: (() -> Void)? = nil
    
    @ObservedObject private var settings = UserSettingsManager.shared
    @StateObject private var healthKit = HealthKitService.shared
    @State private var events: [StoredSleepEvent] = []
    @State private var doseLog: StoredDoseLog?
    @State private var doseEvents: [DoseCore.StoredDoseEvent] = []
    @State private var healthSleepRangeText: String?
    @State private var healthSleepStatusText: String?
    @State private var healthSleepSourceText: String?
    @State private var editingDose1 = false
    @State private var editingDose2 = false
    @State private var editingEvent: StoredSleepEvent?
    
    private let sessionRepo = SessionRepository.shared
    
    private var hasData: Bool {
        doseLog != nil || !events.isEmpty
    }

    private struct NapIntervalDisplay: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date?
        let durationMinutes: Int?
    }

    private var napIntervals: [NapIntervalDisplay] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var intervals: [NapIntervalDisplay] = []
        var pendingStart: Date?

        for event in sorted {
            guard let kind = napEventKind(event.eventType) else { continue }
            if kind == "start" {
                pendingStart = event.timestamp
            } else if kind == "end", let start = pendingStart {
                let minutes = TimeIntervalMath.minutesBetween(start: start, end: event.timestamp)
                intervals.append(NapIntervalDisplay(start: start, end: event.timestamp, durationMinutes: minutes))
                pendingStart = nil
            }
        }

        if let start = pendingStart {
            intervals.append(NapIntervalDisplay(start: start, end: nil, durationMinutes: nil))
        }

        return intervals
    }
    
    private var sessionDateString: String {
        sessionRepo.sessionDateString(for: eveningAnchorDate(for: date))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dateTitle)
                    .font(.headline)
                Spacer()
                if hasData {
                    Text("Tap to edit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if hasData, let onDelete = onDeleteRequested {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Apple Health Cross-Check")
                    .font(.subheadline.bold())
                Text("Session key: \(sessionDateString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let healthSleepRangeText {
                    Text("Sleep range: \(healthSleepRangeText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let healthSleepSourceText {
                    Text(healthSleepSourceText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let healthSleepStatusText {
                    Text(healthSleepStatusText)
                        .font(.caption)
                        .foregroundColor(healthSleepStatusText.hasPrefix("Matches") ? .green : .orange)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
            )
            
            if let dose = doseLog {
                // Dose info - now tappable
                VStack(alignment: .leading, spacing: 8) {
                    // Dose 1 Row - Tappable
                    Button {
                        editingDose1 = true
                    } label: {
                        HStack {
                            Image(systemName: "1.circle.fill")
                                .foregroundColor(.green)
                            Text("Dose 1")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(dose.dose1Time.formatted(date: .omitted, time: .shortened))
                                .foregroundColor(.secondary)
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if let d2 = dose.dose2Time {
                        // Dose 2 Row - Tappable
                        Button {
                            editingDose2 = true
                        } label: {
                            HStack {
                                Image(systemName: "2.circle.fill")
                                    .foregroundColor(.green)
                                Text("Dose 2")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(d2.formatted(date: .omitted, time: .shortened))
                                    .foregroundColor(.secondary)
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        let interval = TimeIntervalMath.minutesBetween(start: dose.dose1Time, end: d2)
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.purple)
                            Text("Interval")
                            Spacer()
                            Text(TimeIntervalMath.formatMinutes(interval))
                                .foregroundColor(.secondary)
                        }
                    } else if dose.skipped {
                        HStack {
                            Image(systemName: "2.circle")
                                .foregroundColor(.orange)
                            Text("Dose 2")
                            Spacer()
                            Text("Skipped")
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
            }

            if doseLog != nil {
                DoseIntervalsCard(doseEvents: doseEvents)
            }
            
            // Events for this day - now tappable
            if !events.isEmpty {
                Text("Events (\(events.count))")
                    .font(.subheadline.bold())
                    .padding(.top, 8)
                
                ForEach(events, id: \.id) { event in
                    Button {
                        editingEvent = event
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: event.colorHex ?? "#888888") ?? .gray)
                                .frame(width: 10, height: 10)
                            Text(EventDisplayName.displayName(for: event.eventType))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            } else {
                Text("No events logged")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !napIntervals.isEmpty {
                Text("Naps")
                    .font(.subheadline.bold())
                    .padding(.top, 8)
                ForEach(napIntervals) { nap in
                    HStack(spacing: 10) {
                        Image(systemName: "bed.double.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(napLabel(for: nap))
                                .font(.subheadline)
                            Text(napDetail(for: nap))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .onChange(of: date) { _ in loadData() }
        .onChange(of: refreshTrigger) { _ in loadData() }
        .onAppear { loadData() }
        // Edit Dose 1 Sheet
        .sheet(isPresented: $editingDose1) {
            if let dose = doseLog {
                EditDoseTimeView(
                    doseNumber: 1,
                    originalTime: dose.dose1Time,
                    dose1Time: nil,
                    sessionDate: sessionDateString,
                    onSave: { newTime in
                        saveDose1Time(newTime)
                    }
                )
            }
        }
        // Edit Dose 2 Sheet
        .sheet(isPresented: $editingDose2) {
            if let dose = doseLog, let d2 = dose.dose2Time {
                EditDoseTimeView(
                    doseNumber: 2,
                    originalTime: d2,
                    dose1Time: dose.dose1Time,
                    sessionDate: sessionDateString,
                    onSave: { newTime in
                        saveDose2Time(newTime)
                    }
                )
            }
        }
        // Edit Event Sheet
        .sheet(item: $editingEvent) { event in
            EditEventTimeView(
                event: event,
                sessionDate: sessionDateString,
                onSave: { newTime in
                    saveEventTime(event: event, newTime: newTime)
                }
            )
        }
    }
    
    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: eveningAnchorDate(for: date))
    }
    
    private func loadData() {
        let sessionDate = sessionDateString
        events = sessionRepo.fetchSleepEvents(for: sessionDate)
        doseLog = sessionRepo.fetchDoseLog(forSession: sessionDate)
        doseEvents = sessionRepo.fetchDoseEvents(forSessionDate: sessionDate)
        loadHealthCrossCheck(for: sessionDate)
    }
    
    private func saveDose1Time(_ newTime: Date) {
        sessionRepo.updateDose1Time(newTime: newTime, sessionDate: sessionDateString)
        loadData()
    }
    
    private func saveDose2Time(_ newTime: Date) {
        sessionRepo.updateDose2Time(newTime: newTime, sessionDate: sessionDateString)
        loadData()
    }
    
    private func saveEventTime(event: StoredSleepEvent, newTime: Date) {
        sessionRepo.updateEventTime(eventId: event.id, newTime: newTime)
        loadData()
    }

    private func loadHealthCrossCheck(for sessionDate: String) {
        healthSleepRangeText = nil
        healthSleepSourceText = nil
        healthSleepStatusText = nil

        Task { @MainActor in
            guard settings.healthKitEnabled else {
                healthSleepStatusText = "HealthKit disabled in Settings."
                return
            }

            healthKit.checkAuthorizationStatus()
            guard healthKit.isAuthorized else {
                healthSleepStatusText = "HealthKit not authorized."
                return
            }

            guard let nightDate = Self.sessionDateFormatter.date(from: sessionDate) else {
                healthSleepStatusText = "Unable to parse session date."
                return
            }

            let queryStart = eveningAnchorDate(for: nightDate, hour: 18)
            guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: nightDate) else {
                healthSleepStatusText = "Unable to compute HealthKit query window."
                return
            }
            let queryEnd = eveningAnchorDate(for: nextDay, hour: 12)

            do {
                let segments = try await healthKit.fetchSegmentsForTimeline(from: queryStart, to: queryEnd)
                guard !segments.isEmpty else {
                    healthSleepStatusText = "No Apple Health sleep samples in this night window."
                    return
                }

                let start = segments.map(\.start).min() ?? queryStart
                let end = segments.map(\.end).max() ?? queryEnd

                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                healthSleepRangeText = "\(formatter.string(from: start)) -> \(formatter.string(from: end))"

                let sourceNames = Set(segments.map(\.source)).sorted()
                if !sourceNames.isEmpty {
                    healthSleepSourceText = "Source: \(sourceNames.joined(separator: ", "))"
                }

                let derivedKey = sessionRepo.sessionDateString(for: start)
                healthSleepStatusText = derivedKey == sessionDate
                    ? "Matches: Health sleep start maps to session \(derivedKey)."
                    : "Mismatch: Health sleep start maps to \(derivedKey), session is \(sessionDate)."
            } catch {
                healthSleepStatusText = "HealthKit error: \(error.localizedDescription)"
            }
        }
    }

    private func napEventKind(_ eventType: String) -> String? {
        let normalized = eventType
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        if normalized == "nap start" || compact == "napstart" { return "start" }
        if normalized == "nap end" || compact == "napend" { return "end" }
        return nil
    }

    private func napLabel(for nap: NapIntervalDisplay) -> String {
        if nap.end == nil {
            return "Nap in progress"
        }
        return "Nap"
    }

    private func napDetail(for nap: NapIntervalDisplay) -> String {
        let start = nap.start.formatted(date: .omitted, time: .shortened)
        if let end = nap.end {
            let endStr = end.formatted(date: .omitted, time: .shortened)
            let duration = nap.durationMinutes.map { TimeIntervalMath.formatMinutes($0) } ?? "—"
            return "\(start) -> \(endStr) (\(duration))"
        }
        return "Started at \(start) (no end logged)"
    }

    private static let sessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()
}

// MARK: - Recent Sessions List
struct RecentSessionsList: View {
    @State private var sessions: [SessionSummary] = []
    private let sessionRepo = SessionRepository.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)
            
            if sessions.isEmpty {
                Text("No recent sessions found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(sessions, id: \.sessionDate) { session in
                    SessionRow(session: session)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
        .onAppear { loadSessions() }
    }
    
    private func loadSessions() {
        sessions = sessionRepo.fetchRecentSessions(days: 7)
    }
}

struct SessionRow: View {
    let session: SessionSummary
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.sessionDate)
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    if session.dose1Time != nil {
                        Label("D1", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    if session.dose2Time != nil {
                        Label("D2", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else if session.skipped {
                        Label("Skipped", systemImage: "forward.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    if session.eventCount > 0 {
                        Label("\(session.eventCount)", systemImage: "list.bullet")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
            }
            Spacer()
            if let d1 = session.dose1Time, let d2 = session.dose2Time {
                let interval = TimeIntervalMath.minutesBetween(start: d1, end: d2)
                Text(TimeIntervalMath.formatMinutes(interval))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Full Session Details
struct FullSessionDetails: View {
    @ObservedObject var core: DoseTapCore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Details")
                .font(.headline)
            
            // Dose Times
            VStack(spacing: 12) {
                DetailRow(
                    icon: "1.circle.fill",
                    title: "Dose 1",
                    value: core.dose1Time?.formatted(date: .abbreviated, time: .shortened) ?? "Not taken",
                    color: .blue
                )
                
                DetailRow(
                    icon: "2.circle.fill",
                    title: "Dose 2",
                    value: dose2String,
                    color: .green
                )
                
                if let dose1 = core.dose1Time {
                    DetailRow(
                        icon: "clock.fill",
                        title: "Window Opens",
                        value: dose1.addingTimeInterval(150 * 60).formatted(date: .omitted, time: .shortened),
                        color: .orange
                    )
                    
                    DetailRow(
                        icon: "clock.badge.exclamationmark.fill",
                        title: "Window Closes",
                        value: dose1.addingTimeInterval(240 * 60).formatted(date: .omitted, time: .shortened),
                        color: .red
                    )
                    
                    if let dose2 = core.dose2Time {
                        let interval = TimeIntervalMath.minutesBetween(start: dose1, end: dose2)
                        DetailRow(
                            icon: "timer",
                            title: "Interval",
                            value: TimeIntervalMath.formatMinutes(interval),
                            color: .purple
                        )
                    }
                }
                
                DetailRow(
                    icon: "bell.badge.fill",
                    title: "Snoozes Used",
                    value: "\(core.snoozeCount) of 3",
                    color: .orange
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
    
    private var dose2String: String {
        if let time = core.dose2Time {
            return time.formatted(date: .abbreviated, time: .shortened)
        }
        if core.isSkipped { return "Skipped" }
        return "Pending"
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Full Event Log Grid (4x3)
struct FullEventLogGrid: View {
    let eventTypes: [(name: String, icon: String, color: Color)]
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var settings: UserSettingsManager
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Log Sleep Event")
                    .font(.headline)
                Spacer()
                Text("Tap to log")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(eventTypes, id: \.name) { event in
                    let cooldown = settings.cooldown(for: event.name)
                    EventGridButton(
                        name: event.name,
                        icon: event.icon,
                        color: event.color,
                        cooldownEnd: eventLogger.cooldownEnd(for: event.name),
                        cooldownDuration: cooldown,
                        onTap: {
                            eventLogger.logEvent(name: event.name, color: event.color, cooldownSeconds: cooldown)
                        }
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct EventGridButton: View {
    let name: String
    let icon: String
    let color: Color
    let cooldownEnd: Date?
    let cooldownDuration: TimeInterval
    let onTap: () -> Void
    
    @State private var progress: CGFloat = 1.0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    private var isOnCooldown: Bool {
        guard let end = cooldownEnd else { return false }
        return Date() < end
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(isOnCooldown ? 0.1 : 0.15))
                        .frame(height: 60)
                    
                    if isOnCooldown {
                        RoundedRectangle(cornerRadius: 12)
                            .trim(from: 0, to: progress)
                            .stroke(color.opacity(0.3), lineWidth: 2)
                            .frame(height: 60)
                    }
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(isOnCooldown ? color.opacity(0.4) : color)
                }
                
                Text(name)
                    .font(.caption2)
                    .foregroundColor(isOnCooldown ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .disabled(isOnCooldown)
        .onReceive(timer) { _ in
            guard let end = cooldownEnd else { progress = 1.0; return }
            let remaining = end.timeIntervalSince(Date())
            progress = remaining <= 0 ? 1.0 : 1.0 - CGFloat(remaining / cooldownDuration)
        }
    }
}

// MARK: - Event History Section
struct EventHistorySection: View {
    let events: [LoggedEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Event History")
                    .font(.headline)
                Spacer()
                Text("\(events.count) events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if events.isEmpty {
                Text("No events logged tonight")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(events) { event in
                    HStack {
                        Circle()
                            .fill(event.color)
                            .frame(width: 10, height: 10)
                        Text(event.name)
                            .font(.subheadline)
                        Spacer()
                        Text(event.time, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Supporting Views (from original)

struct StatusCard: View {
    let status: DoseStatus
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: statusIcon)
                    .font(.title2)
                Text(statusTitle)
                    .font(.headline)
            }
            .foregroundColor(statusColor)
            
            Text(statusDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(statusColor.opacity(0.1))
        )
    }
    
    private var statusIcon: String {
        switch status {
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
        switch status {
        case .noDose1: return "Ready for Dose 1"
        case .beforeWindow: return "Waiting for Window"
        case .active: return "Window Open"
        case .nearClose: return "Window Closing Soon"
        case .closed: return "Window Closed"
        case .completed: return "Complete"
        case .finalizing: return "Finalizing Session"
        }
    }
    
    private var statusDescription: String {
        switch status {
        case .noDose1: return "Take Dose 1 to start your session"
        case .beforeWindow: return "Dose 2 window opens in \(TimeIntervalMath.formatMinutes(150))"
        case .active: return "Take Dose 2 now"
        case .nearClose: return "Less than \(TimeIntervalMath.formatMinutes(15)) remaining!"
        case .closed: return "Window closed (\(TimeIntervalMath.formatMinutes(240)) max)"
        case .completed: return "Both doses taken ✓"
        case .finalizing: return "Complete morning check-in"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .noDose1: return .blue
        case .beforeWindow: return .orange
        case .active: return .green
        case .nearClose: return .red
        case .closed: return .gray
        case .completed: return .purple
        case .finalizing: return .yellow
        }
    }
}

struct TimeUntilWindowCard: View {
    let dose1Time: Date
    @State private var timeRemaining: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private let windowOpenMinutes: TimeInterval = 150
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Window Opens In")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(formatTimeRemaining)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
                .monospacedDigit()
            
            Text("Take Dose 2 after \(formatWindowOpenTime)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
        )
        .onAppear { updateTimeRemaining() }
        .onReceive(timer) { _ in updateTimeRemaining() }
    }
    
    private func updateTimeRemaining() {
        let windowOpenTime = dose1Time.addingTimeInterval(windowOpenMinutes * 60)
        timeRemaining = max(0, windowOpenTime.timeIntervalSince(Date()))
    }
    
    private var formatTimeRemaining: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        let seconds = Int(timeRemaining) % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }
    
    private var formatWindowOpenTime: String {
        dose1Time.addingTimeInterval(windowOpenMinutes * 60).formatted(date: .omitted, time: .shortened)
    }
}

struct DoseButtonsSection: View {
    @ObservedObject var core: DoseTapCore
    @Binding var showEarlyDoseAlert: Bool
    @Binding var earlyDoseMinutes: Int
    @State private var showWindowExpiredOverride = false
    
    private let windowOpenMinutes: Double = 150
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: handlePrimaryButtonTap) {
                Text(primaryButtonText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(primaryButtonColor)
                    .cornerRadius(12)
            }
            .disabled(core.currentStatus == .completed)
            .alert("Window Expired", isPresented: $showWindowExpiredOverride) {
                Button("Cancel", role: .cancel) { }
                Button("Take Dose 2 Anyway", role: .destructive) {
                    Task { await core.takeDose(lateOverride: true) }
                }
            } message: {
                Text("The 240-minute window has passed. Taking Dose 2 late may affect efficacy.")
            }
            
            if core.currentStatus == .beforeWindow {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Dose 2 window not yet open")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            
            HStack(spacing: 12) {
                Button("Snooze +10m") {
                    Task { await core.snooze() }
                }
                .buttonStyle(.bordered)
                .disabled(!snoozeEnabled)
                
                Button("Skip Dose") {
                    Task { await core.skipDose() }
                }
                .buttonStyle(.bordered)
                .disabled(!skipEnabled)
            }
        }
    }
    
    private func handlePrimaryButtonTap() {
        guard core.dose1Time != nil else {
            Task { await core.takeDose() }
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

        if core.currentStatus == .closed {
            showWindowExpiredOverride = true
            return
        }
        
        Task { await core.takeDose() }
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
    
    private var primaryButtonColor: Color {
        switch core.currentStatus {
        case .noDose1: return .blue
        case .beforeWindow: return .gray
        case .active: return .green
        case .nearClose: return .orange
        case .closed: return .orange
        case .completed: return .purple
        case .finalizing: return .yellow
        }
    }
    
    private var snoozeEnabled: Bool {
        (core.currentStatus == .active || core.currentStatus == .nearClose) && core.snoozeCount < 3
    }
    
    private var skipEnabled: Bool {
        core.currentStatus == .active || core.currentStatus == .nearClose || core.currentStatus == .closed
    }
}

// MARK: - Early Dose Override Sheet
struct EarlyDoseOverrideSheet: View {
    let minutesRemaining: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var holdProgress: CGFloat = 0
    @State private var isHolding = false
    @State private var holdTimer: Timer?
    
    private let requiredHoldDuration: CGFloat = 3.0
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                
                Text("Override Dose Timing")
                    .font(.title2.bold())
                
                Text("Hold to confirm early dose")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            VStack(alignment: .leading, spacing: 12) {
                WarningRow(icon: "clock.badge.exclamationmark", text: "\(TimeIntervalMath.formatMinutes(minutesRemaining)) early", color: .orange)
                WarningRow(icon: "pills.fill", text: "May reduce effectiveness", color: .red)
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
            
            VStack(spacing: 12) {
                Text("Hold for 3 seconds")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                        .frame(width: 100, height: 100)
                    
                    Circle()
                        .trim(from: 0, to: holdProgress)
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: holdProgress)
                    
                    Image(systemName: isHolding ? "hand.tap.fill" : "hand.tap")
                        .font(.title)
                        .foregroundColor(isHolding ? .red : .gray)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !isHolding { startHolding() } }
                        .onEnded { _ in stopHolding() }
                )
            }
            
            Button("Cancel") { onCancel() }
                .font(.headline)
                .foregroundColor(.blue)
                .padding(.bottom, 30)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    private func startHolding() {
        isHolding = true
        holdProgress = 0
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            holdProgress += 0.05 / requiredHoldDuration
            if holdProgress >= 1.0 {
                holdTimer?.invalidate()
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                onConfirm()
            }
        }
    }
    
    private func stopHolding() {
        isHolding = false
        holdTimer?.invalidate()
        withAnimation(.easeOut(duration: 0.3)) { holdProgress = 0 }
    }
}

struct WarningRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
