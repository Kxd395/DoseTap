import SwiftUI
import DoseCore
import os.log

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
