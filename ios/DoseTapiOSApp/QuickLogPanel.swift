import SwiftUI
import Combine
#if canImport(DoseCore)
import DoseCore
#endif

/// Quick log panel for sleep events - displays a grid of event buttons
/// with cooldown states and haptic feedback
public struct QuickLogPanel: View {
    @ObservedObject var viewModel: QuickLogViewModel
    @Environment(\.colorScheme) var colorScheme
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    public init(viewModel: QuickLogViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Log")
                .font(.headline)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(QuickLogEventType.allCases, id: \.rawValue) { eventType in
                    QuickLogButton(
                        eventType: eventType,
                        state: viewModel.buttonState(for: eventType),
                        onTap: {
                            viewModel.logEvent(eventType)
                        }
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }
}

/// Individual button for logging a sleep event
struct QuickLogButton: View {
    let eventType: QuickLogEventType
    let state: QuickLogButtonState
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            if state.isEnabled {
                triggerHaptic()
                onTap()
            }
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(state.isEnabled ? eventType.color.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: eventType.iconName)
                        .font(.system(size: 24))
                        .foregroundColor(state.isEnabled ? eventType.color : .gray)
                    
                    // Cooldown overlay
                    if !state.isEnabled, state.remainingSeconds > 0 {
                        Circle()
                            .trim(from: 0, to: CGFloat(state.remainingSeconds) / CGFloat(eventType.defaultCooldownSeconds))
                            .stroke(eventType.color.opacity(0.3), lineWidth: 3)
                            .frame(width: 56, height: 56)
                            .rotationEffect(.degrees(-90))
                    }
                }
                
                Text(eventType.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(state.isEnabled ? .primary : .gray)
                    .lineLimit(1)
                
                // Show cooldown time remaining
                if !state.isEnabled, state.remainingSeconds > 0 {
                    Text(formatCooldown(state.remainingSeconds))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(ScaleButtonStyle(isEnabled: state.isEnabled))
        .disabled(!state.isEnabled)
        .accessibilityLabel("\(eventType.displayName)")
        .accessibilityHint(state.isEnabled ? "Double tap to log" : "Cooldown: \(state.remainingSeconds) seconds remaining")
    }
    
    private func formatCooldown(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let minutes = seconds / 60
            return "\(minutes)m"
        }
    }
    
    private func triggerHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
}

/// Custom button style with scale animation
struct ScaleButtonStyle: ButtonStyle {
    let isEnabled: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && isEnabled ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - View Model

@MainActor
public class QuickLogViewModel: ObservableObject {
    @Published private(set) var buttonStates: [String: QuickLogButtonState] = [:]
    @Published private(set) var recentEvents: [StoredSleepEvent] = []
    
    private let repository: SessionRepository
    private let rateLimiter: EventRateLimiter
    private var cooldownTimers: [String: Timer] = [:]
    private var dataClearedObserver: NSObjectProtocol?
    
    public var onEventLogged: ((QuickLogEventType) -> Void)?
    
    public init(repository: SessionRepository? = nil, rateLimiter: EventRateLimiter = .default) {
        self.repository = repository ?? SessionRepository.shared
        self.rateLimiter = rateLimiter
        
        // Initialize all button states
        for eventType in QuickLogEventType.allCases {
            buttonStates[eventType.rawValue] = QuickLogButtonState(isEnabled: true, remainingSeconds: 0)
        }
        
        Task {
            await loadCooldownStates()
        }
        
        // Listen for data cleared notification
        dataClearedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DataCleared"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.recentEvents.removeAll()
                print("✅ QuickLogViewModel: Recent events cleared")
            }
        }
    }
    
