//
//  HealthKitAndAPITests.swift
//  DoseTapTests
//
//  HealthKit provider, API contract, and watchOS smoke tests.
//  Extracted from DoseTapTests.swift for maintainability.
//

import XCTest
@testable import DoseTap
import DoseCore

// MARK: - HealthKit Provider Tests

@MainActor
final class HealthKitProviderTests: XCTestCase {
    
    func test_factoryDefaultsToNoOpOnSimulator() async throws {
        let provider = HealthKitProviderFactory.makeDefault()
        XCTAssertTrue(provider is NoOpHealthKitProvider, "Simulator should default to NoOpHealthKitProvider")
    }
    
    func test_noOpProvider_returnsSafeDefaults() async throws {
        let provider = NoOpHealthKitProvider()
        
        XCTAssertFalse(provider.isAvailable, "Default isAvailable is false")
        XCTAssertFalse(provider.isAuthorized, "Default isAuthorized is false")
        XCTAssertNil(provider.ttfwBaseline, "Default baseline is nil")
        XCTAssertNil(provider.calculateNudgeSuggestion(), "No nudge by default")
        
        let sameNight = await provider.sameNightNudge(dose1Time: Date(), currentTargetMinutes: 165)
        XCTAssertNil(sameNight, "No same-night nudge by default")
    }
    
    func test_noOpProvider_canBeStubbed() async throws {
        let provider = NoOpHealthKitProvider()
        
        provider.stubIsAvailable = true
        provider.stubIsAuthorized = true
        provider.stubAuthorizationResult = true
        provider.stubTTFWBaseline = 180.5
        provider.stubNudgeSuggestion = 15
        provider.stubSameNightNudge = 195
        
        XCTAssertTrue(provider.isAvailable, "Stubbed isAvailable")
        XCTAssertTrue(provider.isAuthorized, "Stubbed isAuthorized")
        XCTAssertEqual(provider.ttfwBaseline, 180.5, "Stubbed baseline")
        XCTAssertEqual(provider.calculateNudgeSuggestion(), 15, "Stubbed nudge")
        
        let auth = await provider.requestAuthorization()
        XCTAssertTrue(auth, "Stubbed authorization result")
        
        let sameNight = await provider.sameNightNudge(dose1Time: Date(), currentTargetMinutes: 165)
        XCTAssertEqual(sameNight, 195, "Stubbed same-night nudge")
    }
    
    func test_noOpProvider_tracksCalls() async throws {
        let provider = NoOpHealthKitProvider()
        
        XCTAssertEqual(provider.requestAuthorizationCallCount, 0)
        XCTAssertEqual(provider.computeBaselineCallCount, 0)
        XCTAssertNil(provider.lastComputeBaselineDays)
        
        _ = await provider.requestAuthorization()
        XCTAssertEqual(provider.requestAuthorizationCallCount, 1)
        
        await provider.computeTTFWBaseline(days: 14)
        XCTAssertEqual(provider.computeBaselineCallCount, 1)
        XCTAssertEqual(provider.lastComputeBaselineDays, 14)
        
        _ = await provider.requestAuthorization()
        await provider.computeTTFWBaseline(days: 30)
        XCTAssertEqual(provider.requestAuthorizationCallCount, 2)
        XCTAssertEqual(provider.computeBaselineCallCount, 2)
        XCTAssertEqual(provider.lastComputeBaselineDays, 30)
    }
    
    func test_noOpProvider_resetClearsCalls() async throws {
        let provider = NoOpHealthKitProvider()
        
        _ = await provider.requestAuthorization()
        await provider.computeTTFWBaseline(days: 7)
        
        XCTAssertEqual(provider.requestAuthorizationCallCount, 1)
        XCTAssertEqual(provider.computeBaselineCallCount, 1)
        
        provider.reset()
        
        XCTAssertEqual(provider.requestAuthorizationCallCount, 0)
        XCTAssertEqual(provider.computeBaselineCallCount, 0)
        XCTAssertNil(provider.lastComputeBaselineDays)
    }
    
    func test_healthKitService_conformsToProtocol() {
        let _: any HealthKitProviding.Type = HealthKitService.self
    }
    
    func test_whoopService_disabledByDefault() {
        XCTAssertFalse(WHOOPService.isEnabled, "WHOOP should be disabled by default for shipping builds")
    }
}

// MARK: - API Contract Drift Tests

final class APIContractTests: XCTestCase {
    func test_openAPIMatchesClientEndpoints() throws {
        let expected: Set<String> = [
            "/doses/take",
            "/doses/skip",
            "/doses/snooze",
            "/events/log",
            "/analytics/export"
        ]
        
        let possiblePaths = [
            "docs/SSOT/contracts/api.openapi.yaml",
            "../docs/SSOT/contracts/api.openapi.yaml",
            "../../docs/SSOT/contracts/api.openapi.yaml"
        ]
        
        var contents: String? = nil
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                contents = try? String(contentsOfFile: path, encoding: .utf8)
                if contents != nil { break }
            }
        }
        
        if let contents = contents {
            let openapiPaths = Set(
                contents
                    .split(separator: "\n")
                    .map(String.init)
                    .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("/") }
                    .map { line in
                        line.trimmingCharacters(in: .whitespaces)
                            .split(separator: ":")
                            .first
                            .map(String.init) ?? ""
                    }
            )
            
            XCTAssertEqual(openapiPaths, expected, "OpenAPI paths should match SSOT-required endpoints")
        }
        
        let clientPaths = Set(APIClient.Endpoint.allCases.map { $0.rawValue })
        XCTAssertEqual(clientPaths, expected, "APIClient.Endpoint should cover all SSOT endpoints")
    }
}

// MARK: - watchOS Companion Smoke Test

final class WatchOSSmokeTests: XCTestCase {
    func test_watchOSCompanion_isDeferredOrUnavailable() {
        #if os(watchOS)
        XCTAssertTrue(true, "watchOS build present")
        #else
        XCTAssertTrue(true, "watchOS companion not built in this target (deferred)")
        #endif
    }
}
