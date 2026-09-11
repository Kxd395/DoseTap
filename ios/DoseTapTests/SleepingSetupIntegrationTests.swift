import XCTest
import DoseCore
@testable import DoseTap

@MainActor
final class SleepingSetupIntegrationTests: XCTestCase {
    private let night = "2026-09-09"
    private let identity = "synthetic-sleeping-setup-night"
    private var plan: SleepingSetup {
        var value = SleepingSetup(); value.arrangement = .partnerSameBed
        value.pets = .offBed; value.location = .usual
        return value
    }
    func testPreSleepStorageNormalizedExportAndNoAutomaticCarryForward() throws {
        let storage = EventStorage.inMemory()
        var answers = DoseTap.PreSleepLogAnswers(); answers.sleepingSetup = plan
        let saved = try storage.savePreSleepLogOrThrow(sessionId: identity, answers: answers)
        XCTAssertEqual(storage.fetchMostRecentPreSleepLog(sessionId: identity)?.answers?.sleepingSetup, plan)
        let responses = storage.preSleepResponsesByQuestionID(saved.answers!)
        let setup = try XCTUnwrap(responses["pre.sleeping_setup.v1"] as? [String: Any])
        XCTAssertEqual(setup["arrangement"] as? String, plan.arrangement?.rawValue)
        XCTAssertNil(answers.carriedForwardForNewNight(referenceDate: Date()).sleepingSetup)
        XCTAssertNil(storage.preSleepResponsesByQuestionID(.init())["pre.sleeping_setup.v1"])
    }
    func testMorningSaveReopenSnapshotAndExportWithoutLegacyRoomToggle() throws {
        let storage = EventStorage.inMemory()
        storage.startSession(sessionId: identity, sessionDate: night, start: Date(timeIntervalSince1970: 1788998400))
        let repo = SessionRepository(storage: storage)
        let model = MorningCheckInViewModel(sessionId: identity, sessionDate: night,
            loadRememberedSettings: false, plannedSetup: plan)
        XCTAssertNil(model.toStoredCheckIn().sleepEnvironmentJson)
        model.sleepingContext.selectConfirmation(.same)
        model.sleepingContext.impact = .disrupted; model.sleepingContext.factors = [.noise, .pets]
        XCTAssertFalse(model.hasSleepEnvironment)
        XCTAssertTrue(repo.saveMorningCheckIn(model.toStoredCheckIn(), sessionDateOverride: night))
        let saved = try XCTUnwrap(storage.fetchStoredMorningCheckIn(sessionKey: identity))
        let reopened = MorningCheckInViewModel(sessionId: identity, sessionDate: night, existing: saved)
        XCTAssertEqual(reopened.sleepingContext.plan, plan)
        XCTAssertEqual(reopened.sleepingContext.actual, plan)
        XCTAssertEqual(reopened.sleepingContext.impact, .disrupted)
        let normalized = storage.morningResponsesByQuestionID(saved)
        XCTAssertNotNil(normalized["sleeping_context.v1"])
        let data = try StudioBundleExporter().buildStudioInsightsBundleDataForTesting(using: repo, sessionDates: [night])
        let bundle = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try XCTUnwrap((bundle["sessions"] as? [[String: Any]])?.first)
        let morning = try XCTUnwrap(session["morning"] as? [String: Any])
        let raw = try XCTUnwrap(morning["rawSleepEnvironmentJson"] as? String)
        XCTAssertTrue(raw.contains("sleepingContext")); XCTAssertTrue(raw.contains("Partner in the same bed"))
        reopened.sleepingContext.selectConfirmation(.changed)
        reopened.sleepingContext.actual = SleepingSetup(); reopened.sleepingContext.actual?.arrangement = .alone
        XCTAssertEqual(reopened.sleepingContext.plan, plan)
        XCTAssertTrue(repo.saveMorningCheckIn(reopened.toStoredCheckIn(), sessionDateOverride: night))
        let changed = try XCTUnwrap(storage.fetchStoredMorningCheckIn(sessionKey: identity))
        XCTAssertEqual(MorningCheckInViewModel(sessionId: identity, sessionDate: night, existing: changed).sleepingContext.actual?.arrangement, .alone)
        let fresh = MorningCheckInViewModel(sessionId: "next", sessionDate: "2026-09-10", loadRememberedSettings: false)
        XCTAssertNil(fresh.sleepingContext.confirmation); XCTAssertNil(fresh.sleepingContext.impact)
        XCTAssertTrue(repo.fetchDoseEvents(forSessionDate: night).isEmpty)
    }
    func testMatchingPlanRequiresExactSessionAndCompletedLog() throws {
        let storage = EventStorage.inMemory(); let repo = SessionRepository(storage: storage)
        var answers = DoseTap.PreSleepLogAnswers(); answers.sleepingSetup = plan
        try storage.savePreSleepLogOrThrow(sessionId: identity, answers: answers)
        XCTAssertEqual(repo.plannedSleepingSetup(sessionID: identity), plan)
        XCTAssertNil(repo.plannedSleepingSetup(sessionID: "other-night"))
        try storage.savePreSleepLogOrThrow(sessionId: "skipped", answers: answers, completionState: "skipped")
        XCTAssertNil(repo.plannedSleepingSetup(sessionID: "skipped"))
    }
}
