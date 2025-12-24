// iOS/ActionableNotifications.swift
// This file is iOS-only and should not be compiled for macOS
#if os(iOS)
import SwiftUI
import UserNotifications
import UIKit

// MARK: - Actionable Notification Views

@available(iOS 13.0, *)
struct DoseNotificationBanner: View {
    let timeRemaining: Int // minutes
    let isSnoozeDisabled: Bool
    let isCritical: Bool
    let onTakeDose: () -> Void
    let onSnoozeDose: () -> Void
    let onSkipDose: () -> Void
    
    @State private var showingConfirmation = false
    @State private var selectedAction: DoseAction?
    
    enum DoseAction {
        case take, snooze, skip
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text(isCritical ? "⚠️ DoseTap - CRITICAL" : "DoseTap")
                    .font(isCritical ? .headline.bold() : .headline)
                    .foregroundColor(isCritical ? .red : .primary)
                Spacer()
            }
            
            // Message
            Text("Take Dose 2 — \(timeRemaining)m left")
                .font(.title3)
                .foregroundColor(.primary)
            
            // Action Buttons
            HStack(spacing: 12) {
                // Take Now - Primary Action
                Button("Take Now") {
                    selectedAction = .take
                    handleDoseAction(.take)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityHint("Take dose 2 now")
                
                if !isSnoozeDisabled {
                    Button("Snooze +10m") {
                        selectedAction = .snooze
                        handleDoseAction(.snooze)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .accessibilityHint("Delay dose by 10 minutes")
                }
                
                Button("Skip") {
                    selectedAction = .skip
                    showingConfirmation = true
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .accessibilityHint("Skip this dose")
            }
            
            if isSnoozeDisabled && timeRemaining < 15 {
                Text("Snooze unavailable (<15m)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Snooze unavailable, less than 15 minutes remaining")
            }
            
            if isCritical {
                Text("This alert stays until you take action.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isCritical ? Color.red.opacity(0.1) : Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .alert("Skip Dose?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Skip Dose", role: .destructive) {
                handleDoseAction(.skip)
            }
        } message: {
            Text("Are you sure you want to skip this dose? This action cannot be undone.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(createAccessibilityLabel())
    }
    
    private func handleDoseAction(_ action: DoseAction) {
        // Integration with existing dose handling logic
        switch action {
        case .take:
            recordDoseEvent(type: "dose2", source: "notification_banner")
        case .snooze:
            scheduleSnoozeReminder()
        case .skip:
            recordDoseEvent(type: "skip", source: "notification_banner")
        }
    }
    
    private func recordDoseEvent(type: String, source: String) {
        let store = EventStoreCoreData()
        store.insertEvent(
            id: UUID().uuidString,
            type: type,
            source: source,
            occurredAtUTC: Date(),
            localTZ: TimeZone.current.identifier,
            doseSequence: type == "dose2" ? 2 : nil,
            note: nil
        )
    }
    
    private func scheduleSnoozeReminder() {
        // Schedule notification for 10 minutes from now
@available(iOS 10.0, *)
func scheduleNotificationReminder() {
    let content = UNMutableNotificationContent()
    content.title = "Dose Reminder"
    content.body = "Your dose window is still open. Don't forget to take your medication."
    content.sound = .default
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
    let request = UNNotificationRequest(identifier: "snooze_reminder", content: content, trigger: trigger)
    
    UNUserNotificationCenter.current().add(request)
}        // Record snooze event
        recordDoseEvent(type: "snooze", source: "notification_banner")
    }
    
    private func createAccessibilityLabel() -> String {
        var label = isCritical ? "Critical alert. " : ""
        label += "Dose two due in \(timeRemaining) minutes. "
        label += "Take Now. "
        
        if !isSnoozeDisabled {
            label += "Snooze plus ten minutes. "
        } else {
            label += "Snooze unavailable. "
        }
        
        label += "Skip."
        
        if isCritical {
            label += " This alert stays until you take action."
        }
        
        return label
    }
}

// MARK: - Button Styles

@available(iOS 13.0, *)
struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue)
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

@available(iOS 13.0, *)
struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.blue)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 1)
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Notification Manager

@available(iOS 13.0, *)
class NotificationBannerManager: ObservableObject {
    @Published var showBanner = false
    @Published var timeRemaining = 0
    @Published var isSnoozeDisabled = false
    @Published var isCritical = false
    
    private var timer: Timer?
    
    func startDoseWindow(targetInterval: Int = 165) {
        timeRemaining = targetInterval
        showBanner = true
        startTimer()
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            DispatchQueue.main.async {
                if self.timeRemaining > 0 {
                    self.timeRemaining -= 1
                    self.updateNotificationState()
                } else {
                    self.endDoseWindow()
                }
            }
        }
    }
    
    private func updateNotificationState() {
        isSnoozeDisabled = timeRemaining < 15
        isCritical = timeRemaining <= 10
    }
    
    private func endDoseWindow() {
        timer?.invalidate()
        showBanner = false
        timeRemaining = 0
        isSnoozeDisabled = false
        isCritical = false
    }
    
    deinit {
        timer?.invalidate()
    }
}

// MARK: - Integration View

struct NotificationDemoView: View {
    @StateObject private var notificationManager = NotificationBannerManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Actionable Notifications Demo")
                    .font(.title)
                    .fontWeight(.bold)
                
                VStack(spacing: 16) {
                    Button("Start Normal Window (42m)") {
                        notificationManager.timeRemaining = 42
                        notificationManager.isSnoozeDisabled = false
                        notificationManager.isCritical = false
                        notificationManager.showBanner = true
                    }
                    
                    Button("Show Snooze Disabled (8m)") {
                        notificationManager.timeRemaining = 8
                        notificationManager.isSnoozeDisabled = true
                        notificationManager.isCritical = false
                        notificationManager.showBanner = true
                    }
                    
                    Button("Show Critical Alert (3m)") {
                        notificationManager.timeRemaining = 3
                        notificationManager.isSnoozeDisabled = true
                        notificationManager.isCritical = true
                        notificationManager.showBanner = true
                    }
                    
                    Button("Hide Banner") {
                        notificationManager.showBanner = false
                    }
                }
                
                if notificationManager.showBanner {
                    DoseNotificationBanner(
                        timeRemaining: notificationManager.timeRemaining,
                        isSnoozeDisabled: notificationManager.isSnoozeDisabled,
                        isCritical: notificationManager.isCritical
                    )
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Notifications")
        }
    }
}

#endif // os(iOS)
