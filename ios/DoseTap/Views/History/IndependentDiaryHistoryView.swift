import SwiftUI
import CoreFoundation
import DoseCore

enum DiaryCollection: String, CaseIterable, Identifiable {
    case checkIns = "daytime_checkins", events = "daytime_events", naps = "nap_diary"
    case visits = "physician_review_records", prompts = "daytime_prompt_state", work = "work_block_context"
    case doseReviews = "dashboard_dose_reviews", providers = "dashboard_provider_associations"

    var id: Self { self }

    var title: String {
        switch self {
        case .checkIns: "Daytime check-ins"
        case .events: "Daytime events"
        case .naps: "Nap diary"
        case .visits: "Physician visits and reports"
        case .prompts: "Daytime prompts"
        case .work: "Work history"
        case .doseReviews: "Dose history reviews"
        case .providers: "Provider associations"
        }
    }
}

struct IndependentDiaryHistoryView: View {
    var body: some View {
        List(DiaryCollection.allCases) { collection in
            NavigationLink(collection.title) { DiaryCollectionView(collection: collection) }
                .accessibilityIdentifier("diary-collection-\(collection.rawValue)")
        }
        .navigationTitle("Diary records")
    }
}

private struct DiaryCollectionView: View {
    let collection: DiaryCollection
    @State private var records: [DiaryHistoryRecord]?
    @State private var failed = false
    @State private var adding = false

    var body: some View {
        List {
            if collection == .checkIns {
                Button("Record daytime check-in", systemImage: "plus") { adding = true }
                    .disabled(failed || records == nil)
                    .accessibilityIdentifier("daytime-add")
            }
            if failed {
                Text("These records could not be read.")
                Button("Try again", action: load)
            } else if let records {
                if records.isEmpty {
                    Text("No saved records in this collection.")
                } else {
                    ForEach(records) { record in
                        NavigationLink {
                            DiaryRecordDetail(record: record)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title)
                                Text(record.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("diary-record-\(record.id)")
                    }
                }
            } else {
                ProgressView("Loading records…")
            }
        }
        .navigationTitle(collection.title)
        .task { load() }
        .sheet(isPresented: $adding, onDismiss: load) { DaytimeCheckInEditor() }
        .onReceive(SessionRepository.shared.sessionDidChange) { _ in
            if collection == .checkIns { load() }
        }
    }

    private func load() {
        do {
            let rows = try SessionRepository.shared.exportIndependentSourceRecords(in: collection.rawValue)
            records = try rows.reversed().map { try DiaryHistoryRecord(collection: collection, source: $0) }
            failed = false
        } catch {
            records = nil
            failed = true
        }
    }
}

struct DiaryHistoryRecord: Identifiable {
    let id: String
    let collection: DiaryCollection
    let source: StoredExportSourceRecord
    let payload: [String: Any]?

    init(collection: DiaryCollection, source: StoredExportSourceRecord) throws {
        guard source.sourceTable == collection.rawValue,
              let key = StudioIndependentSourceRecord.primaryKeys[source.sourceTable],
              let identity = source.columns[key],
              let id = identity.text ?? identity.integer.map(String.init),
              !id.isEmpty else { throw ExportReadError.unreadable }
        self.id = id
        self.collection = collection
        self.source = source
        if let text = source.columns["payload"]?.text {
            payload = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        } else {
            payload = nil
        }
    }

    var title: String {
        switch collection {
        case .checkIns:
            if payload?["status"] as? String == "answered", let score = payload?["response"] as? NSNumber {
                if payload?["instrumentID"] as? String == "dosetap.custom-current-sleepiness" {
                    return "Sleepiness \(score.stringValue)/10"
                }
                return "Response \(score.stringValue)"
            }
            return payload?["status"] as? String ?? "Daytime check-in"
        case .events: return payload?["kind"] as? String ?? "Daytime event"
        case .visits:
            switch source.columns["kind"]?.text {
            case "visit": return "Physician visit"
            case "report": return "Physician report"
            default: return "Physician record"
            }
        case .naps: return "Nap diary"
        case .prompts: return "Prompt history"
        case .work: return "Work history"
        case .doseReviews: return "Dose history review"
        case .providers: return source.columns["provider"]?.text ?? "Provider association"
        }
    }

    var subtitle: String {
        let shortID = String(id.prefix(8))
        let revision = payload?["predecessorID"] != nil ? "Correction · " : ""
        if let date = source.columns["session_date"]?.text { return "\(date) · \(shortID)" }
        let key = collection == .checkIns ? "assessedAt" : "occurredAt"
        if let time = payload?[key] as? NSNumber {
            let timestamp = collection.timestamp(time, zone: payload?["timeZoneIdentifier"] as? String)
            return "\(revision)\(timestamp) · \(shortID)"
        }
        return "Record \(shortID)"
    }
}

private struct DiaryRecordDetail: View {
    let record: DiaryHistoryRecord
    @Environment(\.dismiss) private var dismiss
    @State private var latest: DaytimeCheckIn?
    @State private var showingCorrection = false
    @State private var correctionSaved = false
    @State private var correctionUnavailable = false

