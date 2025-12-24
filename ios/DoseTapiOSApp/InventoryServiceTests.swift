import XCTest
@testable import DoseTapiOSApp

class InventoryServiceTests: XCTestCase {
    var inventoryService: InventoryService!
    var mockConfigManager: UserConfigurationManager!
    
    override func setUp() {
        super.setUp()
        
        // Clear any existing data
        UserDefaults.standard.removeObject(forKey: "DoseTapInventory")
        UserDefaults.standard.removeObject(forKey: "DoseTapReminders")
        UserDefaults.standard.removeObject(forKey: "DoseTapUserConfig")
        
        // Create mock configuration
        var mockConfig = UserConfig()
        mockConfig.setupCompleted = true
        mockConfig.medicationProfile.medicationName = "XYWAV"
        mockConfig.medicationProfile.doseMgDose1 = 450
        mockConfig.medicationProfile.doseMgDose2 = 225
        mockConfig.medicationProfile.dosesPerBottle = 60
        mockConfig.medicationProfile.bottleMgTotal = 9000
        
        // Save mock config
        let data = try! JSONEncoder().encode(mockConfig)
        UserDefaults.standard.set(data, forKey: "DoseTapUserConfig")
        
        // Initialize service - this will load the mock config
        inventoryService = InventoryService.shared
    }
    
    override func tearDown() {
        // Clean up
        UserDefaults.standard.removeObject(forKey: "DoseTapInventory")
        UserDefaults.standard.removeObject(forKey: "DoseTapReminders")
        UserDefaults.standard.removeObject(forKey: "DoseTapUserConfig")
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationWithConfig() {
        XCTAssertNotNil(inventoryService.currentSupply)
        
        let supply = inventoryService.currentSupply!
        XCTAssertEqual(supply.medicationName, "XYWAV")
        XCTAssertEqual(supply.totalMgPerBottle, 9000)
        XCTAssertEqual(supply.dosesPerBottle, 60)
        XCTAssertEqual(supply.mgPerDose, 675) // 450 + 225
        XCTAssertEqual(supply.currentBottles, 1)
        XCTAssertNotNil(supply.openedBottleDate)
    }
    
    func testInitializationWithoutConfig() {
        // Clear config and reinitialize
        UserDefaults.standard.removeObject(forKey: "DoseTapUserConfig")
        inventoryService = InventoryService.shared
        
        XCTAssertNil(inventoryService.currentSupply)
    }
    
    // MARK: - Supply Calculation Tests
    
    func testTotalMgRemaining() {
        let supply = inventoryService.currentSupply!
        
        // With 1 bottle and fresh opened date, should have close to full bottle
        XCTAssertGreaterThan(supply.totalMgRemaining, 8000)
        XCTAssertLessThanOrEqual(supply.totalMgRemaining, 9000)
    }
    
    func testDosesRemaining() {
        let supply = inventoryService.currentSupply!
        let expectedDoses = supply.totalMgRemaining / 675 // mgPerDose
        
        XCTAssertEqual(supply.dosesRemaining, expectedDoses)
    }
    
    func testNightsRemaining() {
        let supply = inventoryService.currentSupply!
        let expectedNights = supply.dosesRemaining / 2 // 2 doses per night
        
        XCTAssertEqual(supply.nightsRemaining, expectedNights)
    }
    
    func testMgRemainingInOpenBottle() {
        guard var supply = inventoryService.currentSupply else {
            XCTFail("No current supply")
            return
        }
        
        // Test with bottle opened today
        supply.openedBottleDate = Date()
        XCTAssertEqual(supply.mgRemainingInOpenBottle, 9000) // Full bottle
        
        // Test with bottle opened 5 days ago
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        supply.openedBottleDate = fiveDaysAgo
        let expectedRemaining = 9000 - (5 * 675) // 5 nights * 675mg per night
        XCTAssertEqual(supply.mgRemainingInOpenBottle, expectedRemaining)
        
        // Test with bottle opened long ago (should not go below 0)
        let longAgo = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        supply.openedBottleDate = longAgo
        XCTAssertEqual(supply.mgRemainingInOpenBottle, 0)
    }
    
    // MARK: - Supply Status Tests
    
    func testSupplyStatusAdequate() {
        var supply = createTestSupply()
        supply.currentBottles = 3 // Plenty of supply
        
        XCTAssertEqual(supply.supplyStatus, .adequate)
        XCTAssertFalse(supply.supplyStatus.shouldNotify)
    }
    
    func testSupplyStatusModerate() {
        var supply = createTestSupply()
        // Set to exactly 14 nights remaining (moderate threshold)
        supply.currentBottles = 1
        supply.openedBottleDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        
        // Adjust to get close to 14 nights
        let targetMg = 14 * 675 // 14 nights worth
        supply.currentBottles = Int(ceil(Double(targetMg) / Double(supply.totalMgPerBottle)))
        
        XCTAssertEqual(supply.supplyStatus, .moderate)
        XCTAssertFalse(supply.supplyStatus.shouldNotify)
    }
    
    func testSupplyStatusLow() {
        var supply = createTestSupply()
        // Set to 5 nights remaining (low threshold)
        let targetMg = 5 * 675
        supply.currentBottles = 1
        let daysAgo = (9000 - targetMg) / 675
        supply.openedBottleDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
        
        XCTAssertEqual(supply.supplyStatus, .low)
        XCTAssertTrue(supply.supplyStatus.shouldNotify)
    }
    
    func testSupplyStatusCriticalLow() {
        var supply = createTestSupply()
        // Set to 2 nights remaining (critical threshold)
        let targetMg = 2 * 675
        supply.currentBottles = 1
        let daysAgo = (9000 - targetMg) / 675
        supply.openedBottleDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
        
        XCTAssertEqual(supply.supplyStatus, .criticalLow)
        XCTAssertTrue(supply.supplyStatus.shouldNotify)
    }
    
    func testSupplyStatusOutOfStock() {
        var supply = createTestSupply()
        supply.currentBottles = 1
        // Bottle opened 20 days ago (well past depletion)
        supply.openedBottleDate = Calendar.current.date(byAdding: .day, value: -20, to: Date())
        
        XCTAssertEqual(supply.supplyStatus, .outOfStock)
        XCTAssertTrue(supply.supplyStatus.shouldNotify)
    }
    
    // MARK: - Expiration Tests
    
    func testIsExpiringSoon() {
        var supply = createTestSupply()
        
        // Not expiring soon
        supply.expirationDate = Calendar.current.date(byAdding: .month, value: 6, to: Date())
        XCTAssertFalse(supply.isExpiringSoon)
        
        // Expiring soon (within 30 days)
        supply.expirationDate = Calendar.current.date(byAdding: .day, value: 15, to: Date())
        XCTAssertTrue(supply.isExpiringSoon)
        
        // Already expired
        supply.expirationDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())
        XCTAssertTrue(supply.isExpiringSoon)
    }
    
