import XCTest
@testable import DoseCore

final class MedicationInventoryForecastTests: XCTestCase {
    private let newYork = "America/New_York"

    // MARK: - Specification forecast cases 1 through 5

    func test_thirtySessionBottleStartedAfterThirtySessions_hasNoWarning() throws {
        let opened = localDate(2026, 1, 1, 22)
        let proposed = localDate(2026, 1, 31, 22)
        let result = try evaluate(
            asOf: proposed,
            containers: bottlePair(openedAt: opened, quantity: "180"),
            action: .start(
                containerID: "next-bottle",
                replacingContainerID: "active-bottle",
                at: proposed
            ),
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(result.earlyBottleReview?.classification, .noWarning)
        XCTAssertEqual(result.earlyBottleReview?.scheduledTreatmentSessions, 30)
        assertAmount(result.earlyBottleReview?.remainingAtTarget, equals: "0")
    }

    func test_exactMaximumToleranceBoundary_isCautionNotStrong() throws {
        let opened = localDate(2026, 1, 1, 22)
        let proposed = localDate(2026, 1, 20, 22)
        let result = try evaluate(
            asOf: proposed,
            containers: bottlePair(openedAt: opened, quantity: "180"),
            action: .start(
                containerID: "next-bottle",
                replacingContainerID: "active-bottle",
                at: proposed
            ),
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(result.earlyBottleReview?.classification, .caution)
        assertAmount(result.earlyBottleReview?.remainingAtMaximum, equals: "9")
        assertAmount(result.earlyBottleReview?.tolerance, equals: "9")
    }

    func test_beyondTargetButWithinMaximum_isCaution() throws {
        let opened = localDate(2026, 1, 1, 22)
        let proposed = localDate(2026, 1, 26, 22)
        let result = try evaluate(
            asOf: proposed,
            containers: bottlePair(openedAt: opened, quantity: "180"),
            action: .start(
                containerID: "next-bottle",
                replacingContainerID: "active-bottle",
                at: proposed
            ),
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(result.earlyBottleReview?.classification, .caution)
        assertAmount(result.earlyBottleReview?.remainingAtTarget, equals: "30")
        assertAmount(result.earlyBottleReview?.remainingAtMaximum, equals: "-45")
    }

    func test_beforeMaximumDepletion_isStrongWarning() throws {
        let opened = localDate(2026, 1, 1, 22)
        let proposed = localDate(2026, 1, 11, 22)
        let result = try evaluate(
            asOf: proposed,
            containers: bottlePair(openedAt: opened, quantity: "180"),
            action: .start(
                containerID: "next-bottle",
                replacingContainerID: "active-bottle",
                at: proposed
            ),
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(result.earlyBottleReview?.classification, .strongWarning)
        assertAmount(result.earlyBottleReview?.remainingAtMaximum, equals: "90")
    }

    func test_receivingUnopenedBottle_increasesSupplyWithoutEarlyReview() throws {
        let opened = localDate(2026, 1, 1, 22)
        let asOf = localDate(2026, 1, 2, 21)
        let result = try evaluate(
            asOf: asOf,
            containers: bottlePair(openedAt: opened, quantity: "180"),
            action: .receiveUnopened(containerID: "next-bottle"),
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(result.earlyBottleReview?.classification, .notApplicable)
        assertAmount(result.usableQuantityBeforeConsumption, equals: "360")
    }

    // MARK: - Adjustments, plan versions, and units

    func test_signedAdjustments_andAllocation_useCorrectSigns() throws {
        let opened = localDate(2026, 1, 1, 22)
        let asOf = localDate(2026, 1, 2, 21)
        let adjustments = [
            adjustment("spill", value: "-12", at: localDate(2026, 1, 1, 23)),
            adjustment("correction", value: "6", at: localDate(2026, 1, 2, 10))
        ]
        let allocations = [
            allocation("dose-1", value: "6", at: localDate(2026, 1, 1, 23))
        ]
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: opened, quantity: "180")],
            adjustments: adjustments,
            allocations: allocations,
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        assertAmount(result.usableQuantityBeforeConsumption, equals: "174")
        assertAmount(result.prescriptionTargetRemaining, equals: "168")
        assertAmount(result.ledgerRemaining, equals: "168")
    }

    func test_futureAdjustment_isIgnoredAtAsOfTime() throws {
        let opened = localDate(2026, 1, 1, 22)
        let asOf = localDate(2026, 1, 2, 21)
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: opened, quantity: "180")],
            adjustments: [
                adjustment("future-spill", value: "-30", at: localDate(2026, 1, 3, 10))
            ],
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        assertAmount(result.usableQuantityBeforeConsumption, equals: "180")
    }

    func test_planChangeMidBottle_usesBothEffectiveVersions() throws {
        let opened = localDate(2026, 1, 1, 22)
        let change = localDate(2026, 1, 16, 0)
        let proposed = localDate(2026, 1, 21, 22)
        let planA = standardPlan(
            id: "plan-a",
            effectiveFrom: localDate(2026, 1, 1, 0),
            effectiveUntil: change
        )
        let planB = standardPlan(
            id: "plan-b",
            effectiveFrom: change,
            targetPerDose: "4.5",
            targetPerSession: "9",
            maximumPerSession: "12"
        )
        let result = try evaluate(
            asOf: proposed,
            containers: bottlePair(openedAt: opened, quantity: "180"),
            action: .start(
                containerID: "next-bottle",
                replacingContainerID: "active-bottle",
                at: proposed
            ),
            planVersions: [planB, planA]
        )

        XCTAssertEqual(result.earlyBottleReview?.planVersionIDs, ["plan-a", "plan-b"])
        XCTAssertEqual(result.earlyBottleReview?.scheduledTreatmentSessions, 20)
        assertAmount(result.earlyBottleReview?.remainingAtTarget, equals: "45")
        assertAmount(result.earlyBottleReview?.remainingAtMaximum, equals: "-15")
        XCTAssertEqual(result.earlyBottleReview?.classification, .caution)
    }

    func test_missingConversion_returnsNamedPlanReviewState() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let plan = standardPlan(
            effectiveFrom: localDate(2026, 1, 1, 0),
            unit: .g,
            conversionID: "g-to-mg-v1",
            targetPerDose: "0.003",
            targetPerSession: "0.006",
            maximumPerSession: "0.009"
        )
        let result = try evaluate(
            asOf: asOf,
            calculationUnit: .mg,
            containers: [activeBottle(openedAt: asOf, quantity: "180", unit: .mg)],
            tolerancePolicy: tolerancePolicy(unit: .mg, increment: "1"),
            planVersions: [plan]
        )

        XCTAssertEqual(result.completeness, .planNeedsReview)
        XCTAssertTrue(result.issues.contains { $0.code == .missingUnitConversion })
        XCTAssertNil(result.targetProjection)
    }

