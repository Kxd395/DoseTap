import Foundation
import os.log
// import UIKit  // Temporarily commented out until iOS project is properly configured

// MARK: - Secure Logger (no token values in logs)
private let whoopLog = Logger(subsystem: "com.dosetap.app", category: "WHOOP")

class WHOOPManager {
    static let shared = WHOOPManager()

    // WHOOP API Configuration
    private let baseURL = "https://api.prod.whoop.com"
    private let scope = "read:recovery read:cycles read:sleep read:workout read:profile read:body_measurement offline"
    
    // MARK: - Secure Configuration (loaded from SecureConfig)
    private var clientID: String { SecureConfig.shared.whoopClientID }
    private var clientSecret: String { SecureConfig.shared.whoopClientSecret }
    private var redirectURI: String { SecureConfig.shared.whoopRedirectURI }
    
    // MARK: - OAuth State Storage Keys (Keychain-based for CSRF protection)
    private static let oauthStateKey = "whoop_oauth_state"
    private static let oauthStateExpirationKey = "whoop_oauth_state_expiration"
    private static let oauthStateTTL: TimeInterval = 300 // 5 minutes

    struct MetricEndpointConfig {
        let path: String
        let startParam: String
        let endParam: String
        let containerKeys: [String]
        let valueKeys: [String]
        let scale: Double? // multiply returned values to normalize units (e.g., 0.01 to convert %→fraction)
    }

    private var endpoints: [String: MetricEndpointConfig] = [:] // hr, rr, spo2, hrv

    private init() {
        // Validate configuration on init
        if !SecureConfig.shared.isConfigured {
            whoopLog.warning("WHOOP credentials not configured - check Secrets.swift or environment variables")
        }

        // Load metric endpoint config (optional) from Config.plist if present
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let ep = dict["WHOOP_METRIC_ENDPOINTS"] as? [String: Any] {
            self.endpoints = WHOOPManager.parseEndpoints(ep)
        }
    }
    
    // MARK: - Secure Token Storage (Keychain)
    
    private var accessToken: String? {
        get { KeychainHelper.shared.whoopAccessToken }
        set {
            if let token = newValue {
                KeychainHelper.shared.save(token, forKey: "whoop_access_token")
            } else {
                KeychainHelper.shared.delete(forKey: "whoop_access_token")
            }
        }
    }

    private var refreshToken: String? {
        get { KeychainHelper.shared.whoopRefreshToken }
        set {
            if let token = newValue {
                KeychainHelper.shared.save(token, forKey: "whoop_refresh_token")
            } else {
                KeychainHelper.shared.delete(forKey: "whoop_refresh_token")
            }
        }
    }

    private var tokenExpiration: Date? {
        get {
            if let str = KeychainHelper.shared.read(forKey: "whoop_token_expiration"),
               let timestamp = Double(str) {
                return Date(timeIntervalSince1970: timestamp)
            }
            return nil
        }
        set {
            if let exp = newValue {
                KeychainHelper.shared.save(String(exp.timeIntervalSince1970), forKey: "whoop_token_expiration")
            } else {
                KeychainHelper.shared.delete(forKey: "whoop_token_expiration")
            }
        }
    }