    // MARK: - Next Refill Date Tests
    
    func testNextRefillDate() {
        let supply = createTestSupply()
        
        if supply.nightsRemaining > 7 {
            let expectedDays = supply.nightsRemaining - 7
            let expectedDate = Calendar.current.date(byAdding: .day, value: expectedDays, to: Date())
            
            XCTAssertNotNil(supply.nextRefillDate)
            
            // Compare dates within 1 day tolerance
            let timeDifference = abs(supply.nextRefillDate!.timeIntervalSince(expectedDate!))
            XCTAssertLessThan(timeDifference, 24 * 60 * 60) // Less than 1 day difference
        } else {
            // Should suggest refill immediately
            let timeDifference = abs(supply.nextRefillDate!.timeIntervalSince(Date()))
            XCTAssertLessThan(timeDifference, 60) // Less than 1 minute difference
        }
    }
    
    // MARK: - Supply Management Tests
    
    func testAddNewBottle() {
        let initialBottles = inventoryService.currentSupply?.currentBottles ?? 0
        
        inventoryService.addNewBottle()
        
        XCTAssertEqual(inventoryService.currentSupply?.currentBottles, initialBottles + 1)
        
        // Should clear low supply reminders
        XCTAssertTrue(inventoryService.activeReminders.isEmpty)
    }
    
    func testAddNewBottleWithCost() {
        let cost = 250.50
        let initialHistoryCount = inventoryService.inventoryHistory.count
        
        inventoryService.addNewBottle(cost: cost)
        
        XCTAssertEqual(inventoryService.inventoryHistory.count, initialHistoryCount + 1)
        
        // Check if analytics updated
        inventoryService.calculateAnalytics()
        XCTAssertNotNil(inventoryService.analytics)
        XCTAssertGreaterThan(inventoryService.analytics?.totalCostSpent ?? 0, 0)
    }
    
