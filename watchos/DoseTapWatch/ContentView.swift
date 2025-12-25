import SwiftUI
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - Dose Phase (matches iOS DoseStatus)
enum WatchDosePhase: String, Codable {
    case noDose1 = "awaiting_dose1"
    case beforeWindow = "before_window"
    case active = "window_open"
    case nearClose = "near_close"
    case closed = "window_closed"
    case completed = "completed"
    
    var displayText: String {
        switch self {
        case .noDose1: return "Take Dose 1"
        case .beforeWindow: return "Window Opens In"
        case .active: return "Window Open"
        case .nearClose: return "Closing Soon!"
        case .closed: return "Window Closed"
        case .completed: return "Complete ✓"
        }
    }
    
    var color: Color {
        switch self {
        case .noDose1: return .blue
        case .beforeWindow: return .orange
        case .active: return .green
        case .nearClose: return .yellow
        case .closed: return .red
        case .completed: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .noDose1: return "1.circle.fill"
        case .beforeWindow: return "clock.fill"
        case .active: return "checkmark.circle.fill"
        case .nearClose: return "exclamationmark.triangle.fill"
        case .closed: return "xmark.circle.fill"
        case .completed: return "checkmark.seal.fill"
        }
    }
}

// MARK: - Event Types for Quick Log
enum WatchEventType: String, CaseIterable {
    case bathroom = "bathroom"
    case lightsOut = "lights_out"
    case wakeFinal = "wake_final"
    
    var icon: String {
        switch self {
        case .bathroom: return "toilet.fill"
        case .lightsOut: return "light.max"
        case .wakeFinal: return "sun.horizon.fill"
        }
    }
    
    var label: String {
        switch self {
        case .bathroom: return "Bathroom"
        case .lightsOut: return "Lights Out"
        case .wakeFinal: return "Wake Up"
        }
    }
    
    var color: Color {
        switch self {
        case .bathroom: return .cyan
        case .lightsOut: return .indigo
        case .wakeFinal: return .orange
        }
    }
}

// MARK: - Watch View Model
@MainActor
class WatchDoseViewModel: ObservableObject {
    @Published var phase: WatchDosePhase = .noDose1
    @Published var dose1Time: Date?
    @Published var dose2Time: Date?
    @Published var remainingSeconds: Int = 0
    @Published var snoozeCount: Int = 0
    @Published var lastSyncTime: Date?
    @Published var isPhoneReachable: Bool = false
    
    private var timer: Timer?
    
    // Core timing constants (per SSOT)
    private let minIntervalMinutes = 150
    private let maxIntervalMinutes = 240
    private let maxSnoozes = 3
    private let snoozeMinutes = 10
    
