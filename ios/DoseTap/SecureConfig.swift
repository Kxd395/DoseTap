// SecureConfig.swift
// DoseTap
//
// Industry-standard secure configuration loader
// Priorities: 1) Environment Variables, 2) Keychain, 3) Fallback to Secrets.swift
//
// This ensures CI/CD can inject secrets via environment without file changes

import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Secure configuration loader with environment variable support
/// Follows 12-factor app methodology for secrets management
public final class SecureConfig {
    
    public static let shared = SecureConfig()
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "com.dosetap.app", category: "SecureConfig")
    #endif
    
    // MARK: - Environment Variable Keys
    
    private enum EnvKey: String {
        case whoopClientID = "DOSETAP_WHOOP_CLIENT_ID"
        case whoopClientSecret = "DOSETAP_WHOOP_CLIENT_SECRET"
        case whoopRedirectURI = "DOSETAP_WHOOP_REDIRECT_URI"
        case apiBaseURL = "DOSETAP_API_BASE_URL"
        case apiKey = "DOSETAP_API_KEY"
        case analyticsWriteKey = "DOSETAP_ANALYTICS_WRITE_KEY"
        case environment = "DOSETAP_ENVIRONMENT"
    }
    
    // MARK: - Keychain Keys
    
    public enum KeychainKey: String {
        case whoopClientSecret = "whoop_client_secret_secure"
    }
    
    // MARK: - Environment
    
    public enum Environment: String {
        case development
        case staging
        case production
        
        var isDebug: Bool { self != .production }
    }
    
    public var environment: Environment {
        guard let envStr = getEnv(.environment) else {
            #if DEBUG
            return .development
            #else
            return .production
            #endif
        }
        return Environment(rawValue: envStr) ?? .production
    }
    
    // MARK: - WHOOP Configuration
    
    public var whoopClientID: String {
        getEnv(.whoopClientID) ?? Secrets.whoopClientID
    }
    
    /// Client secret - prioritizes Keychain > Environment > Secrets.swift
    /// ⚠️ In production, this should ONLY come from Keychain or environment
    public var whoopClientSecret: String {
        // Priority 1: Keychain (most secure)
        if let keychainSecret = KeychainHelper.shared.read(forKey: KeychainKey.whoopClientSecret.rawValue) {
            return keychainSecret
        }
        
        // Priority 2: Environment variable (CI/CD)
        if let envSecret = getEnv(.whoopClientSecret) {
            return envSecret
        }
        
        // Priority 3: Fallback to Secrets.swift (local development only)
        #if DEBUG
        return Secrets.whoopClientSecret
        #else
        // In release builds, log warning if falling back to hardcoded
        logSecurityWarning("WHOOP client secret not found in Keychain or environment")
        return Secrets.whoopClientSecret
        #endif
    }
    
    public var whoopRedirectURI: String {
        getEnv(.whoopRedirectURI) ?? Secrets.whoopRedirectURI
    }
    
    // MARK: - API Configuration
    
    public var apiBaseURL: String {
        getEnv(.apiBaseURL) ?? Secrets.apiBaseURL
    }
    
    public var apiKey: String? {
        getEnv(.apiKey) ?? (Secrets.apiKey.isEmpty ? nil : Secrets.apiKey)
    }
    
    // MARK: - Analytics
    
    public var analyticsWriteKey: String? {
        getEnv(.analyticsWriteKey) ?? (Secrets.analyticsWriteKey.isEmpty ? nil : Secrets.analyticsWriteKey)
    }
    
    // MARK: - Validation
    
    /// Check if secrets are properly configured for the current environment
    public var isConfigured: Bool {
        !whoopClientID.contains("YOUR_") &&
        !whoopClientSecret.contains("YOUR_")
    }
    
    /// Validate configuration at app launch
    public func validateOnLaunch() {
        if !isConfigured {
            logSecurityWarning("Secrets not configured - app functionality will be limited")
        }
        
        // Warn if using hardcoded secrets in production
        if environment == .production {
            if getEnv(.whoopClientSecret) == nil && KeychainHelper.shared.read(forKey: KeychainKey.whoopClientSecret.rawValue) == nil {
                logSecurityWarning("Production build using hardcoded WHOOP secret - this is a security risk")
            }
        }
    }
    
    /// Store a secret securely in Keychain (for initial setup or token storage)
    public func storeSecretInKeychain(secret: String, for key: KeychainKey) {
        KeychainHelper.shared.save(secret, forKey: key.rawValue)
    }
    
    // MARK: - Private Helpers
    
    private func getEnv(_ key: EnvKey) -> String? {
        ProcessInfo.processInfo.environment[key.rawValue]
    }
    
    private func logSecurityWarning(_ message: String) {
        #if canImport(OSLog)
        logger.warning("⚠️ Security: \(message, privacy: .public)")
        #else
        print("⚠️ Security: \(message)")
        #endif
    }
}

// MARK: - Convenience Extensions

extension SecureConfig {
    /// Get WHOOP API configuration as a struct
    public var whoopConfig: WHOOPConfig {
        WHOOPConfig(
            clientID: whoopClientID,
            clientSecret: whoopClientSecret,
            redirectURI: whoopRedirectURI
        )
    }
}

/// WHOOP configuration container
public struct WHOOPConfig {
    public let clientID: String
    public let clientSecret: String
    public let redirectURI: String
    
    public var isValid: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty && !redirectURI.isEmpty
    }
}
