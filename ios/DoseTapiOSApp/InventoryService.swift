import Foundation
import Combine

// MARK: - Inventory Models

struct MedicationSupply: Codable, Identifiable {
    let id = UUID()
    let medicationName: String
    let totalMgPerBottle: Int
    let dosesPerBottle: Int
    let mgPerDose: Int
    var costPerBottle: Double?
    
    var createdAt: Date
    var currentBottles: Int
    var openedBottleDate: Date?
    var expirationDate: Date?
    
    private enum CodingKeys: String, CodingKey {
        case medicationName, totalMgPerBottle, dosesPerBottle, mgPerDose, costPerBottle, createdAt, currentBottles, openedBottleDate, expirationDate
    }
    
    // Calculated properties
    var totalMgRemaining: Int {
        let closedBottleMg = (currentBottles - 1) * totalMgPerBottle
        let openedBottleMg = openedBottleDate != nil ? mgRemainingInOpenBottle : 0
        return max(0, closedBottleMg + openedBottleMg)
    }
    
    var dosesRemaining: Int {
        return totalMgRemaining / mgPerDose
    }
    
    var nightsRemaining: Int {
        // XYWAV requires 2 doses per night
        return dosesRemaining / 2
    }
    
    var mgRemainingInOpenBottle: Int {
        guard let openedDate = openedBottleDate else { return totalMgPerBottle }
        
        // Calculate days since opened
        let daysSinceOpened = DateInterval(start: openedDate, end: Date()).duration
        let nightsSinceOpened = Int(daysSinceOpened / (24 * 60 * 60))
        
        // Each night uses mgPerDose * 2 (Dose 1 + Dose 2)
        let mgUsed = nightsSinceOpened * (mgPerDose * 2)
        return max(0, totalMgPerBottle - mgUsed)
    }
    
    var supplyStatus: SupplyStatus {
        let nights = nightsRemaining
        
        if nights <= 0 {
            return .outOfStock
        } else if nights <= 3 {
            return .criticalLow
        } else if nights <= 7 {
            return .low
        } else if nights <= 14 {
            return .moderate
        } else {
            return .adequate
        }
    }
    
    var nextRefillDate: Date? {
        guard nightsRemaining > 0 else { return Date() }
        
        // Calculate when supply will run low (7 days remaining)
        let daysUntilLow = max(0, nightsRemaining - 7)
        return Calendar.current.date(byAdding: .day, value: daysUntilLow, to: Date())
    }
    
    var isExpiringSoon: Bool {
        guard let expiration = expirationDate else { return false }
        let daysUntilExpiration = DateInterval(start: Date(), end: expiration).duration
        return daysUntilExpiration <= (30 * 24 * 60 * 60) // 30 days
    }
}

enum SupplyStatus: String, CaseIterable, Codable {
    case outOfStock = "Out of Stock"
    case criticalLow = "Critical Low"
    case low = "Low"
    case moderate = "Moderate"
    case adequate = "Adequate"
    
    var color: String {
        switch self {
        case .outOfStock: return "red"
        case .criticalLow: return "red"
        case .low: return "orange"
        case .moderate: return "yellow"
        case .adequate: return "green"
        }
    }
    
    var icon: String {
        switch self {
        case .outOfStock: return "exclamationmark.triangle.fill"
        case .criticalLow: return "exclamationmark.circle.fill"
        case .low: return "exclamationmark.circle"
        case .moderate: return "info.circle"
        case .adequate: return "checkmark.circle.fill"
        }
    }
    
    var shouldNotify: Bool {
        switch self {
        case .outOfStock, .criticalLow, .low: return true
        case .moderate, .adequate: return false
        }
    }
}

struct RefillReminder: Codable, Identifiable {
    let id = UUID()
    let medicationName: String
    let reminderDate: Date
    let supplyStatus: SupplyStatus
    let nightsRemaining: Int
    let isUrgent: Bool
    var dismissed: Bool = false
    
    private enum CodingKeys: String, CodingKey {
        case medicationName, reminderDate, supplyStatus, nightsRemaining, isUrgent, dismissed
    }
    
    var title: String {
        switch supplyStatus {
        case .outOfStock:
            return "Medication Out of Stock"
        case .criticalLow:
            return "Critical: Only \(nightsRemaining) nights left"
        case .low:
            return "Low Supply: \(nightsRemaining) nights remaining"
        case .moderate:
            return "Refill Soon: \(nightsRemaining) nights remaining"
        case .adequate:
            return "Supply Check: \(nightsRemaining) nights remaining"
        }
    }
    
