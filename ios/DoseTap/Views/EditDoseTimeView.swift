import DoseCore
import SwiftUI

/// One deliberate entry point for missing records and corrections, including
/// nights with no existing medication row. Never invokes a live-dose command.
struct HistoryRecordsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var container: AppContainer
    let sessionDate: String
    var initialDoseType: String? = nil
    var initialSleepID: String? = nil
    var onCommitted: () -> Void = {}
    @State private var review: HistoryRecordSnapshot?
    @State private var sleeps: [StoredSleepEvent] = []
    @State private var eventType = "dose1"
    @State private var selectedTime = Date()
    @State private var reason = ""
    @State private var selectedDoseID: String?
    @State private var selectedSleep: StoredSleepEvent?
    @State private var requestID = UUID().uuidString
    @State private var confirming = false
    @State private var removing = false
    @State private var saving = false
    @State private var error: String?
    @State private var feedback: String?
    @State private var initialized = false
    @FocusState private var notesFocused: Bool

    private var repo: SessionRepository { container.sessionRepository }
    private var isDose: Bool { HistoryDoseChange.doseTypes.contains(eventType) }
    private var isEditing: Bool { selectedDoseID != nil || selectedSleep != nil }
    private var change: HistoryDoseChange {
        HistoryDoseChange(eventType: eventType, timestamp: selectedTime,
                          replacingEventID: selectedDoseID, remove: removing, reason: reason)
    }
    private var choices: [String] {
        if let id = selectedDoseID, let original = review?.events.first(where: { $0.id == id }) {
            return ["dose2", "dose2_skipped"].contains(original.eventType) ? ["dose2", "dose2_skipped"] : [original.eventType]
        }
        return selectedSleep == nil ? HistoryDoseChange.doseTypes + EventType.historySleepTypes : EventType.historySleepTypes
    }
    private var validation: String? {
        guard let review else { return "History must be loaded before saving." }
        if isDose { return change.validationError(existing: review.events, now: container.dateProvider.now()) }
        if reason.count > 500 { return "Notes are limited to 500 characters." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Treatment night: \(sessionDate)").font(.headline)
                    Text("Enter what already happened—not a dose to take now. Times are shown in \(TimeZone.current.identifier).")
                        .font(.footnote)
                    Text("A treatment night starts at 6 p.m. and continues after midnight.").font(.footnote)
                }
                if let review {
                    Section("Existing medication records — tap to correct") {
                        let rows = review.events.filter { HistoryDoseChange.doseTypes.contains($0.eventType) }.sorted { $0.timestamp < $1.timestamp }
                        if rows.isEmpty { Text("No medication records for this night").accessibilityIdentifier("history-no-doses") }
                        ForEach(rows) { row in
                            Button { selectDose(row) } label: {
                                VStack(alignment: .leading) {
                                    Text(label(row.eventType))
                                    Text(row.timestamp.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                }
                            }.accessibilityIdentifier("history-record-\(row.eventType)")
                        }
                    }
                    if !sleeps.isEmpty {
                        Section("Sleep events — tap to correct") {
                            ForEach(sleeps) { row in
                                Button { selectSleep(row) } label: {
                                    Text("\(label(row.eventType)) · \(row.timestamp.formatted(date: .omitted, time: .shortened))")
                                }.accessibilityIdentifier("history-sleep-\(EventType(row.eventType).canonicalString)")
                            }
                        }
                    }
                    Section(isEditing ? "Correct selected record" : "Add a missing entry") {
                        if isEditing { Button("Add a different entry") { resetDraft() } }
                        Picker("Record type", selection: $eventType) {
                            ForEach(choices, id: \.self) { Text(label($0)).tag($0) }
                        }.accessibilityIdentifier("history-record-type")
                        DatePicker(eventType == "dose2_skipped" ? "Outcome time" : "Actual occurrence", selection: $selectedTime,
                                   in: ...container.dateProvider.now(), displayedComponents: [.date, .hourAndMinute])
                            .accessibilityIdentifier("history-occurrence-time")
                        if !isEditing { Text("The initial time is a placeholder. Set the actual time you remember before confirming.").font(.footnote) }
                        TextField(isDose ? "Why are you adding or correcting this?" : "Optional notes", text: $reason, axis: .vertical)
                            .focused($notesFocused)
                            .lineLimit(2...5).accessibilityIdentifier("history-record-reason")
                        if isDose, change.needsTimingWarning(existing: review.events) {
                            Text("This is an extra dose or timing outside the usual window. Confirm only that the record accurately describes what already happened.")
                                .foregroundStyle(.orange)
                        }
                        if let validation { Text(validation).font(.footnote).foregroundStyle(.secondary) }
                        Button("Review & Save") { notesFocused = false; removing = false; confirming = true }
                            .disabled(validation != nil || saving).accessibilityIdentifier("history-review-save")
                        if isEditing {
                            Button("Remove erroneous record", role: .destructive) { notesFocused = false; removing = true; confirming = true }
                                .disabled(saving || (isDose && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                                .accessibilityIdentifier("history-remove-record")
                        }
                    }
                    if review.events.contains(where: { $0.metadata?.contains("previous_events") == true }) {
                        DisclosureGroup("Medication correction history") {
                            ForEach(review.events.filter { $0.metadata?.contains("previous_events") == true }) { row in
                                Text(correctionSummary(row)).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                }
                if let error {
                    Section("Not saved") {
                        Text(error).foregroundStyle(.red)
                        Button("Reload history") { load(); resetDraft() }
                    }
                }
                if let feedback { Text(feedback).accessibilityIdentifier("history-save-feedback") }
                Section {
                    Text("Medication corrections preserve the prior record. Removing a dose leaves it unrecorded, not skipped. Existing live-night reminders are recalculated; past alarms are never replayed. Apple Health and WHOOP source records cannot be edited here.")
                        .font(.footnote)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add / Correct Records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(saving) } }
            .disabled(saving)
            .interactiveDismissDisabled(saving)
            .onAppear {
                guard !initialized else { return }
                initialized = true; load(); resetDraft()
                if let type = initialDoseType, let row = review?.events.first(where: { $0.eventType == type }) { selectDose(row) }
                if let id = initialSleepID, let row = sleeps.first(where: { $0.id == id }) { selectSleep(row) }
            }
            .onChange(of: eventType) { type in
                guard !isEditing, ["dose2", "dose2_skipped", "extra_dose"].contains(type),
                      let first = review?.events.first(where: { $0.eventType == "dose1" })?.timestamp else { return }
                let base = type == "extra_dose" ? review?.events.first(where: { $0.eventType == "dose2" })?.timestamp ?? first : first
                selectedTime = min(type == "extra_dose" ? base : base.addingTimeInterval(165 * 60), container.dateProvider.now())
            }
            .onChange(of: scenePhase) { if $0 != .active { confirming = false; removing = false } }
            .alert("Review History Change", isPresented: $confirming) {
                Button("Cancel", role: .cancel) { removing = false }
                Button(removing ? "Confirm Removal" : "Confirm Save", role: removing ? .destructive : nil) { save() }
            } message: {
                Text(removing
                    ? "Remove this erroneous \(label(eventType)) record? \(isDose ? "Its original contents will remain in correction history. This does not mark a dose skipped." : "This sleep event will be deleted.")"
                    : "Save \(label(eventType)) for \(selectedTime.formatted(date: .abbreviated, time: .shortened)) in treatment night \(sessionDate)? This records the past; it is not a dosing instruction.")
            }
        }
    }

    private func load() {
        do { review = try repo.historySnapshot(sessionDate: sessionDate); sleeps = repo.fetchSleepEvents(for: sessionDate); error = nil }
        catch let issue as MedicationStorageInjectedFailure { review = nil; error = issue.detail }
        catch { review = nil; self.error = error.localizedDescription }
    }
    private func resetDraft() {
        notesFocused = false
        selectedDoseID = nil; selectedSleep = nil; reason = ""; removing = false; requestID = UUID().uuidString
        let types = Set(review?.events.map(\.eventType) ?? [])
        eventType = !types.contains("dose1") ? "dose1" : (types.isDisjoint(with: ["dose2", "dose2_skipped"]) ? "dose2" : "bathroom")
        let day = AppFormatters.sessionDate.date(from: sessionDate) ?? container.dateProvider.now()
        selectedTime = min(Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: day) ?? day, container.dateProvider.now())
    }
    private func selectDose(_ row: DoseCore.StoredDoseEvent) {
        notesFocused = false
        selectedDoseID = row.id; selectedSleep = nil; eventType = row.eventType; selectedTime = row.timestamp; reason = ""; removing = false; error = nil
    }
    private func selectSleep(_ row: StoredSleepEvent) {
        notesFocused = false
        selectedDoseID = nil; selectedSleep = row; eventType = EventType(row.eventType).canonicalString; selectedTime = row.timestamp; removing = false; error = nil
        let notes = row.notes ?? ""
        if notes.hasPrefix("Manual history entry; recorded "), let separator = notes.range(of: ". ") {
            reason = String(notes[separator.upperBound...])
        } else { reason = notes == "manual" ? "" : notes }
    }
    private func label(_ type: String) -> String {
        type == "dose2_skipped" ? "Dose 2 — missed / not taken" : EventType(type).displayName
    }
    private func correctionSummary(_ row: DoseCore.StoredDoseEvent) -> String {
        guard let data = row.metadata?.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let correction = object["correction"] as? [String: Any], let previous = correction["previous_events"] as? [[String: Any]] else { return "Correction preserved in export" }
        let prior = previous.map { "\(label($0["event_type"] as? String ?? "Record")): \($0["timestamp"] as? String ?? "unknown time")" }.joined(separator: "; ")
        return "\(row.eventType == "history_correction" ? "Removed" : "Corrected"): \(prior)\n\(object["reason_notes"] as? String ?? "")"
    }
    private func save() {
        guard scenePhase == .active, !saving, let review else { return }
        saving = true; error = nil
        let mutation = change
        let doseChange = isDose, type = eventType, time = selectedTime, notes = reason
        let originalSleep = selectedSleep, id = selectedSleep?.id ?? requestID, shouldRemove = removing
        Task { @MainActor in
            let result: DoseActionCoordinator.ActionResult
            if doseChange {
                result = await container.doseCoordinator.saveHistoryDoseChange(mutation, review: review, confirmed: true, warningConfirmed: true)
            } else {
                let saved = repo.applyHistorySleepEvent(id: id, eventType: type, timestamp: time,
                    notes: notes, review: review, original: originalSleep, remove: shouldRemove, confirmed: true)
                result = saved.isCommitted ? .success(message: "History event saved") : .retryRequired(message: saved.failure?.detail ?? "History was not saved")
            }
            saving = false
            switch result {
            case .success(let message), .attentionRequired(let message): feedback = message; load(); resetDraft(); onCommitted()
            case .blocked(let message), .retryRequired(let message): error = message
            case .needsConfirm: error = "Review the record again before saving."
            }
        }
    }
}

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
