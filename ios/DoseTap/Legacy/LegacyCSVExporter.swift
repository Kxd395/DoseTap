// Legacy/LegacyCSVExporter.swift
import Foundation
import CoreData

enum LegacyCSVExporter {
    // events.csv — SSOT CSV v1 header & order
    static func exportEventsCSV(to url: URL, ctx: NSManagedObjectContext = LegacyPersistentStore.shared.viewContext) throws {
        let header = "event_id,event_type,source,occurred_at_utc,local_tz,dose_sequence,note\n"
        var out = header
        for e in try fetchEventsSorted(in: ctx) {
            let id = e.eventID ?? ""
            let et = e.eventType ?? ""
            let src = e.source ?? ""
            let ts = AppFormatters.iso8601.string(from: e.occurredAtUTC ?? Date())
            let tz = e.localTZ ?? ""
            let seq = e.value(forKey: "doseSequence") as? Int16
            let seqStr = seq != nil ? String(seq!) : ""
            let note = (e.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            out += "\(id),\(et),\(src),\(ts),\(tz),\(seqStr),\"\(note)\"\n"
        }
        try out.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // sessions.csv v1 — aligns with macOS dashboard & SSOT proposal
    static func exportSessionsCSV(to url: URL, ctx: NSManagedObjectContext = LegacyPersistentStore.shared.viewContext) throws {
        let header = "session_id,started_utc,ended_utc,bedtime_local,window_target_min,window_actual_min,adherence_flag,whoop_recovery,avg_hr,sleep_efficiency,note\n"
        var out = header
        let req = DoseSession.fetchRequest()
        req.sortDescriptors = [NSSortDescriptor(key: "startedUTC", ascending: true)]
        for s in try ctx.fetch(req) {
            let sid = s.sessionID ?? ""
            let start = AppFormatters.iso8601.string(from: s.startedUTC ?? Date())
            let end = s.endedUTC.map(AppFormatters.iso8601.string(from:)) ?? ""
            let bl = s.bedtimeLocal ?? ""
            let target = s.value(forKey: "windowTargetMin") as? Int16
            let actual = s.value(forKey: "windowActualMin") as? Int16
            let adh = s.adherenceFlag ?? ""
            let rec = s.value(forKey: "whoopRecovery") as? Int16
            let hr = s.avgHR
            let eff = s.sleepEfficiency
            let note = (s.note ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            out += "\(sid),\(start),\(end),\(bl),\(target ?? 0),\(actual ?? 0),\(adh),\(rec ?? 0),\(hr ?? 0),\(eff ?? 0),\"\(note)\"\n"
        }
        try out.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func fetchEventsSorted(in context: NSManagedObjectContext) throws -> [DoseEvent] {
        let request = DoseEvent.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "occurredAtUTC", ascending: true)]
        return try context.fetch(request)
    }
}
