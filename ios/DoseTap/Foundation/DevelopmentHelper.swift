#if DEBUG
import Foundation

struct DevelopmentHelper {
    static let isLocalDevelopment = Bundle.main.object(forInfoDictionaryKey: "LOCAL_ONLY") as? Bool ?? false
    static let enableMockAPI = Bundle.main.object(forInfoDictionaryKey: "MOCK_API_RESPONSES") as? Bool ?? false
    static let skipExternalIntegrations = Bundle.main.object(forInfoDictionaryKey: "SKIP_EXTERNAL_INTEGRATIONS") as? Bool ?? false
    static let enableDebugLogging = Bundle.main.object(forInfoDictionaryKey: "ENABLE_DEBUG_LOGGING") as? Bool ?? false
    static let autoPopulateTestData = Bundle.main.object(forInfoDictionaryKey: "AUTO_POPULATE_TEST_DATA") as? Bool ?? false
    
    // MARK: - Mock Dose Window Data
    
    static func mockDoseWindow() -> DoseWindowContext {
        let calc = DoseWindowCalculator()
        let dose1 = Date().addingTimeInterval(-120 * 60) // 2 hours ago
        return calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
    }
    
    static func mockActiveWindow() -> DoseWindowContext {
        let calc = DoseWindowCalculator()
        let dose1 = Date().addingTimeInterval(-160 * 60) // 2h 40m ago (in active window)
        return calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 0)
    }
    
    static func mockNearCloseWindow() -> DoseWindowContext {
        let calc = DoseWindowCalculator()
        let dose1 = Date().addingTimeInterval(-230 * 60) // 3h 50m ago (near close)
        return calc.context(dose1At: dose1, dose2TakenAt: nil, dose2Skipped: false, snoozeCount: 2)
    }
    
    // MARK: - Test Data Population
    
    static func populateTestData() {
        guard isLocalDevelopment && autoPopulateTestData else { return }

        // Clear existing test data
        clearTestData()

        let repo = SessionRepository.shared
        let dose1Time = Date().addingTimeInterval(-160 * 60) // 2h 40m ago
        repo.saveDose1(timestamp: dose1Time)
        repo.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "bathroom",
            timestamp: Date().addingTimeInterval(-45 * 60),
            colorHex: "#007AFF",
            notes: nil
        )
        repo.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "bathroom",
            timestamp: Date().addingTimeInterval(-15 * 60),
            colorHex: "#007AFF",
            notes: nil
        )
        
        if enableDebugLogging {
            print("✅ Test data populated for local development")
            print("   - Dose 1 taken: \(dose1Time)")
        }
    }
    
    private static func clearTestData() {
        SessionRepository.shared.clearAllData()
    }
    
    // MARK: - Mock API Transport
    
    struct MockAPITransport: APITransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            guard enableMockAPI else {
                throw DoseAPIError.offline
            }
            
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            // Mock responses based on endpoint
            let path = request.url?.path ?? ""
            let mockData: Data
            
            switch path {
            case "/doses/take":
                mockData = Data("""
                {"success": true, "message": "Dose recorded", "timestamp": "\(ISO8601DateFormatter().string(from: Date()))"}
                """.utf8)
            case "/doses/skip":
                mockData = Data("""
                {"success": true, "message": "Dose skipped", "timestamp": "\(ISO8601DateFormatter().string(from: Date()))"}
                """.utf8)
            case "/doses/snooze":
                mockData = Data("""
                {"success": true, "message": "Dose snoozed", "snooze_until": "\(ISO8601DateFormatter().string(from: Date().addingTimeInterval(600)))"}
                """.utf8)
            case "/events/log":
                mockData = Data("""
                {"success": true, "message": "Event logged"}
                """.utf8)
            case "/analytics/export":
                mockData = Data("""
                {"export_id": "mock-export-123", "data": [{"event": "dose1", "timestamp": "\(ISO8601DateFormatter().string(from: Date()))"}]}
                """.utf8)
            default:
                mockData = Data("""
                {"success": true, "message": "Mock response"}
                """.utf8)
            }
            
            // Add slight delay to simulate network
            try await Task.sleep(for: .milliseconds(50))
            
            if enableDebugLogging {
                print("🔄 Mock API: \(request.httpMethod ?? "GET") \(path)")
            }
            
            return (mockData, response)
        }
    }
    
    // MARK: - Debug Logging
    
    static func debugLog(_ message: String, category: String = "DEBUG") {
        guard enableDebugLogging else { return }
        print("[\(category)] \(message)")
    }
    
    // MARK: - Development Menu Actions
    
    static func resetAllData() {
        guard isLocalDevelopment else { return }
        clearTestData()
        debugLog("All test data cleared")
    }
    
    static func simulateDose1() {
        guard isLocalDevelopment else { return }

        SessionRepository.shared.saveDose1(timestamp: Date())
        debugLog("Simulated Dose 1 taken")
    }
    
    static func simulateDose2() {
        guard isLocalDevelopment else { return }

        SessionRepository.shared.saveDose2(timestamp: Date())
        debugLog("Simulated Dose 2 taken")
    }
}

#endif
