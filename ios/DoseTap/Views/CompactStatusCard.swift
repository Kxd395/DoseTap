import SwiftUI
import Combine
import DoseCore

// MARK: - Window Closing Countdown View
/// Shown when the Dose 2 window closes in less than 15 minutes. One countdown,
/// the closing clock time and plain wording. The earlier design showed two
/// countdowns, a "HARD STOP" banner and "TAKE DOSE NOW!", which pushed a
/// rushed decision at night (DOSETAP-93).
struct HardStopCountdownView: View {
    let timeRemaining: TimeInterval
    var closesAt: Date? = nil
    var tint: Color = .red
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            if let closesAt {
                Label {
                    Text("Window closes at \(closesAt.formatted(date: .omitted, time: .shortened))")
                        .foregroundColor(.primary)
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundColor(tint)
                }
                .font(.subheadline.weight(.semibold))
            }

            Text(Self.countdownText(timeRemaining))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundColor(.primary)
                .monospacedDigit()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: timeRemaining)
                .accessibilityLabel("\(Int(timeRemaining / 60)) minutes left")

            Text(Self.message(for: timeRemaining))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    static func countdownText(_ timeRemaining: TimeInterval) -> String {
        let clamped = max(0, Int(timeRemaining))
        return String(format: "%d:%02d left", clamped / 60, clamped % 60)
    }

    static func message(for timeRemaining: TimeInterval) -> String {
        timeRemaining < 120
            ? "The window is about to close. Record Dose 2 only if you take it now."
            : "Record Dose 2 before the window closes."
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
                    .foregroundColor(statusColor)
                // Status colors (green, orange, yellow) fail contrast as text on a
                // light card, so the title uses the primary label color.
                Text(statusTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            // Timer (waiting for window to open)
            if core.currentStatus == .beforeWindow, core.dose1Time != nil {
                // P3-10: Progress ring countdown
                ZStack {
                    // Background track
                    Circle()
                        .stroke(Color.orange.opacity(0.15), lineWidth: 6)

                    // Filled progress arc
                    Circle()
                        .trim(from: 0, to: windowProgress)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: windowProgress)

                    // Countdown text inside the ring
                    VStack(spacing: 2) {
                        Text(formatTimeRemaining)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .monospacedDigit()
                            .accessibilityLabel(accessibleTimeRemaining)

                        Text("until window")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 140, height: 140)
                .padding(.vertical, 4)

                Text("Window opens at \(formatWindowOpenTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            // Hard Stop Countdown (near close - <15 min)
            else if core.currentStatus == .nearClose, core.dose1Time != nil {
                HardStopCountdownView(timeRemaining: windowCloseRemaining, closesAt: windowCloseTime, tint: statusColor)
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
    
    /// P3-10: Progress toward window open (0.0 → 1.0 as time elapses)
    private var windowProgress: CGFloat {
        let totalWait = windowOpenMinutes * 60  // 150 min in seconds
        guard totalWait > 0 else { return 1.0 }
        return CGFloat(1.0 - (timeRemaining / totalWait))
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
            return "Dose window is open. " + Self.openWindowDescription(target: plannedTargetTime, closesAt: windowCloseTime)
        case .nearClose:
            let minutes = Int(windowCloseRemaining / 60)
            return "Window closing soon. \(spokenMinutes(minutes)) remaining."
        case .closed:
            return "The planned window ended. The Dose 2 record is unresolved; record what actually happened."
        case .completed:
            return core.isSkipped && core.dose2Time == nil
                ? "Dose 2 is marked missed. You can correct the record if it was actually taken."
                : "Dose 2 occurrence recorded."
        case .finalizing:
            return "Finalizing session. Complete your morning check-in."
        }
    }
    
    private var accessibilityStatusHint: String {
        switch core.currentStatus {
        case .noDose1: return "Double tap to take Dose 1"
        case .beforeWindow: return "Wait for the countdown to finish"
        case .active, .nearClose: return "Double tap to take Dose 2"
        case .closed: return "Complete the unresolved Dose 2 record"
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
        case .closed: return "questionmark.circle"
        case .completed: return "checkmark.seal.fill"
        case .finalizing: return "sunrise.fill"
        }
    }
    
    private var statusTitle: String {
        switch core.currentStatus {
        case .noDose1: return "Ready for Dose 1"
        case .beforeWindow: return "Waiting for Window"
        case .active: return "Window Open"
        case .nearClose: return "Closing Soon"
        case .closed: return "Dose 2 Record Needed"
        case .completed: return "Dose 2 Outcome Recorded"
        case .finalizing: return "Finalizing Session"
        }
    }
    
    private var statusDescription: String {
        switch core.currentStatus {
        case .noDose1: return "Tap below to start"
        case .beforeWindow: return "Wait for optimal timing"
        case .active:
            return Self.openWindowDescription(target: plannedTargetTime, closesAt: windowCloseTime)
        case .nearClose: return "Less than \(TimeIntervalMath.formatMinutes(15)) left"
        case .closed: return "Window ended — record what happened"
        case .completed:
            return core.isSkipped && core.dose2Time == nil ? "Marked missed / not taken" : "Actual occurrence saved ✓"
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
        case .closed: return theme == .night ? theme.warningColor : .orange
        case .completed: return theme == .night ? Color(red: 0.6, green: 0.3, blue: 0.2) : .purple
        case .finalizing: return theme == .night ? theme.warningColor : .orange
        }
    }

    private var windowCloseTime: Date? {
        core.dose1Time?.addingTimeInterval(windowCloseMinutes * 60)
    }

    /// Alarm target after snoozes when known, else Dose 1 plus tonight's interval.
    private var plannedTargetTime: Date? {
        guard let dose1 = core.dose1Time else { return nil }
        return AlarmService.shared.targetWakeTime
            ?? dose1.addingTimeInterval(Double(SessionRepository.shared.activeDoseTargetMinutes) * 60)
    }

    static func openWindowDescription(target: Date?, closesAt: Date?) -> String {
        let format: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
        switch (target, closesAt) {
        case let (target?, closesAt?):
            return "Target \(format(target)) · closes \(format(closesAt))"
        case let (nil, closesAt?):
            return "Window closes at \(format(closesAt))"
        default:
            return "Record Dose 2 when you take it"
        }
    }
}
