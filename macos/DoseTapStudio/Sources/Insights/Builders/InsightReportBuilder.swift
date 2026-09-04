import Foundation

struct InsightExportRedactionOptions: Hashable, Sendable {
    let redactFreeText: Bool
    let redactExactTimestamps: Bool
    let redactBundleFingerprint: Bool

    static let none = InsightExportRedactionOptions(
        redactFreeText: false,
        redactExactTimestamps: false,
        redactBundleFingerprint: false
    )

    static let clinicianSafe = InsightExportRedactionOptions(
        redactFreeText: true,
        redactExactTimestamps: true,
        redactBundleFingerprint: true
    )
}

struct InsightReportBuilder {
    private let recommendationEngine = InsightRecommendationEngine()

    func buildProviderSummary(
        sessions: [InsightSession],
        maxSessions: Int = 30,
        bundle: InsightBundle? = nil,
        redaction: InsightExportRedactionOptions = .none
    ) -> String {
        let selected = Array(sessions.prefix(maxSessions))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let dateRange = reportDateRange(for: selected, formatter: formatter)
        let intervalValues = selected.compactMap(\.intervalMinutes)
        let sleepQualityValues = selected.compactMap(\.morningSleepQuality)
        let readinessValues = selected.compactMap(\.morningReadiness)
        let sleepEfficiencyValues = selected.compactMap(\.sleepEfficiency)
        let recoveryValues = selected.compactMap(\.whoopRecovery)
        let totalSleepValues = selected.compactMap(\.totalSleepMinutes)
        let hrvValues = selected.compactMap(\.hrvMs)
        let drivingConfidenceValues = selected.compactMap(\.morning?.drivingConfidence)
        let daytimeSleepinessValues = selected.compactMap(\.morning?.daytimeSleepiness)
        let lateCount = selected.filter(\.isLateDose2).count
        let skippedCount = selected.filter(\.dose2Skipped).count
        let highStressCount = selected.filter { ($0.preSleepStressLevel ?? 0) >= 4 }.count
        let missingMorningCount = selected.filter { $0.morning == nil }.count
        let healthKitCount = selected.filter { $0.healthKit != nil }.count
        let whoopCount = selected.filter { $0.whoop != nil }.count
        let likelyNaturalWakeCount = selected.filter { $0.likelyNaturalWake == true }.count
        let alarmAssistedCount = selected.filter { $0.likelyNaturalWake == false }.count
        let lateMealCount = selected.filter(\.hasLateMealContext).count
        let scheduleMarkerCount = selected.filter { !($0.context?.scheduleMarkers.isEmpty ?? true) }.count
        let trainableNightCount = selected.filter(\.countsTowardRecommendationTraining).count
        let highConfidenceCount = selected.filter { $0.classification.confidenceBucket == .high }.count
        let reconciledDose2Count = selected.filter(\.wasDose2ReconciledInMorning).count
        let sleptThroughCount = selected.filter { $0.context?.dose2Outcome?.skipReason == "slept_through" }.count
        let dose2TimingExceptionCount = selected.filter { $0.context?.dose2Outcome?.takenReason != nil && $0.dose2TakenReasonLabel != "Forgot To Tap" && $0.dose2TakenReasonLabel != "Unsure" }.count
        let dose2ReasonMismatchCount = selected.filter(\.hasDose2ReasonMismatch).count
        let workSafetyContextCount = selected.filter { $0.morning?.drivingConfidence != nil || $0.context?.wakeRequirement != nil || $0.context?.shiftStartAtUTC != nil || $0.context?.nextRequiredWakeAtUTC != nil }.count
        let clinicalContextCount = selected.filter { !($0.morning?.sleepDisorders ?? []).isEmpty || $0.morning?.sleepDisorderNotes != nil || $0.morning?.coMedicationNotes != nil || $0.morning?.pharmacogenomicFastMetabolizer == true }.count
        let fastMetabolizerContextCount = selected.filter { $0.morning?.pharmacogenomicFastMetabolizer == true }.count

        let onTimeQuality = average(of: selected.filter(\.isOnTimeDose2).compactMap(\.morningSleepQuality))
        let lateQuality = average(of: selected.filter(\.isLateDose2).compactMap(\.morningSleepQuality))
        let flaggedSessions = selected.filter { !$0.qualityFlags.isEmpty || $0.dose2Skipped || $0.isLateDose2 }

        var lines: [String] = [
            "DoseTap Insights Provider Summary",
            "Generated: \(formatter.string(from: Date()))",
            "Included nights: \(selected.count)",
            "Date range: \(dateRange)",
            "",
            "Overview",
            "Average Dose 2 interval: \(formattedAverage(intervalValues, suffix: " min"))",
            "Late Dose 2 nights: \(lateCount)",
            "Dose 2 skipped nights: \(skippedCount)",
            "Average morning sleep quality: \(formattedAverage(sleepQualityValues, suffix: " / 5"))",
            "Average morning readiness: \(formattedAverage(readinessValues, suffix: " / 5"))",
            "High-stress pre-sleep nights: \(highStressCount)",
            "Missing morning check-ins: \(missingMorningCount)",
            "Apple Health nights: \(healthKitCount)",
            "WHOOP nights: \(whoopCount)",
            "Likely natural wake nights: \(likelyNaturalWakeCount)",
            "Alarm-assisted wake nights: \(alarmAssistedCount)",
            "Late meal nights: \(lateMealCount)",
            "Schedule-marker nights: \(scheduleMarkerCount)",
            "Morning-reconciled Dose 2 nights: \(reconciledDose2Count)",
            "Slept-through Dose 2 nights: \(sleptThroughCount)",
            "Dose 2 timing-exception nights: \(dose2TimingExceptionCount)",
            "Dose 2 reason-mismatch nights: \(dose2ReasonMismatchCount)",
            "Work / safety context nights: \(workSafetyContextCount)",
            "Clinical context nights: \(clinicalContextCount)",
            "Fast-metabolizer reference nights: \(fastMetabolizerContextCount)",
            "Trainable nights: \(trainableNightCount)",
            "High-confidence nights: \(highConfidenceCount)",
            "Average total sleep: \(formattedDuration(totalSleepValues))",
            "Average sleep efficiency: \(formattedAverage(sleepEfficiencyValues, suffix: "%"))",
            "Average WHOOP recovery: \(formattedAverage(recoveryValues, suffix: "%"))",
            "Average HRV: \(formattedAverage(hrvValues, suffix: " ms"))",
            "Average driving confidence: \(formattedAverage(drivingConfidenceValues, suffix: " / 5"))",
            "Average daytime sleepiness: \(formattedAverage(daytimeSleepinessValues, suffix: " / 5"))",
            "",
            "Quick comparison",
            "On-time nights avg morning quality: \(formattedAverage(onTimeQuality, suffix: " / 5"))",
            "Late nights avg morning quality: \(formattedAverage(lateQuality, suffix: " / 5"))",
            ""
        ]

        appendBundleMetadata(into: &lines, bundle: bundle, redaction: redaction)

        if flaggedSessions.isEmpty {
            lines.append("Flagged nights")
            lines.append("None in the exported range.")
        } else {
            lines.append("Flagged nights")
            for session in flaggedSessions.prefix(10) {
                lines.append("- \(session.sessionDate): \(flagSummary(for: session))")
            }
        }

        lines.append("")
        lines.append("Notes")
        lines.append("This summary is generated from local DoseTap exports and is intended for review, not diagnosis.")
        if redaction != .none {
            lines.append("Redaction applied: free-text notes, exact timestamps, and bundle fingerprint details removed.")
        }
        return lines.joined(separator: "\n")
    }

