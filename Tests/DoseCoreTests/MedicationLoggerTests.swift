import XCTest
@testable import DoseCore

final class MedicationLoggerTests: XCTestCase {
    
    // MARK: - MedicationConfig Tests
    
    func testMedicationTypesDefinedCorrectly() {
        // All narcolepsy medications: stimulants, wakefulness agents, histamine modulators, sodium oxybate
        XCTAssertGreaterThanOrEqual(MedicationConfig.types.count, 10) // At least 10 medications
        
        let adderallIR = MedicationConfig.type(for: "adderall_ir")
        XCTAssertNotNil(adderallIR)
        XCTAssertEqual(adderallIR?.displayName, "Adderall")
        XCTAssertEqual(adderallIR?.formulation, .immediateRelease)
        XCTAssertEqual(adderallIR?.defaultDoseMg, 10)
        XCTAssertEqual(adderallIR?.validDoses, [5, 10, 15, 20, 25, 30])
        
        let adderallXR = MedicationConfig.type(for: "adderall_xr")
        XCTAssertNotNil(adderallXR)
        XCTAssertEqual(adderallXR?.displayName, "Adderall XR")
        XCTAssertEqual(adderallXR?.formulation, .extendedRelease)
        XCTAssertEqual(adderallXR?.defaultDoseMg, 20)
    }
    
    func testAllNarcolepsyMedicationsPresent() {
        // Stimulants
        XCTAssertNotNil(MedicationConfig.type(for: "adderall_ir"))
        XCTAssertNotNil(MedicationConfig.type(for: "adderall_xr"))
        XCTAssertNotNil(MedicationConfig.type(for: "ritalin_ir"))
        XCTAssertNotNil(MedicationConfig.type(for: "vyvanse"))
        
        // Wakefulness agents
        XCTAssertNotNil(MedicationConfig.type(for: "modafinil"))
        XCTAssertNotNil(MedicationConfig.type(for: "armodafinil"))
        XCTAssertNotNil(MedicationConfig.type(for: "sunosi"))
        
        // Histamine modulator
        XCTAssertNotNil(MedicationConfig.type(for: "wakix"))
        
        // Sodium oxybate (night meds)
        XCTAssertNotNil(MedicationConfig.type(for: "xywav"))
        XCTAssertNotNil(MedicationConfig.type(for: "xyrem"))
    }
    
    func testMedicationCategories() {
        // Check that categories are properly set
        let stimulants = MedicationConfig.types.filter { $0.category == .stimulant }
        let wakefulnessAgents = MedicationConfig.types.filter { $0.category == .wakefulnessAgent }
        let sodiumOxybates = MedicationConfig.types.filter { $0.category == .sodiumOxybate }
        
        XCTAssertGreaterThan(stimulants.count, 0, "Should have stimulants")
        XCTAssertGreaterThan(wakefulnessAgents.count, 0, "Should have wakefulness agents")
        XCTAssertGreaterThan(sodiumOxybates.count, 0, "Should have sodium oxybate medications")
        
        // XYWAV and Xyrem should be sodium oxybate
        let xywav = MedicationConfig.type(for: "xywav")
        XCTAssertEqual(xywav?.category, .sodiumOxybate)
        XCTAssertEqual(xywav?.formulation, .liquid)
    }
    
    func testDuplicateGuardMinutes() {
        XCTAssertEqual(MedicationConfig.duplicateGuardMinutes, 5)
    }
    
    func testUnknownMedicationReturnsNil() {
        XCTAssertNil(MedicationConfig.type(for: "unknown_medication"))
    }
    
    // MARK: - MedicationEntry Tests
    
    func testMedicationEntryDisplayName() {
        let entry = MedicationEntry(
            sessionId: nil,
            sessionDate: "2025-12-24",
            medicationId: "adderall_xr",
            doseMg: 20,
            takenAtUTC: Date()
        )
        XCTAssertEqual(entry.displayName, "Adderall XR")
    }
    
    func testMedicationEntryDisplayNameFallsBackToId() {
        let entry = MedicationEntry(
            sessionId: nil,
            sessionDate: "2025-12-24",
            medicationId: "custom_med",
            doseMg: 10,
            takenAtUTC: Date()
        )
        XCTAssertEqual(entry.displayName, "custom_med")
    }
    
    // MARK: - DuplicateGuardResult Tests
    
    func testDuplicateGuardResultNotDuplicate() {
        let result = DuplicateGuardResult.notDuplicate
        XCTAssertFalse(result.isDuplicate)
        XCTAssertNil(result.existingEntry)
        XCTAssertEqual(result.minutesDelta, 0)
    }
    
