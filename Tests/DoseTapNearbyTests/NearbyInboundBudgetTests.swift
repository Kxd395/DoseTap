import XCTest
import MultipeerConnectivity
@testable import DoseTapNearby

final class NearbyInboundBudgetTests: XCTestCase {
    private func session() -> MCSession {
        MCSession(peer: MCPeerID(displayName: "Synthetic"), securityIdentity: nil, encryptionPreference: .required)
    }
    func testFourPreauthenticationPacketsThenOneAbortAndSubsequentIgnore() {
        let channel = session(), budget = NearbyInboundBudget()
        budget.configure(channel)
        for _ in 0..<4 { XCTAssertEqual(budget.reserve(128, session: ObjectIdentifier(channel)), .accepted) }
        XCTAssertEqual(budget.reserve(1, session: ObjectIdentifier(channel)), .reject)
        XCTAssertEqual(budget.reserve(1, session: ObjectIdentifier(channel)), .ignore)
    }
    func testPreauthenticationSizeLimitAndReleasedCapacity() {
        let channel = session(), budget = NearbyInboundBudget(), id = ObjectIdentifier(channel)
        budget.configure(channel)
        XCTAssertEqual(budget.reserve(129, session: id), .reject)
        budget.configure(channel)
        for _ in 0..<4 { XCTAssertEqual(budget.reserve(128, session: id), .accepted) }
        budget.release(128, session: id)
        XCTAssertEqual(budget.reserve(128, session: id), .accepted)
    }
    func testPairedBudgetIsTwoMaximumPacketsAndCannotAcceptOversize() {
        let channel = session(), budget = NearbyInboundBudget(), id = ObjectIdentifier(channel)
        budget.configure(channel); budget.authenticate()
        for _ in 0..<2 { XCTAssertEqual(budget.reserve(NearbyReportingCodec.maximumWireBytes, session: id), .accepted) }
        XCTAssertEqual(budget.reserve(1, session: id), .reject)
        budget.configure(channel); budget.authenticate()
        XCTAssertEqual(budget.reserve(NearbyReportingCodec.maximumWireBytes + 1, session: id), .reject)
    }
    func testStaleReleaseCannotDecrementNewSessionBudget() {
        let old = session(), current = session(), budget = NearbyInboundBudget()
        budget.configure(old)
        XCTAssertEqual(budget.reserve(128, session: ObjectIdentifier(old)), .accepted)
        budget.configure(current)
        for _ in 0..<4 { XCTAssertEqual(budget.reserve(128, session: ObjectIdentifier(current)), .accepted) }
        budget.release(128, session: ObjectIdentifier(old))
        XCTAssertEqual(budget.reserve(1, session: ObjectIdentifier(current)), .reject)
        XCTAssertEqual(budget.reserve(1, session: ObjectIdentifier(old)), .ignore)
    }
    func testDisconnectAndRestartRevokeAuthenticatedBudget() {
        let channel = session(), budget = NearbyInboundBudget(), id = ObjectIdentifier(channel)
        budget.configure(channel); budget.authenticate()
        budget.configure(nil)
        XCTAssertEqual(budget.reserve(1, session: id), .ignore)
        budget.configure(channel)
        XCTAssertEqual(budget.reserve(129, session: id), .reject)
    }
}
