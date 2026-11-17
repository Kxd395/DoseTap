import XCTest
@testable import DoseTapNearby

final class NearbyPairingVerificationTests: XCTestCase {
    private func compared() throws -> (NearbyPairingVerification, NearbyPairingVerification) {
        var phone = NearbyPairingVerification(role: .publisher)
        var pad = NearbyPairingVerification(role: .reader)
        let a = try phone.begin(), b = try pad.begin()
        let ar = try phone.receive(b), br = try pad.receive(a)
        XCTAssertNil(phone.code); XCTAssertNil(pad.code)
        XCTAssertNil(try phone.receive(br.outbound[0]).key)
        XCTAssertNil(try pad.receive(ar.outbound[0]).key)
        XCTAssertEqual(phone.code, pad.code)
        XCTAssertEqual(phone.code?.count, 6)
        XCTAssertTrue(phone.code!.allSatisfy(\.isNumber))
        return (phone, pad)
    }
    func testBothConfirmationsRequiredAndDerivedKeysDriveEncryptedReport() throws {
        var (phone, pad) = try compared()
        let a = try phone.confirm(); XCTAssertNil(a.key)
        XCTAssertNil(try pad.receive(a.outbound[0]).key)
        let b = try pad.confirm()
        let key = try XCTUnwrap(b.key)
        XCTAssertEqual(try phone.receive(b.outbound[0]).key, key)
        var publisher = try NearbyReportingCodec(role: .publisher, key: key)
        var reader = try NearbyReportingCodec(role: .reader, key: key)
        let ph = try publisher.begin(), rh = try reader.begin()
        let pp = try publisher.receive(rh), rp = try reader.receive(ph)
        let pr = try publisher.receive(rp.outbound[0]), rr = try reader.receive(pp.outbound[0])
        _ = try publisher.receive(rr.outbound[0]); _ = try reader.receive(pr.outbound[0])
        XCTAssertEqual(try publisher.receive(reader.requestSnapshot()).event, .requestSnapshot)
        XCTAssertEqual(try reader.receive(publisher.sendSnapshot(Data("synthetic".utf8))).event,
                       .snapshot(Data("synthetic".utf8)))
    }
    func testSimultaneousConfirmations() throws {
        var (phone, pad) = try compared()
        let a = try phone.confirm(), b = try pad.confirm()
        XCTAssertNil(a.key); XCTAssertNil(b.key)
        XCTAssertEqual(try phone.receive(b.outbound[0]).key, try pad.receive(a.outbound[0]).key)
    }
    func testEarlyConfirmationAndEarlyRevealRejected() throws {
        var phone = NearbyPairingVerification(role: .publisher)
        _ = try phone.begin()
        XCTAssertThrowsError(try phone.confirm())
        XCTAssertThrowsError(try phone.receive(Data([11, 2]) + Data(repeating: 0, count: 64)))
        XCTAssertThrowsError(try phone.begin())
    }
    func testChangedOpeningFailsClosed() throws {
        var phone = NearbyPairingVerification(role: .publisher), pad = NearbyPairingVerification(role: .reader)
        let a = try phone.begin(), b = try pad.begin()
        _ = try phone.receive(b)
        var reveal = try pad.receive(a).outbound[0]; reveal[65] ^= 1
        XCTAssertThrowsError(try phone.receive(reveal)); XCTAssertNil(phone.code)
        XCTAssertThrowsError(try phone.confirm())
    }
    func testDuplicateCommitmentAndRoleReflectionRejected() throws {
        var phone = NearbyPairingVerification(role: .publisher), pad = NearbyPairingVerification(role: .reader)
        let a = try phone.begin(), b = try pad.begin()
        _ = try phone.receive(b)
        XCTAssertThrowsError(try phone.receive(b))
        XCTAssertThrowsError(try pad.receive(b))
        XCTAssertThrowsError(try phone.receive(a))
    }
    func testTamperedConfirmationAndOldSessionProofRejected() throws {
        var (phone, pad) = try compared()
        var proof = try phone.confirm().outbound[0]; proof[2] ^= 1
        XCTAssertThrowsError(try pad.receive(proof))
        var (_, otherPad) = try compared()
        let old = try otherPad.confirm().outbound[0]
        XCTAssertThrowsError(try phone.receive(old)); XCTAssertNil(phone.code)
        otherPad.invalidate(); XCTAssertThrowsError(try otherPad.confirm())
    }
    func testDuplicateConfirmationRejected() throws {
        var (phone, pad) = try compared()
        let proof = try phone.confirm().outbound[0]
        _ = try pad.receive(proof)
        XCTAssertThrowsError(try pad.receive(proof)); XCTAssertNil(pad.code)
    }
}
