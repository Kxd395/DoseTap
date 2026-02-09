//
//  DosingAmountTests.swift
//  DoseTapTests
//
//  Created: January 19, 2026
//  Tests for dosing amount tracking models and calculations
//

import XCTest
@testable import DoseCore

final class DosingAmountTests: XCTestCase {
    
    // MARK: - Regimen Tests
    
    func testRegimenFiftyFiftySplit() {
        let regimen = Regimen(
            medicationId: "xyrem",
            startAt: Date(),
            targetTotalAmountValue: 4500,  // 4.5g
            targetTotalAmountUnit: .mg,
            splitMode: .equal,
            splitPartsCount: 2,
            splitPartsRatio: [0.5, 0.5]
        )
        
        XCTAssertTrue(regimen.isValid)
        XCTAssertTrue(regimen.hasValidSplitRatio)
        XCTAssertEqual(regimen.targetAmountForPart(0), 2250)  // First dose
        XCTAssertEqual(regimen.targetAmountForPart(1), 2250)  // Second dose
    }
    
    func testRegimenSixtyFortySplit() {
        let regimen = Regimen(
            medicationId: "xyrem",
            startAt: Date(),
            targetTotalAmountValue: 4500,
            targetTotalAmountUnit: .mg,
            splitMode: .custom,
            splitPartsCount: 2,
            splitPartsRatio: [0.6, 0.4]
        )
        
        XCTAssertTrue(regimen.isValid)
        XCTAssertEqual(regimen.targetAmountForPart(0), 2700)  // Bigger first dose
        XCTAssertEqual(regimen.targetAmountForPart(1), 1800)  // Smaller second dose
    }
    
    func testRegimenThreeWaySplit() {
        let regimen = Regimen(
            medicationId: "test-med",
            startAt: Date(),
            targetTotalAmountValue: 3000,
            targetTotalAmountUnit: .mg,
            splitMode: .custom,
            splitPartsCount: 3,
            splitPartsRatio: [0.5, 0.3, 0.2]
        )
        
        XCTAssertTrue(regimen.isValid)
        XCTAssertEqual(regimen.targetAmountForPart(0), 1500)
        XCTAssertEqual(regimen.targetAmountForPart(1), 900)
        XCTAssertEqual(regimen.targetAmountForPart(2), 600)
    }
    
    func testRegimenSingleDose() {
        let regimen = Regimen.singleDose(
            medicationId: "modafinil",
            amountMg: 200
        )
        
        XCTAssertTrue(regimen.isValid)
        XCTAssertEqual(regimen.splitPartsCount, 1)
        XCTAssertEqual(regimen.targetAmountForPart(0), 200)
    }
    
    func testRegimenInvalidRatioSum() {
        let regimen = Regimen(
            medicationId: "test-med",
            startAt: Date(),
            targetTotalAmountValue: 100,
            splitMode: .custom,
            splitPartsCount: 2,
            splitPartsRatio: [0.7, 0.5]  // Sums to 1.2, not 1.0
        )
        
        XCTAssertFalse(regimen.hasValidSplitRatio)
        XCTAssertFalse(regimen.isValid)
    }
    
    func testRegimenDateBounded() {
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let endDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        
        let regimen = Regimen(
            medicationId: "test-med",
            startAt: startDate,
            endAt: endDate,
            targetTotalAmountValue: 100,
            splitMode: .none,
            splitPartsCount: 1,
            splitPartsRatio: [1.0]
        )
        
        // Active between start and end
        let midDate = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        XCTAssertTrue(regimen.isActive(at: midDate))
        
        // Not active today (after end)
        XCTAssertFalse(regimen.isActive(at: Date()))
        
        // Not active before start
        let beforeDate = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        XCTAssertFalse(regimen.isActive(at: beforeDate))
    }
    
    // MARK: - Amount Unit Tests
    
    func testAmountUnitMgConversion() {
        XCTAssertEqual(AmountUnit.mg.toMilligrams(value: 100), 100)
        XCTAssertEqual(AmountUnit.g.toMilligrams(value: 4.5), 4500)
        XCTAssertEqual(AmountUnit.mcg.toMilligrams(value: 500), 0.5)
    }
    
    func testAmountUnitMlRequiresConcentration() {
        XCTAssertNil(AmountUnit.mL.toMilligrams(value: 10))  // No concentration
        XCTAssertEqual(AmountUnit.mL.toMilligrams(value: 10, concentration: 500), 5000)  // 10mL at 500mg/mL
    }
    
    func testAmountUnitTabletCannotConvert() {
        XCTAssertNil(AmountUnit.tablet.toMilligrams(value: 2))
    }
    
    // MARK: - Dose Event Tests
    
    func testDoseEventWithAmount() {
        let event = DoseEventWithAmount(
            eventType: "dose1",
            occurredAt: Date(),
            sessionId: "test-session",
            sessionDate: "2026-01-19",
            amountValue: 2250,
            amountUnit: .mg,
            source: .manual,
            bundleId: "bundle-1",
            partIndex: 0,
            partsCount: 2
        )
        
        XCTAssertTrue(event.isValid)
        XCTAssertTrue(event.hasKnownAmount)
        XCTAssertEqual(event.formattedAmount, "2250 mg")
        XCTAssertEqual(event.partLabel, "Part 1 of 2")
    }
    