    func buildRecommendationPackage(
        sessions: [InsightSession],
        mode: InsightRecommendationMode,
        maxMatchedRows: Int = 12,
        bundle: InsightBundle? = nil,
        redaction: InsightExportRedactionOptions = .none
    ) -> String {
        let result = recommendationEngine.recommend(sessions: sessions, mode: mode)

        var lines: [String] = [
            "DoseTap Timing Insight Review Package",
            "Mode: \(mode.displayTitle)",
            "Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))",
            "",
            "Summary",
            result.summary,
            result.cohortDescription,
            "Confidence: \(result.confidenceBucket.label)",
            "Cohort key: \(result.cohortKey ?? "Unavailable")",
            "Observed timing band: \(result.recommendedBand?.label ?? "Not enough evidence")",
            "Comparable nights used: \(result.nightsUsed)",
            "Comparable nights excluded: \(result.nightsExcluded)",
            "Scoring basis: \(mode.transparencySummary)",
            ""
        ]

        appendBundleMetadata(into: &lines, bundle: bundle, redaction: redaction)

        if !result.topFactors.isEmpty {
            lines.append("Top factors")
            result.topFactors.forEach { lines.append("- \($0)") }
            lines.append("")
        }

        if !result.candidates.isEmpty {
            lines.append("Timing band comparison")
            for candidate in result.candidates {
                lines.append(
                    "- \(candidate.band.label): \(candidate.sampleCount) night(s), score \(String(format: "%.2f", candidate.averageScore)), SQ \(formatted(candidate.averageSleepQuality, decimals: 1)), readiness \(formatted(candidate.averageReadiness, decimals: 1)), sleep \(formatted(candidate.averageTotalSleepMinutes, decimals: 0)) min, HRV \(formatted(candidate.averageHRV, decimals: 1)) ms, RHR \(formatted(candidate.averageRestingHeartRate, decimals: 1)) bpm, Resp \(formatted(candidate.averageRespiratoryRate, decimals: 1)) br/min, restorative \(formatted(candidate.averageRestorativeSleepRatio.map { $0 * 100 }, decimals: 0))%, stage \(formatted(candidate.averageSleepStageBalance, decimals: 2)), alarm dep \(formatted(candidate.alarmDependenceRate.map { $0 * 100 }, decimals: 0))%, skip/late \(formatted(candidate.skipLateRiskRate.map { $0 * 100 }, decimals: 0))%, risk \(formatted(candidate.operationalRiskRate.map { $0 * 100 }, decimals: 0))%"
                )
            }
            lines.append("")
        }

        if !result.matchedNights.isEmpty {
            lines.append("Matched nights")
            for night in result.matchedNights.prefix(maxMatchedRows) {
                lines.append("- \(night.sessionDate): \(night.bandLabel ?? "—"), interval \(night.intervalMinutes.map { "\($0)m" } ?? "—"), SQ \(formatted(night.sleepQuality, decimals: 2)), readiness \(night.readiness.map(String.init) ?? "—"), wake \(night.wakeType)")
            }
            lines.append("")
        }

        if !result.excludedNights.isEmpty {
            lines.append("Excluded comparable nights")
            for night in result.excludedNights.prefix(maxMatchedRows) {
                lines.append("- \(night.sessionDate): \(night.exclusionReasons.joined(separator: ", "))")
            }
            lines.append("")
        }

        lines.append("Clinical note")
        lines.append(result.disclaimer)
        if redaction != .none {
            lines.append("Redaction applied: free-text notes, exact timestamps, and bundle fingerprint details removed.")
        }

        return lines.joined(separator: "\n")
    }

