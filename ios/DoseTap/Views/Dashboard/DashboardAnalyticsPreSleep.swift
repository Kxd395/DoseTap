import Foundation

extension DashboardAnalyticsModel {
    // MARK: - Lifestyle Factor Metrics (from Pre-Sleep Log)

    private var nightsWithPreSleep: [DashboardNightAggregate] {
        populatedNights.filter { $0.preSleepLog?.completionState == "complete" && $0.preSleepLog?.answers != nil }
    }

    var averageStressLevel: Double? {
        let values = nightsWithPreSleep.compactMap { $0.preSleepLog?.answers?.stressLevel }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    var highPreSleepStressRate: Double? {
        percentage(
            matching: nightsWithPreSleep.compactMap { $0.preSleepLog?.answers?.stressLevel },
            where: { $0 >= 4 }
        )
    }

    var preSleepStressDriverCounts: [CommonStressDriver: Int] {
        let drivers = nightsWithPreSleep.flatMap { $0.preSleepLog?.answers?.resolvedStressDrivers ?? [] }
        return counts(for: drivers)
    }

    var topPreSleepStressDriver: CommonStressDriver? {
        topKey(in: preSleepStressDriverCounts)
    }

    var stressTrendPoints: [DashboardStressTrendPoint] {
        populatedNights.compactMap { night -> DashboardStressTrendPoint? in
            guard let date = Self.keyFormatter.date(from: night.sessionDate) else {
                return nil
            }
            let bedtimeDrivers = night.preSleepLog?.answers?.resolvedStressDrivers ?? []
            let wakeDrivers = night.morningCheckIn?.resolvedStressDrivers ?? []
            let point = DashboardStressTrendPoint(
                sessionDate: night.sessionDate,
                date: date,
                bedtimeStress: night.preSleepLog?.answers?.stressLevel.map(Double.init),
                wakeStress: night.morningCheckIn?.stressLevel.map(Double.init),
                sleepQuality: night.morningCheckIn.map(\.sleepQuality),
                readiness: night.morningCheckIn.map { Double($0.readinessForDay) },
                intervalMinutes: night.intervalMinutes.map(Double.init),
                bedtimeDrivers: bedtimeDrivers,
                wakeDrivers: wakeDrivers
            )
            if point.bedtimeStress == nil &&
                point.wakeStress == nil &&
                point.sleepQuality == nil &&
                point.readiness == nil &&
                bedtimeDrivers.isEmpty &&
                wakeDrivers.isEmpty {
                return nil
            }
            return point
        }
        .sorted { $0.date < $1.date }
    }

    var stressTrendNightCount: Int {
        stressTrendPoints.count
    }

    var combinedStressDriverCounts: [CommonStressDriver: Int] {
        counts(for: stressTrendPoints.flatMap { Array(Set($0.bedtimeDrivers + $0.wakeDrivers)) })
    }

    var carryoverStressDriverCounts: [CommonStressDriver: Int] {
        counts(for: stressTrendPoints.flatMap(\.carryoverDrivers))
    }

    var recurringStressDrivers: [DashboardStressDriverFrequency] {
        combinedStressDriverCounts.map { driver, totalCount in
            DashboardStressDriverFrequency(
                driver: driver,
                totalCount: totalCount,
                carryoverCount: carryoverStressDriverCounts[driver, default: 0]
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalCount == rhs.totalCount {
                if lhs.carryoverCount == rhs.carryoverCount {
                    return lhs.driver.displayText < rhs.driver.displayText
                }
                return lhs.carryoverCount > rhs.carryoverCount
            }
            return lhs.totalCount > rhs.totalCount
        }
    }

    var topRecurringStressDriver: CommonStressDriver? {
        recurringStressDrivers.first?.driver
    }

    var topCarryoverStressDriver: CommonStressDriver? {
        topKey(in: carryoverStressDriverCounts)
    }

    var stressCarryoverNightRate: Double? {
        percentage(
            matching: stressTrendPoints.compactMap { point -> Bool? in
                guard !point.bedtimeDrivers.isEmpty, !point.wakeDrivers.isEmpty else {
                    return nil
                }
                return !point.carryoverDrivers.isEmpty
            },
            where: { $0 }
        )
    }

    var sleepQualityByHighBedtimeStress: (high: Double?, lower: Double?) {
        let high = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress >= 4 else {
                return nil
            }
            guard let sleepQuality = night.morningCheckIn?.sleepQuality else {
                return nil
            }
            return sleepQuality
        }
        let lower = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress <= 3 else {
                return nil
            }
            guard let sleepQuality = night.morningCheckIn?.sleepQuality else {
                return nil
            }
            return sleepQuality
        }
        return (average(high), average(lower))
    }

