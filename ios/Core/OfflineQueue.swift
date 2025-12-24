import Foundation

public protocol OfflineQueueTask {
    var id: UUID { get }
    var createdAt: Date { get }
    var attempts: Int { get set }
    mutating func markAttempt()
    func execute() async throws
}

@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
public struct AnyOfflineQueueTask: OfflineQueueTask {
    public let id: UUID
    public let createdAt: Date
    public var attempts: Int
    private let exec: () async throws -> Void
    private let mark: (inout Int) -> Void = { attempts in attempts += 1 }

    public init(id: UUID = UUID(), createdAt: Date = Date(), attempts: Int = 0, execute: @escaping () async throws -> Void) {
        self.id = id
        self.createdAt = createdAt
        self.attempts = attempts
        self.exec = execute
    }
    public mutating func markAttempt() { attempts += 1 }
    public func execute() async throws { try await exec() }
}

@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
public protocol OfflineQueue: AnyObject, Sendable {
    func enqueue(_ task: AnyOfflineQueueTask) async
    func flush() async
    func pending() async -> [AnyOfflineQueueTask]
}

@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
public actor InMemoryOfflineQueue: OfflineQueue {
    public struct Config {
        public var maxRetries: Int = 3
        public var backoffBaseSeconds: Double = 2
        public init() {}
    }

    private var tasks: [AnyOfflineQueueTask] = []
    private let isOnline: () -> Bool
    private let config: Config
    private let now: () -> Date

    public init(config: Config = Config(), isOnline: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        self.config = config
        self.isOnline = isOnline
        self.now = now
    }

    public func enqueue(_ task: AnyOfflineQueueTask) async { tasks.append(task) }

    public func pending() async -> [AnyOfflineQueueTask] { tasks }

    public func flush() async {
        guard isOnline() else { return }
        while !tasks.isEmpty {
            var task = tasks.removeFirst()
            task.markAttempt()
            do {
                try await task.execute()
            } catch {
                if task.attempts < config.maxRetries {
                    // Exponential backoff before retry
                    let delaySeconds = pow(config.backoffBaseSeconds, Double(task.attempts))
                    let delayNanoseconds = UInt64(delaySeconds * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                    
                    var retryTask = task
                    retryTask.attempts += 1
                    tasks.append(retryTask)
                }
            }
        }
    }
}
