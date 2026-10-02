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
            return presentation.reportedNightFilter == nil || (reportedNight?.type ?? .unsure) == presentation.reportedNightFilter
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
    var body: some View {
        VStack(alignment: .leading) {
            if model.inspection.workPhaseFilter != nil {
                Text("The shared work-phase filter uses reviewed shifts; morning night type is a separate reported context.").font(.caption)
            }
            Picker("Chart context", selection: $model.replayPresentation.timingContextBasis) {
                ForEach(DashboardTimingContextBasis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("dashboard-timing-context-basis")
            if model.replayPresentation.timingContextBasis == .reported {
                Picker("Reported night type", selection: $model.replayPresentation.reportedNightFilter) {
                    Text("All night types").tag(NightType?.none)
                    ForEach(NightType.allCases, id: \.self) { Text($0 == .unsure ? "Unsure / unknown" : $0.displayText).tag(Optional($0)) }
                }.pickerStyle(.menu).accessibilityIdentifier("dashboard-reported-night-filter")
            } else {
                Picker("Reviewed work before sleep", selection: $model.replayPresentation.timingWorkFilter) {
                    Text("All days").tag(DashboardWorkBeforeSleep?.none)
                    ForEach(DashboardWorkBeforeSleep.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }.pickerStyle(.menu).accessibilityIdentifier("dashboard-timing-work")
            }
        }
    }
}
