import SwiftUI
import DoseCore

/// One checked read of source supply plus a read-only history projection.
@MainActor
final class BottleSupplyModel: ObservableObject {
    @Published var supply: SupplyBackup?
    @Published var usage: SupplyUsageSummary?
    @Published var error: String?
    @Published var doseEvidence: [SupplyDoseEvidence]?
    var remainingMg: Int? {
        guard let supply, let bottle = supply.activeBottleStart else { return nil }
        return supply.remainingBottleMg(bottle.id)
    }
    var refillNotice: String? {
        guard let value = supply, value.activeBottleStart?.receiptID != nil,
              value.trackedUnopenedBottleCount == 0 else { return nil }
        return (usage?.recordedNights ?? 0) >= 3
            ? "Third recorded night reached: contact your pharmacy about your next supply."
            : "Last tracked bottle: plan your next supply."
    }
    private let repository: SessionRepository
    init(repository: SessionRepository? = nil) { self.repository = repository ?? .shared }
    func refresh(now: Date = Date()) {
        supply = nil; usage = nil; error = nil; doseEvidence = nil
        do {
            let value = try repository.loadSupply()
            supply = value
            if let active = value.activeBottleStart {
                usage = try repository.supplyUsage(since: active.openedAt, through: now)
            }
        } catch { self.error = "Bottle usage is unavailable. Your records have not been changed. Retry or review supply history." }
        do { doseEvidence = try repository.supplyDoseEvidence() }
        catch { self.error = "Linked-dose verification is unavailable. Your supply records were not changed. Retry before relying on allocations." }
    }
}

struct BottleSupplyCard: View {
    @StateObject private var model = BottleSupplyModel()
    @ObservedObject private var repo = SessionRepository.shared
    @State private var showing = false
    @State private var showingAmounts = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showing = true } label: {
                HStack {
                    Label("Bottle & supply", systemImage: "cross.case").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
            }.accessibilityIdentifier("manage-bottle-supply")
                .accessibilityHint("Review bottle amounts, unopened stock and bottle openings.")
            if let supply = model.supply {
                if let remaining = model.remainingMg {
                    BottleQuantityEstimate(remaining: remaining, accessibilityPrefix: "bottle-card")
                } else {
                    Text("Amount remaining: not recorded").font(.subheadline.bold())
                        .accessibilityIdentifier("bottle-card-quantity-missing")
                    Text("Set a confirmed bottle amount to see grams and 4.5 g dose equivalents. Nights since opening cannot establish the amount left.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(supply.trackedUnopenedBottleCount.map { "Unopened bottles: \($0)" } ?? "Unopened bottles: not recorded")
                    .font(.subheadline).accessibilityIdentifier("bottle-card-unopened")
                if supply.activeBottleStart != nil {
                    Button(model.remainingMg == nil ? "Set bottle amount" : "Review amounts & prepared doses") { showingAmounts = true }
                        .accessibilityIdentifier("bottle-card-amounts")
                } else {
                    Text("Record a bottle opening in Bottle & supply to start quantity tracking.").font(.caption)
                }
            }
            if model.supply?.activeBottleStart != nil {
                Text(model.usage.map { "Recorded dosing nights since opening: \($0.recordedNights)" } ?? "Dosing-night count unavailable")
                    .font(.caption).foregroundStyle(.secondary)
                if let usage = model.usage, usage.excludedRows > 0 {
                    Text("\(usage.excludedRows) dose records need review and were excluded.").font(.caption)
                }
                if let notice = model.refillNotice { Text(notice).font(.subheadline.bold()) }
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("Retry bottle information") { model.refresh() }
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .onAppear { model.refresh() }
            .onReceive(repo.sessionDidChange) { _ in model.refresh() }
            .sheet(isPresented: $showing, onDismiss: { model.refresh() }) {
                NavigationStack { BottleSupplyManagementView().toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { showing = false } }
                } }
            }
            .sheet(isPresented: $showingAmounts, onDismiss: { model.refresh() }) {
                NavigationStack { BottleQuantityView().toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { showingAmounts = false } }
                } }
            }
    }
}

