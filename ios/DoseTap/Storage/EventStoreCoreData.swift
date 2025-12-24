// Storage/EventStoreCoreData.swift
import Foundation
import CoreData

enum EventWriteError: Error { case invalidState }

/// Bridge your existing DoseCore contract to Core Data.
/// Map CSV v1 fields 1:1 per SSOT.
final class EventStoreCoreData {
    private let ctx: NSManagedObjectContext
    init(context: NSManagedObjectContext = PersistentStore.shared.viewContext) { self.ctx = context }

    // CREATE
    func insertEvent(
        id: String,
        type: String,
        source: String,
        occurredAtUTC: Date,
        localTZ: String,
        doseSequence: Int?,
        note: String?
    ) {
        let e = DoseEvent(context: ctx)
        e.eventID = id
        e.eventType = type
        e.source = source
        e.occurredAtUTC = occurredAtUTC
        e.localTZ = localTZ
        if let seq = doseSequence { e.doseSequence = Int16(seq) }
        e.note = note
        PersistentStore.shared.saveContext(ctx)
    }

    // READ
    func allEvents() throws -> [DoseEvent] { try ctx.fetchEventsSorted() }

    // CLEAR (two-step confirmation handled in UI)
    func clearAll() throws { try PersistentStore.shared.wipeAll() }
}
