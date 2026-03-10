import XCTest
@testable import DoseCore

final class UnifiedSleepSessionTests: XCTestCase {
    
    private let anchor = Date(timeIntervalSince1970: 1_000_000)
    
    private func makeDoseData(
        dose1: Date? = nil,
        dose2: Date? = nil,
        dose2Skipped: Bool = false,
        snoozeCount: Int = 0,
        sleepEvents: [SleepEventRecord] = []
    ) -> DoseSessionData {
        DoseSessionData(
            dose1Time: dose1 ?? anchor,
            dose2Time: dose2,
            dose2Skipped: dose2Skipped,
            snoozeCount: snoozeCount,
            sleepEvents: sleepEvents
        )
    }
    
    // MARK: - DoseSessionData.intervalMinutes
    
    func test_intervalMinutes_nil_whenNoDose2() {
        let data = makeDoseData()
        XCTAssertNil(data.intervalMinutes)
    }
    
    func test_intervalMinutes_correct_whenDose2Taken() {
        let d1 = anchor
        let d2 = d1.addingTimeInterval(170 * 60)
        let data = makeDoseData(dose1: d1, dose2: d2)
        XCTAssertEqual(data.intervalMinutes, 170)
    }
    
    // MARK: - DoseSessionData.isCompliant
    
    func test_isCompliant_false_whenNoDose2() {
        XCTAssertFalse(makeDoseData().isCompliant)
    }
    
    func test_isCompliant_true_at150minutes() {
        let d2 = anchor.addingTimeInterval(150 * 60)
        XCTAssertTrue(makeDoseData(dose2: d2).isCompliant)
    }
    
    func test_isCompliant_true_at240minutes() {
        let d2 = anchor.addingTimeInterval(240 * 60)
        XCTAssertTrue(makeDoseData(dose2: d2).isCompliant)
    }
    
    func test_isCompliant_false_at149minutes() {
        let d2 = anchor.addingTimeInterval(149 * 60)
        XCTAssertFalse(makeDoseData(dose2: d2).isCompliant)
    }
    
    func test_isCompliant_false_at241minutes() {
        let d2 = anchor.addingTimeInterval(241 * 60)
        XCTAssertFalse(makeDoseData(dose2: d2).isCompliant)
    }
    
    // MARK: - DoseSessionData.estimatedSleepDuration
    
    func test_estimatedSleepDuration_nil_whenNoLightsOutOrWake() {
        XCTAssertNil(makeDoseData().estimatedSleepDuration)
    }
    
    func test_estimatedSleepDuration_calculatedFromEvents() {
        let lightsOut = SleepEventRecord(type: .lightsOut, timestamp: anchor)
        let wakeFinal = SleepEventRecord(type: .wakeFinal, timestamp: anchor.addingTimeInterval(8 * 3600))
        let data = makeDoseData(sleepEvents: [lightsOut, wakeFinal])
        XCTAssertEqual(data.estimatedSleepDuration!, 8 * 3600, accuracy: 1)
    }
    
    // MARK: - DoseSessionData.bathroomCount
    
    func test_bathroomCount_countsOnlyBathroomEvents() {
        let events: [SleepEventRecord] = [
            SleepEventRecord(type: .bathroom, timestamp: anchor),
            SleepEventRecord(type: .lightsOut, timestamp: anchor),
            SleepEventRecord(type: .bathroom, timestamp: anchor.addingTimeInterval(3600)),
        ]
        let data = makeDoseData(sleepEvents: events)
        XCTAssertEqual(data.bathroomCount, 2)
    }
    
    // MARK: - UnifiedSleepSession.sleepQualityScore
    
    func test_sleepQualityScore_nil_whenAllSourcesNil() {
        let session = UnifiedSleepSession(date: anchor, doseData: makeDoseData())
        XCTAssertNil(session.sleepQualityScore, "Score should be nil when no WHOOP, no HRV, no compliance data")
    }
    
    func test_sleepQualityScore_compliantDoseOnly() {
        // Compliant dose contributes 85 * 0.3 weight
        let d2 = anchor.addingTimeInterval(165 * 60)
        let data = makeDoseData(dose2: d2)
        let session = UnifiedSleepSession(date: anchor, doseData: data)
        // score = 85 * 0.3 / 0.3 = 85
        XCTAssertEqual(session.sleepQualityScore, 85)
    }
    