    init() {
        startTimer()
        loadCachedState()
        #if canImport(WatchConnectivity)
        setupConnectivity()
        #endif
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateState()
            }
        }
    }
    
    #if canImport(WatchConnectivity)
    private func setupConnectivity() {
        if WCSession.isSupported() {
            isPhoneReachable = WCSession.default.isReachable
        }
    }
    #endif
    
    private func updateState() {
        guard let d1 = dose1Time else {
            phase = .noDose1
            remainingSeconds = 0
            return
        }
        
        if dose2Time != nil {
            phase = .completed
            remainingSeconds = 0
            return
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(d1)
        let elapsedMinutes = Int(elapsed / 60)
        let effectiveMax = maxIntervalMinutes + (snoozeCount * snoozeMinutes)
        
        if elapsedMinutes < minIntervalMinutes {
            // Before window opens
            phase = .beforeWindow
            let windowOpensAt = d1.addingTimeInterval(Double(minIntervalMinutes) * 60)
            remainingSeconds = max(0, Int(windowOpensAt.timeIntervalSince(now)))
        } else if elapsedMinutes < effectiveMax - 15 {
            // Window is open
            phase = .active
            let windowClosesAt = d1.addingTimeInterval(Double(effectiveMax) * 60)
            remainingSeconds = max(0, Int(windowClosesAt.timeIntervalSince(now)))
        } else if elapsedMinutes < effectiveMax {
            // Near close (< 15 min remaining)
            phase = .nearClose
            let windowClosesAt = d1.addingTimeInterval(Double(effectiveMax) * 60)
            remainingSeconds = max(0, Int(windowClosesAt.timeIntervalSince(now)))
        } else {
            // Window closed
            phase = .closed
            remainingSeconds = 0
        }
        
        #if canImport(WatchConnectivity)
        isPhoneReachable = WCSession.default.isReachable
        #endif
    }
    
    // MARK: - Actions
    
    func takeDose1() {
        let now = Date()
        dose1Time = now
        snoozeCount = 0
        send(event: "dose1", time: now)
        saveState()
        updateState()
    }
    
    func takeDose2() {
        guard dose1Time != nil, phase == .active || phase == .nearClose else { return }
        let now = Date()
        dose2Time = now
        send(event: "dose2", time: now)
        saveState()
        updateState()
    }
    
    func skipDose() {
        guard dose1Time != nil, phase != .completed else { return }
        dose2Time = Date() // Mark as "done" for today
        send(event: "skip", time: Date())
        saveState()
        updateState()
    }
    
    func snooze() {
        guard phase == .active || phase == .nearClose else { return }
        guard snoozeCount < maxSnoozes else { return }
        guard remainingSeconds > 15 * 60 else { return } // Disable when <15 min
        
        snoozeCount += 1
        send(event: "snooze", time: Date())
        saveState()
        updateState()
    }
    
    func logEvent(_ type: WatchEventType) {
        send(event: type.rawValue, time: Date())
    }
    
    var canSnooze: Bool {
        (phase == .active || phase == .nearClose) &&
        snoozeCount < maxSnoozes &&
        remainingSeconds > 15 * 60
    }
    
    // MARK: - Communication
    
    private func send(event: String, time: Date) {
        let payload: [String: Any] = [
            "event": event,
            "time": time.timeIntervalSince1970,
            "snoozeCount": snoozeCount
        ]
        
        #if canImport(WatchConnectivity)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.handleReply(reply)
                }
            }, errorHandler: { error in
                print("Send failed: \(error.localizedDescription)")
            })
        } else {
            // Queue for later - use transferUserInfo for guaranteed delivery
            WCSession.default.transferUserInfo(payload)
            print("Queued event '\(event)' for later sync")
        }
        #else
        print("WatchConnectivity unavailable; event='\(event)' not sent")
        #endif
    }
    
    private func handleReply(_ reply: [String: Any]) {
        // Update state from phone if provided
        if let d1Interval = reply["dose1Time"] as? TimeInterval {
            dose1Time = Date(timeIntervalSince1970: d1Interval)
        }
        if let d2Interval = reply["dose2Time"] as? TimeInterval {
            dose2Time = Date(timeIntervalSince1970: d2Interval)
        }
        if let snoozeCt = reply["snoozeCount"] as? Int {
            snoozeCount = snoozeCt
        }
        lastSyncTime = Date()
        saveState()
        updateState()
    }
    
    // MARK: - Persistence
    
    private let dose1Key = "watch_dose1_time"
    private let dose2Key = "watch_dose2_time"
    private let snoozeKey = "watch_snooze_count"
    private let sessionDateKey = "watch_session_date"
    
    private func loadCachedState() {
        let defaults = UserDefaults.standard
        
        // Check if we're on the same "session" day (6 PM to 6 PM)
        let today = sessionDateString(for: Date())
        if defaults.string(forKey: sessionDateKey) != today {
            // New session, clear old state
            defaults.removeObject(forKey: dose1Key)
            defaults.removeObject(forKey: dose2Key)
            defaults.set(0, forKey: snoozeKey)
            defaults.set(today, forKey: sessionDateKey)
            return
        }
        
        if let d1Interval = defaults.object(forKey: dose1Key) as? TimeInterval {
            dose1Time = Date(timeIntervalSince1970: d1Interval)
        }
        if let d2Interval = defaults.object(forKey: dose2Key) as? TimeInterval {
            dose2Time = Date(timeIntervalSince1970: d2Interval)
        }
        snoozeCount = defaults.integer(forKey: snoozeKey)
    }
    
    private func saveState() {
        let defaults = UserDefaults.standard
        let today = sessionDateString(for: Date())
        
        defaults.set(today, forKey: sessionDateKey)
        
        if let d1 = dose1Time {
            defaults.set(d1.timeIntervalSince1970, forKey: dose1Key)
        }
        if let d2 = dose2Time {
            defaults.set(d2.timeIntervalSince1970, forKey: dose2Key)
        }
        defaults.set(snoozeCount, forKey: snoozeKey)
    }
    
    private func sessionDateString(for date: Date) -> String {
        let calendar = Calendar.current
        var effectiveDate = date
        if calendar.component(.hour, from: date) < 18 {
            effectiveDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: effectiveDate)
    }
    
    // MARK: - Sync from Phone
    
    func syncFromPhone(state: [String: Any]) {
        if let d1Interval = state["dose1Time"] as? TimeInterval, d1Interval > 0 {
            dose1Time = Date(timeIntervalSince1970: d1Interval)
        }
        if let d2Interval = state["dose2Time"] as? TimeInterval, d2Interval > 0 {
            dose2Time = Date(timeIntervalSince1970: d2Interval)
        }
        if let snoozeCt = state["snoozeCount"] as? Int {
            snoozeCount = snoozeCt
        }
        lastSyncTime = Date()
        saveState()
        updateState()
    }
}
            // Window closed
            phase = .closed
            remainingSeconds = 0
        }
    }
    
    func takeDose() {
        let now = Date()
        if dose1Time == nil {
            dose1Time = now
            send(event: "dose1")
        } else if phase == .active || phase == .nearClose {
            dose2Time = now
            send(event: "dose2")
        }
        updateState()
    }
    
    func logBathroom() {
        send(event: "bathroom")
    }
    
    func snooze() {
        send(event: "snooze")
    }
    
    private func send(event: String) {
#if canImport(WatchConnectivity)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["event": event], replyHandler: nil, errorHandler: { error in
                print("Send failed: \(error)")
            })
        } else {
            print("iPhone not reachable")
        }
