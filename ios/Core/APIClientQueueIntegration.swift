import Foundation

/// High level façade combining APIClient with an OfflineQueue for resilient dosing actions.
@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
public actor DosingService {
    public enum Action: Codable, Sendable, Equatable {
        case takeDose(type: String, at: Date)
        case skipDose(sequence: Int, reason: String?)
        case snooze(minutes: Int)
        case logEvent(name: String, at: Date)
        // exportAnalytics intentionally excluded from queue; treated as immediate only
    }

    private let client: APIClient
    private let queue: OfflineQueue
    private let limiter: EventRateLimiter

    public init(client: APIClient, queue: OfflineQueue, limiter: EventRateLimiter = EventRateLimiter.default) {
        self.client = client
        self.queue = queue
        self.limiter = limiter
    }

    // Attempts the action immediately; on failure it is wrapped & queued.
    public func perform(_ action: Action) async {
        do {
            try await send(action)
        } catch {
            await enqueue(action)
        }
    }

    private func enqueue(_ action: Action) async {
        let task = AnyOfflineQueueTask {
            try await self.send(action)
        }
        await queue.enqueue(task)
    }

    private func send(_ action: Action) async throws {
        switch action {
        case .takeDose(let type, let date): try await client.takeDose(type: type, at: date)
        case .skipDose(let sequence, let reason): try await client.skipDose(sequence: sequence, reason: reason)
        case .snooze(let minutes): try await client.snooze(minutes: minutes)
        case .logEvent(let name, let date):
            guard await limiter.shouldAllow(event: name, at: date) else { return }
            try await client.logEvent(name, at: date)
        }
    }

    public func flushPending() async { await queue.flush() }
}