    func test_sleepQualityScore_nonCompliantDose2Taken() {
        // Non-compliant dose2 contributes 60 * 0.3 weight
        let d2 = anchor.addingTimeInterval(250 * 60) // over 240
        let data = makeDoseData(dose2: d2)
        let session = UnifiedSleepSession(date: anchor, doseData: data)
        // score = 60 * 0.3 / 0.3 = 60
        XCTAssertEqual(session.sleepQualityScore, 60)
    }
    
    func test_sleepQualityScore_whoopOnly() {
        let whoop = WhoopSleepData(recoveryScore: 80)
        let session = UnifiedSleepSession(date: anchor, doseData: makeDoseData(), whoopData: whoop)
        // score = 80 * 0.4 / 0.4 = 80
        XCTAssertEqual(session.sleepQualityScore, 80)
    }
    
    func test_sleepQualityScore_hrvOnly() {
        // HRV 60ms → normalized = (60-20)/80*100 = 50
        let health = HealthSleepData(averageHRV: 60.0)
        let session = UnifiedSleepSession(date: anchor, doseData: makeDoseData(), healthData: health)
        // score = 50 * 0.3 / 0.3 = 50
        XCTAssertEqual(session.sleepQualityScore, 50)
    }
    
    func test_sleepQualityScore_allThreeSources() {
        let d2 = anchor.addingTimeInterval(165 * 60)
        let data = makeDoseData(dose2: d2) // compliant → 85
        let whoop = WhoopSleepData(recoveryScore: 90)
        let health = HealthSleepData(averageHRV: 60.0) // normalized to 50
        let session = UnifiedSleepSession(date: anchor, doseData: data, healthData: health, whoopData: whoop)
        // score = (90*0.4 + 85*0.3 + 50*0.3) / (0.4+0.3+0.3) = (36+25.5+15)/1.0 = 76.5 → 76
        XCTAssertEqual(session.sleepQualityScore, 76)
    }
    
    func test_sleepQualityScore_hrvClampedAtLowEnd() {
        // HRV below 20ms → normalized to 0
        let health = HealthSleepData(averageHRV: 10.0)
        let session = UnifiedSleepSession(date: anchor, doseData: makeDoseData(), healthData: health)
        XCTAssertEqual(session.sleepQualityScore, 0)
    }
    
    func test_sleepQualityScore_hrvClampedAtHighEnd() {
        // HRV above 100ms → normalized to 100
        let health = HealthSleepData(averageHRV: 120.0)
        let session = UnifiedSleepSession(date: anchor, doseData: makeDoseData(), healthData: health)
        XCTAssertEqual(session.sleepQualityScore, 100)
    }
    
    // MARK: - UnifiedSleepSession.totalSleepDuration
    
    func test_totalSleepDuration_prefersWhoop() {
        let whoop = WhoopSleepData(totalSleepSeconds: 28800) // 8h
        let health = HealthSleepData(totalSleepDuration: 25200) // 7h
        let session = UnifiedSleepSession(date: anchor, doseData: makeDoseData(), healthData: health, whoopData: whoop)
        XCTAssertEqual(session.totalSleepDuration, 28800)
    }
    
    func test_totalSleepDuration_fallsBackToHealth() {
        let health = HealthSleepData(totalSleepDuration: 25200)
        let session = UnifiedSleepSession(date: anchor, doseData: makeDoseData(), healthData: health)
        XCTAssertEqual(session.totalSleepDuration, 25200)
    }
    
    func test_totalSleepDuration_fallsBackToEvents() {
        let lightsOut = SleepEventRecord(type: .lightsOut, timestamp: anchor)
        let wakeFinal = SleepEventRecord(type: .wakeFinal, timestamp: anchor.addingTimeInterval(7 * 3600))
        let data = makeDoseData(sleepEvents: [lightsOut, wakeFinal])
        let session = UnifiedSleepSession(date: anchor, doseData: data)
        XCTAssertEqual(session.totalSleepDuration!, 7 * 3600, accuracy: 1)
    }
    
