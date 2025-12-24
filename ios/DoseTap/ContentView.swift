import SwiftUI
import DoseCore

// MARK: - Shared Event Logger (Observable with SQLite persistence)
@MainActor
class EventLogger: ObservableObject {
    static let shared = EventLogger()
    
    @Published var events: [LoggedEvent] = []
    @Published var cooldowns: [String: Date] = [:]
    
    private let storage = EventStorage.shared
    
    private init() {
        // Load persisted events from SQLite on startup
        loadEventsFromStorage()
    }
    
    /// Load events from SQLite for tonight's session
    private func loadEventsFromStorage() {
        let storedEvents = storage.fetchTonightsSleepEvents()
        events = storedEvents.map { stored in
            LoggedEvent(
                id: UUID(uuidString: stored.id) ?? UUID(),
                name: stored.eventType,
                time: stored.timestamp,
                color: stored.colorHex.flatMap { Color(hex: $0) } ?? .gray
            )
        }
        print("📦 Loaded \(events.count) events from SQLite")
    }
    
    func logEvent(name: String, color: Color, cooldownSeconds: TimeInterval) {
        let now = Date()
        
        // Check cooldown
        if let end = cooldowns[name], now < end {
            return // Still in cooldown
        }
        
        // Create and add event
        let eventId = UUID()
        let event = LoggedEvent(id: eventId, name: name, time: now, color: color)
        events.insert(event, at: 0)
        
        // Set cooldown
        cooldowns[name] = now.addingTimeInterval(cooldownSeconds)
        
        // Persist to SQLite
        storage.insertSleepEvent(
            id: eventId.uuidString,
            eventType: name,
            timestamp: now,
            colorHex: color.toHex()
        )
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    func isOnCooldown(_ name: String) -> Bool {
        guard let end = cooldowns[name] else { return false }
        return Date() < end
    }
    
    func cooldownEnd(for name: String) -> Date? {
        cooldowns[name]
    }
    
    /// Clear cooldown for a specific event (for undo)
    func clearCooldown(for name: String) {
        cooldowns.removeValue(forKey: name)
        // Also remove the event from the in-memory list
        events.removeAll { $0.name == name }
    }
    
    /// Delete a specific event by ID
    func deleteEvent(id: UUID) {
        events.removeAll { $0.id == id }
        storage.deleteSleepEvent(id: id.uuidString)
    }
    
    /// Refresh events from storage
    func refresh() {
        loadEventsFromStorage()
    }
    
    /// Clear tonight's events
    func clearTonight() {
        events.removeAll()
        cooldowns.removeAll()
        storage.clearTonightsEvents()
    }
}

// MARK: - Main Tab View with Swipe Navigation
struct ContentView: View {
    @StateObject private var core = DoseTapCore()
    @StateObject private var settings = UserSettingsManager.shared
    @StateObject private var eventLogger = EventLogger.shared
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Swipeable Page View
            TabView(selection: $selectedTab) {
                TonightView(core: core, eventLogger: eventLogger)
                    .tag(0)
                
                DetailsView(core: core, eventLogger: eventLogger)
                    .tag(1)
                
                HistoryView()
                    .tag(2)
                
                SettingsView()
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)
            
            // Custom Tab Bar
            CustomTabBar(selectedTab: $selectedTab)
        }
        .preferredColorScheme(settings.colorScheme)
        .onAppear {
            // Restore dose state from SQLite on app launch
            let storage = EventStorage.shared
            let (dose1, dose2, snoozeCount, skipped) = storage.loadCurrentSession()
            if let d1 = dose1 {
                Task { @MainActor in
                    core.dose1Time = d1
                    core.dose2Time = dose2
                    core.snoozeCount = snoozeCount
                    core.isSkipped = skipped
                }
            }
        }
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    
    private let tabs: [(icon: String, label: String)] = [
        ("moon.fill", "Tonight"),
        ("list.bullet.clipboard", "Details"),
        ("calendar", "History"),
        ("gear", "Settings")
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = index
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].icon)
                            .font(.system(size: 20))
                        Text(tabs[index].label)
                            .font(.caption2)
                    }
                    .foregroundColor(selectedTab == index ? .blue : .gray)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.bottom, 20)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
                .ignoresSafeArea()
        )
    }
}

