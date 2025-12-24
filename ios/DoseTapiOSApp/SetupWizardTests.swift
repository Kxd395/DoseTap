import XCTest
@testable import DoseTapiOSApp
import DoseCore

class SetupWizardServiceTests: XCTestCase {
    var setupService: SetupWizardService!
    
    override func setUp() {
        super.setUp()
        setupService = SetupWizardService()
        
        // Clear any existing configuration
        UserDefaults.standard.removeObject(forKey: "DoseTapUserConfig")
    }
    
    override func tearDown() {
        // Clean up after each test
        UserDefaults.standard.removeObject(forKey: "DoseTapUserConfig")
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertEqual(setupService.currentStep, 1)
        XCTAssertFalse(setupService.userConfig.setupCompleted)
        XCTAssertNil(setupService.userConfig.setupCompletedAt)
    }
    
    func testCanProceed() {
        // Initially should not be able to proceed due to validation
        setupService.validateCurrentStep()
        XCTAssertFalse(setupService.canProceed)
        
        // Set valid sleep schedule
        let calendar = Calendar.current
        setupService.userConfig.sleepSchedule.usualBedtime = calendar.date(from: DateComponents(hour: 1, minute: 0)) ?? Date()
        setupService.userConfig.sleepSchedule.usualWakeTime = calendar.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.canProceed)
    }
    
    func testCanGoBack() {
        // Initially cannot go back from step 1
        XCTAssertFalse(setupService.canGoBack)
        
        // Move to step 2
        setupService.currentStep = 2
        XCTAssertTrue(setupService.canGoBack)
    }
    
    // MARK: - Sleep Schedule Validation Tests
    
    func testSleepScheduleValidation_ValidSchedule() {
        let calendar = Calendar.current
        setupService.userConfig.sleepSchedule.usualBedtime = calendar.date(from: DateComponents(hour: 1, minute: 0)) ?? Date()
        setupService.userConfig.sleepSchedule.usualWakeTime = calendar.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.validationErrors.isEmpty)
    }
    
    func testSleepScheduleValidation_TooShort() {
        let calendar = Calendar.current
        setupService.userConfig.sleepSchedule.usualBedtime = calendar.date(from: DateComponents(hour: 1, minute: 0)) ?? Date()
        setupService.userConfig.sleepSchedule.usualWakeTime = calendar.date(from: DateComponents(hour: 3, minute: 0)) ?? Date()
        
        setupService.validateCurrentStep()
        XCTAssertFalse(setupService.validationErrors.isEmpty)
        XCTAssertTrue(setupService.validationErrors.contains { $0.contains("at least 4 hours") })
    }
    
    func testSleepScheduleValidation_TooLong() {
        let calendar = Calendar.current
        setupService.userConfig.sleepSchedule.usualBedtime = calendar.date(from: DateComponents(hour: 1, minute: 0)) ?? Date()
        setupService.userConfig.sleepSchedule.usualWakeTime = calendar.date(from: DateComponents(hour: 15, minute: 0)) ?? Date()
        
        setupService.validateCurrentStep()
        XCTAssertFalse(setupService.validationErrors.isEmpty)
        XCTAssertTrue(setupService.validationErrors.contains { $0.contains("unusually long") })
    }
    
    func testSleepScheduleValidation_OvernightSleep() {
        let calendar = Calendar.current
        setupService.userConfig.sleepSchedule.usualBedtime = calendar.date(from: DateComponents(hour: 23, minute: 0)) ?? Date()
        setupService.userConfig.sleepSchedule.usualWakeTime = calendar.date(from: DateComponents(hour: 6, minute: 30)) ?? Date()
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.validationErrors.isEmpty) // 7.5 hours is valid
    }
    
    // MARK: - Medication Profile Validation Tests
    
    func testMedicationValidation_ValidProfile() {
        setupService.currentStep = 2
        setupService.userConfig.medicationProfile.medicationName = "XYWAV"
        setupService.userConfig.medicationProfile.doseMgDose1 = 450
        setupService.userConfig.medicationProfile.doseMgDose2 = 225
        setupService.userConfig.medicationProfile.dosesPerBottle = 60
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.validationErrors.isEmpty)
    }
    
    func testMedicationValidation_EmptyName() {
        setupService.currentStep = 2
        setupService.userConfig.medicationProfile.medicationName = ""
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.validationErrors.contains { $0.contains("Medication name is required") })
    }
    
    func testMedicationValidation_ZeroDose() {
        setupService.currentStep = 2
        setupService.userConfig.medicationProfile.doseMgDose1 = 0
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.validationErrors.contains { $0.contains("Dose 1 amount must be positive") })
    }
    
    func testMedicationValidation_Dose2LargerThanDose1() {
        setupService.currentStep = 2
        setupService.userConfig.medicationProfile.doseMgDose1 = 225
        setupService.userConfig.medicationProfile.doseMgDose2 = 450
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.validationErrors.contains { $0.contains("Warning: Dose 2 is typically smaller") })
    }
    
    // MARK: - Dose Window Validation Tests
    
    func testDoseWindowValidation_ValidTarget() {
        setupService.currentStep = 3
        setupService.userConfig.doseWindow.defaultTargetMinutes = 180
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.validationErrors.isEmpty)
    }
    
    func testDoseWindowValidation_TargetBelowMinimum() {
        setupService.currentStep = 3
        setupService.userConfig.doseWindow.defaultTargetMinutes = 140 // Below 150 minimum
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.validationErrors.contains { $0.contains("Target interval must be between") })
    }
    
    func testDoseWindowValidation_TargetAboveMaximum() {
        setupService.currentStep = 3
        setupService.userConfig.doseWindow.defaultTargetMinutes = 250 // Above 240 maximum
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.validationErrors.contains { $0.contains("Target interval must be between") })
    }
    
    func testDoseWindowValidation_TargetNearMinimum() {
        setupService.currentStep = 3
        setupService.userConfig.doseWindow.defaultTargetMinutes = 155 // Close to minimum
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.validationErrors.contains { $0.contains("Warning: Target is very close to minimum") })
    }
    
    func testDoseWindowValidation_TargetNearMaximum() {
        setupService.currentStep = 3
        setupService.userConfig.doseWindow.defaultTargetMinutes = 235 // Close to maximum
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.validationErrors.contains { $0.contains("Warning: Target is very close to maximum") })
    }
    
    // MARK: - Navigation Tests
    
    func testNextStep() {
        // Setup valid sleep schedule for step 1
        let calendar = Calendar.current
        setupService.userConfig.sleepSchedule.usualBedtime = calendar.date(from: DateComponents(hour: 1, minute: 0)) ?? Date()
        setupService.userConfig.sleepSchedule.usualWakeTime = calendar.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
        
        setupService.validateCurrentStep()
        XCTAssertTrue(setupService.canProceed)
        
        setupService.nextStep()
        XCTAssertEqual(setupService.currentStep, 2)
    }
    
    func testPreviousStep() {
        setupService.currentStep = 2
        setupService.previousStep()
        XCTAssertEqual(setupService.currentStep, 1)
    }
    
    func testCannotGoBackFromFirstStep() {
        XCTAssertEqual(setupService.currentStep, 1)
        setupService.previousStep()
        XCTAssertEqual(setupService.currentStep, 1) // Should not change
    }
    
    // MARK: - Setup Completion Tests
    
    func testCompleteSetup() {
        // Setup all valid configuration
        setupService.currentStep = 5
        
        let calendar = Calendar.current
        setupService.userConfig.sleepSchedule.usualBedtime = calendar.date(from: DateComponents(hour: 1, minute: 0)) ?? Date()
        setupService.userConfig.sleepSchedule.usualWakeTime = calendar.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
        
        setupService.userConfig.medicationProfile.medicationName = "XYWAV"
        setupService.userConfig.medicationProfile.doseMgDose1 = 450
        setupService.userConfig.medicationProfile.doseMgDose2 = 225
        
        setupService.userConfig.doseWindow.defaultTargetMinutes = 180
        
        let expectation = self.expectation(description: "Setup completion")
        
        // Override the completion to avoid async complexity in tests
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            setupService.completeSetup()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertTrue(setupService.userConfig.setupCompleted)
                XCTAssertNotNil(setupService.userConfig.setupCompletedAt)
                
                // Verify data was saved to UserDefaults
                if let data = UserDefaults.standard.data(forKey: "DoseTapUserConfig"),
                   let savedConfig = try? JSONDecoder().decode(UserConfig.self, from: data) {
                    XCTAssertTrue(savedConfig.setupCompleted)
                    XCTAssertNotNil(savedConfig.setupCompletedAt)
                }
                
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    // MARK: - UserConfig Model Tests
    
    func testUserConfigCoding() {
        let config = UserConfig()
        
        // Test encoding
        XCTAssertNoThrow(try JSONEncoder().encode(config))
        
        // Test decoding
        let data = try! JSONEncoder().encode(config)
        XCTAssertNoThrow(try JSONDecoder().decode(UserConfig.self, from: data))
        
        let decodedConfig = try! JSONDecoder().decode(UserConfig.self, from: data)
        XCTAssertEqual(config.schemaVersion, decodedConfig.schemaVersion)
        XCTAssertEqual(config.setupCompleted, decodedConfig.setupCompleted)
    }
    
    func testDoseWindowConfigConstants() {
        let config = DoseWindowConfig()
        
        // Core invariants that should never change
        XCTAssertEqual(config.minMinutes, 150)
        XCTAssertEqual(config.maxMinutes, 240)
        XCTAssertEqual(config.nearWindowThreshold, 15)
        
        // Defaults (per SSOT)
        XCTAssertEqual(config.defaultTargetMinutes, 165)
        XCTAssertEqual(config.snoozeStepMinutes, 10)
        XCTAssertEqual(config.maxSnoozes, 3)
        XCTAssertEqual(config.undoWindowSeconds, 5)  // SSOT: 5s default, range 3-10s
    }
    
    // MARK: - SSOT Compliance Tests
    
    func testUndoWindowDefault_matchesSSOT() {
        // SSOT §1 Core Invariants: "Undo window: 5 seconds"
        // SetupWizard.md contract: "default 5, range 3-10"
        let config = DoseWindowConfig()
        XCTAssertEqual(config.undoWindowSeconds, 5, "Undo window must default to 5s per SSOT")
        
        // Also verify DoseUndoManager uses same default
        XCTAssertEqual(DoseUndoManager.defaultWindowSeconds, 5.0, "DoseUndoManager must use 5s per SSOT")
    }
    
    func testMedicationConfigDefaults() {
        let config = MedicationConfig()
        
        XCTAssertEqual(config.medicationName, "XYWAV")
        XCTAssertEqual(config.doseMgDose1, 450)
        XCTAssertEqual(config.doseMgDose2, 225)
        XCTAssertEqual(config.dosesPerBottle, 60)
        XCTAssertEqual(config.bottleMgTotal, 9000)
    }
    
    func testNotificationConfigDefaults() {
        let config = NotificationConfig()
        
        XCTAssertTrue(config.autoSnoozeEnabled)
        XCTAssertEqual(config.notificationSound, "default")
        XCTAssertFalse(config.focusModeOverride)
        XCTAssertFalse(config.notificationsAuthorized)
        XCTAssertFalse(config.criticalAlertsAuthorized)
    }
    
    func testPrivacyConfigDefaults() {
        let config = PrivacyConfig()
        
        XCTAssertFalse(config.icloudSyncEnabled)
        XCTAssertEqual(config.dataRetentionDays, 365)
        XCTAssertTrue(config.analyticsEnabled)
    }
}

