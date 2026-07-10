import SwiftUI
import DoseCore
import os.log

// MARK: - Home Presentation State
struct HomePresentationState: Equatable {
    enum Primary: Equatable {
        case previousSessionNeedsReview
        case tonightReady
        case dose2Waiting
        case dose2Ready
        case dose2Closed
        case dose2Skipped
        case morningCloseout
        case reviewOnly
    }

    struct PriorSessionReview: Equatable {
        let sessionDate: String
        let isBlocking: Bool
    }

    let primary: Primary
    let priorSessionReview: PriorSessionReview?

    var isBlockedByPriorSession: Bool {
        primary == .previousSessionNeedsReview
    }

    var showsDoseStatusCard: Bool {
        switch primary {
        case .dose2Waiting, .dose2Ready, .dose2Closed, .dose2Skipped, .morningCloseout:
            return true
        case .previousSessionNeedsReview, .tonightReady, .reviewOnly:
            return false
        }
    }

    var showsDosePrimaryAction: Bool {
        switch primary {
        case .tonightReady, .dose2Waiting, .dose2Ready, .dose2Closed, .dose2Skipped:
            return true
        case .previousSessionNeedsReview, .morningCloseout, .reviewOnly:
            return false
        }
    }

    var showsWakeAction: Bool {
        primary == .morningCloseout || primary == .dose2Skipped
    }

    var showsPreSleepCard: Bool {
        switch primary {
        case .previousSessionNeedsReview, .reviewOnly:
            return false
        case .tonightReady, .dose2Waiting, .dose2Ready, .dose2Closed, .dose2Skipped, .morningCloseout:
            return true
        }
    }

    var showsQuickLog: Bool {
        switch primary {
        case .previousSessionNeedsReview, .reviewOnly:
            return false
        case .tonightReady, .dose2Waiting, .dose2Ready, .dose2Closed, .dose2Skipped, .morningCloseout:
            return true
        }
    }

    var showsSessionSummary: Bool {
        switch primary {
        case .previousSessionNeedsReview, .tonightReady:
            return false
        case .dose2Waiting, .dose2Ready, .dose2Closed, .dose2Skipped, .morningCloseout, .reviewOnly:
            return true
        }
    }

    var showsWeeklyInsights: Bool {
        !isBlockedByPriorSession
    }

    var showsLiveDoseIntervals: Bool {
        switch primary {
        case .dose2Waiting, .dose2Ready, .dose2Closed, .dose2Skipped, .morningCloseout, .reviewOnly:
            return true
        case .previousSessionNeedsReview, .tonightReady:
            return false
        }
    }
}

enum HomeStateResolver {
    static func resolve(
        doseStatus: DoseStatus,
        currentSessionDate: String,
        activeSessionDate: String?,
        incompleteSessionDate: String?,
        awaitingRolloverMessage: String?,
        checkInCompleted: Bool,
        hasMorningCheckIn: Bool,
        dose2Skipped: Bool,
        hasDose2: Bool
    ) -> HomePresentationState {
        let priorReview = incompleteSessionDate.map { sessionDate in
            HomePresentationState.PriorSessionReview(
                sessionDate: sessionDate,
                isBlocking: incompleteSessionBlocksCurrentSession(
                    sessionDate: sessionDate,
                    currentSessionDate: currentSessionDate,
                    activeSessionDate: activeSessionDate,
                    awaitingRolloverMessage: awaitingRolloverMessage
                )
            )
        }

        if let priorReview, priorReview.isBlocking {
            return HomePresentationState(primary: .previousSessionNeedsReview, priorSessionReview: priorReview)
        }

        if checkInCompleted || hasMorningCheckIn {
            return HomePresentationState(primary: .reviewOnly, priorSessionReview: priorReview)
        }

        let primary: HomePresentationState.Primary
        if (doseStatus == .completed || doseStatus == .finalizing), dose2Skipped, !hasDose2 {
            // A skipped Dose 2 is recoverable after explicit confirmation. Keep both
            // the recovery action and morning closeout reachable until check-in ends
            // the session.
            primary = .dose2Skipped
        } else {
            switch doseStatus {
            case .noDose1:
                primary = .tonightReady
            case .beforeWindow:
                primary = .dose2Waiting
            case .active, .nearClose:
                primary = .dose2Ready
            case .closed:
                primary = .dose2Closed
            case .completed, .finalizing:
                primary = .morningCloseout
            }
        }

        return HomePresentationState(primary: primary, priorSessionReview: priorReview)
    }

