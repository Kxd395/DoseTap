import XCTest
@testable import DoseCore

final class DoseUndoManagerTests: XCTestCase {
    
    // MARK: - Registration Tests
    
    func testRegister_setsCanUndo() async {
        let manager = DoseUndoManager()
        let action = UndoableAction.takeDose1(at: Date())
        
        await manager.register(action)
        
        let canUndo = await manager.canUndo
        XCTAssertTrue(canUndo)
    }
    
    func testRegister_returnWindowDuration() async {
        let manager = DoseUndoManager(windowSeconds: 5.0)
        let action = UndoableAction.takeDose1(at: Date())
        
        let remaining = await manager.register(action)
        
        XCTAssertEqual(remaining, 5.0)
    }
    
    func testRegister_storesPendingAction() async {
        let manager = DoseUndoManager()
        let action = UndoableAction.takeDose2(at: Date())
        
        await manager.register(action)
        
        let pending = await manager.pending
        XCTAssertEqual(pending, action)
    }
    
    // MARK: - Undo Tests
    
    func testUndo_withinWindow_succeeds() async {
        var now = Date()
        let manager = DoseUndoManager(windowSeconds: 5.0, now: { now })
        let action = UndoableAction.takeDose1(at: now)
        
        await manager.register(action)
        
        // Advance time by 3 seconds (within window)
        now = now.addingTimeInterval(3)
        
        let result = await manager.undo()
        
        if case .success(let undoneAction) = result {
            XCTAssertEqual(undoneAction, action)
        } else {
            XCTFail("Expected success, got \(result)")
        }
    }
    
    func testUndo_afterWindow_returnsExpired() async {
        var now = Date()
        let manager = DoseUndoManager(windowSeconds: 5.0, now: { now })
        let action = UndoableAction.takeDose1(at: now)
        
        await manager.register(action)
        
        // Advance time by 6 seconds (past window)
        now = now.addingTimeInterval(6)
        
        let result = await manager.undo()
        
        XCTAssertEqual(result, .expired)
    }
    
    func testUndo_withNoPending_returnsNoAction() async {
        let manager = DoseUndoManager()
        
        let result = await manager.undo()
        
        XCTAssertEqual(result, .noAction)
    }
    
    func testUndo_clearsPendingAction() async {
        let manager = DoseUndoManager()
        let action = UndoableAction.takeDose1(at: Date())
        
        await manager.register(action)
        _ = await manager.undo()
        
        let canUndo = await manager.canUndo
        XCTAssertFalse(canUndo)
    }
    
    // MARK: - Remaining Time Tests
    
    func testRemainingTime_decreasesOverTime() async {
        var now = Date()
        let manager = DoseUndoManager(windowSeconds: 5.0, now: { now })
        
        await manager.register(.takeDose1(at: now))
        
        // Initial remaining time
        let initial = await manager.remainingTime
        XCTAssertEqual(initial, 5.0, accuracy: 0.1)
        
        // After 2 seconds
        now = now.addingTimeInterval(2)
        let after2s = await manager.remainingTime
        XCTAssertEqual(after2s, 3.0, accuracy: 0.1)
        
        // After window
        now = now.addingTimeInterval(4)
        let afterWindow = await manager.remainingTime
        XCTAssertEqual(afterWindow, 0.0, accuracy: 0.1)
    }
    
    // MARK: - Callback Tests
    
    func testOnUndo_calledWhenUndoSucceeds() async {
        let manager = DoseUndoManager()
        let action = UndoableAction.skipDose(sequence: 2, reason: "test")
        var undoneAction: UndoableAction?
        
        await manager.setOnUndo { undoneAction = $0 }
        await manager.register(action)
        _ = await manager.undo()
        
        XCTAssertEqual(undoneAction, action)
    }
    
    func testOnCommit_calledWhenNewActionRegistered() async {
        let manager = DoseUndoManager()
        let action1 = UndoableAction.takeDose1(at: Date())
        let action2 = UndoableAction.snooze(minutes: 10)
        var committedAction: UndoableAction?
        
        await manager.setOnCommit { committedAction = $0 }
        await manager.register(action1)
        await manager.register(action2) // This should commit action1
        
        XCTAssertEqual(committedAction, action1)
    }
    
    // MARK: - Multiple Actions Tests
    
    func testRegister_replacesExistingPending() async {
        let manager = DoseUndoManager()
        let action1 = UndoableAction.takeDose1(at: Date())
        let action2 = UndoableAction.takeDose2(at: Date())
        
        await manager.register(action1)
        await manager.register(action2)
        
        let pending = await manager.pending
        XCTAssertEqual(pending, action2)
    }
    
    // MARK: - Default Window Tests
    
    func testDefaultWindow_is5Seconds() {
        XCTAssertEqual(DoseUndoManager.defaultWindowSeconds, 5.0)
    }
}

// MARK: - Test Helpers

extension DoseUndoManager {
    func setOnUndo(_ callback: @escaping (UndoableAction) -> Void) {
        self.onUndo = callback
    }
    
    func setOnCommit(_ callback: @escaping (UndoableAction) -> Void) {
        self.onCommit = callback
    }
}
