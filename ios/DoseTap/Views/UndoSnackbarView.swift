//
//  UndoSnackbarView.swift
//  DoseTap
//
//  Undo snackbar that appears after dose actions
//  Shows countdown and allows undo within the configured window
//

import SwiftUI
import DoseCore

// MARK: - Undo Snackbar View
@available(iOS 15.0, *)
struct UndoSnackbarView: View {
    let action: UndoableAction
    let remainingTime: TimeInterval
    let totalTime: TimeInterval
    let onUndo: () -> Void
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    
    var body: some View {
        HStack(spacing: 12) {
            // Action icon and text
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: actionIcon)
                        .font(.title3)
                        .foregroundColor(actionColor)
                    
                    Text(actionDescription)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                // Countdown bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 2)
                            .fill(countdownColor)
                            .frame(width: geo.size.width * progress, height: 4)
                            .animation(.linear(duration: 0.1), value: remainingTime)
                    }
                }
                .frame(height: 4)
                
                Text("\(Int(remainingTime))s to undo")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Undo button
            Button(action: onUndo) {
                Text("Undo")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .cornerRadius(8)
            }
            .accessibilityLabel("Undo \(actionDescription)")
            .accessibilityHint("Double tap to undo this action")
            
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(reduceTransparency ? 0 : 0.15), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(differentiateWithoutColor ? Color.primary.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Undo available for \(actionDescription). \(Int(remainingTime)) seconds remaining.")
    }
    
    // MARK: - Computed Properties
    
    private var progress: CGFloat {
        guard totalTime > 0 else { return 0 }
        return CGFloat(remainingTime / totalTime)
    }
    
    private var countdownColor: Color {
        if remainingTime < 2 {
            return .red
        } else if remainingTime < totalTime / 2 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var actionIcon: String {
        switch action {
        case .takeDose1: return "1.circle.fill"
        case .takeDose2: return "2.circle.fill"
        case .skipDose: return "forward.fill"
        case .snooze: return "clock.badge.plus"
        }
    }
    
    private var actionColor: Color {
        switch action {
        case .takeDose1: return .blue
        case .takeDose2: return .green
        case .skipDose: return .orange
        case .snooze: return .purple
        }
    }
    
    private var actionDescription: String {
        switch action {
        case .takeDose1: return "Took Dose 1"
        case .takeDose2: return "Took Dose 2"
        case .skipDose(let seq, _): return "Skipped Dose \(seq)"
        case .snooze(let mins): return "Snoozed \(mins) min"
        }
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark 
            ? Color(.systemGray6)
            : Color.white
    }
}

// MARK: - Undo State Manager (Observable)
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

// MARK: - Undo Overlay View
@available(iOS 15.0, *)
struct UndoOverlayView: View {
    @ObservedObject var stateManager: UndoStateManager
    
    var body: some View {
        if stateManager.isVisible, let action = stateManager.currentAction {
            VStack {
                Spacer()
                
                UndoSnackbarView(
                    action: action,
                    remainingTime: stateManager.remainingTime,
                    totalTime: UserSettingsManager.shared.undoWindowSeconds,
                    onUndo: {
                        stateManager.performUndo()
                    },
                    onDismiss: {
                        stateManager.dismiss()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 100) // Above tab bar
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: stateManager.isVisible)
        }
    }
}

// MARK: - Preview
#if DEBUG
@available(iOS 15.0, *)
struct UndoSnackbarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            
            UndoSnackbarView(
                action: .takeDose1(at: Date()),
                remainingTime: 3.5,
                totalTime: 5.0,
                onUndo: { print("Undo tapped") },
                onDismiss: { print("Dismissed") }
            )
            .padding()
            
            UndoSnackbarView(
                action: .takeDose2(at: Date()),
                remainingTime: 1.2,
                totalTime: 5.0,
                onUndo: { print("Undo tapped") },
                onDismiss: { print("Dismissed") }
            )
            .padding()
            
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }
}
#endif
