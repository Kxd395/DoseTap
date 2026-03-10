import Testing
import Foundation
@testable import DoseCore

// MARK: - Helpers

private let epoch = Date(timeIntervalSince1970: 0)
private func day(_ n: Int) -> Date { epoch.addingTimeInterval(Double(n) * 86400) }

private func point(
    dayOffset: Int = 0,
    interval: Double? = 165,
    skipped: Bool = false,
    totalSleep: Double? = nil,
    deepSleep: Double? = nil,
    recovery: Int? = nil,
    hrv: Double? = nil,
    awakenings: Int? = nil
) -> DoseEffectivenessDataPoint {
    .init(
        date: day(dayOffset),
        intervalMinutes: interval,
        dose2Skipped: skipped,
        totalSleepMinutes: totalSleep,
        deepSleepMinutes: deepSleep,
        recoveryScore: recovery,
        averageHRV: hrv,
        awakenings: awakenings
    )
}

// MARK: - Empty Input

@Suite("DoseEffectivenessCalculator")
struct DoseEffectivenessCalculatorTests {

    @Test func emptyInput_returnsZeros() {
        let report = DoseEffectivenessCalculator.analyze([])
        #expect(report.totalNights == 0)
        #expect(report.pairableNights == 0)
        #expect(report.complianceRate == 0)
        #expect(report.recentTrend == nil)
        #expect(report.optimalZone.count == 0)
        #expect(report.acceptableZone.count == 0)
        #expect(report.nonCompliant.count == 0)
    }

    // MARK: - Zone Partitioning

    @Test func optimalZone_150to165() {
        let nights = [
            point(dayOffset: 0, interval: 150),
            point(dayOffset: 1, interval: 158),
            point(dayOffset: 2, interval: 165),
        ]
        let report = DoseEffectivenessCalculator.analyze(nights)
        #expect(report.optimalZone.count == 3)
        #expect(report.acceptableZone.count == 0)
        #expect(report.nonCompliant.count == 0)
        #expect(report.complianceRate == 1.0)
    }

    @Test func acceptableZone_166to240() {
        let nights = [
            point(dayOffset: 0, interval: 170),
            point(dayOffset: 1, interval: 200),
            point(dayOffset: 2, interval: 240),
        ]
        let report = DoseEffectivenessCalculator.analyze(nights)
        #expect(report.optimalZone.count == 0)
        #expect(report.acceptableZone.count == 3)
        #expect(report.complianceRate == 1.0)
    }

    @Test func nonCompliant_outsideWindow() {
        let nights = [
            point(dayOffset: 0, interval: 100),
            point(dayOffset: 1, interval: 250),
        ]
        let report = DoseEffectivenessCalculator.analyze(nights)
        #expect(report.nonCompliant.count == 2)
        #expect(report.complianceRate == 0)
    }

    @Test func skippedDose2_isNonCompliant() {
        let night = point(dayOffset: 0, interval: 165, skipped: true)
        let report = DoseEffectivenessCalculator.analyze([night])
        #expect(report.nonCompliant.count == 1)
        #expect(report.optimalZone.count == 0)
    }

    @Test func nilInterval_isNonCompliant() {
        let night = point(dayOffset: 0, interval: nil)
        let report = DoseEffectivenessCalculator.analyze([night])
        #expect(report.nonCompliant.count == 1)
        #expect(report.complianceRate == 0)
    }

    @Test func mixedZones_partitionedCorrectly() {
        let nights = [
            point(dayOffset: 0, interval: 155),  // optimal
            point(dayOffset: 1, interval: 180),  // acceptable
            point(dayOffset: 2, interval: nil),   // non-compliant
            point(dayOffset: 3, interval: 160),  // optimal
            point(dayOffset: 4, interval: 300),  // non-compliant
        ]
        let report = DoseEffectivenessCalculator.analyze(nights)
        #expect(report.optimalZone.count == 2)
        #expect(report.acceptableZone.count == 1)
        #expect(report.nonCompliant.count == 2)
        #expect(report.totalNights == 5)
        // compliance = 3 compliant / 5 total = 0.6
        #expect(report.complianceRate == 0.6)
    }

    // MARK: - Zone Averages

    @Test func optimalZone_averagesComputed() {
        let nights = [
            point(dayOffset: 0, interval: 150, totalSleep: 420, deepSleep: 90, recovery: 80, hrv: 50, awakenings: 2),
            point(dayOffset: 1, interval: 160, totalSleep: 400, deepSleep: 100, recovery: 90, hrv: 60, awakenings: 1),
        ]
        let z = DoseEffectivenessCalculator.analyze(nights).optimalZone
        #expect(z.averageInterval == 155)
        #expect(z.averageTotalSleep == 410)
        #expect(z.averageDeepSleep == 95)
        #expect(z.averageRecovery == 85)
        #expect(z.averageHRV == 55)
        #expect(z.averageAwakenings == 1.5)
    }

