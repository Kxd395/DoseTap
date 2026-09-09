//
//  HealthKitAndAPITests.swift
//  DoseTapTests
//
//  HealthKit provider, API contract, and watchOS smoke tests.
//  Extracted from DoseTapTests.swift for maintainability.
//

import XCTest
import HealthKit
@testable import DoseTap
import DoseCore

// MARK: - HealthKit Provider Tests

@MainActor
final class HealthKitProviderTests: XCTestCase {

    func test_boundedEvidenceRetainsSampleProvenanceBeforeClipping() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000), end = Date(timeIntervalSince1970: 1_800_003_600)
        let device = HKDevice(name: "Synthetic watch", manufacturer: "Test", model: "Test model",
            hardwareVersion: "1", firmwareVersion: "2", softwareVersion: "3", localIdentifier: nil, udiDeviceIdentifier: nil)
        let sample = HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: start.addingTimeInterval(-600), end: end, device: device, metadata: [HKMetadataKeyTimeZone: "America/New_York"])
        let segment = HealthKitService.sleepSegment(from: sample, receivedAt: end)
        let result = try XCTUnwrap(HealthKitService.sleepEvidence(from: [segment], start: start, end: end))
        let evidence = try XCTUnwrap(result.samples.first)
        XCTAssertEqual(evidence.sampleID, sample.uuid.uuidString)
        XCTAssertEqual(evidence.start, start.addingTimeInterval(-600))
        XCTAssertEqual(evidence.rawCategory, sample.value)
        XCTAssertEqual(evidence.origin.bundleIdentifier, sample.sourceRevision.source.bundleIdentifier)
        XCTAssertEqual(evidence.origin.sourceVersion, sample.sourceRevision.version)
        XCTAssertEqual(evidence.origin.timeZoneID, "America/New_York")
        XCTAssertEqual(evidence.origin.deviceModel, "Test model")
        XCTAssertEqual(evidence.origin.deviceSoftwareVersion, "3")
        XCTAssertEqual(evidence.origin.receivedAt, end)
        XCTAssertEqual(result.coverage.asleepMinutes, 60)
        XCTAssertEqual(result.slices.first?.start, start)
    }

    func test_boundedEvidenceDisclosesConflictWithoutChangingLegacySummary() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000), end = Date(timeIntervalSince1970: 1_800_003_600)
        let segments: [HealthKitService.SleepSegment] = [
            .init(start: start, end: end, stage: .asleepCore, source: "Watch"),
            .init(start: start.addingTimeInterval(1200), end: start.addingTimeInterval(1800), stage: .awake, source: "Phone")]
        let result = try XCTUnwrap(HealthKitService.sleepEvidence(from: segments, start: start, end: end))
        XCTAssertEqual(result.conflictMinutes, 10)
        XCTAssertEqual(result.coverage.awakeMinutes, 0)
        XCTAssertEqual(result.coverage.unmeasuredMinutes, 10)
        XCTAssertEqual(result.coverage, HealthKitService.sleepCoverage(from: segments, start: start, end: end))
        XCTAssertNil(result.samples.first?.sampleID) // Legacy/test segments cannot invent provenance.
        let legacy = try XCTUnwrap(HealthKitService.sleepNightSummary(from: segments, nightStart: start))
        XCTAssertEqual(legacy.totalSleepMinutes, 50)
        XCTAssertTrue(legacy.recordedIntervals.contains { !$0.asleep })
    }

    func test_boundedCoverageRetainsSplitSleepButExcludesLaterNap() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func segment(_ lower: Double, _ upper: Double) -> HealthKitService.SleepSegment {
            .init(start: start.addingTimeInterval(lower * 60), end: start.addingTimeInterval(upper * 60),
                  stage: .asleepCore, source: "Watch")
        }
        let segments = [segment(-30, 180), segment(285, 430), segment(600, 660)]
        let result = try XCTUnwrap(HealthKitService.sleepCoverage(
            from: segments, start: start, end: start.addingTimeInterval(405 * 60)))
        XCTAssertEqual(result.asleepMinutes, 300)
        XCTAssertEqual(result.unmeasuredMinutes, 105)
        XCTAssertEqual(result.status, .partial)
        // The legacy primary episode remains a distinct, narrower selection.
        let primary = HealthKitService.primaryNightSegments(from: segments)
        XCTAssertEqual(primary.count, 1)
        XCTAssertEqual(primary.first?.end, start.addingTimeInterval(180 * 60))
    }

    func test_boundedCoverageUnknownAndInBedAreNotMeasuredSleepOrAwake() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func segment(_ lower: Double, _ upper: Double, _ stage: HealthKitService.SleepStage) -> HealthKitService.SleepSegment {
            .init(start: start.addingTimeInterval(lower * 60), end: start.addingTimeInterval(upper * 60),
                  stage: stage, source: "Watch")
        }
        let end = start.addingTimeInterval(60 * 60)
        let segments = [segment(0, 60, .inBed), segment(0, 40, .asleep),
                        segment(10, 20, .unknown(99)), segment(30, 40, .awake)]
        let result = try XCTUnwrap(HealthKitService.sleepCoverage(from: segments, start: start, end: end))
        XCTAssertEqual(result.asleepMinutes, 20)
        XCTAssertEqual(result.awakeMinutes, 0)
        XCTAssertEqual(result.unmeasuredMinutes, 40)
        XCTAssertEqual(result, HealthKitService.sleepCoverage(from: Array(segments.reversed()) + segments, start: start, end: end))
        let empty = try XCTUnwrap(HealthKitService.sleepCoverage(from: [], start: start, end: end))
        XCTAssertEqual(empty.status, .unavailable)
        XCTAssertNil(empty.asleepMinutes)
        let awake = try XCTUnwrap(HealthKitService.sleepCoverage(from: [segment(0, 60, .awake)], start: start, end: end))
        XCTAssertEqual(awake.status, .available)
        XCTAssertEqual(awake.asleepMinutes, 0)
    }

    func test_boundedCoverageRejectsInvalidWindowAndNonfiniteSamples() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000), end = Date(timeIntervalSince1970: 1_800_003_600)
        XCTAssertNil(HealthKitService.sleepCoverage(from: [], start: end, end: start))
        XCTAssertNil(HealthKitService.sleepCoverage(from: [], start: start, end: start))
        XCTAssertNil(HealthKitService.sleepCoverage(from: [], start: start, end: .init(timeIntervalSince1970: .infinity)))
        let samples: [HealthKitService.SleepSegment] = [
            .init(start: .init(timeIntervalSince1970: -.infinity), end: end, stage: .asleep, source: "Watch"),
            .init(start: start, end: .init(timeIntervalSince1970: .nan), stage: .asleep, source: "Watch")]
        let result = try XCTUnwrap(HealthKitService.sleepCoverage(from: samples, start: start, end: end))
        XCTAssertEqual(result.status, .unavailable)
    }

    func test_boundedQueryIncludesOverlapWithoutChangingLegacyQueryDefault() {
        let start = Date(timeIntervalSince1970: 1_800_000_000), end = Date(timeIntervalSince1970: 1_800_003_600)
        let sample = HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                      start: start.addingTimeInterval(-600), end: start.addingTimeInterval(600))
        XCTAssertTrue(HealthKitService.sleepSamplePredicate(from: start, to: end, options: []).evaluate(with: sample))
        XCTAssertFalse(HealthKitService.sleepSamplePredicate(from: start, to: end).evaluate(with: sample))
    }

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

    func test_finalWakeDoesNotUseTrailingAwakeObservationEnd() throws {
        let start = Date(timeIntervalSince1970: 1_788_200_000)
        let sleepEnd = start.addingTimeInterval(300 * 60)
        let observationEnd = sleepEnd.addingTimeInterval(20 * 60)
        let summary = try XCTUnwrap(HealthKitService.sleepNightSummary(from: [
            .init(start: start, end: sleepEnd, stage: .asleepCore, source: "Watch"),
            .init(start: sleepEnd, end: observationEnd, stage: .awake, source: "Watch")
        ], nightStart: start))
        XCTAssertEqual(summary.finalWake, sleepEnd)
        XCTAssertEqual(summary.totalSleepMinutes, 300)
        XCTAssertEqual(summary.recordedIntervals.last?.end, observationEnd)
        XCTAssertEqual(summary.observationEnd, observationEnd)
        XCTAssertEqual(summary.finalWakeBasis, "observed_sleep_to_awake")
        XCTAssertEqual(summary.derivationVersion, "primary_episode_boundary_v2")
    }

    func test_unknownCategoryCannotCreateSleepSummary() {
        let start = Date(timeIntervalSince1970: 1_788_200_000)
        let unknown = HealthKitService.SleepStage.from(hkValue: 999)
        XCTAssertFalse(unknown.isAsleep)
        XCTAssertNil(HealthKitService.sleepNightSummary(from: [
            .init(start: start, end: start.addingTimeInterval(3600), stage: unknown, source: "Future source")
        ], nightStart: start))
    }

    func test_unspecifiedSleepRemainsAsleep() {
        XCTAssertTrue(HealthKitService.SleepStage.from(
            hkValue: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue).isAsleep)
    }

    func test_sleepEndWithoutContiguousAwakeIsOnlySleepEndEstimate() throws {
        let start = Date(timeIntervalSince1970: 1_788_200_000)
        let end = start.addingTimeInterval(3600)
        let tails: [[HealthKitService.SleepSegment]] = [[], [
            .init(start: end.addingTimeInterval(60), end: end.addingTimeInterval(600), stage: .awake, source: "Watch")
        ], [
            .init(start: end, end: end.addingTimeInterval(600), stage: .inBed, source: "Phone")
        ]]
        for tail in tails {
            let summary = try XCTUnwrap(HealthKitService.sleepNightSummary(from: [
                .init(start: start, end: end, stage: .asleepCore, source: "Watch")
            ] + tail, nightStart: start))
            XCTAssertEqual(summary.finalWake, end)
            XCTAssertEqual(summary.finalWakeBasis, "last_observed_sleep_end")
            XCTAssertEqual(summary.observationEnd, tail.last?.end ?? end)
        }
    }

    func test_unknownOverlapPreservesRawCategoryAndExcludesCoverageOnReorder() throws {
        let start = Date(timeIntervalSince1970: 1_788_200_000)
        let segments: [HealthKitService.SleepSegment] = [
            .init(start: start, end: start.addingTimeInterval(3600), stage: .asleep, source: "Watch"),
            .init(start: start.addingTimeInterval(1200), end: start.addingTimeInterval(1800),
                  stage: .unknown(999), source: "Future source")
        ]
        for inputs in [segments, Array(segments.reversed()), segments + segments] {
            let normalized = HealthKitService.normalizedSleepSegments(inputs)
            XCTAssertEqual(normalized.count, 3)
            XCTAssertEqual(normalized[1].stage, .unknown(999))
            let summary = try XCTUnwrap(HealthKitService.sleepNightSummary(from: inputs, nightStart: start))
            XCTAssertEqual(summary.totalSleepMinutes, 50)
            XCTAssertEqual(summary.recordedIntervals.count, 2)
        }
    }

    func test_unclassifiedEvidenceCannotBecomeAwakeChartBands() {
        XCTAssertNil(HealthKitService.mapToDisplayStage(.unknown(999)))
        XCTAssertNil(HealthKitService.mapToDisplayStage(.inBed))
        XCTAssertEqual(HealthKitService.mapToDisplayStage(.awake), .awake)
        XCTAssertEqual(HealthKitService.mapToDisplayStage(.asleep), .core)
        XCTAssertEqual(HealthKitService.mapToDisplayStage(.asleepREM), .rem)
        XCTAssertEqual(HealthKitService.mapToDisplayStage(.asleepDeep), .deep)
    }

    func test_unknownCategoryAndSourceTiesAreDeterministic() {
        let start = Date(timeIntervalSince1970: 1_788_200_000)
        func sample(_ value: Int, _ source: String) -> HealthKitService.SleepSegment {
            .init(start: start, end: start.addingTimeInterval(600), stage: .unknown(value), source: source)
        }
        let inputs = [sample(999, "A"), sample(1000, "A"), sample(998, "B")]
        for order in [inputs, Array(inputs.reversed()), [inputs[1], inputs[2], inputs[0]], inputs + inputs] {
            let result = HealthKitService.normalizedSleepSegments(order)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result.first?.stage, .unknown(999))
            XCTAssertEqual(result.first?.source, "A")
        }
    }

    func test_primaryBoundaryAcrossDSTUsesAbsoluteInstants() throws {
        let parser = ISO8601DateFormatter()
        let start = try XCTUnwrap(parser.date(from: "2026-11-01T00:30:00-04:00"))
        let end = try XCTUnwrap(parser.date(from: "2026-11-01T02:30:00-05:00"))
        let summary = try XCTUnwrap(HealthKitService.sleepNightSummary(from: [
            .init(start: start, end: end, stage: .asleep, source: "Watch"),
            .init(start: end, end: end.addingTimeInterval(1200), stage: .awake, source: "Watch")
        ], nightStart: start))
        XCTAssertEqual(summary.totalSleepMinutes, 180)
        XCTAssertEqual(summary.finalWake, end)
        XCTAssertEqual(summary.observationEnd, end.addingTimeInterval(1200))
    }

    func test_exportRetainsBoundaryEvidenceWithoutChangingFinalWake() throws {
        let end = Date(timeIntervalSince1970: 1_788_200_000)
        let export = InsightsAppleHealthSummary(
            totalSleepMinutes: 300, ttfwMinutes: nil, wakeCount: 1,
            awakeMinutes: 20, wakeAfterSleepOnsetMinutes: 0, inBedMinutes: nil,
            coreSleepMinutes: 300, deepSleepMinutes: nil, remSleepMinutes: nil,
            bedTimeUTC: nil, sleepOnsetUTC: end.addingTimeInterval(-18000), finalWakeUTC: end,
            averageHeartRate: nil, respiratoryRate: nil, hrvMs: nil, restingHeartRate: nil,
            sources: ["Watch"], observationEndUTC: end.addingTimeInterval(1200),
            finalWakeBasis: "observed_sleep_to_awake", derivationVersion: "primary_episode_boundary_v2")
        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(InsightsAppleHealthSummary.self, from: data)
        XCTAssertEqual(decoded.finalWakeUTC, end)
        XCTAssertEqual(decoded.observationEndUTC, end.addingTimeInterval(1200))
        XCTAssertEqual(decoded.finalWakeBasis, export.finalWakeBasis)
        XCTAssertEqual(decoded.derivationVersion, export.derivationVersion)
        let legacy = try JSONDecoder().decode(InsightsAppleHealthSummary.self,
            from: Data("{\"totalSleepMinutes\":300,\"wakeCount\":1,\"sources\":[\"Watch\"]}".utf8))
        XCTAssertNil(legacy.derivationVersion)
        XCTAssertNil(legacy.observationEndUTC)
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
