import XCTest
@testable import DoseTap

@MainActor
final class WHOOPDecodingTests: XCTestCase {

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