private struct BottleSupplySummary: View {
    @ObservedObject var model: BottleSupplyModel
    var body: some View {
        if let value = model.supply {
            if let active = value.activeBottleStart {
                if let id = active.receiptID, let receipt = value.receipts?.first(where: { $0.id == id }),
                   let ordinal = value.currentReceiptOrdinal {
                    Text("Current bottle: \(ordinal) of \(receipt.count) added in this entry")
                        .accessibilityIdentifier("bottle-current")
                } else { Text("Current opening is unlinked. Stock-based notices are unavailable for this bottle; use a calendar reminder.") }
                Text("Opened \(active.openedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                if let usage = model.usage {
                    Text("Recorded dosing nights since opening: \(usage.recordedNights)")
                        .accessibilityIdentifier("bottle-night-count")
                    if usage.excludedRows > 0 {
                        Text("\(usage.excludedRows) dose rows need identity review and are excluded.").font(.caption)
                    }
                }
                if let notice = model.refillNotice {
                    Label(notice, systemImage: "exclamationmark.bubble")
                        .font(.subheadline.bold()).accessibilityIdentifier("bottle-refill-notice")
                }
            } else { Text("No current bottle opening recorded.") }
            if let unopened = value.trackedUnopenedBottleCount {
                Text("Tracked unopened bottles: \(unopened)").accessibilityIdentifier("bottle-unopened-count")
            } else { Text("Unopened bottle count not recorded.") }
            if let remaining = model.remainingMg { BottleQuantityEstimate(remaining: remaining, accessibilityPrefix: "bottle-summary") }
            else { Text("Doses remaining: not available — set a confirmed amount and record preparations.").font(.caption).foregroundStyle(.secondary) }
        }
        if let error = model.error {
            Text(error).foregroundStyle(.secondary)
            Button("Retry bottle information") { model.refresh() }
        }
    }
}

struct BottleSupplyManagementView: View {
    @StateObject private var model = BottleSupplyModel()
    @ObservedObject private var service = SupplyReminderService.shared
    @State private var receive = false
    @State private var start = false
    @State private var undoOpening: UUID?
    @State private var undoReceipt: UUID?
    @State private var confirmingUndo = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("Current supply") { BottleSupplySummary(model: model) }
            NavigationLink("Amounts & prepared doses") { BottleQuantityView() }
                .accessibilityIdentifier("bottle-quantities")
            Section {
                Button("Add unopened bottles") { receive = true }.accessibilityIdentifier("bottle-receive")
                Button("Start a full bottle") { start = true }.accessibilityIdentifier("bottle-start")
                    .disabled(model.supply?.trackedUnopenedBottleCount == 0)
                Text("Add only bottles still unopened. This may be the unopened portion of a delivery. Tracking begins when you next open one; an already-open bottle keeps its original unlinked history.").font(.footnote)
                Text("Starting another bottle replaces the current opening for display; it does not claim the previous bottle was empty.").font(.footnote)
                Text("Night counts describe dose records since opening, not verified consumption from this bottle. The third-night notice appears in the app. Set a separate calendar reminder in Settings for an iOS alert.").font(.footnote)
                NavigationLink("Set a calendar order reminder") { SupplySettingsView(showsBottleManagement: false) }
                    .accessibilityIdentifier("bottle-calendar-reminder")
            }.disabled(service.isBusy || model.supply == nil)
            if let value = model.supply {
                Section("Bottle openings") {
                    ForEach(value.bottleStarts.sorted { $0.openedAt > $1.openedAt }) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.openedAt.formatted(date: .abbreviated, time: .shortened))
                            Text(item.voidedAt == nil ? (item.receiptID == nil ? "Unlinked opening" : "Tracked opening") : "Voided — retained in history").font(.caption)
                            if item.id == value.activeBottleStart?.id {
                                Button("Undo this opening", role: .destructive) { undoOpening = item.id; undoReceipt = nil; confirmingUndo = true }
                            }
                        }
                    }
                }
                Section("Unopened bottles added to tracking") {
                    ForEach((value.receipts ?? []).sorted { $0.receivedAt > $1.receivedAt }) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.count) bottles · \(item.receivedAt.formatted(date: .abbreviated, time: .omitted))")
                            Text(item.voidedAt == nil ? "Unopened stock added; may be part of a delivery" : "Voided — retained in history").font(.caption)
                            if item.voidedAt == nil && !value.bottleStarts.contains(where: { $0.receiptID == item.id && $0.voidedAt == nil }) {
                                Button("Undo this receipt", role: .destructive) { undoReceipt = item.id; undoOpening = nil; confirmingUndo = true }
                            }
                        }
                    }
                }
            }
            if let message { Section { Text(message) } }
        }.navigationTitle("Bottles & supply")
            .onAppear { model.refresh() }
            .onChange(of: service.backup) { _ in model.refresh() }
            .sheet(isPresented: $receive, onDismiss: { model.refresh() }) { BottleTrackingEntrySheet(receiving: true) }
            .sheet(isPresented: $start, onDismiss: { model.refresh() }) { BottleTrackingEntrySheet(receiving: false) }
            .confirmationDialog("Undo the selected supply record?", isPresented: $confirmingUndo, titleVisibility: .visible) {
                Button("Undo supply record", role: .destructive) {
                    let opening = undoOpening, receipt = undoReceipt, time = Date()
                    Task {
                        let success = await service.change { value in
                            if let opening { try value.voidBottleStart(id: opening, at: time, now: time) }
                            if let receipt { try value.voidReceipt(id: receipt, at: time, now: time) }
                        }
                        message = success ? "Supply correction saved. Medication records were unchanged." : service.status
                        model.refresh()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("History is retained. Undoing an opening restores the preceding opening for display and returns that tracked bottle to the unopened count. This does not undo a medication dose.") }
            .disabled(service.isBusy)
    }
}

