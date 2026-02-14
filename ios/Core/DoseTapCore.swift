import Foundation
import Combine
#if canImport(OSLog)
import OSLog
#endif
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
public protocol DoseTapSessionRepository: AnyObject {
    var dose1Time: Date? { get }
    var dose2Time: Date? { get }
    var snoozeCount: Int { get }
    var dose2Skipped: Bool { get }
    var wakeFinalTime: Date? { get }
    var checkInCompleted: Bool { get }
    var sessionDidChange: PassthroughSubject<Void, Never> { get }
    
    func setDose1Time(_ time: Date)
    func setDose2Time(_ time: Date, isEarly: Bool, isExtraDose: Bool)
    func incrementSnooze()
    func skipDose2()
}

// MARK: - Core Bridge Class
// P0 FIX: Now delegates to SessionRepository for all state. No stored dose state.
// Provides an ObservableObject wrapper around the Core module for SwiftUI

#if canImport(SwiftUI)
@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
@MainActor
public class DoseTapCore: ObservableObject {
    // MARK: - State is now computed from repository (P0 FIX)
    
    /// Session repository for state storage - set by the app
    public var sessionRepository: DoseTapSessionRepository?
    
    /// Current status computed from repository state
    public var currentStatus: DoseStatus {
        let context = windowCalculator.context(
            dose1At: sessionRepository?.dose1Time,
            dose2TakenAt: sessionRepository?.dose2Time,
            dose2Skipped: sessionRepository?.dose2Skipped ?? false,
            snoozeCount: sessionRepository?.snoozeCount ?? 0,
            wakeFinalAt: sessionRepository?.wakeFinalTime,
            checkInCompleted: sessionRepository?.checkInCompleted ?? false
        )
        return DoseStatus(from: context.phase)
    }
    
    /// Dose 1 time - computed from repository
    public var dose1Time: Date? {
        get { sessionRepository?.dose1Time }
        set { 
            if let time = newValue {
                sessionRepository?.setDose1Time(time)
            }
            objectWillChange.send()
        }
    }
    
    /// Dose 2 time - computed from repository
    public var dose2Time: Date? {
        get { sessionRepository?.dose2Time }
        set {
            if let time = newValue {
                sessionRepository?.setDose2Time(time, isEarly: false, isExtraDose: false)
            }
            objectWillChange.send()
        }
    }
    
    /// Snooze count - computed from repository
    public var snoozeCount: Int {
        get { sessionRepository?.snoozeCount ?? 0 }
        set { 
            // Note: incrementSnooze() is preferred over direct set
            objectWillChange.send()
        }
    }
    
    /// Is skipped - computed from repository
    public var isSkipped: Bool {
        get { sessionRepository?.dose2Skipped ?? false }
        set {
            if newValue {
                sessionRepository?.skipDose2()
            }
            objectWillChange.send()
        }
    }
    
    private let windowCalculator: DoseWindowCalculator
    private let dosingService: DosingService
    private var repositoryObserver: AnyCancellable?

    private static func logWarning(_ message: String) {
        #if canImport(OSLog)
        Logger(subsystem: "com.dosetap.core", category: "DoseTapCore")
            .warning("\(message, privacy: .public)")
        #endif
    }

    private static func logError(_ message: String) {
        #if canImport(OSLog)
        Logger(subsystem: "com.dosetap.core", category: "DoseTapCore")
            .error("\(message, privacy: .public)")
        #endif
    }
    
    public init(isOnline: @escaping () -> Bool = { true }) {
        self.windowCalculator = DoseWindowCalculator()

        let apiClient = APIClient(baseURL: Self.apiBaseURL, transport: Self.makeTransport())
        let offlineQueue = InMemoryOfflineQueue(isOnline: isOnline)
        self.dosingService = DosingService(client: apiClient, queue: offlineQueue)
    }

