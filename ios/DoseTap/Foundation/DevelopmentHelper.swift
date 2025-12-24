#if DEBUG
import Foundation
import CoreData

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
        
        let store = PersistentStore.shared
        let context = store.viewContext
        
        // Clear existing test data
        clearTestData()
        
        // Create test dose session
        let session = DoseSession(context: context)
        session.sessionID = UUID().uuidString
        session.startedUTC = Date().addingTimeInterval(-3600) // 1 hour ago
        session.windowTargetMin = 165
        session.dose1TakenUTC = Date().addingTimeInterval(-160 * 60) // 2h 40m ago
        
        // Create some test dose events
        createTestDoseEvent(context: context, type: "dose1", sequenceNumber: 1, minutesAgo: 160)
        createTestDoseEvent(context: context, type: "bathroom", sequenceNumber: 0, minutesAgo: 45)
        createTestDoseEvent(context: context, type: "bathroom", sequenceNumber: 0, minutesAgo: 15)
        
        // Create test inventory snapshot
        let inventory = InventorySnapshot(context: context)
        inventory.snapshotID = UUID().uuidString
        inventory.capturedUTC = Date()
        inventory.remainingDoses = 14
        
        store.saveContext()
        
        if enableDebugLogging {
            print("✅ Test data populated for local development")
            print("   - Session: \(session.sessionID ?? "unknown")")
            print("   - Dose 1 taken: \(session.dose1TakenUTC?.description ?? "none")")
            print("   - Inventory: \(inventory.remainingDoses) doses remaining")
        }
    }
    
    private static func createTestDoseEvent(context: NSManagedObjectContext, type: String, sequenceNumber: Int, minutesAgo: Int) {
        let event = DoseEvent(context: context)
        event.eventID = UUID().uuidString
        event.eventType = type
        event.doseSequence = Int16(sequenceNumber)
        event.occurredAtUTC = Date().addingTimeInterval(-Double(minutesAgo * 60))
        event.localTZ = TimeZone.current.identifier
        event.source = "development_helper"
    }
    
    private static func clearTestData() {
        let store = PersistentStore.shared
        let context = store.viewContext
        
        // Delete existing test data
        let sessionFetch = NSFetchRequest<DoseSession>(entityName: "DoseSession")
        let eventFetch = NSFetchRequest<DoseEvent>(entityName: "DoseEvent")
        let inventoryFetch = NSFetchRequest<InventorySnapshot>(entityName: "InventorySnapshot")
        
        do {
            let sessions = try context.fetch(sessionFetch)
            let events = try context.fetch(eventFetch)
            let inventories = try context.fetch(inventoryFetch)
            
            sessions.forEach { context.delete($0) }
            events.forEach { context.delete($0) }
            inventories.forEach { context.delete($0) }
            
            store.saveContext()
        } catch {
            if enableDebugLogging {
                print("⚠️ Failed to clear test data: \(error)")
            }
        }
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
        
        let store = PersistentStore.shared
        let context = store.viewContext
        
        // Create new session if none exists
        let sessionFetch = NSFetchRequest<DoseSession>(entityName: "DoseSession")
        let existingSessions = try? context.fetch(sessionFetch)
        
        let session: DoseSession
        if let existing = existingSessions?.first {
            session = existing
        } else {
            session = DoseSession(context: context)
            session.sessionID = UUID().uuidString
            session.startedUTC = Date()
            session.windowTargetMin = 165
        }
        
        // Record dose 1
        session.dose1TakenUTC = Date()
        
        // Create dose event
        createTestDoseEvent(context: context, type: "dose1", sequenceNumber: 1, minutesAgo: 0)
        
        store.saveContext()
        debugLog("Simulated Dose 1 taken")
    }
    
    static func simulateDose2() {
        guard isLocalDevelopment else { return }
        
        let store = PersistentStore.shared
        let context = store.viewContext
        
        // Find existing session
        let sessionFetch = NSFetchRequest<DoseSession>(entityName: "DoseSession")
        guard let session = try? context.fetch(sessionFetch).first else {
            debugLog("No session found - simulate Dose 1 first")
            return
        }
        
        // Record dose 2
        session.dose2TakenUTC = Date()
        
        // Create dose event
        createTestDoseEvent(context: context, type: "dose2", sequenceNumber: 2, minutesAgo: 0)
        
        store.saveContext()
        debugLog("Simulated Dose 2 taken")
    }
}

#endif
