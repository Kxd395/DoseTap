import SwiftUI
import DoseCore

struct DosePatternReviewSheet: View {
    @ObservedObject var model: DashboardAnalyticsModel
    let night: DashboardNightAggregate
    let expectedRevision: UUID?
    let fingerprint: String?
    let unansweredOnly: Bool
    @State private var count: Int
    @State private var plan: Int
    @State private var omission: Int
    @State private var reason = ""
    @State private var error: String?
    @State private var saving = false
    @State private var pendingReview: DashboardDoseReview?
    @Environment(\.dismiss) private var dismiss

    init(model: DashboardAnalyticsModel, night: DashboardNightAggregate, unansweredOnly: Bool = false) {
        self.model = model; self.night = night
        self.unansweredOnly = unansweredOnly
        expectedRevision = night.doseReviewLedger?.current?.revisionID
        fingerprint = night.reviewFingerprint
        _count = State(initialValue: night.doseReview?.confirmedCount ?? -1)
        _plan = State(initialValue: night.doseReview?.historicalPlanCount ?? -1)
        _omission = State(initialValue: night.doseReview?.secondNotTaken.map { $0 ? 1 : 0 } ?? -1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Review this observation") {
                    Text(night.sessionDate + " • " + night.dosePattern.pattern.label)
                    Text("These are patient reports about this observation. Saving does not add or correct administrations, change alarms, or close your sleep session.")
                    Text("\(night.dosePattern.reportedCount) reported administrations in the current evidence; count completeness and exact times are separate.")
                    if night.doseReviewLedger?.current != nil && night.doseReview == nil {
                        Text("Source evidence changed after the previous review. Confirm it again; the old report remains in history.")
                    }
                    if !model.doseReviewReadReady {
                        Text("Refresh the dashboard successfully before saving this review. Source records must be read completely.")
                    }
                }
                if !unansweredOnly || night.doseReview?.confirmedCount == nil {
                    Section("Complete administration count") {
                        Picker("How many administrations were reported taken?", selection: $count) {
                            Text("Unanswered / unsure").tag(-1)
                            Text("None — complete report").tag(0)
                            Text("One — complete report").tag(1)
                            Text("Two — complete report").tag(2)
                        }.accessibilityIdentifier("dose-review-count")
                        Text("Choose only if the count is complete. Two reported administrations with an unknown time remain two; tablet quantity is not administration count. Other/conflicting records remain available for review.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Historical plan and Dose 2 outcome") {
                    if !unansweredOnly || night.doseReview?.historicalPlanCount == nil {
                        Picker("Plan recorded for this night", selection: $plan) {
                            Text("Unknown / no plan report").tag(-1)
                            Text("One administration planned").tag(1)
                            Text("Two administrations planned").tag(2)
                        }
                    }
                    if !unansweredOnly || (night.doseReview?.secondNotTaken == nil && night.doseReview?.historicalPlanCount != 1
                        && night.dose2Time == nil && !night.dose2Skipped) {
                        Picker("Was expected Dose 2 explicitly not taken?", selection: $omission) {
                            Text("Unanswered / unsure").tag(-1)
                            Text("Yes — not taken").tag(1)
                            Text("No — Dose 2 was not omitted").tag(0)
                        }.accessibilityIdentifier("dose-review-omission")
                    }
                    Text("The plan is patient-reported, not a verified prescription. If a dose was taken but is missing from the ledger, use medication reconciliation or History to enter its actual occurrence; this review cannot invent a time or amount.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(expectedRevision == nil ? "Optional review note" : "Correction reason — required") {
                    TextField("Reason for this report or correction", text: $reason, axis: .vertical)
                        .lineLimit(2...5).accessibilityIdentifier("dose-review-reason")
                    Text("Up to 500 characters. Prior reviews are retained.").font(.caption)
                }
                if let error { Section { Text(error).foregroundStyle(.orange).accessibilityIdentifier("dose-review-error") } }
            }
            .navigationTitle("Dose history review").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save review", action: save).disabled(saving || fingerprint == nil || night.identityNeedsReview || !model.doseReviewReadReady)
                        .accessibilityIdentifier("dose-review-save")
                }
            }
        }
    }

    private func save() {
        guard let fingerprint else { error = "Source evidence cannot be reviewed. Refresh and resolve the source records first."; return }
        let note = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectedRevision == nil || !note.isEmpty else { error = "Enter a reason before saving a correction."; return }
        saving = true; defer { saving = false }
        let reportedCount = count < 0 ? nil : count, historicalPlan = plan < 0 ? nil : plan
        let notTaken: Bool? = omission < 0 ? nil : omission == 1
        let review: DashboardDoseReview
        if let pending = pendingReview, pending.confirmedCount == reportedCount,
           pending.historicalPlanCount == historicalPlan, pending.secondNotTaken == notTaken, pending.reason == note {
            review = pending
        } else {
            review = DashboardDoseReview(observationID: night.id, sourceFingerprint: fingerprint,
                confirmedCount: reportedCount, historicalPlanCount: historicalPlan,
                secondNotTaken: notTaken, recordedAt: model.now(), reason: note)
            pendingReview = review
        }
        do {
            try model.saveDoseHistoryReview(review: review, observationID: night.id, expectedRevision: expectedRevision)
            dismiss()
        } catch {
            dashboardLogger.error("Dose-history review save failed; source records were preserved and the form remains editable.")
            self.error = error.localizedDescription
        }
    }
}
