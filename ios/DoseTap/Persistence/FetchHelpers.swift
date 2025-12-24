// Persistence/FetchHelpers.swift
import CoreData

extension NSManagedObjectContext {
    func fetchEventsSorted() throws -> [DoseEvent] {
        let r = DoseEvent.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(key: "occurredAtUTC", ascending: true)]
        return try fetch(r)
    }
    func fetchSessionsSorted() throws -> [DoseSession] {
        let r = DoseSession.fetchRequest()
        r.sortDescriptors = [NSSortDescriptor(key: "startedUTC", ascending: true)]
        return try fetch(r)
    }
}
