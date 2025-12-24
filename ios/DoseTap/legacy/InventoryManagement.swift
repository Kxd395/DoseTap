// iOS/InventoryManagement.swift
#if os(iOS)
import SwiftUI
import CoreData

// MARK: - Inventory Models

struct MedicationInventory {
    let medicationName: String
    let bottlesOnHand: Int
    let mgPerBottle: Int
    let mgPerDose1: Int
    let mgPerDose2: Int
    let estimatedDaysRemaining: Int
    let refillThresholdDays: Int
    
    var perNightTotal: Int {
        mgPerDose1 + mgPerDose2
    }
    
    var status: InventoryStatus {
        if estimatedDaysRemaining <= 0 {
            return .empty
        } else if estimatedDaysRemaining < 15 {
            return .critical
        } else if estimatedDaysRemaining <= refillThresholdDays {
            return .low
        } else {
            return .good
        }
    }
}

enum InventoryStatus {
    case good, low, critical, empty
    
    var emoji: String {
        switch self {
        case .good: return "🟢"
        case .low: return "🟡"
        case .critical: return "🔴"
        case .empty: return "⚠️"
        }
    }
    
    var description: String {
        switch self {
        case .good: return "Good stock"
        case .low: return "Low stock"
        case .critical: return "Critical"
        case .empty: return "Empty"
        }
    }
}

// MARK: - Inventory View

