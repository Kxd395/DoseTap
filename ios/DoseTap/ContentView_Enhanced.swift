import SwiftUI
import DoseCore

// MARK: - Main Tab View
struct ContentView: View {
    @StateObject private var core = DoseTapCore()
    @StateObject private var settings = UserSettingsManager.shared
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tonight Tab (Main)
            TonightView(core: core)
                .tabItem {
                    Image(systemName: "moon.fill")
                    Text("Tonight")
                }
                .tag(0)
            
            // Details Tab (More info, full event log)
            DetailsView(core: core)
                .tabItem {
                    Image(systemName: "list.bullet.clipboard")
                    Text("Details")
                }
                .tag(1)
            
            // Settings Tab
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(2)
        }
        .preferredColorScheme(settings.colorScheme)
    }
}

// MARK: - Tonight View (Main Screen)
struct TonightView: View {
    @ObservedObject var core: DoseTapCore
    @State private var showEarlyDoseAlert = false
    @State private var showOverrideConfirmation = false
    @State private var earlyDoseMinutesRemaining: Int = 0
    @State private var recentEvents: [LoggedEvent] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Tonight's Date Header
                    TonightHeader()
                    
                    // Status Card
                    StatusCard(status: core.currentStatus)
                    
                    // Countdown Timer (when waiting)
                    if core.currentStatus == .beforeWindow, let dose1 = core.dose1Time {
                        TimeUntilWindowCard(dose1Time: dose1)
                    }
                    
                    // Main Dose Button
                    DoseButtonsSection(
                        core: core,
                        showEarlyDoseAlert: $showEarlyDoseAlert,
                        earlyDoseMinutes: $earlyDoseMinutesRemaining
                    )
                    
                    // Quick Event Log (most common buttons)
                    QuickEventPanel(recentEvents: $recentEvents)
                    
                    // Session Summary Card
                    SessionSummaryCard(core: core, eventCount: recentEvents.count)
                }
                .padding()
            }
            .navigationTitle("DoseTap")
            .navigationBarTitleDisplayMode(.large)
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
                        Task { await core.takeDose() }
                        showOverrideConfirmation = false
                    },
                    onCancel: { showOverrideConfirmation = false }
                )
            }
        }
    }
}

// MARK: - Tonight Header
struct TonightHeader: View {
    var body: some View {
        VStack(spacing: 4) {
            Text(tonightDateString)
                .font(.title2.bold())
            Text(sessionTimeRange)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    private var tonightDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return "Tonight – " + formatter.string(from: Date())
    }
    
    private var sessionTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let now = Date()
        let later = Calendar.current.date(byAdding: .hour, value: 8, to: now) ?? now
        return "\(formatter.string(from: now)) – \(formatter.string(from: later))"
    }
}

// MARK: - Quick Event Panel (Most Common)
struct QuickEventPanel: View {
    @Binding var recentEvents: [LoggedEvent]
    @State private var cooldowns: [String: Date] = [:]
    
