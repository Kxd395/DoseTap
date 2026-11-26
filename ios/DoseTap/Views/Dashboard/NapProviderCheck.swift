import Foundation
import Combine
import DoseCore
import os.log

@MainActor
final class NapProviderCheck: ObservableObject {
    @Published private(set) var evidence: SleepEvidenceResolution?
    @Published private(set) var checkedAt: Date?
    @Published private(set) var message = "Check Apple Health for this explicitly reviewed nap window."
    @Published private(set) var busy = false
    private var generation = 0
    func invalidate() {
        generation += 1; evidence = nil; checkedAt = nil; busy = false
        message = "Coverage has not been checked for the current records."
    }
    func check(episode: NapEpisode, clock: () -> Date, current: () throws -> NapEpisode?,
               allowed: () -> Bool, query: (Date, Date) async throws -> SleepEvidenceResolution?) async {
        invalidate(); let ticket = generation
        guard !Task.isCancelled, episode.isValid, episode.duplicateOf == nil,
              let start = episode.start, let end = episode.end, start < end, end <= clock(), allowed() else {
            message = "Review an ended nap window and enable Apple Health before checking."; return
        }
        busy = true
        defer { if generation == ticket { busy = false } }
        do {
            guard try current()?.evidenceKey == episode.evidenceKey else {
                message = "Nap records changed. Reopen the review before checking."; return
            }
            let result = try await query(start, end)
            guard generation == ticket, !Task.isCancelled else { return }
            guard allowed() else { invalidate(); message = "Provider access changed. Previous evidence was cleared."; return }
            guard try current()?.evidenceKey == episode.evidenceKey else {
                message = "Nap records changed during the check. Check again after reviewing them."; return
            }
            guard let result, result.coverage.start == start, result.coverage.end == end, result.rejectedSampleCount == 0 else {
                message = "The provider did not return a valid result for this window."; return
            }
            evidence = result; checkedAt = clock()
            message = "Apple Health: \(result.status.rawValue). Unmeasured and conflicting time is not awake time."
        } catch {
            guard generation == ticket else { return }
            dashboardLogger.warning("Nap coverage check failed; no provider value published")
            message = "Apple Health or local records could not be read. No measured nap value was published."
        }
    }
}
