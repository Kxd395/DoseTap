// Tests/DoseCoreTests/DataRedactorTests.swift
// Tests for PII redaction in support bundles and exports

import XCTest
@testable import DoseCore

final class DataRedactorTests: XCTestCase {
    
    // MARK: - Email Redaction Tests
    
    func test_redact_removesEmailAddresses() {
        let redactor = DataRedactor()
        let input = "Contact us at support@dosetap.app for help"
        
        let result = redactor.redact(input)
        
        XCTAssertFalse(result.redactedText.contains("support@dosetap.app"))
        XCTAssertTrue(result.redactedText.contains("[EMAIL_REDACTED]"))
        XCTAssertEqual(result.redactionsApplied, 1)
        XCTAssertTrue(result.redactionTypes.contains(.email))
    }
    
    func test_redact_handlesMultipleEmails() {
        let redactor = DataRedactor()
        let input = "From: user@example.com To: admin@test.org"
        
        let result = redactor.redact(input)
        
        XCTAssertFalse(result.redactedText.contains("@"))
        XCTAssertEqual(result.redactionsApplied, 2)
    }
    
    func test_redact_preservesTextAroundEmails() {
        let redactor = DataRedactor()
        let input = "Hello user@test.com goodbye"
        
        let result = redactor.redact(input)
        
        XCTAssertTrue(result.redactedText.hasPrefix("Hello"))
        XCTAssertTrue(result.redactedText.hasSuffix("goodbye"))
    }
    
    func test_redact_withEmailsDisabled_preservesEmails() {
        let config = RedactionConfig(hashDeviceIDs: true, removeEmails: false, removeNames: false, hashPrefix: "H_")
        let redactor = DataRedactor(config: config)
        let input = "Email: user@test.com"
        
        let result = redactor.redact(input)
        
        XCTAssertTrue(result.redactedText.contains("user@test.com"))
    }
    
    // MARK: - UUID Redaction Tests
    
    func test_redact_hashesUUIDs() {
        let redactor = DataRedactor()
        let uuid = "550E8400-E29B-41D4-A716-446655440000"
        let input = "Device ID: \(uuid)"
        
        let result = redactor.redact(input)
        
        XCTAssertFalse(result.redactedText.contains(uuid))
        XCTAssertTrue(result.redactedText.contains("HASH_"))
        XCTAssertEqual(result.redactionsApplied, 1)
        XCTAssertTrue(result.redactionTypes.contains(.uuid))
    }
    
    func test_redact_hashesMultipleUUIDs() {
        let redactor = DataRedactor()
        let input = """
        User: 550E8400-E29B-41D4-A716-446655440000
        Session: A1B2C3D4-E5F6-7890-ABCD-EF1234567890
        """
        
        let result = redactor.redact(input)
        
        XCTAssertEqual(result.redactionsApplied, 2)
    }
    
    func test_hashDeviceID_producesConsistentHash() {
        let redactor = DataRedactor()
        let deviceID = "550E8400-E29B-41D4-A716-446655440000"
        
        let hash1 = redactor.hashDeviceID(deviceID)
        let hash2 = redactor.hashDeviceID(deviceID)
        
        XCTAssertEqual(hash1, hash2, "Same input should produce same hash")
    }
    
    func test_hashDeviceID_differentIDsProduceDifferentHashes() {
        let redactor = DataRedactor()
        let id1 = "550E8400-E29B-41D4-A716-446655440000"
        let id2 = "550E8400-E29B-41D4-A716-446655440001"
        
        let hash1 = redactor.hashDeviceID(id1)
        let hash2 = redactor.hashDeviceID(id2)
        
        XCTAssertNotEqual(hash1, hash2)
    }
    
    func test_hashDeviceID_usesConfiguredPrefix() {
        let config = RedactionConfig(hashDeviceIDs: true, removeEmails: true, removeNames: true, hashPrefix: "DEV_")
        let redactor = DataRedactor(config: config)
        
        let hash = redactor.hashDeviceID("test-id")
        
        XCTAssertTrue(hash.hasPrefix("DEV_"))
    }
    
    // MARK: - IP Address Redaction Tests
    
    func test_redact_removesIPAddresses() {
        let redactor = DataRedactor()
        let input = "Connected from 192.168.1.100"
        
        let result = redactor.redact(input)
        
        XCTAssertFalse(result.redactedText.contains("192.168.1.100"))
        XCTAssertTrue(result.redactedText.contains("[IP_REDACTED]"))
        XCTAssertTrue(result.redactionTypes.contains(.ipAddress))
    }
    
    func test_redact_handlesMultipleIPs() {
        let redactor = DataRedactor()
        let input = "From 10.0.0.1 to 172.16.0.1"
        
        let result = redactor.redact(input)
        
        XCTAssertEqual(result.redactedText.components(separatedBy: "[IP_REDACTED]").count - 1, 2)
    }
    
