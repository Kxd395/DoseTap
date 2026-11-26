import SwiftUI
import DoseCore

struct WorkShiftEventEditor: View {
    let document: WorkContextDocument
    let save: (WorkContextDocument) throws -> Void
    private let existing: [WorkShiftEvent]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedShift: UUID?
    @State private var stableID = UUID()
    @State private var zone = TimeZone.current.identifier
    @State private var workDate = ""
    @State private var status = WorkShiftStatus.scheduled
    @State private var attendance = false
    @State private var precision = WorkActualTimePrecision.unknown
    @State private var hasScheduledStart = false
    @State private var hasScheduledEnd = false
    @State private var hasActualStart = false
    @State private var hasActualEnd = false
    @State private var scheduledStart = Date()
    @State private var scheduledEnd = Date()
    @State private var actualStart = Date()
    @State private var actualEnd = Date()
    @State private var blockID: String?
    @State private var createdBlockID: String?
    @State private var firstShiftDate = ""
    @State private var position = ""
    @State private var blockCount = ""
    @State private var reviewed = false
    @State private var error: String?

    init(document: WorkContextDocument, save: @escaping (WorkContextDocument) throws -> Void) {
        self.document = document; self.save = save
        existing = document.latestShiftEvents(asOf: Date())
    }
    private var blocks: [String] { Set(existing.compactMap(\.blockID) + [createdBlockID].compactMap { $0 }).sorted() }
    private static func label(_ status: WorkShiftStatus) -> String {
        switch status {
        case .scheduled: return "Scheduled"
        case .worked: return "Worked"
        case .cancelled: return "Scheduled shift cancelled"
        case .notWorked: return "Did not work"
        case .uncertain: return "Unknown"
        }
    }
    private func shiftLabel(_ event: WorkShiftEvent) -> String {
        let time = event.scheduledStart.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Scheduled start unknown"
        let actual = event.actualStart == nil && event.actualEnd == nil ? "Actual times unknown" : "Actual times recorded"
        return time + " • " + Self.label(event.status) + " • " + actual
    }
    private func blockLabel(_ id: String) -> String {
        let dates = Set(existing.filter { $0.blockID == id }.compactMap(\.firstShiftDate))
        return dates.count == 1 ? "First shift " + dates.first! : id == createdBlockID ? "New block — enter first date" : "Block date needs review"
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Shift record") {
                    Picker("Saved shift", selection: $selectedShift) {
                        Text("New shift").tag(Optional<UUID>.none)
                        ForEach(existing) { event in Text(shiftLabel(event)).tag(Optional(event.shiftID)) }
                    }.accessibilityIdentifier("work-shift-choose")
                    Text("\(existing.count) saved shifts. Corrections append a revision to the same shift; earlier records and captured plans remain preserved.").font(.caption)
                    TextField("Work date (YYYY-MM-DD; optional if unknown)", text: $workDate).accessibilityIdentifier("work-shift-date")
                    TextField("Timezone identifier", text: $zone).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Status", selection: $status) {
                        ForEach([WorkShiftStatus.scheduled, .worked, .cancelled, .notWorked, .uncertain], id: \.self) { value in
                            Text(Self.label(value)).tag(value)
                        }
                    }.accessibilityIdentifier("work-shift-status")
                    if status == .worked || status == .notWorked {
                        Toggle("I confirmed this attendance status", isOn: $attendance).accessibilityIdentifier("work-shift-attendance")
                    }
                    Text("A scheduled shift does not confirm attendance. Confirming attendance does not establish exact hours.").font(.caption)
                }
                Section("Scheduled times — optional") {
                    Toggle("Scheduled start is known", isOn: $hasScheduledStart)
                    if hasScheduledStart { DatePicker("Scheduled start", selection: $scheduledStart) }
                    Toggle("Scheduled end is known", isOn: $hasScheduledEnd)
                    if hasScheduledEnd { DatePicker("Scheduled end", selection: $scheduledEnd) }
                }
                Section("Actual times — optional") {
                    if status == .notWorked { Text("No actual work times will be recorded for Did not work.") }
                    else {
                        Toggle("Actual start is known", isOn: $hasActualStart).accessibilityIdentifier("work-shift-actual-start-known")
                        if hasActualStart { DatePicker("Actual start", selection: $actualStart) }
                        Toggle("Actual end is known", isOn: $hasActualEnd).accessibilityIdentifier("work-shift-actual-end-known")
                        if hasActualEnd { DatePicker("Actual end", selection: $actualEnd) }
                        Picker("Actual time precision", selection: $precision) {
                            Text("Unknown").tag(WorkActualTimePrecision.unknown)
                            Text("Approximate").tag(WorkActualTimePrecision.approximate)
                            Text("Reported to the minute").tag(WorkActualTimePrecision.reportedMinute)
                        }
                    }
                    Text("Leave missing endpoints unknown. Precise work-hour comparisons require confirmed attendance and both actual endpoints reported to the minute.").font(.caption)
                }
                Section("Optional explicit block membership") {
                    Picker("Work block", selection: Binding(get: { blockID }, set: selectBlock)) {
                        Text("Block unknown").tag(Optional<String>.none)
                        ForEach(blocks, id: \.self) { id in Text(blockLabel(id)).tag(Optional(id)) }
                    }
                    Button("Create a work block") { createdBlockID = "work-block:" + UUID().uuidString; blockID = createdBlockID; firstShiftDate = ""; position = ""; blockCount = "" }
                    if blockID != nil {
                        TextField("First-shift date (YYYY-MM-DD)", text: $firstShiftDate)
                        TextField("Position, if known", text: $position).keyboardType(.numberPad)
                        TextField("Number of shifts, if known", text: $blockCount).keyboardType(.numberPad)
                        Text("Membership and positions are explicitly reviewed. No weekday pattern or hourly cutoff assigns a block.").font(.caption)
                    }
                }
                Toggle("I reviewed these reported shift facts", isOn: $reviewed).accessibilityIdentifier("work-shift-reviewed")
                if let error { Text(error).foregroundStyle(.red) }
            }
            .environment(\.timeZone, TimeZone(identifier: zone) ?? .gmt)
            .navigationTitle("Work shift")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save shift revision", action: submit).disabled(!reviewed || ((status == .worked || status == .notWorked) && !attendance))
                }
            }
            .onChange(of: selectedShift) { id in load(id.flatMap { id in existing.first { $0.shiftID == id } }) }

        }
    }
    private func selectBlock(_ id: String?) {
        blockID = id; firstShiftDate = ""; position = ""; blockCount = ""; reviewed = false
        guard let id else { return }
        let records = existing.filter { $0.blockID == id }
        let dates = Set(records.compactMap(\.firstShiftDate)), counts = Set(records.compactMap(\.blockShiftCount))
        if dates.count == 1 { firstShiftDate = dates.first! }
        if counts.count == 1 { blockCount = String(counts.first!) }
    }
    private func load(_ event: WorkShiftEvent?) {
        stableID = event?.shiftID ?? UUID(); zone = event?.timeZoneIdentifier ?? TimeZone.current.identifier
        workDate = event?.workDate ?? ""
        status = event?.status ?? .scheduled; attendance = event?.attendanceConfirmed ?? false
        precision = event?.actualTimePrecision ?? .unknown
        hasScheduledStart = event?.scheduledStart != nil; hasScheduledEnd = event?.scheduledEnd != nil
        hasActualStart = event?.actualStart != nil; hasActualEnd = event?.actualEnd != nil
        scheduledStart = event?.scheduledStart ?? Date(); scheduledEnd = event?.scheduledEnd ?? Date()
        actualStart = event?.actualStart ?? Date(); actualEnd = event?.actualEnd ?? Date()
        blockID = event?.blockID; firstShiftDate = event?.firstShiftDate ?? ""
        position = event?.position.map(String.init) ?? ""; blockCount = event?.blockShiftCount.map(String.init) ?? ""
        reviewed = false; error = nil
    }
    private func submit() {
        guard reviewed else { return }
        let firstDate = firstShiftDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (position.isEmpty || Int(position) != nil), (blockCount.isEmpty || Int(blockCount) != nil) else {
            error = "Position and shift count must be whole numbers, or left blank."; return
        }
        if blockID != nil && WorkContextDocument.day(firstDate, zone: zone) == nil {
            error = "Enter and review this block's first-shift date and a valid timezone."; return
        }
        var event = WorkShiftEvent(timeZoneIdentifier: zone, recordedAt: Date())
        event.shiftID = stableID; event.workDate = workDate.isEmpty ? nil : workDate
        event.status = status; event.attendanceConfirmed = attendance
        event.source = .userEntered; event.actualTimePrecision = precision
        event.scheduledStart = hasScheduledStart ? scheduledStart : nil; event.scheduledEnd = hasScheduledEnd ? scheduledEnd : nil
        event.actualStart = status != .notWorked && hasActualStart ? actualStart : nil
        event.actualEnd = status != .notWorked && hasActualEnd ? actualEnd : nil
        event.blockID = blockID; event.firstShiftDate = blockID == nil ? nil : firstDate
        event.position = blockID == nil ? nil : Int(position); event.blockShiftCount = blockID == nil ? nil : Int(blockCount)
        guard event.isValid else {
            error = "Review the timezone, attendance, ordering and precision. Actual times cannot be in the future; positions must be 1–366 and within the stated block count."; return
        }
        var next = document; next.schemaVersion = 3; next.revision = UUID()
        next.shiftEvents = (document.shiftEvents ?? []) + [event]
        do { try save(next); dashboardLogger.info("Saved a reviewed work-shift revision"); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