    @Test func zoneSummary_nilMetrics_returnNilAverages() {
        let nights = [
            point(dayOffset: 0, interval: 155),
            point(dayOffset: 1, interval: 160),
        ]
        let z = DoseEffectivenessCalculator.analyze(nights).optimalZone
        #expect(z.count == 2)
        #expect(z.averageTotalSleep == nil)
        #expect(z.averageRecovery == nil)
    }

    @Test func partialMetrics_averageOnlyAvailable() {
        let nights = [
            point(dayOffset: 0, interval: 155, totalSleep: 420),
            point(dayOffset: 1, interval: 160), // no sleep data
        ]
        let z = DoseEffectivenessCalculator.analyze(nights).optimalZone
        #expect(z.averageTotalSleep == 420) // only 1 of 2 had data
    }

    // MARK: - Pairable Nights

    @Test func pairableNights_requiresIntervalAndSleepMetric() {
        let nights = [
            point(dayOffset: 0, interval: 160, totalSleep: 420),  // pairable
            point(dayOffset: 1, interval: 160),                     // not pairable (no sleep)
            point(dayOffset: 2, interval: nil, totalSleep: 420),  // not pairable (no interval)
            point(dayOffset: 3, interval: 170, recovery: 85),     // pairable
        ]
        let report = DoseEffectivenessCalculator.analyze(nights)
        #expect(report.pairableNights == 2)
    }

    // MARK: - Trend

    @Test func trend_fewerThan4Nights_isNil() {
        let nights = [
            point(dayOffset: 0, interval: 200),
            point(dayOffset: 1, interval: 180),
            point(dayOffset: 2, interval: 160),
        ]
        let report = DoseEffectivenessCalculator.analyze(nights)
        #expect(report.recentTrend == nil)
    }

    @Test func trend_improving_intervalDecreasing() {
        let nights = [
            point(dayOffset: 0, interval: 200),
            point(dayOffset: 1, interval: 195),
            point(dayOffset: 2, interval: 170),
            point(dayOffset: 3, interval: 165),
        ]
        let report = DoseEffectivenessCalculator.analyze(nights)
        if case .improving = report.recentTrend {
            // expected
        } else {
            Issue.record("Expected improving trend, got \(String(describing: report.recentTrend))")
        }
    }

    @Test func trend_worsening_intervalIncreasing() {
        let nights = [
            point(dayOffset: 0, interval: 155),
            point(dayOffset: 1, interval: 160),
            point(dayOffset: 2, interval: 190),
            point(dayOffset: 3, interval: 200),
        ]
        let report = DoseEffectivenessCalculator.analyze(nights)
        if case .worsening = report.recentTrend {
            // expected
        } else {
            Issue.record("Expected worsening trend, got \(String(describing: report.recentTrend))")
        }
    }

    @Test func trend_stable_withinThreshold() {
        let nights = [
            point(dayOffset: 0, interval: 164),
            point(dayOffset: 1, interval: 166),
            point(dayOffset: 2, interval: 165),
            point(dayOffset: 3, interval: 167),
        ]
        let report = DoseEffectivenessCalculator.analyze(nights)
        #expect(report.recentTrend == .stable)
    }

    @Test func trend_skipsNilIntervals() {
        let nights = [
            point(dayOffset: 0, interval: 200),
            point(dayOffset: 1, interval: nil),
            point(dayOffset: 2, interval: 195),
            point(dayOffset: 3, interval: nil),
            point(dayOffset: 4, interval: 170),
            point(dayOffset: 5, interval: 165),
        ]
        // Only nights with intervals: [200, 195, 170, 165]
        // Prior half avg: (200+195)/2 = 197.5, Recent half avg: (170+165)/2 = 167.5
        // delta = -30 → improving
        let report = DoseEffectivenessCalculator.analyze(nights)
        if case .improving = report.recentTrend {
            // expected
        } else {
            Issue.record("Expected improving trend, got \(String(describing: report.recentTrend))")
        }
    }

    // MARK: - Constants

    @Test func constants_matchSSOT() {
        #expect(DoseEffectivenessCalculator.windowMin == 150)
        #expect(DoseEffectivenessCalculator.optimalMax == 165)
        #expect(DoseEffectivenessCalculator.windowMax == 240)
    }

    // MARK: - Boundary: exactly 165m

    @Test func boundary_165_isOptimal() {
        let report = DoseEffectivenessCalculator.analyze([point(interval: 165)])
        #expect(report.optimalZone.count == 1)
    }

