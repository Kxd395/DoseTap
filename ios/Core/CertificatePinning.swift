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
        self.pinnedHashes = Set(pins)
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
            let parsed = plistArray.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !parsed.isEmpty { return parsed }
        }

        #if DEBUG
        #if canImport(OSLog)
        Self.logWarning("No pins configured (DOSETAP_CERT_PINS); falling back to default TLS trust evaluation")
        #endif
        #endif
        return []
    }

    private static func parsePins(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
            
            let publicKeyHash = hashPublicKey(of: certificate)
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
    
    /// Generate SHA-256 hash of the certificate's public key (SPKI)
    private func hashPublicKey(of certificate: SecCertificate) -> String {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return ""
        }
        
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return ""
        }
        
        // Hash the public key data
        let hash = SHA256.hash(data: publicKeyData)
        return "sha256/" + Data(hash).base64EncodedString()
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