    func testOpenNewBottle() {
        inventoryService.openNewBottle()
        
        let openedDate = inventoryService.currentSupply?.openedBottleDate
        XCTAssertNotNil(openedDate)
        
        // Should be very recent (within last minute)
        let timeDifference = abs(openedDate!.timeIntervalSince(Date()))
        XCTAssertLessThan(timeDifference, 60)
    }
    
    // MARK: - Reminder Tests
    
    func testReminderCreation() {
        // Manually set low supply
        var supply = createTestSupply()
        let targetMg = 5 * 675 // 5 nights (low status)
        supply.currentBottles = 1
        let daysAgo = (9000 - targetMg) / 675
        supply.openedBottleDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())
        
        // Save the modified supply
        inventoryService.currentSupply = supply
        
        inventoryService.checkSupplyStatus()
        
        XCTAssertFalse(inventoryService.activeReminders.isEmpty)
        
        let reminder = inventoryService.activeReminders.first!
        XCTAssertEqual(reminder.supplyStatus, .low)
        XCTAssertEqual(reminder.medicationName, "XYWAV")
        XCTAssertFalse(reminder.dismissed)
    }
    
    func testReminderDismissal() {
        // Create a reminder first
        let reminder = RefillReminder(
            medicationName: "XYWAV",
            reminderDate: Date(),
            supplyStatus: .low,
            nightsRemaining: 5,
            isUrgent: false
        )
        
        inventoryService.activeReminders = [reminder]
        
        inventoryService.dismissReminder(reminder)
        
        XCTAssertTrue(inventoryService.activeReminders.isEmpty)
    }
    
    // MARK: - Analytics Tests
    
    func testAnalyticsCalculation() {
        // Add some history
        inventoryService.inventoryHistory = [
            createTestSupply(cost: 200.0),
            createTestSupply(cost: 210.0)
        ]
        
        inventoryService.calculateAnalytics()
        
        let analytics = inventoryService.analytics!
        XCTAssertEqual(analytics.totalBottlesPurchased, 3) // 2 in history + 1 current
        XCTAssertEqual(analytics.totalCostSpent, 410.0)
        XCTAssertGreaterThan(analytics.daysTracked, 0)
    }
    
    // MARK: - Export Tests
    
    func testInventoryReportGeneration() {
        let report = inventoryService.generateInventoryReport()
        
        XCTAssertTrue(report.contains("Date,Event,Medication,Bottles,Nights Remaining,Status,Cost"))
        XCTAssertTrue(report.contains("XYWAV"))
        XCTAssertTrue(report.contains("Current Supply"))
    }
    
    // MARK: - Validation Tests
    
    func testValidateSupplyData() {
        // Valid supply should have no errors
        let errors = inventoryService.validateSupplyData()
        XCTAssertTrue(errors.isEmpty)
        
        // Test with invalid data
        var supply = inventoryService.currentSupply!
        supply.currentBottles = -1 // Invalid
        inventoryService.currentSupply = supply
        
        let invalidErrors = inventoryService.validateSupplyData()
        XCTAssertFalse(invalidErrors.isEmpty)
        XCTAssertTrue(invalidErrors.contains { $0.contains("Invalid bottle count") })
    }
    
    func testValidateExpiredMedication() {
        var supply = inventoryService.currentSupply!
        supply.expirationDate = Calendar.current.date(byAdding: .day, value: -5, to: Date()) // Expired
        inventoryService.currentSupply = supply
        
        let errors = inventoryService.validateSupplyData()
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.contains { $0.contains("expired") })
    }
    
    // MARK: - Persistence Tests
    
    func testDataPersistence() {
        // Modify supply
        inventoryService.addNewBottle(cost: 150.0)
        
        // Create new service instance to test loading
        let newService = InventoryService.shared
        
        XCTAssertNotNil(newService.currentSupply)
        XCTAssertEqual(newService.inventoryHistory.count, inventoryService.inventoryHistory.count)
    }
    
    // MARK: - Helper Methods
    
    private func createTestSupply(cost: Double? = nil) -> MedicationSupply {
        return MedicationSupply(
            medicationName: "XYWAV",
            totalMgPerBottle: 9000,
            dosesPerBottle: 60,
            mgPerDose: 675,
            costPerBottle: cost,
            createdAt: Date(),
            currentBottles: 1,
            openedBottleDate: Date(),
            expirationDate: nil
        )
    }
}

