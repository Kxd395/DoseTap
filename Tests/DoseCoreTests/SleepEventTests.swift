import XCTest
@testable import DoseCore

final class SleepEventTests: XCTestCase {
    
    // MARK: - SleepEventType Tests
    
    func testAllEventTypesHaveIcons() {
        for eventType in SleepEventType.allCases {
            XCTAssertFalse(eventType.iconName.isEmpty, "\(eventType.rawValue) should have an icon")
        }
    }
    
    func testAllEventTypesHaveDisplayNames() {
        for eventType in SleepEventType.allCases {
            XCTAssertFalse(eventType.displayName.isEmpty, "\(eventType.rawValue) should have a display name")
        }
    }
    
    func testAllEventTypesHaveCooldowns() {
        // Per SSOT: Only physical events (bathroom/water/snack) have non-zero cooldowns
        let physicalEvents: Set<SleepEventType> = [.bathroom, .water, .snack]
        for eventType in SleepEventType.allCases {
            if physicalEvents.contains(eventType) {
                XCTAssertGreaterThan(eventType.defaultCooldownSeconds, 0, "\(eventType.rawValue) should have a positive cooldown")
            } else {
                XCTAssertEqual(eventType.defaultCooldownSeconds, 0, "\(eventType.rawValue) should have zero cooldown per SSOT")
            }
        }
    }
    
    func testAllEventTypesHaveCategories() {
        for eventType in SleepEventType.allCases {
            // Just access the category to ensure it doesn't crash
            _ = eventType.category
        }
    }
    
    // MARK: - SSOT Cooldown Compliance Tests
    // These tests ensure cooldowns match docs/SSOT/constants.json
    
    func testPhysicalEventCooldowns_SSOTCompliance() {
        // Physical events have 60s cooldown to prevent accidental double-tap
        XCTAssertEqual(SleepEventType.bathroom.defaultCooldownSeconds, 60, "bathroom cooldown must be 60s per SSOT")
        XCTAssertEqual(SleepEventType.water.defaultCooldownSeconds, 60, "water cooldown must be 60s per SSOT")
        XCTAssertEqual(SleepEventType.snack.defaultCooldownSeconds, 60, "snack cooldown must be 60s per SSOT")
    }
    
    func testSleepCycleEventCooldowns_SSOTCompliance() {
        // Sleep cycle markers have NO cooldown (they're session markers)
        XCTAssertEqual(SleepEventType.inBed.defaultCooldownSeconds, 0, "inBed cooldown must be 0 per SSOT")
        XCTAssertEqual(SleepEventType.lightsOut.defaultCooldownSeconds, 0, "lightsOut cooldown must be 0 per SSOT")
        XCTAssertEqual(SleepEventType.wakeFinal.defaultCooldownSeconds, 0, "wakeFinal cooldown must be 0 per SSOT")
        XCTAssertEqual(SleepEventType.wakeTemp.defaultCooldownSeconds, 0, "wakeTemp cooldown must be 0 per SSOT")
    }
    
    func testMentalEventCooldowns_SSOTCompliance() {
        // Mental events have NO cooldown - log as many times as needed
        XCTAssertEqual(SleepEventType.anxiety.defaultCooldownSeconds, 0, "anxiety cooldown must be 0 per SSOT")
        XCTAssertEqual(SleepEventType.dream.defaultCooldownSeconds, 0, "dream cooldown must be 0 per SSOT")
        XCTAssertEqual(SleepEventType.heartRacing.defaultCooldownSeconds, 0, "heartRacing cooldown must be 0 per SSOT")
    }
    
    func testEnvironmentEventCooldowns_SSOTCompliance() {
        // Environment events have NO cooldown - log as many times as needed
        XCTAssertEqual(SleepEventType.noise.defaultCooldownSeconds, 0, "noise cooldown must be 0 per SSOT")
        XCTAssertEqual(SleepEventType.temperature.defaultCooldownSeconds, 0, "temperature cooldown must be 0 per SSOT")
        XCTAssertEqual(SleepEventType.pain.defaultCooldownSeconds, 0, "pain cooldown must be 0 per SSOT")
    }
    
