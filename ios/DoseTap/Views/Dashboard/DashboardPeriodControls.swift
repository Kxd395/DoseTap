import SwiftUI
import DoseCore

/// Reporting selection is separate from provider retrieval and never writes medication.
struct DashboardPeriodControls: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @State private var reviewingCustom = false
    var body: some View {
        Menu {
            Picker("Reporting period", selection: $model.selectedRange) {
                ForEach(DashboardReportingRange.presetCases) { range in
                    Text(range.label).tag(range)
                }
                Text("Since last completed visit").tag(DashboardReportingRange.sinceCompletedVisit)
                if model.selectedRange == .custom { Text("Custom period").tag(DashboardReportingRange.custom) }
            }
            Button("Custom dates…") { reviewingCustom = true }
        } label: {
            Label(model.selectedRange.rawValue, systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }.accessibilityLabel(model.selectedRange.label).accessibilityIdentifier("dashboard-range-picker")
            .sheet(isPresented: $reviewingCustom) { DashboardCustomPeriodSheet(model: model) }
    }
}

private struct DashboardCustomPeriodSheet: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @State private var error: String?
    private let reviewTimeZone: TimeZone
    init(model: DashboardAnalyticsModel) {
        self.model = model
        let zone = model.timeZone(), now = model.now()
        reviewTimeZone = zone
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        if case let .custom(lower, upper) = model.customReportingRange {
            _start = State(initialValue: lower); _end = State(initialValue: upper)
        } else {
            _start = State(initialValue: calendar.date(byAdding: .day, value: -28, to: now) ?? now)
            _end = State(initialValue: now)
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Reviewed reporting bounds") {
                    DatePicker("Start inclusive", selection: $start)
                        .accessibilityIdentifier("dashboard-custom-start")
                    DatePicker("End exclusive", selection: $end, in: ...model.now())
                        .accessibilityIdentifier("dashboard-custom-end")
                    Text("Timezone: \(reviewTimeZone.identifier). Dashboard charts include whole treatment nights with a 6 p.m. rollover. Boundary nights may extend outside these instants.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.environment(\.timeZone, reviewTimeZone)
                .navigationTitle("Custom reporting period")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            do {
                                try model.applyCustomReportingRange(start: start, endExclusive: end, timeZone: reviewTimeZone)
                                dismiss()
                            } catch { self.error = model.reportingPeriodError(error) }
                        }.accessibilityIdentifier("dashboard-custom-apply")
                    }
                }
        }
    }
}

extension DashboardAnalyticsModel {
    func resolveReportingWindow(asOf: Date, timeZone: TimeZone) throws -> DashboardReportingWindow {
        let period: PhysicianReportPeriod?
        if selectedRange == .sinceCompletedVisit {
            period = try PhysicianReportPeriod.resolve(.sinceCompletedVisit,
                ledger: sessionRepo.physicianVisits(), asOf: asOf, timeZone: timeZone)
        } else if selectedRange == .custom {
            guard let customReportingRange else { throw PhysicianReviewError.invalidPeriod }
            period = try PhysicianReportPeriod.resolve(customReportingRange, ledger: .init(), asOf: asOf, timeZone: timeZone)
        } else { period = nil }
        guard let window = selectedRange.window(asOf: asOf, timeZone: timeZone, reviewedPeriod: period) else {
            throw PhysicianReviewError.invalidPeriod
        }
        return window
    }

    func applyCustomReportingRange(start: Date, endExclusive: Date, timeZone: TimeZone) throws {
        guard timeZone == self.timeZone() else { throw PhysicianReviewError.invalidDate }
        let requested = PhysicianReportRange.custom(start: start, endExclusive: endExclusive)
        let asOf = now()
        let period = try PhysicianReportPeriod.resolve(requested, ledger: .init(), asOf: asOf, timeZone: timeZone)
        guard DashboardReportingRange.custom.window(asOf: asOf, timeZone: timeZone, reviewedPeriod: period) != nil else {
            throw PhysicianReviewError.invalidPeriod
        }
        let alreadyCustom = selectedRange == .custom
        customReportingRange = requested
        selectedRange = .custom
        if alreadyCustom { refresh() }
    }

    func reportingPeriodError(_ error: Error) -> String {
        if error as? PhysicianReviewError == .missingCompletedVisit {
            return "No completed visit is recorded. Add a visit that actually occurred in Physician review, or choose another period."
        }
        if error as? PhysicianReviewError == .invalidPeriod || error as? PhysicianReviewError == .invalidDate {
            return "The reporting bounds could not be used. Start must precede the end, the end cannot be in the future, and the timezone must still match. Review the dates and try again."
        }
        return "Completed-visit history could not be read. No substitute start date was used. Try Refresh again or choose another period."
    }
}
