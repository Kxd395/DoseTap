import XCTest
@testable import DoseCore

final class OfflineQueueTests: XCTestCase {
    func test_enqueue_and_flush_success() async {
        let exp = expectation(description: "executed")
        let queue = InMemoryOfflineQueue(isOnline: { true })
    await queue.enqueue(AnyOfflineQueueTask { exp.fulfill() })
        await queue.flush()
        await fulfillment(of: [exp], timeout: 1)
    let remaining = await queue.pending()
    XCTAssertTrue(remaining.isEmpty)
    }

    func test_offline_no_flush() async {
        let queue = InMemoryOfflineQueue(isOnline: { false })
    await queue.enqueue(AnyOfflineQueueTask { })
        await queue.flush()
    let p1 = await queue.pending()
    XCTAssertEqual(p1.count, 1)
    }

    func test_retry_on_failure_then_succeed() async {
        var attempts = 0
        let exp = expectation(description: "succeeded later")
        let queue = InMemoryOfflineQueue(isOnline: { true })
    await queue.enqueue(AnyOfflineQueueTask { 
            attempts += 1
            if attempts < 2 { throw NSError(domain: "test", code: 1) }
            exp.fulfill()
        })
        await queue.flush()
        await fulfillment(of: [exp], timeout: 5)
    let p2 = await queue.pending()
    XCTAssertTrue(p2.isEmpty)
    }

    func test_max_retries_drops_task() async {
        var attempts = 0
    var cfg = InMemoryOfflineQueue.Config()
    cfg.maxRetries = 2
    cfg.backoffBaseSeconds = 0.01
    let queue = InMemoryOfflineQueue(config: cfg, isOnline: { true })
    await queue.enqueue(AnyOfflineQueueTask { 
            attempts += 1
            throw NSError(domain: "test", code: 1)
        })
        await queue.flush()
    let p3 = await queue.pending()
    XCTAssertTrue(p3.isEmpty)
        XCTAssertGreaterThanOrEqual(attempts, 2)
    }
}
