import Foundation
import Security

/// Secure Keychain storage for sensitive data like OAuth tokens
public final class KeychainHelper {
    public static let shared = KeychainHelper()
    private let service = "com.dosetap.app"
    
    private init() {}
    
    // MARK: - Save
    
    /// Save a string value to Keychain
    @discardableResult
    public func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return save(data, forKey: key)
    }
    
    /// Save data to Keychain
    @discardableResult
    public func save(_ data: Data, forKey key: String) -> Bool {
        // Delete any existing item first
        delete(forKey: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Read
    
    /// Read a string value from Keychain
    public func read(forKey key: String) -> String? {
        guard let data = readData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Read data from Keychain
    public func readData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
    
    // MARK: - Delete
    
    /// Delete a value from Keychain
    @discardableResult
    public func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - WHOOP Token Helpers
    
    private static let whoopAccessTokenKey = "whoop_access_token"
    private static let whoopRefreshTokenKey = "whoop_refresh_token"
    private static let whoopExpirationKey = "whoop_token_expiration"
    
    /// Save WHOOP OAuth tokens securely
    public func saveWHOOPTokens(accessToken: String, refreshToken: String?, expiresIn: Int) {
        save(accessToken, forKey: Self.whoopAccessTokenKey)
        
        if let refresh = refreshToken {
            save(refresh, forKey: Self.whoopRefreshTokenKey)
        }
        
        let expiration = Date().addingTimeInterval(TimeInterval(expiresIn))
        save(String(expiration.timeIntervalSince1970), forKey: Self.whoopExpirationKey)
    }
    
    /// Get WHOOP access token if valid
    public var whoopAccessToken: String? {
        guard let token = read(forKey: Self.whoopAccessTokenKey),
              let expirationStr = read(forKey: Self.whoopExpirationKey),
              let expiration = Double(expirationStr) else {
            return nil
        }
        
        // Return nil if expired
        if Date().timeIntervalSince1970 > expiration {
            return nil
        }
        
        return token
    }
    
    /// Get WHOOP refresh token
    public var whoopRefreshToken: String? {
        read(forKey: Self.whoopRefreshTokenKey)
    }
    
    /// Check if WHOOP token needs refresh (expired or expiring within 5 minutes)
    public var whoopTokenNeedsRefresh: Bool {
        guard let expirationStr = read(forKey: Self.whoopExpirationKey),
              let expiration = Double(expirationStr) else {
            return true
        }
        
        // Refresh if expiring within 5 minutes
        return Date().timeIntervalSince1970 > (expiration - 300)
    }
    
    /// Clear all WHOOP tokens (logout)
    public func clearWHOOPTokens() {
        delete(forKey: Self.whoopAccessTokenKey)
        delete(forKey: Self.whoopRefreshTokenKey)
        delete(forKey: Self.whoopExpirationKey)
    }
}