struct BottleTrackingEntrySheet: View {
    let receiving: Bool
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = SupplyReminderService.shared
    @State private var source: SupplyBackup?
    @State private var count = 3
    @State private var occurredAt = Date()
    @State private var receiptID: UUID?
    @State private var actionID = UUID()
    @State private var recordedAt: Date?
    @State private var error: String?
    private var available: [SupplyBottleReceipt] {
        (source?.receipts ?? []).filter { item in item.voidedAt == nil &&
            (source?.bottleStarts.filter { $0.receiptID == item.id && $0.voidedAt == nil }.count ?? 0) < item.count }
    }
    var body: some View {
        NavigationStack {
            Form {
                if receiving {
                    Stepper("Unopened bottles: \(count)", value: $count, in: 1...100).accessibilityIdentifier("bottle-receipt-count")
                    Text("Include only bottles still unopened, even if the delivery contained more. Use their actual received date. Already-open bottles stay unlinked and do not get stock-based notices.")
                } else {
                    if !available.isEmpty {
                        Picker("Use a bottle from", selection: $receiptID) {
                            ForEach(available) { item in
                                Text("\(item.receivedAt.formatted(date: .abbreviated, time: .omitted)) · \(item.count) received").tag(Optional(item.id))
                            }
                        }
                    } else {
                        Text("Unopened stock has not been recorded. This opening tracks this bottle's amount only; it does not assume a delivery or a number of spare bottles.")
                    }
                    Text("Start a full XYWAV bottle · 180 mL at 0.5 g/mL")
                    Text("Automatically starts at 90 g: 20 dose equivalents at 4.5 g, or 10 two-dose-night equivalents. Confirm the bottle was full when opened. Record preparations to update the remaining amount; opening a bottle does not record a dose.")
                        .accessibilityIdentifier("bottle-full-start-explanation")
                }
                DatePicker(receiving ? "Received on" : "Opened on", selection: $occurredAt, in: ...Date())
                Button(receiving ? "Save received bottles" : "Confirm full bottle start") { save() }
                    .accessibilityIdentifier("bottle-entry-save")
                    .disabled(service.isBusy || source == nil || (!receiving && receiptID == nil && source?.trackedUnopenedBottleCount != nil))
                if let error { Text(error).foregroundStyle(.secondary) }
            }.disabled(service.isBusy)
                .navigationTitle(receiving ? "Received bottles" : "Start a bottle")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(service.isBusy) } }
                .task {
                    do { source = try SessionRepository.shared.loadSupply(); receiptID = available.first?.id }
                    catch { self.error = "Supply could not be read. Close and retry; nothing was saved." }
                }
        }.interactiveDismissDisabled(service.isBusy)
            .onChange(of: occurredAt) { _ in newAttempt() }
            .onChange(of: count) { _ in newAttempt() }
            .onChange(of: receiptID) { _ in newAttempt() }
    }
    private func newAttempt() { actionID = UUID(); recordedAt = nil }
    private func save() {
        let id = actionID, captured = recordedAt ?? Date(), occurred = occurredAt, quantity = count
        let receipt = receiptID, expected = source?.activeBottleStart?.id
        recordedAt = captured
        Task {
            let success = await service.change { value in
                if receiving { try value.receiveBottles(id: id, count: quantity, receivedAt: occurred, recordedAt: captured) }
                else {
                    guard value.activeBottleStart?.id == expected || value.activeBottleStart?.id == id else { throw SupplyTrackingError.conflictingIdentity }
                    try value.startFullXYWAVBottle(id: id, receiptID: receipt, openedAt: occurred, recordedAt: captured, now: Date())
                }
            }
            if success { dismiss() } else { error = service.status }
        }
    }
}
