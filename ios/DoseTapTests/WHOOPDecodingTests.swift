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
}
