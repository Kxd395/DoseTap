import SwiftUI
import Foundation

/// Enhanced inventory management view with status indicators and refill logging
struct EnhancedInventoryView: View {
    @ObservedObject var dataStore: DataStore
    @State private var showingRefillSheet = false
    @State private var showingPharmacyNoteSheet = false
    @State private var showingReminderThresholdSheet = false
    
    var body: some View {
        let inventory = dataStore.currentInventory
        
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Inventory Management")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Track medication supply and manage refills")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                if let inventory = inventory {
                    // Enhanced Inventory Status Card
                    EnhancedInventoryStatusCard(
                        inventory: inventory,
                        onLogRefill: { showingRefillSheet = true },
                        onPharmacyNote: { showingPharmacyNoteSheet = true },
                        onSetReminder: { showingReminderThresholdSheet = true }
                    )
                    .padding(.horizontal)
                    
                    // Inventory History
                    InventoryHistorySection(inventorySnapshots: dataStore.inventory)
                        .padding(.horizontal)
                    
                } else {
                    // No inventory data placeholder
                    NoInventoryDataCard()
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding(.vertical)
        }
        .navigationTitle("Inventory")
        .sheet(isPresented: $showingRefillSheet) {
            RefillLoggingSheet(dataStore: dataStore)
        }
        .sheet(isPresented: $showingPharmacyNoteSheet) {
            PharmacyNoteSheet()
        }
        .sheet(isPresented: $showingReminderThresholdSheet) {
            ReminderThresholdSheet()
        }
    }
}

/// Enhanced inventory status card with detailed information and actions
struct EnhancedInventoryStatusCard: View {
    let inventory: InventorySnapshot
    let onLogRefill: () -> Void
    let onPharmacyNote: () -> Void
    let onSetReminder: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with status indicator
            HStack {
                Image(systemName: "pills.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Current Inventory")
                    .font(.headline)
                
                Spacer()
                
                InventoryStatusIndicator(inventory: inventory)
            }
            
            // Medication details
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Medication")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("XYWAV")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("On Hand")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(inventory.bottlesRemaining) bottles")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Per-night total")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("675 mg") // Calculated from typical dose
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Refill in")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let daysLeft = inventory.estimatedDaysLeft {
                            Text("\(daysLeft) days")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(getRefillUrgencyColor(daysLeft: daysLeft))
                        } else {
                            Text("Calculate needed")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Log Refill") {
                    onLogRefill()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Pharmacy Note") {
                    onPharmacyNote()
                }
                .buttonStyle(.bordered)
                
                Button("Set Reminder Threshold") {
                    onSetReminder()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func getRefillUrgencyColor(daysLeft: Int) -> Color {
        switch daysLeft {
        case 31...: return .green
        case 16...30: return .orange
        case 1...15: return .red
        default: return .red
        }
    }
}

/// Status indicator with emoji and color coding
struct InventoryStatusIndicator: View {
    let inventory: InventorySnapshot
    
    var body: some View {
        HStack {
            Text(statusEmoji)
                .font(.title2)
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var statusEmoji: String {
        guard let daysLeft = inventory.estimatedDaysLeft else { return "⚠️" }
        switch daysLeft {
        case 31...: return "🟢"
        case 16...30: return "🟡"
        case 1...15: return "🔴"
        default: return "⚠️"
        }
    }
    
    private var statusText: String {
        guard let daysLeft = inventory.estimatedDaysLeft else { return "Unknown" }
        switch daysLeft {
        case 31...: return "Good stock"
        case 16...30: return "Low stock"
        case 1...15: return "Critical"
        default: return "Empty"
        }
    }
    
    private var statusColor: Color {
        guard let daysLeft = inventory.estimatedDaysLeft else { return .orange }
        switch daysLeft {
        case 31...: return .green
        case 16...30: return .orange
        case 1...15: return .red
        default: return .red
        }
    }
}

/// Inventory history section
struct InventoryHistorySection: View {
    let inventorySnapshots: [InventorySnapshot]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inventory History")
                .font(.headline)
            
            if inventorySnapshots.isEmpty {
                Text("No inventory history available")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(inventorySnapshots.prefix(5)) { snapshot in
                        InventoryHistoryRow(snapshot: snapshot)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(12)
            }
        }
    }
}

/// Individual inventory history row
struct InventoryHistoryRow: View {
    let snapshot: InventorySnapshot
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(snapshot.asOfUTC, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(snapshot.bottlesRemaining) bottles")
                    .font(.body)
            }
            
            Spacer()
            
            if let daysLeft = snapshot.estimatedDaysLeft {
                Text("\(daysLeft) days left")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// No inventory data placeholder
struct NoInventoryDataCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pills.circle")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No Inventory Data")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Import inventory.csv data to track medication supply")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationView {
        EnhancedInventoryView(dataStore: DataStore())
    }
}