    // MARK: - UnifiedSleepSession.awakenings
    
    func test_awakenings_usesMaxOfEventsAndHealth() {
        let wakes = [
            SleepEventRecord(type: .wakeTemp, timestamp: anchor),
            SleepEventRecord(type: .wakeTemp, timestamp: anchor.addingTimeInterval(3600)),
        ]
        let health = HealthSleepData(awakenings: 5)
        let session = UnifiedSleepSession(
            date: anchor,
            doseData: makeDoseData(sleepEvents: wakes),
            healthData: health
        )
        XCTAssertEqual(session.awakenings, 5, "Should use max(eventWakes=2, healthWakes=5)")
    }
    
    // MARK: - UnifiedSessionBuilder
    
    func test_builder_returnsNil_withoutDoseData() {
        let builder = UnifiedSessionBuilder(date: anchor)
        XCTAssertNil(builder.build())
    }
    
    func test_builder_succeeds_withDoseData() {
        var builder = UnifiedSessionBuilder(date: anchor)
        builder.setDoseData(makeDoseData())
        XCTAssertNotNil(builder.build())
    }
    
    // MARK: - SessionAggregator
    
    func test_aggregator_complianceRate_100_whenAllCompliant() {
        let d2 = anchor.addingTimeInterval(165 * 60)
        let sessions = (0..<3).map { i in
            UnifiedSleepSession(
                date: anchor.addingTimeInterval(Double(i) * 86400),
                doseData: makeDoseData(dose2: d2)
            )
        }
        let agg = SessionAggregator(sessions: sessions)
        XCTAssertEqual(agg.complianceRate, 100.0)
    }
    
    func test_aggregator_complianceRate_0_whenNoDose2() {
        let sessions = [UnifiedSleepSession(date: anchor, doseData: makeDoseData())]
        let agg = SessionAggregator(sessions: sessions)
        XCTAssertEqual(agg.complianceRate, 0.0)
    }
    
    func test_aggregator_averageInterval() {
        let s1 = UnifiedSleepSession(date: anchor, doseData: makeDoseData(dose2: anchor.addingTimeInterval(160 * 60)))
        let s2 = UnifiedSleepSession(date: anchor, doseData: makeDoseData(dose2: anchor.addingTimeInterval(180 * 60)))
        let agg = SessionAggregator(sessions: [s1, s2])
        XCTAssertEqual(agg.averageInterval!, 170.0, accuracy: 0.1)
    }
    
    func test_aggregator_averageBathroomTrips() {
        let events1 = [SleepEventRecord(type: .bathroom, timestamp: anchor)]
        let events2 = [
            SleepEventRecord(type: .bathroom, timestamp: anchor),
            SleepEventRecord(type: .bathroom, timestamp: anchor.addingTimeInterval(3600)),
            SleepEventRecord(type: .bathroom, timestamp: anchor.addingTimeInterval(7200)),
        ]
        let s1 = UnifiedSleepSession(date: anchor, doseData: makeDoseData(sleepEvents: events1))
        let s2 = UnifiedSleepSession(date: anchor, doseData: makeDoseData(sleepEvents: events2))
        let agg = SessionAggregator(sessions: [s1, s2])
        XCTAssertEqual(agg.averageBathroomTrips, 2.0, accuracy: 0.01)
    }
    
    // MARK: - SleepStages
    
    func test_sleepStages_percentages() {
        let stages = SleepStages(awake: 100, rem: 200, core: 300, deep: 400)
        XCTAssertEqual(stages.total, 1000)
        XCTAssertEqual(stages.remPercentage, 20.0, accuracy: 0.01)
        XCTAssertEqual(stages.deepPercentage, 40.0, accuracy: 0.01)
        XCTAssertEqual(stages.corePercentage, 30.0, accuracy: 0.01)
    }
    
    func test_sleepStages_zeroTotal_percentagesAreZero() {
        let stages = SleepStages()
        XCTAssertEqual(stages.remPercentage, 0)
        XCTAssertEqual(stages.deepPercentage, 0)
        XCTAssertEqual(stages.corePercentage, 0)
    }
}
