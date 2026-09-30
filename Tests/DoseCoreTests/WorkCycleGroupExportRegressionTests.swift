import XCTest
@testable import DoseCore

final class WorkCycleGroupExportRegressionTests: XCTestCase {
    func testExportKeepsDisplayedCompatibleGroupDenominatorsSeparate() throws {
        func row(_ id: String, _ context: String, _ block: String) -> WorkCycleObservation {
            .init(sleepID: id, sleepDate: "2026-09-22", phase: .after,
                position: "First post-block main sleep", blockID: block, value: 60,
                stratumID: context, stratumLabel: context)
        }
        let csv = WorkCycleSummary.csv([row("a", "one", "block1"), row("b", "one", "block2"), row("c", "two", "block3")],
            metric: "Main sleep", basis: .confirmed, range: "6 months", revision: UUID(), asOf: Date(timeIntervalSince1970: 1_790_000_000))
        let table = try ReportCSV.rows(csv)
        func values(_ name: String) throws -> [String] {
            guard let index = table[0].firstIndex(of: name) else { XCTFail("Missing selected-group export field: " + name); return [] }
            return table.dropFirst().map { $0[index] }
        }
        XCTAssertEqual(try values("group_eligible_observations"), ["2", "2", "1"])
        XCTAssertEqual(try values("group_distinct_known_blocks"), ["2", "2", "1"])
        XCTAssertEqual(try values("group_recorded_dates"), ["1", "1", "1"])
        XCTAssertEqual(try values("group_median"), ["60.0", "60.0", "60.0"])
    }
}
