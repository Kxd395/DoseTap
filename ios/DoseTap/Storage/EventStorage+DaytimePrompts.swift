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
}

extension SessionRepository {
    func daytimePrompts() throws -> DaytimePromptLedger { try storage.loadDaytimePrompts() }
    func saveDaytimePrompts(_ value: DaytimePromptLedger) throws { try storage.saveDaytimePrompts(value) }
    var daytimePromptSleepActive: Bool {
        if dose1Time != nil && wakeFinalTime == nil && !checkInCompleted { return true }
        let events = fetchRecentEvents(limit: 500).sorted { $0.timestamp < $1.timestamp }
        var nap = false, mainSleep = false
        for event in events {
            let type = event.eventType.lowercased().replacingOccurrences(of: " ", with: "_")
            if type == "nap_start" { nap = true }
            if type == "nap_end" { nap = false }
            if ["lights_out", "lightsout"].contains(type) { mainSleep = true }
            if ["wake_final", "wakefinal"].contains(type) { mainSleep = false }
        }
        return nap || (mainSleep && !checkInCompleted)
    }
}

@MainActor
extension SessionRepository {
    func daytimePromptContexts(for schedule: DaytimePromptSchedule, ledger: DaytimePromptLedger,
                               asOf now: Date) throws -> [DaytimePromptAnchorContext] {
        guard let rule = schedule.rule, rule.anchor != .clock,
              let zone = TimeZone(identifier: schedule.timeZone) else { return [] }
        let usesWork = rule.anchor == .shiftMidpoint || rule.anchor == .shiftBreak
        let work = usesWork ? try workContext() : nil
        let usesWake = rule.anchor == .mainWake || (usesWork && rule.offDayAnchor == .mainWake)
        let wakes = usesWake ? try daytimeMainWakeSources(asOf: now) : []
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
