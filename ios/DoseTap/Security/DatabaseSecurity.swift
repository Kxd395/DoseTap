// DatabaseSecurity.swift
// DoseTap
//
// Database encryption key management and security utilities
// This prepares the codebase for SQLCipher integration

import Foundation
import Security
#if canImport(OSLog)
import OSLog
#endif

/// Database security manager for encryption key management
/// Implements industry-standard key derivation and storage practices
public final class DatabaseSecurity {
    
    public static let shared = DatabaseSecurity()
    
    #if canImport(OSLog)
    private let logger = Logger(subsystem: "com.dosetap.app", category: "DatabaseSecurity")
    #endif
    
    // MARK: - Keychain Keys
    
    private enum KeychainKey: String {
        case databaseEncryptionKey = "dosetap_db_encryption_key_v1"
        case databaseKeySalt = "dosetap_db_key_salt_v1"
    }
    
    // MARK: - Key Management
    
    /// Get or create database encryption key
    /// Key is stored securely in Keychain with device-only access
    public func getOrCreateEncryptionKey() -> Data? {
        // Try to load existing key
        if let existingKey = loadEncryptionKey() {
            return existingKey
        }
        
        // Generate new key
        guard let newKey = generateSecureKey() else {
            logError("Failed to generate encryption key")
            return nil
        }
        
        // Store in Keychain
        guard storeEncryptionKey(newKey) else {
            logError("Failed to store encryption key in Keychain")
            return nil
        }
        
        logInfo("Created and stored new database encryption key")
        return newKey
    }
    
    /// Generate a cryptographically secure 256-bit key
    private func generateSecureKey() -> Data? {
        var keyData = Data(count: 32) // 256 bits
        let result = keyData.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        
        guard result == errSecSuccess else {
            return nil
        }
        
        return keyData
    }
    
    /// Load encryption key from Keychain
    private func loadEncryptionKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.dosetap.database",
            kSecAttrAccount as String: KeychainKey.databaseEncryptionKey.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            return nil
        }
        
        return result as? Data
    }
    
    /// Store encryption key in Keychain with high security attributes
    private func storeEncryptionKey(_ key: Data) -> Bool {
        // Delete any existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.dosetap.database",
            kSecAttrAccount as String: KeychainKey.databaseEncryptionKey.rawValue
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new key with secure attributes
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.dosetap.database",
            kSecAttrAccount as String: KeychainKey.databaseEncryptionKey.rawValue,
            kSecValueData as String: key,
            // Device-only access, available after first unlock
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            // Prevent backup/sync
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Convert key data to hex string for SQLCipher PRAGMA
    public func keyToHexString(_ key: Data) -> String {
        return key.map { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Database Integrity
    
    /// Check if database encryption is available
    public var isEncryptionAvailable: Bool {
        loadEncryptionKey() != nil
    }
    
    /// Rotate encryption key (for security policies)
    /// Note: Requires re-encrypting the entire database
    public func rotateEncryptionKey() -> Data? {
        guard let newKey = generateSecureKey() else {
            logError("Failed to generate new encryption key for rotation")
            return nil
        }
        
        // Store new key (will replace old key)
        guard storeEncryptionKey(newKey) else {
            logError("Failed to store rotated encryption key")
            return nil
        }
        
        logInfo("Rotated database encryption key")
        return newKey
    }
    
    /// Delete encryption key (for factory reset)
    public func deleteEncryptionKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.dosetap.database",
            kSecAttrAccount as String: KeychainKey.databaseEncryptionKey.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        logInfo("Deleted database encryption key")
    }
    
    // MARK: - Logging
    
    private func logInfo(_ message: String) {
        #if canImport(OSLog)
        logger.info("\(message, privacy: .public)")
        #endif
    }
    
    private func logError(_ message: String) {
        #if canImport(OSLog)
        logger.error("\(message, privacy: .public)")
        #endif
    }
}

// MARK: - SQLCipher Integration Notes
/*
 To enable database encryption with SQLCipher:
 
 1. Add SQLCipher to the project:
    - SPM: .package(url: "https://github.com/nicklockwood/SQLCipher.git", from: "4.5.0")
    - CocoaPods: pod 'SQLCipher', '~> 4.5'
 
 2. Initialize encrypted database:
    ```swift
    let keyData = DatabaseSecurity.shared.getOrCreateEncryptionKey()!
    let keyHex = DatabaseSecurity.shared.keyToHexString(keyData)
    
    // Open database
    sqlite3_open(dbPath, &db)
    
    // Apply encryption key
    sqlite3_exec(db, "PRAGMA key = \"x'\(keyHex)'\"", nil, nil, nil)
    
    // Verify encryption
    var stmt: OpaquePointer?
    if sqlite3_prepare_v2(db, "SELECT count(*) FROM sqlite_master", -1, &stmt, nil) == SQLITE_OK {
        if sqlite3_step(stmt) == SQLITE_ROW {
            print("Database encrypted and accessible")
        }
    }
    sqlite3_finalize(stmt)
    ```
 
 3. Migration from unencrypted:
    ```swift
    // Export data from unencrypted DB
    // Create new encrypted DB
    // Import data
    // Delete unencrypted DB
    ```
 
 4. Performance considerations:
    - SQLCipher adds ~5-15% overhead
    - Use WAL mode for better concurrent access
    - Consider page size optimization for iOS
 */