    func buildRecommendationComparisonCSV(
        sessions: [InsightSession],
        mode: InsightRecommendationMode
    ) -> String {
        let result = recommendationEngine.recommend(sessions: sessions, mode: mode)
        let nights = result.matchedNights + result.excludedNights
        var rows: [String] = []
        rows.reserveCapacity(nights.count)

        for night in nights {
            let rowType = night.trainable ? "matched" : "excluded"
            let interval = night.intervalMinutes.map(String.init) ?? ""
            let score = night.score.map { String(format: "%.2f", $0) } ?? ""
            let sleepQuality = night.sleepQuality.map { String(format: "%.2f", $0) } ?? ""
            let readiness = night.readiness.map(String.init) ?? ""
            let exclusionReasons = night.exclusionReasons.joined(separator: "; ")

            let values = [
                night.sessionDate,
                rowType,
                result.mode.displayTitle,
                result.cohortKey ?? "",
                night.bandLabel ?? "",
                interval,
                score,
                sleepQuality,
                readiness,
                night.wakeType,
                night.nightType,
                exclusionReasons
            ]
            rows.append(values.map(csvField).joined(separator: ","))
        }

        return ([
            "session_date,row_type,mode,cohort_key,timing_band,interval_minutes,score,sleep_quality,readiness,wake_type,night_type,exclusion_reasons"
        ] + rows).joined(separator: "\n") + "\n"
    }