    // MARK: - SleepEventCategory Tests
    
    func testPhysicalCategoryContainsExpectedEvents() {
        let physical = SleepEventCategory.physical.events
        XCTAssertTrue(physical.contains(.bathroom))
        XCTAssertTrue(physical.contains(.water))
        XCTAssertTrue(physical.contains(.snack))
    }
    
    func testSleepCycleCategoryContainsExpectedEvents() {
        let sleepCycle = SleepEventCategory.sleepCycle.events
        XCTAssertTrue(sleepCycle.contains(.lightsOut))
        XCTAssertTrue(sleepCycle.contains(.wakeFinal))
        XCTAssertTrue(sleepCycle.contains(.wakeTemp))
    }
    
    func testMentalCategoryContainsExpectedEvents() {
        let mental = SleepEventCategory.mental.events
        XCTAssertTrue(mental.contains(.anxiety))
        XCTAssertTrue(mental.contains(.dream))
        XCTAssertTrue(mental.contains(.heartRacing))
    }
    
    func testEnvironmentCategoryContainsExpectedEvents() {
        let environment = SleepEventCategory.environment.events
        XCTAssertTrue(environment.contains(.noise))
        XCTAssertTrue(environment.contains(.temperature))
        XCTAssertTrue(environment.contains(.pain))
    }
    