    // Generate cryptographically secure state parameter for CSRF protection
    private func generateState() -> String {
        // Use 32 bytes of random data for cryptographic security
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
    
    // MARK: - Secure OAuth State Management (Keychain-based)
    
    /// Store OAuth state securely in Keychain with TTL
    private func storeOAuthState(_ state: String) {
        KeychainHelper.shared.save(state, forKey: Self.oauthStateKey)
        let expiration = Date().addingTimeInterval(Self.oauthStateTTL)
        KeychainHelper.shared.save(String(expiration.timeIntervalSince1970), forKey: Self.oauthStateExpirationKey)
    }
    
    /// Retrieve and validate OAuth state from Keychain
    /// Returns nil if expired or not found
    private func retrieveOAuthState() -> String? {
        guard let state = KeychainHelper.shared.read(forKey: Self.oauthStateKey),
              let expirationStr = KeychainHelper.shared.read(forKey: Self.oauthStateExpirationKey),
              let expirationTimestamp = Double(expirationStr) else {
            return nil
        }
        
        let expiration = Date(timeIntervalSince1970: expirationTimestamp)
        guard Date() < expiration else {
            // State expired - clean up
            clearOAuthState()
            whoopLog.warning("OAuth state expired")
            return nil
        }
        
        return state
    }
    
    /// Clear OAuth state from Keychain
    private func clearOAuthState() {
        KeychainHelper.shared.delete(forKey: Self.oauthStateKey)
        KeychainHelper.shared.delete(forKey: Self.oauthStateExpirationKey)
    }

    // Start OAuth flow with state parameter
    func authorize() {
        let state = generateState()
        storeOAuthState(state)

        let authURL = "\(baseURL)/oauth/oauth2/auth?response_type=code&client_id=\(clientID)&redirect_uri=\(redirectURI)&scope=\(scope)&state=\(state)"
        if let url = URL(string: authURL) {
            #if os(iOS)
            // UIApplication.shared.open(url)  // Temporarily commented until UIKit is available
            whoopLog.info("WHOOP: Opening OAuth URL")
            #endif
        }
    }

    // Handle OAuth callback with state validation
    func handleCallback(url: URL) {
        guard url.scheme == "dosetap", url.host == "oauth", url.path == "/callback",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            whoopLog.error("WHOOP: Invalid callback URL or missing parameters")
            return
        }

        // Validate state parameter for CSRF protection (from Keychain)
        guard let storedState = retrieveOAuthState() else {
            whoopLog.error("WHOOP: No valid OAuth state found - possible timeout or attack")
            return
        }
        
        guard returnedState == storedState else {
            whoopLog.error("WHOOP: State parameter mismatch - possible CSRF attack")
            clearOAuthState()
            return
        }

        // Clear stored state immediately after validation
        clearOAuthState()

        exchangeCodeForToken(code: code)
    }

