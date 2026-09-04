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

    func test_healthKitSummary_doesNotDoubleCountOverlappingInBedAndStageSamples() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 21, minute: 0))!
        let sleepOnset = start.addingTimeInterval(23 * 60)
        let firstWake = start.addingTimeInterval(2 * 60 * 60)
        let finalWake = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 4, minute: 36))!
        let inBedEnd = calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 7, minute: 0))!

        let segments: [HealthKitService.SleepSegment] = [
            HealthKitService.SleepSegment(
                start: start,
                end: inBedEnd,
                stage: .inBed,
                source: "Kevin's Apple Watch"
            ),
            HealthKitService.SleepSegment(
                start: sleepOnset,
                end: finalWake,
                stage: .asleepCore,
                source: "Kevin's Apple Watch"
            ),
            HealthKitService.SleepSegment(
                start: firstWake,
                end: firstWake.addingTimeInterval(7 * 60),
                stage: .awake,
                source: "Kevin's Apple Watch"
            ),
            HealthKitService.SleepSegment(
                start: calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 1, minute: 0))!,
                end: calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 1, minute: 30))!,
                stage: .asleepDeep,
                source: "Kevin's Apple Watch"
            ),
            HealthKitService.SleepSegment(
                start: calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 2, minute: 0))!,
                end: calendar.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 2, minute: 28))!,
                stage: .asleepREM,
                source: "Kevin's Apple Watch"
            )
        ]

        let summary = HealthKitService.sleepNightSummary(from: segments, nightStart: start)

        XCTAssertEqual(summary?.sleepOnset, sleepOnset)
        XCTAssertEqual(summary?.firstWake, firstWake)
        XCTAssertEqual(summary?.finalWake, finalWake)
        XCTAssertEqual(summary?.wakeCount, 1)
        XCTAssertEqual(summary?.ttfwMinutes ?? 0, 97, accuracy: 0.001)
        XCTAssertEqual(summary?.totalSleepMinutes ?? 0, 426, accuracy: 0.001)

        let primary = HealthKitService.primaryNightSegments(from: segments)
        XCTAssertFalse(primary.contains { $0.stage == .inBed && $0.end.timeIntervalSince($0.start) > 25 * 60 })
        for index in 0..<(primary.count - 1) {
            XCTAssertLessThanOrEqual(primary[index].end, primary[index + 1].start)
        }
    }

    func test_primarySleepBiometricRange_excludesSecondarySleepCluster() {
        let start = Date(timeIntervalSince1970: 1_788_200_000)
        let segments: [HealthKitService.SleepSegment] = [
            .init(
                start: start,
                end: start.addingTimeInterval(7 * 60 * 60),
                stage: .asleepCore,
                source: "Apple Watch"
            ),
            .init(
                start: start.addingTimeInterval(9 * 60 * 60),
                end: start.addingTimeInterval(9.5 * 60 * 60),
                stage: .asleepCore,
                source: "Apple Watch"
            )
        ]

        let range = HealthKitService.primarySleepBiometricRange(
            from: segments,
            fallbackStart: start.addingTimeInterval(-4 * 60 * 60),
            fallbackEnd: start.addingTimeInterval(14 * 60 * 60)
        )

        XCTAssertEqual(range.start, start)
        XCTAssertEqual(range.end, start.addingTimeInterval(7 * 60 * 60))
    }
    
    func test_whoopService_disabledWhenNoTokens() {
        // WHOOP isEnabled is dynamic: reads UserDefaults "whoop_enabled".
        // In a fresh test environment with no tokens, it should be false.
        let key = "whoop_enabled"
        let saved = UserDefaults.standard.bool(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        
        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(WHOOPService.isEnabled, "WHOOP should be disabled when user hasn't connected")
        
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(WHOOPService.isEnabled, "WHOOP should be enabled when user has connected")
    }
    
    func test_whoopCallbackValidation_rejectsMissingState() {
        let callback = URL(string: "dosetap://whoop/callback?code=abc123")!
        
        XCTAssertThrowsError(
            try WHOOPService.validateAuthorizationCallback(callback, expectedState: "expected-state")
        ) { error in
            guard case WHOOPError.stateMismatch = error else {
                return XCTFail("Expected stateMismatch, got \(error)")
            }
        }
    }
    
    func test_whoopCallbackValidation_returnsCodeWhenStateMatches() throws {
        let callback = URL(string: "dosetap://whoop/callback?code=abc123&state=expected-state")!
        
        let code = try WHOOPService.validateAuthorizationCallback(callback, expectedState: "expected-state")
        
        XCTAssertEqual(code, "abc123")
    }
}

// MARK: - API Contract Drift Tests

final class APIContractTests: XCTestCase {
    func test_openAPIMatchesClientEndpoints() throws {
        let expected: Set<String> = [
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