// MARK: - Tonight View (Main Screen - No Scroll)
struct TonightView: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @State private var showEarlyDoseAlert = false
    @State private var showOverrideConfirmation = false
    @State private var earlyDoseMinutesRemaining: Int = 0
    @State private var showMorningCheckIn = false
    @State private var showPreSleepLog = false
    @State private var showExtraDoseWarning = false  // For second dose 2 attempt
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 2) {
                Text("DoseTap")
                    .font(.largeTitle.bold())
                TonightDateLabel()
            }
            .padding(.top, 8)
            
            Spacer()
            
            // Combined Status + Timer Card (compact)
            CompactStatusCard(core: core)
            
            Spacer()
            
            // Pre-Sleep Log Button (only show if no dose taken yet)
            if core.dose1Time == nil {
                PreSleepLogButton(showPreSleepLog: $showPreSleepLog)
                    .padding(.horizontal)
                
                Spacer()
            }
            
            // Main Dose Button
            CompactDoseButton(
                core: core,
                eventLogger: eventLogger,
                showEarlyDoseAlert: $showEarlyDoseAlert,
                earlyDoseMinutes: $earlyDoseMinutesRemaining,
                showExtraDoseWarning: $showExtraDoseWarning
            )
            
            Spacer()
            
            // Quick Event Log
            QuickEventPanel(eventLogger: eventLogger)
                .padding(.horizontal)
            
            Spacer()
            
            // Wake Up & End Session Button (prominent)
            WakeUpButton(
                eventLogger: eventLogger,
                showMorningCheckIn: $showMorningCheckIn
            )
            .padding(.horizontal)
            
            Spacer()
            
            // Compact Session Summary (tap events to expand list)
            CompactSessionSummary(core: core, eventLogger: eventLogger)
                .padding(.horizontal)
            
            Spacer()
                .frame(height: 80) // Space for tab bar
        }
        .padding(.horizontal)
        .sheet(isPresented: $showMorningCheckIn) {
            MorningCheckInView(
                sessionId: UUID(),
                onComplete: {
                    // Session ended - could trigger a session reset here
                    print("✅ Morning check-in complete")
                }
            )
        }
        .sheet(isPresented: $showPreSleepLog) {
            PreSleepLogView(
                onComplete: { answers in
                    // Save the pre-sleep log
                    let log = PreSleepLog(answers: answers, completionState: "complete")
                    EventStorage.shared.savePreSleepLog(log)
                    print("✅ Pre-sleep log saved: \(log.id)")
                },
                onSkip: {
                    // Save as skipped for tracking
                    let emptyAnswers = PreSleepLogAnswers()
                    let log = PreSleepLog(answers: emptyAnswers, completionState: "skipped")
                    EventStorage.shared.savePreSleepLog(log)
                    print("⏭️ Pre-sleep log skipped")
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
            Text("The dose window hasn't opened yet.\n\n\(earlyDoseMinutesRemaining) minutes remaining until window opens.\n\nTaking Dose 2 too early may reduce effectiveness.")
        }
        .sheet(isPresented: $showOverrideConfirmation) {
            EarlyDoseOverrideSheet(
                minutesRemaining: earlyDoseMinutesRemaining,
                onConfirm: {
                    Task {
                        let storage = EventStorage.shared
                        let now = Date()
                        // Taking Dose 2 early with explicit override
                        await core.takeDose(earlyOverride: true)
                        // Persist to SQLite for History tab (with early flag in metadata)
                        storage.saveDose2(timestamp: now, isEarly: true)
                        // Log dose as event with Early badge for Details tab
                        eventLogger.logEvent(name: "Dose 2 (Early)", color: .orange, cooldownSeconds: 3600 * 8)
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
                    let storage = EventStorage.shared
                    let now = Date()
                    // Save as extra_dose (does NOT update dose2_time)
                    storage.saveDose2(timestamp: now, isExtraDose: true)
                    // Log with warning color
                    eventLogger.logEvent(name: "Extra Dose ⚠️", color: .red, cooldownSeconds: 0)
                    print("⚠️ Extra dose logged at \(now) - user confirmed")
                }
            }
        } message: {
            Text("You have already taken Dose 2 tonight at \(core.dose2Time?.formatted(date: .omitted, time: .shortened) ?? "unknown").\n\n⛔️ TAKING ADDITIONAL DOSES CAN BE DANGEROUS.\n\nThis action will be logged but will NOT replace your original Dose 2 time.\n\nDo NOT proceed unless absolutely necessary.")
        }
    }
}

// MARK: - Tonight Date Label
struct TonightDateLabel: View {
    var body: some View {
        Text(tonightDateString)
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    
    private var tonightDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return "Tonight – " + formatter.string(from: Date())
    }
}

// MARK: - Pre-Sleep Log Button
struct PreSleepLogButton: View {
    @Binding var showPreSleepLog: Bool
    
    var body: some View {
        Button {
            showPreSleepLog = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pre-Sleep Check")
                        .font(.subheadline.bold())
                    Text("Quick 30-second check-in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.indigo.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                    )
            )
            .foregroundColor(.indigo)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Status Card (combines status + timer)
struct CompactStatusCard: View {
    @ObservedObject var core: DoseTapCore
    @State private var timeRemaining: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private let windowOpenMinutes: TimeInterval = 150
    
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
            
            // Timer (only when waiting)
            if core.currentStatus == .beforeWindow, core.dose1Time != nil {
                Text(formatTimeRemaining)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.orange)
                    .monospacedDigit()
                
                Text("Window opens at \(formatWindowOpenTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
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
        .onAppear { updateTimeRemaining() }
        .onReceive(timer) { _ in updateTimeRemaining() }
    }
    
    private func updateTimeRemaining() {
        guard let dose1 = core.dose1Time else { return }
        let windowOpenTime = dose1.addingTimeInterval(windowOpenMinutes * 60)
        timeRemaining = max(0, windowOpenTime.timeIntervalSince(Date()))
    }
    
    private var formatTimeRemaining: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        let seconds = Int(timeRemaining) % 60
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
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
        }
    }
    
    private var statusDescription: String {
        switch core.currentStatus {
        case .noDose1: return "Tap below to start"
        case .beforeWindow: return "Wait for optimal timing"
        case .active: return "Take Dose 2 now"
        case .nearClose: return "Less than 15 minutes left!"
        case .closed: return "Window has closed"
        case .completed: return "Both doses taken ✓"
        }
    }
    
    private var statusColor: Color {
        switch core.currentStatus {
        case .noDose1: return .blue
        case .beforeWindow: return .orange
        case .active: return .green
        case .nearClose: return .red
        case .closed: return .gray
        case .completed: return .purple
        }
    }
}

// MARK: - Compact Dose Button
struct CompactDoseButton: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @Binding var showEarlyDoseAlert: Bool
    @Binding var earlyDoseMinutes: Int
    @Binding var showExtraDoseWarning: Bool  // For second dose 2 attempt
    
    private let windowOpenMinutes: Double = 150
    
    var body: some View {
        VStack(spacing: 8) {
            Button(action: handlePrimaryButtonTap) {
                Text(primaryButtonText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(primaryButtonColor)
                    .cornerRadius(12)
            }
            // Allow tapping even when "completed" to show extra dose warning
            .disabled(core.currentStatus == .closed)
            .padding(.horizontal)
            
            // Secondary buttons row
            if core.currentStatus != .noDose1 && core.currentStatus != .completed {
                HStack(spacing: 12) {
                    Button {
                        Task { await core.snooze() }
                    } label: {
                        Label("Snooze", systemImage: "bell.badge")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!snoozeEnabled)
                    
                    Button {
                        Task { await core.skipDose() }
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
        let storage = EventStorage.shared
        
        guard core.dose1Time != nil else {
            Task {
                let now = Date()
                await core.takeDose()
                // Persist to SQLite for History tab
                storage.saveDose1(timestamp: now)
                // Link any recent pre-sleep log to this session
                let sessionId = storage.currentSessionDate()
                storage.linkPreSleepLogToSession(sessionId: sessionId)
                // Log Dose 1 as event for Details tab
                eventLogger.logEvent(name: "Dose 1", color: .green, cooldownSeconds: 3600 * 8)
            }
            return
        }
        
        // SAFETY: Check if Dose 2 already taken - show extra dose warning
        if core.dose2Time != nil {
            showExtraDoseWarning = true
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
            // Persist to SQLite for History tab
            storage.saveDose2(timestamp: now)
            // Log Dose 2 as event for Details tab
            eventLogger.logEvent(name: "Dose 2", color: .green, cooldownSeconds: 3600 * 8)
        }
    }
    
    private var primaryButtonText: String {
        switch core.currentStatus {
        case .noDose1: return "Take Dose 1"
        case .beforeWindow: return "Waiting..."
        case .active, .nearClose: return "Take Dose 2"
        case .closed: return "Window Closed"
        case .completed: return "Complete ✓"
        }
    }
    
    private var primaryButtonColor: Color {
        switch core.currentStatus {
        case .noDose1: return .blue
        case .beforeWindow: return .gray
        case .active: return .green
        case .nearClose: return .orange
        case .closed: return .gray
        case .completed: return .purple
        }
    }
    
    private var snoozeEnabled: Bool {
        (core.currentStatus == .active || core.currentStatus == .nearClose) && core.snoozeCount < 3
    }
    
    private var skipEnabled: Bool {
        core.currentStatus == .active || core.currentStatus == .nearClose
    }
}

// MARK: - Compact Session Summary (horizontal)
struct CompactSessionSummary: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @State private var isEventsExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Summary row
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
                
                // Tappable Events item
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEventsExpanded.toggle()
                    }
                }) {
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            Image(systemName: "list.bullet")
                                .font(.caption)
                            Image(systemName: isEventsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                        }
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
            
            // Expanded event list
            if isEventsExpanded {
                ExpandedEventList(
                    events: eventLogger.events,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEventsExpanded = false
                        }
                    }
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
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
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Expanded Event List (shows when event count is tapped)
struct ExpandedEventList: View {
    let events: [LoggedEvent]
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal)
            
            if events.isEmpty {
                Text("No events logged tonight")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(events.sorted(by: { $0.time > $1.time })) { event in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(event.color)
                                    .frame(width: 8, height: 8)
                                
                                Text(event.name)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                Text(event.time.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
            
            // Close button
            Button(action: onClose) {
                HStack {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                    Text("Close")
                        .font(.caption)
                }
                .foregroundColor(.blue)
                .padding(.vertical, 8)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Quick Event Panel (Compact)
struct QuickEventPanel: View {
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var settings = UserSettingsManager.shared
    
    // Use first 4 customized QuickLog buttons from settings for compact view
    private var quickEvents: [(name: String, icon: String, color: Color)] {
        settings.quickLogButtons.prefix(4).map { ($0.name, $0.icon, $0.color) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Log")
                    .font(.subheadline.bold())
                Spacer()
                if !eventLogger.events.isEmpty {
                    Text("\(eventLogger.events.count) tonight")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 8) {
                ForEach(quickEvents, id: \.name) { event in
                    let cooldown = settings.cooldown(for: event.name)
                    QuickEventButton(
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
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Quick Event Button (Compact)
struct QuickEventButton: View {
    let name: String
    let icon: String
    let color: Color
    let cooldownSeconds: TimeInterval
    let cooldownEnd: Date?
    let onTap: () -> Void
    
    @State private var progress: CGFloat = 1.0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isOnCooldown ? 0.2 : 0.15))
                        .frame(width: 44, height: 44)
                    
                    if isOnCooldown {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(color.opacity(0.5), lineWidth: 2)
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                    }
                    
                    Image(systemName: icon)
                        .font(.body)
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
        .frame(maxWidth: .infinity)
        .onReceive(timer) { _ in
            updateProgress()
        }
    }
    
    private var isOnCooldown: Bool {
        guard let end = cooldownEnd else { return false }
        return Date() < end
    }
    
    private func updateProgress() {
        guard let end = cooldownEnd else {
            progress = 1.0
            return
        }
        let remaining = end.timeIntervalSince(Date())
        if remaining <= 0 {
            progress = 1.0
        } else {
            progress = 1.0 - CGFloat(remaining / cooldownSeconds)
        }
    }
}

// MARK: - Wake Up & End Session Button
struct WakeUpButton: View {
    @ObservedObject var eventLogger: EventLogger
    @Binding var showMorningCheckIn: Bool
    @ObservedObject var settings = UserSettingsManager.shared
    @State private var showConfirmation = false
    @State private var showUndoSnackbar = false
    @State private var lastWakeEventId: String?
    
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
            Text("This will log your wake time and start the morning check-in. You can undo this within 5 seconds if tapped by mistake.")
        }
        .overlay(alignment: .bottom) {
            if showUndoSnackbar {
                UndoSnackbarView(
                    message: "Wake Up logged",
                    onUndo: undoWakeUp,
                    onDismiss: { showUndoSnackbar = false }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 8)
            }
        }
    }
    
    private func logWakeAndShowCheckIn() {
        // Log the Wake Up event
        eventLogger.logEvent(
            name: "Wake Up",
            color: .yellow,
            cooldownSeconds: cooldownSeconds
        )
        
        // Save to SQLite and store ID for undo
        let id = UUID().uuidString
        lastWakeEventId = id
        EventStorage.shared.insertSleepEvent(
            id: id,
            eventType: "wakeFinal",
            timestamp: Date(),
            colorHex: "#FFCC00",
            notes: nil
        )
        
        // Show undo snackbar
        withAnimation {
            showUndoSnackbar = true
        }
        
        // Auto-dismiss after 5 seconds and show check-in
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation {
                showUndoSnackbar = false
            }
            // Only show check-in if not undone
            if lastWakeEventId != nil {
                showMorningCheckIn = true
            }
        }
    }
    
    private func undoWakeUp() {
        guard let id = lastWakeEventId else { return }
        
        // Delete from SQLite
        EventStorage.shared.deleteSleepEvent(id: id)
        
        // Clear the event from logger
        eventLogger.clearCooldown(for: "Wake Up")
        
        // Clear state
        lastWakeEventId = nil
        
        withAnimation {
            showUndoSnackbar = false
        }
    }
    
    private var isOnCooldown: Bool {
        guard let end = eventLogger.cooldownEnd(for: "Wake Up") else { return false }
        return Date() < end
    }
}

// MARK: - Undo Snackbar View
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
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Logged Event Model
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
}

// MARK: - Details View (Second Tab)
struct DetailsView: View {
    @ObservedObject var core: DoseTapCore
    @ObservedObject var eventLogger: EventLogger
    @ObservedObject var settings = UserSettingsManager.shared
    
    // Use customized QuickLog buttons from settings
    private var quickLogEventTypes: [(name: String, icon: String, color: Color)] {
        settings.quickLogButtons.map { ($0.name, $0.icon, $0.color) }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Full Session Details (dose times, window status)
                    FullSessionDetails(core: core)
                    
                    // Full Event Log Grid (buttons to log events) - uses customized buttons
                    FullEventLogGrid(
                        eventTypes: quickLogEventTypes,
                        eventLogger: eventLogger,
                        settings: settings
                    )
                    
                    // Note: Event history is viewed in the History tab, not here
                    // This keeps Details focused on current session actions
                }
                .padding()
                .padding(.bottom, 80) // Space for tab bar
            }
            .navigationTitle("Details")
        }
    }
}

// MARK: - History View (Past Days)
struct HistoryView: View {
    @State private var selectedDate = Date()
    @State private var pastSessions: [SessionSummary] = []
    @State private var showDeleteDayConfirmation = false
    @State private var refreshTrigger = false  // Toggled to force SelectedDayView refresh
    
    private let storage = EventStorage.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
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
        pastSessions = storage.fetchRecentSessions(days: 7)
    }
    
    private func deleteSelectedDay() {
        let sessionDate = storage.sessionDateString(for: selectedDate)
        storage.deleteSession(sessionDate: sessionDate)
        refreshTrigger.toggle()  // Force SelectedDayView to reload
        loadHistory()
    }
}

// MARK: - Selected Day View
struct SelectedDayView: View {
    let date: Date
    var refreshTrigger: Bool = false  // External trigger to force reload
    var onDeleteRequested: (() -> Void)? = nil
    
    @State private var events: [StoredSleepEvent] = []
    @State private var doseLog: StoredDoseLog?
    
    private let storage = EventStorage.shared
    
    private var hasData: Bool {
        doseLog != nil || !events.isEmpty
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dateTitle)
                    .font(.headline)
                Spacer()
                if hasData, let onDelete = onDeleteRequested {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                    }
                }
            }
            
            if let dose = doseLog {
                // Dose info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "1.circle.fill")
                            .foregroundColor(.green)
                        Text("Dose 1")
                        Spacer()
                        Text(dose.dose1Time.formatted(date: .omitted, time: .shortened))
                            .foregroundColor(.secondary)
                    }
                    
                    if let d2 = dose.dose2Time {
                        HStack {
                            Image(systemName: "2.circle.fill")
                                .foregroundColor(.green)
                            Text("Dose 2")
                            Spacer()
                            Text(d2.formatted(date: .omitted, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                        
                        let interval = Int(d2.timeIntervalSince(dose.dose1Time) / 60)
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.purple)
                            Text("Interval")
                            Spacer()
                            Text("\(interval) minutes")
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
            } else {
                Text("No dose data for this date")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
            }
            
            // Events for this day
            if !events.isEmpty {
                Text("Events (\(events.count))")
                    .font(.subheadline.bold())
                    .padding(.top, 8)
                
                ForEach(events, id: \.id) { event in
                    HStack {
                        Circle()
                            .fill(Color(hex: event.colorHex ?? "#888888") ?? .gray)
                            .frame(width: 10, height: 10)
                        Text(event.eventType)
                            .font(.subheadline)
                        Spacer()
                        Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No events logged")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
    }
    
    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
    
    private func loadData() {
        let sessionDate = storage.sessionDateString(for: date)
        events = storage.fetchSleepEvents(forSession: sessionDate)
        doseLog = storage.fetchDoseLog(forSession: sessionDate)
    }
}

// MARK: - Recent Sessions List
struct RecentSessionsList: View {
    @State private var sessions: [SessionSummary] = []
    private let storage = EventStorage.shared
    
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
        sessions = storage.fetchRecentSessions(days: 7)
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
                let interval = Int(d2.timeIntervalSince(d1) / 60)
                Text("\(interval)m")
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
                        let interval = dose2.timeIntervalSince(dose1) / 60
                        DetailRow(
                            icon: "timer",
                            title: "Interval",
                            value: String(format: "%.0f minutes", interval),
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
        }
    }
    
    private var statusDescription: String {
        switch status {
        case .noDose1: return "Take Dose 1 to start your session"
        case .beforeWindow: return "Dose 2 window opens in 150 min"
        case .active: return "Take Dose 2 now"
        case .nearClose: return "Less than 15 minutes remaining!"
        case .closed: return "Window closed (240 min max)"
        case .completed: return "Both doses taken ✓"
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
            .disabled(core.currentStatus == .completed || core.currentStatus == .closed)
            
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
        
        Task { await core.takeDose() }
    }
    
    private var primaryButtonText: String {
        switch core.currentStatus {
        case .noDose1: return "Take Dose 1"
        case .beforeWindow: return "Waiting..."
        case .active, .nearClose: return "Take Dose 2"
        case .closed: return "Window Closed"
        case .completed: return "Complete ✓"
        }
    }
    
    private var primaryButtonColor: Color {
        switch core.currentStatus {
        case .noDose1: return .blue
        case .beforeWindow: return .gray
        case .active: return .green
        case .nearClose: return .orange
        case .closed: return .gray
        case .completed: return .purple
        }
    }
    
    private var snoozeEnabled: Bool {
        (core.currentStatus == .active || core.currentStatus == .nearClose) && core.snoozeCount < 3
    }
    
    private var skipEnabled: Bool {
        core.currentStatus == .active || core.currentStatus == .nearClose
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
                WarningRow(icon: "clock.badge.exclamationmark", text: "\(minutesRemaining) minutes early", color: .orange)
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
