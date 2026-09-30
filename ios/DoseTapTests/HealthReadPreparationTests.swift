import XCTest
import HealthKit
@testable import DoseTap

@MainActor
final class HealthReadPreparationTests: XCTestCase {
    func testAcceptedEmptyProbeDoesNotClaimReadPermission() async {
        let result = await HealthKitService.prepareReadAccess(status: { .unnecessary }, probe: { true })
        XCTAssertEqual(result, .ready)
    }

    func testRequestNeededDoesNotProbe() async {
        var probed = false
        let result = await HealthKitService.prepareReadAccess(status: { .shouldRequest }, probe: { probed = true; return true })
        XCTAssertEqual(result, .unavailable); XCTAssertFalse(probed)
    }

    func testUnknownStatusIsUnavailable() async {
        let result = await HealthKitService.prepareReadAccess(status: { .unknown }, probe: { true })
        XCTAssertEqual(result, .unavailable)
    }

    func testProbeAndStatusTransientErrorsRemainDistinctFromDenial() async {
        let network = URLError(.timedOut)
        let status = await HealthKitService.prepareReadAccess(status: { throw network }, probe: { true })
        let probe = await HealthKitService.prepareReadAccess(status: { .unnecessary }, probe: { throw network })
        XCTAssertEqual(status, .transientFailure); XCTAssertEqual(probe, .transientFailure)
    }

    func testKnownDeniedAndUnavailableErrorsInvalidate() async {
        for code in [HKError.Code.errorAuthorizationDenied, .errorHealthDataUnavailable,
                     .errorHealthDataRestricted, .errorAuthorizationNotDetermined, .errorRequiredAuthorizationDenied] {
            let denied = NSError(domain: HKErrorDomain, code: code.rawValue)
            let result = await HealthKitService.prepareReadAccess(status: { .unnecessary }, probe: { throw denied })
            XCTAssertEqual(result, .unavailable)
        }
    }

    func testTransientPreparationPreservesPreviousStateButUnavailableClears() {
        let service = HealthKitService.shared, original = HealthKitService.shared.isAuthorized
        defer { service.isAuthorized = original }
        service.isAuthorized = true
        service.applyReadPreparation(.transientFailure)
        XCTAssertTrue(service.isAuthorized)
        service.applyReadPreparation(.unavailable)
        XCTAssertFalse(service.isAuthorized)
        service.applyReadPreparation(.transientFailure)
        XCTAssertFalse(service.isAuthorized)
    }
}
