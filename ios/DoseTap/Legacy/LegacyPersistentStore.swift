// Legacy/LegacyPersistentStore.swift
import CoreData
import os.log

private let legacyPersistentStoreLog = Logger(subsystem: "com.dosetap.app", category: "LegacyPersistentStore")

enum LegacyStoreKind { case persistent, inMemory }

final class LegacyPersistentStore {
    static let shared = LegacyPersistentStore()
    let container: NSPersistentContainer

    init(kind: LegacyStoreKind = .persistent) {
        container = NSPersistentContainer(name: "DoseTap") // matches .xcdatamodeld
        if case .inMemory = kind {
            let desc = NSPersistentStoreDescription()
            desc.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [desc]
        }
        container.loadPersistentStores { _, error in
            if let error {
                legacyPersistentStoreLog.error("Core Data error: \(error.localizedDescription, privacy: .public)")
                // Fallback to in-memory store to keep the app usable; do not crash
                let mem = NSPersistentStoreDescription()
                mem.type = NSInMemoryStoreType
                self.container.persistentStoreDescriptions = [mem]
                self.container.loadPersistentStores { _, memError in
                    if let memError {
                        legacyPersistentStoreLog.error("In-memory store fallback failed: \(memError.localizedDescription, privacy: .public)")
                        // Optionally present a recovery UI here.
                    } else {
                        legacyPersistentStoreLog.info("Fallback to in-memory Core Data store")
                    }
                }
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var viewContext: NSManagedObjectContext { container.viewContext }

    func saveContext(_ ctx: NSManagedObjectContext? = nil) {
        let context = ctx ?? viewContext
        if context.hasChanges {
            do { try context.save() } catch { legacyPersistentStoreLog.error("Save error: \(error.localizedDescription, privacy: .public)") }
        }
    }

    // Atomic wipe used by "Clear All Data" (two-step destructive)
    func wipeAll() throws {
        for entity in ["DoseEvent", "DoseSession", "InventorySnapshot"] {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let req = NSBatchDeleteRequest(fetchRequest: fetch)
            try container.persistentStoreCoordinator.execute(req, with: viewContext)
        }
        try viewContext.save()
    }
}
