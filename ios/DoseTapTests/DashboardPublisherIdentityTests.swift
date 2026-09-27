import XCTest
@testable import DoseTap

@MainActor
final class DashboardPublisherIdentityTests: XCTestCase {
    func testReservationSurvivesNewAllocatorAndNeverReusesSequence() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try DashboardPublisherIdentity(directory: folder).reserve()
        let second = try DashboardPublisherIdentity(directory: folder).reserve()
        XCTAssertNotNil(UUID(uuidString: first.sourceID))
        XCTAssertEqual(first.sourceID, second.sourceID)
        XCTAssertEqual(first.sequence, 1); XCTAssertEqual(second.sequence, 2)
        let file = folder.appendingPathComponent("publisher-identity.json")
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
    func testCorruptionAndExhaustionFailClosedWithoutReplacingState() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let allocator = try DashboardPublisherIdentity(directory: folder)
        let original = try allocator.reserve()
        let file = folder.appendingPathComponent("publisher-identity.json")
        let invalid = [Data("not JSON".utf8),
            try JSONEncoder().encode(DashboardPublisherIdentity.Reservation(schemaVersion: 2, sourceID: original.sourceID, sequence: 2)),
            try JSONEncoder().encode(DashboardPublisherIdentity.Reservation(schemaVersion: 1, sourceID: "bad", sequence: 2)),
            try JSONEncoder().encode(DashboardPublisherIdentity.Reservation(schemaVersion: 1, sourceID: original.sourceID, sequence: UInt64.max))]
        for bytes in invalid {
            try bytes.write(to: file)
            XCTAssertThrowsError(try allocator.reserve())
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }
}
