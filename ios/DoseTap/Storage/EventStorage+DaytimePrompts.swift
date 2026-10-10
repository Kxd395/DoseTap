import Foundation
import SQLite3
import DoseCore

extension EventStorage {
    func loadDaytimePrompts() throws -> DaytimePromptLedger {
        guard databaseInitializationFailure == nil, db != nil else { throw DaytimeDiaryError.unreadable }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM daytime_prompt_state WHERE id = 1", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw DaytimeDiaryError.unreadable }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return DaytimePromptLedger() }
        guard result == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw DaytimeDiaryError.unreadable }
        let value = try DaytimePromptLedger.decodePayload(Data(String(cString: text).utf8))
        try value.validate(); return value
    }
    func saveDaytimePrompts(_ value: DaytimePromptLedger) throws {
        try value.validate()
        guard databaseInitializationFailure == nil, db != nil else { throw DaytimeDiaryError.notCommitted }
        let payload = String(decoding: try value.encodedPayload(), as: UTF8.self)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO daytime_prompt_state (id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw DaytimeDiaryError.notCommitted }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, payload, -1, SQLITE_TRANSIENT) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw DaytimeDiaryError.notCommitted }
    }
    func daytimeSleepTransitions(asOf: Date) throws -> [(type: String, at: Date)] {
        try readExportRows("""
            SELECT lower(replace(event_type, ' ', '_')), timestamp FROM sleep_events
            WHERE lower(replace(event_type, ' ', '_')) IN
                ('nap_start', 'nap_end', 'lights_out', 'lightsout', 'wake_final', 'wakefinal')
            """) { statement in
            func text(_ column: Int32) throws -> String {
                guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
                      let bytes = sqlite3_column_text(statement, column),
                      let value = String(bytes: UnsafeBufferPointer(start: bytes,
                        count: Int(sqlite3_column_bytes(statement, column))), encoding: .utf8),
                      !value.contains("\0") else { throw DaytimeDiaryError.unreadable }
                return value
            }
            let type = try text(0), raw = try text(1)
            guard let at = AppFormatters.iso8601Fractional.date(from: raw) ?? AppFormatters.iso8601.date(from: raw),
                  at.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.unreadable }
            return (type: type, at: at)
        }.filter { $0.at <= asOf }
    }
}

struct DaytimeSleepSuppressionReason: Equatable {
    enum Kind: String { case activeDoseSession, nap, mainSleep }
    let kind: Kind
    let startedAt: Date
}

struct DaytimeSleepEvidenceSnapshot {
    let wakes: [DaytimeMainWakeSource]
    let suppressionReasons: [DaytimeSleepSuppressionReason]
    let capturedAt: Date
    var sleepActive: Bool { !suppressionReasons.isEmpty }
}

extension SessionRepository {
    func daytimePrompts() throws -> DaytimePromptLedger { try storage.loadDaytimePrompts() }
    func saveDaytimePrompts(_ value: DaytimePromptLedger) throws { try storage.saveDaytimePrompts(value) }
    var daytimePromptSleepActive: Bool {
        (try? daytimePromptSleepActive(asOf: clock())) ?? true
    }
    func daytimePromptSleepActive(asOf: Date) throws -> Bool {
        guard asOf.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.invalid }
        if dose1Time != nil && wakeFinalTime == nil && !checkInCompleted { return true }
        return try daytimeSleepEvidence(asOf: asOf).sleepActive
    }
    func daytimeSleepEvidence(asOf: Date) throws -> DaytimeSleepEvidenceSnapshot {
        guard asOf.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.invalid }
        do {
            return try storage.withDaytimeEvidenceRead {
                let events = try storage.daytimeSleepTransitions(asOf: asOf)
                let wakes = try storage.daytimeMainWakeSources(asOf: asOf)
                func latest(_ types: Set<String>) -> Date? {
                    events.filter { types.contains($0.type) }.map(\.at).max()
                }
                func active(start: Date?, end: Date?) -> Bool {
                    guard let start else { return false }
                    return end.map { start >= $0 } ?? true
                }
                let finalWake = [latest(["wake_final", "wakefinal"]), wakes.map(\.at).max()].compactMap { $0 }.max()
                var reasons: [DaytimeSleepSuppressionReason] = []
                if let dose1Time, wakeFinalTime == nil && !checkInCompleted {
                    reasons.append(.init(kind: .activeDoseSession, startedAt: dose1Time))
                }
                if let napStart = latest(["nap_start"]), active(start: napStart, end: latest(["nap_end"])) {
                    reasons.append(.init(kind: .nap, startedAt: napStart))
                }
                if let lightsOut = latest(["lights_out", "lightsout"]),
                   active(start: lightsOut, end: finalWake) && !checkInCompleted {
                    reasons.append(.init(kind: .mainSleep, startedAt: lightsOut))
                }
                return DaytimeSleepEvidenceSnapshot(wakes: wakes, suppressionReasons: reasons, capturedAt: asOf)
            }
        } catch {
            throw DaytimeDiaryError.unreadable
        }
    }
}

@MainActor
extension SessionRepository {
    func daytimePromptContexts(for schedule: DaytimePromptSchedule, ledger: DaytimePromptLedger,
                               asOf now: Date, wakeSources: [DaytimeMainWakeSource]? = nil) throws -> [DaytimePromptAnchorContext] {
        guard let rule = schedule.rule, rule.anchor != .clock,
              let zone = TimeZone(identifier: schedule.timeZone) else { return [] }
        let usesWork = rule.randomizedWake != nil || rule.anchor == .shiftMidpoint || rule.anchor == .shiftBreak
        let work = usesWork ? try workContext() : nil
        let usesWake = rule.anchor == .mainWake || (usesWork && rule.offDayAnchor == .mainWake)
        let wakes = usesWake ? try (wakeSources ?? daytimeMainWakeSources(asOf: now)) : []
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return try (-1...7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { return nil }
            let key = DaytimePromptRule.dayKey(day, timeZone: schedule.timeZone)
            let resolved = work?.resolvedWorkDate(key, timeZoneIdentifier: schedule.timeZone, asOf: now)
            let originalID = ledger.prompts.first {
                $0.scheduleID == schedule.id && $0.anchorDayKey == key && $0.anchor?.kind == .mainWake
            }?.anchor?.sourceID
            let candidates = wakes.filter { source in
                if let originalID { return source.id == originalID }
                return DaytimePromptRule.dayKey(source.at, timeZone: schedule.timeZone) == key
            }
            let wake = candidates.count == 1 ? try candidates.first.map {
                try DaytimeAnchorSource(id: $0.id, revision: $0.revision, at: $0.at)
            } : nil
            var shift: DaytimeAnchorSource?, pause: DaytimeAnchorSource?
            if let resolved, let id = resolved.shiftSourceID, let start = resolved.scheduledStart, let end = resolved.scheduledEnd {
                shift = try DaytimeAnchorSource(id: id.uuidString, revision: resolved.documentRevision.uuidString, at: start, endAt: end)
            }
            if let resolved, let id = resolved.breakSourceID, let at = resolved.plannedBreakAt {
                pause = try DaytimeAnchorSource(id: id.uuidString, revision: resolved.documentRevision.uuidString, at: at)
            }
            return DaytimePromptAnchorContext(dayKey: key, timeZone: schedule.timeZone, working: resolved?.plannedWorking,
                mainWake: wake, shift: shift, plannedBreak: pause, workSourceID: resolved?.plannedSourceID?.uuidString,
                workRevision: resolved?.documentRevision.uuidString)
        }
    }
}
