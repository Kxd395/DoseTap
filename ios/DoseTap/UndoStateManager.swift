import SwiftUI
import DoseCore

// MARK: - Undo State Manager (Observable)
/// Observable wrapper around DoseUndoManager for SwiftUI integration.
/// Manages undo snackbar visibility, countdown timer, and state.
@available(iOS 15.0, *)
@MainActor
class UndoStateManager: ObservableObject {
    @Published var currentAction: UndoableAction?
    @Published var remainingTime: TimeInterval = 0
    @Published var isVisible: Bool = false
    
    private var undoManager: DoseUndoManager?
    private var countdownTimer: Timer?
    private var totalTime: TimeInterval = 5.0
    
    var onCommit: ((UndoableAction) -> Void)?
    var onUndo: ((UndoableAction) -> Void)?
    
    init() {
        // Use user's configured undo window
        let windowSeconds = UserSettingsManager.shared.undoWindowSeconds
        self.totalTime = windowSeconds
        
        // Create undo manager with configured window
        self.undoManager = DoseUndoManager(windowSeconds: windowSeconds)
        
        // Setup callbacks
        Task {
            await setupCallbacks()
        }
    }
    
    private func setupCallbacks() async {
        await undoManager?.setCallbacks(
            onCommit: { [weak self] action in
                Task { @MainActor in
                    self?.handleCommit(action)
                }
            },
            onUndo: { [weak self] action in
                Task { @MainActor in
                    self?.handleUndo(action)
                }
            }
        )
    }
    
    func register(_ action: UndoableAction) {
        Task {
            // Update window from settings each time
            totalTime = UserSettingsManager.shared.undoWindowSeconds
            
            if let manager = undoManager {
                await MainActor.run {
                    currentAction = action
                    remainingTime = totalTime
                    isVisible = true
                    startCountdown()
                    
                    // Diagnostic logging: undo window opened
                    let sessionId = SessionRepository.shared.currentSessionDateString()
                    let targetType = undoTargetType(for: action)
                    Task {
                        await DiagnosticLogger.shared.logUndoWindowOpened(sessionId: sessionId, targetType: targetType)
                    }
                }
                
                await manager.register(action)
            }
        }
    }
    
    func performUndo() {
        Task {
            if let manager = undoManager {
                let action = currentAction
                let result = await manager.undo()
                await MainActor.run {
                    #if DEBUG
                    switch result {
                    case .success(let action):
                        Swift.print("✅ Undo successful: \(action)")
                    case .expired:
                        Swift.print("⏰ Undo window expired")
                    case .noAction:
                        Swift.print("⚠️ No action to undo")
                    }
                    #endif
                    
                    // Diagnostic logging: undo executed
                    if case .success = result, let action = action {
                        let sessionId = SessionRepository.shared.currentSessionDateString()
                        let targetType = undoTargetType(for: action)
                        Task {
                            await DiagnosticLogger.shared.logUndoExecuted(sessionId: sessionId, targetType: targetType)
                        }
                    }
                    
                    dismiss()
                }
            }
        }
    }
    
    func dismiss() {
        stopCountdown()
        isVisible = false
        currentAction = nil
    }
    
    // MARK: - Private
    
    private func startCountdown() {
        stopCountdown()
        
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.remainingTime -= 0.1
                
                if self.remainingTime <= 0 {
                    self.dismiss()
                }
            }
        }
    }
    
    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
    
    private func handleCommit(_ action: UndoableAction) {
        // Diagnostic logging: undo expired (user didn't press undo)
        let sessionId = SessionRepository.shared.currentSessionDateString()
        let targetType = undoTargetType(for: action)
        Task {
            await DiagnosticLogger.shared.logUndoExpired(sessionId: sessionId, targetType: targetType)
        }
        
        onCommit?(action)
        dismiss()
    }
    
    private func handleUndo(_ action: UndoableAction) {
        onUndo?(action)
        dismiss()
    }
    
    /// Convert action to target type string for logging
    private func undoTargetType(for action: UndoableAction) -> String {
        switch action {
        case .takeDose1: return "dose1"
        case .takeDose2: return "dose2"
        case .skipDose: return "skipDose"
        case .snooze: return "snooze"
        }
    }
}

// MARK: - DoseUndoManager Extension for callbacks
extension DoseUndoManager {
    func setCallbacks(
        onCommit: @escaping (UndoableAction) -> Void,
        onUndo: @escaping (UndoableAction) -> Void
    ) {
        self.onCommit = onCommit
        self.onUndo = onUndo
    }
}
