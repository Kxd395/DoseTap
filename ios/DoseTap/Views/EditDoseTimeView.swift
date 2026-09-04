import DoseCore
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
    private let maxAdjustmentMinutes: Double = 720  // ±12 hours
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
                            Text("Original: \(originalTime.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                }
                
                Section("Correct Date & Time") {
                    DatePicker(
                        "Date & Time",
                        selection: $selectedTime,
                        in: timeRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
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
                            if MedicationTiming.classify(elapsedSeconds: Double(interval) * 60) == .inWindow {
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
                    Text("Adjustments are limited to ±12 hours from the original time. Dose 2 interval constraints still apply.")
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
                Text("Change Dose \(doseNumber) from \(originalTime.formatted(date: .abbreviated, time: .shortened)) to \(selectedTime.formatted(date: .abbreviated, time: .shortened))?")
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var formattedSessionDate: String {
        // Parse session date string (YYYY-MM-DD format)
        if let date = AppFormatters.sessionDate.date(from: sessionDate) {
            return AppFormatters.weekdayMedium.string(from: date)
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

/// View for editing a sleep event time (date + time)
struct EditEventTimeView: View {
    @Environment(\.dismiss) private var dismiss
    
    let event: StoredSleepEvent
    let sessionDate: String
    let onSave: (Date) -> Void
    let onSaveNotes: ((String?) -> Void)?
    
    @State private var selectedTime: Date
    @State private var notesText: String
    @State private var showConfirmation = false
    
    init(
        event: StoredSleepEvent,
        sessionDate: String,
        onSave: @escaping (Date) -> Void,
        onSaveNotes: ((String?) -> Void)? = nil
    ) {
        self.event = event
        self.sessionDate = sessionDate
        self.onSave = onSave
        self.onSaveNotes = onSaveNotes
        _selectedTime = State(initialValue: event.timestamp)
        // Hide the system-placed "manual" marker; treat as no user notes.
        let raw = event.notes ?? ""
        _notesText = State(initialValue: raw == "manual" ? "" : raw)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Circle()
                            .fill(Color(hex: event.colorHex ?? "#888888") ?? .gray)
                            .frame(width: 12, height: 12)
                        Text(EventDisplayName.displayName(for: event.eventType))
                            .font(.headline)
                    }
                    
                    Text("Original: \(event.timestamp.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundColor(.secondary)
                }
                
                Section("Correct Date & Time") {
                    DatePicker(
                        "Date & Time",
                        selection: $selectedTime,
                        in: timeRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    
                    if adjustmentMinutes != 0 {
                        HStack {
                            Image(systemName: adjustmentMinutes > 0 ? "plus.circle" : "minus.circle")
                                .foregroundColor(.blue)
                            Text("\(abs(adjustmentMinutes)) min \(adjustmentMinutes > 0 ? "later" : "earlier")")
                        }
                    }
                }

                if onSaveNotes != nil {
                    Section("Notes") {
                        TextField(
                            "e.g. felt anxious, took with food",
                            text: $notesText,
                            axis: .vertical
                        )
                        .lineLimit(2...5)
                        .accessibilityLabel("Event notes")
                        .accessibilityHint("Add optional context about this event")

                        if notesText.count > 500 {
                            Text("Notes are limited to 500 characters")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                Section {
                    Text("Adjustments are limited to ±12 hours from the original time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(onSaveNotes != nil ? "Edit Event" : "Edit Event Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if adjustmentMinutes != 0 {
                            showConfirmation = true
                        } else {
                            saveNotesAndDismiss()
                        }
                    }
                    .disabled(!hasChanges || notesText.count > 500)
                }
            }
            .alert("Confirm Time Change", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    onSave(selectedTime)
                    saveNotesAndDismiss()
                }
            } message: {
                Text("Change \(EventDisplayName.displayName(for: event.eventType)) to \(selectedTime.formatted(date: .abbreviated, time: .shortened))?")
            }
        }
    }

    private func saveNotesAndDismiss() {
        if onSaveNotes != nil, notesChanged {
            let trimmed = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
            onSaveNotes?(trimmed.isEmpty ? nil : trimmed)
        }
        dismiss()
    }

    private var adjustmentMinutes: Int {
        Int(selectedTime.timeIntervalSince(event.timestamp) / 60)
    }

    private var notesChanged: Bool {
        let original = (event.notes == "manual" ? "" : (event.notes ?? ""))
        return notesText.trimmingCharacters(in: .whitespacesAndNewlines) != original.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        adjustmentMinutes != 0 || (onSaveNotes != nil && notesChanged)
    }
    
    /// ±12 hours from original time — covers the full sleep session window
    private var timeRange: ClosedRange<Date> {
        let window: TimeInterval = 12 * 60 * 60
        let minTime = event.timestamp.addingTimeInterval(-window)
        let maxTime = event.timestamp.addingTimeInterval(window)
        return minTime...maxTime
    }
}

// MARK: - Manual Event Log View
/// Lets the user manually log an event that wasn't captured in real time.
/// Presents a type picker and a full date+time picker.
struct ManualEventLogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = UserSettingsManager.shared

    let onSave: (String, Color, Date) -> Void  // (eventType, color, timestamp)

    @State private var selectedType: EventType?
    @State private var selectedTime = Date()
    @State private var showConfirmation = false

    /// The event types available for manual logging (quick-log sleep events only)
    private var availableTypes: [EventType] {
        settings.quickLogButtons.map { EventType($0.name) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Event Type") {
                    ForEach(availableTypes, id: \.canonicalString) { type in
                        Button {
                            selectedType = type
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.sfSymbol)
                                    .foregroundColor(type.displayColor)
                                    .frame(width: 24)
                                Text(type.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Date & Time") {
                    DatePicker(
                        "When",
                        selection: $selectedTime,
                        in: dateRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                }

                if let type = selectedType {
                    Section {
                        HStack {
                            Image(systemName: type.sfSymbol)
                                .foregroundColor(type.displayColor)
                            Text("\(type.displayName) at \(selectedTime.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                }
            }
            .navigationTitle("Log Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { showConfirmation = true }
                        .disabled(selectedType == nil)
                }
            }
            .alert("Confirm Event", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Add") {
                    guard let type = selectedType else { return }
                    onSave(type.canonicalString, type.displayColor, selectedTime)
                    dismiss()
                }
            } message: {
                if let type = selectedType {
                    Text("Log \(type.displayName) at \(selectedTime.formatted(date: .abbreviated, time: .shortened))?")
                }
            }
        }
    }

    /// Allow logging for the past 24 hours up to now
    private var dateRange: ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(-24 * 60 * 60)...now
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
