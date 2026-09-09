import XCTest
import SwiftUI
@testable import DoseTap

@MainActor
final class HistoryBathroomLogTests: XCTestCase {
    private func event(_ type: String) -> StoredSleepEvent {
        .init(id: UUID().uuidString, eventType: type, timestamp: Date(timeIntervalSince1970: 0), sessionDate: "2026-09-08")
    }

    func testEmptyHistoryIsUnavailableRatherThanMeasuredZero() {
        let summary = BathroomLogSummary(nightEvents: [])
        XCTAssertEqual(summary.totalLogs, 0)
        XCTAssertEqual(summary.recordedNights, 0)
        XCTAssertEqual(summary.valueText, "No history")
    }

    func testZeroLogsKeepRecordedNightDenominator() {
        let summary = BathroomLogSummary(nightEvents: [[], [event("Water")]])
        XCTAssertEqual(summary.valueText, "0 logged")
        XCTAssertEqual(summary.nightsWithLogs, 0)
        XCTAssertEqual(summary.recordedNights, 2)
        XCTAssertEqual(summary.coverageText, "0 of 2 recorded nights have bathroom logs.")
    }

    func testMultipleLogsStayCountsAndUseCanonicalTypes() {
        let summary = BathroomLogSummary(nightEvents: [
            [event("Bathroom"), event("bathroom"), event("Water")],
            [event("Bathroom"), event("Noise")], []
        ])
        XCTAssertEqual(summary.totalLogs, 3)
        XCTAssertEqual(summary.nightsWithLogs, 2)
        XCTAssertEqual(summary.recordedNights, 3)
        XCTAssertEqual(summary.valueText, "3 logged")
        XCTAssertEqual(summary.coverageText, "2 of 3 recorded nights have bathroom logs.")
    }

    func testRecalculationAfterCorrectionDoesNotRetainOldCounts() {
        let original = BathroomLogSummary(nightEvents: [[event("Bathroom"), event("Bathroom")]])
        let corrected = BathroomLogSummary(nightEvents: [[event("Water")]])
        XCTAssertEqual(original.totalLogs, 2)
        XCTAssertEqual(corrected.totalLogs, 0)
        XCTAssertEqual(corrected.recordedNights, 1)
    }

    func testRepositorySummaryRefreshesAfterDeletionAndPreservesSourceRows() {
        let storage = EventStorage(dbPath: ":memory:")
        let repository = SessionRepository(storage: storage)
        let calculator = InsightsCalculator(repository: repository)
        for key in ["2026-09-08", "2026-08-30", "2026-08-01"] {
            storage.insertSleepEvent(eventType: "Water", timestamp: Date(timeIntervalSince1970: 0), sessionDate: key)
        }
        for (id, key) in [("a", "2026-09-08"), ("b", "2026-09-08"), ("c", "2026-08-30")] {
            storage.insertSleepEvent(id: id, eventType: "Bathroom", timestamp: Date(timeIntervalSince1970: 0), sessionDate: key)
        }
        calculator.computeInsights()
        XCTAssertEqual(calculator.bathroomLogs.totalLogs, 3)
        XCTAssertEqual(calculator.bathroomLogs.nightsWithLogs, 2)
        XCTAssertEqual(calculator.totalSessions, 3)
        XCTAssertEqual(calculator.recentSessions.map(\.bathroomLogCount), [2, 1, 0])
        XCTAssertEqual(repository.fetchSleepEvents(forSession: "2026-09-08").count, 3)
        storage.deleteSleepEvent(id: "a", recordCloudKitDeletion: false)
        calculator.computeInsights()
        XCTAssertEqual(calculator.bathroomLogs.totalLogs, 2)
        calculator.computeInsights(days: 1)
        XCTAssertEqual(calculator.totalSessions, 1)
        XCTAssertEqual(calculator.bathroomLogs.totalLogs, 1)
        calculator.computeInsights(days: 0)
        XCTAssertEqual(calculator.bathroomLogs.valueText, "No history")
    }

    func testStandardAccessibilityAndDetailedCaptureUseSameCount() throws {
        let storage = EventStorage(dbPath: ":memory:")
        for (key, types) in [("2026-09-08", ["Bathroom", "Bathroom"]),
                             ("2026-09-07", ["Bathroom"]), ("2026-09-06", ["Water"])] {
            for type in types {
                storage.insertSleepEvent(eventType: type, timestamp: Date(timeIntervalSince1970: 0), sessionDate: key)
            }
        }
        let calculator = InsightsCalculator(repository: SessionRepository(storage: storage))
        calculator.computeInsights()
        for detailed in [false, true] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let view = InsightsSummaryCard(insights: calculator, showDefinitions: detailed)
                    .frame(width: 361).environment(\.dynamicTypeSize, size).environment(\.colorScheme, .dark)
                let image = try XCTUnwrap(renderTimelineReviewCapture(view, scale: 2))
                XCTAssertGreaterThan(image.size.height, 100)
                XCTAssertEqual(calculator.bathroomLogs.valueText, "3 logged")
                let attachment = XCTAttachment(image: image)
                attachment.name = "Bathroom counts detailed-\(detailed) \(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
