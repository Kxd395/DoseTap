// ios/Core/DataRedactor.swift
// DoseCore - Platform-free PII redaction utilities

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - Redaction Models

/// Configuration for data redaction
public struct RedactionConfig: Sendable {
    public let hashDeviceIDs: Bool
    public let removeEmails: Bool
    public let removeNames: Bool
    public let hashPrefix: String
    
    public static let `default` = RedactionConfig(
        hashDeviceIDs: true,
        removeEmails: true,
        removeNames: true,
        hashPrefix: "HASH_"
    )
    
    public static let minimal = RedactionConfig(
        hashDeviceIDs: true,
        removeEmails: false,
        removeNames: false,
        hashPrefix: "H_"
    )
    
    public init(hashDeviceIDs: Bool, removeEmails: Bool, removeNames: Bool, hashPrefix: String) {
        self.hashDeviceIDs = hashDeviceIDs
        self.removeEmails = removeEmails
        self.removeNames = removeNames
        self.hashPrefix = hashPrefix
    }
}

/// Result of a redaction operation
public struct RedactionResult: Sendable {
    public let redactedText: String
    public let redactionsApplied: Int
    public let redactionTypes: Set<RedactionType>
    
    public init(redactedText: String, redactionsApplied: Int, redactionTypes: Set<RedactionType>) {
        self.redactedText = redactedText
        self.redactionsApplied = redactionsApplied
        self.redactionTypes = redactionTypes
    }
}

public enum RedactionType: String, Sendable, Hashable {
    case email
    case deviceID
    case name
    case uuid
    case ipAddress
}

// MARK: - Data Redactor

/// Platform-free PII redaction for support bundles and exports
/// Follows SSOT privacy requirements: "PII minimized, not guaranteed zero-PII"
public struct DataRedactor: Sendable {
    
    private let config: RedactionConfig
    
    public init(config: RedactionConfig = .default) {
        self.config = config
    }
    
    // MARK: - Main Redaction
    
    /// Redact PII from text following configured rules
    public func redact(_ text: String) -> RedactionResult {
        var result = text
        var count = 0
        var types: Set<RedactionType> = []
        
        // Redact emails
        if config.removeEmails {
            let (redacted, emailCount) = redactEmails(result)
            result = redacted
            count += emailCount
            if emailCount > 0 { types.insert(.email) }
        }
        
        // Redact device IDs (UUIDs)
        if config.hashDeviceIDs {
            let (redacted, uuidCount) = redactUUIDs(result)
            result = redacted
            count += uuidCount
            if uuidCount > 0 { types.insert(.uuid) }
        }
        
        // Redact IP addresses
        let (ipRedacted, ipCount) = redactIPAddresses(result)
        result = ipRedacted
        count += ipCount
        if ipCount > 0 { types.insert(.ipAddress) }
        
        return RedactionResult(redactedText: result, redactionsApplied: count, redactionTypes: types)
    }
    
    /// Redact a specific device ID by hashing it
    public func hashDeviceID(_ deviceID: String) -> String {
        guard config.hashDeviceIDs else { return deviceID }
        let hash = sha256Hash(deviceID)
        return "\(config.hashPrefix)\(hash.prefix(12))"
    }
    
    // MARK: - Specific Redactions
    
    /// Redact email addresses
    private func redactEmails(_ text: String) -> (String, Int) {
        // Email regex pattern
        let pattern = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        return redactPattern(text, pattern: pattern, replacement: "[EMAIL_REDACTED]")
    }
    
    /// Redact UUIDs (device IDs, etc.)
    private func redactUUIDs(_ text: String) -> (String, Int) {
        // UUID pattern: 8-4-4-4-12 hex digits
        let pattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        return redactPatternWithHash(text, pattern: pattern)
    }
    
    /// Redact IPv4 addresses
    private func redactIPAddresses(_ text: String) -> (String, Int) {
        let pattern = "\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b"
        return redactPattern(text, pattern: pattern, replacement: "[IP_REDACTED]")
    }
    
    // MARK: - Helpers
    
    /// Replace matches with fixed string
    private func redactPattern(_ text: String, pattern: String, replacement: String) -> (String, Int) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (text, 0)
        }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.numberOfMatches(in: text, options: [], range: range)
        let redacted = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
        
        return (redacted, matches)
    }
    
    /// Replace matches with hashed version
    private func redactPatternWithHash(_ text: String, pattern: String) -> (String, Int) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (text, 0)
        }
        
        var result = text
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        
        // Process in reverse to maintain indices
        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let original = String(result[swiftRange])
            let hashed = hashDeviceID(original)
            result.replaceSubrange(swiftRange, with: hashed)
        }
        
        return (result, matches.count)
    }
    
    /// SHA256 hash of input string (first 12 hex chars)
    private func sha256Hash(_ input: String) -> String {
        let data = Data(input.utf8)
        
        #if canImport(CryptoKit)
        if #available(iOS 13.0, macOS 10.15, watchOS 6.0, *) {
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }
        #endif
        
        // Fallback: simple hash for older platforms
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - Convenience Extensions

public extension DataRedactor {
    
    /// Check if text contains potential PII
    static func containsPotentialPII(_ text: String) -> Bool {
        let patterns = [
            "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",  // Email
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",  // UUID
            "\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b"  // IP
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        
        return false
    }
    
    /// Redact dictionary values, preserving structure
    static func redactDictionary(_ dict: [String: Any], config: RedactionConfig = .default) -> [String: Any] {
        let redactor = DataRedactor(config: config)
        var result: [String: Any] = [:]
        
        for (key, value) in dict {
            switch value {
            case let str as String:
                result[key] = redactor.redact(str).redactedText
            case let nested as [String: Any]:
                result[key] = redactDictionary(nested, config: config)
            case let array as [String]:
                result[key] = array.map { redactor.redact($0).redactedText }
            default:
                result[key] = value
            }
        }
        
        return result
    }
}
