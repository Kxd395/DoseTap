import Foundation
import Security
import CryptoKit
#if canImport(OSLog)
import OSLog
#endif

/// Certificate pinning delegate for URLSession
/// 
/// This provides TLS certificate pinning to prevent MITM attacks.
/// Pins are SHA-256 hashes of the Subject Public Key Info (SPKI).
///
/// Usage:
/// ```swift
/// let pinning = CertificatePinning(pins: [
///     "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
/// ])
/// let session = URLSession(configuration: .default, delegate: pinning, delegateQueue: nil)
/// ```
@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
public final class CertificatePinning: NSObject, URLSessionDelegate, @unchecked Sendable {
    private static func logWarning(_ message: String) {
        #if canImport(OSLog)
        Logger(subsystem: "com.dosetap.core", category: "CertificatePinning")
            .warning("\(message, privacy: .public)")
        #endif
    }

    private static func logError(_ message: String) {
        #if canImport(OSLog)
        Logger(subsystem: "com.dosetap.core", category: "CertificatePinning")
            .error("\(message, privacy: .public)")
        #endif
    }
    
    // MARK: - Configuration
    
    /// SHA-256 pins of the Subject Public Key Info (SPKI)
    /// Generate with: openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256 -binary | base64
    private let pinnedHashes: Set<String>
    
    /// Domains to apply pinning to (empty = all domains)
    private let pinnedDomains: Set<String>
    
    /// Whether to allow system trust evaluation as fallback (development only)
    private let allowFallback: Bool
    
    // MARK: - Initialization
    
    /// Initialize with SPKI SHA-256 pins
    /// - Parameters:
    ///   - pins: Array of base64-encoded SHA-256 hashes of the SPKI
    ///   - domains: Domains to apply pinning to (empty = all)
    ///   - allowFallback: If true, allows connection if pinning fails (DEBUG only)
    public init(
        pins: [String],
        domains: [String] = [],
        allowFallback: Bool = false
    ) {
        self.pinnedHashes = Set(Self.normalizedPins(pins))
        self.pinnedDomains = Set(domains.map { $0.lowercased() })
        #if DEBUG
        self.allowFallback = allowFallback
        #else
        self.allowFallback = false // Never allow fallback in production
        #endif
        super.init()
    }
    
    // MARK: - Default Pins
    
    /// Create pinning configuration for DoseTap API
    public static func forDoseTapAPI() -> CertificatePinning {
        let pins = configuredPins()
        return CertificatePinning(
            pins: pins,
            domains: ["api.dosetap.com", "auth.dosetap.com"],
            allowFallback: false
        )
    }

    /// Returns true when at least one pin is configured via env or Info.plist.
    public static var hasConfiguredPins: Bool {
        !configuredPins().isEmpty
    }

    private static func configuredPins() -> [String] {
        if let envValue = ProcessInfo.processInfo.environment["DOSETAP_CERT_PINS"] {
            let parsed = parsePins(envValue)
            if !parsed.isEmpty { return parsed }
        }

        if let plistValue = Bundle.main.object(forInfoDictionaryKey: "DOSETAP_CERT_PINS") as? String {
            let parsed = parsePins(plistValue)
            if !parsed.isEmpty { return parsed }
        }

        if let plistArray = Bundle.main.object(forInfoDictionaryKey: "DOSETAP_CERT_PINS") as? [String] {
            let parsed = normalizedPins(plistArray)
            if !parsed.isEmpty { return parsed }
        }

        #if DEBUG
        #if canImport(OSLog)
        Self.logWarning("No pins configured (DOSETAP_CERT_PINS); falling back to default TLS trust evaluation")
        #endif
        #endif
        return []
    }

    static func parsePins(_ raw: String) -> [String] {
        normalizedPins(raw.split(separator: ",").map(String.init))
    }

    static func normalizedPins(_ rawPins: [String]) -> [String] {
        var seen: Set<String> = []
        return rawPins.compactMap { rawPin in
            let pin = rawPin.trimmingCharacters(in: .whitespacesAndNewlines)
            guard pin.hasPrefix("sha256/") else { return nil }
            let encodedDigest = String(pin.dropFirst("sha256/".count))
            guard encodedDigest.count == 44,
                  let digest = Data(base64Encoded: encodedDigest),
                  digest.count == SHA256.Digest.byteCount,
                  digest.base64EncodedString() == encodedDigest,
                  seen.insert(pin).inserted else {
                return nil
            }
            return pin
        }
    }
    
    // MARK: - URLSessionDelegate
    
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let host = challenge.protectionSpace.host.lowercased()
        
