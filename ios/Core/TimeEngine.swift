import Foundation

public struct TimeEngineConfig {
    public var minIntervalMin: Int = 150
    public var maxIntervalMin: Int = 240
    public var targetIntervalMin: Int = 165
    public init() {}
}

public enum SimpleDoseWindowState: Equatable { case noDose1, waitingForTarget(remaining: TimeInterval), targetWindowOpen(elapsed: TimeInterval, remainingToMax: TimeInterval), windowExceeded }

public struct TimeEngine {
    public let config: TimeEngineConfig
    public let now: () -> Date
    public init(config: TimeEngineConfig = TimeEngineConfig(), now: @escaping () -> Date = { Date() }) { self.config = config; self.now = now }

    public func state(dose1At: Date?) -> SimpleDoseWindowState {
        guard let d1 = dose1At else { return .noDose1 }
        let elapsed = now().timeIntervalSince(d1)
        let maxS = Double(config.maxIntervalMin) * 60
        let targetS = Double(config.targetIntervalMin) * 60
        if elapsed < targetS { return .waitingForTarget(remaining: targetS - elapsed) }
        if elapsed <= maxS { return .targetWindowOpen(elapsed: elapsed, remainingToMax: maxS - elapsed) }
        return .windowExceeded
    }
}