    private static var apiBaseURL: URL {
        if let envURL = ProcessInfo.processInfo.environment["DOSETAP_API_URL"],
           let url = URL(string: envURL) {
            return url
        }
        #if DEBUG
        return URL(string: "https://api-dev.dosetap.com")!
        #else
        return URL(string: "https://api.dosetap.com")!
        #endif
    }

    private static func makeTransport() -> APITransport {
        let env = ProcessInfo.processInfo.environment

        #if DEBUG
        if env["DOSETAP_USE_MOCK_TRANSPORT"] == "1" {
            return MockAPITransport()
        }
        if env["DOSETAP_USE_PINNED_TRANSPORT"] == "1",
           CertificatePinning.hasConfiguredPins {
            return PinnedURLSessionTransport()
        }
        return URLSessionTransport()
        #else
        if CertificatePinning.hasConfiguredPins {
            return PinnedURLSessionTransport()
        }
        // Graceful degradation: log a critical security warning but don't crash.
        // CI should catch missing pins for release builds — see ci.yml.
        #if canImport(OSLog)
        Logger(subsystem: "com.dosetap.core", category: "Security")
            .critical("⚠️ Release build without certificate pins — set DOSETAP_CERT_PINS")
        #endif
        assertionFailure("Certificate pinning is not configured; set DOSETAP_CERT_PINS for release builds.")
        return URLSessionTransport()
        #endif
    }
    
    /// Set the session repository and observe changes
    public func setSessionRepository(_ repo: DoseTapSessionRepository) {
        self.sessionRepository = repo
        
        // Observe repository changes to trigger objectWillChange
        repositoryObserver = repo.sessionDidChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
    }
    
    /// Take dose with optional early override flag
    /// - Parameter earlyOverride: If true, allows taking Dose 2 before window opens (user confirmed)
    public func takeDose(earlyOverride: Bool = false, lateOverride: Bool = false) async {
        let now = Date()
        
        await MainActor.run {
            if dose1Time == nil {
                // P0 FIX: Write through repository
                sessionRepository?.setDose1Time(now)
            } else if dose2Time == nil {
                // Dose 2 logic
                let windowOpen = currentStatus == .active || currentStatus == .nearClose
                
                if windowOpen || earlyOverride || lateOverride {
                    // P0 FIX: Write through repository
                    sessionRepository?.setDose2Time(now, isEarly: earlyOverride, isExtraDose: false)
                    #if DEBUG
                    if earlyOverride {
                        #if canImport(OSLog)
                        Self.logWarning("Dose 2 taken early with user override")
                        #endif
                    } else if lateOverride {
                        #if canImport(OSLog)
                        Self.logWarning("Dose 2 taken late with user override")
                        #endif
                    }
                    #endif
                } else {
                    // Window not open and no override - block
                    #if DEBUG
                    #if canImport(OSLog)
                    let status = self.currentStatus
                    Self.logError("Cannot take Dose 2: window not open (status: \(status))")
                    #endif
                    #endif
                    return
                }
            } else {
                // Dose 2 already taken - this should be blocked by UI
                #if DEBUG
                #if canImport(OSLog)
                Self.logWarning("Dose 2 already taken, ignoring duplicate")
                #endif
                #endif
                return
            }
        }
        
        await dosingService.perform(.takeDose(type: "XYWAV", at: now))
    }
    
    public func skipDose() async {
        await MainActor.run {
            // P0 FIX: Write through repository
            sessionRepository?.skipDose2()
        }
        
        await dosingService.perform(.skipDose(sequence: 2, reason: "user_request"))
    }
    
    public func snooze() async {
        await MainActor.run {
            // P0 FIX: Write through repository
            sessionRepository?.incrementSnooze()
        }
        
        await dosingService.perform(.snooze(minutes: 10))
    }
}

// MARK: - Mock Transport for Development (DEBUG only)
#if DEBUG
struct MockAPITransport: APITransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Return mock success response
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(), response)
    }
}
#endif // DEBUG
#endif // canImport(SwiftUI)