    func test_explicitVersionedConversion_isAppliedAndRecorded() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let conversion = MedicationInventoryUnitConversion(
            id: "g-to-mg-v1",
            version: "1",
            fromUnit: .g,
            toUnit: .mg,
            multiplier: decimal("1000")
        )
        let plan = standardPlan(
            effectiveFrom: localDate(2026, 1, 1, 0),
            unit: .g,
            conversionID: "g-to-mg-v1",
            targetPerDose: "0.003",
            targetPerSession: "0.006",
            maximumPerSession: "0.009"
        )
        let result = try evaluate(
            asOf: asOf,
            calculationUnit: .mg,
            containers: [activeBottle(openedAt: asOf, quantity: "60", unit: .mg)],
            conversions: [conversion],
            tolerancePolicy: tolerancePolicy(unit: .mg, increment: "1"),
            planVersions: [plan]
        )

        XCTAssertEqual(result.completeness, .complete)
        XCTAssertEqual(result.targetProjection?.fullTreatmentSessions, 10)
        XCTAssertEqual(result.provenance.conversionIDs, ["g-to-mg-v1"])
        XCTAssertEqual(result.provenance.conversionVersions, ["g-to-mg-v1": "1"])
    }

    func test_amountSelectsExactConversionVersion_whenPairHasHistory() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let conversions = [
            MedicationInventoryUnitConversion(
                id: "concentration-v1",
                version: "1",
                fromUnit: .g,
                toUnit: .mg,
                multiplier: decimal("1000")
            ),
            MedicationInventoryUnitConversion(
                id: "concentration-v2",
                version: "2",
                fromUnit: .g,
                toUnit: .mg,
                multiplier: decimal("2000")
            )
        ]
        let plan = standardPlan(
            effectiveFrom: asOf,
            unit: .g,
            conversionID: "concentration-v2",
            targetPerDose: "0.003",
            targetPerSession: "0.006",
            maximumPerSession: "0.009"
        )
        let result = try evaluate(
            asOf: asOf,
            calculationUnit: .mg,
            containers: [activeBottle(openedAt: asOf, quantity: "120", unit: .mg)],
            conversions: conversions,
            tolerancePolicy: tolerancePolicy(unit: .mg, increment: "1"),
            planVersions: [plan]
        )

        XCTAssertEqual(result.targetProjection?.fullTreatmentSessions, 10)
        XCTAssertEqual(result.provenance.conversionIDs, ["concentration-v2"])
        XCTAssertEqual(result.provenance.conversionVersions, ["concentration-v2": "2"])
    }

    func test_tolerance_roundsUpToSmallestMeaningfulIncrement() throws {
        let opened = localDate(2026, 1, 1, 22)
        let result = try evaluate(
            asOf: opened,
            containers: bottlePair(openedAt: opened, quantity: "101"),
            action: .start(
                containerID: "next-bottle",
                replacingContainerID: "active-bottle",
                at: opened
            ),
            tolerancePolicy: tolerancePolicy(increment: "0.1"),
            planVersions: [
                standardPlan(
                    effectiveFrom: localDate(2026, 1, 1, 0),
                    targetPerDose: "2",
                    targetPerSession: "4",
                    maximumPerSession: "6"
                )
            ]
        )

        assertAmount(result.earlyBottleReview?.tolerance, equals: "5.1")
    }

    // MARK: - Supply and completeness

    func test_orderedSupply_isReportedButExcludedFromUsableInventory() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let containers = [
            activeBottle(openedAt: asOf, quantity: "60"),
            MedicationInventoryContainer(
                id: "unopened",
                state: .unopened,
                startingUsableQuantity: amount("60"),
                receivedAt: asOf
            ),
            MedicationInventoryContainer(
                id: "ordered",
                state: .orderedNotReceived,
                startingUsableQuantity: amount("60")
            )
        ]
        let result = try evaluate(
            asOf: asOf,
            containers: containers,
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        assertAmount(result.usableQuantityBeforeConsumption, equals: "120")
        assertAmount(result.orderedNotReceivedQuantity, equals: "60")
        assertAmount(result.ledgerRemaining, equals: "120")
    }

    func test_futureReceivedContainer_isExcludedFromBackdatedForecast() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let futureBottle = MedicationInventoryContainer(
            id: "future-bottle",
            state: .unopened,
            startingUsableQuantity: amount("60"),
            receivedAt: localDate(2026, 1, 2, 12)
        )
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "60"), futureBottle],
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        assertAmount(result.usableQuantityBeforeConsumption, equals: "60")
        assertAmount(result.ledgerRemaining, equals: "60")
    }

    func test_missingReceivedDate_keepsSupplyVisibleButRequiresReview() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let unknownReceipt = MedicationInventoryContainer(
            id: "unknown-receipt",
            state: .unopened,
            startingUsableQuantity: amount("60")
        )
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "60"), unknownReceipt],
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        assertAmount(result.usableQuantityBeforeConsumption, equals: "120")
        XCTAssertEqual(result.completeness, .inventoryNeedsReview)
        XCTAssertTrue(result.issues.contains {
            $0.code == .missingReceivedAt && $0.recordID == "unknown-receipt"
        })
    }

    func test_irregularSchedule_returnsSessionsWithoutInventingDate() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let plan = standardPlan(
            effectiveFrom: localDate(2026, 1, 1, 0),
            schedule: .irregular
        )
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "60")],
            planVersions: [plan]
        )

        XCTAssertEqual(result.completeness, .planNeedsReview)
        XCTAssertEqual(result.targetProjection?.fullTreatmentSessions, 10)
        XCTAssertNil(result.targetProjection?.runoutAt)
        XCTAssertTrue(result.issues.contains { $0.code == .irregularSchedule })
    }

    func test_missingDoseAmount_returnsPlanBasedStateWithoutGuessingLedger() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let unknownAmount = MedicationInventoryDoseAllocation(
            id: "allocation-unknown",
            doseEventID: "dose-unknown",
            sessionID: "session-1",
            containerID: "active-bottle",
            quantity: nil,
            occurredAt: asOf
        )
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "60")],
            allocations: [unknownAmount],
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(result.completeness, .planBased)
        XCTAssertNil(result.ledgerRemaining)
        assertAmount(result.prescriptionTargetRemaining, equals: "60")
        XCTAssertTrue(result.issues.contains { $0.code == .missingDoseAmount })
    }

    func test_unallocatedDose_requiresInventoryReviewWithoutGuessingBottle() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let unallocated = MedicationInventoryDoseAllocation(
            id: "allocation-unallocated",
            doseEventID: "dose-unallocated",
            sessionID: "session-1",
            containerID: nil,
            quantity: amount("6"),
            occurredAt: asOf
        )
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "60")],
            allocations: [unallocated],
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(result.completeness, .inventoryNeedsReview)
        XCTAssertNil(result.ledgerRemaining)
        XCTAssertTrue(result.issues.contains { $0.code == .unallocatedDose })
    }

    func test_conservativeForecast_usesEarlierLedgerQuantity() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "60")],
            allocations: [allocation("dose-1", value: "12", at: asOf)],
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        assertAmount(result.prescriptionTargetRemaining, equals: "60")
        assertAmount(result.ledgerRemaining, equals: "48")
        assertAmount(result.activeForecastRemaining, equals: "48")
        XCTAssertEqual(result.targetProjection?.fullTreatmentSessions, 10)
        XCTAssertEqual(result.activeProjection?.fullTreatmentSessions, 8)
    }

    func test_negativeActiveBottleBalances_areNotHiddenByUnopenedSupply() throws {
        let opened = localDate(2026, 1, 1, 22)
        let asOf = localDate(2026, 1, 3, 21)
        let unopened = MedicationInventoryContainer(
            id: "unopened",
            state: .unopened,
            startingUsableQuantity: amount("60"),
            receivedAt: opened
        )
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: opened, quantity: "6"), unopened],
            allocations: [allocation("too-large", value: "12", at: localDate(2026, 1, 2, 1))],
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(result.completeness, .inventoryNeedsReview)
        XCTAssertTrue(result.issues.contains {
            $0.code == .negativePlanBalance && $0.recordID == "active-bottle"
        })
        XCTAssertTrue(result.issues.contains {
            $0.code == .negativeLedgerBalance && $0.recordID == "active-bottle"
        })
        assertAmount(result.ledgerRemaining, equals: "54")
    }

    func test_emptyPlanList_returnsNamedIncompleteStateWithoutCrashing() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "60")],
            planVersions: []
        )

        XCTAssertEqual(result.completeness, .planNeedsReview)
        XCTAssertTrue(result.issues.contains { $0.code == .missingPlan })
        XCTAssertNil(result.targetProjection)
    }

    // MARK: - Time and schedule boundaries

    func test_dailySchedule_springForwardGapProducesOneSessionPerLocalDay() throws {
        let asOf = localDate(2026, 3, 7, 0)
        let plan = standardPlan(
            effectiveFrom: localDate(2026, 3, 7, 0),
            targetPerDose: "1",
            targetPerSession: "1",
            maximumPerSession: "1",
            schedule: .daily(hour: 2, minute: 30, timeZoneIdentifier: newYork)
        )
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "4")],
            planVersions: [plan]
        )

        XCTAssertEqual(result.targetProjection?.fullTreatmentSessions, 4)
        let runout = try XCTUnwrap(result.targetProjection?.runoutAt)
        assertLocalDate(runout, year: 2026, month: 3, day: 10)
    }

    func test_dailySchedule_fallBackFoldDoesNotDuplicateSession() throws {
        let asOf = localDate(2026, 10, 31, 0)
        let plan = standardPlan(
            effectiveFrom: asOf,
            targetPerDose: "1",
            targetPerSession: "1",
            maximumPerSession: "1",
            schedule: .daily(hour: 1, minute: 30, timeZoneIdentifier: newYork)
        )
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "3")],
            planVersions: [plan]
        )

        XCTAssertEqual(result.targetProjection?.fullTreatmentSessions, 3)
        let runout = try XCTUnwrap(result.targetProjection?.runoutAt)
        assertLocalDate(runout, year: 2026, month: 11, day: 2)
    }

    func test_selectedWeekdays_onlyConsumeConfiguredTreatmentDays() throws {
        let asOf = localDate(2026, 1, 5, 0) // Monday
        let plan = standardPlan(
            effectiveFrom: asOf,
            targetPerDose: "1",
            targetPerSession: "1",
            maximumPerSession: "1",
            schedule: .selectedWeekdays(
                weekdays: [2, 4, 6],
                hour: 22,
                minute: 0,
                timeZoneIdentifier: newYork
            )
        )
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "3")],
            planVersions: [plan]
        )

        XCTAssertEqual(result.targetProjection?.fullTreatmentSessions, 3)
        let runout = try XCTUnwrap(result.targetProjection?.runoutAt)
        assertLocalDate(runout, year: 2026, month: 1, day: 9)
    }

    func test_planCoverageGap_returnsNamedIncompleteState() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let plan = standardPlan(
            effectiveFrom: localDate(2026, 1, 1, 0),
            effectiveUntil: localDate(2026, 1, 3, 0)
        )
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "180")],
            planVersions: [plan]
        )

        XCTAssertEqual(result.completeness, .planNeedsReview)
        XCTAssertNil(result.targetProjection)
        XCTAssertTrue(result.issues.contains { $0.code == .planCoverageGap })
    }

    func test_forecastHorizonExceeded_returnsNamedIncompleteState() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let result = try evaluate(
            asOf: asOf,
            forecastHorizonDays: 1,
            containers: [activeBottle(openedAt: asOf, quantity: "180")],
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(result.completeness, .planNeedsReview)
        XCTAssertNil(result.targetProjection)
        XCTAssertTrue(result.issues.contains { $0.code == .forecastHorizonExceeded })
    }

    // MARK: - Invalid inputs fail closed

    func test_zeroPlanAmount_isRejected() {
        let asOf = localDate(2026, 1, 1, 20)
        let invalid = standardPlan(
            effectiveFrom: localDate(2026, 1, 1, 0),
            targetPerSession: "0"
        )

        XCTAssertThrowsError(
            try evaluate(
                asOf: asOf,
                containers: [activeBottle(openedAt: asOf, quantity: "60")],
                planVersions: [invalid]
            )
        ) { error in
            XCTAssertEqual(
                error as? MedicationInventoryForecastError,
                .invalidAmount(recordID: "plan-a", field: "targetPerSession")
            )
        }
    }

    func test_nonfiniteContainerAmount_isRejected() {
        let asOf = localDate(2026, 1, 1, 20)
        let invalid = MedicationInventoryContainer(
            id: "active-bottle",
            state: .openActive,
            startingUsableQuantity: MedicationInventoryAmount(value: .nan, unit: .mL),
            openedAt: asOf
        )

        XCTAssertThrowsError(
            try evaluate(
                asOf: asOf,
                containers: [invalid],
                planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
            )
        ) { error in
            XCTAssertEqual(
                error as? MedicationInventoryForecastError,
                .invalidAmount(
                    recordID: "active-bottle",
                    field: "startingUsableQuantity"
                )
            )
        }
    }

    func test_overlappingPlanVersions_areRejected() {
        let asOf = localDate(2026, 1, 1, 20)
        let first = standardPlan(
            id: "first",
            effectiveFrom: localDate(2026, 1, 1, 0),
            effectiveUntil: localDate(2026, 2, 1, 0)
        )
        let second = standardPlan(
            id: "second",
            effectiveFrom: localDate(2026, 1, 15, 0)
        )

        XCTAssertThrowsError(
            try evaluate(
                asOf: asOf,
                containers: [activeBottle(openedAt: asOf, quantity: "60")],
                planVersions: [first, second]
            )
        ) { error in
            XCTAssertEqual(
                error as? MedicationInventoryForecastError,
                .overlappingPlanVersions(first: "first", second: "second")
            )
        }
    }

    func test_multipleActiveBottles_areRejected() {
        let asOf = localDate(2026, 1, 1, 20)
        let second = MedicationInventoryContainer(
            id: "second-active",
            state: .openActive,
            startingUsableQuantity: amount("60"),
            openedAt: asOf
        )

        XCTAssertThrowsError(
            try evaluate(
                asOf: asOf,
                containers: [activeBottle(openedAt: asOf, quantity: "60"), second],
                planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
            )
        ) { error in
            XCTAssertEqual(
                error as? MedicationInventoryForecastError,
                .multipleActiveContainers
            )
        }
    }

    // MARK: - Determinism and provenance

    func test_injectedClock_controlsAsOfAndExplanation() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "60")],
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(result.asOf, asOf)
        XCTAssertEqual(result.provenance.asOf, asOf)
        XCTAssertTrue(result.explanation.lines.contains { $0.hasPrefix("As of: 2026-01-02T01:00:00.000Z") })
    }

    func test_reviewHarnessExplanation_matchesDeterministicFixture() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "60")],
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(
            result.explanation,
            MedicationInventoryForecastExplanation(
                summary: "Inventory forecast is complete for the supplied records.",
                lines: [
                    "As of: 2026-01-02T01:00:00.000Z",
                    "Calculation unit: mL",
                    "Plan versions: plan-a",
                    "Conversions: ",
                    "Tolerance policy: inventory-tolerance@1",
                    "Usable before consumption: 60 mL",
                    "Ordered, not received: 0 mL",
                    "Prescription target remaining: 60 mL",
                    "Prescription maximum remaining: 60 mL",
                    "Ledger remaining: 60 mL",
                    "Active conservative remaining: 60 mL",
                    "Target projection: sessions=10 runout=2026-01-11T03:00:00.000Z",
                    "Maximum projection: sessions=6 runout=2026-01-08T03:00:00.000Z",
                    "Ledger projection: sessions=10 runout=2026-01-11T03:00:00.000Z",
                    "Active projection: sessions=10 runout=2026-01-11T03:00:00.000Z",
                    "Issues: none"
                ]
            )
        )
    }

    func test_inputOrder_doesNotChangeResultOrExplanation() throws {
        let asOf = localDate(2026, 1, 2, 21)
        let containers = [
            activeBottle(openedAt: localDate(2026, 1, 1, 22), quantity: "60"),
            MedicationInventoryContainer(
                id: "unopened",
                state: .unopened,
                startingUsableQuantity: amount("60"),
                receivedAt: localDate(2026, 1, 1, 12)
            )
        ]
        let adjustments = [
            adjustment("a-adjustment", value: "1", at: localDate(2026, 1, 2, 10)),
            adjustment("z-adjustment", value: "-2", at: localDate(2026, 1, 2, 9))
        ]
        let allocations = [
            allocation("a-allocation", value: "3", at: localDate(2026, 1, 1, 23)),
            allocation("z-allocation", value: "3", at: localDate(2026, 1, 2, 1))
        ]
        let first = try evaluate(
            asOf: asOf,
            containers: containers,
            adjustments: adjustments,
            allocations: allocations,
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )
        let second = try evaluate(
            asOf: asOf,
            containers: containers.reversed(),
            adjustments: adjustments.reversed(),
            allocations: allocations.reversed(),
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.provenance.inputRecordIDs,
            [
                "a-adjustment",
                "a-allocation",
                "active-bottle",
                "unopened",
                "z-adjustment",
                "z-allocation"
            ]
        )
    }

    func test_resultCodableRoundTrip_preservesDecimalAndProvenance() throws {
        let asOf = localDate(2026, 1, 1, 20)
        let result = try evaluate(
            asOf: asOf,
            containers: [activeBottle(openedAt: asOf, quantity: "60.125")],
            planVersions: [standardPlan(effectiveFrom: localDate(2026, 1, 1, 0))]
        )
        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(
            MedicationInventoryForecastResult.self,
            from: encoded
        )

        XCTAssertEqual(decoded, result)
        assertAmount(decoded.ledgerRemaining, equals: "60.125")
    }

    // MARK: - Helpers

    private func evaluate(
        asOf: Date,
        forecastHorizonDays: Int = 3_660,
        calculationUnit: AmountUnit = .mL,
        containers: [MedicationInventoryContainer],
        adjustments: [MedicationInventoryAdjustment] = [],
        allocations: [MedicationInventoryDoseAllocation] = [],
        conversions: [MedicationInventoryUnitConversion] = [],
        action: MedicationInventoryBottleAction? = nil,
        tolerancePolicy: MedicationInventoryTolerancePolicy? = nil,
        planVersions: [MedicationInventoryPlanVersion]
    ) throws -> MedicationInventoryForecastResult {
        let request = MedicationInventoryForecastRequest(
            medicationID: "medication-1",
            calculationUnit: calculationUnit,
            planVersions: planVersions,
            containers: containers,
            adjustments: adjustments,
            allocations: allocations,
            conversions: conversions,
            tolerancePolicy: tolerancePolicy
                ?? self.tolerancePolicy(unit: calculationUnit),
            proposedBottleAction: action
        )
        return try MedicationInventoryForecast(
            forecastHorizonDays: forecastHorizonDays,
            now: { asOf }
        ).evaluate(request)
    }

    private func standardPlan(
        id: String = "plan-a",
        effectiveFrom: Date,
        effectiveUntil: Date? = nil,
        unit: AmountUnit = .mL,
        conversionID: String? = nil,
        targetPerDose: String = "3",
        targetPerSession: String = "6",
        maximumPerSession: String = "9",
        schedule: MedicationInventorySchedule? = nil
    ) -> MedicationInventoryPlanVersion {
        MedicationInventoryPlanVersion(
            id: id,
            effectiveFrom: effectiveFrom,
            effectiveUntil: effectiveUntil,
            targetPerDose: amount(
                targetPerDose,
                unit: unit,
                conversionID: conversionID
            ),
            maximumPerDose: nil,
            targetPerSession: amount(
                targetPerSession,
                unit: unit,
                conversionID: conversionID
            ),
            maximumPerSession: amount(
                maximumPerSession,
                unit: unit,
                conversionID: conversionID
            ),
            schedule: schedule
                ?? .daily(hour: 22, minute: 0, timeZoneIdentifier: newYork)
        )
    }

    private func bottlePair(
        openedAt: Date,
        quantity: String
    ) -> [MedicationInventoryContainer] {
        [
            activeBottle(openedAt: openedAt, quantity: quantity),
            MedicationInventoryContainer(
                id: "next-bottle",
                state: .unopened,
                startingUsableQuantity: amount(quantity),
                receivedAt: openedAt
            )
        ]
    }

    private func activeBottle(
        openedAt: Date,
        quantity: String,
        unit: AmountUnit = .mL
    ) -> MedicationInventoryContainer {
        MedicationInventoryContainer(
            id: "active-bottle",
            state: .openActive,
            startingUsableQuantity: amount(quantity, unit: unit),
            receivedAt: openedAt,
            openedAt: openedAt
        )
    }

    private func adjustment(
        _ id: String,
        value: String,
        at date: Date
    ) -> MedicationInventoryAdjustment {
        MedicationInventoryAdjustment(
            id: id,
            containerID: "active-bottle",
            quantityChange: amount(value),
            occurredAt: date
        )
    }

    private func allocation(
        _ id: String,
        value: String,
        at date: Date
    ) -> MedicationInventoryDoseAllocation {
        MedicationInventoryDoseAllocation(
            id: id,
            doseEventID: "dose-\(id)",
            sessionID: "session-\(id)",
            containerID: "active-bottle",
            quantity: amount(value),
            occurredAt: date,
            planVersionID: "plan-a"
        )
    }

    private func tolerancePolicy(
        unit: AmountUnit = .mL,
        increment: String = "0.1"
    ) -> MedicationInventoryTolerancePolicy {
        MedicationInventoryTolerancePolicy(
            id: "inventory-tolerance",
            version: "1",
            percentOfStartingQuantity: decimal("0.05"),
            measurementTolerance: amount("1", unit: unit),
            smallestMeaningfulIncrement: amount(increment, unit: unit)
        )
    }

    private func amount(
        _ value: String,
        unit: AmountUnit = .mL,
        conversionID: String? = nil
    ) -> MedicationInventoryAmount {
        MedicationInventoryAmount(
            value: decimal(value),
            unit: unit,
            conversionID: conversionID
        )
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: newYork)!
        return calendar.date(
            from: DateComponents(
                timeZone: calendar.timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func assertLocalDate(
        _ date: Date,
        year: Int,
        month: Int,
        day: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: newYork)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        XCTAssertEqual(components.year, year, file: file, line: line)
        XCTAssertEqual(components.month, month, file: file, line: line)
        XCTAssertEqual(components.day, day, file: file, line: line)
    }

    private func assertAmount(
        _ actual: MedicationInventoryAmount?,
        equals expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected amount \(expected), got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.value, decimal(expected), file: file, line: line)
    }
}
