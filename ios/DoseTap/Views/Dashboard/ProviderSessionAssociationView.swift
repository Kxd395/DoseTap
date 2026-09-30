import SwiftUI

struct ProviderSessionAssociationView: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @State private var review: DashboardProviderMatchReview?
    @State private var unlink: UnlinkReview?
    @State private var failure: String?
    @State private var confirmationText = ""

    private struct UnlinkReview: Identifiable {
        let id: String
        let revision: String
        let description: String
    }
    private var unmatched: [DashboardNightAggregate] { model.nights.filter { $0.unmatchedProviderEvidence != nil } }


    var body: some View {
        List {
            Section {
                Text("Choose which treatment session belongs to a provider sleep episode. Matching does not record a dose, change sleep measurements, or confirm how many doses were taken.")
                Text("A shared date is only a candidate. Review the source, observed times and session before confirming.")
                    .font(.footnote).foregroundStyle(.secondary)
                if model.isLoading { ProgressView("Refreshing evidence…") }
                if let message = model.errorMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if let failure { Text(failure).foregroundStyle(.red).accessibilityIdentifier("provider-match-error") }
            }
            Section("Sleep awaiting a match") {
                if unmatched.isEmpty { Text("No unmatched provider sleep is loaded.").foregroundStyle(.secondary) }
                ForEach(unmatched) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        episode(row)
                        let candidates = model.nights.filter {
                            $0.sessionDate == row.sessionDate && $0.sessionID != nil && !$0.identityNeedsReview
                        }
                        if candidates.isEmpty {
                            Text("No resolved local session for this treatment date. Sleep stays available independently.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Menu("Choose treatment session") {
                                ForEach(candidates) { session in
                                    Button(sessionLabel(session)) {
                                        do {
                                            review = try model.providerMatchReview(providerRowID: row.id, sessionID: session.sessionID!)
                                            confirmationText = "\(sourceLabel(row)) · \(bounds(row))\nMatch to \(sessionLabel(session))?"
                                            failure = nil
                                        } catch { showFailure() }
                                    }
                                }
                            }
                            .disabled(!sourceIsCurrent(row))
                            .accessibilityIdentifier("provider-match-choose-\(row.id)")
                            if !sourceIsCurrent(row) {
                                Text("Refresh this provider successfully before matching. Retained or unavailable data cannot create a new match.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }
            Section("Saved relationships") {
                if model.savedProviderAssociations.isEmpty { Text("No saved relationships.").foregroundStyle(.secondary) }
                ForEach(model.savedProviderAssociations, id: \.episodeID) { match in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(match.provider == "apple-health" ? "Apple Health" : "WHOOP").font(.headline)
                        Text("\(match.sessionDate) · Session \(match.sessionID.suffix(8))")
                        Text("Stored relationship; changed or unavailable evidence stays separate until reviewed.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Remove this sleep match", role: .destructive) {
                            unlink = UnlinkReview(id: match.episodeID, revision: match.revision,
                                description: "\(match.sessionDate) · Session \(match.sessionID.suffix(8))")
                        }.accessibilityIdentifier("provider-match-remove-\(match.episodeID)")
                    }
                }
            }
        }
        .navigationTitle("Match provider sleep")
        .accessibilityIdentifier("provider-association-screen")
        .toolbar { Button("Refresh") { failure = nil; model.refresh() }.disabled(model.isLoading) }
        .confirmationDialog("Confirm sleep match", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } }), presenting: review) { value in
            Button("Save explicit match") {
                do { try model.saveProviderAssociation(value); failure = nil }
                catch { showFailure() }
                review = nil
            }
            Button("Cancel", role: .cancel) { review = nil }
        } message: { _ in Text(confirmationText) }
        .confirmationDialog("Remove this relationship?", isPresented: Binding(get: { unlink != nil }, set: { if !$0 { unlink = nil } }), presenting: unlink) { value in
            Button("Remove match", role: .destructive) {
                do { try model.removeProviderAssociation(providerEpisodeID: value.id, expectedRevision: value.revision); failure = nil }
                catch { showFailure() }
                unlink = nil
            }
            Button("Cancel", role: .cancel) { unlink = nil }
        } message: { value in Text("Remove the provider relationship for \(value.description)? Medication and measured sleep remain unchanged.") }
    }

    @ViewBuilder private func episode(_ row: DashboardNightAggregate) -> some View {
        Text(sourceLabel(row)).font(.headline)
        Text(bounds(row))
        Text("Treatment date: \(row.sessionDate) · \(model.reportingTimeZone.identifier)").font(.footnote)
        Text("No confirmed treatment-session match.").font(.footnote).foregroundStyle(.secondary)
    }
    private func sourceLabel(_ row: DashboardNightAggregate) -> String {
        row.healthSummary.map { "Apple Health · \($0.source)" } ?? "WHOOP"
    }
    private func sourceIsCurrent(_ row: DashboardNightAggregate) -> Bool {
        model.providerSnapshotIsCurrent(row.healthSummary != nil ? .health : .whoop)
    }
    private func formatted(_ date: Date?) -> String {
        guard let date else { return "not supplied" }
        let formatter = DateFormatter(); formatter.timeZone = model.reportingTimeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    private func bounds(_ row: DashboardNightAggregate) -> String {
        if let health = row.healthSummary {
            let start = health.recordedIntervals.map(\.start).min() ?? health.bedTime ?? health.sleepOnset
            let end = health.recordedIntervals.map(\.end).max() ?? health.observationEnd ?? health.finalWake
            return "Observed bounds: \(formatted(start)) – \(formatted(end))"
        }
        return "Episode start: \(formatted(row.whoopSummary?.date)). End time is not supplied by this summary."
    }
    private func sessionLabel(_ row: DashboardNightAggregate) -> String {
        "\(row.sessionDate) · Session \(row.sessionID?.suffix(8) ?? "unknown") · D1 \(formatted(row.dose1Time)) · D2 \(formatted(row.dose2Time))"
    }
    private func showFailure() {
        failure = "The source, session or saved relationship changed, or the save could not finish. Refresh and review the match again."
    }
}
