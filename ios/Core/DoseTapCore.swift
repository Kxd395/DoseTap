import Foundation
import Combine
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Legacy Bridge Types
// This file provides compatibility types for the legacy SwiftUI app

public enum DoseStatus: Equatable {
    case noDose1
    case beforeWindow
    case active
    case nearClose
    case closed
    case completed
    case finalizing  // User pressed Wake Up, awaiting morning check-in
    
    init(from phase: DoseWindowPhase) {
        switch phase {
        case .noDose1: self = .noDose1
        case .beforeWindow: self = .beforeWindow
        case .active: self = .active
        case .nearClose: self = .nearClose
        case .closed: self = .closed
        case .completed: self = .completed
        case .finalizing: self = .finalizing
        }
    }
}

// MARK: - Session Repository Protocol
// Allows DoseTapCore to delegate to the app's SessionRepository without tight coupling

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
public protocol DoseTapSessionStateProviding: AnyObject {
    var dose1Time: Date? { get }
    var dose2Time: Date? { get }
    var snoozeCount: Int { get }
    var dose2Skipped: Bool { get }
    var wakeFinalTime: Date? { get }
    var checkInCompleted: Bool { get }
    var sessionDidChange: PassthroughSubject<Void, Never> { get }
}

// MARK: - Core Bridge Class
// P0 FIX: Now delegates to SessionRepository for all state. No stored dose state.
// Provides an ObservableObject wrapper around the Core module for SwiftUI

#if canImport(SwiftUI)
@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
@MainActor
public class DoseTapCore: ObservableObject {
    // MARK: - State is now computed from repository (P0 FIX)
    
    /// Read-only session state provider set by the composition root.
    private var sessionRepository: DoseTapSessionStateProviding?
    
    /// Current status computed from repository state
    public var currentStatus: DoseStatus {
        let context = windowContext
        return DoseStatus(from: context.phase)
    }
    
    /// Full window context — use for snooze/skip state checks.
    /// All surfaces MUST use this instead of manual boolean checks per SSOT.
    public var windowContext: DoseWindowContext {
        windowCalculator.context(
            dose1At: sessionRepository?.dose1Time,
            dose2TakenAt: sessionRepository?.dose2Time,
            dose2Skipped: sessionRepository?.dose2Skipped ?? false,
            snoozeCount: sessionRepository?.snoozeCount ?? 0,
            wakeFinalAt: sessionRepository?.wakeFinalTime,
            checkInCompleted: sessionRepository?.checkInCompleted ?? false
        )
    }
    
    /// Dose 1 time - computed from repository
    public var dose1Time: Date? {
        sessionRepository?.dose1Time
    }
    
    /// Dose 2 time - computed from repository
    public var dose2Time: Date? {
        sessionRepository?.dose2Time
    }
    
    /// Snooze count - computed from repository
    public var snoozeCount: Int {
        sessionRepository?.snoozeCount ?? 0
    }
    
    /// Is skipped - computed from repository
    public var isSkipped: Bool {
        sessionRepository?.dose2Skipped ?? false
    }
    
    private let windowCalculator: DoseWindowCalculator
    private var repositoryObserver: AnyCancellable?
    
    public init() {
        self.windowCalculator = DoseWindowCalculator()
    }
    
    /// Set the session repository and observe changes
    public func setSessionRepository(_ repo: DoseTapSessionStateProviding) {
        self.sessionRepository = repo
        
        // Observe repository changes to trigger objectWillChange
        repositoryObserver = repo.sessionDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
    }
}
#endif // canImport(SwiftUI)
