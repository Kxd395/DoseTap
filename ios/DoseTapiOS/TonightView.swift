import SwiftUI
import DoseCore

struct TonightView: View {
    let context: DoseWindowContext
    let takeDose1: () -> Void
    let takeDose2: () -> Void
    let snooze: () -> Void
    let skipDose2: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(phaseLine).font(.headline)
            Text(remainingLine).font(.subheadline)
            HStack {
                if showDose1 { Button("Dose 1", action: takeDose1).buttonStyle(.borderedProminent) }
                if showDose2Take { Button("Dose 2", action: takeDose2).buttonStyle(.borderedProminent) }
                if showSnooze { Button("Snooze", action: snooze) }
                if showSkip { Button("Skip", action: skipDose2) }
            }
        }.padding()
    }

    private var showDose1: Bool { context.phase == .noDose1 }
    private var showDose2Take: Bool { context.phase == .active || context.phase == .nearClose }
    private var showSnooze: Bool {
        if case .snoozeEnabled = context.snooze { return true } else { return false }
    }
    private var showSkip: Bool {
        if case .skipEnabled = context.skip { return true } else { return false }
    }

    private var phaseLine: String {
        switch context.phase {
        case .noDose1: return "Log Dose 1"
        case .beforeWindow: return "Too Early"
        case .active: return "Dose 2 Window Open"
        case .nearClose: return "Dose 2 Window Closing"
        case .closed: return "Window Closed"
        case .completed: return "Completed"
        }
    }

    private var remainingLine: String {
        guard let rem = context.remainingToMax else { return "" }
        let m = Int(rem / 60)
        return "Remaining: \(m)m"
    }
}
