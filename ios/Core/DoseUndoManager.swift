import Foundation

// MARK: - Undo Manager for DoseTap
// Provides 5-second undo window for dose actions per SSOT §1

/// Actions that can be undone
public enum UndoableAction: Equatable, Sendable {
    case takeDose1(at: Date)
    case takeDose2(at: Date)
    case skipDose(sequence: Int, reason: String?)
    case snooze(minutes: Int)
}

/// Result of an undo attempt
public enum UndoResult: Equatable, Sendable {
    case success(action: UndoableAction)
    case expired
    case noAction
}

/// Thread-safe undo manager with configurable window
@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
public actor DoseUndoManager {
    
    // MARK: - Configuration
    
    /// Default undo window in seconds (per SSOT)
    public static let defaultWindowSeconds: TimeInterval = 5.0
    
    private let windowSeconds: TimeInterval
    private let now: () -> Date
    
    // MARK: - State
    
    private var pendingAction: UndoableAction?
    private var actionTimestamp: Date?
    private var undoTask: Task<Void, Never>?
    
    // MARK: - Callbacks
    
    /// Called when undo window expires without undo
    public var onCommit: ((UndoableAction) -> Void)?
    
    /// Called when undo is performed
    public var onUndo: ((UndoableAction) -> Void)?
    
    // MARK: - Init
    
    public init(
        windowSeconds: TimeInterval = defaultWindowSeconds,
        now: @escaping () -> Date = { Date() }
    ) {
        self.windowSeconds = windowSeconds
        self.now = now
    }
    
    // MARK: - Public API
    
    /// Register an action that can be undone within the window
    /// - Parameter action: The action to register
    /// - Returns: Time remaining in undo window
    @discardableResult
    public func register(_ action: UndoableAction) -> TimeInterval {
        // Cancel any existing undo timer
        undoTask?.cancel()
        
        // If there was a pending action, commit it first
        if let pending = pendingAction {
            onCommit?(pending)
        }
        
        // Register new action
        pendingAction = action
        actionTimestamp = now()
        
        // Start countdown timer
        undoTask = Task { [weak self, windowSeconds] in
            try? await Task.sleep(nanoseconds: UInt64(windowSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.commitPending()
        }
        
        return windowSeconds
    }
    
    /// Attempt to undo the pending action
    /// - Returns: Result indicating success/failure
    public func undo() -> UndoResult {
        guard let action = pendingAction, let timestamp = actionTimestamp else {
            return .noAction
        }
        
        let elapsed = now().timeIntervalSince(timestamp)
        guard elapsed <= windowSeconds else {
            // Window expired
            commitPending()
            return .expired
        }
        
        // Cancel timer and clear state
        undoTask?.cancel()
        pendingAction = nil
        actionTimestamp = nil
        
        onUndo?(action)
        return .success(action: action)
    }
    
    /// Check if there's a pending action that can be undone
    public var canUndo: Bool {
        guard let timestamp = actionTimestamp else { return false }
        return now().timeIntervalSince(timestamp) <= windowSeconds
    }
    
    /// Time remaining in undo window (0 if expired or no action)
    public var remainingTime: TimeInterval {
        guard let timestamp = actionTimestamp else { return 0 }
        let elapsed = now().timeIntervalSince(timestamp)
        return max(0, windowSeconds - elapsed)
    }
    
    /// The currently pending action, if any
    public var pending: UndoableAction? {
        guard canUndo else { return nil }
        return pendingAction
    }
    
    // MARK: - Private
    
    private func commitPending() {
        guard let action = pendingAction else { return }
        onCommit?(action)
        pendingAction = nil
        actionTimestamp = nil
    }
}
