import XCTest
import SQLite3
@testable import DoseTap
import DoseCore

@MainActor
final class EventStorageIntegrationTests: XCTestCase {
    private var storage: EventStorage!
    private var iso: ISO8601DateFormatter!

    override func setUp() async throws {
        storage = EventStorage.inMemory()
        iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    override func tearDown() async throws {
        storage = nil
        iso = nil
    }

    func test_schemaUserVersion_isAppliedOnInitialization() {
        XCTAssertEqual(storage.getSchemaVersion(), EventStorage.schemaUserVersion)
    }

    func test_schemaInitialization_isIdempotentForExistingColumns() {
        storage.createTables()
        storage.createTables()

        XCTAssertEqual(storage.getSchemaVersion(), EventStorage.schemaUserVersion)
    }

    func test_doseStateInvariant_passesForCanonicalDosePair() {
        let sessionDate = "2026-02-12"
        storage.saveDose1(
            timestamp: makeDate("2026-02-12T22:05:00.000Z"),
            sessionId: sessionDate,
            sessionDateOverride: sessionDate
        )
        storage.saveDose2(
            timestamp: makeDate("2026-02-13T02:30:00.000Z"),
            isEarly: false,
            isExtraDose: false,
            isLate: false,
            sessionId: sessionDate,
            sessionDateOverride: sessionDate
        )

        XCTAssertTrue(storage.validateActiveDoseStateInvariant().isEmpty)
    }

    func test_eventStoreProtocolClearDose2_keepsEventLogAndSnapshotConsistent() {
        let sessionDate = "2026-02-12"
        storage.saveDose1(
            timestamp: makeDate("2026-02-12T22:05:00.000Z"),
            sessionId: sessionDate,
            sessionDateOverride: sessionDate
        )
        storage.saveDose2(
            timestamp: makeDate("2026-02-13T02:30:00.000Z"),
            isEarly: false,
            isExtraDose: false,
            isLate: false,
            sessionId: sessionDate,
            sessionDateOverride: sessionDate
        )

        let eventStore: EventStore = storage
        eventStore.clearDose2()

        XCTAssertTrue(storage.validateActiveDoseStateInvariant().isEmpty)
        XCTAssertNil(storage.loadCurrentSessionState().dose2Time)
        XCTAssertFalse(storage.fetchDoseEvents(sessionId: sessionDate, sessionDate: sessionDate).contains { $0.eventType == "dose2" })
    }

    func test_doseStateInvariant_detectsDoseEventSnapshotDrift() {
        let sessionDate = "2026-02-12"
        storage.saveDose1(
            timestamp: makeDate("2026-02-12T22:05:00.000Z"),
            sessionId: sessionDate,
            sessionDateOverride: sessionDate
        )
        storage.saveDose2(
            timestamp: makeDate("2026-02-13T02:30:00.000Z"),
            isEarly: false,
            isExtraDose: false,
            isLate: false,
            sessionId: sessionDate,
            sessionDateOverride: sessionDate
        )

        execSQL("UPDATE current_session SET dose2_time = NULL WHERE id = 1")

        let violationCodes = Set(storage.validateActiveDoseStateInvariant().map(\.code))
        XCTAssertTrue(violationCodes.contains("dose2_event_without_snapshot"))
    }

    func test_doseStateInvariant_detectsNonCanonicalActiveDoseEventType() {
        let sessionDate = "2026-02-12"
        storage.saveDose1(
            timestamp: makeDate("2026-02-12T22:05:00.000Z"),
            sessionId: sessionDate,
            sessionDateOverride: sessionDate
        )
        storage.saveDose2(
            timestamp: makeDate("2026-02-13T02:30:00.000Z"),
            isEarly: false,
            isExtraDose: false,
            isLate: false,
            sessionId: sessionDate,
            sessionDateOverride: sessionDate
        )

        execSQL("UPDATE dose_events SET event_type = 'dose_2' WHERE session_date = '\(sessionDate)' AND event_type = 'dose2'")

        let violationCodes = Set(storage.validateActiveDoseStateInvariant().map(\.code))
        XCTAssertTrue(violationCodes.contains("non_canonical_dose_event_type"))
    }

    func test_importDoseEventCanonicalizesLegacyAlias() {
        let sessionDate = "2026-02-12"

        storage.upsertDoseEvent(
            id: "legacy-dose-2",
            eventType: "dose_2",
            timestamp: makeDate("2026-02-13T02:30:00.000Z"),
            sessionDate: sessionDate,
            sessionId: sessionDate,
            metadata: nil
        )

        let events = storage.fetchDoseEvents(sessionId: sessionDate, sessionDate: sessionDate)
        XCTAssertEqual(events.map(\.eventType), ["dose2"])
    }

    func test_importDoseEventRejectsUnknownDoseEventType() {
        let sessionDate = "2026-02-12"

        storage.upsertDoseEvent(
            id: "bad-dose-event",
            eventType: "lights_out",
            timestamp: makeDate("2026-02-13T02:30:00.000Z"),
            sessionDate: sessionDate,
            sessionId: sessionDate,
            metadata: nil
        )

        XCTAssertTrue(storage.fetchDoseEvents(sessionId: sessionDate, sessionDate: sessionDate).isEmpty)
    }

    func test_fetchRecentSessionsLocal_handlesSleepOnlyDoseOnlyAndMixedSessions() {
        let sleepOnlyDate = "2026-02-10"
        let doseOnlyDate = "2026-02-11"
        let mixedDate = "2026-02-12"

        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "lights_out",
            timestamp: makeDate("2026-02-10T23:10:00.000Z"),
            sessionDate: sleepOnlyDate,
            sessionId: sleepOnlyDate,
            colorHex: nil,
            notes: nil
        )

        storage.insertDoseEvent(
            eventType: "dose1",
            timestamp: makeDate("2026-02-11T22:00:00.000Z"),
            sessionDate: doseOnlyDate,
            sessionId: doseOnlyDate,
            metadata: nil
        )

        storage.insertDoseEvent(
            eventType: "dose1",
            timestamp: makeDate("2026-02-12T22:05:00.000Z"),
            sessionDate: mixedDate,
            sessionId: mixedDate,
            metadata: nil
        )
        storage.insertDoseEvent(
            eventType: "snooze",
            timestamp: makeDate("2026-02-12T22:30:00.000Z"),
            sessionDate: mixedDate,
            sessionId: mixedDate,
            metadata: nil
        )
        storage.insertSleepEvent(
            id: UUID().uuidString,
            eventType: "asleep",
            timestamp: makeDate("2026-02-12T23:00:00.000Z"),
            sessionDate: mixedDate,
            sessionId: mixedDate,
            colorHex: nil,
            notes: nil
        )

        let sessions = storage.fetchRecentSessionsLocal(days: 10)
        let keyed = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionDate, $0) })

        XCTAssertEqual(keyed.count, 3)

        let sleepOnly = tryUnwrap(keyed[sleepOnlyDate])
        XCTAssertNil(sleepOnly.dose1Time)
        XCTAssertEqual(sleepOnly.eventCount, 1)

        let doseOnly = tryUnwrap(keyed[doseOnlyDate])
        XCTAssertNotNil(doseOnly.dose1Time)
        XCTAssertEqual(doseOnly.eventCount, 0)

        let mixed = tryUnwrap(keyed[mixedDate])
        XCTAssertNotNil(mixed.dose1Time)
        XCTAssertEqual(mixed.snoozeCount, 1)
        XCTAssertEqual(mixed.eventCount, 1)
    }

    func test_fetchDoseLog_returnsCurrentAndHistoricalSessionData() {
        let historicalDate = "2026-02-11"
        let currentDate = "2026-02-12"

        let historicalDose1 = makeDate("2026-02-11T22:00:00.000Z")
        storage.insertDoseEvent(
            eventType: "dose1",
            timestamp: historicalDose1,
            sessionDate: historicalDate,
            sessionId: historicalDate,
            metadata: nil
        )
        storage.insertDoseEvent(
            eventType: "snooze",
            timestamp: makeDate("2026-02-11T22:20:00.000Z"),
            sessionDate: historicalDate,
            sessionId: historicalDate,
            metadata: nil
        )

        let currentDose1 = makeDate("2026-02-12T22:05:00.000Z")
        let currentDose2 = makeDate("2026-02-13T02:30:00.000Z")
        storage.saveDose1(timestamp: currentDose1, sessionId: currentDate, sessionDateOverride: currentDate)
        storage.saveDose2(timestamp: currentDose2, isEarly: false, isExtraDose: false, isLate: false, sessionId: currentDate, sessionDateOverride: currentDate)

        let historicalLog = tryUnwrap(storage.fetchDoseLog(forSession: historicalDate))
        XCTAssertEqual(historicalLog.sessionDate, historicalDate)
        XCTAssertEqual(historicalLog.snoozeCount, 1)
        XCTAssertEqual(historicalLog.dose1Time.timeIntervalSince1970, historicalDose1.timeIntervalSince1970, accuracy: 0.001)

        let currentLog = tryUnwrap(storage.fetchDoseLog(forSession: currentDate))
        XCTAssertEqual(currentLog.sessionDate, currentDate)
        XCTAssertNotNil(currentLog.dose1Time)
        XCTAssertNotNil(currentLog.dose2Time)
        XCTAssertEqual(currentLog.dose1Time.timeIntervalSince1970, currentDose1.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(tryUnwrap(currentLog.dose2Time).timeIntervalSince1970, currentDose2.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_sessionDiscovery_includesMorningMedicationAndPreSleepOnlySessions() throws {
        let morningOnlyDate = "2026-02-13"
        let medicationOnlyDate = "2026-02-14"
        let preSleepOnlyDate = "2026-02-15"

        storage.saveMorningCheckIn(
            StoredMorningCheckIn(
                id: UUID().uuidString,
                sessionId: morningOnlyDate,
                timestamp: makeDate("2026-02-14T12:00:00.000Z"),
                sessionDate: morningOnlyDate,
                sleepQuality: 4
            ),
            forSession: morningOnlyDate
        )

        storage.insertMedicationEvent(
            StoredMedicationEntry(
                sessionId: medicationOnlyDate,
                sessionDate: medicationOnlyDate,
                medicationId: "adderall_xr",
                doseMg: 10,
                takenAtUTC: makeDate("2026-02-14T23:00:00.000Z"),
                doseUnit: "mg",
                formulation: "xr",
                localOffsetMinutes: 0,
                notes: "with food"
            )
        )

        _ = try storage.savePreSleepLogOrThrow(
            sessionId: preSleepOnlyDate,
            answers: PreSleepLogAnswers(stressLevel: 2),
            completionState: "complete",
            now: makeDate("2026-02-15T21:00:00.000Z"),
            timeZone: TimeZone(identifier: "UTC")!
        )

        let dates = storage.getAllSessionDates()
        XCTAssertEqual(Set(dates), Set([morningOnlyDate, medicationOnlyDate, preSleepOnlyDate]))

        let sessions = storage.fetchRecentSessionsLocal(days: 10)
        let keyed = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionDate, $0) })

        XCTAssertEqual(keyed.count, 3)
        XCTAssertNil(keyed[morningOnlyDate]?.dose1Time)
        XCTAssertEqual(keyed[morningOnlyDate]?.eventCount, 0)
        XCTAssertNil(keyed[medicationOnlyDate]?.dose1Time)
        XCTAssertEqual(keyed[medicationOnlyDate]?.eventCount, 0)
        XCTAssertNil(keyed[preSleepOnlyDate]?.dose1Time)
        XCTAssertEqual(keyed[preSleepOnlyDate]?.eventCount, 0)
    }

    func test_symptomEventSchema_isIdempotentAndDiscoverable() throws {
        let sessionDate = "2026-02-18"

        storage.createTables()
        storage.createTables()

        let event = try makeSymptomEvent(
            id: "symptom-schema-1",
            sessionId: "symptom-session-schema",
            sessionDate: sessionDate,
            noticedAt: "2026-02-19T03:20:00.000Z"
        )
        try storage.recordSymptomEvent(event, idempotencyKey: "night:symptom-schema-1")

        XCTAssertEqual(storage.getSchemaVersion(), EventStorage.schemaUserVersion)
        XCTAssertTrue(storage.getAllSessionDates().contains(sessionDate))
    }

    func test_recordSymptomEvent_persistsLocationsPointsAndSummary() throws {
        let sessionDate = "2026-02-18"
        let event = try makeSymptomEvent(
            id: "symptom-persist-1",
            sessionId: "symptom-session-persist",
            sessionDate: sessionDate,
            noticedAt: "2026-02-19T03:20:00.000Z"
        )

        let saved = try storage.recordSymptomEvent(event, idempotencyKey: "night:symptom-persist-1")

        XCTAssertEqual(saved.id, event.id)

        let fetched = storage.fetchSymptomEvents(sessionDate: sessionDate)
        XCTAssertEqual(fetched.count, 1)

        let symptom = tryUnwrap(fetched.first)
        XCTAssertEqual(symptom.id, event.id)
        XCTAssertEqual(symptom.sessionId, "symptom-session-persist")
        XCTAssertEqual(symptom.phase, .nightLog)
        XCTAssertEqual(symptom.source, .nightQuickLog)
        XCTAssertEqual(symptom.kind, .numbness)
        XCTAssertEqual(symptom.severity0to10, 6)
        XCTAssertTrue(symptom.sleepDisruption)
        XCTAssertTrue(symptom.stillPresent)
        XCTAssertEqual(symptom.functionalImpact, "hard_to_grip")
        XCTAssertEqual(symptom.note, "Woke up with left pinky numbness.")

        let location = tryUnwrap(symptom.locations.first)
        XCTAssertEqual(location.bodySide, .left)
        XCTAssertEqual(location.bodyRegionId, "hand.left.pinky")
        XCTAssertEqual(location.anatomyLayer, .nerveLike)
        XCTAssertEqual(location.precision, .point)
        XCTAssertEqual(location.confidence, .exact)

        let point = tryUnwrap(location.points.first)
        XCTAssertEqual(point.mapId, "hand.left.v1")
        XCTAssertEqual(point.normalizedX, 0.25, accuracy: 0.001)
        XCTAssertEqual(point.normalizedY, 0.75, accuracy: 0.001)
        XCTAssertEqual(point.zoomLevel, 2.0, accuracy: 0.001)
        XCTAssertEqual(point.bodyView, .palm)

        let summary = tryUnwrap(storage.fetchSymptomSummary(sessionDate: sessionDate))
        XCTAssertEqual(summary.sessionDate, sessionDate)
        XCTAssertEqual(summary.sessionId, "symptom-session-persist")
        XCTAssertEqual(summary.symptomCount, 1)
        XCTAssertEqual(summary.highestSeverity, 6)
        XCTAssertEqual(summary.sleepDisruptionCount, 1)
        XCTAssertEqual(summary.stillPresentCount, 1)
    }

    func test_recordSymptomEvent_isIdempotentByCommandKey() throws {
        let sessionDate = "2026-02-19"
        let firstEvent = try makeSymptomEvent(
            id: "symptom-idempotent-1",
            sessionId: "symptom-session-idempotent",
            sessionDate: sessionDate,
            noticedAt: "2026-02-20T02:45:00.000Z",
            severity0to10: 4
        )
        let duplicateCommandEvent = try makeSymptomEvent(
            id: "symptom-idempotent-2",
            sessionId: "symptom-session-idempotent",
            sessionDate: sessionDate,
            noticedAt: "2026-02-20T03:00:00.000Z",
            severity0to10: 9,
            kind: .burning
        )

        let firstSaved = try storage.recordSymptomEvent(firstEvent, idempotencyKey: "body-map:same-command")
        let secondSaved = try storage.recordSymptomEvent(duplicateCommandEvent, idempotencyKey: "body-map:same-command")

        XCTAssertEqual(firstSaved.id, "symptom-idempotent-1")
        XCTAssertEqual(secondSaved.id, "symptom-idempotent-1")
        XCTAssertEqual(storage.fetchSymptomEvents(sessionDate: sessionDate).map(\.id), ["symptom-idempotent-1"])

        let summary = tryUnwrap(storage.fetchSymptomSummary(sessionDate: sessionDate))
        XCTAssertEqual(summary.symptomCount, 1)
        XCTAssertEqual(summary.highestSeverity, 4)
    }

    func test_replaceSymptomEvents_replacesSourceRecordRowsAndClearsSummary() throws {
        let sessionDate = "2026-02-21"
        let first = try makeSymptomEvent(
            id: "symptom-source-1",
            sessionId: "symptom-session-source",
            sessionDate: sessionDate,
            noticedAt: "2026-02-22T03:00:00.000Z",
            severity0to10: 3,
            phase: .preSleep,
            source: .preSleep,
            sourceRecordId: "pre-log-1",
            sourceEntryKey: "lower_back|both"
        )
        let second = try makeSymptomEvent(
            id: "symptom-source-2",
            sessionId: "symptom-session-source",
            sessionDate: sessionDate,
            noticedAt: "2026-02-22T03:01:00.000Z",
            severity0to10: 7,
            phase: .preSleep,
            source: .preSleep,
            sourceRecordId: "pre-log-1",
            sourceEntryKey: "wrist_hand|left"
        )

        try storage.replaceSymptomEvents(
            source: .preSleep,
            sourceRecordId: "pre-log-1",
            sessionDate: sessionDate,
            events: [first, second]
        )

        XCTAssertEqual(storage.fetchSymptomEvents(sessionDate: sessionDate).map(\.id), ["symptom-source-1", "symptom-source-2"])
        XCTAssertEqual(tryUnwrap(storage.fetchSymptomSummary(sessionDate: sessionDate)).symptomCount, 2)
        XCTAssertEqual(scalarInt("SELECT COUNT(*) FROM symptom_command_log WHERE source = 'pre_sleep' AND source_record_id = 'pre-log-1'"), 2)

        let replacement = try makeSymptomEvent(
            id: "symptom-source-3",
            sessionId: "symptom-session-source",
            sessionDate: sessionDate,
            noticedAt: "2026-02-22T03:02:00.000Z",
            severity0to10: 8,
            phase: .preSleep,
            source: .preSleep,
            sourceRecordId: "pre-log-1",
            sourceEntryKey: "lower_back|both"
        )

        try storage.replaceSymptomEvents(
            source: .preSleep,
            sourceRecordId: "pre-log-1",
            sessionDate: sessionDate,
            events: [replacement]
        )

        let fetched = storage.fetchSymptomEvents(sessionDate: sessionDate)
        XCTAssertEqual(fetched.map(\.id), ["symptom-source-3"])
        XCTAssertEqual(tryUnwrap(fetched.first).sourceRecordId, "pre-log-1")
        XCTAssertEqual(tryUnwrap(fetched.first).sourceEntryKey, "lower_back|both")
        XCTAssertEqual(tryUnwrap(storage.fetchSymptomSummary(sessionDate: sessionDate)).highestSeverity, 8)
        XCTAssertEqual(scalarInt("SELECT COUNT(*) FROM symptom_command_log WHERE source = 'pre_sleep' AND source_record_id = 'pre-log-1'"), 1)

        try storage.replaceSymptomEvents(
            source: .preSleep,
            sourceRecordId: "pre-log-1",
            sessionDate: sessionDate,
            events: []
        )

        XCTAssertTrue(storage.fetchSymptomEvents(sessionDate: sessionDate).isEmpty)
        XCTAssertNil(storage.fetchSymptomSummary(sessionDate: sessionDate))
        XCTAssertEqual(scalarInt("SELECT COUNT(*) FROM symptom_command_log WHERE source = 'pre_sleep' AND source_record_id = 'pre-log-1'"), 0)
    }

    func test_preSleepPainEntries_replaceDerivedSymptomEventsOnEdit() throws {
        let sessionDate = "2026-02-22"
        let firstAnswers = PreSleepLogAnswers(
            bodyPain: .moderate,
            painEntries: [
                PreSleepLogAnswers.PainEntry(
                    area: .lowerBack,
                    side: .both,
                    intensity: 6,
                    sensations: [.burning],
                    pattern: .constant,
                    notes: "Before bed."
                )
            ]
        )

        let log = try storage.savePreSleepLogOrThrow(
            sessionId: sessionDate,
            answers: firstAnswers,
            completionState: "complete",
            now: makeDate("2026-02-22T23:00:00.000Z"),
            timeZone: TimeZone(identifier: "UTC")!
        )

        var fetched = storage.fetchSymptomEvents(sessionDate: sessionDate)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(tryUnwrap(fetched.first).source, .preSleep)
        XCTAssertEqual(tryUnwrap(fetched.first).sourceRecordId, log.id)
        XCTAssertEqual(tryUnwrap(fetched.first).sourceEntryKey, "lower_back|both")
        XCTAssertEqual(tryUnwrap(fetched.first).kind, .burning)

        let editedAnswers = PreSleepLogAnswers(
            bodyPain: .severe,
            painEntries: [
                PreSleepLogAnswers.PainEntry(
                    area: .wristHand,
                    side: .right,
                    intensity: 8,
                    sensations: [.pinsNeedles],
                    pattern: .intermittent,
                    notes: "Edited."
                )
            ]
        )
        _ = try storage.savePreSleepLogOrThrow(
            sessionId: sessionDate,
            answers: editedAnswers,
            completionState: "complete",
            now: makeDate("2026-02-22T23:05:00.000Z"),
            timeZone: TimeZone(identifier: "UTC")!,
            existingLog: log
        )

        fetched = storage.fetchSymptomEvents(sessionDate: sessionDate)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(tryUnwrap(fetched.first).sourceRecordId, log.id)
        XCTAssertEqual(tryUnwrap(fetched.first).sourceEntryKey, "wrist_hand|right")
        XCTAssertEqual(tryUnwrap(fetched.first).severity0to10, 8)
        XCTAssertEqual(tryUnwrap(fetched.first).kind, .pinsNeedles)
        XCTAssertEqual(tryUnwrap(storage.fetchSymptomSummary(sessionDate: sessionDate)).symptomCount, 1)
    }

    func test_preSleepSave_rollsBackSourceRowsWhenDerivedSymptomReplacementFails() throws {
        let sessionDate = "2026-02-24"
        let answers = PreSleepLogAnswers(
            bodyPain: .moderate,
            painEntries: [
                PreSleepLogAnswers.PainEntry(
                    area: .lowerBack,
                    side: .both,
                    intensity: 6,
                    sensations: [.burning],
                    pattern: .constant,
                    notes: "Before bed."
                )
            ]
        )

        execSQL("DROP TABLE symptom_command_log")

        XCTAssertThrowsError(
            try storage.savePreSleepLogOrThrow(
                sessionId: sessionDate,
                answers: answers,
                completionState: "complete",
                now: makeDate("2026-02-24T23:00:00.000Z"),
                timeZone: TimeZone(identifier: "UTC")!
            )
        )
        XCTAssertEqual(storage.fetchPreSleepLogCount(sessionId: sessionDate), 0)
        XCTAssertEqual(storage.fetchCheckInSubmissionCount(sessionDate: sessionDate, checkInType: .preNight), 0)
    }

    func test_preSleepEdit_rollsBackSourceRowsWhenDerivedSymptomReplacementFails() throws {
        let sessionDate = "2026-02-25"
        let firstAnswers = PreSleepLogAnswers(
            bodyPain: .moderate,
            painEntries: [
                PreSleepLogAnswers.PainEntry(
                    area: .lowerBack,
                    side: .both,
                    intensity: 6,
                    sensations: [.burning],
                    pattern: .constant,
                    notes: nil
                )
            ]
        )
        let log = try storage.savePreSleepLogOrThrow(
            sessionId: sessionDate,
            answers: firstAnswers,
            completionState: "complete",
            now: makeDate("2026-02-25T23:00:00.000Z"),
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertEqual(storage.fetchCheckInSubmissionCount(sessionDate: sessionDate, checkInType: .preNight), 1)

        execSQL("DROP TABLE symptom_command_log")

        let editedAnswers = PreSleepLogAnswers(
            bodyPain: .severe,
            painEntries: [
                PreSleepLogAnswers.PainEntry(
                    area: .wristHand,
                    side: .right,
                    intensity: 8,
                    sensations: [.pinsNeedles],
                    pattern: .intermittent,
                    notes: "Edited."
                )
            ]
        )
        XCTAssertThrowsError(
            try storage.savePreSleepLogOrThrow(
                sessionId: sessionDate,
                answers: editedAnswers,
                completionState: "complete",
                now: makeDate("2026-02-25T23:05:00.000Z"),
                timeZone: TimeZone(identifier: "UTC")!,
                existingLog: log
            )
        )

        let fetched = tryUnwrap(storage.fetchMostRecentPreSleepLog(sessionId: sessionDate))
        XCTAssertEqual(fetched.answers?.bodyPain, .moderate)
        XCTAssertEqual(storage.fetchCheckInSubmissionCount(sessionDate: sessionDate, checkInType: .preNight), 1)
    }

    func test_morningPainEntries_replaceAndClearDerivedSymptomEvents() throws {
        let sessionDate = "2026-02-23"
        let physicalJson = #"{"painEntries":[{"entry_key":"lower_back|both","area":"lower_back","side":"both","intensity":8,"sensations":["burning","tightness"],"pattern":"constant","notes":"Woke with pain."}]}"#
        let checkIn = DoseTap.StoredMorningCheckIn(
            id: "morning-symptom-1",
            sessionId: sessionDate,
            timestamp: makeDate("2026-02-24T12:00:00.000Z"),
            sessionDate: sessionDate,
            sleepQuality: 3,
            hasPhysicalSymptoms: true,
            physicalSymptomsJson: physicalJson
        )

        storage.saveMorningCheckIn(checkIn, forSession: sessionDate)

        var fetched = storage.fetchSymptomEvents(sessionDate: sessionDate)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(tryUnwrap(fetched.first).source, .morningReview)
        XCTAssertEqual(tryUnwrap(fetched.first).sourceRecordId, "morning-symptom-1")
        XCTAssertEqual(tryUnwrap(fetched.first).sourceEntryKey, "lower_back|both")
        XCTAssertEqual(tryUnwrap(fetched.first).severity0to10, 8)
        XCTAssertEqual(tryUnwrap(storage.fetchSymptomSummary(sessionDate: sessionDate)).symptomCount, 1)

        let cleared = DoseTap.StoredMorningCheckIn(
            id: "morning-symptom-1",
            sessionId: sessionDate,
            timestamp: makeDate("2026-02-24T12:05:00.000Z"),
            sessionDate: sessionDate,
            sleepQuality: 3,
            hasPhysicalSymptoms: false,
            physicalSymptomsJson: nil
        )

        storage.saveMorningCheckIn(cleared, forSession: sessionDate)

        fetched = storage.fetchSymptomEvents(sessionDate: sessionDate)
        XCTAssertTrue(fetched.isEmpty)
        XCTAssertNil(storage.fetchSymptomSummary(sessionDate: sessionDate))
    }

    func test_morningSave_rollsBackSourceRowsWhenDerivedSymptomReplacementFails() throws {
        let sessionDate = "2026-02-26"
        let physicalJson = #"{"painEntries":[{"entry_key":"lower_back|both","area":"lower_back","side":"both","intensity":8,"sensations":["burning"],"pattern":"constant","notes":"Woke with pain."}]}"#
        let checkIn = DoseTap.StoredMorningCheckIn(
            id: "morning-symptom-rollback-1",
            sessionId: sessionDate,
            timestamp: makeDate("2026-02-27T12:00:00.000Z"),
            sessionDate: sessionDate,
            sleepQuality: 3,
            hasPhysicalSymptoms: true,
            physicalSymptomsJson: physicalJson
        )

        execSQL("DROP TABLE symptom_command_log")

        storage.saveMorningCheckIn(checkIn, forSession: sessionDate)

        XCTAssertNil(storage.fetchStoredMorningCheckIn(sessionKey: sessionDate))
        XCTAssertEqual(storage.fetchCheckInSubmissionCount(sessionDate: sessionDate, checkInType: .morning), 0)
    }

    func test_sessionDelete_cascadesSymptomEventsAndLocationDetails() throws {
        let sessionDate = "2026-02-20"
        let event = try makeSymptomEvent(
            id: "symptom-delete-1",
            sessionId: "symptom-session-delete",
            sessionDate: sessionDate,
            noticedAt: "2026-02-21T04:00:00.000Z"
        )

        try storage.recordSymptomEvent(event, idempotencyKey: "night:symptom-delete-1")

        XCTAssertEqual(storage.fetchRowCount(table: "symptom_events", sessionDate: sessionDate), 1)
        XCTAssertEqual(scalarInt("SELECT COUNT(*) FROM symptom_locations WHERE event_id = 'symptom-delete-1'"), 1)
        XCTAssertEqual(scalarInt("SELECT COUNT(*) FROM body_map_points WHERE location_id = 'symptom-delete-1-location'"), 1)
        XCTAssertEqual(scalarInt("SELECT COUNT(*) FROM symptom_command_log WHERE session_date = '\(sessionDate)'"), 1)
        XCTAssertNotNil(storage.fetchSymptomSummary(sessionDate: sessionDate))

        storage.deleteSession(sessionDate: sessionDate, recordCloudKitDeletion: false)

        XCTAssertTrue(storage.fetchSymptomEvents(sessionDate: sessionDate).isEmpty)
        XCTAssertEqual(storage.fetchRowCount(table: "symptom_events", sessionDate: sessionDate), 0)
        XCTAssertEqual(scalarInt("SELECT COUNT(*) FROM symptom_locations WHERE event_id = 'symptom-delete-1'"), 0)
        XCTAssertEqual(scalarInt("SELECT COUNT(*) FROM body_map_points WHERE location_id = 'symptom-delete-1-location'"), 0)
        XCTAssertEqual(scalarInt("SELECT COUNT(*) FROM symptom_command_log WHERE session_date = '\(sessionDate)'"), 0)
        XCTAssertNil(storage.fetchSymptomSummary(sessionDate: sessionDate))
    }

    func test_morningCheckIn_roundTripsTimingContextJson() {
        let sessionDate = "2026-02-16"
        let json = #"{"nightType":"transition_into_work_block","wakeType":"alarm","nextDayDemand":"shift_13h","dose2WakeMethod":"natural","backToSleepDuration":"lt_15m","dose2TakenReason":"forgot_to_tap","dose2ReasonNotes":"Woke up already too groggy.","hasWorkSafetyContext":true,"wakeRequirement":"work","shiftStartAtUTC":"2026-02-17T12:00:00.000Z","shiftEndAtUTC":"2026-02-18T01:00:00.000Z","nextRequiredWakeAtUTC":"2026-02-17T10:15:00.000Z","commuteMinutes":45,"drivingConfidence":2,"daytimeSleepiness":4,"cataplexyBurden":"mild","hasClinicalContext":true,"sleepDisorders":["narcolepsy","obstructive_sleep_apnea"],"pharmacogenomicFastMetabolizer":true,"pharmacogenomicClinicianReviewed":true,"pharmacogenomicNotes":"Reviewed with sleep specialist."}"#

        storage.saveMorningCheckIn(
            StoredMorningCheckIn(
                id: UUID().uuidString,
                sessionId: sessionDate,
                timestamp: makeDate("2026-02-17T11:00:00.000Z"),
                sessionDate: sessionDate,
                sleepQuality: 4,
                timingContextJson: json
            ),
            forSession: sessionDate
        )

        let fetched = tryUnwrap(storage.fetchStoredMorningCheckIn(sessionKey: sessionDate))
        XCTAssertEqual(fetched.timingContextJson, json)
        XCTAssertEqual(fetched.resolvedTimingContext?.dose2TakenReason, "forgot_to_tap")
        XCTAssertEqual(fetched.resolvedTimingContext?.dose2ReasonNotes, "Woke up already too groggy.")
        XCTAssertEqual(fetched.resolvedTimingContext?.wakeRequirement, "work")
        XCTAssertEqual(fetched.resolvedTimingContext?.commuteMinutes, 45)
        XCTAssertEqual(fetched.resolvedTimingContext?.drivingConfidence, 2)
        XCTAssertEqual(fetched.resolvedTimingContext?.daytimeSleepiness, 4)
        XCTAssertEqual(fetched.resolvedTimingContext?.cataplexyBurden, "mild")
        XCTAssertEqual(fetched.resolvedTimingContext?.sleepDisorders, ["narcolepsy", "obstructive_sleep_apnea"])
        XCTAssertEqual(fetched.resolvedTimingContext?.pharmacogenomicFastMetabolizer, true)
        XCTAssertEqual(fetched.resolvedTimingContext?.pharmacogenomicClinicianReviewed, true)
    }

    private func makeSymptomEvent(
        id: String,
        sessionId: String,
        sessionDate: String,
        noticedAt: String,
        severity0to10: Int = 6,
        kind: SymptomKind = .numbness,
        phase: SymptomCheckInPhase = .nightLog,
        source: SymptomEventSource = .nightQuickLog,
        sourceRecordId: String? = nil,
        sourceEntryKey: String? = nil
    ) throws -> StoredSymptomEvent {
        let point = try StoredBodyMapPoint(
            id: "\(id)-point",
            mapId: "hand.left.v1",
            normalizedX: 0.25,
            normalizedY: 0.75,
            zoomLevel: 2.0,
            bodyView: .palm
        )
        let location = StoredSymptomLocation(
            id: "\(id)-location",
            bodySide: .left,
            bodyRegionId: "hand.left.pinky",
            anatomyLayer: .nerveLike,
            precision: .point,
            confidence: .exact,
            points: [point]
        )
        return try StoredSymptomEvent(
            id: id,
            sessionId: sessionId,
            sessionDate: sessionDate,
            phase: phase,
            source: source,
            sourceRecordId: sourceRecordId,
            sourceEntryKey: sourceEntryKey,
            kind: kind,
            noticedAt: makeDate(noticedAt),
            severity0to10: severity0to10,
            sleepDisruption: true,
            stillPresent: true,
            functionalImpact: "hard_to_grip",
            note: "Woke up with left pinky numbness.",
            schemaVersion: 1,
            appVersion: "test",
            createdAt: makeDate(noticedAt),
            locations: [location]
        )
    }

    private func makeDate(_ isoString: String) -> Date {
        guard let date = iso.date(from: isoString) else {
            XCTFail("Invalid ISO date: \(isoString)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private func execSQL(_ sql: String, file: StaticString = #filePath, line: UInt = #line) {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(storage.db, sql, nil, nil, &errorMessage)
        defer {
            if let errorMessage {
                sqlite3_free(errorMessage)
            }
        }
        XCTAssertEqual(result, SQLITE_OK, errorMessage.map { String(cString: $0) } ?? "SQLite error", file: file, line: line)
    }

    private func scalarInt(_ sql: String, file: StaticString = #filePath, line: UInt = #line) -> Int {
        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(storage.db, sql, -1, &stmt, nil)
        XCTAssertEqual(prepareResult, SQLITE_OK, String(cString: sqlite3_errmsg(storage.db)), file: file, line: line)
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            XCTFail("Expected scalar row", file: file, line: line)
            return 0
        }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func tryUnwrap<T>(_ value: T?) -> T {
        guard let value else {
            XCTFail("Expected value to be non-nil")
            fatalError("Unreachable")
        }
        return value
    }
}
