import SwiftUI

/// Actionable notification banners for dose management
/// Implements ASCII specifications for in-app notifications with Take/Snooze/Skip actions

/// Main notification banner component for dose alerts
struct DoseNotificationBanner: View {
    let timeRemaining: Int // minutes
    let isSnoozeDisabled: Bool
    let isCritical: Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessingAction = false
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            actionButtons
            if isCritical {
                persistentAlertMessage
            }
        }
        .padding()
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: isCritical ? 2 : 1)
        )
        .cornerRadius(12)
        .shadow(elevation: isCritical ? .high : .medium)
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                if isCritical {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .accessibilityLabel("Critical alert")
                }
                
                Text("DoseTap")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            HStack {
                Text(timeRemainingText)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Primary action - Take Now
            Button(action: handleTakeNow) {
                Text("Take Now")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(isProcessingAction)
            .accessibilityLabel("Take dose two now")
            
            if !isSnoozeDisabled {
                // Secondary action - Snooze
                Button(action: handleSnooze) {
                    Text("Snooze +10m")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(Color(.controlColor))
                .cornerRadius(8)
                .disabled(isProcessingAction)
                .accessibilityLabel("Snooze for ten more minutes")
            }
            
            // Tertiary action - Skip
            Button(action: handleSkip) {
                Text("Skip")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(Color(.controlColor))
            .cornerRadius(8)
            .disabled(isProcessingAction)
            .accessibilityLabel("Skip dose two")
        }
        .padding(.top, 12)
    }
    
    private var persistentAlertMessage: some View {
        Text("This alert stays until you take action.")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
            .accessibilityLabel("This alert stays until you take action")
    }
    
    private var snoozeUnavailableMessage: some View {
        Text("Snooze unavailable (<15m)")
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.top, 4)
            .accessibilityLabel("Snooze unavailable, less than fifteen minutes remaining")
    }
    
    // MARK: - Computed Properties
    
    private var timeRemainingText: String {
        if isCritical && timeRemaining <= 3 {
            return "Dose window closing in \(timeRemaining)m"
        } else {
            return "Take Dose 2 — \(timeRemaining)m left"
        }
    }
    
    private var backgroundColor: Color {
        if isCritical {
            return Color.orange.opacity(0.1)
        } else {
            return Color(.controlBackgroundColor)
        }
    }
    
    private var borderColor: Color {
        if isCritical {
            return .orange
        } else {
            return Color(.separatorColor)
        }
    }
    
    // MARK: - Actions
    
    private func handleTakeNow() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isProcessingAction = true
        }
        
        // Simulate action processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("📋 Taking Dose 2 now")
            dismiss()
        }
    }
    
    private func handleSnooze() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isProcessingAction = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("⏰ Snoozing for 10 minutes")
            dismiss()
        }
    }
    
    private func handleSkip() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isProcessingAction = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("⏭️ Skipping Dose 2")
            dismiss()
        }
    }
}

/// Shadow elevation levels for consistent visual hierarchy
enum ShadowElevation {
    case low, medium, high
    
    var radius: CGFloat {
        switch self {
        case .low: return 2
        case .medium: return 4
        case .high: return 8
        }
    }
    
    var offset: CGSize {
        switch self {
        case .low: return CGSize(width: 0, height: 1)
        case .medium: return CGSize(width: 0, height: 2)
        case .high: return CGSize(width: 0, height: 4)
        }
    }
}

extension View {
    func shadow(elevation: ShadowElevation) -> some View {
        self.shadow(color: .black.opacity(0.1), radius: elevation.radius, x: elevation.offset.width, y: elevation.offset.height)
    }
}