    private static func incompleteSessionBlocksCurrentSession(
        sessionDate: String,
        currentSessionDate: String,
        activeSessionDate: String?,
        awaitingRolloverMessage: String?
    ) -> Bool {
        if sessionDate == currentSessionDate { return true }
        if sessionDate == activeSessionDate { return true }
        return awaitingRolloverMessage != nil && sessionDate == activeSessionDate
    }
}

// MARK: - Legacy Tonight View
struct LegacyTonightView: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var undoState: UndoStateManager
    @ObservedObject var coordinator: DoseActionCoordinator
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.isInSplitView) private var isInSplitView
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
    @State private var morningCheckIn: StoredMorningCheckIn? = nil

    var body: some View {
        let homeState = resolvedHomeState

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
                .padding(.top, isInSplitView ? 16 : 50) // Safe area offset for page-style TabView (less needed in split view)

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

            if let priorReview = homeState.priorSessionReview {
                IncompleteSessionBanner(
                    sessionDate: priorReview.sessionDate,
                    isBlocking: priorReview.isBlocking,
                    onComplete: {
                        showIncompleteCheckIn = true
                    },
                    onDismiss: {
                        Self.dismissIncompleteSession(priorReview.sessionDate)
                        incompleteSessionDate = nil
                    }
                )
                .padding(.horizontal)
                .padding(.top, 8)
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
            if homeState.showsDoseStatusCard {
                Spacer().frame(height: 12)

                // Combined Status + Timer Card (compact)
                CompactStatusCard(core: core)
            }

            Spacer().frame(height: 12)

            // Pre-Sleep Log Card — always visible during a session so users can
            // log, view, or edit pre-sleep info at any time (before or after Dose 1).
            // Only hidden once the session has fully ended (wake/morning check-in).
            if homeState.showsPreSleepCard && !sessionRepo.checkInCompleted {
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

            // Morning Check-In Card (view/edit completed check-in)
            if let checkIn = morningCheckIn {
                MorningCheckInCompactCard(checkIn: checkIn) {
                    showMorningCheckIn = true
                }
                .padding(.horizontal)

                Spacer().frame(height: 12)
            }

            // Wide layout: dose controls left, events right
            // Compact layout: stacked vertically (default)
            if !homeState.isBlockedByPriorSession, horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    // LEFT: Dose controls + status
                    VStack(spacing: 12) {
                        if homeState.showsDosePrimaryAction {
                            CompactDoseButton(
                                core: core,
                                eventLogger: eventLogger,
                                undoState: undoState,
                                sessionRepo: sessionRepo,
                                showEarlyDoseAlert: $showEarlyDoseAlert,
                                earlyDoseMinutes: $earlyDoseMinutesRemaining,
                                showExtraDoseWarning: $showExtraDoseWarning,
                                showMorningCheckIn: $showMorningCheckIn,
                                coordinator: coordinator
                            )
                        }

                        if homeState.showsWakeAction {
                            WakeUpButton(
                                eventLogger: eventLogger,
                                showMorningCheckIn: $showMorningCheckIn
                            )
                        }

                        if homeState.showsLiveDoseIntervals {
                            LiveDoseIntervalsCard(sessionRepo: sessionRepo)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // RIGHT: Event log + session summary
                    VStack(spacing: 12) {
                        if homeState.showsQuickLog {
                            QuickEventPanel(eventLogger: eventLogger)
                        }

                        if homeState.showsSessionSummary {
                            CompactSessionSummary(core: core, eventLogger: eventLogger)
                        }

                        if homeState.showsWeeklyInsights {
                            WeeklyInsightsCard(sessionRepo: sessionRepo)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
            } else if !homeState.isBlockedByPriorSession {
                if homeState.showsDosePrimaryAction {
                    CompactDoseButton(
                        core: core,
                        eventLogger: eventLogger,
                        undoState: undoState,
                        sessionRepo: sessionRepo,
                        showEarlyDoseAlert: $showEarlyDoseAlert,
                        earlyDoseMinutes: $earlyDoseMinutesRemaining,
                        showExtraDoseWarning: $showExtraDoseWarning,
                        showMorningCheckIn: $showMorningCheckIn,
                        coordinator: coordinator
                    )
                }

                if homeState.showsQuickLog {
                    Spacer().frame(height: 12)

                    QuickEventPanel(eventLogger: eventLogger)
                        .padding(.horizontal)
                }

                if homeState.showsWakeAction {
                    Spacer().frame(height: 12)

                    WakeUpButton(
                        eventLogger: eventLogger,
                        showMorningCheckIn: $showMorningCheckIn
                    )
                    .padding(.horizontal)
                }

                if homeState.showsSessionSummary {
                    Spacer().frame(height: 12)

                    CompactSessionSummary(core: core, eventLogger: eventLogger)
                        .padding(.horizontal)
                }

                if homeState.showsWeeklyInsights {
                    Spacer().frame(height: 12)

                    WeeklyInsightsCard(sessionRepo: sessionRepo)
                        .padding(.horizontal)
                }

                if homeState.showsLiveDoseIntervals {
                    Spacer().frame(height: 12)

                    LiveDoseIntervalsCard(sessionRepo: sessionRepo)
                        .padding(.horizontal)
                }
            } // end compact layout

            Spacer()
                .frame(height: 100) // Space for tab bar (increased from 80)
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showMorningCheckIn) {
            if let existing = morningCheckIn {
                // Edit existing check-in
                MorningCheckInView(
                    sessionId: existing.sessionId,
                    sessionDate: existing.sessionDate,
                    existingCheckIn: existing,
                    onComplete: {
                        appLogger.info("Morning check-in updated")
                        reloadMorningCheckIn()
                    }
                )
            } else {
                // New check-in
                MorningCheckInView(
                    sessionId: sessionRepo.currentSessionIdString(),
                    sessionDate: sessionRepo.currentSessionDateString(),
                    onComplete: {
                        appLogger.info("Morning check-in complete")
                        reloadMorningCheckIn()
                    }
                )
            }
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
                onConfirm: { reason, notes in
                    Task {
                        let result = await coordinator.takeDose2(
                            override: .earlyConfirmed,
                            reason: reason,
                            reasonNotes: notes
                        )
                        if case .blocked(let reason) = result {
                            appLogger.warning("Early dose override blocked: \(reason, privacy: .public)")
                        }
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
                Task {
                    let result = await coordinator.takeDose2(override: .extraDoseConfirmed)
                    if case .blocked(let reason) = result {
                        appLogger.warning("Extra dose override blocked: \(reason, privacy: .public)")
                    }
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
            // Check for incomplete sessions on view appear (skip permanently dismissed ones)
            if let candidate = sessionRepo.mostRecentIncompleteSession(),
               !Self.isDismissed(candidate) {
                incompleteSessionDate = candidate
            } else {
                incompleteSessionDate = nil
            }
            syncOverrideState()
            reloadPreSleepLog()
            reloadMorningCheckIn()
        }
        .onChange(of: sessionRepo.currentSessionKey) { _ in
            syncOverrideState()
            reloadPreSleepLog()
            reloadMorningCheckIn()
        }
        .onReceive(sessionRepo.sessionDidChange) { _ in
            reloadPreSleepLog()
            reloadMorningCheckIn()
        }
        .onChange(of: showMorningCheckIn) { newValue in
            if !newValue {
                reloadMorningCheckIn()
            }
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

    private var resolvedHomeState: HomePresentationState {
        HomeStateResolver.resolve(
            doseStatus: core.currentStatus,
            currentSessionDate: sessionRepo.currentSessionDateString(),
            activeSessionDate: sessionRepo.activeSessionDate,
            incompleteSessionDate: incompleteSessionDate,
            awaitingRolloverMessage: sessionRepo.awaitingRolloverMessage,
            checkInCompleted: sessionRepo.checkInCompleted,
            hasMorningCheckIn: morningCheckIn != nil,
            dose2Skipped: sessionRepo.dose2Skipped,
            hasDose2: sessionRepo.dose2Time != nil
        )
    }

    private var sleepPlanSummary: (wakeBy: Date, recommendedInBed: Date, windDown: Date, expectedSleepMinutes: Double)? {
        let key = sessionRepo.currentSessionKey
        return sleepPlanStore.plan(for: key, now: Date(), tz: TimeZone.current)
    }

    private func reloadPreSleepLog() {
        let key = sessionRepo.preSleepLogSessionKey(for: Date())
        preSleepLog = sessionRepo.fetchMostRecentPreSleepLog(sessionId: key)

        // Fallback: if the primary key is a UUID (post-dose-1) and linking hasn't
        // updated the pre-sleep log yet, try the date-string key.
        if preSleepLog == nil {
            let displayKey = sessionRepo.preSleepDisplaySessionKey(for: Date())
            if displayKey != key {
                preSleepLog = sessionRepo.fetchMostRecentPreSleepLog(sessionId: displayKey)
            }
        }
        // Last-resort fallback: try the raw date string (pre-session key)
        if preSleepLog == nil {
            let dateKey = preSleepSessionKey(for: Date(), timeZone: .current)
            if dateKey != key {
                preSleepLog = sessionRepo.fetchMostRecentPreSleepLog(sessionId: dateKey)
            }
        }

        if preSleepLog == nil {
            preSleepEditingLog = nil
        }
    }

    private func reloadMorningCheckIn() {
        let key = sessionRepo.activeSessionDate ?? sessionRepo.currentSessionKey
        morningCheckIn = sessionRepo.fetchMorningCheckIn(for: key)
    }

    // MARK: - Persistent Banner Dismissal

    private static let dismissedSessionsKey = "dismissedIncompleteSessions"

    /// Persist that a user dismissed the incomplete-session banner for this date.
    static func dismissIncompleteSession(_ sessionDate: String) {
        var dismissed = UserDefaults.standard.stringArray(forKey: dismissedSessionsKey) ?? []
        if !dismissed.contains(sessionDate) {
            dismissed.append(sessionDate)
            // Keep only the 30 most recent dismissals to avoid unbounded growth
            if dismissed.count > 30 { dismissed = Array(dismissed.suffix(30)) }
            UserDefaults.standard.set(dismissed, forKey: dismissedSessionsKey)
        }
    }

    /// Check if a session date has been permanently dismissed.
    static func isDismissed(_ sessionDate: String) -> Bool {
        let dismissed = UserDefaults.standard.stringArray(forKey: dismissedSessionsKey) ?? []
        return dismissed.contains(sessionDate)
    }
}

// MARK: - Quick Theme Switch Button
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
            Haptics.light.play()
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
        // Use the session key to determine the "Tonight" date
        // If the session key is 2025-12-26, we want to show Friday, Dec 26
        let key = sessionRepo.currentSessionKey

        if let date = AppFormatters.sessionDate.date(from: key) {
            return "Tonight – " + AppFormatters.weekdayMedium.string(from: date)
        }

        return "Tonight – " + AppFormatters.weekdayMedium.string(from: Date())
    }
}

// MARK: - Tonight Events Sheet (Popover replacement for better visibility)
struct TonightEventsSheet: View {
    let events: [LoggedEvent]
    let onDelete: (UUID) -> Void
    let onEditTime: ((UUID, Date) -> Void)?
    let onEditNotes: ((UUID, String?) -> Void)?
    let onAddEvent: ((String, Color, Date) -> Void)?
    let storedEventLookup: ((UUID) -> StoredSleepEvent?)?
    @Environment(\.dismiss) private var dismiss
    @State private var editingEvent: StoredSleepEvent?
    @State private var showAddEvent = false

    init(
        events: [LoggedEvent],
        onDelete: @escaping (UUID) -> Void,
        onEditTime: ((UUID, Date) -> Void)? = nil,
        onEditNotes: ((UUID, String?) -> Void)? = nil,
        onAddEvent: ((String, Color, Date) -> Void)? = nil,
        storedEventLookup: ((UUID) -> StoredSleepEvent?)? = nil
    ) {
        self.events = events
        self.onDelete = onDelete
        self.onEditTime = onEditTime
        self.onEditNotes = onEditNotes
        self.onAddEvent = onAddEvent
        self.storedEventLookup = storedEventLookup
    }

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
                            Button {
                                if let lookup = storedEventLookup,
                                   let stored = lookup(event.id) {
                                    editingEvent = stored
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(event.color)
                                        .frame(width: 12, height: 12)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.name)
                                            .font(.body)
                                        Text(event.time.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let stored = storedEventLookup?(event.id),
                                           let notes = stored.notes,
                                           !notes.isEmpty, notes != "manual" {
                                            Text(notes)
                                                .font(.caption2)
                                                .italic()
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(2)
                                        }
                                    }

                                    Spacer()

                                    if storedEventLookup != nil {
                                        Image(systemName: "pencil")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .tint(.primary)
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
                    Button {
                        showAddEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $editingEvent) { event in
                EditEventTimeView(
                    event: event,
                    sessionDate: SessionRepository.shared.currentSessionKey,
                    onSave: { newTime in
                        onEditTime?(UUID(uuidString: event.id) ?? UUID(), newTime)
                    },
                    onSaveNotes: onEditNotes.map { handler in
                        { notes in
                            handler(UUID(uuidString: event.id) ?? UUID(), notes)
                        }
                    }
                )
            }
            .sheet(isPresented: $showAddEvent) {
                ManualEventLogView { eventType, color, timestamp in
                    onAddEvent?(eventType, color, timestamp)
                }
            }
        }
    }
}
