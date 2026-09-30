import SwiftUI
import DoseCore

struct DaytimeSourcePicker: View {
    let repository: SessionRepository
    @Binding var selected: [DaytimeSourceLink]
    @State private var kind = DaytimeSourceLink.Kind.nap
    @State private var candidates: [DaytimeSourceCandidate] = []
    @State private var failure: String?
    var body: some View {
        List {
            Section {
                Text("Select existing records for context. Linking creates no nap, dose, or sleep session and does not establish an effect.")
                Picker("Source type", selection: $kind) {
                    Text("Naps").tag(DaytimeSourceLink.Kind.nap)
                    Text("Medication taken").tag(DaytimeSourceLink.Kind.medication)
                    Text("Reported main wake").tag(DaytimeSourceLink.Kind.mainWake)
                }.accessibilityIdentifier("daytime-source-kind")
            }
            if !selected.isEmpty {
                Section("Selected source snapshots") {
                    ForEach(selected) { link in
                        VStack(alignment: .leading) {
                            Text("\(link.kind.rawValue) · \(link.daytimePrecisionLabel) · \(link.daytimeTimestamp(link.start))")
                            Text("\(link.sourceCalendarDay ?? "") \(link.timeZoneIdentifier ?? "")").font(.caption)
                            if link.kind == kind, failure == nil, !candidates.contains(where: { $0.matches(link) }) {
                                Text("Source changed or is unavailable. Remove this selection or explicitly choose its current version before saving.").foregroundStyle(.orange)
                            }
                            Button("Remove selection", role: .destructive) { selected.removeAll { $0.id == link.id } }
                        }
                    }
                }
            }
            Section("Available existing records") {
                if kind == .nap { Text("Naps with overlapping or conflicting source records need review in Sleep & naps before linking.").font(.caption) }
                if let failure { Text(failure) }
                else if candidates.isEmpty { Text("No eligible records of this type. Unknown or unavailable history is not a zero value.") }
                ForEach(candidates) { candidate in
                    Button {
                        selected.removeAll { $0.id == candidate.id }
                        selected.append(candidate.link)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(candidate.label)
                            Text(selected.contains(where: { candidate.matches($0) }) ? "Selected" : "Select this source version").font(.caption)
                        }
                    }.disabled(selected.count >= 32 && !selected.contains(where: { $0.id == candidate.id }))
                        .accessibilityIdentifier("daytime-source-candidate")
                }
                Button("Refresh sources", action: load)
            }
        }.navigationTitle("Existing source links").onAppear(perform: load).onChange(of: kind) { _ in load() }
    }
    private func load() {
        do { candidates = try repository.daytimeSourceCandidates(kind: kind, asOf: Date()); failure = nil }
        catch { candidates = []; failure = "These source records could not be read. Your selections are retained; refresh to retry." }
    }
}
