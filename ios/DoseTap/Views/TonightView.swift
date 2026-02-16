import SwiftUI
import DoseCore
import os.log

// MARK: - Legacy Tonight View
struct LegacyTonightView: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var undoState: UndoStateManager
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
            
            // Wide layout: dose controls left, events right
            // Compact layout: stacked vertically (default)
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 16) {
                    // LEFT: Dose controls + status
                    VStack(spacing: 12) {
                        CompactDoseButton(
                            core: core,
                            eventLogger: eventLogger,
                            undoState: undoState,
                            sessionRepo: sessionRepo,
                            showEarlyDoseAlert: $showEarlyDoseAlert,
                            earlyDoseMinutes: $earlyDoseMinutesRemaining,
                            showExtraDoseWarning: $showExtraDoseWarning
                        )
                        
                        WakeUpButton(
                            eventLogger: eventLogger,
                            showMorningCheckIn: $showMorningCheckIn
                        )
                        
                        LiveDoseIntervalsCard(sessionRepo: sessionRepo)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // RIGHT: Event log + session summary
                    VStack(spacing: 12) {
                        QuickEventPanel(eventLogger: eventLogger)
                        
                        CompactSessionSummary(core: core, eventLogger: eventLogger)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
            } else {
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
            } // end compact layout
            
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
