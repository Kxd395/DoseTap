import Foundation
import SwiftUI

/// Enhanced EventStoreAdapter that queues events for optional sync
class EventStoreWithSync: ObservableObject {
    private let eventStore: EventStoreAdapter
    private let offlineQueue: OfflineQueue
    
    init(eventStore: EventStoreAdapter, offlineQueue: OfflineQueue) {
        self.eventStore = eventStore
        self.offlineQueue = offlineQueue
    }
    
    func log(_ event: DoseEvent) async {
        // Log to local store first
        await eventStore.log(event)
        
        // Queue for potential sync
        do {
            let eventData = try JSONEncoder().encode(event)
            let action = QueuedAction(
                type: .eventLog,
                payload: eventData,
                idempotencyKey: event.idempotencyKey
            )
            await offlineQueue.enqueue(action)
        } catch {
            print("Failed to queue event for sync: \(error)")
        }
        
        await MainActor.run {
            objectWillChange.send()
        }
    }
    
    func undoLast() async -> DoseEvent? {
        let undone = await eventStore.undoLast()
        await MainActor.run {
            objectWillChange.send()
        }
        return undone
    }
    
    func getRecent(_ count: Int) async -> [DoseEvent] {
        return await eventStore.getRecent(count)
    }
    
    /// Access to the offline queue for sync management
    var syncQueue: OfflineQueue { offlineQueue }
}
