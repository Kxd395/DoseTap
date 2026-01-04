// InputValidator.swift
// DoseTap
//
// Centralized input validation and sanitization utilities
// Implements defense-in-depth for user inputs and deep links

import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Input validation and sanitization utilities
/// Use these for all external inputs (deep links, user input, API responses)
public struct InputValidator {
    
    #if canImport(OSLog)
    private static let logger = Logger(subsystem: "com.dosetap.app", category: "InputValidator")
    #endif
    
    // MARK: - Event Names
    
    /// Valid sleep event types per SSOT
    public static let validEventTypes: Set<String> = [
        // Physical
        "bathroom", "water", "snack",
        // Sleep Cycle
        "lightsOut", "lights_out", "wakeTemp", "wake_temp", "inBed", "in_bed", "wake_final",
        // Mental
        "anxiety", "dream", "heartRacing", "heart_racing",
        // Environment
        "noise", "temperature", "pain",
        // Dose Events (internal)
        "dose1", "dose2", "dose2_skipped", "snooze", "extra_dose"
    ]
    
    /// Validate and sanitize event name
    /// - Returns: Sanitized event name or nil if invalid
    public static func validateEventName(_ input: String?) -> String? {
        guard let input = input, !input.isEmpty else { return nil }
        
        // Normalize: lowercase, trim whitespace
        let normalized = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check against whitelist
        guard validEventTypes.contains(normalized) else {
            logInvalidInput("Event name", input)
            return nil
        }
        
        return normalized
    }
    
    // MARK: - String Sanitization
    
    /// Maximum allowed length for user notes
    public static let maxNotesLength = 500
    
    /// Maximum allowed length for general text fields
    public static let maxTextLength = 1000
    
    /// Sanitize user-provided text (notes, comments, etc.)
    /// - Parameters:
    ///   - input: Raw user input
    ///   - maxLength: Maximum allowed length
    /// - Returns: Sanitized string or nil if input is too long/empty
    public static func sanitizeText(_ input: String?, maxLength: Int = maxNotesLength) -> String? {
        guard let input = input else { return nil }
        
        // Trim whitespace
        var sanitized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check length
        if sanitized.isEmpty { return nil }
        
        if sanitized.count > maxLength {
            logInvalidInput("Text length exceeded", "[\(sanitized.count) chars]")
            sanitized = String(sanitized.prefix(maxLength))
        }
        
        // Remove control characters (keep newlines)
        sanitized = sanitized.components(separatedBy: .controlCharacters.subtracting(.newlines)).joined()
        
        // Remove HTML/script tags (basic XSS prevention)
        sanitized = stripHTMLTags(sanitized)
        
        return sanitized.isEmpty ? nil : sanitized
    }
    
