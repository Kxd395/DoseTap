import SwiftUI
import DoseCore

struct DaytimeEventView: View {
    @ObservedObject private var repository = SessionRepository.shared
    @State private var rows: [DaytimeEvent] = []
    @State private var adding = false
    @State private var editing: DaytimeEvent?
    @State private var failure: String?
    var body: some View {
        List {
            Text("Record an experience only when safe to pause. Struggling to stay awake and actually sleeping are separate reports.").font(.footnote)
            Button("Add daytime event") { adding = true }.disabled(failure != nil).accessibilityIdentifier("daytime-event-add")
            if let failure { Text(failure); Button("Retry loading", action: reload) }
            ForEach(rows) { row in
                Section {
                    Text(row.kind.rawValue).font(.headline)
                    Text(row.occurredAt.formatted())
                    Text("\(row.precision.rawValue) · \(row.durationSeconds.map { String(format: "%.1f minutes", $0 / 60) } ?? "Duration unknown")")
                    if !row.note.isEmpty { Text(row.note) }
                    Text("Recorded \(row.recordedAt.formatted())").font(.caption)
                    Button("Correct event description") { editing = row }
                }
            }
        }.navigationTitle("Daytime events")
            .onAppear(perform: reload)
            .sheet(isPresented: $adding, onDismiss: reload) { DaytimeEventEditor() }
            .sheet(item: $editing, onDismiss: reload) { DaytimeEventEditor(original: $0) }
    }
    private func reload() {
        do { rows = try repository.daytimeEvents().current; failure = nil }
        catch { rows = []; failure = DaytimeDiaryError.unreadable.localizedDescription }
    }
}

private struct DaytimeEventEditor: View {
    var original: DaytimeEvent? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var kind: DaytimeEvent.Kind?
    @State private var occurredAt = Date()
    @State private var precision: DaytimeEvent.Precision = .approximate
    @State private var minutes = ""
    @State private var note = ""
    @State private var reason = ""
    @State private var pending: DaytimeEvent?
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("What happened?", selection: $kind) {
                        Text("Choose an event").tag(DaytimeEvent.Kind?.none)
                        ForEach(DaytimeEvent.Kind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }.accessibilityIdentifier("daytime-event-kind")
                    if original == nil {
                        DatePicker("Occurred at", selection: $occurredAt, in: ...Date())
                        Picker("Time precision", selection: $precision) { ForEach(DaytimeEvent.Precision.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        TextField("Duration in minutes, if known", text: $minutes).keyboardType(.decimalPad)
                    }
                    TextField("Optional context / consequence (no names)", text: $note, axis: .vertical)
                    if original != nil { TextField("Correction reason", text: $reason) }
                }.disabled(pending != nil)
                if let failure { Text(failure); Button("Edit entry") { pending = nil; self.failure = nil } }
                Button(pending == nil ? "Save event" : "Retry exact event", action: save).accessibilityIdentifier("daytime-event-save")
            }.navigationTitle("Daytime event")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear { if let original { kind = original.kind; note = original.note } }
        }
    }
    private func save() {
        do {
            if pending == nil {
                guard let kind else { throw DaytimeDiaryError.invalid }
                if let original { pending = try original.corrected(kind: kind, note: note, reason: reason, recordedAt: Date()) }
                else {
                    let text = minutes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let duration = text.isEmpty ? nil : Double(text).map { $0 * 60 }
                    guard text.isEmpty || duration != nil else { throw DaytimeDiaryError.invalid }
                    pending = try DaytimeEvent(kind: kind, occurredAt: occurredAt, recordedAt: Date(), timeZoneIdentifier: TimeZone.current.identifier,
                        precision: precision, durationSeconds: duration, note: note)
                }
            }
            guard let pending else { return }
            try SessionRepository.shared.saveDaytimeEvent(pending); dismiss()
        } catch { failure = (error as? DaytimeDiaryError)?.localizedDescription ?? DaytimeDiaryError.notCommitted.localizedDescription }
    }
}
