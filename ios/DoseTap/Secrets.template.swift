// Secrets.template.swift
// DoseTap
//
// TEMPLATE FILE - Copy to Secrets.swift and fill in your values
// DO NOT commit Secrets.swift to version control
//
// Setup Instructions:
// 1. Copy this file: cp Secrets.template.swift Secrets.swift
// 2. Fill in your actual credentials
// 3. Secrets.swift is in .gitignore and will not be committed
//
// For CI/CD, use environment variables and the SecureConfig loader

import Foundation

/// Secrets container - values loaded from environment or hardcoded for local dev
/// NEVER commit real credentials to version control
struct Secrets {
    // MARK: - WHOOP API Credentials
    
    /// WHOOP OAuth Client ID
    /// Obtain from: https://developer.whoop.com/
    static let whoopClientID = "YOUR_WHOOP_CLIENT_ID"
    
    /// WHOOP OAuth Client Secret
    /// ⚠️ SENSITIVE - Never commit, rotate if exposed
    static let whoopClientSecret = "YOUR_WHOOP_CLIENT_SECRET"
    
    /// OAuth Redirect URI
    /// Must match WHOOP app settings
    /// Local testing: http://127.0.0.1:8888/callback
    /// Production: dosetap://oauth/callback
    static let whoopRedirectURI = "dosetap://oauth/callback"
    
    // MARK: - API Configuration
    
    /// DoseTap API Base URL (if applicable)
    static let apiBaseURL = "https://api.dosetap.com"
    
    /// API Key for DoseTap backend (if applicable)
    static let apiKey = "YOUR_API_KEY"
    
    // MARK: - Analytics (Optional)
    
    /// Analytics write key (e.g., Segment, Amplitude)
    static let analyticsWriteKey = ""
    
    // MARK: - Validation
    
    /// Check if secrets are configured (not template values)
    static var isConfigured: Bool {
        whoopClientID != "YOUR_WHOOP_CLIENT_ID" &&
        whoopClientSecret != "YOUR_WHOOP_CLIENT_SECRET"
    }
    
    /// Validate configuration and log warnings
    static func validateConfiguration() {
        if !isConfigured {
            print("⚠️ Secrets not configured - copy Secrets.template.swift to Secrets.swift")
        }
    }
}
