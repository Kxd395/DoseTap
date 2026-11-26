import SwiftUI

struct DashboardReportedNightContext: Codable, Equatable {
    let type: NightType
    let firstOff: Bool
    let recordID: String
    let reportedAt: Date
    var label: String { type.displayText + (firstOff ? " · First night off after work block" : "") }
    static func project(night: DashboardNightAggregate, asOf: Date) -> Self? {
        guard !night.identityNeedsReview, let session = night.sessionID, !session.isEmpty,
              let morning = night.morningCheckIn, !morning.id.isEmpty,
              morning.sessionId == session, morning.sessionDate == night.sessionDate,
              asOf.timeIntervalSince1970.isFinite, morning.timestamp.timeIntervalSince1970.isFinite,
              morning.timestamp <= asOf, let timing = morning.resolvedTimingContext,
              let raw = timing.nightType, let type = NightType(rawValue: raw) else { return nil }
        return .init(type: type, firstOff: timing.firstNightOffAfterWorkBlock,
                     recordID: morning.id, reportedAt: morning.timestamp)
    }
}

enum DashboardTimingContextBasis: String, CaseIterable {
    case reported = "Morning check-in", reviewed = "Reviewed shifts"
}

extension ReplayComparisonRow {
    func matchesTimingContext(_ presentation: DashboardReplayPresentation) -> Bool {
        if presentation.timingContextBasis == .reported {
            return presentation.reportedNightFilter.contains(reportedNight?.type ?? .unsure)
        }
        return presentation.timingWorkFilter == nil || workBeforeSleep == presentation.timingWorkFilter
    }
    func timingContextLabel(_ basis: DashboardTimingContextBasis) -> String {
        basis == .reported ? "Morning report: " + (reportedNight?.label ?? "Unknown · no usable check-in for this session")
            : "Reviewed work before sleep: " + workBeforeSleep.rawValue
    }
}

struct DashboardTimingContextControls: View {
    @ObservedObject var model: DashboardAnalyticsModel
    @State private var choosingNightTypes = false
    private var selectionLabel: String {
        let selected = model.replayPresentation.reportedNightFilter
        if selected.count == NightType.allCases.count { return "All night types" }
        if selected.isEmpty { return "No night types selected" }
        return NightType.allCases.filter { selected.contains($0) }.map {
            $0 == .unsure ? "Unsure / unknown" : $0.displayText
        }.joined(separator: ", ")
    }
    var body: some View {
        VStack(alignment: .leading) {
            if model.inspection.workPhaseFilter != nil {
                Text("The shared work-phase filter uses reviewed shifts; morning night type is a separate reported context.").font(.caption)
            }
            Picker("Chart context", selection: $model.replayPresentation.timingContextBasis) {
                ForEach(DashboardTimingContextBasis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("dashboard-timing-context-basis")
            if model.replayPresentation.timingContextBasis == .reported {
                Button { choosingNightTypes = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Night types", systemImage: "line.3.horizontal.decrease")
                        Text(selectionLabel).font(.caption).multilineTextAlignment(.leading)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("dashboard-reported-night-filter")
                .accessibilityHint("Choose one or more morning night types to show")
                if model.replayPresentation.reportedNightFilter.isEmpty {
                    Text("Choose at least one night type to show nights on the chart.")
                        .font(.caption).accessibilityIdentifier("dashboard-night-types-empty")
                }
            } else {
                Picker("Reviewed work before sleep", selection: $model.replayPresentation.timingWorkFilter) {
                    Text("All days").tag(DashboardWorkBeforeSleep?.none)
                    ForEach(DashboardWorkBeforeSleep.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }.pickerStyle(.menu).accessibilityIdentifier("dashboard-timing-work")
            }
        }
        .sheet(isPresented: $choosingNightTypes) {
            NavigationStack {
                List {
                    Section {
                        Button("Select all") { model.replayPresentation.reportedNightFilter = Set(NightType.allCases) }
                            .accessibilityIdentifier("dashboard-night-types-all")
                        Button("Clear all") { model.replayPresentation.reportedNightFilter.removeAll() }
                            .accessibilityIdentifier("dashboard-night-types-clear")
                    }
                    Section {
                        ForEach(NightType.allCases, id: \.self) { type in
                            let selected = model.replayPresentation.reportedNightFilter.contains(type)
                            Button {
                                if selected { model.replayPresentation.reportedNightFilter.remove(type) }
                                else { model.replayPresentation.reportedNightFilter.insert(type) }
                            } label: {
                                HStack {
                                    Text(type == .unsure ? "Unsure / unknown" : type.displayText)
                                    Spacer()
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                }.contentShape(Rectangle())
                            }
                            .accessibilityValue(selected ? "Selected" : "Not selected")
                            .accessibilityAddTraits(selected ? [.isSelected] : [])
                            .accessibilityIdentifier("dashboard-night-type-" + type.rawValue)
                        }
                    } footer: {
                        Text("Show nights matching any selected type. Unsure / unknown includes nights without a usable morning check-in.")
                    }
                }
                .navigationTitle("Night types")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { choosingNightTypes = false }
                            .accessibilityIdentifier("dashboard-night-types-done")
                    }
                }
            }
        }
    }
}
