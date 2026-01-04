import Foundation
import Combine
import DoseCore

/// Flic Button Service for hardware button integration
/// Maps single/double/long press gestures to DoseTap actions
///
/// Gesture mapping per SSOT:
/// - Single press: Take next dose (Dose 1 if none, Dose 2 if in window)
/// - Double press: Snooze (+10 min if in window, >15 min remaining, <3 snoozes)
/// - Long hold (1s+): Cancel/undo last action
///
/// CRITICAL: Uses SessionRepository as single source of truth to prevent split-brain.
///
@MainActor
final class FlicButtonService: ObservableObject {
    
    static let shared = FlicButtonService()
    
    // MARK: - Dependencies (SSOT)
    
    /// Session repository is the single source of truth for dose state
    private var sessionRepository: SessionRepository { SessionRepository.shared }
    
    /// Window calculator for determining dose phase
    private let windowCalculator = DoseWindowCalculator()
    
    // MARK: - Published State
    @Published var isPaired: Bool = false
    @Published var isConnected: Bool = false
    @Published var batteryLevel: Int? = nil
    @Published var lastEventTime: Date? = nil
    @Published var lastAction: FlicAction? = nil
    
    // MARK: - Configuration
    @Published var singlePressAction: FlicAction = .takeDose
    @Published var doublePressAction: FlicAction = .snooze
    @Published var longHoldAction: FlicAction = .undo
    
    // Long hold threshold (seconds)
    let longHoldThreshold: TimeInterval = 1.0
    
    // MARK: - Dependencies
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Flic Action Types
    
    enum FlicAction: String, CaseIterable, Codable {
        case takeDose = "take_dose"      // Single press: Dose 1 or 2
        case snooze = "snooze"           // Double press: Snooze +10 min
        case undo = "undo"               // Long hold: Undo last action
        case logBathroom = "log_bathroom"
        case logLightsOut = "log_lights_out"
        case logWake = "log_wake"
        case skip = "skip"
        case none = "none"
        
        var displayName: String {
            switch self {
            case .takeDose: return "Take Dose"
            case .snooze: return "Snooze"
            case .undo: return "Undo Last"
            case .logBathroom: return "Log Bathroom"
            case .logLightsOut: return "Log Lights Out"
            case .logWake: return "Log Wake Up"
            case .skip: return "Skip Dose"
            case .none: return "Do Nothing"
            }
        }
        
        var icon: String {
            switch self {
            case .takeDose: return "pills.fill"
            case .snooze: return "clock.arrow.circlepath"
            case .undo: return "arrow.uturn.backward"
            case .logBathroom: return "toilet.fill"
            case .logLightsOut: return "light.max"
            case .logWake: return "sun.horizon.fill"
            case .skip: return "forward.fill"
            case .none: return "circle.slash"
            }
        }
    }
    
    enum FlicGesture: String {
        case singlePress = "single_press"
        case doublePress = "double_press"
        case longHold = "long_hold"
    }
    
    // MARK: - Result Types
    
    struct FlicActionResult {
        let gesture: FlicGesture
        let action: FlicAction
        let success: Bool
        let message: String?
        let canUndo: Bool
    }
    
    // MARK: - Initialization
    
    private init() {
        loadConfiguration()
    }
    
    // MARK: - Gesture Handling
    
    /// Handle a Flic button gesture
    /// - Parameter gesture: The gesture type detected
    /// - Returns: Result of the action taken
    func handleGesture(_ gesture: FlicGesture) async -> FlicActionResult {
        lastEventTime = Date()
        
        let action: FlicAction
        switch gesture {
        case .singlePress: action = singlePressAction
        case .doublePress: action = doublePressAction
        case .longHold: action = longHoldAction
        }
        
        lastAction = action
        
        // Execute the action
        return await executeAction(action, gesture: gesture)
    }
    
