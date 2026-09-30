import SwiftUI
import DoseCore

struct DosePatternDetailSheet: View {
    @ObservedObject var model: DashboardAnalyticsModel
    let observationID: String?
    let navigationIDs: [String]
    let select: (String) -> Void
    let outcome: DosePatternSleepOutcome
    @Environment(\.dismiss) private var dismiss
    @State private var reviewObservation: DashboardNightAggregate?

    private var night: DashboardNightAggregate? { model.nights.first { $0.id == observationID } }
    private var freshness: DashboardSleepMetricProjection.Freshness {
        model.providerSnapshotIsCurrent(model.sleepSource == .appleHealth ? .health : .whoop) ? .current : .stale
    }

    var body: some View {
        NavigationStack {
            List {
                if let night {
                    Section("Selected observation") {
                        Text(night.sessionDate).font(.headline)
                        Text(night.dosePattern.pattern.label)
                        Text(night.providerAssociation)
                        Text("Identity: \(night.sessionID == nil ? "provider or unresolved observation" : "resolved treatment session")")
                        Text("\(model.reportingTimeZone.identifier) • \(DashboardDosePattern.version)").font(.caption)
                    }
                    Section("Selected sleep and interval") {
                        LabeledContent("Source", value: model.sleepSource.rawValue)
                        LabeledContent(outcome.rawValue, value: DosePatternPresentation.minutes(
                            DosePatternPresentation.sleepValue(night, source: model.sleepSource, outcome: outcome, freshness: freshness)))
                        Text(DosePatternPresentation.sleepDescription(night, source: model.sleepSource, outcome: outcome, freshness: freshness))
                            .font(.caption).foregroundStyle(.secondary)
                        LabeledContent("D1–D2", value: DosePatternPresentation.minutes(night.dosePattern.interval.value))
                        Text("\(night.dosePattern.interval.state.rawValue): \(night.dosePattern.interval.reason.replacingOccurrences(of: "_", with: " "))")
                        Text("Sleep eligibility and dose-spacing eligibility are independent. A reviewed-night window is not this main-episode total.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Dose evidence") {
                        LabeledContent("Reported count", value: String(night.dosePattern.reportedCount))
                        LabeledContent("Count completeness", value: night.dosePattern.countComplete ? "Explicit complete report" : "Not confirmed complete")
                        ForEach(night.doseEvents) { event in
                            VStack(alignment: .leading) {
                                Text(event.eventType)
                                Text(timestamp(event.timestamp)).font(.caption).foregroundStyle(.secondary)
                                if CanonicalDoseEventType(canonicalizing: event.eventType)?.countsAsTakenDose == true {
                                    Text("Recorded amount: " + (DosePatternPresentation.recordedAmountMg(event).map { $0.formatted() + " mg" } ?? "unknown"))
                                        .font(.caption)
                                }
                            }
                        }
                        if night.doseEvents.isEmpty { Text("No administration source rows in this observation.") }
                        Text("Actual amounts are not inferred from count or the historical plan. Review medication records for confirmed amounts.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(night.doseReview == nil ? "Review dose history" : "Correct saved dose-history review") {
                            reviewObservation = night
                        }.disabled(night.reviewFingerprint == nil || night.identityNeedsReview)
                            .accessibilityIdentifier("dose-pattern-review")
                        if night.identityNeedsReview { Text("Resolve this observation's source identity before saving a count review.").font(.caption) }
                    }
                    Section("Distinct sleep and app times") {
                        timeRow("Selected provider sleep onset", model.sleepSource == .appleHealth ? night.healthSummary?.sleepOnset : nil)
                        timeRow("Selected provider last observed sleep end", model.sleepSource == .appleHealth ? night.healthSummary?.finalWake : nil)
                        if model.sleepSource == .whoop { Text("The current WHOOP summary does not expose absolute onset/end times. Apple Health timestamps are not substituted.").font(.caption) }
                        timeRow("Patient-reported final awakening", night.outcome?.finalWakeAt)
                        Text("Wake Up captures an app action. Finishing morning check-in closes the session; neither extends provider sleep.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Browse observations") {
                        HStack {
                            Button("Previous") { move(-1) }.disabled(neighbor(-1) == nil)
                            Spacer()
                            Button("Next") { move(1) }.disabled(neighbor(1) == nil)
                        }
                        Text("\(navigationIDs.count) observations in the originating selection. Refresh retains the selected identity.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("This observation is no longer available. Close detail and inspect the refreshed table; no replacement was silently selected.")
                }
            }
            .navigationTitle("Observation detail").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $reviewObservation) { snapshot in DosePatternReviewSheet(model: model, night: snapshot) }
        }
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.timeZone = model.reportingTimeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .medium
        return formatter.string(from: date) + " • " + model.reportingTimeZone.identifier
    }
    private func timeRow(_ label: String, _ date: Date?) -> some View {
        LabeledContent(label, value: date.map(timestamp) ?? "Unavailable")
    }
    private func neighbor(_ delta: Int) -> String? {
        guard let id = observationID, let index = navigationIDs.firstIndex(of: id),
              navigationIDs.indices.contains(index + delta) else { return nil }
        return navigationIDs[index + delta]
    }
    private func move(_ delta: Int) { if let id = neighbor(delta) { select(id) } }
}