    var message: String {
        switch supplyStatus {
        case .outOfStock:
            return "Contact your healthcare provider immediately to refill your \(medicationName) prescription."
        case .criticalLow:
            return "You have \(nightsRemaining) nights of \(medicationName) remaining. Contact your pharmacy today."
        case .low:
            return "Your \(medicationName) supply is running low. Schedule a refill within the next few days."
        case .moderate:
            return "Consider scheduling a refill for your \(medicationName) prescription soon."
        case .adequate:
            return "Your \(medicationName) supply is adequate. Next refill due in approximately \(nightsRemaining - 7) days."
        }
    }
}

struct InventoryAnalytics: Codable {
    let totalBottlesPurchased: Int
    let totalCostSpent: Double
    let averageUsagePerNight: Double
    let adherencePercentage: Double
    let daysTracked: Int
    
    var averageCostPerNight: Double {
        guard daysTracked > 0, totalCostSpent > 0 else { return 0 }
        return totalCostSpent / Double(daysTracked)
    }
    
    var projectedMonthlyCost: Double {
        return averageCostPerNight * 30
    }
}

// MARK: - Inventory Service

@MainActor
class InventoryService: ObservableObject {
    static let shared = InventoryService()
    
    @Published var currentSupply: MedicationSupply?
    @Published var activeReminders: [RefillReminder] = []
    @Published var inventoryHistory: [MedicationSupply] = []
    @Published var analytics: InventoryAnalytics?
    @Published var lastUpdated: Date = Date()
    
    private let configManager = UserConfigurationManager.shared
    private let dataStorage = DataStorageService.shared
    
    private var cancellables = Set<AnyCancellable>()
    private let inventoryKey = "DoseTapInventory"
    private let remindersKey = "DoseTapReminders"
    
    private init() {
        loadInventoryData()
        setupDataBindings()
        calculateAnalytics()
    }
    
    // MARK: - Data Loading & Persistence
    
    private func loadInventoryData() {
        // Load current supply
        if let data = UserDefaults.standard.data(forKey: inventoryKey),
           let supply = try? JSONDecoder().decode(MedicationSupply.self, from: data) {
            currentSupply = supply
        } else {
            createInitialSupplyFromConfig()
        }
        
        // Load reminders
        if let data = UserDefaults.standard.data(forKey: remindersKey),
           let reminders = try? JSONDecoder().decode([RefillReminder].self, from: data) {
            activeReminders = reminders.filter { !$0.dismissed }
        }
    }
    
    private func saveInventoryData() {
        // Save current supply
        if let supply = currentSupply {
            if let data = try? JSONEncoder().encode(supply) {
                UserDefaults.standard.set(data, forKey: inventoryKey)
            }
        }
        
        // Save reminders
        if let data = try? JSONEncoder().encode(activeReminders) {
            UserDefaults.standard.set(data, forKey: remindersKey)
        }
        
        lastUpdated = Date()
    }
    
    private func createInitialSupplyFromConfig() {
        guard let userConfig = configManager.userConfig else { return }
        
        let medicationConfig = userConfig.medicationProfile
        let totalDosePerNight = medicationConfig.doseMgDose1 + medicationConfig.doseMgDose2
        
        currentSupply = MedicationSupply(
            medicationName: medicationConfig.medicationName,
            totalMgPerBottle: medicationConfig.bottleMgTotal,
            dosesPerBottle: medicationConfig.dosesPerBottle,
            mgPerDose: totalDosePerNight,
            costPerBottle: nil, // User can set this later
            createdAt: Date(),
            currentBottles: 1, // Assume they start with 1 bottle
            openedBottleDate: Date(), // Assume current bottle is opened
            expirationDate: nil
        )
        
        saveInventoryData()
    }
    
