import SwiftUI
import DoseCore

@main
struct DoseTapApp: App {
    @State private var dose1Time: Date? = nil
    @State private var dose2Time: Date? = nil
    @State private var snoozeCount: Int = 0
    private let calc = DoseWindowCalculator()

    var body: some Scene {
        WindowGroup {
            TonightView(
                context: context,
                takeDose1: { dose1Time = Date() },
                takeDose2: { dose2Time = Date() },
                snooze: { snoozeCount += 1 },
                skipDose2: { dose2Time = Date() } // placeholder semantics
            )
        }
    }

    private var context: DoseWindowContext {
        calc.context(dose1At: dose1Time, dose2TakenAt: dose2Time, dose2Skipped: false, snoozeCount: snoozeCount)
    }
}
