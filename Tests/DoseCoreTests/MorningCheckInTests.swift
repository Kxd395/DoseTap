import XCTest
@testable import DoseCore

@available(iOS 15.0, watchOS 8.0, macOS 12.0, *)
final class MorningCheckInTests: XCTestCase {
    
    // MARK: - Default Initialization
    
    func test_defaultInit_hasExpectedDefaults() {
        let sessionId = UUID()
        let checkIn = MorningCheckIn(sessionId: sessionId)
        
        XCTAssertEqual(checkIn.sessionId, sessionId)
        XCTAssertEqual(checkIn.sleepQuality, 3)
        XCTAssertEqual(checkIn.feelRested, .moderate)
        XCTAssertEqual(checkIn.grogginess, .mild)
        XCTAssertEqual(checkIn.sleepInertiaDuration, .fiveToFifteen)
        XCTAssertEqual(checkIn.dreamRecall, .none)
        XCTAssertFalse(checkIn.hasPhysicalSymptoms)
        XCTAssertNil(checkIn.physicalSymptoms)
        XCTAssertFalse(checkIn.hasRespiratorySymptoms)
        XCTAssertNil(checkIn.respiratorySymptoms)
        XCTAssertEqual(checkIn.mentalClarity, 5)
        XCTAssertEqual(checkIn.mood, .neutral)
        XCTAssertEqual(checkIn.anxietyLevel, .none)
        XCTAssertEqual(checkIn.readinessForDay, 3)
        XCTAssertFalse(checkIn.hadSleepParalysis)
        XCTAssertFalse(checkIn.hadHallucinations)
        XCTAssertFalse(checkIn.hadAutomaticBehavior)
        XCTAssertFalse(checkIn.fellOutOfBed)
        XCTAssertFalse(checkIn.hadConfusionOnWaking)
        XCTAssertFalse(checkIn.hasSleepEnvironmentData)
        XCTAssertNil(checkIn.sleepEnvironment)
        XCTAssertNil(checkIn.notes)
    }
    
    // MARK: - Codable Round-Trip
    
