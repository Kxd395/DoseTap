import XCTest
@testable import DoseTapStudio

/// Test suite for data import functionality
final class ImporterTests: XCTestCase {
    
    func testParseEventsCSV() throws {
        let csvContent = """
        event_type,occurred_at_utc,details,device_time
        dose1_taken,2024-09-07T20:00:00.000Z,Manual entry,2024-09-07T16:00:00-04:00
        dose2_taken,2024-09-07T22:45:00.000Z,,2024-09-07T18:45:00-04:00
        bathroom,2024-09-07T21:30:00.000Z,Quick break,2024-09-07T17:30:00-04:00
        """
        
        let importer = Importer()
        let events = try importer.parseEventsCSV(csvContent)
        
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].eventType, .dose1_taken)
        XCTAssertEqual(events[1].eventType, .dose2_taken)
        XCTAssertEqual(events[2].eventType, .bathroom)
        XCTAssertEqual(events[0].details, "Manual entry")
        XCTAssertNil(events[1].details)
    }

    func testParseEventsCSVNormalizesLegacyAliases() throws {
        let csvContent = """
        event_type,occurred_at_utc,details,device_time
        dose1,2024-09-07T20:00:00.000Z,,2024-09-07
        dose2,2024-09-07T22:45:00.000Z,,2024-09-07
        lightsout,2024-09-07T19:55:00.000Z,ready,2024-09-07
        """

        let importer = Importer()
        let events = try importer.parseEventsCSV(csvContent)

        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].eventType, .dose1_taken)
        XCTAssertEqual(events[1].eventType, .dose2_taken)
        XCTAssertEqual(events[2].eventType, .lights_out)
    }
    
    func testParseSessionsCSV() throws {
        let csvContent = """
        started_utc,ended_utc,window_target_min,window_actual_min,adherence_flag,whoop_recovery,avg_hr,sleep_efficiency,notes
        2024-09-07T20:00:00.000Z,2024-09-07T22:45:00.000Z,165,165,ok,75,65,85.5,Good session
        2024-09-06T20:00:00.000Z,2024-09-06T23:00:00.000Z,165,180,late,80,70,90.2,
        """
        
        let importer = Importer()
        let sessions = try importer.parseSessionsCSV(csvContent)
        
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].windowTargetMin, 165)
        XCTAssertEqual(sessions[0].windowActualMin, 165)
        XCTAssertEqual(sessions[0].adherenceFlag, "ok")
        XCTAssertEqual(sessions[0].whoopRecovery, 75)
        XCTAssertEqual(sessions[1].windowActualMin, 180)
        XCTAssertEqual(sessions[1].adherenceFlag, "late")
    }
    
    func testParseInventoryCSV() throws {
        let csvContent = """
        as_of_utc,bottles_remaining,doses_remaining,estimated_days_left,next_refill_date,notes
        2024-09-07T08:00:00.000Z,2,28,14,2024-09-21T08:00:00.000Z,Good supply
        2024-09-01T08:00:00.000Z,3,42,21,,
        """
        
        let importer = Importer()
        let inventory = try importer.parseInventoryCSV(csvContent)
        
        XCTAssertEqual(inventory.count, 2)
        XCTAssertEqual(inventory[0].bottlesRemaining, 2)
        XCTAssertEqual(inventory[0].dosesRemaining, 28)
        XCTAssertEqual(inventory[0].estimatedDaysLeft, 14)
        XCTAssertEqual(inventory[0].notes, "Good supply")
        XCTAssertEqual(inventory[1].bottlesRemaining, 3)
        XCTAssertNil(inventory[1].notes)
    }
    
    func testCSVLineParsingWithQuotes() {
        let importer = Importer()
        
        // Test quoted field with comma
        let line1 = #"dose1_taken,2024-09-07T20:00:00.000Z,"Manual entry, user initiated",2024-09-07T16:00:00-04:00"#
        let columns1 = importer.parseCSVLine(line1)
        XCTAssertEqual(columns1.count, 4)
        XCTAssertEqual(columns1[2], "Manual entry, user initiated")
        
        // Test escaped quotes
        let line2 = #"bathroom,2024-09-07T21:30:00.000Z,"Said ""quick break""",2024-09-07T17:30:00-04:00"#
        let columns2 = importer.parseCSVLine(line2)
        XCTAssertEqual(columns2[2], #"Said "quick break""#)
    }

    func testParseInsightsBundleV2WithHealthKitAndWHOOP() throws {
        let json = """
        {
          "schemaVersion" : 2,
          "exportVersion" : "2.2",
          "appVersion" : "1.4.0 (207)",
          "exportedAtUTC" : "2026-03-21T10:00:00Z",
          "timeZoneIdentifier" : "America/New_York",
          "localOffsetMinutes" : -240,
          "consent" : {
            "appleHealthEnabled" : true,
            "appleHealthAvailable" : true,
            "appleHealthAuthorized" : true,
            "whoopEnabled" : true,
            "whoopConnected" : true
          },
          "exportWarnings" : [
            "1 night(s) include session-level data-quality flags."
          ],
          "sessions" : [
            {
              "sessionDate" : "2026-03-20",
              "dose1TimeUTC" : "2026-03-21T03:00:00Z",
              "dose2TimeUTC" : "2026-03-21T05:45:00Z",
              "rawEvents" : [
                {
                  "kind" : "dose",
                  "eventType" : "dose2",
                  "occurredAtUTC" : "2026-03-21T05:45:00Z",
                  "details" : "{\\"source\\":\\"manual\\"}",
                  "source" : "manual",
                  "deviceTime" : "2026-03-20"
                }
              ],
              "normalizedEvents" : [
                {
                  "kind" : "dose",
                  "eventType" : "dose2_taken",
                  "occurredAtUTC" : "2026-03-21T05:45:00Z",
                  "details" : "{\\"source\\":\\"manual\\"}",
                  "source" : "manual",
                  "deviceTime" : "2026-03-20"
                }
              ],
              "sourceAvailability" : {
                "doseEvents" : true,
                "sleepEvents" : false,
                "preSleep" : true,
                "morningCheckIn" : false,
                "medications" : false,
                "healthKit" : true,
                "whoop" : true,
                "alarmDiagnostics" : true
              },
              "metricProvenance" : {
                "dose2_time" : "manual",
                "total_sleep_minutes" : "whoop"
              },
              "dataQualityFlags" : [
                "Dose 2 reason mismatch between live and morning logs"
              ],
              "exportExclusionReasons" : [
                "Dose 2 reason mismatch between live and morning logs"
              ],
              "preSleep" : {
                "sessionId" : "night-1",
                "completionState" : "complete",
                "loggedAtUTC" : "2026-03-21T02:40:00Z",
                "stressLevel" : 3,
                "stressDrivers" : ["schedule"],
                "laterReason" : "late_meal",
                "bodyPain" : "mild",
                "caffeineSources" : ["coffee"],
                "caffeineLastIntakeAtUTC" : "2026-03-21T00:15:00Z",
                "caffeineLastAmountMg" : 120,
                "caffeineDailyTotalMg" : 220,
                "alcohol" : "none",
                "alcoholLastDrinkAtUTC" : null,
                "alcoholLastAmountDrinks" : null,
                "alcoholDailyTotalDrinks" : null,
                "exercise" : "light",
                "exerciseLastAtUTC" : "2026-03-20T23:30:00Z",
                "exerciseDurationMinutes" : 35,
                "napToday" : "yes",
                "napCount" : 1,
                "napTotalMinutes" : 20,
                "napLastEndAtUTC" : "2026-03-20T20:10:00Z",
                "lateMeal" : "yes",
                "lateMealEndedAtUTC" : "2026-03-21T01:30:00Z",
                "screensInBed" : "yes",
                "screensLastUsedAtUTC" : "2026-03-21T02:20:00Z",
                "roomTemp" : "cool",
                "noiseLevel" : "quiet",
                "sleepAids" : ["magnesium"],
                "notes" : "Ran late after work."
              },
              "morning" : null,
              "medications" : [],
              "context" : {
                "nextMorningWeekdayIndex" : 7,
                "nextMorningIsWeekend" : true,
                "scheduledWakeByUTC" : "2026-03-21T10:00:00Z",
                "scheduledWakeMinutesAfterMidnight" : 360,
                "scheduleDayType" : "worklike",
                "previousScheduleDayType" : "offlike",
                "nextScheduleDayType" : "offlike",
                "explicitNightType" : "work_night",
                "explicitWakeType" : "alarm_then_snooze",
                "explicitNextDayDemand" : "shift_13h",
                "explicitDose2WakeMethod" : "alarm",
                "explicitBackToSleepDuration" : "15_30m",
                "alarm" : {
                  "scheduledForUTC" : "2026-03-21T05:45:00Z",
                  "firstFireAtUTC" : "2026-03-21T05:45:02Z",
                  "acknowledgedAtUTC" : "2026-03-21T05:46:10Z",
                  "acknowledgementAction" : "snooze",
                  "followUpDeliveredCount" : 1
                },
                "dose2Outcome" : {
                  "takenSource" : "manual",
                  "takenAmountMg" : 4500,
                  "takenEarly" : false,
                  "takenLate" : false,
                  "liveTakenReason" : "ate_too_late",
                  "morningTakenReason" : "pain_disruption",
                  "takenReason" : "pain_disruption",
                  "hasExtraDose" : false,
                  "skipReason" : null,
                  "skipSource" : null,
                  "reasonMismatch" : true
                },
                "wakeSignal" : "alarm_assisted",
                "wakeFinalLoggedAtUTC" : "2026-03-21T10:35:00Z",
                "snoozeCount" : 2,
                "scheduleMarkers" : ["schedule"],
                "wakeRequirement" : "work",
                "shiftStartAtUTC" : "2026-03-21T12:00:00Z",
                "shiftEndAtUTC" : "2026-03-22T01:00:00Z",
                "nextRequiredWakeAtUTC" : "2026-03-21T10:15:00Z",
                "commuteMinutes" : 45,
                "lateMealType" : "heavy",
                "lateMealEndedAtUTC" : "2026-03-21T01:30:00Z",
                "lateMealMinutesBeforeDose1" : 75,
                "lateMealMinutesBeforeDose2" : 250,
                "caffeineLastIntakeAtUTC" : "2026-03-21T00:15:00Z",
                "caffeineMinutesBeforeDose1" : 150,
                "alcoholLastDrinkAtUTC" : null,
                "alcoholMinutesBeforeDose1" : null,
                "exerciseLastAtUTC" : "2026-03-20T23:30:00Z",
                "exerciseMinutesBeforeDose1" : 195,
                "napLastEndAtUTC" : "2026-03-20T20:10:00Z",
                "napMinutesBeforeDose1" : 395,
                "screensLastUsedAtUTC" : "2026-03-21T02:20:00Z",
                "screenMinutesBeforeDose1" : 25
              },
              "healthKit" : {
                "totalSleepMinutes" : 412.5,
                "ttfwMinutes" : 182,
                "wakeCount" : 3,
                "awakeMinutes" : 32,
                "wakeAfterSleepOnsetMinutes" : 21,
                "inBedMinutes" : 452,
                "coreSleepMinutes" : 245,
                "deepSleepMinutes" : 74,
                "remSleepMinutes" : 93.5,
                "bedTimeUTC" : "2026-03-21T03:10:00Z",
                "sleepOnsetUTC" : "2026-03-21T03:25:00Z",
                "finalWakeUTC" : "2026-03-21T10:30:00Z",
                "averageHeartRate" : 61.2,
                "respiratoryRate" : 14.8,
                "hrvMs" : 48.4,
                "restingHeartRate" : 57.0,
                "sources" : ["Apple Watch", "AutoSleep"]
              },
              "whoop" : {
                "sleepId" : "sleep-1",
                "totalSleepMinutes" : 405,
                "remMinutes" : 92,
                "deepMinutes" : 71,
                "lightMinutes" : 242,
                "awakeMinutes" : 28,
                "inBedMinutes" : 433,
                "disturbanceCount" : 5,
                "sleepEfficiency" : 90.5,
                "sleepPerformance" : 92,
                "sleepConsistency" : 84,
                "respiratoryRate" : 14.4,
                "recoveryScore" : 76,
                "hrvMs" : 52.1,
                "restingHeartRate" : 56,
                "sleepNeedBaselineMinutes" : 430,
                "sleepNeedDebtMinutes" : 20,
                "sleepNeedStrainMinutes" : 14,
                "sleepNeedNapMinutes" : 0,
                "spo2Percentage" : 97,
                "skinTempCelsius" : 0.2
              }
            }
          ]
        }
        """

        let importer = Importer()
        let bundle = try importer.parseInsightsBundle(Data(json.utf8))

        XCTAssertEqual(bundle.schemaVersion, 2)
        XCTAssertEqual(bundle.exportVersion, "2.2")
        XCTAssertEqual(bundle.exportWarnings?.count, 1)
        XCTAssertEqual(bundle.appVersion, "1.4.0 (207)")
        XCTAssertEqual(bundle.timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(bundle.localOffsetMinutes, -240)
        XCTAssertEqual(bundle.consent?.appleHealthAuthorized, true)
        XCTAssertEqual(bundle.consent?.whoopConnected, true)
        XCTAssertEqual(bundle.sessions.count, 1)
        XCTAssertNotNil(bundle.sessions[0].dose1TimeUTC)
        XCTAssertEqual(bundle.sessions[0].rawEvents.count, 1)
        XCTAssertEqual(bundle.sessions[0].normalizedEvents.first?.eventType, "dose2_taken")
        XCTAssertEqual(bundle.sessions[0].sourceAvailability?.alarmDiagnostics, true)
        XCTAssertEqual(bundle.sessions[0].metricProvenance?["total_sleep_minutes"], "whoop")
        XCTAssertEqual(bundle.sessions[0].dataQualityFlags, ["Dose 2 reason mismatch between live and morning logs"])
        XCTAssertEqual(bundle.sessions[0].preSleep?.caffeineLastAmountMg, 120)
        XCTAssertEqual(bundle.sessions[0].context?.wakeSignal, "alarm_assisted")
        XCTAssertEqual(bundle.sessions[0].context?.scheduleDayType, "worklike")
        XCTAssertEqual(bundle.sessions[0].context?.explicitNightType, "work_night")
        XCTAssertEqual(bundle.sessions[0].context?.explicitNextDayDemand, "shift_13h")
        XCTAssertEqual(bundle.sessions[0].context?.alarm?.acknowledgementAction, "snooze")
        XCTAssertEqual(bundle.sessions[0].context?.dose2Outcome?.takenAmountMg, 4500)
        XCTAssertEqual(bundle.sessions[0].context?.dose2Outcome?.liveTakenReason, "ate_too_late")
        XCTAssertEqual(bundle.sessions[0].context?.dose2Outcome?.morningTakenReason, "pain_disruption")
        XCTAssertEqual(bundle.sessions[0].context?.dose2Outcome?.takenReason, "pain_disruption")
        XCTAssertEqual(bundle.sessions[0].context?.dose2Outcome?.reasonMismatch, true)
        XCTAssertEqual(bundle.sessions[0].context?.wakeRequirement, "work")
        XCTAssertEqual(bundle.sessions[0].context?.commuteMinutes, 45)
        XCTAssertEqual(bundle.sessions[0].context?.lateMealType, "heavy")
        XCTAssertEqual(bundle.sessions[0].context?.lateMealMinutesBeforeDose1, 75)
        XCTAssertEqual(bundle.sessions[0].healthKit?.wakeCount, 3)
        XCTAssertEqual(bundle.sessions[0].healthKit?.deepSleepMinutes, 74)
        XCTAssertEqual(bundle.sessions[0].healthKit?.sources, ["Apple Watch", "AutoSleep"])
        XCTAssertEqual(bundle.sessions[0].whoop?.sleepId, "sleep-1")
        XCTAssertEqual(bundle.sessions[0].whoop?.recoveryScore, 76)
        XCTAssertEqual(bundle.sessions[0].whoop?.sleepPerformance, 92)
        XCTAssertEqual(bundle.sessions[0].whoop?.spo2Percentage, 97)
    }

    func testParseInsightsBundlePreservesRawCheckInPayloadsAndFractionalSleepQuality() throws {
        let json = """
        {
          "schemaVersion" : 2,
          "exportVersion" : "2.2",
          "exportedAtUTC" : "2026-06-17T10:00:00Z",
          "sessions" : [
            {
              "sessionDate" : "2026-06-16",
              "dose1TimeUTC" : "2026-06-17T01:15:00Z",
              "dose2TimeUTC" : "2026-06-17T04:45:00Z",
              "rawEvents" : [],
              "normalizedEvents" : [],
              "dataQualityFlags" : [],
              "preSleep" : {
                "sessionId" : "night-raw",
                "completionState" : "complete",
                "loggedAtUTC" : "2026-06-17T00:40:00Z",
                "rawAnswersJson" : "{\\"plannedTotalNightlyMg\\":9000,\\"stressProgression\\":\\"worse\\",\\"painEntries\\":[{\\"area\\":\\"neck\\",\\"severity\\":6}]}",
                "stressLevel" : 3,
                "stressDrivers" : ["work"],
                "laterReason" : "work",
                "bodyPain" : "moderate",
                "caffeineSources" : ["coffee"],
                "caffeineLastIntakeAtUTC" : null,
                "caffeineLastAmountMg" : null,
                "caffeineDailyTotalMg" : null,
                "alcohol" : "none",
                "alcoholLastDrinkAtUTC" : null,
                "alcoholLastAmountDrinks" : null,
                "alcoholDailyTotalDrinks" : null,
                "exercise" : "none",
                "exerciseLastAtUTC" : null,
                "exerciseDurationMinutes" : null,
                "napToday" : "no",
                "napCount" : null,
                "napTotalMinutes" : null,
                "napLastEndAtUTC" : null,
                "lateMeal" : "no",
                "lateMealEndedAtUTC" : null,
                "screensInBed" : "yes",
                "screensLastUsedAtUTC" : null,
                "roomTemp" : "cool",
                "noiseLevel" : "quiet",
                "sleepAids" : [],
                "notes" : null
              },
              "morning" : {
                "submittedAtUTC" : "2026-06-17T11:00:00Z",
                "sleepQuality" : 4.25,
                "rawPhysicalSymptomsJson" : "{\\"painEntries\\":[{\\"area\\":\\"neck\\",\\"severity\\":5}],\\"headacheIntensity\\":2}",
                "rawRespiratorySymptomsJson" : "{\\"congestionBurden\\":\\"mild\\",\\"coughBurden\\":\\"none\\"}",
                "rawSleepTherapyJson" : "{\\"device\\":\\"cpap\\",\\"compliance\\":4}",
                "rawSleepEnvironmentJson" : "{\\"roomTemp\\":\\"cool\\",\\"noiseLevel\\":\\"quiet\\"}",
                "rawStressContextJson" : "{\\"stressProgression\\":\\"better\\",\\"stressNotes\\":\\"less pressure\\"}",
                "rawTimingContextJson" : "{\\"nightType\\":\\"work_night\\",\\"wakeType\\":\\"natural\\",\\"nextDayDemand\\":\\"shift_13h\\"}",
                "feelRested" : "mostly",
                "grogginess" : "mild",
                "sleepInertiaDuration" : "fiveToFifteen",
                "dreamRecall" : "some",
                "mentalClarity" : 4,
                "mood" : "steady",
                "anxietyLevel" : "low",
                "stressLevel" : 2,
                "stressDrivers" : ["work"],
                "readinessForDay" : 4,
                "hadSleepParalysis" : false,
                "hadHallucinations" : false,
                "hadAutomaticBehavior" : false,
                "fellOutOfBed" : false,
                "hadConfusionOnWaking" : false,
                "sleepTherapyDevice" : "cpap",
                "sleepTherapyCompliance" : 4,
                "drivingConfidence" : 4,
                "daytimeSleepiness" : 2,
                "cataplexyBurden" : "none",
                "painBurden" : "mild",
                "anxietyBurden" : "low",
                "congestionBurden" : "mild",
                "refluxBurden" : "none",
                "restlessLegsBurden" : "none",
                "bathroomUrgencyBurden" : "none",
                "sleepDisorders" : ["sleep_apnea"],
                "sleepDisorderNotes" : null,
                "coMedicationNotes" : null,
                "pharmacogenomicFastMetabolizer" : false,
                "pharmacogenomicClinicianReviewed" : false,
                "pharmacogenomicNotes" : null,
                "firstNightOffAfterWorkBlock" : false,
                "notes" : null
              },
              "medications" : [],
              "checkInSubmissions" : [
                {
                  "id" : "morning:morning-raw",
                  "sourceRecordId" : "morning-raw",
                  "sessionId" : "night-raw",
                  "sessionDate" : "2026-06-16",
                  "checkInType" : "morning",
                  "questionnaireVersion" : "morning-v2",
                  "submittedAtUTC" : "2026-06-17T11:00:00Z",
                  "localOffsetMinutes" : -240,
                  "responsesJson" : "{\\"sleep.quality\\":4.25,\\"timing.nightType\\":\\"work_night\\"}"
                }
              ]
            }
          ]
        }
        """

        let importer = Importer()
        let bundle = try importer.parseInsightsBundle(Data(json.utf8))
        let session = try XCTUnwrap(bundle.sessions.first)
        let preSleep = try XCTUnwrap(session.preSleep)
        let morning = try XCTUnwrap(session.morning)
        let submission = try XCTUnwrap(session.checkInSubmissions?.first)

        XCTAssertTrue(preSleep.rawAnswersJson?.contains("plannedTotalNightlyMg") == true)
        XCTAssertEqual(morning.sleepQuality, 4.25, accuracy: 0.001)
        XCTAssertTrue(morning.rawPhysicalSymptomsJson?.contains("painEntries") == true)
        XCTAssertTrue(morning.rawTimingContextJson?.contains("work_night") == true)
        XCTAssertEqual(submission.checkInType, "morning")
        XCTAssertTrue(submission.responsesJson.contains("sleep.quality"))
    }

    func testLoadCleanNightFixtureBundleFromDisk() async throws {
        let importer = Importer()
        let folder = try FixtureLoader.folder(named: "clean-nights")

        let events = try await importer.loadEvents(from: folder)
        let sessions = try await importer.loadSessions(from: folder)
        let inventory = try await importer.loadInventory(from: folder)
        let loadedBundle = try await importer.loadInsightsBundle(from: folder)
        let bundle = try XCTUnwrap(loadedBundle)

        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.map(\.eventType), [.dose1_taken, .lights_out, .dose2_taken, .wake_final])
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].windowActualMin, 170)
        XCTAssertEqual(inventory.count, 1)
        XCTAssertEqual(bundle.schemaVersion, 2)
        XCTAssertEqual(bundle.sessions.count, 1)
        XCTAssertEqual(bundle.sessions[0].normalizedEvents.last?.eventType, "wake_final")
        XCTAssertEqual(bundle.sessions[0].context?.explicitWakeType, "natural")
        XCTAssertNotNil(bundle.importMetadata)
    }

    func testLoadShiftWorkFixturePreservesContext() async throws {
        let importer = Importer()
        let folder = try FixtureLoader.folder(named: "shift-work-nights")
        let loadedBundle = try await importer.loadInsightsBundle(from: folder)
        let bundle = try XCTUnwrap(loadedBundle)

        XCTAssertEqual(bundle.sessions.count, 2)
        XCTAssertEqual(bundle.sessions[0].context?.explicitNightType, "work_night")
        XCTAssertEqual(bundle.sessions[0].context?.explicitNextDayDemand, "shift_13h")
        XCTAssertEqual(bundle.sessions[0].context?.wakeRequirement, "work")
        XCTAssertEqual(bundle.sessions[1].context?.explicitNightType, "transition_out_of_work_block")
    }
}
