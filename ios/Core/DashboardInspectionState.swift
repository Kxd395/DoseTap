import Foundation

/// Presentation-only state shared by dashboard routes. It never writes clinical records.
public struct DashboardInspectionState: Equatable, Sendable {
    public enum SelectionStatus: String, Sendable {
        case none, visible, filtered, unavailable
        public var explanation: String? {
            switch self {
            case .none, .visible: return nil
            case .filtered: return "The selected observation is outside this view's current range or filters. Reset filters or choose another observation explicitly."
            case .unavailable: return "The selected observation is no longer available in the current data. Its selection is retained; refresh or choose another observation explicitly."
            }
        }
    }
    public var selectedObservationID: String?
    public var dosePatternFilter: DashboardDosePattern.Pattern?
    public var workPhaseFilter: WorkPhase?
    public var workContextBasis: WorkContextBasis = .planned
    public var contextStratumID: String?
    public var includePartialMetrics = false
    public init() {}

    public func selectionStatus(visibleIDs: [String], knownIDs: [String]) -> SelectionStatus {
        guard let selectedObservationID else { return .none }
        if visibleIDs.contains(selectedObservationID) { return .visible }
        return knownIDs.contains(selectedObservationID) ? .filtered : .unavailable
    }
    public mutating func resetFilters() {
        dosePatternFilter = nil
        workPhaseFilter = nil
        contextStratumID = nil
        includePartialMetrics = false
    }
}