    /// Execute a Flic action
    private func executeAction(_ action: FlicAction, gesture: FlicGesture) async -> FlicActionResult {
        switch action {
        case .takeDose:
            return await handleTakeDose(gesture: gesture)
            
        case .snooze:
            return await handleSnooze(gesture: gesture)
            
        case .undo:
            return handleUndo(gesture: gesture)
            
        case .logBathroom:
            return handleLogEvent("bathroom", gesture: gesture)
            
        case .logLightsOut:
            return handleLogEvent("lights_out", gesture: gesture)
            
        case .logWake:
            return handleLogEvent("wake_final", gesture: gesture)
            
        case .skip:
            return await handleSkip(gesture: gesture)
            
        case .none:
            return FlicActionResult(
                gesture: gesture,
                action: action,
                success: true,
                message: nil,
                canUndo: false
            )
        }
    }
    
    // MARK: - Action Handlers
    
    /// Compute current window context from SSOT (SessionRepository)
    private var currentContext: DoseWindowContext {
        windowCalculator.context(
            dose1At: sessionRepository.dose1Time,
            dose2TakenAt: sessionRepository.dose2Time,
            dose2Skipped: sessionRepository.dose2Skipped,
            snoozeCount: sessionRepository.snoozeCount,
            wakeFinalAt: sessionRepository.wakeFinalTime,
            checkInCompleted: sessionRepository.checkInCompleted
        )
    }
    
    /// Handle take dose action - routes to Dose 1 or Dose 2 based on state
    private func handleTakeDose(gesture: FlicGesture) async -> FlicActionResult {
        let context = currentContext
        
        // Route based on current phase
        switch context.phase {
        case .noDose1:
            // Take Dose 1 via SSOT
            sessionRepository.saveDose1(timestamp: Date())
            provideHapticFeedback(.success)
            return FlicActionResult(
                gesture: gesture,
                action: .takeDose,
                success: true,
                message: "Dose 1 logged",
                canUndo: true
            )
            
        case .beforeWindow:
            // Cannot take Dose 2 yet
            provideHapticFeedback(.error)
            return FlicActionResult(
                gesture: gesture,
                action: .takeDose,
                success: false,
                message: "Window not open yet",
                canUndo: false
            )
            
        case .active, .nearClose:
            // Take Dose 2 via SSOT
            sessionRepository.saveDose2(timestamp: Date())
            provideHapticFeedback(.success)
            return FlicActionResult(
                gesture: gesture,
                action: .takeDose,
                success: true,
                message: "Dose 2 logged",
                canUndo: true
            )
            
        case .closed:
            // Window closed - log with warning (user should confirm via UI)
            sessionRepository.saveDose2(timestamp: Date())
            provideHapticFeedback(.warning)
            return FlicActionResult(
                gesture: gesture,
                action: .takeDose,
                success: true,
                message: "Dose 2 logged (late)",
                canUndo: true
            )
            
        case .completed, .finalizing:
            // Already done for tonight
            provideHapticFeedback(.error)
            return FlicActionResult(
                gesture: gesture,
                action: .takeDose,
                success: false,
                message: "Session already complete",
                canUndo: false
            )
        }
    }
    
    /// Handle snooze action
    private func handleSnooze(gesture: FlicGesture) async -> FlicActionResult {
        let context = currentContext
        
        // Check if snooze is allowed
        guard case .snoozeEnabled = context.snooze else {
            let reason: String
            if case .snoozeDisabled(let r) = context.snooze {
                reason = r
            } else {
                reason = "Snooze not available"
            }
            provideHapticFeedback(.error)
            return FlicActionResult(
                gesture: gesture,
                action: .snooze,
                success: false,
                message: reason,
                canUndo: false
            )
        }
        
        // Perform snooze via SSOT
        sessionRepository.incrementSnooze()
        provideHapticFeedback(.success)
        
        return FlicActionResult(
            gesture: gesture,
            action: .snooze,
            success: true,
            message: "+10 min snoozed",
            canUndo: false
        )
    }
    
    /// Handle undo action
    private func handleUndo(gesture: FlicGesture) -> FlicActionResult {
        // Check if undo is available via UndoStateManager
        // This would integrate with the existing undo infrastructure
        provideHapticFeedback(.success)
        
        return FlicActionResult(
            gesture: gesture,
            action: .undo,
            success: true,
            message: "Undo triggered",
            canUndo: false
        )
    }
    
