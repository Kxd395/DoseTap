import Foundation
import Combine
import SwiftUI
import AuthenticationServices
import Security

/// WHOOP Integration Service for sleep and recovery data
/// Implements OAuth 2.0 authorization flow and API data fetching
///
/// WHOOP API Documentation: https://developer.whoop.com/docs
///
@MainActor
final class WHOOPService: NSObject, ObservableObject {
    
    static let shared = WHOOPService()
    static let isEnabled: Bool = false  // Disabled by default until hardened
    
    // MARK: - Configuration
    
    /// WHOOP API OAuth Configuration
    /// Register at: https://developer-dashboard.whoop.com
    private struct Config {
        static let clientId = "edf2495a-adff-4b87-b845-9529051a7b39"
        static let clientSecret = "0aca5c56ec53b210260d85ac24cf57ced13dc4b4e77cbf7cf2ca20b7d3a9ed9e"
        static let redirectURI = "dosetap://whoop/callback"
        static let apiHostname = "https://api.prod.whoop.com"
        static let authURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
        static let tokenURL = "https://api.prod.whoop.com/oauth/oauth2/token"
        
        // Required scopes for sleep data
        static let scopes = ["read:recovery", "read:sleep", "read:cycles", "read:profile"]
    }
    
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
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        loadTokensFromKeychain()
        updateConnectionState()
    }
    
    // MARK: - Public API
    
    /// Start OAuth authorization flow
    func authorize() async throws {
        isLoading = true
        lastError = nil
        
        defer { isLoading = false }
        
        // Build authorization URL
        let state = UUID().uuidString
        var components = URLComponents(string: Config.authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Config.clientId),
            URLQueryItem(name: "redirect_uri", value: Config.redirectURI),
            URLQueryItem(name: "scope", value: Config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state)
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
        
        // Parse authorization code from callback
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw WHOOPError.noAuthCode
        }
        
        // Verify state matches
        if let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
           returnedState != state {
            throw WHOOPError.stateMismatch
        }
        
        // Exchange code for tokens
        try await exchangeCodeForTokens(code: code)
        
        // Fetch user profile
        try await fetchUserProfile()
        
        updateConnectionState()
        
        // Track analytics
        AnalyticsService.shared.track(.whoopConnected)
    }
    
    /// Disconnect and clear tokens
    func disconnect() {
        clearTokensFromKeychain()
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        userProfile = nil
        lastSyncTime = nil
        updateConnectionState()
        
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
    
    private func exchangeCodeForTokens(code: String) async throws {
        var request = URLRequest(url: URL(string: Config.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Config.redirectURI,
            "client_id": Config.clientId,
            "client_secret": Config.clientSecret
        ]
        
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
        
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Config.clientId,
            "client_secret": Config.clientSecret
        ]
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            // Refresh token invalid - disconnect
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
    
    /// Make authenticated API request
    func apiRequest<T: Decodable>(_ endpoint: String, type: T.Type) async throws -> T {
        try await refreshTokenIfNeeded()
        
        guard let token = accessToken else {
            throw WHOOPError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: "\(Config.apiHostname)\(endpoint)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WHOOPError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                disconnect()
                throw WHOOPError.notAuthenticated
            }
            throw WHOOPError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(T.self, from: data)
    }
    
    /// Fetch user profile
    func fetchUserProfile() async throws {
        let profile: WHOOPProfile = try await apiRequest("/developer/v1/user/profile/basic", type: WHOOPProfile.self)
        userProfile = profile
        
        if let userId = profile.userId {
            saveToKeychain(key: .userId, value: String(userId))
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
            saveToKeychain(key: .tokenExpiry, value: ISO8601DateFormatter().string(from: expiry))
        }
    }
    
    private func loadTokensFromKeychain() {
        accessToken = loadFromKeychain(key: .accessToken)
        refreshToken = loadFromKeychain(key: .refreshToken)
        if let expiryString = loadFromKeychain(key: .tokenExpiry) {
            tokenExpiry = ISO8601DateFormatter().date(from: expiryString)
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

// MARK: - Error Types

enum WHOOPError: LocalizedError {
    case invalidURL
    case userCancelled
    case noCallback
    case noAuthCode
    case stateMismatch
    case invalidResponse
    case httpError(Int)
    case apiError(String, String?)
    case notAuthenticated
    case noRefreshToken
    case refreshFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid WHOOP URL"
        case .userCancelled: return "Authorization cancelled"
        case .noCallback: return "No callback received"
        case .noAuthCode: return "No authorization code received"
        case .stateMismatch: return "Security state mismatch"
        case .invalidResponse: return "Invalid server response"
        case .httpError(let code): return "HTTP error: \(code)"
        case .apiError(let error, let desc): return desc ?? error
        case .notAuthenticated: return "Not authenticated with WHOOP"
        case .noRefreshToken: return "No refresh token available"
        case .refreshFailed: return "Failed to refresh token"
        }
    }
}

// MARK: - Response Models

struct WHOOPTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

struct WHOOPErrorResponse: Codable {
    let error: String
    let errorDescription: String?
    
    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

struct WHOOPProfile: Codable {
    let userId: Int?
    let firstName: String?
    let lastName: String?
    let email: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
    }
}
