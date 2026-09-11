import Foundation
import Combine
import DoseCore

/// Exact local inputs from one SQLite read snapshot. Never persisted or exported.
struct ReviewedNightSleepInput: Equatable {
    let sessionID: String
    let window: ReviewedSleepWindow?
    let outcomeJSON: String?
    let doses: [DoseCore.StoredDoseEvent]
    let otherWindows: [ReviewedSleepWindow]
    let naps: [ReviewedWindowAssessment.NapMarker]

    func assessment(now: Date) -> ReviewedWindowAssessment {
        .calculate(window: window, sessionID: sessionID, doses: doses, otherWindows: otherWindows, naps: naps, now: now)
    }
}

struct ReviewedNightSleepResult {
    enum Status { case available, partial, conflict, unavailable, missingWindow, needsReview, disabled, stale, unreadable, failed, cancelled }
    let status: Status
    var window: ReviewedSleepWindow?
    var assessment: ReviewedWindowAssessment?
    var evidence: SleepEvidenceResolution?
    var checkedAt: Date?
    var projection: ReviewedNightSleepProjection?
    var doseSleepMetrics: ReviewedDoseSleepMetrics?
    let derivationVersion = "reviewed_night_provider_check_v1"

    var explanation: String {
        switch status {
        case .available: return "Apple Health coverage is complete for this reviewed window."
        case .partial: return "Apple Health coverage is partial. Unmeasured time is not counted as sleep or awake."
        case .conflict: return "Apple Health observations conflict. Conflicting time remains unmeasured."
        case .unavailable: return "No classified sleep or awake observations are available. Check the date range, watch data and Health permissions."
        case .missingWindow: return "Save a reviewed night window before checking Apple Health coverage."
        case .needsReview: return "Review the local window, dose and nap warnings before checking coverage."
        case .disabled: return "Apple Health is disabled in DoseTap Settings. No coverage result is being used."
        case .stale: return "Local records changed during the check. Check again for current results."
        case .unreadable: return "Local records could not be read completely. No sleep result was used."
        case .failed: return "Apple Health coverage could not be checked. Try again; no records were changed."
        case .cancelled: return "The coverage check was cancelled."
        }
    }
}

@MainActor
enum ReviewedNightSleepLoader {
    static func load(read: () -> ReviewedNightSleepInput?, clock: () -> Date, isEnabled: () -> Bool,
                     query: (Date, Date) async throws -> SleepEvidenceResolution?) async -> ReviewedNightSleepResult {
        guard !Task.isCancelled else { return .init(status: .cancelled) }
        guard let input = read() else { return .init(status: .unreadable) }
        guard let window = input.window else { return .init(status: .missingWindow) }
        let assessment = input.assessment(now: clock())
        guard assessment.status == .checked else { return .init(status: .needsReview, window: window, assessment: assessment) }
        guard isEnabled() else { return .init(status: .disabled) }
        do {
            let evidence = try await query(window.start, window.end)
            guard !Task.isCancelled else { return .init(status: .cancelled) }
            guard isEnabled() else { return .init(status: .disabled) }
            guard let current = read() else { return .init(status: .unreadable) }
            guard current == input else { return .init(status: .stale) }
            let checkedAt = clock()
            let currentAssessment = current.assessment(now: checkedAt)
            guard currentAssessment.status == .checked else {
                return .init(status: .needsReview, window: window, assessment: currentAssessment)
            }
            guard let evidence, evidence.coverage.start == window.start, evidence.coverage.end == window.end,
                  evidence.rejectedSampleCount == 0,
                  let projection = ReviewedNightSleepProjection.calculate(window: window, evidence: evidence,
                                                                          generatedAt: checkedAt)
            else { return .init(status: .failed) }
            let status: ReviewedNightSleepResult.Status
            switch evidence.status {
            case .available: status = .available
            case .partial: status = .partial
            case .unavailable: status = .unavailable
            case .conflict: status = .conflict
            }
            return .init(status: status, window: window, assessment: currentAssessment, evidence: evidence,
                         checkedAt: checkedAt, projection: projection,
                         doseSleepMetrics: .calculate(projection: projection, doses: current.doses))
        } catch is CancellationError { return .init(status: .cancelled) }
        catch { return .init(status: Task.isCancelled ? .cancelled : .failed) }
    }
}

extension SessionRepository {
    func reviewedNightSleep(sessionDate: String) async -> ReviewedNightSleepResult {
        await ReviewedNightSleepLoader.load(
            read: { self.storage.reviewedNightSleepInput(sessionDate: sessionDate, now: self.clock()) },
            clock: clock, isEnabled: { UserSettingsManager.shared.healthKitEnabled },
            query: { try await HealthKitService.shared.fetchSleepEvidence(from: $0, to: $1) })
    }
}

/// Selected-night UI state. Late provider responses cannot restore invalidated evidence.
@MainActor
final class TimelineDoseSleepModel: ObservableObject {
    @Published private(set) var result: ReviewedNightSleepResult?
    @Published private(set) var isLoading = false
    private var generation = 0

    func invalidate() {
        generation += 1
        result = nil
        isLoading = false
    }

    func refresh(sessionDate: String, query: (String) async -> ReviewedNightSleepResult) async {
        guard !Task.isCancelled else { return }
        invalidate()
        let request = generation
        isLoading = true
        let next = await query(sessionDate)
        guard generation == request else { return }
        guard !Task.isCancelled else { invalidate(); return }
        result = next
        isLoading = false
    }
}

/// A display association from the existing calculator, never a second timing algorithm.
struct TimelineDose2Episode {
    let start: Date
    let dose: Date
    let returned: Date?
    let observedEnd: Date
    let samples: [SleepEvidenceSample]

    init?(result: ReviewedNightSleepResult) {
        guard let metrics = result.doseSleepMetrics,
              let start = metrics.awakeningToDose2.start,
              let dose = metrics.awakeningToDose2.end else { return nil }
        self.start = start
        self.dose = dose
        returned = metrics.dose2ToSleep.end
        observedEnd = metrics.dose2ToSleep.end ?? result.projection?.bands.first {
            $0.state == .awake && $0.start == start && $0.end >= dose
        }?.end ?? dose
        // Include the samples on both sides of exact transitions so boundaries are reviewable.
        let intervalEnd = observedEnd
        samples = (result.evidence?.samples ?? []).filter {
            $0.end >= start && $0.start <= intervalEnd
        }.sorted { $0.start < $1.start }
    }
}

extension TimelineDose2Episode {
    func matchingEvents(_ events: [StoredSleepEvent]) -> [StoredSleepEvent] {
        events.filter { $0.timestamp >= start && $0.timestamp <= observedEnd }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
