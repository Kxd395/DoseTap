import XCTest
@testable import DoseTapStudio

/// Test suite for data import functionality
final class ImporterTests: XCTestCase {
    
    func testParseEventsCSV() throws {
        let csvContent = """
        event_type,occurred_at_utc,details,device_time
        dose1_taken,2024-09-07T20:00:00.000Z,Manual entry,2024-09-07T16:00:00-04:00
        dose2_taken,2024-09-07T22:45:00.000Z,,2024-09-07T18:45:00-04:00
        bathroom,2024-09-07T21:30:00.000Z,Quick break,2024-09-07T17:30:00-04:00
        """
        
        let importer = Importer()
        let events = try importer.parseEventsCSV(csvContent)
        
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].eventType, .dose1_taken)
        XCTAssertEqual(events[1].eventType, .dose2_taken)
        XCTAssertEqual(events[2].eventType, .bathroom)
        XCTAssertEqual(events[0].details, "Manual entry")
        XCTAssertNil(events[1].details)
    }
    
    func testParseSessionsCSV() throws {
        let csvContent = """
        started_utc,ended_utc,window_target_min,window_actual_min,adherence_flag,whoop_recovery,avg_hr,sleep_efficiency,notes
        2024-09-07T20:00:00.000Z,2024-09-07T22:45:00.000Z,165,165,ok,75,65,85.5,Good session
        2024-09-06T20:00:00.000Z,2024-09-06T23:00:00.000Z,165,180,late,80,70,90.2,
        """
        
        let importer = Importer()
        let sessions = try importer.parseSessionsCSV(csvContent)
        
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].windowTargetMin, 165)
        XCTAssertEqual(sessions[0].windowActualMin, 165)
        XCTAssertEqual(sessions[0].adherenceFlag, "ok")
        XCTAssertEqual(sessions[0].whoopRecovery, 75)
        XCTAssertEqual(sessions[1].windowActualMin, 180)
        XCTAssertEqual(sessions[1].adherenceFlag, "late")
    }
    
    func testParseInventoryCSV() throws {
        let csvContent = """
        as_of_utc,bottles_remaining,doses_remaining,estimated_days_left,next_refill_date,notes
        2024-09-07T08:00:00.000Z,2,28,14,2024-09-21T08:00:00.000Z,Good supply
        2024-09-01T08:00:00.000Z,3,42,21,,
        """
        
        let importer = Importer()
        let inventory = try importer.parseInventoryCSV(csvContent)
        
        XCTAssertEqual(inventory.count, 2)
        XCTAssertEqual(inventory[0].bottlesRemaining, 2)
        XCTAssertEqual(inventory[0].dosesRemaining, 28)
        XCTAssertEqual(inventory[0].estimatedDaysLeft, 14)
        XCTAssertEqual(inventory[0].notes, "Good supply")
        XCTAssertEqual(inventory[1].bottlesRemaining, 3)
        XCTAssertNil(inventory[1].notes)
    }
    
    func testCSVLineParsingWithQuotes() {
        let importer = Importer()
        
        // Test quoted field with comma
        let line1 = #"dose1_taken,2024-09-07T20:00:00.000Z,"Manual entry, user initiated",2024-09-07T16:00:00-04:00"#
        let columns1 = importer.parseCSVLine(line1)
        XCTAssertEqual(columns1.count, 4)
        XCTAssertEqual(columns1[2], "Manual entry, user initiated")
        
        // Test escaped quotes
        let line2 = #"bathroom,2024-09-07T21:30:00.000Z,"Said ""quick break""",2024-09-07T17:30:00-04:00"#
        let columns2 = importer.parseCSVLine(line2)
        XCTAssertEqual(columns2[2], #"Said "quick break""#)
    }
}
