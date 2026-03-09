import XCTest
@testable import DoseTapStudio

final class InsightAdherenceAnalyzerTests: XCTestCase {
    func testBucketSummaryCountsEachOutcomeType() {
        let analyzer = InsightAdherenceAnalyzer()
        let sessions = [
            makeSession(date: "2024-09-08", interval: 140, skipped: false, stress: 2),
            makeSession(date: "2024-09-07", interval: 165, skipped: false, stress: 2),
            makeSession(date: "2024-09-06", interval: 250, skipped: false, stress: 5),
            makeSession(date: "2024-09-05", interval: nil, skipped: true, stress: 4),
            makeSession(date: "2024-09-04", interval: nil, skipped: false, stress: 1)
        ]

        let summary = analyzer.bucketSummary(sessions: sessions)

        XCTAssertEqual(summary.early, 1)
        XCTAssertEqual(summary.onTime, 1)
        XCTAssertEqual(summary.late, 1)
        XCTAssertEqual(summary.skipped, 1)
        XCTAssertEqual(summary.missingOutcome, 1)
    }

    func testStressSummarySeparatesHighAndLowStressRates() {
        let analyzer = InsightAdherenceAnalyzer()
        let sessions = [
            makeSession(date: "2024-09-08", interval: 165, skipped: false, stress: 5),
            makeSession(date: "2024-09-07", interval: 250, skipped: false, stress: 4),
            makeSession(date: "2024-09-06", interval: 165, skipped: false, stress: 1),
            makeSession(date: "2024-09-05", interval: 165, skipped: false, stress: 2)
        ]

        let summary = analyzer.stressSummary(sessions: sessions)

        XCTAssertEqual(summary.highStressNightCount, 2)
        XCTAssertEqual(summary.lowStressNightCount, 2)
        XCTAssertEqual(summary.highStressOnTimeRate, 0.5)
        XCTAssertEqual(summary.lowStressOnTimeRate, 1.0)
    }

    private func makeSession(date: String, interval: Int?, skipped: Bool, stress: Int) -> InsightSession {
        let formatter = ISO8601DateFormatter()
        let dose1 = formatter.date(from: "\(date)T22:00:00Z")!
        let dose2 = interval.map { dose1.addingTimeInterval(TimeInterval($0 * 60)) }

        return InsightSession(
            id: date,
            sessionDate: date,
            startedAt: dose1,
            endedAt: dose2,
            dose1Time: dose1,
            dose2Time: skipped ? nil : dose2,
            dose2Skipped: skipped,
            snoozeCount: 0,
            adherenceFlag: skipped ? "missed" : nil,
            sleepEfficiency: nil,
            whoopRecovery: nil,
            averageHeartRate: nil,
            notes: nil,
            events: [],
            preSleep: InsightPreSleepSummary(
                sessionId: date,
                completionState: "complete",
                loggedAtUTC: "\(date)T21:30:00Z",
                stressLevel: stress,
                stressDrivers: [],
                laterReason: nil,
                bodyPain: nil,
                caffeineSources: [],
                alcohol: nil,
                exercise: nil,
                napToday: nil,
                lateMeal: nil,
                screensInBed: nil,
                roomTemp: nil,
                noiseLevel: nil,
                sleepAids: [],
                notes: nil
            ),
            morning: interval == nil && !skipped ? nil : InsightMorningSummary(
                submittedAtUTC: dose1.addingTimeInterval(8 * 60 * 60),
                sleepQuality: 4,
                feelRested: "mostly",
                grogginess: "mild",
                sleepInertiaDuration: "fiveToFifteen",
                dreamRecall: "some",
                mentalClarity: 4,
                mood: "steady",
                anxietyLevel: "low",
                stressLevel: 2,
                stressDrivers: [],
                readinessForDay: 4,
                hadSleepParalysis: false,
                hadHallucinations: false,
                hadAutomaticBehavior: false,
                fellOutOfBed: false,
                hadConfusionOnWaking: false,
                notes: nil
            ),
            medications: []
        )
    }
}
