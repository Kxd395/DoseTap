import XCTest
import SwiftUI
import class DoseCore.DoseTapCore
@testable import DoseTap

@MainActor
final class TimelineReviewMetricsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_788_912_000)

    private func metrics(_ seconds: Double? = nil, skipped: Bool = false, now: Double = 18_000,
                         events: [StoredSleepEvent] = []) -> TimelineReviewMetrics {
        TimelineReviewMetrics(session: .init(sessionDate: "2026-09-08", dose1Time: start,
            dose2Time: seconds.map { start.addingTimeInterval($0) }, dose2Skipped: skipped),
            events: events, now: start.addingTimeInterval(now))
    }

    func testExactBoundariesIgnoreDisplayRounding() {
        for (seconds, status) in [(8999.0, "Early"), (9000, "In-window"), (14400, "In-window"), (14401, "Late")] {
            XCTAssertEqual(metrics(seconds).statusText, status)
        }
    }

    func testPendingEndsOnlyAfterInclusiveBoundary() {
        XCTAssertEqual(metrics(now: 14400).statusText, "Pending")
        XCTAssertEqual(metrics(now: 14401).statusText, "Not recorded")
        XCTAssertEqual(metrics(skipped: true, now: 14400).statusText, "Skipped")
        XCTAssertEqual(metrics(skipped: true).statusText, "Skipped")
    }

    func testEmptyOrphanInvalidAndContradictoryRecords() {
        XCTAssertEqual(TimelineReviewMetrics(session: .init(sessionDate: "2026-09-08"), events: [], now: start).statusText, "No doses")
        XCTAssertEqual(TimelineReviewMetrics(session: .init(sessionDate: "2026-09-08", dose2Time: start), events: [], now: start).statusText, "Dose 1 missing")
        XCTAssertEqual(metrics(-1).statusText, "Invalid pair")
        XCTAssertEqual(metrics(-1).intervalText, "Unavailable")
        XCTAssertEqual(metrics(9000, skipped: true).statusText, "Conflicting records")
    }

    func testBathroomAndDisruptionValuesAreLogCountsOnly() {
        let events = [event("Bathroom"), event("bathroom"), event("Noise"), event("Water")]
        XCTAssertEqual(metrics(events: events).bathroomText, "2 logged")
        XCTAssertEqual(metrics(events: events).disruptionText, "3 logged")
        XCTAssertEqual(metrics().bathroomText, "0 logged")
        XCTAssertEqual(metrics().disruptionText, "0 logged")
    }

    func testLoggedElapsedRequiresOrderedMarkers() {
        XCTAssertEqual(metrics().loggedRestText, "Unavailable")
        XCTAssertEqual(metrics(events: [event("lights_out", at: 60), event("wake_final", at: 0)]).loggedRestText, "Unavailable")
        XCTAssertEqual(metrics(events: [event("lights_out"), event("wake_final", at: 3660)]).loggedRestText, "1h 1m")
    }

    func testAbsoluteTimeAcrossRepeatedDSTHour() throws {
        let formatter = ISO8601DateFormatter()
        let dose1 = try XCTUnwrap(formatter.date(from: "2026-11-01T00:30:00-04:00"))
        let dose2 = try XCTUnwrap(formatter.date(from: "2026-11-01T02:00:00-05:00"))
        let result = TimelineReviewMetrics(session: .init(sessionDate: "2026-10-31", dose1Time: dose1, dose2Time: dose2), events: [], now: dose2)
        XCTAssertEqual(result.statusText, "In-window")
        XCTAssertEqual(result.intervalText, "2h 30m")
    }

    func testReviewCardRendersStandardAndAccessibilityCapture() throws {
        let session = DoseTap.SessionSummary(sessionDate: "2026-09-08", dose1Time: start,
            dose2Time: start.addingTimeInterval(14401))
        for size in [DynamicTypeSize.large, .accessibility3] {
            let card = ReviewKeyMetricsCard(session: session, events: [event("Bathroom"), event("Bathroom")], now: start.addingTimeInterval(18000))
            XCTAssertEqual(card.metrics.statusText, "Late")
            XCTAssertEqual(card.metrics.bathroomText, "2 logged")
            let renderer = ImageRenderer(content: card.frame(width: 361)
                .environment(\.dynamicTypeSize, size).environment(\.colorScheme, .dark))
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(image.size.height, 200)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Review metrics \(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func event(_ name: String, at seconds: Double = 0) -> StoredSleepEvent {
        .init(id: UUID().uuidString, eventType: name, timestamp: start.addingTimeInterval(seconds), sessionDate: "2026-09-08")
    }

    func testFullReviewCaptureHasRasterPixels() throws {
        let content = TimelineReviewShareSnapshotView(session: .init(sessionDate: "2026-09-08", dose1Time: start,
            dose2Time: start.addingTimeInterval(14401)), events: [event("Bathroom"), event("Bathroom")],
            nightDate: start, hasMorningCheckIn: false, core: DoseTapCore(), snapshotTimeline: nil, healthSnapshot: nil)
            .frame(width: 361).padding(.vertical, 8)
            .environment(\.colorScheme, .dark)
        let image = try XCTUnwrap(renderTimelineReviewCapture(content, scale: 3))
        let pixels = try XCTUnwrap(image.cgImage)
        XCTAssertGreaterThan(pixels.width, 300)
        XCTAssertGreaterThan(pixels.height, 300)
        let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        attachment.name = "Full Review raster \(pixels.width)x\(pixels.height)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureRejectsTransparentContentButKeepsBlackAndSparseContent() throws {
        XCTAssertNil(renderTimelineReviewCapture(Color.clear.frame(width: 100, height: 100), scale: 1))
        XCTAssertNotNil(renderTimelineReviewCapture(Color.black.frame(width: 100, height: 100), scale: 1))
        XCTAssertNotNil(renderTimelineReviewCapture(
            Color.clear.frame(width: 100, height: 100).overlay(alignment: .bottomTrailing) {
                Color.white.frame(width: 1, height: 1)
            }, scale: 1))
    }
}