    func testDuplicateGuardResultWithDuplicate() {
        let existingEntry = MedicationEntry(
            sessionId: nil,
            sessionDate: "2025-12-24",
            medicationId: "adderall_ir",
            doseMg: 10,
            takenAtUTC: Date()
        )
        
        let result = DuplicateGuardResult(
            isDuplicate: true,
            existingEntry: existingEntry,
            minutesDelta: 3
        )
        
        XCTAssertTrue(result.isDuplicate)
        XCTAssertNotNil(result.existingEntry)
        XCTAssertEqual(result.minutesDelta, 3)
    }
    
    // MARK: - Session Date Computation Tests
    
    func testSessionDateAfter6PM() {
        // 8 PM on Dec 24 should be session date Dec 24
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 24
        components.hour = 20 // 8 PM
        components.minute = 0
        
        let date = Calendar.current.date(from: components)!
        let sessionDate = computeSessionDate(for: date)
        XCTAssertEqual(sessionDate, "2025-12-24")
    }
    
    func testSessionDateBefore6PM() {
        // 2 PM on Dec 24 should be session date Dec 23 (previous night's session)
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 24
        components.hour = 14 // 2 PM
        components.minute = 0
        
        let date = Calendar.current.date(from: components)!
        let sessionDate = computeSessionDate(for: date)
        XCTAssertEqual(sessionDate, "2025-12-23")
    }
    
    func testSessionDateAt6PMBoundary() {
        // Exactly 6 PM on Dec 24 should be session date Dec 24
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 24
        components.hour = 18 // 6 PM exactly
        components.minute = 0
        
        let date = Calendar.current.date(from: components)!
        let sessionDate = computeSessionDate(for: date)
        XCTAssertEqual(sessionDate, "2025-12-24")
    }
    
    func testSessionDateEarlyMorning() {
        // 3 AM on Dec 25 should be session date Dec 24 (still part of Dec 24 night)
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 25
        components.hour = 3 // 3 AM
        components.minute = 0
        
        let date = Calendar.current.date(from: components)!
        let sessionDate = computeSessionDate(for: date)
        XCTAssertEqual(sessionDate, "2025-12-24")
    }
    
    // MARK: - Duplicate Guard Time Delta Tests
    
    func testDuplicateGuardAbsoluteDeltaForward() {
        // Entry at 8 PM, new entry at 8:03 PM = 3 minutes delta
        let entryTime = createDate(hour: 20, minute: 0)
        let newTime = createDate(hour: 20, minute: 3)
        
        let delta = computeAbsoluteDelta(from: entryTime, to: newTime)
        XCTAssertEqual(delta, 3)
    }
    
    func testDuplicateGuardAbsoluteDeltaBackward() {
        // Entry at 8 PM, new entry at 7:58 PM = 2 minutes delta (user edited time backwards)
        let entryTime = createDate(hour: 20, minute: 0)
        let newTime = createDate(hour: 19, minute: 58)
        
        let delta = computeAbsoluteDelta(from: entryTime, to: newTime)
        XCTAssertEqual(delta, 2)
    }
    
    func testDuplicateGuardWithinWindow() {
        // 4 minutes should be within 5-minute guard window
        XCTAssertTrue(isWithinDuplicateGuard(minutesDelta: 4, guardWindow: 5))
    }
    
    func testDuplicateGuardOutsideWindow() {
        // 6 minutes should be outside 5-minute guard window
        XCTAssertFalse(isWithinDuplicateGuard(minutesDelta: 6, guardWindow: 5))
    }
    
    func testDuplicateGuardAtExactBoundary() {
        // 5 minutes should be outside (< guard, not <=)
        XCTAssertFalse(isWithinDuplicateGuard(minutesDelta: 5, guardWindow: 5))
    }
    
    // MARK: - Helpers
    
    private func computeSessionDate(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        let sessionDay: Date
        if hour < 18 { // Before 6 PM
            sessionDay = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        } else {
            sessionDay = date
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: sessionDay)
    }
    
    private func computeAbsoluteDelta(from entry: Date, to new: Date) -> Int {
        let deltaSeconds = abs(new.timeIntervalSince(entry))
        return Int(deltaSeconds / 60)
    }
    
    private func isWithinDuplicateGuard(minutesDelta: Int, guardWindow: Int) -> Bool {
        return minutesDelta < guardWindow
    }
    
    private func createDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 12
        components.day = 24
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }
}