    func test_morningCheckIn_codableRoundTrip_defaults() throws {
        let original = MorningCheckIn(sessionId: UUID())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MorningCheckIn.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.sessionId, original.sessionId)
        XCTAssertEqual(decoded.sleepQuality, original.sleepQuality)
        XCTAssertEqual(decoded.feelRested, original.feelRested)
        XCTAssertEqual(decoded.grogginess, original.grogginess)
        XCTAssertEqual(decoded.mood, original.mood)
        XCTAssertEqual(decoded.anxietyLevel, original.anxietyLevel)
    }
    
    func test_morningCheckIn_codableRoundTrip_withNarcolepsySymptoms() throws {
        var checkIn = MorningCheckIn(sessionId: UUID())
        checkIn.hadSleepParalysis = true
        checkIn.hadHallucinations = true
        checkIn.hadConfusionOnWaking = true
        checkIn.notes = "Vivid hypnagogic hallucinations"
        
        let data = try JSONEncoder().encode(checkIn)
        let decoded = try JSONDecoder().decode(MorningCheckIn.self, from: data)
        
        XCTAssertTrue(decoded.hadSleepParalysis)
        XCTAssertTrue(decoded.hadHallucinations)
        XCTAssertTrue(decoded.hadConfusionOnWaking)
        XCTAssertEqual(decoded.notes, "Vivid hypnagogic hallucinations")
    }
    
    // MARK: - RestedLevel
    
    func test_restedLevel_allCases_count() {
        XCTAssertEqual(RestedLevel.allCases.count, 5)
    }
    
    func test_restedLevel_numericValues_ascending() {
        let values = RestedLevel.allCases.map { $0.numericValue }
        XCTAssertEqual(values, [1, 2, 3, 4, 5], "Numeric values should ascend from notAtAll(1) to veryWell(5)")
    }
    
    func test_restedLevel_codableRoundTrip() throws {
        for level in RestedLevel.allCases {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(RestedLevel.self, from: data)
            XCTAssertEqual(decoded, level)
        }
    }
    
    // MARK: - GrogginessLevel
    
    func test_grogginessLevel_allCases_count() {
        XCTAssertEqual(GrogginessLevel.allCases.count, 5)
    }
    
    func test_grogginessLevel_iconsNotEmpty() {
        for level in GrogginessLevel.allCases {
            XCTAssertFalse(level.icon.isEmpty, "\(level.rawValue) should have an icon")
        }
    }
    
    // MARK: - SleepInertiaDuration
    
    func test_sleepInertiaDuration_midpointMinutes_increase() {
        let midpoints = SleepInertiaDuration.allCases.map { $0.midpointMinutes }
        // Each midpoint should be strictly greater than the previous
        for i in 1..<midpoints.count {
            XCTAssertGreaterThan(midpoints[i], midpoints[i - 1],
                "Midpoint for \(SleepInertiaDuration.allCases[i]) should exceed \(SleepInertiaDuration.allCases[i - 1])")
        }
    }
    
    func test_sleepInertiaDuration_specificValues() {
        XCTAssertEqual(SleepInertiaDuration.lessThanFive.midpointMinutes, 3)
        XCTAssertEqual(SleepInertiaDuration.fiveToFifteen.midpointMinutes, 10)
        XCTAssertEqual(SleepInertiaDuration.fifteenToThirty.midpointMinutes, 22)
        XCTAssertEqual(SleepInertiaDuration.thirtyToSixty.midpointMinutes, 45)
        XCTAssertEqual(SleepInertiaDuration.moreThanHour.midpointMinutes, 90)
    }
    
    // MARK: - MoodLevel
    
    func test_moodLevel_allCases_count() {
        XCTAssertEqual(MoodLevel.allCases.count, 5)
    }
    
    func test_moodLevel_emojisNotEmpty() {
        for mood in MoodLevel.allCases {
            XCTAssertFalse(mood.emoji.isEmpty, "\(mood.rawValue) should have an emoji")
        }
    }
    
    // MARK: - AnxietyLevel
    
    func test_anxietyLevel_allCases_count() {
        XCTAssertEqual(AnxietyLevel.allCases.count, 5)
    }
    
    // MARK: - DreamRecallType
    
    func test_dreamRecallType_allCases_count() {
        XCTAssertEqual(DreamRecallType.allCases.count, 6)
    }
    
    func test_dreamRecallType_codableRoundTrip() throws {
        for dream in DreamRecallType.allCases {
            let data = try JSONEncoder().encode(dream)
            let decoded = try JSONDecoder().decode(DreamRecallType.self, from: data)
            XCTAssertEqual(decoded, dream)
        }
    }
    
    // MARK: - BodyPart
    
    func test_bodyPart_iconsNotEmpty() {
        for part in BodyPart.allCases {
            XCTAssertFalse(part.icon.isEmpty, "\(part.rawValue) should have an icon")
        }
    }
    
    // MARK: - PhysicalSymptoms
    
    func test_physicalSymptoms_defaultInit() {
        let symptoms = PhysicalSymptoms()
        XCTAssertTrue(symptoms.painLocations.isEmpty)
        XCTAssertEqual(symptoms.painSeverity, 0)
        XCTAssertEqual(symptoms.muscleStiffness, .none)
        XCTAssertEqual(symptoms.muscleSoreness, .none)
    }
    
    func test_physicalSymptoms_codableRoundTrip() throws {
        let symptoms = PhysicalSymptoms(
            painLocations: [.head, .lowerBack],
            painSeverity: 7,
            painType: .sharp,
            muscleStiffness: .moderate,
            muscleSoreness: .mild
        )
        
        let data = try JSONEncoder().encode(symptoms)
        let decoded = try JSONDecoder().decode(PhysicalSymptoms.self, from: data)
        
        XCTAssertEqual(decoded.painLocations, [.head, .lowerBack])
        XCTAssertEqual(decoded.painSeverity, 7)
        XCTAssertEqual(decoded.painType, .sharp)
        XCTAssertEqual(decoded.muscleStiffness, .moderate)
        XCTAssertEqual(decoded.muscleSoreness, .mild)
    }
}