    func buildSessionCSV(sessions: [InsightSession]) -> String {
        buildSessionCSV(sessions: sessions, redaction: .none)
    }

    func buildSessionCSV(
        sessions: [InsightSession],
        redaction: InsightExportRedactionOptions
    ) -> String {
        var rows: [String] = []
        rows.reserveCapacity(sessions.count)

        for session in sessions {
            let sessionDate = session.sessionDate
            let dose1UTC = iso8601(session.dose1Time, redaction: redaction)
            let dose2UTC = iso8601(session.dose2Time, redaction: redaction)
            let dose2Skipped = session.dose2Skipped ? "true" : "false"
            let intervalMinutes = session.intervalMinutes.map(String.init) ?? ""
            let eventCount = String(session.eventCount)
            let preSleepStress = session.preSleepStressLevel.map(String.init) ?? ""
            let morningSleepQuality = session.morningSleepQuality.map { String(format: "%.2f", $0) } ?? ""
            let morningReadiness = session.morningReadiness.map(String.init) ?? ""
            let medicationCount = String(session.medicationCount)
            let totalSleepMinutes = session.totalSleepMinutes.map { String(format: "%.1f", $0) } ?? ""
            let sleepEfficiency = session.sleepEfficiency.map { String(format: "%.1f", $0) } ?? ""
            let sleepPerformance = session.whoop?.sleepPerformance.flatMap { value in
                String(format: "%.1f", value)
            } ?? ""
            let sleepConsistency = session.whoop?.sleepConsistency.flatMap { value in
                String(format: "%.1f", value)
            } ?? ""
            let whoopRecovery = session.whoopRecovery.map(String.init) ?? ""
            let averageHeartRate = session.averageHeartRate.map { String(format: "%.1f", $0) } ?? ""
            let hrvMs = session.hrvMs.map { String(format: "%.1f", $0) } ?? ""
            let wakeDisruptionCount = session.wakeDisruptionCount.map(String.init) ?? ""
            let healthKitAwakeMinutes = session.healthKit?.awakeMinutes.map { String(format: "%.1f", $0) }
            let whoopAwakeMinutes = session.whoop.map { String($0.awakeMinutes) }
            let awakeMinutes = healthKitAwakeMinutes ?? whoopAwakeMinutes ?? ""
            let wasoMinutes = session.healthKit?.wakeAfterSleepOnsetMinutes.map { String(format: "%.1f", $0) } ?? ""
            let healthKitInBedMinutes = session.healthKit?.inBedMinutes.map { String(format: "%.1f", $0) }
            let whoopInBedMinutes = session.whoop?.inBedMinutes.map(String.init)
            let inBedMinutes = healthKitInBedMinutes ?? whoopInBedMinutes ?? ""
            let coreSleepMinutes = session.healthKit?.coreSleepMinutes.map { String(format: "%.1f", $0) } ?? ""
            let healthKitDeepSleepMinutes = session.healthKit?.deepSleepMinutes.map { String(format: "%.1f", $0) }
            let whoopDeepSleepMinutes = session.whoop.map { String($0.deepMinutes) }
            let deepSleepMinutes = healthKitDeepSleepMinutes ?? whoopDeepSleepMinutes ?? ""
            let healthKitRemSleepMinutes = session.healthKit?.remSleepMinutes.map { String(format: "%.1f", $0) }
            let whoopRemSleepMinutes = session.whoop.map { String($0.remMinutes) }
            let remSleepMinutes = healthKitRemSleepMinutes ?? whoopRemSleepMinutes ?? ""
            let lightSleepMinutes = session.whoop.map { String($0.lightMinutes) } ?? ""
            let spo2Percentage = session.whoop?.spo2Percentage.flatMap { value in
                String(format: "%.1f", value)
            } ?? ""
            let skinTempCelsius = session.whoop?.skinTempCelsius.flatMap { value in
                String(format: "%.1f", value)
            } ?? ""
            let nextMorningWeekday = session.nextMorningWeekdayLabel ?? ""
            let wakeSignal = session.context?.wakeSignal ?? ""
            let scheduleDayType = session.context?.scheduleDayType ?? ""
            let explicitNightType = session.context?.explicitNightType ?? ""
            let explicitNextDayDemand = session.context?.explicitNextDayDemand ?? ""
            let explicitDose2WakeMethod = session.context?.explicitDose2WakeMethod ?? ""
            let explicitBackToSleepDuration = session.context?.explicitBackToSleepDuration ?? ""
            let wakeRequirement = session.context?.wakeRequirement ?? ""
            let shiftStartUTC = iso8601(session.context?.shiftStartAtUTC, redaction: redaction)
            let shiftEndUTC = iso8601(session.context?.shiftEndAtUTC, redaction: redaction)
            let nextRequiredWakeUTC = iso8601(session.context?.nextRequiredWakeAtUTC, redaction: redaction)
            let commuteMinutes = session.context?.commuteMinutes.map(String.init) ?? ""
            let alarmScheduledForUTC = iso8601(session.context?.alarm?.scheduledForUTC, redaction: redaction)
            let alarmFirstFireUTC = iso8601(session.context?.alarm?.firstFireAtUTC, redaction: redaction)
            let alarmAcknowledgedUTC = iso8601(session.context?.alarm?.acknowledgedAtUTC, redaction: redaction)
            let alarmAcknowledgementAction = session.context?.alarm?.acknowledgementAction ?? ""
            let followUpDeliveredCount = session.context?.alarm.map { String($0.followUpDeliveredCount) } ?? ""
            let dose2TakenSource = session.context?.dose2Outcome?.takenSource ?? ""
            let dose2LiveTakenReason = session.context?.dose2Outcome?.liveTakenReason ?? ""
            let dose2MorningTakenReason = session.context?.dose2Outcome?.morningTakenReason ?? ""
            let dose2TakenReason = session.context?.dose2Outcome?.takenReason ?? ""
            let dose2TakenReasonNotes = redact(session.context?.dose2Outcome?.takenReasonNotes, redaction: redaction)
            let dose2LiveSkipReason = session.context?.dose2Outcome?.liveSkipReason ?? ""
            let dose2MorningSkipReason = session.context?.dose2Outcome?.morningSkipReason ?? ""
            let dose2SkipReason = session.context?.dose2Outcome?.skipReason ?? ""
            let dose2SkipReasonNotes = redact(session.context?.dose2Outcome?.skipReasonNotes, redaction: redaction)
            let dose2SkipSource = session.context?.dose2Outcome?.skipSource ?? ""
            let dose2ReasonMismatch = (session.context?.dose2Outcome?.reasonMismatch ?? false) ? "true" : "false"
            let dose2TakenEarly = (session.context?.dose2Outcome?.takenEarly ?? false) ? "true" : "false"
            let dose2TakenLate = (session.context?.dose2Outcome?.takenLate ?? false) ? "true" : "false"
            let dose2HasExtraDose = (session.context?.dose2Outcome?.hasExtraDose ?? false) ? "true" : "false"
            let drivingConfidence = session.morning?.drivingConfidence.map(String.init) ?? ""
            let daytimeSleepiness = session.morning?.daytimeSleepiness.map(String.init) ?? ""
            let cataplexyBurden = session.morning?.cataplexyBurden ?? ""
            let painBurden = session.morning?.painBurden ?? ""
            let anxietyBurden = session.morning?.anxietyBurden ?? session.morning?.anxietyLevel ?? ""
            let congestionBurden = session.morning?.congestionBurden ?? ""
            let refluxBurden = session.morning?.refluxBurden ?? ""
            let restlessLegsBurden = session.morning?.restlessLegsBurden ?? ""
            let bathroomUrgencyBurden = session.morning?.bathroomUrgencyBurden ?? ""
            let sleepTherapyDevice = session.morning?.sleepTherapyDevice ?? ""
            let sleepTherapyCompliance = session.morning?.sleepTherapyCompliance.map(String.init) ?? ""
            let firstNightOffAfterWorkBlock = (session.context?.firstNightOffAfterWorkBlock == true || session.morning?.firstNightOffAfterWorkBlock == true) ? "true" : "false"
            let sleepDisorders = (session.morning?.sleepDisorders ?? []).joined(separator: "; ")
            let sleepDisorderNotes = redact(session.morning?.sleepDisorderNotes, redaction: redaction)
            let coMedicationNotes = redact(session.morning?.coMedicationNotes, redaction: redaction)
            let pharmacogenomicFastMetabolizer = (session.morning?.pharmacogenomicFastMetabolizer ?? false) ? "true" : "false"
            let pharmacogenomicClinicianReviewed = (session.morning?.pharmacogenomicClinicianReviewed ?? false) ? "true" : "false"
            let pharmacogenomicNotes = redact(session.morning?.pharmacogenomicNotes, redaction: redaction)
            let lateMealType = session.context?.lateMealType ?? ""
            let lateMealToDose1 = session.context?.lateMealMinutesBeforeDose1.map(String.init) ?? ""
            let caffeineToDose1 = session.context?.caffeineMinutesBeforeDose1.map(String.init) ?? ""
            let alcoholToDose1 = session.context?.alcoholMinutesBeforeDose1.map(String.init) ?? ""
            let exerciseToDose1 = session.context?.exerciseMinutesBeforeDose1.map(String.init) ?? ""
            let screenToDose1 = session.context?.screenMinutesBeforeDose1.map(String.init) ?? ""
            let scheduleMarkers = session.context?.scheduleMarkers.joined(separator: "; ") ?? ""
            let comparableCohortKey = session.comparableCohortKey
            let confidenceBucket = session.classification.confidenceBucket.rawValue
            let trainingEligible = session.countsTowardRecommendationTraining ? "true" : "false"
            let qualityFlags = session.qualityFlags.joined(separator: "; ")
            let exportExclusionReasons = session.exportExclusionReasons.joined(separator: "; ")
            let metricProvenance = session.metricProvenance.map { "\($0.key):\($0.value)" }.sorted().joined(separator: "; ")
            let notes = redact(session.notes, redaction: redaction)

            let values = [
                sessionDate,
                dose1UTC,
                dose2UTC,
                dose2Skipped,
                intervalMinutes,
                eventCount,
                preSleepStress,
                morningSleepQuality,
                morningReadiness,
                medicationCount,
                totalSleepMinutes,
                sleepEfficiency,
                sleepPerformance,
                sleepConsistency,
                whoopRecovery,
                averageHeartRate,
                hrvMs,
                wakeDisruptionCount,
                awakeMinutes,
                wasoMinutes,
                inBedMinutes,
                coreSleepMinutes,
                deepSleepMinutes,
                remSleepMinutes,
                lightSleepMinutes,
                spo2Percentage,
                skinTempCelsius,
                nextMorningWeekday,
                wakeSignal,
                scheduleDayType,
                explicitNightType,
                explicitNextDayDemand,
                explicitDose2WakeMethod,
                explicitBackToSleepDuration,
                wakeRequirement,
                shiftStartUTC,
                shiftEndUTC,
                nextRequiredWakeUTC,
                commuteMinutes,
                alarmScheduledForUTC,
                alarmFirstFireUTC,
                alarmAcknowledgedUTC,
                alarmAcknowledgementAction,
                followUpDeliveredCount,
                dose2TakenSource,
                dose2LiveTakenReason,
                dose2MorningTakenReason,
                dose2TakenReason,
                dose2TakenReasonNotes,
                dose2LiveSkipReason,
                dose2MorningSkipReason,
                dose2SkipReason,
                dose2SkipReasonNotes,
                dose2SkipSource,
                dose2ReasonMismatch,
                dose2TakenEarly,
                dose2TakenLate,
                dose2HasExtraDose,
                drivingConfidence,
                daytimeSleepiness,
                cataplexyBurden,
                painBurden,
                anxietyBurden,
                congestionBurden,
                refluxBurden,
                restlessLegsBurden,
                bathroomUrgencyBurden,
                sleepTherapyDevice,
                sleepTherapyCompliance,
                firstNightOffAfterWorkBlock,
                sleepDisorders,
                sleepDisorderNotes,
                coMedicationNotes,
                pharmacogenomicFastMetabolizer,
                pharmacogenomicClinicianReviewed,
                pharmacogenomicNotes,
                lateMealType,
                lateMealToDose1,
                caffeineToDose1,
                alcoholToDose1,
                exerciseToDose1,
                screenToDose1,
                scheduleMarkers,
                comparableCohortKey,
                confidenceBucket,
                trainingEligible,
                qualityFlags,
                exportExclusionReasons,
                metricProvenance,
                notes
            ]
            rows.append(values.map(csvField).joined(separator: ","))
        }

        return ([
            "session_date,dose1_utc,dose2_utc,dose2_skipped,interval_minutes,event_count,pre_sleep_stress,morning_sleep_quality,morning_readiness,medication_count,total_sleep_minutes,sleep_efficiency,sleep_performance,sleep_consistency,whoop_recovery,avg_hr,hrv_ms,wake_disruption_count,awake_minutes,waso_minutes,in_bed_minutes,core_sleep_minutes,deep_sleep_minutes,rem_sleep_minutes,light_sleep_minutes,spo2_percentage,skin_temp_celsius,next_morning_weekday,wake_signal,schedule_day_type,explicit_night_type,explicit_next_day_demand,explicit_dose2_wake_method,explicit_back_to_sleep_duration,wake_requirement,shift_start_utc,shift_end_utc,next_required_wake_utc,commute_minutes,alarm_scheduled_for_utc,alarm_first_fire_utc,alarm_acknowledged_utc,alarm_ack_action,alarm_followup_delivered_count,dose2_taken_source,dose2_live_taken_reason,dose2_morning_taken_reason,dose2_taken_reason,dose2_taken_reason_notes,dose2_live_skip_reason,dose2_morning_skip_reason,dose2_skip_reason,dose2_skip_reason_notes,dose2_skip_source,dose2_reason_mismatch,dose2_taken_early,dose2_taken_late,dose2_has_extra_dose,driving_confidence,daytime_sleepiness,cataplexy_burden,pain_burden,anxiety_burden,congestion_burden,reflux_burden,restless_legs_burden,bathroom_urgency_burden,sleep_therapy_device,sleep_therapy_compliance,first_night_off_after_work_block,sleep_disorders,sleep_disorder_notes,co_medication_notes,pharmacogenomic_fast_metabolizer,pharmacogenomic_clinician_reviewed,pharmacogenomic_notes,late_meal_type,late_meal_to_dose1_min,caffeine_to_dose1_min,alcohol_to_dose1_min,exercise_to_dose1_min,screen_to_dose1_min,schedule_markers,comparable_cohort_key,confidence_bucket,training_eligible,quality_flags,export_exclusion_reasons,metric_provenance,notes"
        ] + rows).joined(separator: "\n") + "\n"
    }

