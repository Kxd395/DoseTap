import XCTest
@testable import DoseCore

final class SleepingSetupTests: XCTestCase {
    func testSummaryIdentifiesPetsSeparatelyFromPeople() {
        var setup = SleepingSetup(); setup.arrangement = .partnerSameBed; setup.pets = .offBed
        XCTAssertEqual(setup.summary, "Partner in the same bed · Pets: In the room, off the bed")
    }
    func testMissingAndExplicitUnknownRemainDistinct() throws {
        XCTAssertTrue(SleepingSetup().isEmpty)
        var setup = SleepingSetup()
        setup.arrangement = .unsure
        XCTAssertFalse(setup.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(SleepingSetup.self, from: JSONEncoder().encode(setup)), setup)
    }
    func testSharedDetailClearsWhenArrangementNoLongerApplies() {
        var setup = SleepingSetup()
        setup.arrangement = .otherPeople; setup.sharedSpace = .sameBed; setup.pets = .onBed
        XCTAssertEqual(setup.normalized.sharedSpace, .sameBed)
        setup.arrangement = .alone
        XCTAssertNil(setup.normalized.sharedSpace)
        XCTAssertEqual(setup.normalized.pets, .onBed)
    }
    func testUsualSetupFillsBlanksWithoutReplacingTonight() {
        var usual = SleepingSetup(); usual.arrangement = .partnerSameBed; usual.pets = .offBed
        var tonight = SleepingSetup(); tonight.arrangement = .alone
        XCTAssertEqual(tonight.applyingMissing(from: usual).arrangement, .alone)
        XCTAssertEqual(tonight.applyingMissing(from: usual).pets, .offBed)
        XCTAssertNil(tonight.pets)
    }
    func testMorningRequiresExplicitConfirmationAndDoesNotMutatePlan() throws {
        var plan = SleepingSetup(); plan.arrangement = .partnerSameBed
        var morning = MorningSleepingContext(); morning.plan = plan
        XCTAssertTrue(morning.isEmpty)
        XCTAssertNil(morning.actual)
        morning.selectConfirmation(.same)
        XCTAssertEqual(morning.actual, plan)
        morning.selectConfirmation(.changed)
        XCTAssertNil(morning.actual)
        morning.actual = SleepingSetup(); morning.actual?.arrangement = .alone
        XCTAssertEqual(morning.plan, plan)
        XCTAssertEqual(try JSONDecoder().decode(MorningSleepingContext.self,
            from: JSONEncoder().encode(morning.normalized)), morning.normalized)
    }
    func testNoPlanCannotBeConfirmedAndUnknownClearsActual() {
        var morning = MorningSleepingContext()
        morning.selectConfirmation(.same)
        XCTAssertNil(morning.confirmation)
        morning.actual = SleepingSetup(); morning.actual?.pets = .onBed
        morning.selectConfirmation(.unsure)
        XCTAssertNil(morning.actual)
        XCTAssertFalse(morning.isEmpty)
    }
    func testImpactFactorsAreIndependentFreshAndConditional() {
        var morning = MorningSleepingContext()
        XCTAssertNil(morning.impact); XCTAssertNil(morning.factors)
        morning.impact = .disrupted; morning.factors = [.pets, .noise, .pets]
        XCTAssertEqual(morning.normalized.factors, [.noise, .pets])
        morning.impact = .noEffect
        XCTAssertNil(morning.normalized.factors)
        XCTAssertEqual(morning.normalized.impact, .noEffect)
    }
}
