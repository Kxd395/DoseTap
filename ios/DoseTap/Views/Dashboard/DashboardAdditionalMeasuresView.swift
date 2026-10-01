import SwiftUI
import DoseCore

enum DashboardAdditionalMeasure: String, CaseIterable {
    case summary = "Recorded summary", dosing = "Dose records", sleep = "Sleep outcomes"
    case whoop = "WHOOP recovery & biometrics", prior = "Prior period comparison"
    case trends = "Recorded trends", waking = "Reported waking methods", food = "Food & next-day diary"
    case lifestyle = "Lifestyle answers", morning = "Morning answers", stress = "Stress answers"
}

/// Preserves raw saved records while withholding aggregates without answer confirmation.
struct DashboardAdditionalMeasuresView: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @ObservedObject var core: DoseTapCore
    private var measure: DashboardAdditionalMeasure { model.additionalMeasure }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Recorded measure", selection: $model.additionalMeasure) {
                    ForEach(DashboardAdditionalMeasure.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("dashboard-additional-measure")
                DisclosureGroup("Source & reporting details") {
                Text("These recorded-measure panels use the whole selected reporting range. Shared night-comparison filters do not narrow these legacy summaries; use the focused comparison views for those filters.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Sleep comparison source: \(model.sleepSource.rawValue) · \(model.sleepSampleCount) available readings. Providers are not substituted.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Captured at \(stampUTC(model.reportingAsOf)) (UTC) · reporting timezone \(model.reportingTimeZone.identifier)")
                    .font(.caption).foregroundStyle(.secondary)
                }.font(.caption)
                if model.populatedNights.isEmpty {
                    Text("No recorded night measurements are available for this panel. Missing sleep and unanswered questions are not zero values.")
                } else { panel }
            }.padding().padding(.bottom, 90)
        }
    }
    @ViewBuilder private var panel: some View {
        switch measure {
        case .summary: DashboardExecutiveSummaryCard(model: model, core: core)
        case .dosing: DashboardDosingSnapshotCard(model: model)
        case .sleep: providerSleep
        case .whoop:
            if model.whoopNights.isEmpty { Text("No WHOOP records in this range. Check the connection in Settings, then refresh or choose a wider range.") }
            else { DashboardWHOOPCard(model: model) }
        case .prior: priorComparison
        case .trends: DashboardTrendChartsCard(model: model)
        case .waking: DashboardWakeComparisonCard(model: model)
        case .food, .lifestyle, .morning, .stress: rawSavedAnswers
        }
    }
    private var providerSleep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep Outcomes").font(.headline)
            Text("Provider main-episode aggregates; complete reviewed-night coverage is not established.").font(.caption)
            Text("Apple Health: \(minutes(model.averageAppleHealthSleepMinutes)) · n=\(model.populatedNights.compactMap(\.appleHealthSleepMinutes).count)")
            Text("WHOOP: \(minutes(model.averageWhoopSleepMinutes)) · n=\(model.populatedNights.compactMap(\.whoopSleepMinutes).count)")
            Text("Time to first wake · Health: \(minutes(model.averageTTFW))")
            Text("Avg wakes · Health: \(number(model.averageWakeCount))")
            Text("First-wake timing n=\(model.populatedNights.compactMap(\.ttfwMinutes).count); wake counts n=\(model.populatedNights.compactMap(\.wakeCount).count). Source: Apple Health main episode.").font(.caption)
            Text("Bathroom logs: \(model.bathroomLogCount). Logs do not measure duration.")
            Text("Saved sleep-quality and readiness answers need review; their unconfirmed averages are withheld.")
                .accessibilityIdentifier("dashboard-withheld-morning-averages")
            Text("Nap Nights: \(model.napNightCount); average recorded timer duration per nap night: \(minutes(model.averageNapMinutes)). Timer records remain separate from provider sleep and reported asleep estimates.")
            contextLink
        }
    }
    private var priorComparison: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Period Comparison").font(.headline)
            if model.periodComparison.isEmpty {
                Text("A comparison needs matching measurements in this range and the preceding period. All Time has no preceding comparison period.")
            } else {
                Text("vs. Prior \(model.selectedRange.label)")
                Text("Rate changes are percentage points; other changes are relative percent. Missing measurements remain unavailable; increases are not automatically improvements.").font(.caption)
                ForEach(model.periodComparison.filter { $0.metricName != "Sleep Quality" }, id: \.metricName) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.metricName).font(.subheadline.bold())
                        Text("Current: \(comparisonValue(row.current, metric: row.metricName)) · Prior: \(comparisonValue(row.prior, metric: row.metricName))")
                        Text(row.delta.map { String(format: "%+.0f", $0) + " " + row.deltaUnit }
                             ?? (row.isNew ? "From a zero baseline" : "Change unavailable"))
                    }
                }
            }
            Text("Unconfirmed saved sleep-quality comparisons are withheld. Original answers remain available for review.")
            contextLink
        }
    }
    private var rawHeading: String {
        switch measure {
        case .food: return "Food timing & next-day diary"
        case .lifestyle: return "Lifestyle Factors"
        case .morning: return "Mood & Symptoms"
        case .stress: return "Stress Trends"
        default: return measure.rawValue
        }
    }
    private var rawSavedAnswers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rawHeading).font(.headline)
            Text("Needs review: saved questionnaire values may include legacy defaults or carried-forward answers. Per-item confirmation and actual assessment time were not collected. No percentage, mean, absence, or paired outcome is inferred from these values.")
                .accessibilityIdentifier("dashboard-saved-answer-needs-review")
            contextLink
            Text("Original saved records").font(.headline)
            ForEach(model.populatedNights.filter { $0.preSleepLog != nil || $0.morningCheckIn != nil }) { night in
                DisclosureGroup(night.sessionDate + " · " + night.id + " · Needs review") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Select this observation") { model.inspection.selectedObservationID = night.id }
                            .accessibilityIdentifier("dashboard-raw-select-" + night.id)
                        if model.inspection.selectedObservationID == night.id {
                            Text("Selected observation: " + night.id)
                                .accessibilityIdentifier("dashboard-raw-selected-" + night.id)
                        }
                        if let record = night.morningCheckIn {
                            Text("Morning record ID: \(record.id); saved session ID: \(record.sessionId)")
                            Text("Recorded timestamp: \(stampUTC(record.timestamp)) (UTC). Actual assessment time unavailable.")
                            Text("Saved sleep quality: \(record.sleepQuality); feeling rested: \(record.feelRested)")
                            Text("Saved grogginess: \(record.grogginess); sleep inertia: \(record.sleepInertiaDuration)")
                            Text("Saved mental clarity: \(record.mentalClarity); readiness: \(record.readinessForDay)")
                            Text("Saved mood: \(record.mood); anxiety: \(record.anxietyLevel); stress: \(record.stressLevel.map(String.init) ?? "Not stored")")
                            Text("Saved dream recall: \(record.dreamRecall)")
                            Text("Stored physical-symptom flag: \(record.hasPhysicalSymptoms.description); respiratory-symptom flag: \(record.hasRespiratorySymptoms.description)")
                            Text("Stored sleep-paralysis flag: \(record.hadSleepParalysis.description); hallucination flag: \(record.hadHallucinations.description); automatic-behavior flag: \(record.hadAutomaticBehavior.description)")
                            Text("Stored fell-out-of-bed flag: \(record.fellOutOfBed.description); confusion-on-waking flag: \(record.hadConfusionOnWaking.description)")
                            Text("Stored sleep-therapy flag: \(record.usedSleepTherapy.description); sleep-environment flag: \(record.hasSleepEnvironment.description)")
                            Text("A stored false flag does not establish a confirmed No answer or an absence.").font(.caption)
                            rawText("Physical symptom detail", record.physicalSymptomsJson)
                            rawText("Respiratory symptom detail", record.respiratorySymptomsJson)
                            rawText("Stress context", record.stressContextJson)
                            rawText("Sleep therapy", record.sleepTherapyJson)
                            rawText("Sleep environment", record.sleepEnvironmentJson)
                            rawText("Timing context", record.timingContextJson)
                            rawText("Saved note", record.notes)
                        }
                        if let record = night.preSleepLog {
                            Text("Pre-sleep record ID: \(record.id); saved session ID: \(record.sessionId)")
                            Text("Stored timestamp: \(record.createdAtUtc); completion: \(record.completionState)")
                            if let answers = record.answers {
                                Text(verbatim: encodedAnswers(answers)).font(.caption.monospaced()).textSelection(.enabled)
                            } else { Text("No decoded pre-sleep answers available. The original record remains stored.") }
                        }
                    }.padding(.vertical, 8)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("dashboard-raw-answer-" + night.id)
            }
            if !model.populatedNights.contains(where: { $0.preSleepLog != nil || $0.morningCheckIn != nil }) {
                Text("No saved questionnaire records in this range. Unanswered questions remain unavailable.")
            }
        }
    }
    private var contextLink: some View {
        NavigationLink("Open Context & Morning Outcomes") { ContextMorningOutcomesView(model: model) }
            .accessibilityIdentifier("dashboard-reviewed-context-open")
    }
    @ViewBuilder private func rawText(_ title: String, _ value: String?) -> some View {
        if let value { Text(title + ": " + value).font(.caption).textSelection(.enabled) }
    }
    private func encodedAnswers(_ answers: PreSleepLogAnswers) -> String {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let value = String(data: try encoder.encode(answers), encoding: .utf8) else {
                return "Saved pre-sleep answers could not be displayed as UTF-8. The original record has not been changed."
            }
            return value
        } catch { return "Saved pre-sleep answers could not be formatted. The original record has not been changed." }
    }
    private func stampUTC(_ date: Date) -> String {
        guard date.timeIntervalSince1970.isFinite else { return "Invalid stored timestamp; needs review" }
        return AppFormatters.iso8601.string(from: date)
    }
    private func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Unavailable" }; return String(format: "%.1f", value)
    }
    private func minutes(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Unavailable" }; return number(value) + " minutes"
    }
    private func comparisonValue(_ value: Double?, metric: String) -> String {
        let unit = metric == "Recorded On-Time %" || metric == "Recovery" ? "%" : metric == "HRV" ? " ms" : " minutes"
        return value.map { number($0) + unit } ?? "Unavailable"
    }
}
