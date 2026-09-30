import SwiftUI

enum DashboardPage: String, CaseIterable, Identifiable {
    case timing, intervals, opportunity, medications, coverage, sleepNaps, dosePatterns, work, context, daytime, physician, data, additional
    var id: String { rawValue }
    var requiresNightEvidence: Bool {
        switch self {
        case .timing, .intervals, .opportunity, .coverage, .dosePatterns, .work, .context, .additional: return true
        case .medications, .sleepNaps, .daytime, .physician, .data: return false
        }
    }
    var replayMode: DashboardReplayMode? {
        switch self {
        case .timing: return .replay
        case .intervals: return .intervals
        case .opportunity: return .opportunity
        case .medications: return .medication
        case .coverage: return .coverage
        default: return nil
        }
    }
    static func page(for mode: DashboardReplayMode) -> DashboardPage {
        switch mode {
        case .replay: return .timing
        case .intervals: return .intervals
        case .opportunity: return .opportunity
        case .medication: return .medications
        case .coverage: return .coverage
        }
    }
    var title: String {
        switch self {
        case .timing: return "Session Replay"
        case .intervals: return "Interval Explorer"
        case .opportunity: return "Sleep Opportunity"
        case .medications: return "Medication Explorer"
        case .coverage: return "Reviewed Sleep Coverage"
        case .sleepNaps: return "Sleep & Naps"
        case .dosePatterns: return "Sleep & Dose Pattern"
        case .work: return "Work Block & Sleep"
        case .context: return "Context & Morning Outcomes"
        case .daytime: return "Daytime Diary"
        case .physician: return "Physician Review"
        case .data: return "Review Data"
        case .additional: return "Other Recorded Measures"
        }
    }
    var accessibilityID: String {
        switch self {
        case .timing: return "dashboard-replay-open"
        case .intervals: return "dashboard-intervals-open"
        case .opportunity: return "dashboard-opportunity-open"
        case .medications: return "dashboard-medications-open"
        case .coverage: return "dashboard-coverage-open"
        case .sleepNaps: return "dashboard-sleep-naps-open"
        case .dosePatterns: return "dashboard-dose-pattern-open"
        case .work: return "dashboard-work-block"
        case .context: return "dashboard-context-open"
        case .daytime: return "dashboard-daytime-open"
        case .physician: return "dashboard-physician-open"
        case .data: return "dashboard-data-open"
        case .additional: return "dashboard-additional-open"
        }
    }
}

struct DashboardPagePicker: View {
    @Binding var selection: DashboardPage
    var body: some View {
        Menu {
            ForEach(DashboardPage.allCases) { page in
                Button {
                    selection = page
                } label: {
                    if page == selection { Label(page.title, systemImage: "checkmark") }
                    else { Text(page.title) }
                }.accessibilityIdentifier(page.accessibilityID)
            }
        } label: {
            Label(selection.title, systemImage: "rectangle.3.group")
                .frame(maxWidth: .infinity, minHeight: 44)
        }.accessibilityIdentifier("dashboard-view-picker")
    }
}