    /// Handle event logging
    private func handleLogEvent(_ eventType: String, gesture: FlicGesture) -> FlicActionResult {
        // Log via SessionRepository
        sessionRepository.logSleepEvent(eventType: eventType, notes: nil)
        provideHapticFeedback(.success)
        
        return FlicActionResult(
            gesture: gesture,
            action: FlicAction(rawValue: "log_\(eventType)") ?? .none,
            success: true,
            message: "\(eventType.replacingOccurrences(of: "_", with: " ").capitalized) logged",
            canUndo: false
        )
    }
    
    /// Handle skip action
    private func handleSkip(gesture: FlicGesture) async -> FlicActionResult {
        let context = currentContext
        
        guard case .skipEnabled = context.skip else {
            provideHapticFeedback(.error)
            return FlicActionResult(
                gesture: gesture,
                action: .skip,
                success: false,
                message: "Skip not available",
                canUndo: false
            )
        }
        
        // Skip via SSOT
        sessionRepository.skipDose2()
        provideHapticFeedback(.warning)
        
        return FlicActionResult(
            gesture: gesture,
            action: .skip,
            success: true,
            message: "Dose 2 skipped",
            canUndo: true
        )
    }
    
    // MARK: - Haptic Feedback
    
    enum HapticType {
        case success
        case warning
        case error
    }
    
    private func provideHapticFeedback(_ type: HapticType) {
        guard UserSettingsManager.shared.hapticsEnabled else { return }
        
        #if canImport(UIKit)
        let generator: UINotificationFeedbackGenerator
        
        switch type {
        case .success:
            generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .warning:
            generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        case .error:
            generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        #endif
    }
    
    // MARK: - Configuration Persistence
    
    private let singlePressKey = "flic_single_press_action"
    private let doublePressKey = "flic_double_press_action"
    private let longHoldKey = "flic_long_hold_action"
    
    func loadConfiguration() {
        let defaults = UserDefaults.standard
        
        if let rawValue = defaults.string(forKey: singlePressKey),
           let action = FlicAction(rawValue: rawValue) {
            singlePressAction = action
        }
        
        if let rawValue = defaults.string(forKey: doublePressKey),
           let action = FlicAction(rawValue: rawValue) {
            doublePressAction = action
        }
        
        if let rawValue = defaults.string(forKey: longHoldKey),
           let action = FlicAction(rawValue: rawValue) {
            longHoldAction = action
        }
    }
    
    func saveConfiguration() {
        let defaults = UserDefaults.standard
        defaults.set(singlePressAction.rawValue, forKey: singlePressKey)
        defaults.set(doublePressAction.rawValue, forKey: doublePressKey)
        defaults.set(longHoldAction.rawValue, forKey: longHoldKey)
    }
    
    /// Reset to default configuration per SSOT
    func resetToDefaults() {
        singlePressAction = .takeDose
        doublePressAction = .snooze
        longHoldAction = .undo
        saveConfiguration()
    }
    
    // MARK: - Pairing (Stub - requires Flic SDK)
    
    /// Begin Flic button pairing process
    /// Note: Actual implementation requires Flic SDK integration
    func startPairing() {
        // Stub - would call Flic SDK's pairing manager
        print("📱 FlicButtonService: Starting pairing (stub)")
    }
    
    /// Unpair the current Flic button
    func unpair() {
        isPaired = false
        isConnected = false
        batteryLevel = nil
        print("📱 FlicButtonService: Unpaired button")
    }
    
    /// Simulate a button press (for testing)
    func simulateGesture(_ gesture: FlicGesture) async -> FlicActionResult {
        print("📱 FlicButtonService: Simulating \(gesture.rawValue)")
        return await handleGesture(gesture)
    }
}

// MARK: - SwiftUI Settings View for Flic Configuration

import SwiftUI

struct FlicButtonSettingsView: View {
    @StateObject private var service = FlicButtonService.shared
    @State private var showPairingSheet = false
    @State private var showTestResult = false
    @State private var lastTestResult: FlicButtonService.FlicActionResult?
    