    var readinessByHighBedtimeStress: (high: Double?, lower: Double?) {
        let high = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress >= 4 else {
                return nil
            }
            guard let readiness = night.morningCheckIn?.readinessForDay else {
                return nil
            }
            return Double(readiness)
        }
        let lower = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress <= 3 else {
                return nil
            }
            guard let readiness = night.morningCheckIn?.readinessForDay else {
                return nil
            }
            return Double(readiness)
        }
        return (average(high), average(lower))
    }

    var intervalByHighBedtimeStress: (high: Double?, lower: Double?) {
        let high = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress >= 4 else {
                return nil
            }
            return night.intervalMinutes.map(Double.init)
        }
        let lower = populatedNights.compactMap { night -> Double? in
            guard let stress = night.preSleepLog?.answers?.stressLevel, stress <= 3 else {
                return nil
            }
            return night.intervalMinutes.map(Double.init)
        }
        return (average(high), average(lower))
    }

    func lifestyleSampleCounts(_ answer: (PreSleepLogAnswers) -> Bool?) -> (answered: Int, yes: Int, no: Int) {
        let answered = nightsWithPreSleep.filter { $0.preSleepLog?.answers.flatMap(answer) != nil }.count
        let paired = nightsWithPreSleep.compactMap { night -> Bool? in
            guard night.morningCheckIn != nil, let answers = night.preSleepLog?.answers else { return nil }
            return answer(answers)
        }
        return (answered, paired.filter { $0 }.count, paired.filter { !$0 }.count)
    }

    var caffeineRate: Double? {
        percentage(matching: nightsWithPreSleep.compactMap { $0.preSleepLog?.answers?.reportedCaffeine }, where: { $0 })
    }

    var alcoholRate: Double? {
        percentage(matching: nightsWithPreSleep.compactMap { $0.preSleepLog?.answers?.alcohol }, where: { $0 != .none })
    }

    var exerciseRate: Double? {
        percentage(matching: nightsWithPreSleep.compactMap { $0.preSleepLog?.answers?.exercise }, where: { $0 != .none })
    }

    var screenTimeRate: Double? {
        percentage(matching: nightsWithPreSleep.compactMap { $0.preSleepLog?.answers?.screensInBed }, where: { $0 != .none })
    }

    var lateMealRate: Double? {
        percentage(matching: nightsWithPreSleep.compactMap { $0.preSleepLog?.answers?.lateMeal }, where: { $0 != .none })
    }

    var sleepQualityByCaffeine: (with: Double?, without: Double?) {
        let withCaff = nightsWithPreSleep.filter {
            $0.preSleepLog?.answers?.reportedCaffeine == true
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let noCaff = nightsWithPreSleep.filter {
            $0.preSleepLog?.answers?.reportedCaffeine == false
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let avgWith = withCaff.isEmpty ? nil : Double(withCaff.reduce(0, +)) / Double(withCaff.count)
        let avgWithout = noCaff.isEmpty ? nil : Double(noCaff.reduce(0, +)) / Double(noCaff.count)
        return (avgWith, avgWithout)
    }

    var sleepQualityByAlcohol: (with: Double?, without: Double?) {
        let withAlc = nightsWithPreSleep.filter {
            guard let a = $0.preSleepLog?.answers?.alcohol else { return false }
            return a != PreSleepLogAnswers.AlcoholLevel.none
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let noAlc = nightsWithPreSleep.filter {
            $0.preSleepLog?.answers?.alcohol == PreSleepLogAnswers.AlcoholLevel.none
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let avgWith = withAlc.isEmpty ? nil : Double(withAlc.reduce(0, +)) / Double(withAlc.count)
        let avgWithout = noAlc.isEmpty ? nil : Double(noAlc.reduce(0, +)) / Double(noAlc.count)
        return (avgWith, avgWithout)
    }

    var sleepQualityByScreens: (with: Double?, without: Double?) {
        let withScr = nightsWithPreSleep.filter {
            guard let s = $0.preSleepLog?.answers?.screensInBed else { return false }
            return s != PreSleepLogAnswers.ScreensInBed.none
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let noScr = nightsWithPreSleep.filter {
            $0.preSleepLog?.answers?.screensInBed == PreSleepLogAnswers.ScreensInBed.none
        }.compactMap { $0.morningCheckIn?.sleepQuality }
        let avgWith = withScr.isEmpty ? nil : Double(withScr.reduce(0, +)) / Double(withScr.count)
        let avgWithout = noScr.isEmpty ? nil : Double(noScr.reduce(0, +)) / Double(noScr.count)
        return (avgWith, avgWithout)
    }
}

extension PreSleepLogAnswers {
    var reportedCaffeine: Bool? {
        guard caffeineSourceSummary != nil || caffeineSources != nil else { return nil }
        return hasCaffeineIntake
    }
}