    private func setupDataBindings() {
        // Listen for dose events to update supply
        dataStorage.$currentSession
            .sink { [weak self] session in
                self?.updateSupplyFromDoseEvents()
            }
            .store(in: &cancellables)
        
        // Check for supply updates every hour
        Timer.publish(every: 3600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkSupplyStatus()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Supply Management
    
    func addNewBottle(expirationDate: Date? = nil, cost: Double? = nil) {
        guard var supply = currentSupply else { return }
        
        supply.currentBottles += 1
        
        if let cost = cost {
            // Add to history for analytics
            var historicalSupply = supply
            historicalSupply.costPerBottle = cost
            inventoryHistory.append(historicalSupply)
        }
        
        if let expiration = expirationDate {
            supply.expirationDate = expiration
        }
        
        currentSupply = supply
        saveInventoryData()
        
        // Remove low supply reminders since we have new stock
        activeReminders.removeAll { $0.supplyStatus.shouldNotify }
        
        calculateAnalytics()
        checkSupplyStatus()
    }
    
    func openNewBottle() {
        guard var supply = currentSupply, supply.currentBottles > 0 else { return }
        
        supply.openedBottleDate = Date()
        currentSupply = supply
        saveInventoryData()
        
        checkSupplyStatus()
    }
    
    func updateSupplyFromDoseEvents() {
        guard var supply = currentSupply else { return }
        
        // Get today's dose events
        let todayEvents = dataStorage.getTodayEvents()
        let doseEvents = todayEvents.filter { event in
            event.type == .dose1 || event.type == .dose2
        }
        
        // If we have dose events but haven't updated the opened bottle date,
        // assume the bottle was opened when first dose was taken
        if !doseEvents.isEmpty && supply.openedBottleDate == nil {
            supply.openedBottleDate = doseEvents.first?.timestamp ?? Date()
            currentSupply = supply
            saveInventoryData()
        }
        
        checkSupplyStatus()
    }
    
    func checkSupplyStatus() {
        guard let supply = currentSupply else { return }
        
        // Update current reminder if supply status changed
        let status = supply.supplyStatus
        
        // Remove outdated reminders
        activeReminders.removeAll { reminder in
            reminder.supplyStatus != status || reminder.nightsRemaining != supply.nightsRemaining
        }
        
        // Add new reminder if needed
        if status.shouldNotify {
            let reminder = RefillReminder(
                medicationName: supply.medicationName,
                reminderDate: Date(),
                supplyStatus: status,
                nightsRemaining: supply.nightsRemaining,
                isUrgent: status == .outOfStock || status == .criticalLow
            )
            
            // Only add if we don't already have one for this status
            if !activeReminders.contains(where: { $0.supplyStatus == status }) {
                activeReminders.append(reminder)
            }
        }
        
        saveInventoryData()
    }
    
    func dismissReminder(_ reminder: RefillReminder) {
        if let index = activeReminders.firstIndex(where: { $0.id == reminder.id }) {
            activeReminders[index].dismissed = true
            activeReminders.remove(at: index)
        }
        saveInventoryData()
    }
    
    // MARK: - Analytics
    
    private func calculateAnalytics() {
        let totalBottles = inventoryHistory.count + (currentSupply != nil ? 1 : 0)
        let totalCost = inventoryHistory.compactMap { $0.costPerBottle }.reduce(0, +)
        
        // Calculate usage based on dose events
        let allEvents = dataStorage.getAllEvents()
        let doseEvents = allEvents.filter { $0.type.rawValue.contains("dose") }
        let nightsWithDoses = Set(doseEvents.map { 
            Calendar.current.startOfDay(for: $0.timestamp)
        }).count
        
        let daysTracked = max(1, nightsWithDoses)
        let adherence = daysTracked > 0 ? min(100.0, Double(nightsWithDoses) / Double(daysTracked) * 100) : 0
        
        analytics = InventoryAnalytics(
            totalBottlesPurchased: totalBottles,
            totalCostSpent: totalCost,
            averageUsagePerNight: 2.0, // Always 2 doses per night for XYWAV
            adherencePercentage: adherence,
            daysTracked: daysTracked
        )
    }
    
    // MARK: - Export
    
    func generateInventoryReport() -> String {
        var csv = "Date,Event,Medication,Bottles,Nights Remaining,Status,Cost\n"
        
        // Add historical data
        for supply in inventoryHistory {
            let cost = supply.costPerBottle.map { String(format: "%.2f", $0) } ?? ""
            csv += "\(formatDate(supply.createdAt)),Bottle Added,\(supply.medicationName),\(supply.currentBottles),\(supply.nightsRemaining),\(supply.supplyStatus.rawValue),\(cost)\n"
        }
        
        // Add current supply
        if let current = currentSupply {
            csv += "\(formatDate(current.createdAt)),Current Supply,\(current.medicationName),\(current.currentBottles),\(current.nightsRemaining),\(current.supplyStatus.rawValue),\n"
        }
        
        // Add reminders
        for reminder in activeReminders {
            csv += "\(formatDate(reminder.reminderDate)),Reminder,\(reminder.medicationName),,\(reminder.nightsRemaining),\(reminder.supplyStatus.rawValue),\n"
        }
        
        return csv
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    // MARK: - Validation
    
    func validateSupplyData() -> [String] {
        var errors: [String] = []
        
        guard let supply = currentSupply else {
            errors.append("No supply data found")
            return errors
        }
        
        if supply.currentBottles < 0 {
            errors.append("Invalid bottle count: \(supply.currentBottles)")
        }
        
        if supply.nightsRemaining < 0 {
            errors.append("Invalid nights remaining calculation")
        }
        
        if let expiration = supply.expirationDate, expiration < Date() {
            errors.append("Medication has expired on \(formatDate(expiration))")
        }
        
        return errors
    }
}
