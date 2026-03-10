import XCTest
@testable import DoseCore

@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
final class DosingServiceTests: XCTestCase {

    // MARK: - Helpers

    private struct RecordingTransport: APITransport {
        let handler: (URLRequest) async throws -> (Data, HTTPURLResponse)
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            try await handler(request)
        }
    }

    private func okResponse(for req: URLRequest) -> (Data, HTTPURLResponse) {
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(), resp)
    }

    private func failingTransport() -> RecordingTransport {
        RecordingTransport { _ in throw URLError(.notConnectedToInternet) }
    }

    private func successTransport(capturing: @Sendable @escaping (URLRequest) -> Void = { _ in }) -> RecordingTransport {
        RecordingTransport { req in
            capturing(req)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), resp)
        }
    }

    private func makeService(transport: RecordingTransport, isOnline: @escaping () -> Bool = { true }) -> DosingService {
        let client = APIClient(baseURL: URL(string: "https://example.com")!, transport: transport)
        let queue = InMemoryOfflineQueue(isOnline: isOnline)
        return DosingService(client: client, queue: queue)
    }

    // MARK: - Happy Path

    func test_takeDose_success_hits_api() async {
        let expectation = expectation(description: "request sent")
        let transport = successTransport { _ in expectation.fulfill() }
        let svc = makeService(transport: transport)

        await svc.perform(.takeDose(type: "dose1", at: Date()))
        await fulfillment(of: [expectation], timeout: 1)
    }

    func test_skipDose_success() async {
        var captured: URLRequest?
        let transport = successTransport { captured = $0 }
        let svc = makeService(transport: transport)

        await svc.perform(.skipDose(sequence: 2, reason: "felt_better"))
        XCTAssertNotNil(captured)
        XCTAssertTrue(captured?.url?.path.contains("skip") ?? false)
    }

    func test_snooze_success() async {
        var captured: URLRequest?
        let transport = successTransport { captured = $0 }
        let svc = makeService(transport: transport)

        await svc.perform(.snooze(minutes: 10))
        XCTAssertNotNil(captured)
        XCTAssertTrue(captured?.url?.path.contains("snooze") ?? false)
    }

    func test_logEvent_success() async {
        var captured: URLRequest?
        let transport = successTransport { captured = $0 }
        let svc = makeService(transport: transport)

        await svc.perform(.logEvent(name: "bathroom", at: Date()))
        XCTAssertNotNil(captured)
        XCTAssertTrue(captured?.url?.path.contains("events") ?? false)
    }

    // MARK: - Offline Queue Fallback

    func test_failure_enqueues_to_offline_queue() async {
        let transport = failingTransport()
        let client = APIClient(baseURL: URL(string: "https://example.com")!, transport: transport)
        let queue = InMemoryOfflineQueue(isOnline: { false })
        let svc = DosingService(client: client, queue: queue)

        await svc.perform(.takeDose(type: "dose1", at: Date()))

        let pending = await queue.pending()
        XCTAssertEqual(pending.count, 1, "Failed action should be enqueued")
    }

    func test_flushPending_drains_queue() async {
        let transport = failingTransport()
        let client = APIClient(baseURL: URL(string: "https://example.com")!, transport: transport)
        let queue = InMemoryOfflineQueue(isOnline: { false })
        let svc = DosingService(client: client, queue: queue)

        await svc.perform(.takeDose(type: "dose1", at: Date()))
        let before = await queue.pending()
        XCTAssertEqual(before.count, 1)

        // Flush while still offline — tasks remain
        await svc.flushPending()
        let after = await queue.pending()
        XCTAssertEqual(after.count, 1, "Tasks remain when still offline")
    }

    // MARK: - Rate Limiter Integration

    func test_logEvent_rate_limited_drops_duplicate() async {
        var callCount = 0
        let transport = RecordingTransport { req in
            callCount += 1
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(), resp)
        }

        let client = APIClient(baseURL: URL(string: "https://example.com")!, transport: transport)
        let queue = InMemoryOfflineQueue(isOnline: { true })
        let limiter = EventRateLimiter(cooldowns: ["bathroom": 60])
        let svc = DosingService(client: client, queue: queue, limiter: limiter)

        let now = Date()
        // First call should go through
        await svc.perform(.logEvent(name: "bathroom", at: now))
        // Second call within cooldown should be dropped
        await svc.perform(.logEvent(name: "bathroom", at: now.addingTimeInterval(5)))

        XCTAssertEqual(callCount, 1, "Rate limiter should drop the duplicate within cooldown")
    }

    // MARK: - Action Equatable

    func test_action_equatable() {
        let a1 = DosingService.Action.takeDose(type: "dose1", at: Date(timeIntervalSince1970: 0))
        let a2 = DosingService.Action.takeDose(type: "dose1", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(a1, a2)
    }

    func test_action_codable_roundtrip() throws {
        let actions: [DosingService.Action] = [
            .takeDose(type: "dose1", at: Date(timeIntervalSince1970: 1000)),
            .skipDose(sequence: 2, reason: "felt_better"),
            .snooze(minutes: 10),
            .logEvent(name: "bathroom", at: Date(timeIntervalSince1970: 2000)),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for action in actions {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(DosingService.Action.self, from: data)
            XCTAssertEqual(decoded, action)
        }
    }
}