    func testAllCategoriesHaveDisplayNames() {
        for category in SleepEventCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty)
        }
    }
    
    func testAllCategoriesHaveIcons() {
        for category in SleepEventCategory.allCases {
            XCTAssertFalse(category.iconName.isEmpty)
        }
    }
    
    // MARK: - SleepEvent Tests
    
    func testSleepEventInitialization() {
        let event = SleepEvent(type: .bathroom, timestamp: Date())
        
        XCTAssertNotNil(event.id)
        XCTAssertEqual(event.type, .bathroom)
        XCTAssertNil(event.sessionId)
        XCTAssertNil(event.notes)
        XCTAssertEqual(event.source, .manual)
    }
    
    func testSleepEventWithSessionId() {
        let sessionId = UUID()
        let event = SleepEvent(type: .lightsOut, sessionId: sessionId)
        
        XCTAssertEqual(event.sessionId, sessionId)
    }
    
    func testSleepEventWithNotes() {
        let event = SleepEvent(type: .anxiety, notes: "Feeling stressed")
        
        XCTAssertEqual(event.notes, "Feeling stressed")
    }
    
    func testSleepEventSources() {
        let manualEvent = SleepEvent(type: .bathroom, source: .manual)
        let watchEvent = SleepEvent(type: .bathroom, source: .watch)
        let flicEvent = SleepEvent(type: .bathroom, source: .flic)
        let siriEvent = SleepEvent(type: .bathroom, source: .siri)
        let autoEvent = SleepEvent(type: .bathroom, source: .automatic)
        
        XCTAssertEqual(manualEvent.source, .manual)
        XCTAssertEqual(watchEvent.source, .watch)
        XCTAssertEqual(flicEvent.source, .flic)
        XCTAssertEqual(siriEvent.source, .siri)
        XCTAssertEqual(autoEvent.source, .automatic)
    }
    
    func testSleepEventEquality() {
        let id = UUID()
        let timestamp = Date()
        
        let event1 = SleepEvent(id: id, type: .bathroom, timestamp: timestamp)
        let event2 = SleepEvent(id: id, type: .bathroom, timestamp: timestamp)
        
        XCTAssertEqual(event1, event2)
    }
    
    func testSleepEventAPIBody() {
        let id = UUID()
        let timestamp = Date()
        let event = SleepEvent(id: id, type: .bathroom, timestamp: timestamp, source: .watch)
        
        let body = event.apiBody
        
        XCTAssertEqual(body["id"] as? String, id.uuidString)
        XCTAssertEqual(body["type"] as? String, "bathroom")
        XCTAssertEqual(body["source"] as? String, "watch")
        XCTAssertNotNil(body["timestamp"])
    }
    
    // MARK: - SleepEventSummary Tests
    
    func testSleepEventSummaryEmpty() {
        let summary = SleepEventSummary(events: [])
        
        XCTAssertEqual(summary.totalEvents, 0)
        XCTAssertEqual(summary.bathroomCount, 0)
        XCTAssertEqual(summary.wakeCount, 0)
        XCTAssertNil(summary.firstEvent)
        XCTAssertNil(summary.lastEvent)
        XCTAssertTrue(summary.eventsByType.isEmpty)
    }
    
    func testSleepEventSummaryWithEvents() {
        let now = Date()
        let events = [
            SleepEvent(type: .bathroom, timestamp: now.addingTimeInterval(-3600)),
            SleepEvent(type: .bathroom, timestamp: now.addingTimeInterval(-1800)),
            SleepEvent(type: .wakeTemp, timestamp: now.addingTimeInterval(-900)),
            SleepEvent(type: .water, timestamp: now)
        ]
        
        let summary = SleepEventSummary(events: events)
        
        XCTAssertEqual(summary.totalEvents, 4)
        XCTAssertEqual(summary.bathroomCount, 2)
        XCTAssertEqual(summary.wakeCount, 1)
        XCTAssertNotNil(summary.firstEvent)
        XCTAssertNotNil(summary.lastEvent)
        XCTAssertEqual(summary.eventsByType[.bathroom], 2)
        XCTAssertEqual(summary.eventsByType[.wakeTemp], 1)
        XCTAssertEqual(summary.eventsByType[.water], 1)
    }
    
    // MARK: - SleepEventResult Tests
    
    func testSleepEventResultSuccess() {
        let event = SleepEvent(type: .bathroom)
        let result = SleepEventResult.logged(event)
        
        XCTAssertTrue(result.isSuccess)
    }
    
    func testSleepEventResultRateLimited() {
        let result = SleepEventResult.rateLimited(remainingSeconds: 30)
        
        XCTAssertFalse(result.isSuccess)
    }
    
    func testSleepEventResultError() {
        let result = SleepEventResult.error("Database error")
        
        XCTAssertFalse(result.isSuccess)
    }
    
    // MARK: - All Cooldowns Dictionary Tests
    
    func testAllCooldownsDictionaryContainsAllTypes() {
        let cooldowns = SleepEventType.allCooldowns
        
        for eventType in SleepEventType.allCases {
            XCTAssertNotNil(cooldowns[eventType.rawValue], "Missing cooldown for \(eventType.rawValue)")
        }
    }
    
    func testAllCooldownsMatchIndividualCooldowns() {
        let cooldowns = SleepEventType.allCooldowns
        
        for eventType in SleepEventType.allCases {
            XCTAssertEqual(
                cooldowns[eventType.rawValue],
                eventType.defaultCooldownSeconds,
                "Cooldown mismatch for \(eventType.rawValue)"
            )
        }
    }
    
    // MARK: - Codable Tests
    
    func testSleepEventEncodeDecode() throws {
        let event = SleepEvent(
            type: .bathroom,
            timestamp: Date(),
            sessionId: UUID(),
            notes: "Test note",
            source: .watch
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(event)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SleepEvent.self, from: data)
        
        XCTAssertEqual(event.id, decoded.id)
        XCTAssertEqual(event.type, decoded.type)
        XCTAssertEqual(event.sessionId, decoded.sessionId)
        XCTAssertEqual(event.notes, decoded.notes)
        XCTAssertEqual(event.source, decoded.source)
    }
    
    func testSleepEventTypeEncodeDecode() throws {
        for eventType in SleepEventType.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(eventType)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(SleepEventType.self, from: data)
            
            XCTAssertEqual(eventType, decoded)
        }
    }
}
