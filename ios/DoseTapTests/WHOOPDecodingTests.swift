import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class WHOOPDecodingTests: XCTestCase {

    func testSummaryPreservesRawEndpointsAndRejectsInconsistentIdentity() throws {
        let json = #"{"id":"endpoint-night","start":"2026-09-29T22:00:00Z","end":"2026-09-30T06:00:00Z","timezone_offset":"-04:00","updated_at":"2026-09-30T07:00:00Z"}"#
        let raw = try WHOOPService.makeAPIDecoder().decode(WHOOPSleep.self, from: Data(json.utf8))
        var summary = raw.toNightSummary()
        XCTAssertEqual(summary.endpointEvidence?.originalStart, raw.start)
        XCTAssertEqual(summary.endpointEvidence?.originalEnd, raw.end)
        XCTAssertEqual(summary.endpointEvidence?.providerUpdatedAt, raw.updatedAt)
        XCTAssertEqual(summary.endpointEvidence?.providerTimeZoneOffset, "-04:00")
        XCTAssertEqual(summary.originalSleepInterval?.duration, 28_800)
        let previous = summary.associationFingerprint
        summary.endpointEvidence = .init(sleepID: raw.id, originalStart: raw.start, originalEnd: raw.end?.addingTimeInterval(60), providerTimeZoneOffset: raw.timezoneOffset, providerUpdatedAt: raw.updatedAt)
        XCTAssertNotEqual(previous, summary.associationFingerprint)
        summary.endpointEvidence = .init(sleepID: "wrong-id", originalStart: raw.start, originalEnd: raw.end, providerTimeZoneOffset: raw.timezoneOffset, providerUpdatedAt: raw.updatedAt)
        XCTAssertNil(summary.originalSleepInterval)
        summary.endpointEvidence = .init(sleepID: raw.id, originalStart: raw.start?.addingTimeInterval(1), originalEnd: raw.end, providerTimeZoneOffset: raw.timezoneOffset, providerUpdatedAt: raw.updatedAt)
        XCTAssertNil(summary.originalSleepInterval)
    }
    func testMissingOrInvalidWHOOPEndIsNotInventedFromDuration() throws {
        for suffix in ["", #", "end":"2026-09-29T21:00:00Z""#] {
            let json = #"{"id":"endpoint-night","start":"2026-09-29T22:00:00Z","score":{"stage_summary":{"total_in_bed_time_milli":28800000}}"# + suffix + "}"
            let raw = try WHOOPService.makeAPIDecoder().decode(WHOOPSleep.self, from: Data(json.utf8))
            let summary = raw.toNightSummary()
            XCTAssertEqual(summary.inBedMinutes, 480)
            XCTAssertEqual(summary.endpointEvidence?.originalEnd, raw.end)
            XCTAssertNil(summary.originalSleepInterval)
        }
    }

    func testStageCorrectionPreservesPrecisionAndInvalidatesFingerprint() throws {
        let json = #"{"id":"precision-night","start":"2026-09-29T22:00:00Z","end":"2026-09-30T06:00:00Z","score_state":"SCORED","score":{"stage_summary":{"total_light_sleep_time_milli":1000,"total_slow_wave_sleep_time_milli":0,"total_rem_sleep_time_milli":0}}}"#
        let raw = try WHOOPService.makeAPIDecoder().decode(WHOOPSleep.self, from: Data(json.utf8))
        let original = raw.toNightSummary()
        var corrected = original
        corrected.stageEvidence = .init(sleepID: original.sleepId, scoreState: "SCORED",
            lightMilliseconds: 2_000, deepMilliseconds: 0, remMilliseconds: 0)
        XCTAssertEqual(original.totalSleepMinutes, corrected.totalSleepMinutes)
        XCTAssertNotEqual(original.associationFingerprint, corrected.associationFingerprint)
        XCTAssertEqual(try XCTUnwrap(corrected.quantitativeSleepMinutes), 1.0 / 30, accuracy: 0.000001)
        corrected.stageEvidence = .init(sleepID: "different-sleep", scoreState: "SCORED",
            lightMilliseconds: 2_000, deepMilliseconds: 0, remMilliseconds: 0)
        XCTAssertNil(corrected.quantitativeSleepMinutes)
        XCTAssertNotNil(corrected.sleepEvidenceReviewReason)
        corrected.stageEvidence = nil
        XCTAssertNil(corrected.quantitativeSleepMinutes) // Legacy integer totals cannot establish scoring.
    }

    func testNightFetchPreservesSleepAfterRecoveryFailure() async throws {
        let sleeps = try nightFetchSleepRecords()
        let result = try await WHOOPService.loadNightSummaryResult(
            sleep: { sleeps }, recovery: { throw URLError(.timedOut) })
        XCTAssertEqual(result.sleepRecordCount, 2)
        XCTAssertEqual(result.recoveryStatus, .failed)
        XCTAssertNil(result.recoveryRecordCount)
        XCTAssertEqual(result.summaries.map(\.sleepId), ["night"])
        XCTAssertEqual(result.summaries.first?.totalSleepMinutes, 60)
        XCTAssertNil(result.summaries.first?.recoveryScore)
    }

    func testNightFetchCompletedCountsIncludeReturnedRecordsBeforeFiltering() async throws {
        let sleeps = try nightFetchSleepRecords()
        let recoveries = try WHOOPService.makeAPIDecoder().decode([WHOOPRecovery].self, from: Data(
            #"[{"cycle_id":"cycle","sleep_id":"night","score":{"recovery_score":72}}]"#.utf8))
        let result = try await WHOOPService.loadNightSummaryResult(sleep: { sleeps }, recovery: { recoveries })
        XCTAssertEqual(result.sleepRecordCount, 2)
        XCTAssertEqual(result.recoveryRecordCount, 1)
        XCTAssertEqual(result.recoveryStatus, .completed)
        XCTAssertEqual(result.summaries.count, 1)
        XCTAssertEqual(result.summaries.first?.recoveryScore, 72)
        let empty = try await WHOOPService.loadNightSummaryResult(sleep: { [] }, recovery: { [] })
        XCTAssertEqual(empty.sleepRecordCount, 0)
        XCTAssertEqual(empty.recoveryRecordCount, 0)
        XCTAssertEqual(empty.recoveryStatus, .completed)
        XCTAssertTrue(empty.summaries.isEmpty)
    }

    func testNightFetchSleepFailureDoesNotFetchRecovery() async {
        var recoveryCalled = false
        do {
            _ = try await WHOOPService.loadNightSummaryResult(
                sleep: { throw URLError(.timedOut) }, recovery: { recoveryCalled = true; return [] })
            XCTFail("Sleep failure must propagate")
        } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertFalse(recoveryCalled)
    }

    func testNightFetchCancellationSignalsNeverBecomePartialSuccess() async {
        let signals: [Error] = [CancellationError(), URLError(.cancelled)]
        for duringRecovery in [false, true] {
            for signal in signals {
                do {
                    _ = try await WHOOPService.loadNightSummaryResult(
                        sleep: { if !duringRecovery { throw signal }; return [] },
                        recovery: { throw signal })
                    XCTFail("Cancellation must propagate")
                } catch {
                    XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
                }
            }
        }
    }

    func testNightFetchRejectsCancellationBeforeAndAfterNonthrowingLoaders() async {
        for cancellationPoint in 0...2 {
            var sleepCalls = 0
            var recoveryCalls = 0
            let task = Task { @MainActor in
                if cancellationPoint == 0 { withUnsafeCurrentTask { $0?.cancel() } }
                return try await WHOOPService.loadNightSummaryResult(sleep: {
                    sleepCalls += 1
                    if cancellationPoint == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                    return []
                }, recovery: {
                    recoveryCalls += 1
                    if cancellationPoint == 2 { withUnsafeCurrentTask { $0?.cancel() } }
                    return []
                })
            }
            do { _ = try await task.value; XCTFail("Cancelled result must not publish") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(sleepCalls, cancellationPoint == 0 ? 0 : 1)
            XCTAssertEqual(recoveryCalls, cancellationPoint == 2 ? 1 : 0)
        }
    }

    func testOverlappingNightFetchesKeepTheirOwnRecoveryStatus() async throws {
        let sleeps = try nightFetchSleepRecords()
        let suspended = expectation(description: "First recovery pending")
        var resumeRecovery: CheckedContinuation<[WHOOPRecovery], Error>?
        let first = Task { @MainActor in
            try await WHOOPService.loadNightSummaryResult(sleep: { sleeps }, recovery: {
                try await withCheckedThrowingContinuation {
                    resumeRecovery = $0
                    suspended.fulfill()
                }
            })
        }
        await fulfillment(of: [suspended], timeout: 2)
        let second = try await WHOOPService.loadNightSummaryResult(sleep: { [] }, recovery: { [] })
        resumeRecovery?.resume(throwing: URLError(.timedOut))
        let partial = try await first.value
        XCTAssertEqual(second.recoveryStatus, .completed)
        XCTAssertEqual(second.recoveryRecordCount, 0)
        XCTAssertTrue(second.summaries.isEmpty)
        XCTAssertEqual(partial.recoveryStatus, .failed)
        XCTAssertNil(partial.recoveryRecordCount)
        XCTAssertEqual(partial.summaries.map(\.sleepId), ["night"])
    }

    private func nightFetchSleepRecords() throws -> [WHOOPSleep] {
        let json = """
        [
          {"id":"night","start":"2026-09-10T23:00:00Z","end":"2026-09-11T00:00:00Z","nap":false,"score_state":"SCORED","score":{"stage_summary":{"total_light_sleep_time_milli":3600000}}},
          {"id":"nap","start":"2026-09-11T10:00:00Z","end":"2026-09-11T11:00:00Z","nap":true,"score_state":"SCORED","score":{"stage_summary":{"total_light_sleep_time_milli":3600000}}}
        ]
        """
        return try WHOOPService.makeAPIDecoder().decode([WHOOPSleep].self, from: Data(json.utf8))
    }

    func test_whoopOAuthStateIsEightURLSafeCharacters() {
        for _ in 0..<20 {
            let state = WHOOPService.generateOAuthState()

            XCTAssertEqual(state.count, 8)
            XCTAssertNotNil(
                state.range(of: #"^[A-Za-z0-9_-]{8}$"#, options: .regularExpression)
            )
        }
    }

    func test_whoopSleepDecodesFractionalSecondTimestamps() throws {
        let json = """
        {
          "records": [
            {
              "id": 12345,
              "user_id": 67890,
              "created_at": "2026-03-07T11:25:44.774Z",
              "updated_at": "2026-03-07T11:30:44.774Z",
              "start": "2026-03-06T23:12:10.125Z",
              "end": "2026-03-07T07:14:55.932Z",
              "timezone_offset": "-05:00",
              "nap": false,
              "score_state": "SCORED",
              "score": {
                "stage_summary": {
                  "total_awake_time_milli": 600000,
                  "total_light_sleep_time_milli": 14400000,
                  "total_slow_wave_sleep_time_milli": 5400000,
                  "total_rem_sleep_time_milli": 7200000,
                  "disturbance_count": 3
                },
                "respiratory_rate": 14.2,
                "sleep_efficiency_percentage": 91.0
              }
            }
          ],
          "next_token": null
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try WHOOPService.makeAPIDecoder().decode(WHOOPPaginatedResponse<WHOOPSleep>.self, from: data)

        XCTAssertEqual(response.records.count, 1)
        XCTAssertEqual(response.records.first?.id, "12345")
        XCTAssertEqual(response.records.first?.durationMinutes, 482)
        XCTAssertEqual(response.records.first?.score?.stageSummary?.totalSleepMinutes, 450)
    }

    func test_whoopRecoveryDecodesFractionalSecondTimestamps() throws {
        let json = """
        {
          "records": [
            {
              "cycle_id": 777,
              "sleep_id": 12345,
              "user_id": 67890,
              "created_at": "2026-03-07T12:25:44.774Z",
              "updated_at": "2026-03-07T12:30:44.774Z",
              "score_state": "SCORED",
              "score": {
                "recovery_score": 72,
                "resting_heart_rate": 54,
                "hrv_rmssd_milli": 68.5
              }
            }
          ],
          "next_token": null
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try WHOOPService.makeAPIDecoder().decode(WHOOPPaginatedResponse<WHOOPRecovery>.self, from: data)

        XCTAssertEqual(response.records.count, 1)
        XCTAssertEqual(response.records.first?.sleepId, "12345")
        XCTAssertEqual(response.records.first?.score?.recoveryScore, 72)
        XCTAssertEqual(response.records.first?.score?.hrvMs, 68.5)
    }

    func test_whoopPaginatedResponseDecodesNextToken() throws {
        let json = """
        {
          "records": [],
          "next_token": "cursor-123"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try WHOOPService.makeAPIDecoder().decode(WHOOPPaginatedResponse<WHOOPSleep>.self, from: data)

        XCTAssertEqual(response.nextToken, "cursor-123")
    }

    func test_whoopPaginationEndpointAddsNextTokenAndPreservesQuery() {
        let endpoint = "/developer/v2/activity/sleep?start=2026-03-07T00:00:00Z&end=2026-03-08T00:00:00Z"

        let pagedEndpoint = WHOOPService.endpoint(endpoint, addingNextToken: "cursor-123")

        XCTAssertTrue(pagedEndpoint.contains("start=2026-03-07T00:00:00Z"))
        XCTAssertTrue(pagedEndpoint.contains("end=2026-03-08T00:00:00Z"))
        XCTAssertTrue(pagedEndpoint.contains("nextToken=cursor-123"))
    }

    func test_whoopPaginationEndpointIgnoresEmptyNextToken() {
        let endpoint = "/developer/v2/recovery?start=2026-03-07T00:00:00Z&end=2026-03-08T00:00:00Z"

        XCTAssertEqual(WHOOPService.endpoint(endpoint, addingNextToken: nil), endpoint)
        XCTAssertEqual(WHOOPService.endpoint(endpoint, addingNextToken: " "), endpoint)
    }

    func test_whoopConnectionStateTreatsRefreshTokenAsRecoverableConnection() {
        let now = ISO8601DateFormatter().date(from: "2026-03-07T12:00:00Z")!

        XCTAssertTrue(
            WHOOPService.hasRecoverableConnection(
                accessToken: "expired-access",
                refreshToken: "refresh-token",
                tokenExpiry: now.addingTimeInterval(-60),
                now: now
            )
        )
        XCTAssertTrue(
            WHOOPService.hasRecoverableConnection(
                accessToken: "valid-access",
                refreshToken: nil,
                tokenExpiry: now.addingTimeInterval(3600),
                now: now
            )
        )
        XCTAssertFalse(
            WHOOPService.hasRecoverableConnection(
                accessToken: "expired-access",
                refreshToken: nil,
                tokenExpiry: now.addingTimeInterval(-60),
                now: now
            )
        )
    }

    func test_whoopNightSummariesMergeRecoveryAndFilterUnscoredSleep() throws {
        let sleepJSON = """
        {
          "records": [
            {
              "id": 12345,
              "user_id": 67890,
              "created_at": "2026-03-07T11:25:44.774Z",
              "updated_at": "2026-03-07T11:30:44.774Z",
              "start": "2026-03-06T23:12:10.125Z",
              "end": "2026-03-07T07:14:55.932Z",
              "timezone_offset": "-05:00",
              "nap": false,
              "score_state": "SCORED",
              "score": {
                "stage_summary": {
                  "total_awake_time_milli": 600000,
                  "total_light_sleep_time_milli": 14400000,
                  "total_slow_wave_sleep_time_milli": 5400000,
                  "total_rem_sleep_time_milli": 7200000,
                  "disturbance_count": 3
                },
                "respiratory_rate": 14.2,
                "sleep_efficiency_percentage": 91.0
              }
            },
            {
              "id": 99999,
              "user_id": 67890,
              "created_at": "2026-03-08T11:25:44.774Z",
              "updated_at": "2026-03-08T11:30:44.774Z",
              "start": "2026-03-07T23:12:10.125Z",
              "end": "2026-03-08T07:14:55.932Z",
              "timezone_offset": "-05:00",
              "nap": false,
              "score_state": "PENDING_SCORE",
              "score": null
            }
          ],
          "next_token": null
        }
        """
        let recoveryJSON = """
        {
          "records": [
            {
              "cycle_id": 777,
              "sleep_id": 12345,
              "user_id": 67890,
              "created_at": "2026-03-07T12:25:44.774Z",
              "updated_at": "2026-03-07T12:30:44.774Z",
              "score_state": "SCORED",
              "score": {
                "recovery_score": 72,
                "resting_heart_rate": 54,
                "hrv_rmssd_milli": 68.5,
                "spo2_percentage": 98.1,
                "skin_temp_celsius": 33.4
              }
            }
          ],
          "next_token": null
        }
        """

        let decoder = WHOOPService.makeAPIDecoder()
        let sleeps = try decoder
            .decode(WHOOPPaginatedResponse<WHOOPSleep>.self, from: try XCTUnwrap(sleepJSON.data(using: .utf8)))
            .records
        let recoveries = try decoder
            .decode(WHOOPPaginatedResponse<WHOOPRecovery>.self, from: try XCTUnwrap(recoveryJSON.data(using: .utf8)))
            .records

        let summaries = WHOOPService.makeNightSummaries(sleeps: sleeps, recoveries: recoveries)

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.sleepId, "12345")
        XCTAssertEqual(summaries.first?.recoveryScore, 72)
        XCTAssertEqual(summaries.first?.hrvMs, 68.5)
        XCTAssertEqual(summaries.first?.restingHeartRate, 54)
        XCTAssertEqual(summaries.first?.spo2Percentage, 98.1)
        XCTAssertEqual(summaries.first?.skinTempCelsius, 33.4)
    }
}