// MARK: - Refill Reminder Tests

class RefillReminderTests: XCTestCase {
    
    func testReminderProperties() {
        let reminder = RefillReminder(
            medicationName: "XYWAV",
            reminderDate: Date(),
            supplyStatus: .low,
            nightsRemaining: 6,
            isUrgent: false
        )
        
        XCTAssertEqual(reminder.title, "Low Supply: 6 nights remaining")
        XCTAssertTrue(reminder.message.contains("running low"))
        XCTAssertFalse(reminder.isUrgent)
        XCTAssertFalse(reminder.dismissed)
    }
    
    func testUrgentReminder() {
        let urgentReminder = RefillReminder(
            medicationName: "XYWAV",
            reminderDate: Date(),
            supplyStatus: .criticalLow,
            nightsRemaining: 2,
            isUrgent: true
        )
        
        XCTAssertEqual(urgentReminder.title, "Critical: Only 2 nights left")
        XCTAssertTrue(urgentReminder.message.contains("Contact your pharmacy today"))
        XCTAssertTrue(urgentReminder.isUrgent)
    }
    
    func testOutOfStockReminder() {
        let outOfStockReminder = RefillReminder(
            medicationName: "XYWAV",
            reminderDate: Date(),
            supplyStatus: .outOfStock,
            nightsRemaining: 0,
            isUrgent: true
        )
        
        XCTAssertEqual(outOfStockReminder.title, "Medication Out of Stock")
        XCTAssertTrue(outOfStockReminder.message.contains("healthcare provider immediately"))
        XCTAssertTrue(outOfStockReminder.isUrgent)
    }
}

// MARK: - Supply Status Tests

class SupplyStatusTests: XCTestCase {
    
    func testStatusColors() {
        XCTAssertEqual(SupplyStatus.outOfStock.color, "red")
        XCTAssertEqual(SupplyStatus.criticalLow.color, "red")
        XCTAssertEqual(SupplyStatus.low.color, "orange")
        XCTAssertEqual(SupplyStatus.moderate.color, "yellow")
        XCTAssertEqual(SupplyStatus.adequate.color, "green")
    }
    
    func testStatusIcons() {
        XCTAssertEqual(SupplyStatus.outOfStock.icon, "exclamationmark.triangle.fill")
        XCTAssertEqual(SupplyStatus.criticalLow.icon, "exclamationmark.circle.fill")
        XCTAssertEqual(SupplyStatus.low.icon, "exclamationmark.circle")
        XCTAssertEqual(SupplyStatus.moderate.icon, "info.circle")
        XCTAssertEqual(SupplyStatus.adequate.icon, "checkmark.circle.fill")
    }
    
    func testShouldNotify() {
        XCTAssertTrue(SupplyStatus.outOfStock.shouldNotify)
        XCTAssertTrue(SupplyStatus.criticalLow.shouldNotify)
        XCTAssertTrue(SupplyStatus.low.shouldNotify)
        XCTAssertFalse(SupplyStatus.moderate.shouldNotify)
        XCTAssertFalse(SupplyStatus.adequate.shouldNotify)
    }
}

// MARK: - Inventory Analytics Tests

class InventoryAnalyticsTests: XCTestCase {
    
    func testAnalyticsCalculations() {
        let analytics = InventoryAnalytics(
            totalBottlesPurchased: 4,
            totalCostSpent: 800.0,
            averageUsagePerNight: 2.0,
            adherencePercentage: 85.0,
            daysTracked: 60
        )
        
        XCTAssertEqual(analytics.averageCostPerNight, 800.0 / 60.0, accuracy: 0.01)
        XCTAssertEqual(analytics.projectedMonthlyCost, (800.0 / 60.0) * 30, accuracy: 0.01)
    }
    
    func testAnalyticsWithZeroData() {
        let analytics = InventoryAnalytics(
            totalBottlesPurchased: 0,
            totalCostSpent: 0,
            averageUsagePerNight: 0,
            adherencePercentage: 0,
            daysTracked: 0
        )
        
        XCTAssertEqual(analytics.averageCostPerNight, 0)
        XCTAssertEqual(analytics.projectedMonthlyCost, 0)
    }
}