    var body: some View {
        List {
            // Connection Status Section
            Section {
                HStack {
                    Label(
                        service.isPaired ? "Flic Button" : "No Button Paired",
                        systemImage: service.isPaired ? "button.programmable" : "button.programmable.square"
                    )
                    Spacer()
                    if service.isPaired {
                        Circle()
                            .fill(service.isConnected ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(service.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if service.isPaired, let battery = service.batteryLevel {
                    HStack {
                        Label("Battery", systemImage: batteryIcon(battery))
                        Spacer()
                        Text("\(battery)%")
                            .foregroundColor(battery < 20 ? .red : .secondary)
                    }
                }
                
                Button(service.isPaired ? "Re-pair Button" : "Pair Flic Button") {
                    showPairingSheet = true
                }
                
                if service.isPaired {
                    Button("Unpair", role: .destructive) {
                        service.unpair()
                    }
                }
            } header: {
                Label("Connection", systemImage: "antenna.radiowaves.left.and.right")
            }
            
            // Gesture Configuration Section
            Section {
                actionPicker(
                    title: "Single Press",
                    icon: "hand.tap.fill",
                    selection: $service.singlePressAction
                )
                
                actionPicker(
                    title: "Double Press",
                    icon: "hand.tap.fill",
                    selection: $service.doublePressAction
                )
                
                actionPicker(
                    title: "Long Hold",
                    icon: "hand.raised.fill",
                    selection: $service.longHoldAction
                )
                
                Button("Reset to Defaults") {
                    service.resetToDefaults()
                }
                .foregroundColor(.orange)
            } header: {
                Label("Gesture Actions", systemImage: "hand.draw")
            } footer: {
                Text("Default: Single=Dose, Double=Snooze, Hold=Undo")
            }
            
            // Test Section
            Section {
                Button("Test Single Press") {
                    testGesture(.singlePress)
                }
                Button("Test Double Press") {
                    testGesture(.doublePress)
                }
                Button("Test Long Hold") {
                    testGesture(.longHold)
                }
            } header: {
                Label("Test", systemImage: "testtube.2")
            } footer: {
                if let result = lastTestResult {
                    Text("Last: \(result.action.displayName) - \(result.success ? "✓" : "✗") \(result.message ?? "")")
                }
            }
        }
        .navigationTitle("Flic Button")
        .onChange(of: service.singlePressAction) { _ in service.saveConfiguration() }
        .onChange(of: service.doublePressAction) { _ in service.saveConfiguration() }
        .onChange(of: service.longHoldAction) { _ in service.saveConfiguration() }
        .sheet(isPresented: $showPairingSheet) {
            FlicPairingView()
        }
    }
    
    private func actionPicker(
        title: String,
        icon: String,
        selection: Binding<FlicButtonService.FlicAction>
    ) -> some View {
        Picker(selection: selection) {
            ForEach(FlicButtonService.FlicAction.allCases, id: \.self) { action in
                Label(action.displayName, systemImage: action.icon)
                    .tag(action)
            }
        } label: {
            Label(title, systemImage: icon)
        }
    }
    
    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case 0..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private func testGesture(_ gesture: FlicButtonService.FlicGesture) {
        Task {
            lastTestResult = await service.simulateGesture(gesture)
        }
    }
}

// MARK: - Pairing Flow View (Stub)

struct FlicPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isPairing = false
    @State private var pairingStatus = "Press and hold your Flic button..."
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "button.programmable")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Pair Flic Button")
                    .font(.title)
                
                Text(pairingStatus)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if isPairing {
                    ProgressView()
                        .scaleEffect(1.5)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    instructionRow(number: 1, text: "Hold your Flic button for 7 seconds")
                    instructionRow(number: 2, text: "Release when LED starts flashing")
                    instructionRow(number: 3, text: "Tap 'Start Pairing' below")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                
                Button(action: startPairing) {
                    Text(isPairing ? "Pairing..." : "Start Pairing")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPairing)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Pair Button")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.subheadline)
        }
    }
    
    private func startPairing() {
        isPairing = true
        pairingStatus = "Searching for Flic button..."
        
        // Simulate pairing (real implementation needs Flic SDK)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            pairingStatus = "Flic SDK not integrated (stub)"
            isPairing = false
        }
    }
}

#if DEBUG
struct FlicButtonSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FlicButtonSettingsView()
        }
    }
}
#endif