    @Test func boundary_165_01_isAcceptable() {
        let report = DoseEffectivenessCalculator.analyze([point(interval: 165.01)])
        #expect(report.acceptableZone.count == 1)
    }

    @Test func boundary_150_isOptimal() {
        let report = DoseEffectivenessCalculator.analyze([point(interval: 150)])
        #expect(report.optimalZone.count == 1)
    }

    @Test func boundary_149_99_isNonCompliant() {
        let report = DoseEffectivenessCalculator.analyze([point(interval: 149.99)])
        #expect(report.nonCompliant.count == 1)
    }

    @Test func boundary_240_isAcceptable() {
        let report = DoseEffectivenessCalculator.analyze([point(interval: 240)])
        #expect(report.acceptableZone.count == 1)
    }

    @Test func boundary_240_01_isNonCompliant() {
        let report = DoseEffectivenessCalculator.analyze([point(interval: 240.01)])
        #expect(report.nonCompliant.count == 1)
    }

    // MARK: - IntervalFormat: minutes

    @Test func format_minutes_wholeNumber() {
        let fmt = IntervalFormat.minutes
        #expect(fmt.string(from: 165) == "165m")
    }

    @Test func format_minutes_fractional() {
        let fmt = IntervalFormat.minutes
        #expect(fmt.string(from: 165.5) == "165.5m")
    }

    @Test func format_minutes_nil() {
        #expect(IntervalFormat.minutes.string(from: nil) == "—")
    }

    @Test func format_minutes_zero() {
        #expect(IntervalFormat.minutes.string(from: 0) == "0m")
    }

    @Test func format_minutes_240() {
        #expect(IntervalFormat.minutes.string(from: 240) == "240m")
    }

    // MARK: - IntervalFormat: hoursMinutes

    @Test func format_hm_165() {
        #expect(IntervalFormat.hoursMinutes.string(from: 165) == "2:45")
    }

    @Test func format_hm_150() {
        #expect(IntervalFormat.hoursMinutes.string(from: 150) == "2:30")
    }

    @Test func format_hm_240() {
        #expect(IntervalFormat.hoursMinutes.string(from: 240) == "4:00")
    }

    @Test func format_hm_60() {
        #expect(IntervalFormat.hoursMinutes.string(from: 60) == "1:00")
    }

    @Test func format_hm_0() {
        #expect(IntervalFormat.hoursMinutes.string(from: 0) == "0:00")
    }

    @Test func format_hm_nil() {
        #expect(IntervalFormat.hoursMinutes.string(from: nil) == "—")
    }

    @Test func format_hm_90() {
        #expect(IntervalFormat.hoursMinutes.string(from: 90) == "1:30")
    }

    @Test func format_hm_fractional_rounds() {
        // 165.7 → rounds to 166 → 2:46
        #expect(IntervalFormat.hoursMinutes.string(from: 165.7) == "2:46")
    }

    // MARK: - IntervalFormat: displayName

    @Test func format_displayName_minutes() {
        #expect(IntervalFormat.minutes.displayName == "Minutes (165m)")
    }

    @Test func format_displayName_hoursMinutes() {
        #expect(IntervalFormat.hoursMinutes.displayName == "Hours:Minutes (2:45)")
    }

    // MARK: - IntervalFormat: rawValue / Codable

    @Test func format_rawValue_roundtrip() {
        #expect(IntervalFormat(rawValue: "mm") == .minutes)
        #expect(IntervalFormat(rawValue: "h:mm") == .hoursMinutes)
    }

    @Test func format_allCases() {
        #expect(IntervalFormat.allCases.count == 2)
    }

    // MARK: - ZoneSummary formattedAverageInterval

    @Test func zoneSummary_formattedAverageInterval_minutes() {
        let nights = [
            point(dayOffset: 0, interval: 150),
            point(dayOffset: 1, interval: 160),
        ]
        let z = DoseEffectivenessCalculator.analyze(nights).optimalZone
        #expect(z.formattedAverageInterval(.minutes) == "155m")
    }

    @Test func zoneSummary_formattedAverageInterval_hm() {
        let nights = [
            point(dayOffset: 0, interval: 150),
            point(dayOffset: 1, interval: 160),
        ]
        let z = DoseEffectivenessCalculator.analyze(nights).optimalZone
        #expect(z.formattedAverageInterval(.hoursMinutes) == "2:35")
    }

    @Test func zoneSummary_formattedAverageInterval_nilAverage() {
        let report = DoseEffectivenessCalculator.analyze([])
        #expect(report.optimalZone.formattedAverageInterval(.minutes) == "—")
        #expect(report.optimalZone.formattedAverageInterval(.hoursMinutes) == "—")
    }
}
