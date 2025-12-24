import SwiftUI
import Charts

struct InventoryView: View {
    @StateObject private var inventoryService = InventoryService.shared
    @State private var showingAddBottleSheet = false
    @State private var showingExportSheet = false
    @State private var exportData = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Supply Status Header
                    supplyStatusHeader
                    
                    // Active Reminders
                    if !inventoryService.activeReminders.isEmpty {
                        remindersSection
                    }
                    
                    // Supply Details
                    supplyDetailsSection
                    
                    // Analytics
                    if let analytics = inventoryService.analytics {
                        analyticsSection(analytics)
                    }
                    
                    // Actions
                    actionsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export") {
                        exportData = inventoryService.generateInventoryReport()
                        showingExportSheet = true
                    }
                }
            }
            .sheet(isPresented: $showingAddBottleSheet) {
                AddBottleSheet()
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportSheet(data: exportData)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            inventoryService.checkSupplyStatus()
        }
    }
    
    // MARK: - Supply Status Header
    
    private var supplyStatusHeader: some View {
        VStack(spacing: 12) {
            if let supply = inventoryService.currentSupply {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: supply.supplyStatus.icon)
                            .foregroundColor(colorForStatus(supply.supplyStatus))
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(supply.medicationName)
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text(supply.supplyStatus.rawValue)
                                .font(.subheadline)
                                .foregroundColor(colorForStatus(supply.supplyStatus))
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(supply.nightsRemaining)")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("nights left")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Progress bar
                    ProgressView(
                        value: Double(supply.nightsRemaining),
                        total: Double(supply.nightsRemaining + 30) // Show progress based on ~30 day supply
                    )
                    .progressViewStyle(LinearProgressViewStyle())
                    .accentColor(colorForStatus(supply.supplyStatus))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            } else {
                noSupplyView
            }
        }
    }
    
    private var noSupplyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "pills.circle")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No Supply Data")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Add your first bottle to start tracking")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Add Bottle") {
                showingAddBottleSheet = true
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Reminders Section
    
    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Reminders")
                .font(.headline)
                .fontWeight(.semibold)
            
            ForEach(inventoryService.activeReminders) { reminder in
                reminderCard(reminder)
            }
        }
    }
    
    private func reminderCard(_ reminder: RefillReminder) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: reminder.isUrgent ? "exclamationmark.triangle.fill" : "bell.fill")
                .foregroundColor(reminder.isUrgent ? .red : .orange)
                .font(.title3)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(reminder.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Button("Dismiss") {
                inventoryService.dismissReminder(reminder)
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding(12)
        .background(reminder.isUrgent ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Supply Details Section
    
    private var supplyDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Supply Details")
                .font(.headline)
                .fontWeight(.semibold)
            
            if let supply = inventoryService.currentSupply {
                VStack(spacing: 12) {
                    supplyDetailRow("Current Bottles", value: "\(supply.currentBottles)")
                    supplyDetailRow("Doses Remaining", value: "\(supply.dosesRemaining)")
                    supplyDetailRow("Total mg Remaining", value: "\(supply.totalMgRemaining) mg")
                    
                    if let openedDate = supply.openedBottleDate {
                        supplyDetailRow("Current Bottle Opened", value: formatDate(openedDate))
                        supplyDetailRow("mg in Current Bottle", value: "\(supply.mgRemainingInOpenBottle) mg")
                    }
                    
                    if let expirationDate = supply.expirationDate {
                        let isExpiringSoon = supply.isExpiringSoon
                        supplyDetailRow(
                            "Expiration Date",
                            value: formatDate(expirationDate),
                            isWarning: isExpiringSoon
                        )
                    }
                    
                    if let nextRefill = supply.nextRefillDate {
                        supplyDetailRow("Suggested Refill Date", value: formatDate(nextRefill))
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
    }
    
    private func supplyDetailRow(_ title: String, value: String, isWarning: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isWarning ? .orange : .primary)
        }
    }
    
    // MARK: - Analytics Section
    
    private func analyticsSection(_ analytics: InventoryAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Usage Analytics")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                analyticsRow("Adherence Rate", value: "\(Int(analytics.adherencePercentage))%")
                analyticsRow("Days Tracked", value: "\(analytics.daysTracked)")
                analyticsRow("Bottles Purchased", value: "\(analytics.totalBottlesPurchased)")
                
                if analytics.totalCostSpent > 0 {
                    analyticsRow("Total Cost", value: "$\(analytics.totalCostSpent, specifier: "%.2f")")
                    analyticsRow("Avg Cost/Month", value: "$\(analytics.projectedMonthlyCost, specifier: "%.2f")")
                }
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
    
    private func analyticsRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            if inventoryService.currentSupply != nil {
                Button("Add New Bottle") {
                    showingAddBottleSheet = true
                }
                .buttonStyle(PrimaryButtonStyle())
                
                Button("Open New Bottle") {
                    inventoryService.openNewBottle()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func colorForStatus(_ status: SupplyStatus) -> Color {
        switch status {
        case .outOfStock, .criticalLow:
            return .red
        case .low:
            return .orange
        case .moderate:
            return .yellow
        case .adequate:
            return .green
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Add Bottle Sheet

struct AddBottleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var inventoryService = InventoryService.shared
    
    @State private var expirationDate = Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
    @State private var cost = ""
    @State private var hasExpiration = true
    @State private var hasCost = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("New Bottle Details") {
                    Toggle("Has Expiration Date", isOn: $hasExpiration)
                    
                    if hasExpiration {
                        DatePicker(
                            "Expiration Date",
                            selection: $expirationDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                    }
                    
                    Toggle("Track Cost", isOn: $hasCost)
                    
                    if hasCost {
                        HStack {
                            Text("Cost")
                            Spacer()
                            TextField("$0.00", text: $cost)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                
                Section {
                    Button("Add Bottle") {
                        let expiration = hasExpiration ? expirationDate : nil
                        let bottleCost = hasCost ? Double(cost) : nil
                        
                        inventoryService.addNewBottle(
                            expirationDate: expiration,
                            cost: bottleCost
                        )
                        
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(hasCost && cost.isEmpty)
                }
            }
            .navigationTitle("Add Bottle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Export Sheet

struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let data: String
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Inventory Report")
                    .font(.headline)
                
                Text("Your inventory data has been prepared for export. You can copy it or share it with your healthcare provider.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                ScrollView {
                    Text(data)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(8)
                }
                .frame(maxHeight: 300)
                
                VStack(spacing: 12) {
                    Button("Copy to Clipboard") {
                        UIPasteboard.general.string = data
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    
                    ShareLink("Share Report", item: data)
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Button Styles (if not already defined)

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(configuration.isPressed ? Color.blue.opacity(0.8) : Color.blue)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.blue)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

struct InventoryView_Previews: PreviewProvider {
    static var previews: some View {
        InventoryView()
    }
}
