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
    
    // MARK: - Network Recovery Tests (GAP closure)
    
    /// Verify tasks queued while offline are executed when connectivity returns
    func test_networkRecovery_flushesQueuedTasks() async {
        var isOnline = false
        var executedCount = 0
        let exp = expectation(description: "all tasks executed")
        exp.expectedFulfillmentCount = 3
        
        let queue = InMemoryOfflineQueue(isOnline: { isOnline })
        
        // Queue 3 tasks while offline
        await queue.enqueue(AnyOfflineQueueTask { executedCount += 1; exp.fulfill() })
        await queue.enqueue(AnyOfflineQueueTask { executedCount += 1; exp.fulfill() })
        await queue.enqueue(AnyOfflineQueueTask { executedCount += 1; exp.fulfill() })
        
        // Flush while offline - nothing should execute
        await queue.flush()
        let pendingOffline = await queue.pending()
        XCTAssertEqual(pendingOffline.count, 3, "Tasks should remain queued while offline")
        XCTAssertEqual(executedCount, 0, "No tasks should execute while offline")
        
        // Simulate network recovery
        isOnline = true
        
        // Flush again - all tasks should execute
        await queue.flush()
        await fulfillment(of: [exp], timeout: 2)
        
        let pendingOnline = await queue.pending()
        XCTAssertTrue(pendingOnline.isEmpty, "Queue should be empty after recovery flush")
        XCTAssertEqual(executedCount, 3, "All 3 tasks should have executed")
    }
    
    /// Verify order is preserved during network recovery
    func test_networkRecovery_preservesTaskOrder() async {
        var isOnline = false
        var executionOrder: [Int] = []
        
        let queue = InMemoryOfflineQueue(isOnline: { isOnline })
        
        // Queue tasks with identifiable order
        await queue.enqueue(AnyOfflineQueueTask { executionOrder.append(1) })
        await queue.enqueue(AnyOfflineQueueTask { executionOrder.append(2) })
        await queue.enqueue(AnyOfflineQueueTask { executionOrder.append(3) })
        
        // Recover and flush
        isOnline = true
        await queue.flush()
        
        // Wait briefly for async execution
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(executionOrder, [1, 2, 3], "Tasks should execute in FIFO order")
    }
    
    /// Verify partial flush on intermittent connectivity
    /// When a task fails mid-flush, subsequent tasks may not execute in same flush cycle
    func test_intermittentConnectivity_taskFailureHandling() async {
        var executedTasks: [Int] = []
        
        var cfg = InMemoryOfflineQueue.Config()
        cfg.maxRetries = 1  // Fail fast for test
        cfg.backoffBaseSeconds = 0.01
        
        let queue = InMemoryOfflineQueue(config: cfg, isOnline: { true })
        
        // Queue 3 tasks, second one will always fail
        await queue.enqueue(AnyOfflineQueueTask { 
            executedTasks.append(1)
        })
        await queue.enqueue(AnyOfflineQueueTask { 
            throw NSError(domain: "network", code: -1009) // always fails
        })
        await queue.enqueue(AnyOfflineQueueTask { 
            executedTasks.append(3)
        })
        
        // Flush - task 1 succeeds, task 2 fails and is dropped, task 3 succeeds
        await queue.flush()
        
        // Wait for async execution
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertTrue(executedTasks.contains(1), "Task 1 should have executed")
        XCTAssertTrue(executedTasks.contains(3), "Task 3 should have executed despite task 2 failure")
        
        // Queue should be empty (all tasks processed or dropped)
        let pending = await queue.pending()
        XCTAssertTrue(pending.isEmpty, "Queue should be empty after flush")
    }
}
