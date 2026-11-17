import XCTest
@testable import DoseTapNearby

final class NearbyReportingCodecTests: XCTestCase {
    private let key = Data(repeating: 7, count: 32)
    private func pair() throws -> (NearbyReportingCodec, NearbyReportingCodec) {
        var publisher = try NearbyReportingCodec(role: .publisher, key: key, nonce: Data(repeating: 1, count: 32))
        var reader = try NearbyReportingCodec(role: .reader, key: key, nonce: Data(repeating: 2, count: 32))
        let pHello = try publisher.begin(), rHello = try reader.begin()
        let pProof = try publisher.receive(rHello).outbound[0], rProof = try reader.receive(pHello).outbound[0]
        let pReady = try publisher.receive(rProof).outbound[0], rReady = try reader.receive(pProof).outbound[0]
        XCTAssertEqual(publisher.state, .handshaking); XCTAssertEqual(reader.state, .handshaking)
        XCTAssertThrowsError(try reader.requestSnapshot())
        XCTAssertEqual(try publisher.receive(rReady).event, .authenticated)
        XCTAssertEqual(try reader.receive(pReady).event, .authenticated)
        return (publisher, reader)
    }
    func testMutualProofThenRequestedOpaqueSnapshotAndSecondRequest() throws {
        var (publisher, reader) = try pair()
        for _ in 0..<2 {
            XCTAssertEqual(try publisher.receive(reader.requestSnapshot()).event, .requestSnapshot)
            let bytes = Data([0, 255, 12, 34, 0])
            let packet = try publisher.sendSnapshot(bytes)
            XCTAssertNotEqual(packet, bytes)
            XCTAssertEqual(try reader.receive(packet).event, .snapshot(bytes))
        }
    }
    func testWrongKeyFailsAndFailureCannotBeReused() throws {
        var publisher = try NearbyReportingCodec(role: .publisher, key: key)
        var reader = try NearbyReportingCodec(role: .reader, key: Data(repeating: 8, count: 32))
        let pHello = try publisher.begin(), rHello = try reader.begin()
        _ = try publisher.receive(rHello)
        let proof = try reader.receive(pHello).outbound[0]
        XCTAssertThrowsError(try publisher.receive(proof)); XCTAssertEqual(publisher.state, .failed)
        XCTAssertThrowsError(try publisher.begin()); XCTAssertThrowsError(try publisher.sendSnapshot(Data()))
    }
    func testReplayAndReflectedPayloadFailClosed() throws {
        var (publisher, reader) = try pair()
        let request = try reader.requestSnapshot()
        _ = try publisher.receive(request)
        let packet = try publisher.sendSnapshot(Data([9]))
        _ = try reader.receive(packet)
        XCTAssertThrowsError(try reader.receive(packet)); XCTAssertEqual(reader.state, .failed)
        XCTAssertThrowsError(try publisher.receive(packet)); XCTAssertEqual(publisher.state, .failed)
    }
    func testCorruptionCannotDeliverSnapshot() throws {
        var (publisher, reader) = try pair()
        _ = try publisher.receive(reader.requestSnapshot())
        var packet = try publisher.sendSnapshot(Data([1, 2, 3]))
        packet[packet.count - 1] ^= 1
        XCTAssertThrowsError(try reader.receive(packet)); XCTAssertEqual(reader.state, .failed)
    }
    func testStateOrderingDuplicateHelloAndReflectedHelloAreRejected() throws {
        var publisher = try NearbyReportingCodec(role: .publisher, key: key)
        XCTAssertThrowsError(try publisher.sendSnapshot(Data()))
        let reflected = try publisher.begin()
        XCTAssertThrowsError(try publisher.receive(reflected))
        var reader = try NearbyReportingCodec(role: .reader, key: key)
        _ = try reader.begin(); _ = try reader.receive(reflected)
        XCTAssertThrowsError(try reader.receive(reflected))
        var outOfOrder = try NearbyReportingCodec(role: .reader, key: key)
        _ = try outOfOrder.begin()
        XCTAssertThrowsError(try outOfOrder.receive(Data([3]) + Data(repeating: 0, count: 32)))
    }
    func testOversizePacketsAndPayloadsAreRejected() throws {
        var (publisher, reader) = try pair()
        _ = try publisher.receive(reader.requestSnapshot())
        XCTAssertThrowsError(try publisher.sendSnapshot(Data(count: NearbyReportingCodec.maximumSnapshotBytes + 1)))
        XCTAssertThrowsError(try reader.receive(Data(count: NearbyReportingCodec.maximumWireBytes + 1)))
        XCTAssertEqual(reader.state, .failed)
    }
    func testCodeMustBeFullEntropyLengthASCIIHexAndNonceSized() throws {
        XCTAssertEqual(try NearbyReportingCodec.key(from: NearbyReportingCodec.code(for: key)), key)
        for bad in ["123456", String(repeating: "g", count: 64), String(repeating: "é", count: 32), String(repeating: "0", count: 63)] {
            XCTAssertThrowsError(try NearbyReportingCodec.key(from: bad))
        }
        XCTAssertThrowsError(try NearbyReportingCodec(role: .reader, key: key, nonce: Data(count: 31)))
    }
    func testOldSessionCiphertextCannotCrossFreshNonceBoundary() throws {
        var (publisher, reader) = try pair()
        let oldRequest = try reader.requestSnapshot()
        var fresh = try NearbyReportingCodec(role: .publisher, key: key, nonce: Data(repeating: 3, count: 32))
        var freshReader = try NearbyReportingCodec(role: .reader, key: key, nonce: Data(repeating: 4, count: 32))
        let p = try fresh.begin(), r = try freshReader.begin()
        let pp = try fresh.receive(r).outbound[0], rp = try freshReader.receive(p).outbound[0]
        let pr = try fresh.receive(rp).outbound[0], rr = try freshReader.receive(pp).outbound[0]
        _ = try fresh.receive(rr); _ = try freshReader.receive(pr)
        XCTAssertThrowsError(try fresh.receive(oldRequest))
        XCTAssertEqual(try publisher.receive(oldRequest).event, .requestSnapshot)
    }
}
