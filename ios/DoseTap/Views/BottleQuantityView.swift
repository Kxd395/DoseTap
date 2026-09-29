import SwiftUI
import DoseCore

func supplyGrams(_ mg: Int) -> String {
    (Double(mg) / 1000).formatted(.number.precision(.fractionLength(0...3))) + " g"
}

struct BottleQuantityEstimate: View {
    let remaining: Int
    var accessibilityPrefix = "bottle"
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Estimated in bottle: \(supplyGrams(remaining))").font(.headline)
                .accessibilityIdentifier("\(accessibilityPrefix)-remaining-grams")
            Text("\((Double(remaining) / Double(SupplyQuantity.referenceDoseMg)).formatted(.number.precision(.fractionLength(0...2)))) dose equivalents at 4.5 g")
                .accessibilityIdentifier("\(accessibilityPrefix)-dose-equivalents")
            Text("\((Double(remaining) / Double(SupplyQuantity.referenceDoseMg * 2)).formatted(.number.precision(.fractionLength(0...2)))) night equivalents at 4.5 g twice nightly")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct QuantityRoute: Identifiable {
    let id = UUID()
    let kind: SupplyQuantityKind
    var preparation: SupplyQuantityEntry?
}

struct BottleQuantityView: View {
    @StateObject private var model = BottleSupplyModel()
    @ObservedObject private var service = SupplyReminderService.shared
    @State private var route: QuantityRoute?
    @State private var undoID: UUID?
    @State private var confirmUndo = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("XYWAV · 0.5 g/mL") {
                if let remaining = model.remainingMg { BottleQuantityEstimate(remaining: remaining) }
                else { Text("Remaining amount not recorded.") }
                Text("Based on your balance and preparation entries. Unrecorded withdrawals can overstate stock. Prepared doses are separate. Night equivalents use the stated reference, not a change to your prescription.").font(.footnote)
                Button(model.remainingMg == nil ? "Set starting amount" : "Reconcile remaining amount") {
                    route = QuantityRoute(kind: .baseline)
                }.accessibilityIdentifier("quantity-baseline")
                    .disabled(model.supply?.activeBottleStart == nil)
                Button("Record prepared doses") { route = QuantityRoute(kind: .preparation) }
                    .accessibilityIdentifier("quantity-prepare").disabled((model.remainingMg ?? 0) <= 0)
                if model.supply?.activeBottleStart == nil { Text("Record a bottle opening in Bottle & supply first.").font(.footnote) }
            }
            Section("Prepared doses awaiting an outcome") {
                Text("Unresolved preparations: \(model.supply?.unresolvedPreparations.count ?? 0)")
                    .accessibilityIdentifier("quantity-unresolved-count")
                ForEach(model.supply?.unresolvedPreparations ?? []) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(supplyGrams(item.amountMg)) · \(item.occurredAt.formatted(date: .abbreviated, time: .shortened))").font(.headline)
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            Text(item.preparationLimitReached(at: timeline.date)
                                 ? "24-hour mixing limit reached. Follow the label disposal instructions; disposition is still unrecorded."
                                 : "Mixing time recorded. This is not confirmation that the dose is usable or was taken.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Link to a recorded dose") { route = QuantityRoute(kind: .doseLink, preparation: item) }
                        Button("Record as discarded") { route = QuantityRoute(kind: .discard, preparation: item) }
                    }.buttonStyle(.borderless)
                }
                Text("XYWAV mixed with water must be used within 24 hours. If not taken within that time, discard it according to the label. The app does not automatically carry a preparation into tomorrow or mark it discarded.").font(.footnote)
                Link("XYWAV preparation instructions", destination: URL(string: "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=1e0ae43a-037f-42af-8e23-a0e51d75abe8")!)
            }
            if let value = model.supply {
                Section("Quantity history") {
                    ForEach((value.quantityEntries ?? []).reversed()) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(title(item.kind))\(item.amountMg > 0 || item.kind == .baseline ? ": " + supplyGrams(item.amountMg) : "")")
                            Text(item.occurredAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            Text(item.reason).font(.caption)
                            if item.voidedAt != nil { Text("Voided — history retained").font(.caption) }
                            if let dose = item.dose, item.voidedAt == nil {
                                Text(model.doseEvidence.map { $0.contains(dose) ? "Linked \(dose.eventType) at \(dose.occurredAt.formatted(date: .abbreviated, time: .shortened))" : "Linked dose changed, was removed, or needs identity review." } ?? "Linked-dose verification unavailable. Retry before relying on this allocation.")
                                    .font(.caption)
                                if let prep = value.quantityEntries?.first(where: { $0.id == item.preparationID }), prep.preparationLimitReached(at: dose.occurredAt) {
                                    Text("Reported use at or beyond the 24-hour mixing limit — review with your pharmacist.").font(.caption)
                                }
                            }
                            if value.quantityEntries?.last(where: { $0.bottleID == item.bottleID && $0.voidedAt == nil })?.id == item.id {
                                Button("Correct by undoing this entry") { undoID = item.id; confirmUndo = true }
                                    .accessibilityIdentifier("quantity-undo-\(item.id)")
                            }
                        }
                    }
                }
            }
            if let error = model.error { Text(error); Button("Retry") { model.refresh() } }
            if let message { Text(message) }
        }.navigationTitle("Amounts & preparations")
            .task { model.refresh() }
            .onChange(of: service.backup) { _ in model.refresh() }
            .sheet(item: $route, onDismiss: { model.refresh() }) { route in
                BottleQuantityEntrySheet(kind: route.kind, preparation: route.preparation)
            }
            .confirmationDialog("Correct an erroneous quantity entry?", isPresented: $confirmUndo, titleVisibility: .visible) {
                Button("Undo quantity entry", role: .destructive) {
                    guard let id = undoID else { return }
                    let now = Date()
                    Task {
                        let success = await service.change { try $0.voidQuantity(id: id, at: now, now: now) }
                        message = success ? "Correction saved; medication records are unchanged." : service.status
                        model.refresh()
                    }
                }
            } message: { Text("Use this only to correct a mistaken entry. It does not mean mixed medication was returned to the bottle. For unused medication, record a discard instead.") }
            .disabled(service.isBusy)
    }
    private func title(_ kind: SupplyQuantityKind) -> String {
        switch kind { case .baseline: return "Bottle balance"; case .preparation: return "Prepared"
        case .discard: return "Discarded preparation"; case .doseLink: return "Allocated to recorded dose" }
    }
}

