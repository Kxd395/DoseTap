import Foundation
import Combine
import SwiftUI
import AuthenticationServices
import Security
import CryptoKit
import os

/// WHOOP Integration Service for sleep and recovery data
/// Implements OAuth 2.0 authorization flow and API data fetching
///
/// WHOOP API Documentation: https://developer.whoop.com/docs
///
@MainActor
final class WHOOPService: NSObject, ObservableObject {
    
    static let shared = WHOOPService()
    
    /// Feature gate: enabled when the user has opted in via Settings or successfully connected.
    /// Previously hardcoded `false`; now reads the user's preference so that connecting
    /// WHOOP in Settings automatically unlocks data flow across Dashboard, NightReview, and Timeline.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "whoop_enabled")
    }
    
    private static let logger = Logger(subsystem: "com.dosetap", category: "WHOOP")
    
    // MARK: - Configuration
    
    /// WHOOP API OAuth Configuration
    /// Register at: https://developer-dashboard.whoop.com
    private struct Config {
        static let apiHostname = "https://api.prod.whoop.com"
        static let authURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
        static let tokenURL = "https://api.prod.whoop.com/oauth/oauth2/token"

        // Required scopes for sleep data
        static let scopes = ["read:recovery", "read:sleep", "read:cycles", "read:profile"]
    }

    private var clientID: String { SecureConfig.shared.whoopClientID }
    private var clientSecret: String { SecureConfig.shared.whoopClientSecret }
    private var redirectURI: String { SecureConfig.shared.whoopRedirectURI }
    
    // MARK: - Keychain Keys
    
    private enum KeychainKey: String {
        case accessToken = "com.dosetap.whoop.accessToken"
        case refreshToken = "com.dosetap.whoop.refreshToken"
        case tokenExpiry = "com.dosetap.whoop.tokenExpiry"
        case userId = "com.dosetap.whoop.userId"
    }
    
    // MARK: - Published State
    
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var userProfile: WHOOPProfile?
    @Published var lastSyncTime: Date?
    
    // MARK: - Token State
    
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    
    // MARK: - Web Auth Session
    
    private var webAuthSession: ASWebAuthenticationSession?
    
    // MARK: - PKCE (P0-6)
    
    /// Transient code verifier — lives only during a single auth flow
    private var codeVerifier: String?
    
    /// Generate a cryptographically random PKCE code verifier (43-128 chars, unreserved chars)
    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Derive S256 code challenge from a code verifier
    private static func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        loadTokensFromKeychain()
        updateConnectionState()
        UserDefaults.standard.set(isConnected, forKey: "whoop_enabled")
    }
    
    // MARK: - Public API
    
    /// Start OAuth authorization flow
    func authorize() async throws {
        Self.logger.info("Starting WHOOP OAuth authorization")
        isLoading = true
        lastError = nil

        defer { isLoading = false }
        
        // PKCE: Generate code verifier and challenge
        let verifier = Self.generateCodeVerifier()
        codeVerifier = verifier
        let challenge = Self.codeChallenge(from: verifier)
        
        // Build authorization URL with PKCE
        let state = UUID().uuidString
        var components = URLComponents(string: Config.authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        guard let authURL = components.url else {
            throw WHOOPError.invalidURL
        }
        
        // Start web authentication session
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            webAuthSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "dosetap"
            ) { callbackURL, error in
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: WHOOPError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: WHOOPError.noCallback)
                    return
                }
                
                continuation.resume(returning: callbackURL)
            }
            
            webAuthSession?.presentationContextProvider = self
            webAuthSession?.prefersEphemeralWebBrowserSession = true
            webAuthSession?.start()
        }
        
        let code = try Self.validateAuthorizationCallback(callbackURL, expectedState: state)
        
        // Exchange code for tokens
        try await exchangeCodeForTokens(code: code)
        
        // Fetch user profile
        try await fetchUserProfile()
        
        updateConnectionState()
        
        // Auto-enable WHOOP integration in user settings on successful connect
        UserDefaults.standard.set(true, forKey: "whoop_enabled")
        
        // Track analytics
        AnalyticsService.shared.track(.whoopConnected)
    }

    /// Disconnect and clear tokens
    func disconnect() {
        Self.logger.info("Disconnecting WHOOP — clearing tokens")
        clearTokensFromKeychain()
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        userProfile = nil
        lastSyncTime = nil
        updateConnectionState()
        
        // Auto-disable WHOOP integration in user settings on disconnect
        UserDefaults.standard.set(false, forKey: "whoop_enabled")
        
        AnalyticsService.shared.track(.whoopDisconnected)
    }
    
    /// Refresh access token if expired
    func refreshTokenIfNeeded() async throws {
        guard let expiry = tokenExpiry, expiry <= Date() else { return }
        guard let refresh = refreshToken else {
            throw WHOOPError.noRefreshToken
        }
        
        try await refreshAccessToken(refreshToken: refresh)
    }
    
    // MARK: - Token Exchange
    
    static func validateAuthorizationCallback(_ callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw WHOOPError.noAuthCode
        }
        
        guard let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == expectedState else {
            throw WHOOPError.stateMismatch
        }
        
        return code
    }
    
    private func exchangeCodeForTokens(code: String) async throws {
        var request = URLRequest(url: URL(string: Config.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // PKCE + client_secret: WHOOP requires both (confidential client with PKCE)
        guard let verifier = codeVerifier else {
            throw WHOOPError.noAuthCode // verifier should always exist during auth flow
        }
        
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "client_secret": clientSecret,
            "code_verifier": verifier
        ]
        
        // Clear verifier after use — single use per PKCE spec
        codeVerifier = nil
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WHOOPError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(WHOOPErrorResponse.self, from: data) {
                throw WHOOPError.apiError(errorResponse.error, errorResponse.errorDescription)
            }
            throw WHOOPError.httpError(httpResponse.statusCode)
        }
        
        let tokenResponse = try JSONDecoder().decode(WHOOPTokenResponse.self, from: data)
        
        // Store tokens
        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60)) // 60s buffer
        
        saveTokensToKeychain()
    }
    
    private func refreshAccessToken(refreshToken: String) async throws {
        var request = URLRequest(url: URL(string: Config.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // WHOOP requires client_secret for refresh (confidential client)
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret
        ]
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            // Refresh token invalid - disconnect
            Self.logger.warning("WHOOP token refresh failed — disconnecting")
            disconnect()
            throw WHOOPError.refreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(WHOOPTokenResponse.self, from: data)
        
        accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken ?? self.refreshToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 60))
        
        saveTokensToKeychain()
    }
    
    // MARK: - API Requests
    
    /// Make authenticated API request with resilient retry
    func apiRequest<T: Decodable>(_ endpoint: String, type: T.Type, maxRetries: Int = 2) async throws -> T {
        try await refreshTokenIfNeeded()
        
        guard let token = accessToken else {
            throw WHOOPError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: "\(Config.apiHostname)\(endpoint)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        var lastError: Error = WHOOPError.invalidResponse
        for attempt in 0...maxRetries {
            if attempt > 0 {
                // Exponential backoff: 1s, 2s
                let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                try await Task.sleep(nanoseconds: delay)
                Self.logger.info("WHOOP API retry attempt \(attempt) for \(endpoint, privacy: .public)")
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw WHOOPError.invalidResponse
                }
                
                guard (200..<300).contains(httpResponse.statusCode) else {
                    if httpResponse.statusCode == 401 {
                        Self.logger.warning("WHOOP 401 — disconnecting")
                        disconnect()
                        throw WHOOPError.notAuthenticated
                    }
                    if httpResponse.statusCode == 429 || (500..<600).contains(httpResponse.statusCode) {
                        // Retryable errors
                        Self.logger.warning("WHOOP \(httpResponse.statusCode) — will retry")
                        lastError = WHOOPError.httpError(httpResponse.statusCode)
                        continue
                    }
                    throw WHOOPError.httpError(httpResponse.statusCode)
                }
                
                let decoder = Self.makeAPIDecoder()
                
                Self.logger.debug("WHOOP API success: \(endpoint, privacy: .public)")
                return try decoder.decode(T.self, from: data)
            } catch let error as WHOOPError {
                throw error  // Don't retry auth/client errors
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Network errors are retryable
                Self.logger.warning("WHOOP network error: \(error.localizedDescription, privacy: .public)")
                lastError = error
                continue
            }
        }
        
        Self.logger.error("WHOOP API failed after \(maxRetries + 1) attempts: \(endpoint, privacy: .public)")
        throw lastError
    }

    static func makeAPIDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // WHOOP models already declare explicit snake_case CodingKeys.
        // convertFromSnakeCase breaks those mappings for fields like
        // cycle_id and stage_summary by transforming payload keys twice.
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = AppFormatters.parseISO8601Flexible(value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid WHOOP ISO-8601 date: \(value)"
            )
        }
        return decoder
    }
    
    /// Fetch user profile
    func fetchUserProfile() async throws {
        let profile: WHOOPProfile = try await apiRequest("/developer/v2/user/profile/basic", type: WHOOPProfile.self)
        userProfile = profile
        
        if let userId = profile.userId {
            saveToKeychain(key: .userId, value: userId)
        }
    }
    
    // MARK: - Connection State
    
    private func updateConnectionState() {
        isConnected = accessToken != nil && (tokenExpiry ?? Date.distantPast) > Date()
    }
    
    // MARK: - Keychain Storage
    
    private func saveTokensToKeychain() {
        if let token = accessToken {
            saveToKeychain(key: .accessToken, value: token)
        }
        if let refresh = refreshToken {
            saveToKeychain(key: .refreshToken, value: refresh)
        }
        if let expiry = tokenExpiry {
            saveToKeychain(key: .tokenExpiry, value: AppFormatters.iso8601.string(from: expiry))
        }
    }
    
    private func loadTokensFromKeychain() {
        accessToken = loadFromKeychain(key: .accessToken)
        refreshToken = loadFromKeychain(key: .refreshToken)
        if let expiryString = loadFromKeychain(key: .tokenExpiry) {
            tokenExpiry = AppFormatters.iso8601.date(from: expiryString)
        }
    }
    
    private func clearTokensFromKeychain() {
        deleteFromKeychain(key: .accessToken)
        deleteFromKeychain(key: .refreshToken)
        deleteFromKeychain(key: .tokenExpiry)
        deleteFromKeychain(key: .userId)
    }
    
    private func saveToKeychain(key: KeychainKey, value: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func loadFromKeychain(key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    private func deleteFromKeychain(key: KeychainKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension WHOOPService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