    // Most common quick-access events
    private let quickEvents: [(name: String, icon: String, color: Color, cooldown: TimeInterval)] = [
        ("Bathroom", "toilet.fill", .blue, 60),
        ("Water", "drop.fill", .cyan, 300),
        ("Brief Wake", "moon.zzz.fill", .indigo, 300),
        ("Anxiety", "brain.head.profile", .purple, 300)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Log")
                    .font(.headline)
                Spacer()
                if !recentEvents.isEmpty {
                    Text("\(recentEvents.count) tonight")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 12) {
                ForEach(quickEvents, id: \.name) { event in
                    QuickEventButton(
                        name: event.name,
                        icon: event.icon,
                        color: event.color,
                        cooldownSeconds: event.cooldown,
                        cooldownEnd: cooldowns[event.name],
                        onTap: {
                            logEvent(event.name, cooldown: event.cooldown)
                        }
                    )
                }
            }
            
            // Recent events list
            if !recentEvents.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                
                ForEach(recentEvents.prefix(3)) { event in
                    HStack {
                        Circle()
                            .fill(event.color)
                            .frame(width: 8, height: 8)
                        Text(event.name)
                            .font(.caption)
                        Spacer()
                        Text(event.time, style: .time)
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
    }
    
    private func logEvent(_ name: String, cooldown: TimeInterval) {
        let now = Date()
        
        // Check cooldown
        if let end = cooldowns[name], now < end {
            return // Still in cooldown
        }
        
        // Log the event
        let event = LoggedEvent(
            name: name,
            time: now,
            color: quickEvents.first { $0.name == name }?.color ?? .gray
        )
        recentEvents.insert(event, at: 0)
        
        // Set cooldown
        cooldowns[name] = now.addingTimeInterval(cooldown)
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}

// MARK: - Quick Event Button
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
            VStack(spacing: 6) {
                ZStack {
                    // Background circle
                    Circle()
                        .fill(color.opacity(isOnCooldown ? 0.2 : 0.15))
                        .frame(width: 52, height: 52)
                    
                    // Cooldown progress ring
                    if isOnCooldown {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(color.opacity(0.5), lineWidth: 3)
                            .frame(width: 52, height: 52)
                            .rotationEffect(.degrees(-90))
                    }
                    
                    // Icon
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(isOnCooldown ? color.opacity(0.4) : color)
                }
                
                Text(name)
                    .font(.caption2)
                    .foregroundColor(isOnCooldown ? .secondary : .primary)
                    .lineLimit(1)
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
    let id = UUID()
    let name: String
    let time: Date
    let color: Color
}

// MARK: - Details View (Second Tab)
struct DetailsView: View {
    @ObservedObject var core: DoseTapCore
    @State private var allEvents: [LoggedEvent] = []
    
    // All available events for full logging
    private let allEventTypes: [(name: String, icon: String, color: Color, cooldown: TimeInterval)] = [
        // Physical
        ("Bathroom", "toilet.fill", .blue, 60),
        ("Water", "drop.fill", .cyan, 300),
        ("Snack", "fork.knife", .green, 900),
        // Sleep Cycle
        ("Lights Out", "light.max", .indigo, 3600),
        ("Wake Up", "sun.max.fill", .yellow, 3600),
        ("Brief Wake", "moon.zzz.fill", .indigo, 300),
        // Mental
        ("Anxiety", "brain.head.profile", .purple, 300),
        ("Dream", "cloud.moon.fill", .pink, 60),
        ("Heart Racing", "heart.fill", .red, 300),
        // Environment
        ("Noise", "speaker.wave.3.fill", .orange, 60),
        ("Temperature", "thermometer.medium", .teal, 300),
        ("Pain", "bandage.fill", .red, 300)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Full Session Details
                    FullSessionDetails(core: core)
                    
                    // Full Event Log Grid
                    FullEventLogGrid(
                        eventTypes: allEventTypes,
                        allEvents: $allEvents
                    )
                    
                    // Event History
                    EventHistorySection(events: allEvents)
                }
                .padding()
            }
            .navigationTitle("Details")
        }
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
    let eventTypes: [(name: String, icon: String, color: Color, cooldown: TimeInterval)]
    @Binding var allEvents: [LoggedEvent]
    @State private var cooldowns: [String: Date] = [:]
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log Sleep Event")
                .font(.headline)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(eventTypes, id: \.name) { event in
                    EventGridButton(
                        name: event.name,
                        icon: event.icon,
                        color: event.color,
                        cooldownEnd: cooldowns[event.name],
                        cooldownDuration: event.cooldown,
                        onTap: {
                            logEvent(event)
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
    
    private func logEvent(_ event: (name: String, icon: String, color: Color, cooldown: TimeInterval)) {
        let now = Date()
        
        // Check cooldown
        if let end = cooldowns[event.name], now < end {
            return
        }
        
        // Log event
        allEvents.insert(LoggedEvent(name: event.name, time: now, color: event.color), at: 0)
        cooldowns[event.name] = now.addingTimeInterval(event.cooldown)
        
        // Haptic
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