/// Notification overlay container for presenting banners
struct NotificationOverlay: View {
    @State private var showNotification = false
    @State private var notificationInfo: DoseNotificationInfo?
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            
            if let info = notificationInfo, showNotification {
                DoseNotificationBanner(
                    timeRemaining: info.timeRemaining,
                    isSnoozeDisabled: info.isSnoozeDisabled,
                    isCritical: info.isCritical
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showNotification)
                .zIndex(1000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDoseNotification)) { notification in
            if let info = notification.object as? DoseNotificationInfo {
                presentNotification(info)
            }
        }
    }
    
    private func presentNotification(_ info: DoseNotificationInfo) {
        notificationInfo = info
        withAnimation {
            showNotification = true
        }
        
        // Auto-dismiss non-critical notifications after 10 seconds
        if !info.isCritical {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                dismissNotification()
            }
        }
    }
    
    private func dismissNotification() {
        withAnimation {
            showNotification = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            notificationInfo = nil
        }
    }
}

/// Data model for notification information
struct DoseNotificationInfo {
    let timeRemaining: Int
    let isSnoozeDisabled: Bool
    let isCritical: Bool
    
    init(timeRemaining: Int) {
        self.timeRemaining = timeRemaining
        self.isSnoozeDisabled = timeRemaining < 15
        self.isCritical = timeRemaining <= 10
    }
}

/// Notification name for dose alerts
extension Notification.Name {
    static let showDoseNotification = Notification.Name("showDoseNotification")
}

/// Helper for triggering notifications
struct NotificationTrigger {
    static func showDoseReminder(timeRemaining: Int) {
        let info = DoseNotificationInfo(timeRemaining: timeRemaining)
        NotificationCenter.default.post(
            name: .showDoseNotification,
            object: info
        )
    }
}

#Preview("Active Notification") {
    VStack(spacing: 20) {
        DoseNotificationBanner(
            timeRemaining: 42,
            isSnoozeDisabled: false,
            isCritical: false
        )
        
        Text("Regular notification with all actions available")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Snooze Disabled") {
    VStack(spacing: 20) {
        DoseNotificationBanner(
            timeRemaining: 8,
            isSnoozeDisabled: true,
            isCritical: false
        )
        
        Text("Snooze disabled when less than 15 minutes remain")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

#Preview("Critical Alert") {
    VStack(spacing: 20) {
        DoseNotificationBanner(
            timeRemaining: 3,
            isSnoozeDisabled: true,
            isCritical: true
        )
        
        Text("Critical alert with persistent messaging")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
    .background(Color(.windowBackgroundColor))
}

/// Demo view for testing notification banners
struct NotificationDemoView: View {
    @State private var timeRemaining = 42
    @State private var showBanner = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Notification Banner Demo")
                    .font(.title)
                    .fontWeight(.bold)
                
                VStack(spacing: 20) {
                    Text("Time Remaining: \(timeRemaining) minutes")
                        .font(.headline)
                    
                    Slider(value: Binding(
                        get: { Double(timeRemaining) },
                        set: { timeRemaining = Int($0) }
                    ), in: 1...60, step: 1)
                    .frame(width: 300)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(12)
                
                VStack(spacing: 16) {
                    Button("Show Normal Notification") {
                        showTestNotification(timeRemaining: max(16, timeRemaining))
                    }
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button("Show Snooze Disabled (< 15m)") {
                        showTestNotification(timeRemaining: min(14, timeRemaining))
                    }
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    
                    Button("Show Critical Alert (≤ 10m)") {
                        showTestNotification(timeRemaining: min(10, timeRemaining))
                    }
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                if showBanner {
                    DoseNotificationBanner(
                        timeRemaining: timeRemaining,
                        isSnoozeDisabled: timeRemaining < 15,
                        isCritical: timeRemaining <= 10
                    )
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Notification Demo")
        }
    }
    
    private func showTestNotification(timeRemaining: Int) {
        self.timeRemaining = timeRemaining
        withAnimation(.easeInOut(duration: 0.3)) {
            showBanner = true
        }
        
        // Auto-hide after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showBanner = false
            }
        }
    }
}
