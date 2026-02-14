import SwiftUI
import DoseCore

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
