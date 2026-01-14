import SwiftUI

/// View for editing a dose time (Dose 1 or Dose 2)
/// Respects safety constraints: ±30 min adjustment, 90-360 min interval for Dose 2
struct EditDoseTimeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    
    let doseNumber: Int  // 1 or 2
    let originalTime: Date
    let dose1Time: Date?  // Required for Dose 2 validation
    let sessionDate: String
    let onSave: (Date) -> Void
    
    @State private var selectedTime: Date
    @State private var errorMessage: String?
    @State private var showConfirmation = false
    
    // Constants from spec
    private let maxAdjustmentMinutes: Double = 30
    private let minDose2IntervalMinutes: Double = 90
    private let maxDose2IntervalMinutes: Double = 360
    
    init(doseNumber: Int, originalTime: Date, dose1Time: Date?, sessionDate: String, onSave: @escaping (Date) -> Void) {
        self.doseNumber = doseNumber
        self.originalTime = originalTime
        self.dose1Time = dose1Time
        self.sessionDate = sessionDate
        self.onSave = onSave
        _selectedTime = State(initialValue: originalTime)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Session: \(formattedSessionDate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Image(systemName: "\(doseNumber).circle.fill")
                                .foregroundColor(.green)
                            Text("Original time: \(originalTime.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                }
                
                Section("Correct Time") {
                    DatePicker(
                        "New time",
                        selection: $selectedTime,
                        in: timeRange,
                        displayedComponents: [.hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .onChange(of: selectedTime) { _ in validateTime() }
                    
                    // Show adjustment delta
                    if adjustmentMinutes != 0 {
                        HStack {
                            Image(systemName: adjustmentMinutes > 0 ? "plus.circle" : "minus.circle")
                                .foregroundColor(isValidAdjustment ? .blue : .red)
                            Text("\(abs(adjustmentMinutes)) minutes \(adjustmentMinutes > 0 ? "later" : "earlier")")
                                .foregroundColor(isValidAdjustment ? .primary : .red)
                        }
                    }
                    
                    // Show interval for Dose 2
                    if doseNumber == 2, let d1 = dose1Time {
                        let interval = Int(selectedTime.timeIntervalSince(d1) / 60)
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.purple)
                            Text("Interval: \(interval) min")
                            Spacer()
                            if interval >= 150 && interval <= 240 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else if interval >= Int(minDose2IntervalMinutes) && interval <= Int(maxDose2IntervalMinutes) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                                .font(.subheadline)
                        }
                    }
                }
                
                Section {
                    Text("Adjustments are limited to ±30 minutes from the original time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Dose \(doseNumber) Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { showConfirmation = true }
                        .disabled(!canSave)
                }
            }
            .alert("Confirm Time Change", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Save") { 
                    onSave(selectedTime)
                    dismiss()
                }
            } message: {
                Text("Change Dose \(doseNumber) time from \(originalTime.formatted(date: .omitted, time: .shortened)) to \(selectedTime.formatted(date: .omitted, time: .shortened))?")
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var formattedSessionDate: String {
        // Parse session date string (YYYY-MM-DD format)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: sessionDate) {
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
        return sessionDate
    }
    
    private var adjustmentMinutes: Int {
        Int(selectedTime.timeIntervalSince(originalTime) / 60)
    }
    
    private var isValidAdjustment: Bool {
        abs(Double(adjustmentMinutes)) <= maxAdjustmentMinutes
    }
    
    private var timeRange: ClosedRange<Date> {
        let minTime = originalTime.addingTimeInterval(-maxAdjustmentMinutes * 60)
        let maxTime = originalTime.addingTimeInterval(maxAdjustmentMinutes * 60)
        return minTime...maxTime
    }
    
    private var canSave: Bool {
        guard isValidAdjustment else { return false }
        guard adjustmentMinutes != 0 else { return false }  // No change
        
        // For Dose 2, validate interval
        if doseNumber == 2, let d1 = dose1Time {
            let interval = selectedTime.timeIntervalSince(d1) / 60
            if interval < minDose2IntervalMinutes || interval > maxDose2IntervalMinutes {
                return false
            }
        }
        
        return errorMessage == nil
    }
    
    // MARK: - Methods
    
    private func validateTime() {
        errorMessage = nil
        
        if !isValidAdjustment {
            errorMessage = "Adjustment exceeds ±30 minute limit"
            return
        }
        
        if doseNumber == 2, let d1 = dose1Time {
            let interval = selectedTime.timeIntervalSince(d1) / 60
            if interval < minDose2IntervalMinutes {
                errorMessage = "Dose 2 must be at least \(Int(minDose2IntervalMinutes)) min after Dose 1"
            } else if interval > maxDose2IntervalMinutes {
                errorMessage = "Dose 2 must be within \(Int(maxDose2IntervalMinutes)) min of Dose 1"
            }
        }
    }
}

/// View for editing a sleep event time
struct EditEventTimeView: View {
    @Environment(\.dismiss) private var dismiss
    
    let event: StoredSleepEvent
    let sessionDate: String
    let onSave: (Date) -> Void
    
    @State private var selectedTime: Date
    @State private var showConfirmation = false
    
    private let maxAdjustmentMinutes: Double = 30
    
    init(event: StoredSleepEvent, sessionDate: String, onSave: @escaping (Date) -> Void) {
        self.event = event
        self.sessionDate = sessionDate
        self.onSave = onSave
        _selectedTime = State(initialValue: event.timestamp)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Circle()
                            .fill(Color(hex: event.colorHex ?? "#888888") ?? .gray)
                            .frame(width: 12, height: 12)
                        Text(event.eventType)
                            .font(.headline)
                    }
                    
                    Text("Original: \(event.timestamp.formatted(date: .omitted, time: .shortened))")
                        .foregroundColor(.secondary)
                }
                
                Section("Correct Time") {
                    DatePicker(
                        "New time",
                        selection: $selectedTime,
                        in: timeRange,
                        displayedComponents: [.hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    
                    if adjustmentMinutes != 0 {
                        HStack {
                            Image(systemName: adjustmentMinutes > 0 ? "plus.circle" : "minus.circle")
                                .foregroundColor(.blue)
                            Text("\(abs(adjustmentMinutes)) minutes \(adjustmentMinutes > 0 ? "later" : "earlier")")
                        }
                    }
                }
                
                Section {
                    Text("Adjustments are limited to ±30 minutes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Edit Event Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { showConfirmation = true }
                        .disabled(adjustmentMinutes == 0)
                }
            }
            .alert("Confirm Time Change", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    onSave(selectedTime)
                    dismiss()
                }
            } message: {
                Text("Change \(event.eventType) time to \(selectedTime.formatted(date: .omitted, time: .shortened))?")
            }
        }
    }
    
    private var adjustmentMinutes: Int {
        Int(selectedTime.timeIntervalSince(event.timestamp) / 60)
    }
    
    private var timeRange: ClosedRange<Date> {
        let minTime = event.timestamp.addingTimeInterval(-maxAdjustmentMinutes * 60)
        let maxTime = event.timestamp.addingTimeInterval(maxAdjustmentMinutes * 60)
        return minTime...maxTime
    }
}

#if DEBUG
struct EditDoseTimeView_Previews: PreviewProvider {
    static var previews: some View {
        EditDoseTimeView(
            doseNumber: 2,
            originalTime: Date(),
            dose1Time: Date().addingTimeInterval(-180 * 60),
            sessionDate: "2026-01-10",
            onSave: { _ in }
        )
    }
}
#endif
