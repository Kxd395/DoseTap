import SwiftUI
import DoseCore

struct ReportContentsView: View {
    let snapshot: CloudDashboardSnapshot
    private let labels: [DashboardDataset: String] = [
        .sessions: "Sleep sessions", .doseEvents: "Nighttime dose events", .quickLogs: "Quick logs, including bathroom",
        .preSleep: "Pre-sleep check-ins", .morning: "Morning check-ins", .normalizedAnswers: "Questionnaire source answers",
        .medicationEntries: "Medication entries", .presetVersions: "Saved medication versions", .administrations: "Confirmed preset administrations",
        .amendments: "Administration amendments", .daytimeDiary: "Daytime diary source", .reviewedSleepWindows: "Reviewed sleep-window source",
        .inventory: "Medication inventory", .symptoms: "Symptoms and body maps", .workSchedule: "Work and wake schedule",
        .appleHealth: "Apple Health measurements", .whoop: "WHOOP measurements"
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("What arrived from your iPhone", systemImage: "checklist").font(.title.bold())
            Text("This is the inventory of the saved report, across all available dates. Source rows can include revisions or repeat across sections; they are not counts of distinct nights, symptoms or completed assessments.")
                .foregroundStyle(.secondary)
            ForEach(snapshot.sections, id: \.dataset) { section in
                HStack(alignment: .top) {
                    Image(systemName: section.rowCount != nil ? "checkmark.circle" : "info.circle")
                        .foregroundStyle(section.rowCount != nil ? .teal : .orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(labels[section.dataset] ?? section.dataset.rawValue).font(.headline)
                        if section.unavailableReason != nil { Text("Not included in this nearby report").foregroundStyle(.secondary) }
                        else if section.notCollectedBySource == true { Text("Not collected by this source").foregroundStyle(.secondary) }
                        else { Text("\(section.rowCount ?? 0) source rows retained").foregroundStyle(.secondary) }
                    }
                    Spacer()
                }.padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Sleep averages, stages, dose-to-sleep and recovery trends require provider evidence that this report does not yet carry. Questionnaire source is retained, but answer-aware trend calculations need separate validation.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