    func buildMetricFactsCSV(sessions: [InsightSession]) -> String {
        buildMetricFactsCSV(sessions: sessions, redaction: .none)
    }

    func buildMetricFactsCSV(
        sessions: [InsightSession],
        redaction: InsightExportRedactionOptions
    ) -> String {
        var rows: [String] = []

        for session in sessions {
            for fact in session.normalizedFacts {
                let values = [
                    session.sessionDate,
                    fact.category.rawValue,
                    fact.key,
                    fact.title,
                    fact.displayValue,
                    fact.numericValue.map { String(format: "%.4f", $0) } ?? "",
                    fact.unit ?? "",
                    fact.source,
                    session.comparableCohortKey,
                    session.classification.confidenceBucket.rawValue,
                    session.countsTowardRecommendationTraining ? "true" : "false"
                ]
                rows.append(values.map(csvField).joined(separator: ","))
            }
        }

        return ([
            "session_date,category,metric_key,metric_title,display_value,numeric_value,unit,source,comparable_cohort_key,confidence_bucket,training_eligible"
        ] + rows).joined(separator: "\n") + "\n"
    }

    private func reportDateRange(for sessions: [InsightSession], formatter: DateFormatter) -> String {
        let dates = sessions.compactMap(\.startedAt)
        guard let earliest = dates.min(), let latest = dates.max() else {
            return "Unavailable"
        }
        return "\(formatter.string(from: earliest)) to \(formatter.string(from: latest))"
    }

