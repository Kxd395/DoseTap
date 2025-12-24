import SwiftUI
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - Dose Phase (matches iOS DoseStatus)
enum WatchDosePhase: String {
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
        case .nearClose: return "Window Closing!"
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
}

// MARK: - Watch View Model
@MainActor
class WatchDoseViewModel: ObservableObject {
    @Published var phase: WatchDosePhase = .noDose1
    @Published var dose1Time: Date?
    @Published var dose2Time: Date?
    @Published var remainingSeconds: Int = 0
    
    private var timer: Timer?
    
    // Core timing constants (per SSOT)
    private let minIntervalMinutes = 150
    private let maxIntervalMinutes = 240
    
    init() {
        startTimer()
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
        
        if elapsedMinutes < minIntervalMinutes {
            // Before window opens
            phase = .beforeWindow
            let windowOpensAt = d1.addingTimeInterval(Double(minIntervalMinutes) * 60)
            remainingSeconds = max(0, Int(windowOpensAt.timeIntervalSince(now)))
        } else if elapsedMinutes < maxIntervalMinutes - 15 {
            // Window is open
            phase = .active
            let windowClosesAt = d1.addingTimeInterval(Double(maxIntervalMinutes) * 60)
            remainingSeconds = max(0, Int(windowClosesAt.timeIntervalSince(now)))
        } else if elapsedMinutes < maxIntervalMinutes {
            // Near close (< 15 min remaining)
            phase = .nearClose
            let windowClosesAt = d1.addingTimeInterval(Double(maxIntervalMinutes) * 60)
            remainingSeconds = max(0, Int(windowClosesAt.timeIntervalSince(now)))
        } else {
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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Status Header
                Text(viewModel.phase.displayText)
                    .font(.headline)
                    .foregroundColor(viewModel.phase.color)
                
                // Timer Display
                if viewModel.remainingSeconds > 0 {
                    TimerDisplay(seconds: viewModel.remainingSeconds, phase: viewModel.phase)
                }
                
                // Primary Action Button
                Button(action: viewModel.takeDose) {
                    HStack {
                        Image(systemName: viewModel.dose1Time == nil ? "1.circle.fill" : "2.circle.fill")
                        Text(viewModel.dose1Time == nil ? "Take Dose 1" : "Take Dose 2")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.phase.color)
                .disabled(viewModel.phase == .closed || viewModel.phase == .completed)
                
                // Secondary Actions
                HStack(spacing: 8) {
                    Button(action: viewModel.logBathroom) {
                        Image(systemName: "toilet.fill")
                    }
                    .buttonStyle(.bordered)
                    
                    if viewModel.phase == .active {
                        Button(action: viewModel.snooze) {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding()
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
                .font(.system(.title, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(phase.color)
            
            Text(phase == .beforeWindow ? "until window opens" : "until window closes")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}