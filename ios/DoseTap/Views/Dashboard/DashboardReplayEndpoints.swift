import SwiftUI
import DoseCore

struct ReplayMedication: Identifiable {
    let id: String
    let medicationID: String
    let name: String
    let formulation: String
    let amount: String
    let occurredAt: Date?
    let recordedAt: Date
    let precision: String
    let release: MedicationReleaseProfile
    init(_ record: MedicationHistoryRecord) throws {
        id = record.id
        switch record {
        case .quick(let value):
            medicationID = value.medicationId
            name = MedicationConfig.type(for: value.medicationId)?.displayName ?? value.medicationId
            formulation = value.formulation; amount = "\(value.doseMg) \(value.doseUnit)"
            occurredAt = value.takenAtUTC; recordedAt = value.createdAt; precision = "legacy recorded occurrence"
            switch value.formulation.lowercased() {
            case "xr", "extended_release", "extendedrelease": release = .extendedRelease
            case "ir", "immediate_release", "immediaterelease": release = .immediateRelease
            default: release = .unknown
            }
        case .preset(let value):
            medicationID = value.preset.presetID.uuidString; name = value.preset.labelName
            formulation = value.preset.releaseProfile.rawValue
            amount = NSDecimalNumber(decimal: try value.totalMilligrams).stringValue + " mg"
            occurredAt = value.occurredAt; recordedAt = value.recordedAt; precision = value.precision.rawValue
            release = value.preset.releaseProfile
        }
    }
    func marker(role: DashboardReplayMarker.Kind, sessionID: String) -> DashboardReplayMarker? {
        guard let occurredAt, role == .daytimeMedication || (role == .medicationXR && release == .extendedRelease)
            || (role == .medicationIR && release == .immediateRelease) else { return nil }
        return .init(id: id + ":" + role.rawValue, sessionID: sessionID, kind: role, occurredAt: occurredAt,
            recordedAt: recordedAt, source: "User-selected for this inspection only; \(name); \(precision)",
            sourceRecordID: id, medicationID: medicationID, formulation: formulation, amountDescription: amount)
    }
}

/// Explicit inspection links. These never rewrite an administration's stored session or schedule.
struct DashboardReplayEndpoints: View {
    @ObservedObject var model: DashboardAnalyticsModel
    let snapshot: DashboardReplaySnapshot
    @Binding var selected: [DashboardReplayMarker]
    var onRecords: ([ReplayMedication]) -> Void = { _ in }
    @State private var medications: [ReplayMedication] = []
    @State private var error: String?
    private let roles: [DashboardReplayMarker.Kind] = [.medicationXR, .medicationIR, .daytimeMedication, .napEnd]
    private var naps: [StoredSleepEvent] {
        let rows = model.nights.flatMap(\.events).filter { normalizeStoredEventType($0.eventType) == "nap_end" }
        return Dictionary(grouping: rows, by: \.id).values.compactMap { group in
            guard let first = group.first, group.allSatisfy({ $0.timestamp == first.timestamp }) else { return nil }
            return first
        }.sorted { $0.timestamp > $1.timestamp }
    }
    var body: some View {
        DisclosureGroup("Select medication or nap endpoints / review medication logs") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose actual records to associate with this selected sleep/session for inspection. Nothing is chosen by calendar date or nearest time. These temporary links do not edit source records.").font(.caption)
                if let error { Text(error).foregroundStyle(.secondary) }
                ForEach(roles, id: \.rawValue) { role in
                    Picker(role.label, selection: selection(role)) {
                        Text("Not selected").tag("")
                        if role == .napEnd {
                            ForEach(naps.filter { $0.timestamp <= snapshot.asOf }) { nap in
                                Text("Recorded nap end · \(nap.timestamp.formatted())").tag(nap.id)
                            }
                        } else {
                            ForEach(medications.filter { $0.marker(role: role, sessionID: snapshot.sessionID).map { $0.occurredAt <= snapshot.asOf } == true }) { medication in
                                Text("\(medication.name) · \(medication.formulation) · \(medication.amount) · \(medication.occurredAt?.formatted() ?? "time unknown")").tag(medication.id)
                            }
                        }
                    }.accessibilityIdentifier("dashboard-replay-endpoint-" + role.rawValue).disabled(error != nil || model.isLoading)
                }
                Text("Reported medication ledger").font(.headline)
                Text("Actual amounts stay per medication. No combined milligram scale, planned-amount substitution or claim of alarm delivery. Unknown-time records remain below but cannot become interval endpoints.").font(.caption)
                if medications.isEmpty && error == nil { Text("No medication ledger entries are available.") }
                ForEach(medications) { medication in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(medication.name + " · " + medication.formulation).font(.subheadline.bold())
                        Text(medication.amount + " · " + (medication.occurredAt?.formatted() ?? "Occurrence time unknown"))
                        Text("Recorded \(medication.recordedAt.formatted()) · \(medication.precision)").font(.caption)
                    }.accessibilityElement(children: .combine)
                }
                Button("Reload medication ledger") { reload() }
            }.padding(.top, 8)
        }.task { reload() }
            .onReceive(model.sessionRepo.sessionDidChange) { _ in selected = []; reload() }
    }
    private func selection(_ role: DashboardReplayMarker.Kind) -> Binding<String> {
        Binding(get: { selected.first { $0.kind == role }?.sourceRecordID ?? "" }, set: { id in
            selected.removeAll { $0.kind == role }
            if role == .napEnd, let nap = naps.first(where: { $0.id == id }) {
                selected.append(.init(id: "nap:" + nap.id, sessionID: snapshot.sessionID, kind: .napEnd,
                    occurredAt: nap.timestamp, source: "User-selected recorded nap end; no duration or sleep amount inferred", sourceRecordID: nap.id))
            } else if let medication = medications.first(where: { $0.id == id }),
                      let marker = medication.marker(role: role, sessionID: snapshot.sessionID) { selected.append(marker) }
        })
    }
    private func reload() {
        do { medications = try DashboardReplayUITestFixture.medications(model: model) ?? model.sessionRepo.medicationHistory().map(ReplayMedication.init); error = nil; onRecords(medications) }
        catch { onRecords([]); self.error = "Medication records could not be read completely. Endpoint selection is disabled; retry reload." }
    }
}