// MARK: - UserConfigurationManager Tests

class UserConfigurationManagerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clear any existing configuration
        UserDefaults.standard.removeObject(forKey: "DoseTapUserConfig")
    }
    
    override func tearDown() {
        // Clean up after each test
        UserDefaults.standard.removeObject(forKey: "DoseTapUserConfig")
        super.tearDown()
    }
    
    func testInitialState() {
        let manager = UserConfigurationManager()
        
        XCTAssertNil(manager.userConfig)
        XCTAssertFalse(manager.isConfigured)
    }
    
    func testSaveAndLoadConfiguration() {
        let manager = UserConfigurationManager()
        var config = UserConfig()
        config.setupCompleted = true
        config.setupCompletedAt = Date()
        config.medicationProfile.medicationName = "Test Medication"
        
        // Save configuration
        XCTAssertNoThrow(try manager.saveConfiguration(config))
        XCTAssertTrue(manager.isConfigured)
        XCTAssertNotNil(manager.userConfig)
        XCTAssertEqual(manager.userConfig?.medicationProfile.medicationName, "Test Medication")
        
        // Create new manager instance to test persistence
        let newManager = UserConfigurationManager()
        XCTAssertTrue(newManager.isConfigured)
        XCTAssertEqual(newManager.userConfig?.medicationProfile.medicationName, "Test Medication")
    }
    
    func testResetConfiguration() {
        let manager = UserConfigurationManager()
        var config = UserConfig()
        config.setupCompleted = true
        
        try! manager.saveConfiguration(config)
        XCTAssertTrue(manager.isConfigured)
        
        manager.resetConfiguration()
        XCTAssertFalse(manager.isConfigured)
        XCTAssertNil(manager.userConfig)
    }
    
    func testConfigurationAccessHelpers() {
        let manager = UserConfigurationManager()
        
        // Test defaults when no configuration exists
        XCTAssertEqual(manager.doseWindowConfig.defaultTargetMinutes, 165)
        XCTAssertEqual(manager.medicationConfig.medicationName, "XYWAV")
        XCTAssertTrue(manager.notificationConfig.autoSnoozeEnabled)
        XCTAssertFalse(manager.privacyConfig.icloudSyncEnabled)
    }
    
    func testValidateConfiguration() {
        let manager = UserConfigurationManager()
        
        // Test with no configuration
        let errors = manager.validateConfiguration()
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.contains("No configuration found"))
        
        // Test with valid configuration
        var config = UserConfig()
        config.medicationProfile.medicationName = "XYWAV"
        config.medicationProfile.doseMgDose1 = 450
        config.medicationProfile.doseMgDose2 = 225
        config.doseWindow.defaultTargetMinutes = 180
        
        try! manager.saveConfiguration(config)
        let validErrors = manager.validateConfiguration()
        XCTAssertTrue(validErrors.isEmpty)
        
        // Test with invalid configuration
        config.doseWindow.defaultTargetMinutes = 300 // Invalid - above max
        try! manager.saveConfiguration(config)
        let invalidErrors = manager.validateConfiguration()
        XCTAssertFalse(invalidErrors.isEmpty)
        XCTAssertTrue(invalidErrors.contains { $0.contains("Invalid dose window target") })
    }
}