    private func average(of values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private func average(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func formattedAverage(_ values: [Int], suffix: String) -> String {
        formattedAverage(average(of: values), suffix: suffix)
    }

    private func formattedAverage(_ values: [Double], suffix: String) -> String {
        formattedAverage(average(of: values), suffix: suffix)
    }

    private func formattedAverage(_ value: Double?, suffix: String) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%@", value, suffix)
    }

    private func formatted(_ value: Double?, decimals: Int) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(decimals)f", value)
    }

    private func formattedDuration(_ values: [Double]) -> String {
        guard let average = average(of: values) else { return "—" }
        let roundedMinutes = Int(average.rounded())
        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60
        return "\(hours)h \(minutes)m"
    }

    private func flagSummary(for session: InsightSession) -> String {
        if session.dose2Skipped {
            return "Dose 2 skipped"
        }
        if session.isLateDose2 {
            return "Late Dose 2"
        }
        return session.qualityFlags.joined(separator: ", ")
    }

    private func iso8601(_ date: Date?, redaction: InsightExportRedactionOptions = .none) -> String {
        if redaction.redactExactTimestamps {
            return ""
        }
        guard let date else { return "" }
        return Self.isoFormatter.string(from: date)
    }

    private func appendBundleMetadata(
        into lines: inout [String],
        bundle: InsightBundle?,
        redaction: InsightExportRedactionOptions
    ) {
        guard let metadata = bundle?.importMetadata else { return }

        lines.append("Bundle provenance")
        lines.append("Imported bundle: \(redaction.redactBundleFingerprint ? "redacted" : metadata.fileName)")
        lines.append("Bundle size: \(metadata.byteCount) bytes")
        lines.append("Bundle SHA-256: \(redaction.redactBundleFingerprint ? "redacted" : metadata.sha256Hex)")
        lines.append("Imported into Studio: \(DateFormatter.localizedString(from: metadata.importedAtUTC, dateStyle: .medium, timeStyle: .short))")

        if let exportVersion = bundle?.exportVersion {
            lines.append("Bundle export version: \(exportVersion)")
        }

        if let exportWarnings = bundle?.exportWarnings, !exportWarnings.isEmpty {
            lines.append("Bundle warnings: \(exportWarnings.joined(separator: " | "))")
        }

        lines.append("")
    }

    private func redact(_ value: String?, redaction: InsightExportRedactionOptions) -> String {
        guard let value else { return "" }
        guard redaction.redactFreeText else { return value }
        return value.isEmpty ? "" : "[redacted]"
    }

    private func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
