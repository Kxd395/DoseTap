import XCTest
@testable import DoseCore

final class CaffeineAmountsTests: XCTestCase {
    func testIndependentUnitsAndMissingnessRoundTrip() throws {
        var amounts = CaffeineAmounts()
        XCTAssertNil(amounts.validationError)
        XCTAssertNil(amounts.lastCaffeineMg)
        amounts.lastVolumeUSFlOz = 12.5
        amounts.dailyVolumeUSFlOz = 20.25
        amounts.lastCaffeineMg = 0
        amounts.dailyCaffeineMg = 95.5
        amounts.source = .labelReported
        let decoded = try JSONDecoder().decode(CaffeineAmounts.self, from: JSONEncoder().encode(amounts))
        XCTAssertEqual(decoded, amounts)
        XCTAssertEqual(decoded.lastCaffeineMg, 0)
        XCTAssertEqual(decoded.lastVolumeUSFlOz, 12.5)
        XCTAssertNil(decoded.validationError)
    }

    func testInvalidAmountsAndUnsupportedVersionsFailClosed() {
        for invalid in [-1, Double.infinity, Double.nan] {
            var amounts = CaffeineAmounts()
            amounts.lastCaffeineMg = invalid
            XCTAssertNotNil(amounts.validationError)
        }
        var amounts = CaffeineAmounts()
        amounts.lastVolumeUSFlOz = 12
        amounts.dailyVolumeUSFlOz = 8
        XCTAssertNotNil(amounts.validationError)
        amounts.dailyVolumeUSFlOz = nil
        XCTAssertNil(amounts.validationError)
        amounts.version = 2
        XCTAssertNotNil(amounts.validationError)
    }
}
