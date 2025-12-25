import SwiftUI

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
                }
                
                await manager.register(action)
            }
        }
    }
    
    func performUndo() {
        Task {
            if let manager = undoManager {
                let result = await manager.undo()
                await MainActor.run {
                    switch result {
                    case .success(let action):
                        print("✅ Undo successful: \(action)")
                    case .expired:
                        print("⏰ Undo window expired")
                    case .noAction:
                        print("⚠️ No action to undo")
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
        onCommit?(action)
        dismiss()
    }
    
    private func handleUndo(_ action: UndoableAction) {
        onUndo?(action)
        dismiss()
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
