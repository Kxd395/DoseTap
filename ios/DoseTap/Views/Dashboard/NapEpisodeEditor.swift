import SwiftUI
import DoseCore

struct NapEpisodeEditor: View {
    let original: NapEpisode?
    let candidates: [NapEpisode]
    let source: NapEpisode?
    var persistedRevision: UUID? = nil
    let day: String
    let zone: String
    let save: (NapEpisode) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hasTimes = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var endKnown = false
    @State private var estimateKnown = false
    @State private var estimate = ""
    @State private var benefit = ""
    @State private var intent = NapIntent.unknown
    @State private var duplicate = ""
    @State private var reason = ""
    @State private var reviewed = false
    @State private var keepSource = false
    @State private var capturedRevision: UUID?
    @State private var capturedSource: NapEpisode?
    @State private var initialized = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Reviewed nap or rest episode") {
                    Text("One episode can include both your report and a separate Apple Health check. Rest time is not automatically time asleep.").font(.caption)
                    Text("Calendar date: \(day). Timezone: \(zone)").font(.caption)
                    Toggle("I know the start time", isOn: $hasTimes)
                    if hasTimes {
                        DatePicker("Nap / rest started", selection: $start, in: ...Date())
                    }
                    Toggle("I know the end time", isOn: $endKnown)
                    if endKnown { DatePicker("Nap / rest ended", selection: $end, in: ...Date()) }
                    if !hasTimes || !endKnown { Text("A missing clock boundary stays unknown. A duration-only report has no invented clock position.").font(.caption) }
                    Toggle("I can estimate time actually asleep", isOn: $estimateKnown).accessibilityIdentifier("nap-estimate-known")
                    if estimateKnown { TextField("Estimated asleep minutes", text: $estimate).keyboardType(.decimalPad).accessibilityIdentifier("nap-estimated-minutes") }
                    TextField("Optional reported benefit (0–10)", text: $benefit).keyboardType(.numberPad)
                    Text("Custom rating: 0 = no benefit, 10 = greatest perceived benefit. Leave blank if unknown; this is not a validated symptom scale.").font(.caption)
                    Picker("Intent", selection: $intent) { ForEach(NapIntent.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                }
                if original?.sourceEventIDs.isEmpty == false {
                    Section("Recorded timer evidence") {
                        if let capturedSource {
                            Text("Recorded start: \(capturedSource.start?.formatted() ?? "unknown"); recorded end: \(capturedSource.end?.formatted() ?? "unknown").")
                            Text("Your reviewed report above remains separate from these source boundaries.").font(.caption)
                        } else { Text("The original timer evidence is no longer available. Reopen if it changed, or explicitly remove its association with a reason.") }
                        Toggle("Retain recorded timer association", isOn: $keepSource)
                    }
                }
                Section("Duplicate observations") {
                    Picker("Same episode as", selection: $duplicate) {
                        Text("Separate episode").tag("")
                        ForEach(candidates.filter { $0.id != original?.id && $0.duplicateOf == nil }) { value in
                            Text("\(value.day) · \(value.start?.formatted() ?? "duration only") · \(value.id.suffix(6))").tag(value.id)
                        }
                    }
                    Text("Choose an existing episode only after reviewing both records. A linked manual/device observation is counted once. Overlap alone does not establish a match.").font(.caption)
                    TextField("Correction or matching reason", text: $reason, axis: .vertical)
                }
                Toggle("I reviewed the timing, estimate and episode association", isOn: $reviewed).accessibilityIdentifier("nap-reviewed")
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("nap-save-error") }
            }.environment(\.timeZone, TimeZone(identifier: zone) ?? .current).scrollDismissesKeyboard(.immediately)
                .navigationTitle(original == nil ? "Add nap report" : "Review nap").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save review", action: submit).disabled(!reviewed).accessibilityIdentifier("nap-save-review") }
                }
                .onAppear {
                    guard !initialized else { return }; initialized = true
                    capturedSource = source; capturedRevision = persistedRevision
                    guard let original else { return }
                    keepSource = !original.sourceEventIDs.isEmpty
                    hasTimes = original.start != nil; start = original.start ?? capturedSource?.start ?? Date(); end = original.end ?? capturedSource?.end ?? Date()
                    endKnown = original.end != nil; estimateKnown = original.estimatedSleepMinutes != nil
                    estimate = original.estimatedSleepMinutes.map { String($0) } ?? ""
                    benefit = original.benefitRating.map(String.init) ?? ""
                    intent = original.intent; duplicate = original.duplicateOf ?? ""
                }
        }
    }
    private func submit() {
        guard !estimateKnown || Double(estimate) != nil else { error = "Enter estimated asleep minutes or turn off the estimate."; return }
        guard benefit.isEmpty || Int(benefit) != nil else { error = "Enter a whole-number benefit rating from 0 to 10, or leave it blank."; return }
        var next = NapEpisode(id: original?.id ?? UUID().uuidString,
            day: hasTimes ? NapEpisode.day(start, zone) : (endKnown ? NapEpisode.day(end, zone) : day), timeZoneID: zone,
            start: hasTimes ? start : nil, end: endKnown ? end : nil,
            estimatedSleepMinutes: estimateKnown ? Double(estimate) : nil, recordedAt: Date())
        next.benefitRating = Int(benefit); next.intent = intent; next.duplicateOf = duplicate.isEmpty ? nil : duplicate
        next.reason = reason; next.predecessor = capturedRevision
        if keepSource {
            guard let capturedSource else { error = "Reopen the current timer evidence or explicitly remove its association."; return }
            next.sourceEventIDs = capturedSource.sourceEventIDs; next.sourceEvidenceKey = capturedSource.evidenceKey
        } else if original?.sourceEventIDs.isEmpty == false && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "Explain why the timer association is being removed."; return
        }
        guard next.isValid else { error = "Check the ordered, nonfuture times, asleep estimate and matching reason."; return }
        do { try save(next); dismiss() } catch { self.error = error.localizedDescription }
    }
}
