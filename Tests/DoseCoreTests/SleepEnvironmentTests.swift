import XCTest
@testable import DoseCore

final class SleepEnvironmentTests: XCTestCase {
    
    // MARK: - SleepEnvironment Tests
    
    func testSleepEnvironmentInitialization() {
        let env = SleepEnvironment()
        
        XCTAssertTrue(env.sleepAidsUsed.isEmpty)
        XCTAssertEqual(env.roomDarkness, .dark)
        XCTAssertEqual(env.noiseLevel, .quiet)
        XCTAssertEqual(env.screenInBedMinutesBucket, .none)
        XCTAssertEqual(env.temperatureComfort, .comfortable)
        XCTAssertFalse(env.hadPartnerDisruption)
        XCTAssertFalse(env.hadPetDisruption)
    }
    
    func testSleepEnvironmentWithAids() {
        let env = SleepEnvironment(
            sleepAidsUsed: [.eyeMask, .earplugs, .whiteNoise],
            roomDarkness: .pitch,
            noiseLevel: .whiteNoise
        )
        
        XCTAssertEqual(env.sleepAidsUsed.count, 3)
        XCTAssertTrue(env.sleepAidsUsed.contains(.eyeMask))
        XCTAssertTrue(env.sleepAidsUsed.contains(.earplugs))
        XCTAssertTrue(env.sleepAidsUsed.contains(.whiteNoise))
        XCTAssertEqual(env.roomDarkness, .pitch)
        XCTAssertEqual(env.noiseLevel, .whiteNoise)
    }
    
    func testSleepEnvironmentCodable() throws {
        let env = SleepEnvironment(
            sleepAidsUsed: [.eyeMask, .weightedBlanket],
            roomDarkness: .dim,
            noiseLevel: .someNoise,
            screenInBedMinutesBucket: .thirtyToSixty,
            temperatureComfort: .tooWarm,
            hadPartnerDisruption: true
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(env)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SleepEnvironment.self, from: data)
        
        XCTAssertEqual(decoded.sleepAidsUsed, env.sleepAidsUsed)
        XCTAssertEqual(decoded.roomDarkness, env.roomDarkness)
        XCTAssertEqual(decoded.noiseLevel, env.noiseLevel)
        XCTAssertEqual(decoded.screenInBedMinutesBucket, env.screenInBedMinutesBucket)
        XCTAssertEqual(decoded.temperatureComfort, env.temperatureComfort)
        XCTAssertEqual(decoded.hadPartnerDisruption, env.hadPartnerDisruption)
    }
    
    // MARK: - SleepAid Tests
    
    func testAllSleepAidsHaveIcons() {
        for aid in SleepAid.allCases {
            XCTAssertFalse(aid.icon.isEmpty, "\(aid.rawValue) should have an icon")
        }
    }
    
    func testAllSleepAidsHaveCategories() {
        for aid in SleepAid.allCases {
            // Just verify accessing category doesn't crash
            _ = aid.category
        }
    }
    
    func testSleepAidCategorization() {
        // Physical aids
        XCTAssertEqual(SleepAid.eyeMask.category, .physical)
        XCTAssertEqual(SleepAid.earplugs.category, .physical)
        XCTAssertEqual(SleepAid.weightedBlanket.category, .physical)
        
        // Relaxation aids
        XCTAssertEqual(SleepAid.sleepMeditation.category, .relaxation)
        XCTAssertEqual(SleepAid.breathingExercises.category, .relaxation)
        
        // Supplements
        XCTAssertEqual(SleepAid.melatonin.category, .supplement)
        XCTAssertEqual(SleepAid.magnesium.category, .supplement)
        XCTAssertEqual(SleepAid.cbdOrThc.category, .supplement)
        
        // Screens
        XCTAssertEqual(SleepAid.tvOn.category, .screen)
        XCTAssertEqual(SleepAid.phoneInBed.category, .screen)
    }
    
    func testSleepAidCategoryContainsCorrectAids() {
        let physicalAids = SleepAidCategory.physical.aids
        XCTAssertTrue(physicalAids.contains(.eyeMask))
        XCTAssertTrue(physicalAids.contains(.earplugs))
        XCTAssertFalse(physicalAids.contains(.melatonin))
        
        let screenAids = SleepAidCategory.screen.aids
        XCTAssertTrue(screenAids.contains(.tvOn))
        XCTAssertTrue(screenAids.contains(.phoneInBed))
        XCTAssertFalse(screenAids.contains(.eyeMask))
    }
    
    // MARK: - DarknessLevel Tests
    
    func testAllDarknessLevelsHaveIcons() {
        for level in DarknessLevel.allCases {
            XCTAssertFalse(level.icon.isEmpty, "\(level.rawValue) should have an icon")
        }
    }
    
    // MARK: - NoiseLevel Tests
    
    func testAllNoiseLevelsHaveIcons() {
        for level in NoiseLevel.allCases {
            XCTAssertFalse(level.icon.isEmpty, "\(level.rawValue) should have an icon")
        }
    }
    
    // MARK: - ScreenTimeBucket Tests
    
    func testScreenTimeBucketMidpoints() {
        XCTAssertEqual(ScreenTimeBucket.none.midpointMinutes, 0)
        XCTAssertEqual(ScreenTimeBucket.under15.midpointMinutes, 7)
        XCTAssertEqual(ScreenTimeBucket.fifteenToThirty.midpointMinutes, 22)
        XCTAssertEqual(ScreenTimeBucket.thirtyToSixty.midpointMinutes, 45)
        XCTAssertEqual(ScreenTimeBucket.overHour.midpointMinutes, 90)
    }
    
    // MARK: - TemperatureComfort Tests
    
    func testAllTemperatureComfortLevelsHaveIcons() {
        for level in TemperatureComfort.allCases {
            XCTAssertFalse(level.icon.isEmpty, "\(level.rawValue) should have an icon")
        }
    }
    
    // MARK: - MorningCheckIn Integration
    
    @available(iOS 15.0, *)
    func testMorningCheckInWithSleepEnvironment() {
        let env = SleepEnvironment(
            sleepAidsUsed: [.eyeMask, .whiteNoise],
            roomDarkness: .pitch
        )
        
        let checkin = MorningCheckIn(
            sessionId: UUID(),
            hasSleepEnvironmentData: true,
            sleepEnvironment: env
        )
        
        XCTAssertTrue(checkin.hasSleepEnvironmentData)
        XCTAssertNotNil(checkin.sleepEnvironment)
        XCTAssertEqual(checkin.sleepEnvironment?.sleepAidsUsed.count, 2)
    }
    
    @available(iOS 15.0, *)
    func testMorningCheckInWithoutSleepEnvironment() {
        let checkin = MorningCheckIn(sessionId: UUID())
        
        XCTAssertFalse(checkin.hasSleepEnvironmentData)
        XCTAssertNil(checkin.sleepEnvironment)
    }
}