private struct BottleQuantityEntrySheet: View {
    let kind: SupplyQuantityKind
    let preparation: SupplyQuantityEntry?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var service = SupplyReminderService.shared
    @State private var source: SupplyBackup?
    @State private var evidence: [SupplyDoseEvidence] = []
    @State private var selectedDose: String?
    @State private var grams = ""
    @State private var count = 1
    @State private var reason = ""
    @State private var occurred = Date()
    @State private var ids = [UUID(), UUID()]
    @State private var recorded: Date?
    @State private var error: String?
    private var title: String {
        switch kind { case .baseline: return "Bottle balance"; case .preparation: return "Prepared doses"
        case .discard: return "Discarded preparation"; case .doseLink: return "Link recorded dose" }
    }
    private var amount: Int? {
        let normalized = grams.replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, normalized.allSatisfy({ "0123456789.".contains($0) }),
              normalized.filter({ $0 == "." }).count <= 1, let value = Decimal(string: normalized), value >= 0, value <= 90 else { return nil }
        let mg = NSDecimalNumber(decimal: value * 1000)
        guard mg == NSDecimalNumber(value: mg.intValue) else { return nil }
        return mg.intValue
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("XYWAV oral solution · 0.5 g/mL")
                if kind == .baseline || kind == .preparation {
                    TextField(kind == .baseline ? "Grams still in the bottle" : "Grams per prepared dose", text: $grams)
                        .keyboardType(.decimalPad).accessibilityIdentifier("quantity-grams")
                    if kind == .baseline {
                        Text("Enter the amount still IN the bottle now, excluding prepared doses. A full 180 mL bottle is nominally 90 g. This explicit balance replaces the estimate from earlier entries; their history remains.").font(.footnote)
                        TextField("Reason for this balance", text: $reason).accessibilityIdentifier("quantity-reason")
                    } else {
                        Stepper("Prepared doses: \(count)", value: $count, in: 1...2).accessibilityIdentifier("quantity-count")
                        Text("Confirm doses you already measured from this bottle and mixed with water. Each gets a separate record. This does not log medication as taken.").font(.footnote)
                    }
                    DatePicker(kind == .baseline ? "Balance as of" : "Mixed with water at", selection: $occurred, in: ...Date())
                } else if kind == .discard {
                    Text("Confirm the prepared \(supplyGrams(preparation?.amountMg ?? 0)) was discarded. The bottle amount will not be deducted again.")
                    DatePicker("Discarded at", selection: $occurred, in: ...Date())
                } else {
                    Text("Choose the dose you already logged as taken. This links inventory only; it does not create or change medication records.")
                    Picker("Recorded dose", selection: $selectedDose) {
                        Text("Choose a dose").tag(String?.none)
                        ForEach(evidence, id: \.eventID) { item in
                            Text("\(item.eventType) · \(item.occurredAt.formatted(date: .abbreviated, time: .shortened))").tag(Optional(item.eventID))
                        }
                    }
                    if evidence.isEmpty { Text("No eligible recorded dose found. Log an actual administration through the normal dose controls or History first.").font(.footnote) }
                }
                Button("Confirm and save") { save() }.accessibilityIdentifier("quantity-save")
                    .disabled(source == nil || service.isBusy || ((kind == .baseline || kind == .preparation) && amount == nil) || (kind == .baseline && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || (kind == .doseLink && selectedDose == nil))
                if let error { Text(error).foregroundStyle(.secondary) }
            }.navigationTitle(title).disabled(service.isBusy)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(service.isBusy) } }
                .task {
                    do {
                        source = try SessionRepository.shared.loadSupply()
                        if kind == .preparation, grams.isEmpty {
                            grams = String(Double(SupplyQuantity.referenceDoseMg) / 1000)
                        }
                        if kind == .doseLink, let preparation {
                            let used = Set((source?.quantityEntries ?? []).filter { $0.voidedAt == nil }.compactMap { $0.dose?.eventID })
                            evidence = try SessionRepository.shared.supplyDoseEvidence().filter { $0.occurredAt >= preparation.occurredAt && $0.occurredAt <= Date() && !used.contains($0.eventID) }
                        }
                    } catch { self.error = "Could not load current supply or dose evidence. Close and retry." }
                }
        }.interactiveDismissDisabled(service.isBusy)
            .onChange(of: grams) { _ in resetAttempt() }.onChange(of: count) { _ in resetAttempt() }
            .onChange(of: occurred) { _ in resetAttempt() }.onChange(of: reason) { _ in resetAttempt() }
            .onChange(of: selectedDose) { _ in resetAttempt() }
    }
    private func resetAttempt() { ids = [UUID(), UUID()]; recorded = nil }
    private func save() {
        guard let bottle = preparation?.bottleID ?? source?.activeBottleStart?.id else { return }
        let now = Date(), captured = recorded ?? now, selected = evidence.first { $0.eventID == selectedDose }
        let entryTime = selected?.occurredAt ?? occurred, expected = source?.quantityEntries
        let entries = (0..<(kind == .preparation ? count : 1)).map { index in
            SupplyQuantityEntry(id: ids[index], bottleID: bottle, kind: kind,
                amountMg: kind == .baseline || kind == .preparation ? (amount ?? -1) : 0,
                occurredAt: entryTime, recordedAt: captured,
                reason: kind == .baseline ? reason : "User confirmed \(kind.rawValue)", preparationID: preparation?.id, dose: selected)
        }
        recorded = captured
        Task {
            let success = await service.change { value in
                guard value.quantityEntries == expected || entries.allSatisfy({ e in value.quantityEntries?.contains(e) == true }) else { throw SupplyQuantityError.conflict }
                if kind == .baseline || kind == .preparation {
                    guard value.activeBottleStart?.id == bottle else { throw SupplyQuantityError.conflict }
                }
                if let selected { try SessionRepository.shared.validateSupplyDose(selected) }
                try value.recordQuantities(entries, now: now)
            }
            if success { dismiss() } else { error = service.status }
        }
    }
}