struct InventoryManagementView: View {
    @StateObject private var inventoryManager = InventoryManager()
    @State private var showingRefillSheet = false
    @State private var showingPharmacyNote = false
    @State private var showingThresholdSetting = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if let inventory = inventoryManager.currentInventory {
                        // Current Inventory Status
                        InventoryStatusCard(inventory: inventory)
                        
                        // Action Buttons
                        VStack(spacing: 12) {
                            Button("Log Refill") {
                                showingRefillSheet = true
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            
                            HStack(spacing: 12) {
                                Button("Pharmacy Note") {
                                    showingPharmacyNote = true
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                
                                Button("Set Reminder Threshold") {
                                    showingThresholdSetting = true
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                        .padding(.horizontal)
                        
                        // Inventory History
                        InventoryHistorySection(manager: inventoryManager)
                        
                    } else {
                        // Setup Inventory
                        InventorySetupCard {
                            inventoryManager.setupInitialInventory()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Inventory")
            .sheet(isPresented: $showingRefillSheet) {
                RefillLogSheet(manager: inventoryManager)
            }
            .sheet(isPresented: $showingPharmacyNote) {
                PharmacyNoteSheet()
            }
            .sheet(isPresented: $showingThresholdSetting) {
                ThresholdSettingSheet(manager: inventoryManager)
            }
        }
    }
}

// MARK: - Inventory Status Card

struct InventoryStatusCard: View {
    let inventory: MedicationInventory
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Inventory")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            
            // Main Info
            VStack(spacing: 8) {
                HStack {
                    Text("Medication:")
                        .foregroundColor(.secondary)
                    Text(inventory.medicationName)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("On hand:")
                        .foregroundColor(.secondary)
                    Text("\(inventory.bottlesOnHand) bottles")
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Per-night total:")
                        .foregroundColor(.secondary)
                    Text("\(inventory.perNightTotal) mg")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("Refill in:")
                        .foregroundColor(.secondary)
                    Text("\(inventory.estimatedDaysRemaining) days")
                        .fontWeight(.medium)
                }
            }
            
            // Status
            HStack {
                Text("Status:")
                    .foregroundColor(.secondary)
                HStack(spacing: 4) {
                    Text(inventory.status.emoji)
                    Text(inventory.status.description)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor(for: inventory.status))
                }
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Inventory. \(inventory.bottlesOnHand) bottles on hand. Refill in \(inventory.estimatedDaysRemaining) days.")
    }
    
    private func statusColor(for status: InventoryStatus) -> Color {
        switch status {
        case .good: return .green
        case .low: return .orange
        case .critical, .empty: return .red
        }
    }
}

// MARK: - Refill Log Sheet

struct RefillLogSheet: View {
    @ObservedObject var manager: InventoryManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var bottlesReceived = 1
    @State private var pickupDate = Date()
    @State private var pharmacyName = "Central Pharmacy"
    @State private var prescriptionNumber = ""
    
    var newTotal: Int {
        (manager.currentInventory?.bottlesOnHand ?? 0) + bottlesReceived
    }
    
    var estimatedDays: Int {
        let perNightTotal = manager.currentInventory?.perNightTotal ?? 675
        let totalMg = newTotal * (manager.currentInventory?.mgPerBottle ?? 9000)
        return totalMg / perNightTotal
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Refill Details") {
                    HStack {
                        Text("Medication")
                        Spacer()
                        Text(manager.currentInventory?.medicationName ?? "XYWAV")
                            .foregroundColor(.secondary)
                    }
                    
                    Stepper("Bottles received: \(bottlesReceived)", value: $bottlesReceived, in: 1...10)
                    
                    DatePicker("Pickup date", selection: $pickupDate, displayedComponents: .date)
                    
                    HStack {
                        Text("Pharmacy")
                        TextField("Pharmacy name", text: $pharmacyName)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("Prescription #")
                        TextField("Optional", text: $prescriptionNumber)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section("Summary") {
                    HStack {
                        Text("New total:")
                        Spacer()
                        Text("\(newTotal) bottles (~\(estimatedDays) days remaining)")
                            .fontWeight(.medium)
                    }
                }
            }
            .navigationTitle("Log New Refill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save Refill") {
                        saveRefill()
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
        .accessibilityLabel("Log new refill. Save refill.")
    }
    
    private func saveRefill() {
        manager.logRefill(
            bottlesReceived: bottlesReceived,
            pickupDate: pickupDate,
            pharmacyName: pharmacyName.isEmpty ? nil : pharmacyName,
            prescriptionNumber: prescriptionNumber.isEmpty ? nil : prescriptionNumber
        )
    }
}

// MARK: - Additional Supporting Views

struct InventorySetupCard: View {
    let onSetup: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Setup Inventory Tracking")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Track your medication inventory and get refill reminders.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Setup Inventory") {
                onSetup()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

struct InventoryHistorySection: View {
    @ObservedObject var manager: InventoryManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .padding(.horizontal)
            
            if manager.recentActivity.isEmpty {
                Text("No recent activity")
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(manager.recentActivity, id: \.id) { activity in
                    InventoryActivityRow(activity: activity)
                }
            }
        }
    }
}

struct InventoryActivityRow: View {
    let activity: InventoryActivity
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.description)
                    .fontWeight(.medium)
                Text(activity.date, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let bottles = activity.bottlesAdded {
                Text("+\(bottles)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct PharmacyNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Add a note about your pharmacy or prescription")
                    .foregroundColor(.secondary)
                
                TextEditor(text: $note)
                    .frame(minHeight: 100)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Pharmacy Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { dismiss() }
                }
            }
        }
    }
}

struct ThresholdSettingSheet: View {
    @ObservedObject var manager: InventoryManager
    @Environment(\.dismiss) private var dismiss
    @State private var thresholdDays = 10
    
