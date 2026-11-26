import Foundation
import DoseCore

/// Navigation state only; provider evidence and clinical records never live here.
struct DashboardNapInspection: Equatable {
    private(set) var selectedEpisodeID: String?
    private(set) var selectedDay: Date?
    private(set) var calendarPage = 0

    mutating func initializeDayIfNeeded(_ date: Date) {
        guard selectedDay == nil else { return }
        selectDay(date)
    }
    mutating func selectDay(_ date: Date) {
        guard !NapEpisode.day(date, "GMT").isEmpty else { return }
        selectedDay = date
    }
    mutating func selectEpisode(_ id: String) {
        guard !id.isEmpty, id.count <= 300 else { return }
        selectedEpisodeID = id
    }
    mutating func clearSelection() { selectedEpisodeID = nil }
    mutating func setCalendarPage(_ value: Int) { calendarPage = max(0, value) }
    func visiblePage(dayCount: Int) -> Int {
        min(calendarPage, (max(1, dayCount) - 1) / 14)
    }
    func selectionStatus(visibleIDs: [String], knownIDs: [String]) -> DashboardInspectionState.SelectionStatus {
        var state = DashboardInspectionState()
        state.selectedObservationID = selectedEpisodeID
        return state.selectionStatus(visibleIDs: visibleIDs, knownIDs: knownIDs)
    }
}