    // MARK: - Combined Redaction Tests
    
    func test_redact_handlesMultiplePIITypes() {
        let redactor = DataRedactor()
        let input = """
        User: user@test.com
        Device: 550E8400-E29B-41D4-A716-446655440000
        IP: 192.168.1.1
        """
        
        let result = redactor.redact(input)
        
        XCTAssertTrue(result.redactionTypes.contains(.email))
        XCTAssertTrue(result.redactionTypes.contains(.uuid))
        XCTAssertTrue(result.redactionTypes.contains(.ipAddress))
        XCTAssertEqual(result.redactionsApplied, 3)
    }
    
    func test_redact_withNoSensitiveData_returnsOriginal() {
        let redactor = DataRedactor()
        let input = "Just some normal text without PII"
        
        let result = redactor.redact(input)
        
        XCTAssertEqual(result.redactedText, input)
        XCTAssertEqual(result.redactionsApplied, 0)
        XCTAssertTrue(result.redactionTypes.isEmpty)
    }
    
    // MARK: - PII Detection Tests
    
    func test_containsPotentialPII_detectsEmail() {
        XCTAssertTrue(DataRedactor.containsPotentialPII("Contact: user@test.com"))
    }
    
    func test_containsPotentialPII_detectsUUID() {
        XCTAssertTrue(DataRedactor.containsPotentialPII("ID: 550E8400-E29B-41D4-A716-446655440000"))
    }
    
    func test_containsPotentialPII_detectsIP() {
        XCTAssertTrue(DataRedactor.containsPotentialPII("Server: 192.168.1.1"))
    }
    
    func test_containsPotentialPII_cleanText_returnsFalse() {
        XCTAssertFalse(DataRedactor.containsPotentialPII("No sensitive data here"))
    }
    
    // MARK: - Dictionary Redaction Tests
    
    func test_redactDictionary_redactsStringValues() {
        let dict: [String: Any] = [
            "email": "user@test.com",
            "count": 42
        ]
        
        let result = DataRedactor.redactDictionary(dict)
        
        XCTAssertEqual(result["email"] as? String, "[EMAIL_REDACTED]")
        XCTAssertEqual(result["count"] as? Int, 42)
    }
    
    func test_redactDictionary_handlesNestedDictionaries() {
        let dict: [String: Any] = [
            "user": [
                "email": "user@test.com"
            ]
        ]
        
        let result = DataRedactor.redactDictionary(dict)
        let nested = result["user"] as? [String: Any]
        
        XCTAssertEqual(nested?["email"] as? String, "[EMAIL_REDACTED]")
    }
    
    func test_redactDictionary_handlesStringArrays() {
        let dict: [String: Any] = [
            "emails": ["a@test.com", "b@test.com"]
        ]
        
        let result = DataRedactor.redactDictionary(dict)
        let emails = result["emails"] as? [String]
        
        XCTAssertEqual(emails?.count, 2)
        XCTAssertTrue(emails?.allSatisfy { $0 == "[EMAIL_REDACTED]" } ?? false)
    }
    
    // MARK: - Edge Cases
    
    func test_redact_emptyString() {
        let redactor = DataRedactor()
        let result = redactor.redact("")
        
        XCTAssertEqual(result.redactedText, "")
        XCTAssertEqual(result.redactionsApplied, 0)
    }
    
    func test_redact_preservesNewlines() {
        let redactor = DataRedactor()
        let input = "Line 1\nuser@test.com\nLine 3"
        
        let result = redactor.redact(input)
        
        XCTAssertTrue(result.redactedText.contains("\n"))
        XCTAssertEqual(result.redactedText.components(separatedBy: "\n").count, 3)
    }
    
    func test_redact_lowercaseUUID() {
        let redactor = DataRedactor()
        let input = "id: 550e8400-e29b-41d4-a716-446655440000"
        
        let result = redactor.redact(input)
        
        XCTAssertTrue(result.redactedText.contains("HASH_"))
        XCTAssertEqual(result.redactionsApplied, 1)
    }
    
    // MARK: - SSOT Compliance Tests
    
    func test_defaultConfig_followsSSOTRequirements() {
        // SSOT: "Device IDs hashed, names/emails excluded"
        let config = RedactionConfig.default
        
        XCTAssertTrue(config.hashDeviceIDs, "SSOT requires device IDs to be hashed")
        XCTAssertTrue(config.removeEmails, "SSOT requires emails to be removed")
    }
    
    func test_redaction_preservesFunctionalData() {
        // SSOT: "Relative time offsets (not exact times)" - we preserve timestamps
        // This tests that non-PII data is preserved
        let redactor = DataRedactor()
        let input = "Event at 2024-01-15T22:30:00Z with count 42"
        
        let result = redactor.redact(input)
        
        XCTAssertTrue(result.redactedText.contains("2024-01-15"))
        XCTAssertTrue(result.redactedText.contains("42"))
    }
}
