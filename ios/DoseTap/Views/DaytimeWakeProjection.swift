import Foundation
import DoseCore

@MainActor
extension SessionRepository {
    /// Original source identity is authoritative; read failures never select a replacement wake.
    func daytimeWakeContexts(observations: [DaytimeCheckIn], asOf: Date) throws -> [UUID: DaytimeWakeContext] {
        guard asOf.timeIntervalSince1970.isFinite, Set(observations.map(\.id)).count == observations.count else { throw DaytimeDiaryError.invalid }
        let evidence: [DaytimeWakeEvidence]?
        do {
            evidence = try daytimeMainWakeSources(asOf: asOf).map {
                try DaytimeWakeEvidence(reference: DaytimeWakeReference(sourceID: $0.id, revision: $0.revision, at: $0.at), recordedAt: $0.recordedAt)
            }
        } catch { evidence = nil; storageLog.error("Main-wake comparison source unavailable; no substitute selected") }
        let prompts: DaytimePromptLedger?
        do { prompts = observations.contains(where: { $0.promptID != nil }) ? try daytimePrompts() : nil }
        catch { prompts = nil; storageLog.error("Daytime prompt comparison source unavailable; no substitute selected") }
        return try Dictionary(uniqueKeysWithValues: observations.map { row in
            var references: [DaytimeWakeReference]? = []
            do {
                for link in row.sourceLinks ?? [] where link.kind == .mainWake {
                    guard let at = link.start else { throw DaytimeDiaryError.invalid }
                    references?.append(try DaytimeWakeReference(sourceID: link.sourceID, revision: link.evidenceKey, at: at))
                }
                if let promptID = row.promptID {
                    guard let prompt = prompts?.prompts.first(where: { $0.id == promptID }),
                          let schedule = prompts?.schedules.first(where: { $0.id == prompt.scheduleID }),
                          schedule.createdAt <= row.recordedAt, schedule.createdAt <= asOf,
                          row.samplingProtocolID.map({ $0 == prompt.scheduleID }) ?? true else { throw DaytimeDiaryError.unreadable }
                    if let rule = schedule.rule, rule.anchor != .clock, prompt.anchor == nil { throw DaytimeDiaryError.unreadable }
                    if let anchor = prompt.anchor, anchor.kind == .mainWake {
                        guard let id = anchor.sourceID, let revision = anchor.sourceRevision, let at = anchor.sourceAt else { throw DaytimeDiaryError.unreadable }
                        references?.append(try DaytimeWakeReference(sourceID: id, revision: revision, at: at))
                    }
                }
            } catch { references = nil }
            return (row.id, try DaytimeWakeContext(observation: row, references: references, sources: evidence, asOf: asOf))
        })
    }
}
