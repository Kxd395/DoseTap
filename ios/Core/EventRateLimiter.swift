import Foundation

public actor EventRateLimiter {
    private var last: [String: Date]
    private let cooldowns: [String: TimeInterval]
    private let now: () -> Date

    public init(last: [String: Date] = [:], cooldowns: [String: TimeInterval], now: @escaping () -> Date = Date.init) {
        self.last = last
        self.cooldowns = cooldowns
        self.now = now
    }

    public func register(event: String, at date: Date? = nil) {
        last[event] = date ?? now()
    }

    public func shouldAllow(event: String, at date: Date? = nil) -> Bool {
        let current = date ?? now()
        guard let cd = cooldowns[event] else { return true }
        if let previous = last[event], current.timeIntervalSince(previous) < cd { return false }
        last[event] = current
        return true
    }
    
    /// Check if event is allowed without registering it
    public func canLog(event: String, at date: Date? = nil) -> Bool {
        let current = date ?? now()
        guard let cd = cooldowns[event] else { return true }
        if let previous = last[event], current.timeIntervalSince(previous) < cd { return false }
        return true
    }
    
    /// Get remaining cooldown time for an event (0 if ready)
    public func remainingCooldown(for event: String, at date: Date? = nil) -> TimeInterval {
        let current = date ?? now()
        guard let cd = cooldowns[event], let previous = last[event] else { return 0 }
        let elapsed = current.timeIntervalSince(previous)
        return max(0, cd - elapsed)
    }
    
    /// Reset cooldown for a specific event
    public func reset(event: String) {
        last.removeValue(forKey: event)
    }
    
    /// Reset all cooldowns
    public func resetAll() {
        last.removeAll()
    }

    /// Default limiter with all sleep event cooldowns
    public static var `default`: EventRateLimiter {
        EventRateLimiter(cooldowns: SleepEventType.allCooldowns)
    }
    
    /// Limiter with only legacy bathroom cooldown (for backward compatibility)
    public static var legacy: EventRateLimiter {
        EventRateLimiter(cooldowns: ["bathroom": 60])
    }
}