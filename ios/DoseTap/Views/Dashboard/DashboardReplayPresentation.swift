import Foundation
import Combine
import DoseCore

/// UI inspection state lives with the dashboard model, so changing routes does not discard choices.
struct DashboardReplayPresentation {
    var mode: DashboardReplayMode = .replay
    var alignment: DashboardReplaySnapshot.Alignment = .clock
    var preset: DashboardIntervalPreset = .dose1ToDose2
    var intervalMode = "By date"
    var comparedOutcome: ReplayComparedOutcome = .mainSleep
    var selectedBinLower: Double?
    struct DosePairChoice { var dose1ID: String?; var dose2ID: String? }
    var dosePairs: [String: DosePairChoice] = [:]
    var opportunityEndpoint: DashboardIntervalPreset = .dose2ToDeviceEnd
    var endpointSelections: [String: [DashboardReplayMarker]] = [:]
    var medicationLabels: [String: String] = [:]
    var selectionNotice: String?
    private(set) var hasOpened = false

    mutating func open(initialMode: DashboardReplayMode?) {
        guard !hasOpened else { return }
        if let initialMode { mode = initialMode }
        hasOpened = true
    }

    mutating func localRecordsChanged() {
        if !endpointSelections.isEmpty || !dosePairs.isEmpty {
            selectionNotice = "Local records changed. Select current dose, medication or nap endpoints again."
        }
        endpointSelections.removeAll(); dosePairs.removeAll()
    }
}

extension DashboardAnalyticsModel {
    func installReplaySourceObservation() {
        let observationChanges = $inspection.map(\.selectedObservationID).removeDuplicates().dropFirst().map { _ in () }
        let recordChanges = $nights.dropFirst().map { _ in () }
        let cutoffChanges = $reportingAsOf.removeDuplicates().dropFirst().map { _ in () }
        let zoneChanges = $reportingTimeZone.removeDuplicates().dropFirst().map { _ in () }
        let sourceChanges = $sleepSource.removeDuplicates().dropFirst().map { _ in () }
        Publishers.MergeMany([observationChanges.eraseToAnyPublisher(), recordChanges.eraseToAnyPublisher(),
            cutoffChanges.eraseToAnyPublisher(), zoneChanges.eraseToAnyPublisher(), sourceChanges.eraseToAnyPublisher()])
            .sink { [weak self] _ in self?.replayCoverageState.invalidate() }
            .store(in: &replaySourceSubscriptions)
        sessionRepo.sessionDidChange.sink { [weak self] _ in
            let invalidate: @MainActor () -> Void = { [weak self] in
                self?.localSnapshotRevision &+= 1
                self?.replayCoverageState.invalidate()
                self?.replayPresentation.localRecordsChanged()
            }
            if Thread.isMainThread { MainActor.assumeIsolated { invalidate() } }
            else { Task { @MainActor in invalidate() } }
        }.store(in: &replaySourceSubscriptions)
        providerAccess.changes.sink { [weak self] _ in
            if Thread.isMainThread { MainActor.assumeIsolated { self?.replayCoverageState.invalidate() } }
            else { Task { @MainActor [weak self] in self?.replayCoverageState.invalidate() } }
        }.store(in: &replaySourceSubscriptions)
    }
}
