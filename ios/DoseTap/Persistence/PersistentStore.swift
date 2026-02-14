// Persistence/PersistentStore.swift
import CoreData
import os.log

private let persistentStoreLog = Logger(subsystem: "com.dosetap.app", category: "PersistentStore")

enum StoreKind { case persistent, inMemory }

final class PersistentStore {
    static let shared = PersistentStore()
    let container: NSPersistentContainer

    init(kind: StoreKind = .persistent) {
        container = NSPersistentContainer(name: "DoseTap") // matches .xcdatamodeld
        if case .inMemory = kind {
            let desc = NSPersistentStoreDescription()
            desc.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [desc]
        }
        container.loadPersistentStores { _, error in
            if let error {
                persistentStoreLog.error("Core Data error: \(error.localizedDescription, privacy: .public)")
                // Fallback to in-memory store to keep the app usable; do not crash
                let mem = NSPersistentStoreDescription()
                mem.type = NSInMemoryStoreType
                self.container.persistentStoreDescriptions = [mem]
                self.container.loadPersistentStores { _, memError in
                    if let memError {
                        persistentStoreLog.error("In-memory store fallback failed: \(memError.localizedDescription, privacy: .public)")
                        // Optionally present a recovery UI here.
                    } else {
                        persistentStoreLog.info("Fallback to in-memory Core Data store")
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
            do { try context.save() } catch { persistentStoreLog.error("Save error: \(error.localizedDescription, privacy: .public)") }
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