    deinit {
        cooldownTimers.values.forEach { $0.invalidate() }
        if let observer = dataClearedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    public func buttonState(for eventType: QuickLogEventType) -> QuickLogButtonState {
        buttonStates[eventType.rawValue] ?? QuickLogButtonState(isEnabled: true, remainingSeconds: 0)
    }
    
    public func logEvent(_ eventType: QuickLogEventType) {
        Task {
            let eventKey = eventType.rawValue
            let allowed = await rateLimiter.shouldAllow(event: eventKey)
            
            guard allowed else {
                // Update remaining cooldown
                let remaining = await rateLimiter.remainingCooldown(for: eventKey)
                buttonStates[eventKey] = QuickLogButtonState(isEnabled: false, remainingSeconds: Int(remaining))
                startCooldownTimer(for: eventType)
                return
            }
            
            // Log event via unified storage (SessionRepository)
            let now = Date()
            repository.logSleepEvent(eventType: eventKey, timestamp: now, notes: nil, source: "manual")
            
            // Update local recent events list from storage
            let newEvent = StoredSleepEvent(
                id: UUID().uuidString,
                eventType: eventKey,
                timestamp: now,
                sessionDate: repository.currentSessionKey,
                colorHex: nil,
                notes: nil
            )
            recentEvents.insert(newEvent, at: 0)
            
            // Update button state with cooldown
            buttonStates[eventKey] = QuickLogButtonState(
                isEnabled: false,
                remainingSeconds: Int(eventType.defaultCooldownSeconds)
            )
            
            startCooldownTimer(for: eventType)
            
            // Notify callback
            onEventLogged?(eventType)
            
            // Trigger success haptic
            triggerSuccessHaptic()
        }
    }
    
    private func loadCooldownStates() async {
        for eventType in QuickLogEventType.allCases {
            let remaining = await rateLimiter.remainingCooldown(for: eventType.rawValue)
            if remaining > 0 {
                buttonStates[eventType.rawValue] = QuickLogButtonState(
                    isEnabled: false,
                    remainingSeconds: Int(remaining)
                )
                startCooldownTimer(for: eventType)
            }
        }
        
        // Load recent events via SessionRepository
        recentEvents = repository.fetchTonightSleepEvents()
    }
    
    private func startCooldownTimer(for eventType: QuickLogEventType) {
        let key = eventType.rawValue
        
        // Invalidate existing timer
        cooldownTimers[key]?.invalidate()
        
        // Create new timer that updates every second
        cooldownTimers[key] = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                let remaining = await self.rateLimiter.remainingCooldown(for: key)
                
                if remaining <= 0 {
                    self.buttonStates[key] = QuickLogButtonState(isEnabled: true, remainingSeconds: 0)
                    timer.invalidate()
                    self.cooldownTimers.removeValue(forKey: key)
                } else {
                    self.buttonStates[key] = QuickLogButtonState(isEnabled: false, remainingSeconds: Int(remaining))
                }
            }
        }
    }
    
    private func triggerSuccessHaptic() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
    
    public func refresh() {
        Task {
            await loadCooldownStates()
        }
    }
}

// MARK: - Supporting Types

public struct QuickLogButtonState {
    public let isEnabled: Bool
    public let remainingSeconds: Int
    
    public init(isEnabled: Bool, remainingSeconds: Int) {
        self.isEnabled = isEnabled
        self.remainingSeconds = remainingSeconds
    }
}

/// Subset of sleep event types shown in QuickLog (most common ones)
public enum QuickLogEventType: String, CaseIterable {
    case bathroom
    case water
    case lightsOut
    case wakeFinal
    case wakeTemp
    case anxiety
    case pain
    case noise
    
    public var iconName: String {
        switch self {
        case .bathroom:   return "toilet.fill"
        case .water:      return "drop.fill"
        case .lightsOut:  return "light.max"
        case .wakeFinal:  return "sun.max.fill"
        case .wakeTemp:   return "moon.zzz.fill"
        case .anxiety:    return "brain.head.profile"
        case .pain:       return "bandage.fill"
        case .noise:      return "speaker.wave.3.fill"
        }
    }
    
    public var displayName: String {
        switch self {
        case .bathroom:   return "Bathroom"
        case .water:      return "Water"
        case .lightsOut:  return "Lights Out"
        case .wakeFinal:  return "Wake Up"
        case .wakeTemp:   return "Brief Wake"
        case .anxiety:    return "Anxiety"
        case .pain:       return "Pain"
        case .noise:      return "Noise"
        }
    }
    
    public var defaultCooldownSeconds: TimeInterval {
        switch self {
        case .bathroom:   return 60     // 1 min
        case .water:      return 300    // 5 min
        case .lightsOut:  return 3600   // 1 hour
        case .wakeFinal:  return 3600   // 1 hour
        case .wakeTemp:   return 300    // 5 min
        case .anxiety:    return 300    // 5 min
        case .pain:       return 300    // 5 min
        case .noise:      return 60     // 1 min
        }
    }
    
    public var color: Color {
        switch self {
        case .bathroom:   return .blue
        case .water:      return .cyan
        case .lightsOut:  return .purple
        case .wakeFinal:  return .orange
        case .wakeTemp:   return .indigo
        case .anxiety:    return .pink
        case .pain:       return .red
        case .noise:      return .gray
        }
    }
}

// MARK: - Preview

#if DEBUG
struct QuickLogPanel_Previews: PreviewProvider {
    static var previews: some View {
        QuickLogPanel(viewModel: QuickLogViewModel())
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
#endif