    var body: some View {
        NavigationView {
            Form {
                Section("Reminder Threshold") {
                    Stepper("Remind me when \(thresholdDays) days remain", value: $thresholdDays, in: 1...30)
                }
                
                Section {
                    Text("You'll get a notification when your medication supply reaches this threshold.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Refill Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        manager.updateThreshold(days: thresholdDays)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            thresholdDays = manager.currentInventory?.refillThresholdDays ?? 10
        }
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue)
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundColor(.blue)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 1)
                    .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Inventory Manager

class InventoryManager: ObservableObject {
    @Published var currentInventory: MedicationInventory?
    @Published var recentActivity: [InventoryActivity] = []
    
    private let context = PersistentStore.shared.viewContext
    
    init() {
        loadCurrentInventory()
        loadRecentActivity()
    }
    
    func setupInitialInventory() {
        let inventory = MedicationInventory(
            medicationName: "XYWAV",
            bottlesOnHand: 2,
            mgPerBottle: 9000,
            mgPerDose1: 450,
            mgPerDose2: 225,
            estimatedDaysRemaining: 26,
            refillThresholdDays: 10
        )
        
        saveInventorySnapshot(inventory)
        currentInventory = inventory
    }
    
    func logRefill(bottlesReceived: Int, pickupDate: Date, pharmacyName: String?, prescriptionNumber: String?) {
        guard let current = currentInventory else { return }
        
        let newBottleCount = current.bottlesOnHand + bottlesReceived
        let totalMg = newBottleCount * current.mgPerBottle
        let newDaysRemaining = totalMg / current.perNightTotal
        
        let updatedInventory = MedicationInventory(
            medicationName: current.medicationName,
            bottlesOnHand: newBottleCount,
            mgPerBottle: current.mgPerBottle,
            mgPerDose1: current.mgPerDose1,
            mgPerDose2: current.mgPerDose2,
            estimatedDaysRemaining: newDaysRemaining,
            refillThresholdDays: current.refillThresholdDays
        )
        
        saveInventorySnapshot(updatedInventory)
        addActivity(description: "Refill logged: +\(bottlesReceived) bottles", bottlesAdded: bottlesReceived)
        
        currentInventory = updatedInventory
    }
    
    func updateThreshold(days: Int) {
        guard let current = currentInventory else { return }
        
        let updatedInventory = MedicationInventory(
            medicationName: current.medicationName,
            bottlesOnHand: current.bottlesOnHand,
            mgPerBottle: current.mgPerBottle,
            mgPerDose1: current.mgPerDose1,
            mgPerDose2: current.mgPerDose2,
            estimatedDaysRemaining: current.estimatedDaysRemaining,
            refillThresholdDays: days
        )
        
        saveInventorySnapshot(updatedInventory)
        currentInventory = updatedInventory
    }
    
    private func loadCurrentInventory() {
        // Load from Core Data InventorySnapshot
        let request = InventorySnapshot.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "asOfUTC", ascending: false)]
        request.fetchLimit = 1
        
        do {
            if let snapshot = try context.fetch(request).first {
                currentInventory = MedicationInventory(
                    medicationName: snapshot.medicationName ?? "XYWAV",
                    bottlesOnHand: Int(snapshot.bottlesOnHand),
                    mgPerBottle: Int(snapshot.mgPerBottle),
                    mgPerDose1: Int(snapshot.mgPerDose1),
                    mgPerDose2: Int(snapshot.mgPerDose2),
                    estimatedDaysRemaining: Int(snapshot.estimatedDaysRemaining),
                    refillThresholdDays: Int(snapshot.refillThresholdDays)
                )
            }
        } catch {
            print("Error loading inventory: \(error)")
        }
    }
    
    private func saveInventorySnapshot(_ inventory: MedicationInventory) {
        let snapshot = InventorySnapshot(context: context)
        snapshot.asOfUTC = Date()
        snapshot.medicationName = inventory.medicationName
        snapshot.bottlesOnHand = Int16(inventory.bottlesOnHand)
        snapshot.mgPerBottle = Int32(inventory.mgPerBottle)
        snapshot.mgPerDose1 = Int32(inventory.mgPerDose1)
        snapshot.mgPerDose2 = Int32(inventory.mgPerDose2)
        snapshot.estimatedDaysRemaining = Int16(inventory.estimatedDaysRemaining)
        snapshot.refillThresholdDays = Int16(inventory.refillThresholdDays)
        
        PersistentStore.shared.saveContext()
    }
    
    private func loadRecentActivity() {
        // Mock recent activity - in real implementation, load from Core Data
        recentActivity = [
            InventoryActivity(id: "1", description: "Refill logged", date: Date().addingTimeInterval(-86400 * 7), bottlesAdded: 3),
            InventoryActivity(id: "2", description: "Threshold updated", date: Date().addingTimeInterval(-86400 * 14), bottlesAdded: nil),
        ]
    }
    
    private func addActivity(description: String, bottlesAdded: Int?) {
        let activity = InventoryActivity(
            id: UUID().uuidString,
            description: description,
            date: Date(),
            bottlesAdded: bottlesAdded
        )
        recentActivity.insert(activity, at: 0)
        
        // Keep only recent 10 activities
        if recentActivity.count > 10 {
            recentActivity = Array(recentActivity.prefix(10))
        }
    }
}

// MARK: - Activity Model

struct InventoryActivity {
    let id: String
    let description: String
    let date: Date
    let bottlesAdded: Int?
}

#endif // os(iOS)
