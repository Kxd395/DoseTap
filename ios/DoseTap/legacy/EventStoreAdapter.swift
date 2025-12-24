import Foundation
import Combine
import SwiftUI

@MainActor
@available(iOS 15.0, macOS 12.0, *)
final class EventStoreAdapter: ObservableObject {
    // Shared instance for global access
    static let shared = EventStoreAdapter(shared: JSONEventStore())
    
    let shared: EventStoreProtocol
    @Published private(set) var recent: [DoseEvent] = []

    init(shared: EventStoreProtocol) {
        self.shared = shared
        Task { await refresh() }
    }

    func log(type: DoseEventType, meta: [String:String] = [:]) async {
        _ = await shared.append(DoseEvent(type: type, meta: meta))
        await refresh()
    }

    func undoLast() async -> DoseEvent? {
        let undone = await shared.undoLast()
        await refresh()
        return undone
    }
    
    // Add delete functionality by marking events as deleted
    func delete(_ event: DoseEvent) async -> Bool {
        // Mark as deleted by appending a new version with deleted metadata
        let deletedEvent = DoseEvent(
            id: event.id,
            type: event.type,
            utcTs: event.utcTs,
            localOffsetSec: event.localOffsetSec,
            idempotencyKey: "\(event.idempotencyKey)_deleted_\(Date().timeIntervalSince1970)",
            meta: event.meta.merging(["deleted": "true", "original_id": event.id.uuidString]) { _, new in new }
        )
        _ = await shared.append(deletedEvent)
        await refresh()
        return true
    }

    func refresh() async {
        let all = await shared.all()
        // Filter out deleted events from recent display
        let nonDeleted = all.filter { $0.meta["deleted"] != "true" }
        self.recent = Array(nonDeleted.suffix(10)).reversed()
    }
}
