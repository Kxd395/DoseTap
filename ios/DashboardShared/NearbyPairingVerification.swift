import Foundation
import CryptoKit

/// One-attempt numeric comparison. The six digits are a human verification value,
/// never a password. Both devices commit before revealing ephemeral keys/nonces.
/// This custom protocol requires independent security review before release.
struct NearbyPairingVerification {
    typealias Role = NearbyReportingCodec.Role
    enum Failure: Error { case invalidState, invalidPacket, mismatch }
    struct Result { let outbound: [Data]; let key: Data? }
    private static let domain = Data("DoseTap-nearby-comparison-v1".utf8)
    let role: Role
    private var privateKey: Curve25519.KeyAgreement.PrivateKey?
    private let opening: Data
    private var commitment: Data?
    private var remoteOpening: Data?
    private var shared: SharedSecret?
    private var started = false, localConfirmed = false, remoteConfirmed = false, failed = false
    private(set) var code: String?
    init(role: Role) {
        self.role = role
        let key = Curve25519.KeyAgreement.PrivateKey()
        privateKey = key
        opening = key.publicKey.rawRepresentation + NearbyReportingCodec.randomBytes()
    }
    private var other: Role { role == .publisher ? .reader : .publisher }
    private func digest(_ opening: Data, role: Role) -> Data {
        Data(SHA256.hash(data: Self.domain + Data([role.rawValue]) + opening))
    }
    mutating func begin() throws -> Data {
        guard !started, !failed else { throw Failure.invalidState }
        started = true
        return Data([10, role.rawValue]) + digest(opening, role: role)
    }
    mutating func invalidate() {
        failed = true; privateKey = nil; shared = nil; commitment = nil; remoteOpening = nil; code = nil
    }
    mutating func receive(_ data: Data) throws -> Result {
        do { return try process(data) } catch { invalidate(); throw error }
    }
    private mutating func process(_ data: Data) throws -> Result {
        guard started, !failed, data.count <= 66, data.count >= 2,
              data[1] == other.rawValue else { throw Failure.invalidPacket }
        let body = Data(data.dropFirst(2))
        switch data[0] {
        case 10:
            guard commitment == nil, body.count == 32 else { throw Failure.invalidState }
            commitment = body
            return Result(outbound: [Data([11, role.rawValue]) + opening], key: nil)
        case 11:
            guard let commitment, remoteOpening == nil, body.count == 64,
                  digest(body, role: other) == commitment, let privateKey else { throw Failure.mismatch }
            let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: body.prefix(32))
            shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
            self.privateKey = nil; remoteOpening = body
            let hash = SHA256.hash(data: try transcript("display"))
            let value = hash.reduce(UInt64(0)) { ($0 * 256 + UInt64($1)) % 1_000_000 }
            code = String(format: "%06llu", value)
            return Result(outbound: [], key: nil)
        case 12:
            guard code != nil, !remoteConfirmed, body.count == 32,
                  HMAC<SHA256>.isValidAuthenticationCode(body,
                    authenticating: try transcript("confirm") + Data([other.rawValue]),
                    using: try key("confirmation-key")) else { throw Failure.mismatch }
            remoteConfirmed = true
            return Result(outbound: [], key: try readyKey())
        default: throw Failure.invalidPacket
        }
    }
    mutating func confirm() throws -> Result {
        guard code != nil, !failed, !localConfirmed else { throw Failure.invalidState }
        let proof = Data(HMAC<SHA256>.authenticationCode(
            for: try transcript("confirm") + Data([role.rawValue]), using: try key("confirmation-key")))
        localConfirmed = true
        return Result(outbound: [Data([12, role.rawValue]) + proof], key: try readyKey())
    }
    private func transcript(_ purpose: String) throws -> Data {
        guard let remoteOpening else { throw Failure.invalidState }
        return Self.domain + Data(purpose.utf8) +
            (role == .publisher ? opening + remoteOpening : remoteOpening + opening)
    }
    private func key(_ purpose: String) throws -> SymmetricKey {
        guard let shared else { throw Failure.invalidState }
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Self.domain,
            sharedInfo: try transcript(purpose), outputByteCount: 32)
    }
    private func readyKey() throws -> Data? {
        guard localConfirmed, remoteConfirmed else { return nil }
        return try key("reporting-key").withUnsafeBytes { Data($0) }
    }
}