    // Exchange authorization code for access token
    private func exchangeCodeForToken(code: String) {
        #if os(iOS)
        if #available(iOS 15.0, *) {
            Task {
                let tokenURL = "\(baseURL)/oauth/oauth2/token"
                var request = URLRequest(url: URL(string: tokenURL)!)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

                let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)&client_id=\(clientID)&client_secret=\(clientSecret)"
                request.httpBody = body.data(using: .utf8)

                do {
                    let (data, response) = try await URLSession.shared.data(for: request)

                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let token = json["access_token"] as? String {
                            self.accessToken = token
                            whoopLog.info("Access token obtained successfully")

                            // Store refresh token if provided
                            if let refreshToken = json["refresh_token"] as? String {
                                self.refreshToken = refreshToken
                            }

                            // Store expiration
                            if let expiresIn = json["expires_in"] as? TimeInterval {
                                self.tokenExpiration = Date().addingTimeInterval(expiresIn)
                            }
                        }
                    } else {
                        whoopLog.error("Token exchange failed")
                        if let responseString = String(data: data, encoding: .utf8) {
                            whoopLog.debug("Token response: \(responseString, privacy: .private)")
                        }
                    }
                } catch {
                    whoopLog.error("Token exchange error: \(error.localizedDescription)")
                }
            }
        } else {
            print("WHOOP: iOS 15.0+ required for async operations")
        }
        #endif
    }

    // Refresh access token using refresh token
    private func refreshAccessToken() async throws -> Bool {
        guard let refreshToken = self.refreshToken else {
            whoopLog.warning("No refresh token available")
            return false
        }

        let tokenURL = "\(baseURL)/oauth/oauth2/token"
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientID)&client_secret=\(clientSecret)&scope=\(scope)"
        request.httpBody = body.data(using: .utf8)

        #if os(iOS)
        if #available(iOS 15.0, *) {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let newToken = json["access_token"] as? String {
                    self.accessToken = newToken
                    whoopLog.info("Access token refreshed successfully")

                    // Update refresh token if provided
                    if let newRefreshToken = json["refresh_token"] as? String {
                        self.refreshToken = newRefreshToken
                    }

                    // Update expiration
                    if let expiresIn = json["expires_in"] as? TimeInterval {
                        self.tokenExpiration = Date().addingTimeInterval(expiresIn)
                    }

                    return true
                }
            }

            whoopLog.error("Token refresh failed")
            if let responseString = String(data: data, encoding: .utf8) {
                whoopLog.debug("Refresh response: \(responseString, privacy: .private)")
            }
        } else {
            whoopLog.warning("iOS 15.0+ required for async URLSession")
        }
        #endif
        return false
    }

    // Clear all stored tokens (for logout)
    func clearTokens() {
        accessToken = nil
        refreshToken = nil
        tokenExpiration = nil
        UserDefaults.standard.removeObject(forKey: "whoop_oauth_state")
        whoopLog.info("All tokens cleared")
    }

    // Check if user is authenticated
    func isAuthenticated() -> Bool {
        return accessToken != nil && !isTokenExpired()
    }

    // Revoke access token on WHOOP's servers (complete disconnect)
    func revokeAccess() async {
        guard let token = accessToken else {
            whoopLog.info("No access token to revoke")
            return
        }

        let revokeURL = "\(baseURL)/v1/user/oauth_access"
        var request = URLRequest(url: URL(string: revokeURL)!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            #if os(iOS)
            if #available(iOS 15.0, *) {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        whoopLog.info("Access token successfully revoked on WHOOP servers")
                    } else {
                        whoopLog.error("Failed to revoke token, status: \(httpResponse.statusCode)")
                    }
                }
            } else {
                whoopLog.warning("iOS 15.0+ required for async URLSession")
            }
            #endif
        } catch {
            whoopLog.error("Error revoking access token: \(error.localizedDescription)")
        }

        // Always clear local tokens regardless of server response
        clearTokens()
    }

    // Enhanced error handling and logging with automatic token refresh
    func fetchSleepHistory() async -> [NightSummary] {
        // Check if we need to refresh the token first
        if isTokenExpired(), let _ = refreshToken {
            do {
                let refreshSuccess = try await refreshAccessToken()
                if !refreshSuccess {
                    whoopLog.error("Token refresh failed, cannot fetch sleep data")
                    return []
                }
            } catch {
                whoopLog.error("Token refresh error: \(error.localizedDescription)")
                return []
            }
        }

        guard let token = accessToken else {
            whoopLog.warning("No access token available")
            return []
        }

        let sleepURL = "\(baseURL)/v2/activity/sleep?limit=30"
        var request = URLRequest(url: URL(string: sleepURL)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            whoopLog.debug("Fetching sleep history")
            #if os(iOS)
            if #available(iOS 15.0, *) {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    whoopLog.debug("Sleep API response status: \(httpResponse.statusCode)")

                    // Handle 401 Unauthorized - token might be expired
                    if httpResponse.statusCode == 401 {
                        whoopLog.warning("Received 401, attempting token refresh")
                        if let _ = refreshToken {
                            do {
                                let refreshSuccess = try await refreshAccessToken()
                                if refreshSuccess {
                                    // Retry the request with new token
                                    return await fetchSleepHistory()
                                }
                            } catch {
                                whoopLog.error("Token refresh failed during 401 handling: \(error.localizedDescription)")
                            }
                        }
                        return []
                    }

                    if httpResponse.statusCode != 200 {
                        whoopLog.error("API error response: \(String(data: data, encoding: .utf8) ?? "No response body", privacy: .private)")
                        return []
                    }
                }

                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let records = json?["records"] as? [[String: Any]] {
                    whoopLog.info("Successfully parsed \(records.count) sleep records")
                    return parseSleepRecords(records)
                } else {
                    whoopLog.warning("No records found in response")
                }
            } else {
                whoopLog.warning("iOS 15.0+ required for async URLSession")
            }
            #endif
        } catch {
            whoopLog.error("Sleep fetch error: \(error.localizedDescription)")
        }
        return []
    }

    // Fetch sleep data for a specific cycle (more precise than general sleep history)
    func fetchSleepForCycle(_ cycleId: String) async -> NightSummary? {
        guard let token = accessToken else { return nil }

        let cycleSleepURL = "\(baseURL)/v2/cycle/\(cycleId)/sleep"
        var request = URLRequest(url: URL(string: cycleSleepURL)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            #if os(iOS)
            if #available(iOS 15.0, *) {
                let (data, _) = try await URLSession.shared.data(for: request)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let record = json {
                    return parseSingleSleepRecord(record)
                }
            } else {
                print("WHOOP: iOS 15.0+ required for async URLSession")
            }
            #endif
        } catch {
            print("WHOOP cycle sleep fetch error: \(error)")
        }
        return nil
    }

    // Check if token is expired or about to expire (within 5 minutes)
    private func isTokenExpired() -> Bool {
        guard let expiration = tokenExpiration else { return true }
        return Date().addingTimeInterval(300) >= expiration // 5 minutes buffer
    }

    private func parseSleepRecords(_ records: [[String: Any]]) -> [NightSummary] {
        var summaries: [NightSummary] = []
        for record in records {
            // Extract sleep timing from the record
            guard let start = record["start"] as? String,
                  let _ = record["end"] as? String,
                  let stageSummary = record["stage_summary"] as? [String: Any] else { continue }

            // Parse sleep stages to find wake time
            if let awakeStages = stageSummary["awake"] as? [[String: Any]],
               let firstAwake = awakeStages.first,
               let awakeStart = firstAwake["start"] as? String {

                // Calculate time from sleep start to first wake
                if let startDate = ISO8601DateFormatter().date(from: start),
                   let awakeDate = ISO8601DateFormatter().date(from: awakeStart) {
                    let minutes = Int(awakeDate.timeIntervalSince(startDate) / 60)
                    if minutes >= 150 && minutes <= 240 {
                        summaries.append(NightSummary(minutesToFirstWake: minutes, disturbancesScore: nil))
                    }
                }
            }
        }
        return summaries
    }

    private func parseSingleSleepRecord(_ record: [String: Any]) -> NightSummary? {
        guard let start = record["start"] as? String,
              let _ = record["end"] as? String,
              let stageSummary = record["stage_summary"] as? [String: Any] else { return nil }

        // Extract awake stages to find first wake time
        if let awakeStages = stageSummary["awake"] as? [[String: Any]],
           let firstAwake = awakeStages.first,
           let awakeStart = firstAwake["start"] as? String {

            if let startDate = ISO8601DateFormatter().date(from: start),
               let awakeDate = ISO8601DateFormatter().date(from: awakeStart) {
                let minutes = Int(awakeDate.timeIntervalSince(startDate) / 60)
                if minutes >= 150 && minutes <= 240 {
                    return NightSummary(minutesToFirstWake: minutes, disturbancesScore: nil)
                }
            }
        }
        return nil
    }

    // Debug method to test WHOOP integration without real API calls
    func testIntegration() async -> String {
        if !isAuthenticated() {
            return "❌ Not authenticated with WHOOP. Please connect first."
        }

        let tokenStatus = getTokenStatus()
        return """
        ✅ WHOOP Integration Status:
        \(tokenStatus)

        🔍 What would be retrieved:
        • Sleep records from last 30 days
        • Time from sleep start to first wake (TTFW)
        • Used for calculating optimal medication timing
        • Data is processed locally and not stored
        """
    }

    // Simulate a real WHOOP API response for testing
    func simulateAPIResponse() -> String {
        let mockResponse = """
        🌙 Simulated WHOOP API Response:
        GET https://api.prod.whoop.com/v2/activity/sleep?limit=30

        Response:
        {
          "records": [
            {
              "id": "01HXXXXXXXXXXXXXXXXX",
              "user_id": "01HXXXXXXXXXXXXXXX",
              "created_at": "2025-09-02T06:15:00.000Z",
              "updated_at": "2025-09-02T06:15:00.000Z",
              "start": "2025-09-01T22:30:00.000Z",
              "end": "2025-09-02T06:15:00.000Z",
              "timezone_offset": "-04:00",
              "nap": false,
              "score": {
                "stage_summary": {
                  "total_in_bed_time_milli": 27300000,
                  "total_awake_time_milli": 300000,
                  "total_no_bed_time_milli": 0,
                  "total_light_sleep_time_milli": 7200000,
                  "total_slow_wave_sleep_time_milli": 7200000,
                  "total_rem_sleep_time_milli": 5400000,
                  "sleep_cycle_count": 4,
                  "awake": [
                    {
                      "start": "2025-09-02T06:15:00.000Z",
                      "end": "2025-09-02T06:15:05.000Z",
                      "duration_milli": 5000
                    }
                  ]
                }
              }
            }
          ]
        }

        � Extracted Data for DoseTap:
        • Sleep Start: 2025-09-01 22:30:00 UTC
        • First Wake: 2025-09-02 06:15:00 UTC
        • Time to First Wake: 465 minutes
        • Within safe window (150-240 min): No (too long)
        • Would use HealthKit fallback or default 165 min
        """

        return mockResponse
    }

    // Get current token status for debugging
    func getTokenStatus() -> String {
        if accessToken == nil {
            return "No access token"
        }
        if isTokenExpired() {
            return "Token expired"
        }
        if let expiration = tokenExpiration {
            let remaining = expiration.timeIntervalSince(Date())
            return String(format: "Token valid for %.0f minutes", remaining / 60)
        }
        return "Token status unknown"
    }

    // MARK: - Metric averages (experimental wiring)
    struct WhoopVitals { let hr: Double?; let rr: Double?; let spo2: Double?; let hrv: Double? }

    /// Attempts to fetch average HR/RR/SpO2/HRV for a time window. Endpoints may evolve; this is best‑effort.
    /// Returns nils when data is unavailable so callers can degrade gracefully.
    func fetchVitalsAverage(start: Date, end: Date) async -> WhoopVitals {
        let hr = await fetchAverageMetric(paths: [
            "/v1/physiological/heart_rate",
            "/v2/metrics/heart_rate",
        ], start: start, end: end)
        let rr = await fetchAverageMetric(paths: [
            "/v1/physiological/respiratory_rate",
            "/v2/metrics/respiratory_rate",
        ], start: start, end: end)
        let sO2 = await fetchAverageMetric(paths: [
            "/v1/physiological/oxygen_saturation",
            "/v2/metrics/oxygen_saturation",
        ], start: start, end: end)
        let hrv = await fetchAverageMetric(paths: [
            "/v1/physiological/hrv",
            "/v2/metrics/hrv",
        ], start: start, end: end)
        return WhoopVitals(hr: hr, rr: rr, spo2: sO2, hrv: hrv)
    }

    /// Preferred: use endpoints configured in Config.plist > WHOOP_METRIC_ENDPOINTS
    func fetchVitalsAverageConfigured(start: Date, end: Date) async -> WhoopVitals {
        guard !endpoints.isEmpty else { return WhoopVitals(hr: nil, rr: nil, spo2: nil, hrv: nil) }
        let hr = await fetchAverageConfigured(metricKey: "hr", start: start, end: end)
        let rr = await fetchAverageConfigured(metricKey: "rr", start: start, end: end)
        let spo2 = await fetchAverageConfigured(metricKey: "spo2", start: start, end: end)
        let hrv = await fetchAverageConfigured(metricKey: "hrv", start: start, end: end)
        return WhoopVitals(hr: hr, rr: rr, spo2: spo2, hrv: hrv)
    }

    private func fetchAverageMetric(paths: [String], start: Date, end: Date) async -> Double? {
        guard let token = accessToken else { return nil }
        let iso = ISO8601DateFormatter()
        for p in paths {
            let urlStr = "\(baseURL)\(p)?start=\(iso.string(from: start))&end=\(iso.string(from: end))"
            guard let url = URL(string: urlStr) else { continue }
            do {
                #if os(iOS)
                if #available(iOS 15.0, *) {
                    var req = URLRequest(url: url)
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Accept")
                    let (data, response) = try await URLSession.shared.data(for: req)
                    if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                        if let val = parseAverage(from: data) { return val }
                    }
                }
                #endif
            } catch {
                print("WHOOP metric fetch error for \(p): \(error)")
            }
        }
        return nil
    }

    private func parseAverage(from data: Data) -> Double? {
        // Accept either { records: [...] } or raw array; detect common keys
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let items: [Any]
        if let dict = json as? [String: Any], let recs = dict["records"] as? [Any] { items = recs }
        else if let arr = json as? [Any] { items = arr }
        else { return nil }
        var values: [Double] = []
        for item in items {
            if let d = item as? [String: Any] {
                if let v = d["value"] as? Double { values.append(v) }
                else if let v = d["avg"] as? Double { values.append(v) }
                else if let v = d["mean"] as? Double { values.append(v) }
                else if let m = d["metric"] as? [String: Any], let v = m["value"] as? Double { values.append(v) }
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Endpoint config helpers
    private static func parseEndpoints(_ anyDict: [String: Any]) -> [String: MetricEndpointConfig] {
        var map: [String: MetricEndpointConfig] = [:]
        for key in ["hr","rr","spo2","hrv"] {
            guard let raw = anyDict[key] as? [String: Any],
                  let path = raw["path"] as? String else { continue }
            let startParam = (raw["start_param"] as? String) ?? "start"
            let endParam = (raw["end_param"] as? String) ?? "end"
            let containerKeys = raw["container_keys"] as? [String] ?? ["records","data","items"]
            let valueKeys = raw["value_keys"] as? [String] ?? ["value","avg","mean"]
            let scale = raw["value_scale"] as? Double
            map[key] = MetricEndpointConfig(path: path, startParam: startParam, endParam: endParam, containerKeys: containerKeys, valueKeys: valueKeys, scale: scale)
        }
        return map
    }

    private func fetchAverageConfigured(metricKey: String, start: Date, end: Date) async -> Double? {
        guard let ep = endpoints[metricKey], let token = accessToken else { return nil }
        let iso = ISO8601DateFormatter()
        let startStr = iso.string(from: start)
        let endStr = iso.string(from: end)
        var comps = URLComponents(string: baseURL + ep.path)
        comps?.queryItems = [URLQueryItem(name: ep.startParam, value: startStr), URLQueryItem(name: ep.endParam, value: endStr)]
        guard let url = comps?.url else { return nil }
        do {
            #if os(iOS)
            if #available(iOS 15.0, *) {
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    if let val = parseAverage(from: data, containerKeys: ep.containerKeys, valueKeys: ep.valueKeys, scale: ep.scale) {
                        return val
                    }
                }
            }
            #endif
        } catch {
            print("WHOOP configured metric fetch error for \(metricKey): \(error)")
        }
        return nil
    }

    private func parseAverage(from data: Data, containerKeys: [String], valueKeys: [String], scale: Double?) -> Double? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var items: [Any]? = nil
        if let dict = json as? [String: Any] {
            for k in containerKeys { if let arr = dict[k] as? [Any] { items = arr; break } }
        } else if let arr = json as? [Any] { items = arr }
        guard let rows = items, !rows.isEmpty else { return nil }
        var values: [Double] = []
        for item in rows {
            if let d = item as? [String: Any] {
                var found: Double? = nil
                for k in valueKeys { if let v = d[k] as? Double { found = v; break } }
                if let v = found { values.append(scale != nil ? v * scale! : v) }
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
