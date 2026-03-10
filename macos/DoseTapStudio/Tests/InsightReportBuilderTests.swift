import XCTest
@testable import DoseTapStudio

final class InsightReportBuilderTests: XCTestCase {
    func testProviderSummaryIncludesKeyMetrics() {
        let builder = InsightReportBuilder()
        let sessions = [
            makeSession(
                sessionDate: "2024-09-08",
                intervalMinutes: 165,
                late: false,
                skipped: false,
                stress: 2,
                sleepQuality: 4,
                readiness: 4
            ),
            makeSession(
                sessionDate: "2024-09-07",
                intervalMinutes: 250,
                late: true,
                skipped: false,
                stress: 5,
                sleepQuality: 2,
                readiness: 2
            )
        ]

        let summary = builder.buildProviderSummary(sessions: sessions)

        XCTAssertTrue(summary.contains("Included nights: 2"))
        XCTAssertTrue(summary.contains("Late Dose 2 nights: 1"))
        XCTAssertTrue(summary.contains("Average morning sleep quality: 3.0 / 5"))
        XCTAssertTrue(summary.contains("High-stress pre-sleep nights: 1"))
    }

    func testSessionCSVIncludesEscapedNotes() {
        let builder = InsightReportBuilder()
        let sessions = [
            makeSession(
                sessionDate: "2024-09-08",
                intervalMinutes: 165,
                late: false,
                skipped: false,
                stress: 3,
                sleepQuality: 4,
                readiness: 4,
                notes: "Needs, commas"
            )
        ]

        let csv = builder.buildSessionCSV(sessions: sessions)

        XCTAssertTrue(csv.contains("session_date,dose1_utc"))
        XCTAssertTrue(csv.contains("\"Needs, commas\""))
    }

    private func makeSession(
        sessionDate: String,
        intervalMinutes: Int,
        late: Bool,
        skipped: Bool,
        stress: Int,
        sleepQuality: Int,
        readiness: Int,
        notes: String? = nil
    ) -> InsightSession {
        let dose1 = ISO8601DateFormatter().date(from: "\(sessionDate)T22:00:00Z")!
        let dose2 = dose1.addingTimeInterval(TimeInterval(intervalMinutes * 60))

        return InsightSession(
            id: sessionDate,
            sessionDate: sessionDate,
            startedAt: dose1,
            endedAt: dose2,
            dose1Time: dose1,
            dose2Time: skipped ? nil : dose2,
            dose2Skipped: skipped,
            snoozeCount: 0,
            adherenceFlag: late ? "late" : "ok",
            sleepEfficiency: 85,
            whoopRecovery: 70,
            averageHeartRate: 62,
            notes: notes,
            events: [],
            preSleep: InsightPreSleepSummary(
                sessionId: sessionDate,
                completionState: "complete",
                loggedAtUTC: "\(sessionDate)T21:30:00Z",
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
            morning: InsightMorningSummary(
                submittedAtUTC: dose2.addingTimeInterval(8 * 60 * 60),
                sleepQuality: sleepQuality,
                feelRested: "mostly",
                grogginess: "mild",
                sleepInertiaDuration: "fiveToFifteen",
                dreamRecall: "some",
                mentalClarity: sleepQuality,
                mood: "steady",
                anxietyLevel: "low",
                stressLevel: 2,
                stressDrivers: [],
                readinessForDay: readiness,
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