// MARK: - Configuration Extensions Tests

class ConfigurationExtensionsTests: XCTestCase {
    
    func testUserConfigExtensions() {
        let config = UserConfig.createDefault()
        
        XCTAssertFalse(config.setupCompleted)
        XCTAssertEqual(config.schemaVersion, 1)
        
        // Test formatted times (basic format check)
        XCTAssertFalse(config.formattedBedtime.isEmpty)
        XCTAssertFalse(config.formattedWakeTime.isEmpty)
        
        // Test total dose calculation
        XCTAssertEqual(config.totalDosePerNight, 675) // 450 + 225
        
        // Test bottle duration calculation
        XCTAssertEqual(config.estimatedBottleDuration, 30) // 60 doses / 2 doses per night
    }
    
    func testDoseWindowConfigExtensions() {
        let config = DoseWindowConfig()
        
        // Test formatted target interval
        XCTAssertEqual(config.targetIntervalFormatted, "2h 45m") // 165 minutes
        
        // Test formatted window range
        XCTAssertEqual(config.windowRangeFormatted, "2h 30m - 4h") // 150-240 minutes
        
        // Test with exact hours
        var hourConfig = config
        hourConfig.defaultTargetMinutes = 180
        XCTAssertEqual(hourConfig.targetIntervalFormatted, "3h")
    }
    
    func testMedicationConfigExtensions() {
        let config = MedicationConfig()
        
        // Test dose ratio
        XCTAssertEqual(config.doseRatio, 0.5, accuracy: 0.01) // 225/450 = 0.5
        
        // Test typical ratio check
        XCTAssertTrue(config.isTypicalRatio) // 0.5 is within 0.4-0.6 range
        
        // Test atypical ratio
        var atypicalConfig = config
        atypicalConfig.doseMgDose2 = 100 // 100/450 = 0.22
        XCTAssertFalse(atypicalConfig.isTypicalRatio)
    }
}
