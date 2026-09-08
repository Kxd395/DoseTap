import SwiftUI
import UniformTypeIdentifiers
import DoseCore

private struct SupplyFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw SupplyStorageError.invalid }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SupplySettingsView: View {
    @ObservedObject private var service = SupplyReminderService.shared
    @State private var mode: SupplyReminderDateMode = .receivedDate
    @State private var sourceDate = Date()
    @State private var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var leadDays = 7
    @State private var exportFile = SupplyFile(data: Data())
    @State private var exporting = false
    @State private var importing = false
    @State private var fileMessage: String?
    @State private var showConfirmation = false
    @State private var pendingRestore: SupplyBackup?
    @State private var bottleToDelete: UUID?
    @State private var deletingReminder = false
    @State private var didLoadDraft = false

    private var draft: SupplyReminderEntry {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.dateComponents([.year, .month, .day], from: sourceDate)
        let time = calendar.dateComponents([.hour, .minute], from: reminderTime)
        var entry = SupplyReminderEntry(year: day.year!, month: day.month!, day: day.day!, hour: time.hour!, minute: time.minute!)
        entry.mode = mode
        entry.leadDays = leadDays
        return entry
    }

    var body: some View {
        Form {
            Section {
                Picker("Calculate from", selection: $mode) {
                    Text("Last received + 21 days").tag(SupplyReminderDateMode.receivedDate)
                    Text("Reminder date I choose").tag(SupplyReminderDateMode.reminderDate)
                    Text("Cycle end minus lead days").tag(SupplyReminderDateMode.cycleEnd)
                }
                if mode == .receivedDate {
                    DatePicker("Last received", selection: $sourceDate, in: ...Date(), displayedComponents: .date)
                } else {
                    DatePicker(mode == .cycleEnd ? "Cycle ends" : "Remind me on", selection: $sourceDate, displayedComponents: .date)
                }
                if mode == .cycleEnd { Stepper("Lead time: \(leadDays) days", value: $leadDays, in: 0...365) }
                DatePicker("Reminder time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                if let fire = draft.fireDate(in: .current) {
                    Text("Remind me: \(fire.formatted(date: .complete, time: .shortened))")
                        .accessibilityIdentifier("supplyReminderPreview")
                    if fire <= Date() { Text("This date has arrived. Choose a later reminder date to schedule an alert.") }
                } else {
                    Text("This local time does not exist. Choose another time.")
                }
                Button("Save order reminder") { Task { _ = await service.save(draft) } }
                    .accessibilityIdentifier("saveSupplyReminder")
                    .disabled(service.isBusy || (draft.fireDate(in: .current).map { $0 <= Date() } ?? true))
            } header: { Text("Order reminder") } footer: {
                Text("Entered by you. Last received adds 21 calendar days. The time follows your device timezone. Uses a standard iOS notification, subject to your sound and Focus settings. DoseTap does not place an order.")
            }

            Section("Saved reminder status") {
                Text(service.status).accessibilityIdentifier("supplyReminderStatus")
                if service.isBusy { ProgressView("Checking…") }
                if service.backup?.reminder != nil {
                    Button("Retry scheduling") { Task { await service.reconcile(requestPermission: true) } }
                    if service.needsSettings {
                        Button("Open notification settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    Button("Mark handled") { Task { await service.setHandledOrDisabled(handled: true) } }
                    Button("Disable reminder") { Task { await service.setHandledOrDisabled(handled: false) } }
                    Button("Delete reminder and its history", role: .destructive) {
                        deletingReminder = true; showConfirmation = true
                    }
                    Text("Handled means you acknowledged this reminder. It does not confirm an order. To reschedule or re-enable, choose a date above and save.")
                        .font(.footnote)
                }
            }.disabled(service.isBusy)

            Section("Bottle openings — optional") {
                SupplyBottleButton()
                if let records = service.backup?.bottleStarts, !records.isEmpty {
                    ForEach(records.sorted { $0.openedAt > $1.openedAt }) { record in
                        VStack(alignment: .leading) {
                            Text("Started: \(record.openedAt.formatted(date: .abbreviated, time: .shortened))")
                            Button("Delete this bottle record", role: .destructive) {
                                bottleToDelete = record.id; showConfirmation = true
                            }.font(.footnote)
                        }
                    }
                } else { Text("No bottle openings recorded.") }
                Text("Bottle openings do not change your reminder, supply counts, or dose records.").font(.footnote)
            }.disabled(service.isBusy)

            if let history = service.backup?.reminder?.history, !history.isEmpty {
                Section("Previous reminder entries") {
                    ForEach(history.reversed(), id: \.revision) { entry in
                        VStack(alignment: .leading) {
                            Text("\(entry.year.description)-\(entry.month)-\(entry.day), \(entry.hour):\(String(format: "%02d", entry.minute))")
                            Text("\(entry.mode == .receivedDate ? "Last received + 21 days" : entry.mode == .cycleEnd ? "Cycle end − \(entry.leadDays) days" : "Direct reminder date") · \(entry.source)")
                            Text(entry.changedAt.formatted(date: .abbreviated, time: .shortened))
                        }.font(.footnote)
                    }
                }
            }
            Section("Supply backup") {
                Button("Export supply records") {
                    do {
                        exportFile = SupplyFile(data: try JSONEncoder().encode(service.backup ?? SupplyBackup()))
                        exporting = true
                    } catch { fileMessage = error.localizedDescription }
                }.disabled(service.backup == nil)
                Button("Restore supply records…") { importing = true }
                Text("Includes the reminder, previous entries, and bottle openings. Restore replaces these supply records only. Keep exported files private.").font(.footnote)
                if let fileMessage { Text(fileMessage) }
            }.disabled(service.isBusy)
        }
        .navigationTitle("Supply & reminders")
        .task {
            await service.reconcile()
            if service.backup != nil && !didLoadDraft { loadDraft(); didLoadDraft = true }
        }
        .onChange(of: service.backup) { value in
            if value != nil && !didLoadDraft { loadDraft(); didLoadDraft = true }
        }
        .fileExporter(isPresented: $exporting, document: exportFile, contentType: .json, defaultFilename: "DoseTap-supply") { result in
            if case .failure(let error) = result { fileMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let value = try SupplyBackupFileCodec.decode(contentsOf: url)
                pendingRestore = value; showConfirmation = true
            } catch { fileMessage = "Restore failed: \(error.localizedDescription)" }
        }
        .confirmationDialog("Confirm supply change", isPresented: $showConfirmation, titleVisibility: .visible) {
            if let restored = pendingRestore {
                Button("Replace supply records", role: .destructive) {
                    Task { if await service.change(requestPermission: true, { $0 = restored }) { loadDraft() } }
                }
            } else if let id = bottleToDelete {
                Button("Delete bottle record", role: .destructive) {
                    Task { await service.change { $0.bottleStarts.removeAll { $0.id == id } } }
                }
            } else if deletingReminder {
                Button("Delete reminder", role: .destructive) { Task { await service.change { $0.reminder = nil } } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Medication and sleep history will be preserved.") }
        .onChange(of: showConfirmation) { shown in
            if !shown { pendingRestore = nil; bottleToDelete = nil; deletingReminder = false }
        }
    }

    private func loadDraft() {
        guard let entry = service.backup?.reminder?.current else { return }
        mode = entry.mode; leadDays = entry.leadDays
        let calendar = Calendar(identifier: .gregorian)
        sourceDate = calendar.date(from: DateComponents(year: entry.year, month: entry.month, day: entry.day, hour: 12)) ?? sourceDate
        reminderTime = calendar.date(bySettingHour: entry.hour, minute: entry.minute, second: 0, of: Date()) ?? reminderTime
    }
}

struct PreSleepBottleSection: View {
    @ObservedObject private var service = SupplyReminderService.shared

    var body: some View {
        QuestionSection(title: "Started a new bottle?", icon: "drop.fill") {
            SupplyBottleButton(accessibilityID: "preSleepStartedNewBottle")
                .buttonStyle(.bordered)
            if let latest = service.backup?.bottleStarts.max(by: { $0.openedAt < $1.openedAt }) {
                Text("Last recorded opening: \(latest.openedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .accessibilityIdentifier("preSleepLastBottleOpening")
            }
            Text("Optional. Saved when you confirm, even if you skip this check. Your reorder date stays the same.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SupplyBottleButton: View {
    var accessibilityID = "startedNewBottle"
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { Label("Started a new bottle", systemImage: "plus.circle") }
            .accessibilityIdentifier(accessibilityID)
            .sheet(isPresented: $showing) { SupplyBottleSheet() }
    }
}

private struct SupplyBottleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = SupplyReminderService.shared
    @State private var openedAt = Date()
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Started on", selection: $openedAt, in: ...Date())
                Text("Optional personal record. This does not log a dose or change the reorder reminder.")
                Button("Record bottle start") {
                    Task { if await service.recordBottleStart(at: openedAt) { dismiss() } }
                }.disabled(service.isBusy)
                if service.status.hasPrefix("Failed:") { Text(service.status) }
            }
            .navigationTitle("New bottle")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.interactiveDismissDisabled(service.isBusy)
    }
}