        // Skip pinning for domains not in our list (if list is not empty)
        if !pinnedDomains.isEmpty && !pinnedDomains.contains(host) {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if pinnedHashes.isEmpty {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        // Evaluate server trust
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)
        
        guard isValid else {
            #if DEBUG
            #if canImport(OSLog)
            Self.logWarning("Trust evaluation failed for \(host): \(error?.localizedDescription ?? "unknown")")
            #endif
            #endif
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // Check certificate pins
        let certificateCount = SecTrustGetCertificateCount(serverTrust)
        var pinMatched = false
        
        for i in 0..<certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, i) else { continue }
            
            let publicKeyHash = Self.spkiPin(of: certificate)
            if pinnedHashes.contains(publicKeyHash) {
                pinMatched = true
                break
            }
        }
        
        if pinMatched {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else if allowFallback {
            #if DEBUG
            #if canImport(OSLog)
            Self.logWarning("Pin mismatch for \(host), allowing fallback (DEBUG only)")
            #endif
            #endif
            completionHandler(.performDefaultHandling, nil)
        } else {
            #if DEBUG
            #if canImport(OSLog)
            Self.logError("Pin mismatch for \(host), rejecting connection")
            #endif
            #endif
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    
    // MARK: - Helpers
    
    /// Generate the SHA-256 pin of the certificate's DER SubjectPublicKeyInfo.
    /// `SecKeyCopyExternalRepresentation` returns only the algorithm-specific
    /// key bytes, so the matching SPKI AlgorithmIdentifier must be restored
    /// before hashing to match the OpenSSL production-pin runbook.
    private static func spkiPin(of certificate: SecCertificate) -> String {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return ""
        }
        
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?,
              let subjectPublicKeyInfo = subjectPublicKeyInfo(
                for: publicKey,
                externalRepresentation: publicKeyData
              ) else {
            return ""
        }

        let hash = SHA256.hash(data: subjectPublicKeyInfo)
        return "sha256/" + Data(hash).base64EncodedString()
    }

    static func spkiPin(forCertificateData certificateData: Data) -> String? {
        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            return nil
        }
        let pin = spkiPin(of: certificate)
        return pin.isEmpty ? nil : pin
    }

    static func matchesCertificateChain(
        _ certificateData: [Data],
        pins: [String]
    ) -> Bool {
        let normalized = Set(normalizedPins(pins))
        guard !normalized.isEmpty else { return false }
        return certificateData.contains { data in
            spkiPin(forCertificateData: data).map(normalized.contains) == true
        }
    }

    private static func subjectPublicKeyInfo(
        for key: SecKey,
        externalRepresentation: Data
    ) -> Data? {
        guard let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              let keyType = attributes[kSecAttrKeyType] as? String else {
            return nil
        }

        let algorithmIdentifier: Data
        if keyType == (kSecAttrKeyTypeRSA as String) {
            // rsaEncryption (1.2.840.113549.1.1.1) with the required NULL.
            algorithmIdentifier = Data([
                0x30, 0x0D,
                0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01,
                0x05, 0x00,
            ])
        } else if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            guard let keySize = attributes[kSecAttrKeySizeInBits] as? Int else { return nil }
            let curveOID: Data
            switch keySize {
            case 256:
                // prime256v1 / secp256r1 (1.2.840.10045.3.1.7)
                curveOID = Data([0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07])
            case 384:
                // secp384r1 (1.3.132.0.34)
                curveOID = Data([0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x22])
            case 521:
                // secp521r1 (1.3.132.0.35)
                curveOID = Data([0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x23])
            default:
                return nil
            }
            let ecPublicKeyOID = Data([0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01])
            algorithmIdentifier = derSequence(ecPublicKeyOID + curveOID)
        } else {
            return nil
        }

        var bitStringBody = Data([0x00])
        bitStringBody.append(externalRepresentation)
        var bitString = Data([0x03])
        bitString.append(derLength(bitStringBody.count))
        bitString.append(bitStringBody)
        return derSequence(algorithmIdentifier + bitString)
    }

    private static func derSequence(_ body: Data) -> Data {
        var sequence = Data([0x30])
        sequence.append(derLength(body.count))
        sequence.append(body)
        return sequence
    }

    private static func derLength(_ length: Int) -> Data {
        precondition(length >= 0)
        if length < 0x80 {
            return Data([UInt8(length)])
        }

        var value = length
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}

// MARK: - Pinned URLSession Transport

/// Transport that uses certificate pinning
@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
public struct PinnedURLSessionTransport {
    private let session: URLSession
    private let pinning: CertificatePinning
    
    /// Initialize with certificate pinning configuration
    public init(pinning: CertificatePinning) {
        self.pinning = pinning
        
        let config = URLSessionConfiguration.default
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.urlCache = nil
        
        self.session = URLSession(
            configuration: config,
            delegate: pinning,
            delegateQueue: nil
        )
    }
    
    /// Initialize with default DoseTap API pinning
    public init() {
        self.init(pinning: CertificatePinning.forDoseTapAPI())
    }
    
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

// MARK: - APITransport Conformance

@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
extension PinnedURLSessionTransport: APITransport {}
