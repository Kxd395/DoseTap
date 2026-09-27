import Foundation
import CryptoKit

/// Versioned PSK-authenticated reporting envelope; no discovery, identity or storage.
/// The 256-bit key MUST arrive through a separate trusted channel. Device names
/// and six-digit codes are not keys. This implementation still needs protocol review.
public struct NearbyReportingCodec {
    public enum Role: UInt8 { case publisher = 1, reader = 2 }
    public enum State { case initial, handshaking, authenticated, failed }
    public enum Event: Equatable { case authenticated, requestSnapshot, snapshot(Data) }
    public enum Failure: Error { case invalidKey, invalidState, protocolViolation, tooLarge, unsupportedPlatform }
    public struct Result { public let outbound: [Data]; public let event: Event? }
    public static let maximumSnapshotBytes = 32 * 1024 * 1024
    public static let maximumWireBytes = maximumSnapshotBytes + 64
    private static let domain = Data("DoseTap-nearby-psk-v1".utf8)
    public let role: Role
    public private(set) var state: State = .initial
    private var secret: SymmetricKey?
    private var nonce: Data
    private var remoteNonce: Data?
    private var verified = false, pending = false
    private var tx: UInt64 = 0, rx: UInt64 = 0
    public init(role: Role, key: Data, nonce: Data = Self.randomBytes()) throws {
        guard #available(macOS 11.0, *) else { throw Failure.unsupportedPlatform }
        guard key.count == 32, nonce.count == 32 else { throw Failure.invalidKey }
        self.role = role; secret = SymmetricKey(data: key); self.nonce = nonce
    }
    public static func randomBytes() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }
    public static func code(for key: Data) -> String { key.map { String(format: "%02x", $0) }.joined() }
    public static func key(from code: String) throws -> Data {
        let bytes = Array(code.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard bytes.count == 64 else { throw Failure.invalidKey }
        func nibble(_ byte: UInt8) throws -> UInt8 {
            switch byte {
            case 48...57: return byte - 48
            case 65...70: return byte - 65 + 10
            case 97...102: return byte - 97 + 10
            default: throw Failure.invalidKey
            }
        }
        return try Data(stride(from: 0, to: 64, by: 2).map { try nibble(bytes[$0]) * 16 + nibble(bytes[$0 + 1]) })
    }
    public mutating func begin() throws -> Data {
        guard state == .initial else { throw Failure.invalidState }
        state = .handshaking; return Data([1, role.rawValue]) + nonce
    }
    public mutating func invalidate() {
        state = .failed; secret = nil; nonce = Data(); remoteNonce = nil; verified = false; pending = false
        tx = 0; rx = 0
    }
    public mutating func receive(_ bytes: Data) throws -> Result {
        do { return try process(bytes) } catch { invalidate(); throw error }
    }
    public mutating func requestSnapshot() throws -> Data {
        guard role == .reader, state == .authenticated, !pending else { throw Failure.invalidState }
        let packet = try seal(Data([0])); pending = true; return packet
    }
    public mutating func sendSnapshot(_ bytes: Data) throws -> Data {
        guard role == .publisher, state == .authenticated, pending else { throw Failure.invalidState }
        guard bytes.count <= Self.maximumSnapshotBytes else { throw Failure.tooLarge }
        let packet = try seal(Data([1]) + bytes); pending = false; return packet
    }
    private var otherRole: Role { role == .publisher ? .reader : .publisher }
    private func transcript(_ sender: Role, _ purpose: String) throws -> Data {
        guard let remoteNonce, remoteNonce.count == 32, nonce.count == 32 else { throw Failure.protocolViolation }
        return Self.domain + Data(purpose.utf8) + Data([sender.rawValue]) +
            (role == .publisher ? nonce + remoteNonce : remoteNonce + nonce)
    }
    private func proof(_ purpose: String) throws -> Data {
        guard let secret else { throw Failure.protocolViolation }
        return Data(HMAC<SHA256>.authenticationCode(for: try transcript(role, purpose), using: secret))
    }
    private func checkProof(_ bytes: Data, purpose: String) throws {
        guard let secret, HMAC<SHA256>.isValidAuthenticationCode(bytes,
            authenticating: try transcript(otherRole, purpose), using: secret) else { throw Failure.protocolViolation }
    }
    private func channelKey(_ sender: Role) throws -> SymmetricKey {
        guard #available(macOS 11.0, *) else { throw Failure.unsupportedPlatform }
        guard let secret else { throw Failure.protocolViolation }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: secret, salt: Self.domain,
            info: try transcript(sender, "payload-key"), outputByteCount: 32)
    }
    private mutating func seal(_ plaintext: Data) throws -> Data {
        guard tx < UInt64.max else { throw Failure.protocolViolation }
        let counter = withUnsafeBytes(of: (tx + 1).bigEndian) { Data($0) }
        let box = try ChaChaPoly.seal(plaintext, using: channelKey(role),
            authenticating: transcript(role, "payload") + counter)
        tx += 1; return Data([4]) + counter + box.combined
    }
    private mutating func process(_ data: Data) throws -> Result {
        guard data.count <= Self.maximumWireBytes else { throw Failure.tooLarge }
        guard let kind = data.first else { throw Failure.protocolViolation }
        let body = Data(data.dropFirst())
        switch kind {
        case 1:
            guard state == .handshaking, remoteNonce == nil, body.count == 33,
                  body.first == otherRole.rawValue else { throw Failure.protocolViolation }
            remoteNonce = Data(body.dropFirst())
            return Result(outbound: [Data([2]) + (try proof("proof"))], event: nil)
        case 2:
            guard state == .handshaking, !verified, body.count == 32 else { throw Failure.protocolViolation }
            try checkProof(body, purpose: "proof"); verified = true
            return Result(outbound: [Data([3]) + (try proof("ready"))], event: nil)
        case 3:
            guard state == .handshaking, verified, body.count == 32 else { throw Failure.protocolViolation }
            try checkProof(body, purpose: "ready"); state = .authenticated
            return Result(outbound: [], event: .authenticated)
        case 4:
            guard state == .authenticated, body.count >= 37, rx < UInt64.max else { throw Failure.protocolViolation }
            let counter = Data(body.prefix(8))
            guard counter.reduce(UInt64(0), { ($0 << 8) | UInt64($1) }) == rx + 1 else { throw Failure.protocolViolation }
            let box = try ChaChaPoly.SealedBox(combined: body.dropFirst(8))
            let plain = try ChaChaPoly.open(box, using: channelKey(otherRole), authenticating: transcript(otherRole, "payload") + counter)
            rx += 1
            if role == .publisher {
                guard plain == Data([0]), !pending else { throw Failure.protocolViolation }
                pending = true; return Result(outbound: [], event: .requestSnapshot)
            }
            guard pending, plain.first == 1, plain.count <= Self.maximumSnapshotBytes + 1 else { throw Failure.protocolViolation }
            pending = false; return Result(outbound: [], event: .snapshot(Data(plain.dropFirst())))
        default: throw Failure.protocolViolation
        }
    }
}
