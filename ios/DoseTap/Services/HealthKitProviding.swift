import Foundation

// MARK: - HealthKit Protocol for Dependency Injection

/// Protocol abstracting HealthKit access for testability.
/// Production code uses `HealthKitService`, tests use `NoOpHealthKitProvider`.
/// This enables test isolation without simulator HealthKit entitlements.
@MainActor
public protocol HealthKitProviding: AnyObject {
    /// Whether HealthKit is available on this device
    var isAvailable: Bool { get }
    
    /// Whether authorization has been granted
    var isAuthorized: Bool { get }
    
    /// Request HealthKit authorization
    func requestAuthorization() async -> Bool
    
    /// Computed TTFW baseline in minutes (nil if no data)
    var ttfwBaseline: Double? { get }
    
    /// Fetch and compute TTFW baseline from recent sleep data
    func computeTTFWBaseline(days: Int) async
    
    /// Calculate nudge suggestion based on baseline
    func calculateNudgeSuggestion() -> Int?
    
    /// Get same-night nudge suggestion
    func sameNightNudge(dose1Time: Date, currentTargetMinutes: Int) async -> Int?
}

// MARK: - No-Op Provider for Testing

/// Fake HealthKit provider that does nothing and returns safe defaults.
/// Use this in tests to avoid HealthKit entitlement issues and ensure
/// tests don't depend on real device health data.
@MainActor
public final class NoOpHealthKitProvider: HealthKitProviding {
    
    /// Configurable test state
    public var stubIsAvailable: Bool = false
    public var stubIsAuthorized: Bool = false
    public var stubAuthorizationResult: Bool = false
    public var stubTTFWBaseline: Double? = nil
    public var stubNudgeSuggestion: Int? = nil
    public var stubSameNightNudge: Int? = nil
    
    /// Call tracking for verification
    public private(set) var requestAuthorizationCallCount = 0
    public private(set) var computeBaselineCallCount = 0
    public private(set) var lastComputeBaselineDays: Int? = nil
    
    public init() {}
    
    public var isAvailable: Bool {
        stubIsAvailable
    }
    
    public var isAuthorized: Bool {
        stubIsAuthorized
    }
    
    public func requestAuthorization() async -> Bool {
        requestAuthorizationCallCount += 1
        return stubAuthorizationResult
    }
    
    public var ttfwBaseline: Double? {
        stubTTFWBaseline
    }
    
    public func computeTTFWBaseline(days: Int) async {
        computeBaselineCallCount += 1
        lastComputeBaselineDays = days
        // No-op: doesn't modify stubTTFWBaseline
    }
    
    public func calculateNudgeSuggestion() -> Int? {
        stubNudgeSuggestion
    }
    
    public func sameNightNudge(dose1Time: Date, currentTargetMinutes: Int) async -> Int? {
        stubSameNightNudge
    }
    
    /// Reset all call tracking
    public func reset() {
        requestAuthorizationCallCount = 0
        computeBaselineCallCount = 0
        lastComputeBaselineDays = nil
    }
}
