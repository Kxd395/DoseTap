// Storage/JSONMigrator.swift
import Foundation

struct JSONMigrator {
    struct JSONDoseEvent: Decodable {
        let event_id: String, event_type: String, source: String
        let occurred_at_utc: Date, local_tz: String
        let dose_sequence: Int?
        let note: String?
    }
    struct JSONDoseSession: Decodable {
        let session_id: String, started_utc: Date
        let ended_utc: Date?
        let bedtime_local: String?
        let window_target_min: Int?
        let window_actual_min: Int?
        let adherence_flag: String?
        let whoop_recovery: Int?
        let avg_hr: Double?
        let sleep_efficiency: Double?
        let note: String?
    }

    static func runIfNeeded(baseURL: URL) {
        let flagKey = "didMigrateToCoreData"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        let fm = FileManager.default
        let eventsURL = baseURL.appendingPathComponent("dose_events.json")
        let sessionsURL = baseURL.appendingPathComponent("dose_sessions.json")
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let store = EventStoreCoreData()

        if fm.fileExists(atPath: eventsURL.path),
           let data = try? Data(contentsOf: eventsURL),
           let items = try? dec.decode([JSONDoseEvent].self, from: data) {
            for i in items {
                store.insertEvent(
                    id: i.event_id,
                    type: i.event_type,
                    source: i.source,
                    occurredAtUTC: i.occurred_at_utc,
                    localTZ: i.local_tz,
                    doseSequence: i.dose_sequence,
                    note: i.note
                )
            }
        }

        if fm.fileExists(atPath: sessionsURL.path),
           let data = try? Data(contentsOf: sessionsURL),
           let sessions = try? dec.decode([JSONDoseSession].self, from: data) {
            let ctx = PersistentStore.shared.viewContext
            for s in sessions {
                let mo = DoseSession(context: ctx)
                mo.sessionID = s.session_id
                mo.startedUTC = s.started_utc
                mo.endedUTC = s.ended_utc
                mo.bedtimeLocal = s.bedtime_local
                if let v = s.window_target_min { mo.windowTargetMin = Int16(v) }
                if let v = s.window_actual_min { mo.windowActualMin = Int16(v) }
                if let v = s.whoop_recovery { mo.whoopRecovery = Int16(v) }
                if let v = s.avg_hr { mo.avgHR = v }
                if let v = s.sleep_efficiency { mo.sleepEfficiency = v }
                mo.adherenceFlag = s.adherence_flag
                mo.note = s.note
            }
            PersistentStore.shared.saveContext(ctx)
        }

        UserDefaults.standard.set(true, forKey: flagKey)
    }
}
