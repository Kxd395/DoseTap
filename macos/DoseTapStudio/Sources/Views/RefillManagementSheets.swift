import SwiftUI
import Foundation

/// Refill logging sheet for adding new medication refills
struct RefillLoggingSheet: View {
    @ObservedObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var bottlesReceived: String = "1"
    @State private var pickupDate = Date()
    @State private var pharmacyName: String = ""
    @State private var prescriptionNumber: String = ""
    
    private var isFormValid: Bool {
        !bottlesReceived.isEmpty && Int(bottlesReceived) != nil
    }
    
    private var newTotalBottles: Int {
        let current = dataStore.currentInventory?.bottlesRemaining ?? 0
        let received = Int(bottlesReceived) ?? 0
        return current + received
    }
    
    private var estimatedDaysRemaining: Int {
        // Assuming 1 bottle = ~14 days (approximate)
        return newTotalBottles * 14
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Log New Refill")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Record a new medication refill to update your inventory")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Refill Details")
                            .font(.headline)
                        
                        HStack {
                            Text("Medication")
                            Spacer()
                            Text("XYWAV")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Bottles received")
                            Spacer()
                            TextField("Number of bottles", text: $bottlesReceived)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                        
                        DatePicker("Pickup date", selection: $pickupDate, displayedComponents: .date)
                        
                        HStack {
                            Text("Pharmacy")
                            Spacer()
                            TextField("Pharmacy name (optional)", text: $pharmacyName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }
                        
                        HStack {
                            Text("Prescription #")
                            Spacer()
                            TextField("RX number (optional)", text: $prescriptionNumber)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 150)
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Summary")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Current inventory:")
                                Spacer()
                                Text("\(dataStore.currentInventory?.bottlesRemaining ?? 0) bottles")
                            }
                            
                            HStack {
                                Text("Adding:")
                                Spacer()
                                Text("+\(bottlesReceived) bottles")
                                    .foregroundColor(.green)
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("New total:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\(newTotalBottles) bottles (~\(estimatedDaysRemaining) days)")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button("Save Refill") {
                            saveRefill()
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        .disabled(!isFormValid)
                    }
                    .padding(.vertical, 8)
                }
                .padding()
            }
            .navigationTitle("Log Refill")
        }
        .frame(width: 500, height: 600)
    }
    
    private func saveRefill() {
        // Create a new inventory snapshot with updated values
        let bottlesAdded = Int(bottlesReceived) ?? 0
        let currentBottles = dataStore.currentInventory?.bottlesRemaining ?? 0
        let newBottles = currentBottles + bottlesAdded
        
        let newSnapshot = InventorySnapshot(
            asOfUTC: pickupDate,
            bottlesRemaining: newBottles,
            dosesRemaining: newBottles * 60, // Assuming 60 doses per bottle
            estimatedDaysLeft: estimatedDaysRemaining,
            nextRefillDate: Calendar.current.date(byAdding: .day, value: estimatedDaysRemaining - 7, to: pickupDate),
            notes: createRefillNote()
        )
        
        // In a real app, this would save to the data store
        print("📦 Would save refill: \(newSnapshot)")
        
        // For demo purposes, we could add this to the data store
        // dataStore.addInventorySnapshot(newSnapshot)
    }
    
    private func createRefillNote() -> String {
        var notes: [String] = ["Refill: +\(bottlesReceived) bottles"]
        
        if !pharmacyName.isEmpty {
            notes.append("Pharmacy: \(pharmacyName)")
        }
        
        if !prescriptionNumber.isEmpty {
            notes.append("RX#: \(prescriptionNumber)")
        }
        
        return notes.joined(separator: " | ")
    }
}

/// Pharmacy note sheet for adding pharmacy-specific information
struct PharmacyNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var category: String = "general"
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Pharmacy Notes")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Add notes about pharmacy communication or special instructions")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Note Details")
                            .font(.headline)
                        
                        TextField("Note title (optional)", text: $title)
                            .textFieldStyle(.roundedBorder)
                        
                        VStack(alignment: .leading) {
                            Text("Note")
                            TextEditor(text: $note)
                                .frame(minHeight: 100)
                                .background(Color(.textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(.separatorColor), lineWidth: 1)
                                )
                        }
                        
                        HStack {
                            Text("Category")
                            Spacer()
                            Picker("Category", selection: $category) {
                                Text("General").tag("general")
                                Text("Refill Issue").tag("refill_issue")
                                Text("Delivery Note").tag("delivery")
                                Text("Insurance").tag("insurance")
                                Text("Special Instructions").tag("special")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(12)
                    
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button("Save Note") {
                            saveNote()
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.vertical, 8)
                }
                .padding()
            }
        }
        .frame(width: 500, height: 450)
    }
    
    private func saveNote() {
        // In a real app, this would save to the data store
        print("📝 Would save pharmacy note: \(title.isEmpty ? "Untitled" : title) - \(note)")
    }
}

/// Reminder threshold sheet for setting low stock alerts
struct ReminderThresholdSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var warningThreshold: Double = 8
    @State private var criticalThreshold: Double = 3
    @State private var reorderThreshold: Double = 12
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Reminder Thresholds")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Set when to receive low inventory warnings")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Threshold Settings")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Warning threshold")
                                .fontWeight(.medium)
                            
                            HStack {
                                Text("\(Int(warningThreshold)) bottles")
                                    .foregroundColor(.orange)
                                    .font(.headline)
                                Spacer()
                                Text("~\(Int(warningThreshold * 4)) days remaining")
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $warningThreshold, in: 1...15, step: 1)
                                .accentColor(.orange)
                            
                            Text("Show warning notifications when inventory reaches this level")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(12)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Critical threshold")
                                .fontWeight(.medium)
                            
                            HStack {
                                Text("\(Int(criticalThreshold)) bottles")
                                    .foregroundColor(.red)
                                    .font(.headline)
                                Spacer()
                                Text("~\(Int(criticalThreshold * 4)) days remaining")
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $criticalThreshold, in: 1...10, step: 1)
                                .accentColor(.red)
                            
                            Text("Show urgent notifications when inventory reaches this level")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(12)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Reorder reminder")
                                .fontWeight(.medium)
                            
                            HStack {
                                Text("\(Int(reorderThreshold)) bottles")
                                    .foregroundColor(.blue)
                                    .font(.headline)
                                Spacer()
                                Text("~\(Int(reorderThreshold * 4)) days remaining")
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $reorderThreshold, in: 5...20, step: 1)
                                .accentColor(.blue)
                            
                            Text("Show reorder reminders when inventory reaches this level")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(12)
                    }
                    
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        Button("Save Settings") {
                            saveThresholds()
                            dismiss()
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                }
                .padding()
            }
        }
        .frame(width: 500, height: 550)
    }
    
    private func saveThresholds() {
        // In a real app, this would save to the data store
        print("⚙️ Would save thresholds: Warning=\(Int(warningThreshold)), Critical=\(Int(criticalThreshold)), Reorder=\(Int(reorderThreshold))")
    }
}

#Preview("Refill Logging") {
    RefillLoggingSheet(dataStore: DataStore())
}

#Preview("Pharmacy Note") {
    PharmacyNoteSheet()
}

#Preview("Reminder Threshold") {
    ReminderThresholdSheet()
}
