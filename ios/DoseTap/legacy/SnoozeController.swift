import Foundation

enum SnoozeRejectionReason: String, CaseIterable {
    case noDose1 = "No Dose 1 recorded"
    case tooEarlyForTarget = "Too early - target window not open"
    case windowExceeded = "Window exceeded - too late for Dose 2"
    case insufficientTimeRemaining = "Less than 15 minutes remaining"
    case dose2AlreadyTaken = "Dose 2 already taken"
}

struct SnoozeResult {
    let success: Bool
    let newTargetTime: Date?
    let rejectionReason: SnoozeRejectionReason?
    
    static func success(newTarget: Date) -> SnoozeResult {
        SnoozeResult(success: true, newTargetTime: newTarget, rejectionReason: nil)
    }
    
    static func rejected(_ reason: SnoozeRejectionReason) -> SnoozeResult {
        SnoozeResult(success: false, newTargetTime: nil, rejectionReason: reason)
    }
}

struct SnoozeController {
    let snoozeIntervalMin: Int = 10
    let minRemainingForSnoozeMin: Int = 15
    let timeEngine: TimeEngine
    let now: () -> Date
    
    init(timeEngine: TimeEngine = TimeEngine(), now: @escaping () -> Date = { Date() }) {
        self.timeEngine = timeEngine
        self.now = now
    }
    
    func canSnooze(dose1At: Date?, dose2Taken: Bool = false) -> SnoozeResult {
        guard let d1 = dose1At else {
            return .rejected(.noDose1)
        }
        
        if dose2Taken {
            return .rejected(.dose2AlreadyTaken)
        }
        
        let state = timeEngine.state(dose1At: d1)
        
        switch state {
        case .noDose1:
            return .rejected(.noDose1)
        case .waitingForTarget:
            return .rejected(.tooEarlyForTarget)
        case .windowExceeded:
            return .rejected(.windowExceeded)
        case .targetWindowOpen(_, let remainingToMax):
            let remainingMin = remainingToMax / 60
            if remainingMin < Double(minRemainingForSnoozeMin) {
                return .rejected(.insufficientTimeRemaining)
            }
            
            // Calculate new target (current time + snooze interval)
            let current = now()
            let newTarget = current.addingTimeInterval(Double(snoozeIntervalMin) * 60)
            
            // Ensure new target doesn't exceed window
            let maxTime = d1.addingTimeInterval(Double(timeEngine.config.maxIntervalMin) * 60)
            if newTarget > maxTime {
                return .rejected(.insufficientTimeRemaining)
            }
            
            return .success(newTarget: newTarget)
        }
    }
    
    func snooze(dose1At: Date?, dose2Taken: Bool = false) -> SnoozeResult {
        return canSnooze(dose1At: dose1At, dose2Taken: dose2Taken)
    }
}
