import Foundation
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
    
    init(from phase: DoseWindowPhase) {
        switch phase {
        case .noDose1: self = .noDose1
        case .beforeWindow: self = .beforeWindow
        case .active: self = .active
        case .nearClose: self = .nearClose
        case .closed: self = .closed
        case .completed: self = .completed
        }
    }
}

// MARK: - Core Bridge Class
// Provides an ObservableObject wrapper around the Core module for SwiftUI

#if canImport(SwiftUI)
@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
@MainActor
public class DoseTapCore: ObservableObject {
    @Published public var currentStatus: DoseStatus = .noDose1
    @Published public var dose1Time: Date?
    @Published public var dose2Time: Date?
    @Published public var snoozeCount: Int = 0
    @Published public var isSkipped: Bool = false
    
    private let windowCalculator: DoseWindowCalculator
    private let dosingService: DosingService
    
    public init() {
        self.windowCalculator = DoseWindowCalculator()
        
        // Initialize with mock transport for development
        let mockTransport = MockAPITransport()
        let apiClient = APIClient(baseURL: URL(string: "https://api.dosetap.com")!, transport: mockTransport)
        let offlineQueue = InMemoryOfflineQueue(isOnline: { true }) // Always online for development
        self.dosingService = DosingService(client: apiClient, queue: offlineQueue)
        
        updateStatus()
    }
    
    /// Take dose with optional early override flag
    /// - Parameter earlyOverride: If true, allows taking Dose 2 before window opens (user confirmed)
    public func takeDose(earlyOverride: Bool = false) async {
        let now = Date()
        // Ensure we're on main thread for @Published updates
        await MainActor.run {
            if dose1Time == nil {
                dose1Time = now
            } else if dose2Time == nil {
                // Dose 2 logic
                let windowOpen = currentStatus == .active || currentStatus == .nearClose
                
                if windowOpen {
                    // Normal case: window is open
                    dose2Time = now
                } else if earlyOverride {
                    // Early override: user confirmed they understand the risk
                    dose2Time = now
                    print("⚠️ Dose 2 taken early with user override")
                } else {
                    // Window not open and no override - block
                    print("❌ Cannot take Dose 2: window not open (status: \(currentStatus))")
                    return
                }
            } else {
                // Dose 2 already taken - this should be blocked by UI
                print("⚠️ Dose 2 already taken, ignoring duplicate")
                return
            }
            updateStatus()
        }
        
        await dosingService.perform(.takeDose(type: "XYWAV", at: now))
    }
    
    public func skipDose() async {
        await MainActor.run {
            isSkipped = true
            updateStatus()
        }
        
        await dosingService.perform(.skipDose(sequence: 2, reason: "user_request"))
    }
    
    public func snooze() async {
        await MainActor.run {
            snoozeCount += 1
            updateStatus()
        }
        
        await dosingService.perform(.snooze(minutes: 10))
    }
    
    private func updateStatus() {
        let context = windowCalculator.context(
            dose1At: dose1Time,
            dose2TakenAt: dose2Time,
            dose2Skipped: isSkipped,
            snoozeCount: snoozeCount
        )
        currentStatus = DoseStatus(from: context.phase)
    }
}

// MARK: - Mock Transport for Development
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
#endif
