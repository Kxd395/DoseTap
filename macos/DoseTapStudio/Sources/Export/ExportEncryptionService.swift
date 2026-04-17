import Foundation
import CryptoKit
import Security

struct EncryptedExportEnvelope: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let algorithm: String
    let originalFileName: String
    let createdAtUTC: Date
    let saltBase64: String
    let nonceBase64: String
    let ciphertextBase64: String
    let payloadSHA256Hex: String
}

enum ExportEncryptionError: LocalizedError {
    case emptyPassphrase
    case randomGenerationFailed
    case invalidEnvelope

    var errorDescription: String? {
        switch self {
        case .emptyPassphrase:
            return "Passphrase cannot be empty."
        case .randomGenerationFailed:
            return "Unable to generate encryption randomness."
        case .invalidEnvelope:
            return "Encrypted export envelope is invalid."
        }
    }
}

struct ExportEncryptionService {
    func encrypt(data: Data, fileName: String, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else {
            throw ExportEncryptionError.emptyPassphrase
        }

        let salt = try randomData(count: 16)
        let key = deriveKey(passphrase: passphrase, salt: salt)
        let sealedBox = try AES.GCM.seal(data, using: key)

        let envelope = EncryptedExportEnvelope(
            schemaVersion: 1,
            algorithm: "AES.GCM+SHA256",
            originalFileName: fileName,
            createdAtUTC: Date(),
            saltBase64: salt.base64EncodedString(),
            nonceBase64: sealedBox.nonce.withUnsafeBytes { Data($0).base64EncodedString() },
            ciphertextBase64: sealedBox.combined?.base64EncodedString() ?? "",
            payloadSHA256Hex: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )

        return try JSONEncoder.exportEncoder.encode(envelope)
    }

    func decrypt(encryptedData: Data, passphrase: String) throws -> Data {
        guard !passphrase.isEmpty else {
            throw ExportEncryptionError.emptyPassphrase
        }

        let envelope = try JSONDecoder.exportDecoder.decode(EncryptedExportEnvelope.self, from: encryptedData)
        guard let salt = Data(base64Encoded: envelope.saltBase64),
              let combined = Data(base64Encoded: envelope.ciphertextBase64) else {
            throw ExportEncryptionError.invalidEnvelope
        }

        let key = deriveKey(passphrase: passphrase, salt: salt)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private func deriveKey(passphrase: String, salt: Data) -> SymmetricKey {
        var digest = SHA256.hash(data: Data(passphrase.utf8) + salt)
        for _ in 0..<9_999 {
            digest = SHA256.hash(data: Data(digest) + salt)
        }
        return SymmetricKey(data: Data(digest))
    }

    private func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw ExportEncryptionError.randomGenerationFailed
        }
        return Data(bytes)
    }
}

private extension JSONEncoder {
    static let exportEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let exportDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