    var body: some View {
        List {
            if latest != nil {
                Button("Correct response", systemImage: "pencil") { showingCorrection = true }
                    .accessibilityIdentifier("daytime-correct")
            }
            if correctionUnavailable {
                Text("This revision could not be verified for correction. Its original record is available below.")
            }
            if record.collection == .prompts {
                SavedDaytimeReminderSection(record: record.source)
            }
            if let payload = record.payload {
                Section("Recorded details") { DiaryFields(object: payload, collection: record.collection) }
            } else if record.source.columns["payload"] != nil {
                Text("The saved payload could not be displayed as fields. Its original value is available below.")
            }
            Section("Source record") {
                ForEach(record.source.columns.keys.sorted(), id: \.self) { key in
                    if let column = record.source.columns[key] {
                        if key == "payload" {
                            NavigationLink("Original payload") {
                                ScrollView {
                                    Text(verbatim: column.historyText)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                                }
                                .textSelection(.enabled).navigationTitle("Original payload")
                            }
                        } else {
                            DiaryFieldValue(label: DiaryFields.label(key), value: column.historyText)
                        }
                    }
                }
            }
        }
        .navigationTitle(record.title)
        .task {
            guard record.collection == .checkIns else { return }
            do {
                latest = try SessionRepository.shared.daytimeCheckIns().current.first {
                    $0.revisionID.uuidString == record.id
                }
            } catch {
                correctionUnavailable = true
            }
        }
        .sheet(isPresented: $showingCorrection, onDismiss: {
            if correctionSaved { dismiss() }
        }) {
            if let latest {
                DaytimeCheckInEditor(original: latest) { correctionSaved = true }
            }
        }
    }
}

private extension StoredExportColumn {
    var historyText: String {
        if let text { return text.isEmpty ? "Empty text" : text }
        if let integer { return String(integer) }
        if let real { return String(real) }
        if let blobBase64 { return "Base64 · \(blobBase64)" }
        return "No stored value"
    }
}

private extension DiaryCollection {
    // Build-108 daytime check-ins/events encode Unix time. Nap, visit, work and review
    // documents use the Foundation reference epoch; prompt dates are already ISO 8601 strings.
    func timestamp(_ number: NSNumber, zone: String?) -> String {
        let date = self == .checkIns || self == .events
            ? Date(timeIntervalSince1970: number.doubleValue)
            : Date(timeIntervalSinceReferenceDate: number.doubleValue)
        let zone = zone.flatMap(TimeZone.init(identifier:)) ?? .current
        var style = Date.FormatStyle().year().month(.abbreviated).day().hour().minute().timeZone(.specificName(.short))
        style.timeZone = zone
        return date.formatted(style)
    }
}

private struct DiaryFieldValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: label).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).textSelection(.enabled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityIdentifier("diary-field-\(label)")
    }
}

/// Preserve array order and navigate into nested ledger entries without inferring which revision is current.
private struct DiaryFields: View {
    let object: Any
    let collection: DiaryCollection

    private static let numericDateKeys: Set<String> = [
        "assessedAt", "capturedAt", "createdAt", "occurredAt", "recordedAt", "scheduledAt",
        "start", "end", "endExclusive", "scheduledStart", "scheduledEnd", "actualStart", "actualEnd",
        "plannedBreakAt", "plannedAt"
    ]

    var body: some View {
        if let fields = object as? [String: Any] {
            ForEach(fields.keys.sorted(), id: \.self) { key in
                if let value = fields[key] { row(title: Self.label(key), key: key, value: value) }
            }
        } else if let entries = object as? [Any] {
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                let fields = entry as? [String: Any]
                let title = fields?["day"] as? String ?? fields?["workDate"] as? String ?? "Entry \(index + 1)"
                row(title: title, value: entry)
            }
        }
    }

    static func label(_ key: String) -> String {
        let spaced = key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    @ViewBuilder private func row(title: String, key: String? = nil, value: Any) -> some View {
        if let count = (value as? [Any])?.count ?? (value as? [String: Any])?.count {
            if count == 0 {
                DiaryFieldValue(label: title, value: "No entries")
            } else {
                NavigationLink {
                    List { DiaryFields(object: value, collection: collection) }.navigationTitle(title)
                } label: {
                    Text("\(title) (\(count))")
                }
            }
        } else if let number = value as? NSNumber {
            let isBool = CFGetTypeID(number) == CFBooleanGetTypeID()
            if !isBool, let key, Self.numericDateKeys.contains(key), collection != .prompts {
                let fields = object as? [String: Any]
                let zone = fields?["timeZoneIdentifier"] as? String ?? fields?["timeZoneID"] as? String
                DiaryFieldValue(label: title, value: collection.timestamp(number, zone: zone))
            } else {
                DiaryFieldValue(label: title, value: isBool ? (number.boolValue ? "Yes" : "No") : number.stringValue)
            }
        } else if let text = value as? String {
            DiaryFieldValue(label: title, value: text.isEmpty ? "Empty text" : text)
        } else {
            DiaryFieldValue(label: title, value: "No stored value")
        }
    }
}