    func testDoseEventMigratedNoAmount() {
        let event = DoseEventWithAmount(
            eventType: "dose1",
            occurredAt: Date(),
            sessionId: "test-session",
            sessionDate: "2026-01-19",
            amountValue: nil,
            amountUnit: nil,
            source: .migrated
        )
        
        XCTAssertTrue(event.isValid)
        XCTAssertFalse(event.hasKnownAmount)
        XCTAssertEqual(event.formattedAmount, "Unknown")
        XCTAssertFalse(event.source.hasReliableAmount)
    }
    
    func testDoseEventInvalidNegativeAmount() {
        let event = DoseEventWithAmount(
            eventType: "dose1",
            occurredAt: Date(),
            sessionId: "test-session",
            sessionDate: "2026-01-19",
            amountValue: -100,  // Invalid!
            amountUnit: .mg
        )
        
        XCTAssertFalse(event.isValid)
    }
    
    func testDoseEventInvalidPartIndex() {
        let event = DoseEventWithAmount(
            eventType: "dose1",
            occurredAt: Date(),
            sessionId: "test-session",
            sessionDate: "2026-01-19",
            amountValue: 100,
            amountUnit: .mg,
            partIndex: 5,  // Out of range
            partsCount: 2
        )
        
        XCTAssertFalse(event.isValid)
    }
    
    // MARK: - Dose Bundle Tests
    
    func testDoseBundleExpectedParts() {
        let bundle = DoseBundle(
            sessionId: "test-session",
            sessionDate: "2026-01-19",
            targetTotalAmountValue: 4500,
            targetSplitRatio: [0.5, 0.5]
        )
        
        XCTAssertEqual(bundle.expectedPartsCount, 2)
        XCTAssertEqual(bundle.targetAmountForPart(0), 2250)
        XCTAssertEqual(bundle.targetAmountForPart(1), 2250)
    }
    
    // MARK: - Bundle Status Tests
    
    func testBundleStatusOnTarget() {
        let bundle = DoseBundle(
            sessionId: "test-session",
            sessionDate: "2026-01-19",
            targetTotalAmountValue: 4500,
            targetSplitRatio: [0.5, 0.5]
        )
        
        let events = [
            DoseEventWithAmount(
                eventType: "dose1",
                occurredAt: Date(),
                sessionId: "test-session",
                sessionDate: "2026-01-19",
                amountValue: 2250,
                amountUnit: .mg,
                partIndex: 0,
                partsCount: 2
            ),
            DoseEventWithAmount(
                eventType: "dose2",
                occurredAt: Date(),
                sessionId: "test-session",
                sessionDate: "2026-01-19",
                amountValue: 2250,
                amountUnit: .mg,
                partIndex: 1,
                partsCount: 2
            )
        ]
        
        let status = DoseBundleStatus(bundle: bundle, loggedEvents: events)
        
        XCTAssertEqual(status.totalAmountTaken, 4500)
        XCTAssertEqual(status.partsLogged, 2)
        XCTAssertTrue(status.isComplete)
        XCTAssertTrue(status.adherenceStatus.isOnTarget)
        XCTAssertEqual(status.remainingAmount, 0)
    }
    
    func testBundleStatusUnderTarget() {
        let bundle = DoseBundle(
            sessionId: "test-session",
            sessionDate: "2026-01-19",
            targetTotalAmountValue: 4500,
            targetSplitRatio: [0.5, 0.5]
        )
        
        let events = [
            DoseEventWithAmount(
                eventType: "dose1",
                occurredAt: Date(),
                sessionId: "test-session",
                sessionDate: "2026-01-19",
                amountValue: 2000,  // Under target
                amountUnit: .mg,
                partIndex: 0,
                partsCount: 2
            )
        ]
        
        let status = DoseBundleStatus(bundle: bundle, loggedEvents: events)
        
        XCTAssertEqual(status.totalAmountTaken, 2000)
        XCTAssertEqual(status.partsLogged, 1)
        XCTAssertFalse(status.isComplete)
        XCTAssertEqual(status.remainingAmount, 2500)
        
        if case .underTarget = status.adherenceStatus {
            // Expected
        } else {
            XCTFail("Expected underTarget status")
        }
    }
    
    // MARK: - Regimen Presets Tests
    
    func testXyremDefaultPreset() {
        let regimen = Regimen.xyremDefault()
        
        XCTAssertEqual(regimen.medicationId, "xyrem")
        XCTAssertEqual(regimen.targetTotalAmountValue, 4500)
        XCTAssertEqual(regimen.splitMode, .equal)
        XCTAssertEqual(regimen.splitPartsRatio, [0.5, 0.5])
        XCTAssertTrue(regimen.isValid)
    }
    
    func testBiggerEarlierPreset() {
        let regimen = Regimen.biggerEarlier(medicationId: "xyrem", totalMg: 5000)
        
        XCTAssertEqual(regimen.splitMode, .custom)
        XCTAssertEqual(regimen.splitPartsRatio, [0.6, 0.4])
        XCTAssertEqual(regimen.targetAmountForPart(0), 3000)  // 60%
        XCTAssertEqual(regimen.targetAmountForPart(1), 2000)  // 40%
    }
    
    // MARK: - Static Split Ratio Helpers
    
    func testEqualSplitRatioGeneration() {
        let twoWay = Regimen.equalSplitRatio(parts: 2)
        XCTAssertEqual(twoWay, [0.5, 0.5])
        
        let threeWay = Regimen.equalSplitRatio(parts: 3)
        XCTAssertEqual(threeWay.count, 3)
        XCTAssertEqual(threeWay.reduce(0, +), 1.0, accuracy: 0.001)
    }
}
