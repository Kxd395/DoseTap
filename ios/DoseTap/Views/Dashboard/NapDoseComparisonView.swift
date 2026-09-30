import SwiftUI
import DoseCore

/// Selecting endpoints is a transient inspection, never a medication command.
struct NapDoseComparisonView: View {
    let episode: NapEpisode
    let nights: [DashboardNightAggregate]
    let asOf: Date
    let doseDataAsOf: Date
    @State private var selectedID: String?
    private struct Option: Identifiable {
        let sessionID: String
        let dose: DoseCore.StoredDoseEvent
        var id: String { sessionID + ":" + dose.id }
        var label: String { ["dose1": "Dose 1", "dose2": "Dose 2", "extra_dose": "Extra dose"][dose.eventType] ?? "Recorded dose" }
    }
    private var options: [Option] {
        let values = nights.flatMap { night -> [Option] in
            guard let session = night.sessionID, !night.identityNeedsReview else { return [] }
            return night.doseEvents.filter {
                $0.sessionId == session && ["dose1", "dose2", "extra_dose"].contains($0.eventType)
                && $0.timestamp.timeIntervalSince1970.isFinite && $0.timestamp <= min(asOf, doseDataAsOf)
            }.map { Option(sessionID: session, dose: $0) }
        }
        return Dictionary(grouping: values, by: \.id).values.compactMap { $0.count == 1 ? $0.first : nil }.sorted { $0.dose.timestamp == $1.dose.timestamp ? $0.id < $1.id : $0.dose.timestamp < $1.dose.timestamp }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actual nap end to selected dose").font(.headline)
            Text("Select an actual administration occurrence. No dose is chosen from proximity, and the interval is not dosing guidance.").font(.caption)
            Text("Dose history captured \(NapPeriodEligibility.stamp(doseDataAsOf, zone: episode.timeZoneID)); nap evidence read \(NapPeriodEligibility.stamp(asOf, zone: episode.timeZoneID)).").font(.caption)
            Picker("Actual dose occurrence", selection: $selectedID) {
                Text("Choose a recorded dose").tag(String?.none)
                if let selectedID, !options.contains(where: { $0.id == selectedID }) { Text("Selected dose is filtered or unavailable").tag(Optional(selectedID)) }
                ForEach(options) { option in
                    Text("\(option.label) · \(NapPeriodEligibility.stamp(option.dose.timestamp, zone: episode.timeZoneID)) · \(option.dose.id.suffix(6))").tag(Optional(option.id))
                }
            }
            .accessibilityIdentifier("nap-dose-choice")
            if let choice = options.first(where: { $0.id == selectedID }) {
                if let value = NapDoseInterval(episode: episode, dose: choice.dose, sessionID: choice.sessionID, asOf: asOf) {
                    Text(String(format: "%.1f elapsed minutes", value.minutes)).accessibilityIdentifier("nap-dose-interval")
                    Text("Nap end \(NapPeriodEligibility.stamp(value.start, zone: episode.timeZoneID)) → actual dose \(NapPeriodEligibility.stamp(value.end, zone: episode.timeZoneID)). Nap \(value.napID); dose \(value.doseID); session \(value.sessionID). Displayed in \(episode.timeZoneID).").font(.caption)
                        .textSelection(.enabled)
                    ShareLink("Share selected interval CSV", item: intervalCSV(value))
                } else {
                    Text("Unavailable: a known nap end before the selected actual dose is required; unresolved or linked duplicate episodes cannot supply an interval.").font(.caption)
                }
            } else { Text("No explicit endpoint pair selected.").font(.caption) }
        }.onChange(of: episode.id) { _ in selectedID = nil }
    }
    private func intervalCSV(_ value: NapDoseInterval) -> String {
        let stamp = ISO8601DateFormatter()
        return ReportCSV.row(["nap_id", "nap_evidence_key", "nap_timezone", "dose_id", "dose_session_id", "actual_nap_end_utc", "actual_dose_utc", "elapsed_minutes", "nap_snapshot_at", "dose_dataset_as_of", "definition"]) + "\r\n"
            + ReportCSV.row([value.napID, episode.evidenceKey, episode.timeZoneID, value.doseID, value.sessionID, stamp.string(from: value.start), stamp.string(from: value.end), String(value.minutes), stamp.string(from: asOf), stamp.string(from: doseDataAsOf), "nap_actual_end_to_explicit_dose_v1; descriptive only"]) + "\r\n"
    }

}