#else
        print("WatchConnectivity unavailable; event='\(event)' not sent")
#endif
    }
}

// MARK: - Main Watch View
struct ContentView: View {
    @StateObject private var viewModel = WatchDoseViewModel()
    @State private var showEventsSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Status Card
                    StatusCard(viewModel: viewModel)
                    
                    // Timer Display
                    if viewModel.remainingSeconds > 0 {
                        TimerDisplay(seconds: viewModel.remainingSeconds, phase: viewModel.phase)
                    }
                    
                    // Primary Actions
                    PrimaryActionButtons(viewModel: viewModel)
                    
                    // Quick Event Buttons
                    QuickEventGrid(viewModel: viewModel)
                    
                    // Sync Status
                    SyncStatusBar(viewModel: viewModel)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 20)
            }
            .navigationTitle("DoseTap")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Status Card
struct StatusCard: View {
    @ObservedObject var viewModel: WatchDoseViewModel
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: viewModel.phase.icon)
                .font(.title2)
                .foregroundColor(viewModel.phase.color)
            
            Text(viewModel.phase.displayText)
                .font(.headline)
                .foregroundColor(viewModel.phase.color)
            
            if viewModel.snoozeCount > 0 {
                Text("+\(viewModel.snoozeCount * 10)m snoozed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(viewModel.phase.color.opacity(0.15))
        )
    }
}

// MARK: - Primary Action Buttons
struct PrimaryActionButtons: View {
    @ObservedObject var viewModel: WatchDoseViewModel
    @State private var showSkipConfirm = false
    
    var body: some View {
        VStack(spacing: 8) {
            if viewModel.dose1Time == nil {
                // Dose 1 Button
                Button(action: viewModel.takeDose1) {
                    Label("Take Dose 1", systemImage: "1.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else if viewModel.phase != .completed {
                // Dose 2 Button
                Button(action: viewModel.takeDose2) {
                    Label("Take Dose 2", systemImage: "2.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(viewModel.phase == .beforeWindow || viewModel.phase == .closed)
                
                // Secondary row: Snooze & Skip
                HStack(spacing: 8) {
                    // Snooze
                    Button(action: viewModel.snooze) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canSnooze)
                    
                    // Skip
                    Button(action: { showSkipConfirm = true }) {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
        }
        .confirmationDialog("Skip Dose 2?", isPresented: $showSkipConfirm) {
            Button("Skip", role: .destructive) {
                viewModel.skipDose()
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - Quick Event Grid
struct QuickEventGrid: View {
    @ObservedObject var viewModel: WatchDoseViewModel
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(WatchEventType.allCases, id: \.self) { event in
                Button(action: { viewModel.logEvent(event) }) {
                    VStack(spacing: 2) {
                        Image(systemName: event.icon)
                            .font(.body)
                        Text(event.label)
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(event.color)
            }
        }
    }
}

// MARK: - Timer Display Component
struct TimerDisplay: View {
    let seconds: Int
    let phase: WatchDosePhase
    
    private var timeString: String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
    
    var body: some View {
        VStack(spacing: 2) {
            Text(timeString)
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(phase.color)
            
            Text(phase == .beforeWindow ? "until window opens" : "until window closes")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Sync Status Bar
struct SyncStatusBar: View {
    @ObservedObject var viewModel: WatchDoseViewModel
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.isPhoneReachable ? "iphone" : "iphone.slash")
                .font(.caption2)
                .foregroundColor(viewModel.isPhoneReachable ? .green : .secondary)
            
            if let syncTime = viewModel.lastSyncTime {
                Text("Synced \(syncTime.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                Text("Not synced")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
}