    /// Strip HTML tags from string
    private static func stripHTMLTags(_ input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
            return input
        }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: "")
    }
    
    // MARK: - Color Hex Validation
    
    /// Valid hex color pattern (3, 6, or 8 chars with optional #)
    private static let hexColorPattern = "^#?([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"
    
    /// Validate and normalize color hex string
    /// - Returns: Normalized hex color (with #) or nil if invalid
    public static func validateColorHex(_ input: String?) -> String? {
        guard let input = input else { return nil }
        
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let regex = try? NSRegularExpression(pattern: hexColorPattern, options: []) else {
            return nil
        }
        
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard regex.firstMatch(in: trimmed, options: [], range: range) != nil else {
            logInvalidInput("Color hex", trimmed)
            return nil
        }
        
        // Normalize: ensure # prefix
        return trimmed.hasPrefix("#") ? trimmed.uppercased() : "#\(trimmed.uppercased())"
    }
    
    // MARK: - Numeric Validation
    
    /// Validate integer within range
    public static func validateInt(_ input: Int, min: Int, max: Int, defaultValue: Int) -> Int {
        if input < min || input > max {
            logInvalidInput("Integer out of range", "\(input) not in [\(min), \(max)]")
            return defaultValue.clamped(to: min...max)
        }
        return input
    }
    
    /// Validate double within range
    public static func validateDouble(_ input: Double, min: Double, max: Double, defaultValue: Double) -> Double {
        if input < min || input > max {
            logInvalidInput("Double out of range", "\(input) not in [\(min), \(max)]")
            return defaultValue.clamped(to: min...max)
        }
        return input
    }
    
    // MARK: - URL Validation
    
    /// Validate URL for safe schemes
    private static let safeSchemes: Set<String> = ["dosetap", "https", "http"]
    
    /// Validation result structure
    public struct ValidationResult {
        public let isValid: Bool
        public let errors: [String]
        
        public static func success() -> ValidationResult {
            ValidationResult(isValid: true, errors: [])
        }
        
        public static func failure(_ errors: [String]) -> ValidationResult {
            ValidationResult(isValid: false, errors: errors)
        }
    }
    
    /// Validate deep link URL (returns ValidationResult)
    /// - Returns: ValidationResult with isValid and errors array
    public static func validateDeepLink(_ url: URL?) -> ValidationResult {
        var errors: [String] = []
        
        guard let url = url else {
            return .failure(["URL is nil"])
        }
        
        guard let scheme = url.scheme?.lowercased() else {
            return .failure(["URL has no scheme"])
        }
        
        guard safeSchemes.contains(scheme) else {
            logInvalidInput("Deep link URL", url.absoluteString)
            return .failure(["Invalid scheme: \(scheme)"])
        }
        
        // Check for suspicious characters in URL
        let suspiciousPatterns = ["javascript:", "data:", "<script", "onclick"]
        let urlString = url.absoluteString.lowercased()
        for pattern in suspiciousPatterns {
            if urlString.contains(pattern) {
                errors.append("Suspicious pattern detected: \(pattern)")
            }
        }
        
        if !errors.isEmpty {
            return .failure(errors)
        }
        
        return .success()
    }
    
    /// Legacy boolean validation (for backward compatibility)
    public static func isValidDeepLink(_ url: URL?) -> Bool {
        return validateDeepLink(url).isValid
    }
    
    /// Sanitize string for logging (remove sensitive data patterns)
    public static func sanitizeForLogging(_ input: String) -> String {
        var sanitized = input
        
        // Remove potential tokens/secrets (long hex strings)
        if let tokenRegex = try? NSRegularExpression(pattern: "[a-fA-F0-9]{32,}", options: []) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = tokenRegex.stringByReplacingMatches(in: sanitized, options: [], range: range, withTemplate: "[REDACTED]")
        }
        
        // Remove email patterns
        if let emailRegex = try? NSRegularExpression(pattern: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}", options: []) {
            let range = NSRange(sanitized.startIndex..., in: sanitized)
            sanitized = emailRegex.stringByReplacingMatches(in: sanitized, options: [], range: range, withTemplate: "[EMAIL]")
        }
        
        // Truncate if too long
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200)) + "..."
        }
        
        return sanitized
    }
    
    /// Validate event type against whitelist (returns ValidationResult)
    public static func validateEventType(_ input: String?) -> ValidationResult {
        guard let input = input, !input.isEmpty else {
            return .failure(["Event type is empty"])
        }
        
        let normalized = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard validEventTypes.contains(normalized) else {
            logInvalidInput("Event type", input)
            return .failure(["Unknown event type: \(input)"])
        }
        
        return .success()
    }
    
    /// Validate and return sanitized event name (returns String?)
    public static func validateAndSanitizeEventType(_ input: String?) -> String? {
        return validateEventName(input)
    }
    
    /// Sanitize general input (alias for sanitizeText) - returns non-optional with default
    public static func sanitizeInput(_ input: String?, maxLength: Int = maxTextLength) -> String {
        return sanitizeText(input, maxLength: maxLength) ?? ""
    }
    
    /// Sanitize input returning optional
    public static func sanitizeInputOptional(_ input: String?, maxLength: Int = maxTextLength) -> String? {
        return sanitizeText(input, maxLength: maxLength)
    }
    
    /// Extract and validate query parameters
    public static func extractQueryParam(_ url: URL, name: String, maxLength: Int = maxTextLength) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == name })?.value else {
            return nil
        }
        return sanitizeText(value, maxLength: maxLength)
    }
    
    // MARK: - UUID Validation
    
    /// Validate UUID string format
    public static func validateUUID(_ input: String?) -> UUID? {
        guard let input = input else { return nil }
        return UUID(uuidString: input)
    }
    
    // MARK: - Date Validation
    
    /// Validate ISO8601 date string
    public static func validateISO8601Date(_ input: String?) -> Date? {
        guard let input = input else { return nil }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: input) {
            return date
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: input)
    }
    
    // MARK: - Session Key Validation
    
    /// Valid session key pattern: YYYY-MM-DD
    private static let sessionKeyPattern = "^\\d{4}-\\d{2}-\\d{2}$"
    
    /// Validate session key format
    public static func validateSessionKey(_ input: String?) -> String? {
        guard let input = input else { return nil }
        
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let regex = try? NSRegularExpression(pattern: sessionKeyPattern, options: []) else {
            return nil
        }
        
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard regex.firstMatch(in: trimmed, options: [], range: range) != nil else {
            logInvalidInput("Session key", trimmed)
            return nil
        }
        
        return trimmed
    }
    
    // MARK: - Private Helpers
    
    private static func logInvalidInput(_ type: String, _ value: String) {
        #if canImport(OSLog)
        logger.warning("Invalid input [\(type, privacy: .public)]: \(value, privacy: .private)")
        #endif
    }
}

// MARK: - Comparable Clamping

extension Comparable {
    /// Clamp value to a closed range
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
