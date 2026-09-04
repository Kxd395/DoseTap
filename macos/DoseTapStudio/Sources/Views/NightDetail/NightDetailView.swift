import SwiftUI

struct NightDetailView: View {
    let session: InsightSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summaryCards
                supplementalCards
                eventListCard
            }
            .padding()
        }
        .navigationTitle(session.sessionDate)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.sessionDate)
                .font(.title.bold())
            Text(detailSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let notes = session.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCards: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 140)),
                GridItem(.flexible(minimum: 140)),
                GridItem(.flexible(minimum: 140)),
                GridItem(.flexible(minimum: 140))
            ],
            spacing: 12
        ) {
            metricCard(title: "Dose 1", value: timeText(session.dose1Time), accent: .blue)
            metricCard(title: "Dose 2", value: session.dose2Skipped ? "Skipped" : timeText(session.dose2Time), accent: session.dose2Skipped ? .red : .green)
            metricCard(title: "Interval", value: session.intervalMinutes.map { "\($0)m" } ?? "—", accent: session.isLateDose2 ? .orange : .primary)
            metricCard(title: "Events", value: "\(session.eventCount)", accent: .purple)
            metricCard(title: "Meds", value: "\(session.medicationCount)", accent: .pink)
            metricCard(title: "Snoozes", value: "\(session.snoozeCount)", accent: .orange)
            metricCard(title: "Bathroom", value: "\(session.bathroomCount)", accent: .cyan)
            metricCard(title: "Quality", value: session.qualityFlags.isEmpty ? "Clean" : "Flags", accent: session.qualityFlags.isEmpty ? .green : .orange)
            metricCard(title: "Completeness", value: "\(Int(session.completenessScore * 100))%", accent: .indigo)
        }
    }

    @ViewBuilder
    private var supplementalCards: some View {
        if session.hasSupplementalContext {
            VStack(alignment: .leading, spacing: 12) {
                if let preSleep = session.preSleep {
                    supplementalCard(title: "Pre-Sleep") {
                        detailRow("Stress", preSleep.stressLevel.map(String.init) ?? "—")
                        detailRow("Pain", preSleep.bodyPain ?? "—")
                        detailRow("Later reason", preSleep.laterReason ?? "—")
                        detailRow("Late meal", preSleep.lateMeal ?? "—")
                        detailRow("Late meal ended", timeText(preSleep.lateMealEndedAtUTC))
                        detailRow("Caffeine sources", joinedText(preSleep.caffeineSources))
                        detailRow("Caffeine last intake", timeText(preSleep.caffeineLastIntakeAtUTC))
                        detailRow("Alcohol last drink", timeText(preSleep.alcoholLastDrinkAtUTC))
                        detailRow("Exercise last", timeText(preSleep.exerciseLastAtUTC))
                        detailRow("Screens last used", timeText(preSleep.screensLastUsedAtUTC))
                        detailRow("Sleep aids", joinedText(preSleep.sleepAids))
                        if let notes = preSleep.notes, !notes.isEmpty {
                            detailRow("Notes", notes)
                        }
                    }
                }

                if let context = session.context {
                    supplementalCard(title: "Night Context") {
                        detailRow("Next morning", session.nextMorningWeekdayLabel ?? "—")
                        detailRow("Scheduled wake", timeText(context.scheduledWakeByUTC))
                        detailRow("Schedule type", context.scheduleDayType ?? "—")
                        detailRow("Night type", session.explicitNightTypeLabel ?? "—")
                        detailRow("First night off after work block", context.firstNightOffAfterWorkBlock ? "Yes" : "No")
                        detailRow("Wake signal", session.wakeSignalLabel)
                        detailRow("Next-day demand", session.explicitNextDayDemandLabel ?? "—")
                        detailRow("Dose 2 wake method", session.explicitDose2WakeMethodLabel ?? "—")
                        detailRow("Back to sleep after Dose 2", session.explicitBackToSleepDurationLabel ?? "—")
                        detailRow("Wake requirement", context.wakeRequirement ?? "—")
                        detailRow("Shift start", timeText(context.shiftStartAtUTC))
                        detailRow("Shift end", timeText(context.shiftEndAtUTC))
                        detailRow("Next required wake", timeText(context.nextRequiredWakeAtUTC))
                        detailRow("Commute burden", timingText(context.commuteMinutes))
                        detailRow("Alarm scheduled for", timeText(context.alarm?.scheduledForUTC))
                        detailRow("Alarm first fire", timeText(context.alarm?.firstFireAtUTC))
                        detailRow("Alarm acknowledged", timeText(context.alarm?.acknowledgedAtUTC))
                        detailRow("Alarm action", session.alarmAcknowledgementActionLabel ?? "—")
                        detailRow("Follow-up alarms delivered", "\(context.alarm?.followUpDeliveredCount ?? 0)")
                        detailRow("Wake final logged", timeText(context.wakeFinalLoggedAtUTC))
                        detailRow("Snoozes used", "\(context.snoozeCount)")
                        detailRow("Dose 2 source", session.dose2TakenSourceLabel ?? "—")
                        detailRow("Dose 2 early / late", dose2TimingFlagText(context.dose2Outcome))
                        detailRow("Dose 2 reason mismatch", session.hasDose2ReasonMismatch ? "Yes" : "No")
                        detailRow("Dose 2 taken reason", session.dose2TakenReasonLabel ?? "—")
                        detailRow("Dose 2 live taken reason", labelOrDash(context.dose2Outcome?.liveTakenReason, session.dose2TakenReasonLabel))
                        detailRow("Dose 2 morning taken reason", labelOrDash(context.dose2Outcome?.morningTakenReason, session.dose2TakenReasonLabel))
                        detailRow("Dose 2 taken reason notes", context.dose2Outcome?.takenReasonNotes ?? "—")
                        detailRow("Dose 2 skip reason", session.dose2SkipReasonLabel ?? "—")
                        detailRow("Dose 2 live skip reason", labelOrDash(context.dose2Outcome?.liveSkipReason, session.dose2SkipReasonLabel))
                        detailRow("Dose 2 morning skip reason", labelOrDash(context.dose2Outcome?.morningSkipReason, session.dose2SkipReasonLabel))
                        detailRow("Dose 2 skip reason notes", context.dose2Outcome?.skipReasonNotes ?? "—")
                        detailRow("Dose 2 skip source", session.dose2SkipSourceLabel ?? "—")
                        detailRow("Schedule markers", joinedText(context.scheduleMarkers))
                        detailRow("Late meal type", context.lateMealType ?? "—")
                        detailRow("Late meal -> Dose 1", timingText(context.lateMealMinutesBeforeDose1))
                        detailRow("Late meal -> Dose 2", timingText(context.lateMealMinutesBeforeDose2))
                        detailRow("Caffeine -> Dose 1", timingText(context.caffeineMinutesBeforeDose1))
                        detailRow("Alcohol -> Dose 1", timingText(context.alcoholMinutesBeforeDose1))
                        detailRow("Exercise -> Dose 1", timingText(context.exerciseMinutesBeforeDose1))
                        detailRow("Nap -> Dose 1", timingText(context.napMinutesBeforeDose1))
                        detailRow("Screen use -> Dose 1", timingText(context.screenMinutesBeforeDose1))
                    }
                }

                supplementalCard(title: "Classification") {
                    detailRow("Comparable cohort", session.comparableCohortKey)
                    detailRow("Confidence", session.classification.confidenceBucket.label)
                    detailRow("Trainable night", session.countsTowardRecommendationTraining ? "Yes" : "No")
                    detailRow("Tags", joinedText(session.classification.tags.map(\.label)))
                    detailRow("Bundle exclusions", joinedText(session.exportExclusionReasons))
                    detailRow("Exclusions", joinedText(session.classification.exclusionReasons))
                }

                supplementalCard(title: "Data Sources") {
                    detailRow("Available sources", joinedText(session.sourceAvailabilitySummary))
                    detailRow("Raw event count", "\(session.rawEvents.count)")
                    detailRow("Normalized event count", "\(session.normalizedEvents.count)")
                    detailRow("Bundle quality flags", joinedText(session.dataQualityFlags))
                    detailRow("Metric provenance", joinedText(session.metricProvenance.map { "\($0.key): \($0.value)" }.sorted()))
                }

                if !session.normalizedFacts.isEmpty {
                    supplementalCard(title: "Metric Facts") {
                        ForEach(InsightMetricFactCategory.allCases, id: \.self) { category in
                            let facts = session.normalizedFacts.filter { $0.category == category }
                            if !facts.isEmpty {
                                Text(category.label)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.top, category == .dosing ? 0 : 8)
                                ForEach(facts) { fact in
                                    detailRow("\(fact.title) [\(fact.source)]", fact.displayValue)
                                }
                            }
                        }
                    }
                }

                if let morning = session.morning {
                    supplementalCard(title: "Morning Check-In") {
                        detailRow("Sleep quality", "\(morning.sleepQuality)/5")
                        detailRow("Rested", morning.feelRested)
                        detailRow("Grogginess", morning.grogginess)
                        detailRow("Mental clarity", "\(morning.mentalClarity)/5")
                        detailRow("Mood", morning.mood)
                        detailRow("Readiness", "\(morning.readinessForDay)/5")
                        detailRow("Driving confidence", morning.drivingConfidence.map { "\($0)/5" } ?? "—")
                        detailRow("Daytime sleepiness", morning.daytimeSleepiness.map { "\($0)/5" } ?? "—")
                        detailRow("Cataplexy burden", morning.cataplexyBurden ?? "—")
                        detailRow("Pain burden", morning.painBurden ?? "—")
                        detailRow("Anxiety burden", morning.anxietyBurden ?? morning.anxietyLevel)
                        detailRow("Congestion burden", morning.congestionBurden ?? "—")
                        detailRow("Reflux burden", morning.refluxBurden ?? "—")
                        detailRow("Restless legs burden", morning.restlessLegsBurden ?? "—")
                        detailRow("Bathroom urgency burden", morning.bathroomUrgencyBurden ?? "—")
                        detailRow("Sleep therapy device", morning.sleepTherapyDevice ?? "—")
                        detailRow("Sleep therapy compliance", morning.sleepTherapyCompliance.map { "\($0)%" } ?? "—")
                        detailRow("First night off after work block", (morning.firstNightOffAfterWorkBlock ?? false) ? "Yes" : "No")
                        detailRow("Sleep disorders", joinedText(morning.sleepDisorders ?? []))
                        detailRow("Sleep disorder notes", morning.sleepDisorderNotes ?? "—")
                        detailRow("Co-medication notes", morning.coMedicationNotes ?? "—")
                        detailRow("Fast-metabolizer flag", (morning.pharmacogenomicFastMetabolizer ?? false) ? "Yes" : "No")
                        detailRow("Genetics clinician-reviewed", (morning.pharmacogenomicClinicianReviewed ?? false) ? "Yes" : "No")
                        detailRow("Genetics notes", morning.pharmacogenomicNotes ?? "—")
                        if let notes = morning.notes, !notes.isEmpty {
                            detailRow("Notes", notes)
                        }
                    }
                }

                if !rawCheckInPayloadRows.isEmpty {
                    supplementalCard(title: "Raw Check-In Payloads") {
                        ForEach(Array(rawCheckInPayloadRows.enumerated()), id: \.offset) { _, row in
                            rawPayloadBlock(title: row.title, payload: row.payload)
                        }
                    }
                }

                if !session.medications.isEmpty {
                    supplementalCard(title: "Other Medications") {
                        ForEach(session.medications) { medication in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(medication.medicationId) \(medication.doseMg)\(medication.doseUnit)")
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(medication.formulation.uppercased()) • \(medication.takenAtUTC.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let notes = medication.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            if medication.id != session.medications.last?.id {
                                Divider()
                            }
                        }
                    }
                }

                if let healthKit = session.healthKit {
                    supplementalCard(title: "Apple Health") {
                        detailRow("Total sleep", durationText(minutes: healthKit.totalSleepMinutes))
                        detailRow("Time to first wake", minutesText(healthKit.ttfwMinutes))
                        detailRow("Wake count", "\(healthKit.wakeCount)")
                        detailRow("Awake minutes", minutesText(healthKit.awakeMinutes))
                        detailRow("WASO", minutesText(healthKit.wakeAfterSleepOnsetMinutes))
                        detailRow("In bed", minutesText(healthKit.inBedMinutes))
                        detailRow("Core / Deep / REM", "\(minutesLabel(healthKit.coreSleepMinutes)) / \(minutesLabel(healthKit.deepSleepMinutes)) / \(minutesLabel(healthKit.remSleepMinutes))")
                        detailRow("Sleep onset", timeText(healthKit.sleepOnsetUTC))
                        detailRow("Final wake", timeText(healthKit.finalWakeUTC))
                        detailRow("Avg heart rate", rateText(healthKit.averageHeartRate, unit: "bpm"))
                        detailRow("Respiratory rate", rateText(healthKit.respiratoryRate, unit: "br/min"))
                        detailRow("HRV", rateText(healthKit.hrvMs, unit: "ms"))
                        detailRow("Resting HR", rateText(healthKit.restingHeartRate, unit: "bpm"))
                        detailRow("Sources", joinedText(healthKit.sources))
                    }
                }

                if let whoop = session.whoop {
                    supplementalCard(title: "WHOOP") {
                        detailRow("Recovery", percentText(whoop.recoveryScore))
                        detailRow("Sleep efficiency", percentText(whoop.sleepEfficiency))
                        detailRow("Sleep performance", percentText(whoop.sleepPerformance))
                        detailRow("Sleep consistency", percentText(whoop.sleepConsistency))
                        detailRow("Total sleep", durationText(minutes: Double(whoop.totalSleepMinutes)))
                        detailRow("In bed", whoop.inBedMinutes.map { "\($0)m" } ?? "—")
                        detailRow("Deep / REM / Light", "\(whoop.deepMinutes)m / \(whoop.remMinutes)m / \(whoop.lightMinutes)m")
                        detailRow("Awake", "\(whoop.awakeMinutes)m")
                        detailRow("Disturbances", "\(whoop.disturbanceCount)")
                        detailRow("Respiratory rate", rateText(whoop.respiratoryRate, unit: "br/min"))
                        detailRow("HRV", rateText(whoop.hrvMs, unit: "ms"))
                        detailRow("Resting HR", rateText(whoop.restingHeartRate, unit: "bpm"))
                        detailRow("SpO2", percentText(whoop.spo2Percentage))
                        detailRow("Skin temp", rateText(whoop.skinTempCelsius, unit: "°C"))
                        detailRow("Sleep need baseline / debt / strain / nap", "\(minutesLabel(whoop.sleepNeedBaselineMinutes.map(Double.init))) / \(minutesLabel(whoop.sleepNeedDebtMinutes.map(Double.init))) / \(minutesLabel(whoop.sleepNeedStrainMinutes.map(Double.init))) / \(minutesLabel(whoop.sleepNeedNapMinutes.map(Double.init)))")
                    }
                }
            }
        }
    }

    private var eventListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Night Events")
                .font(.headline)

            if session.events.isEmpty {
                Text("No events imported for this night.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(session.events) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(color(for: event))
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(label(for: event))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let details = event.details, !details.isEmpty {
                                Text(details)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    if event.id != session.events.last?.id {
                        Divider()
                    }
                }
            }

            if !session.qualityFlags.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quality Flags")
                        .font(.headline)
                    ForEach(session.qualityFlags, id: \.self) { flag in
                        Label(flag, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var detailSubtitle: String {
        if session.dose2Skipped {
            return "Dose 2 was skipped"
        }
        if session.isLateDose2 {
            return "Late Dose 2 night"
        }
        if session.isOnTimeDose2 {
            return "On-time dosing night"
        }
        return session.qualitySummary
    }

    private var rawCheckInPayloadRows: [(title: String, payload: String)] {
        var rows: [(title: String, payload: String)] = []

        appendRawPayload(&rows, title: "Pre-sleep raw answers", payload: session.preSleep?.rawAnswersJson)

        if let morning = session.morning {
            appendRawPayload(&rows, title: "Morning physical symptoms", payload: morning.rawPhysicalSymptomsJson)
            appendRawPayload(&rows, title: "Morning respiratory symptoms", payload: morning.rawRespiratorySymptomsJson)
            appendRawPayload(&rows, title: "Morning sleep therapy", payload: morning.rawSleepTherapyJson)
            appendRawPayload(&rows, title: "Morning sleep environment", payload: morning.rawSleepEnvironmentJson)
            appendRawPayload(&rows, title: "Morning stress context", payload: morning.rawStressContextJson)
            appendRawPayload(&rows, title: "Morning timing context", payload: morning.rawTimingContextJson)
        }

        for submission in session.checkInSubmissions.sorted(by: { $0.submittedAtUTC < $1.submittedAtUTC }) {
            appendRawPayload(
                &rows,
                title: "\(submission.checkInType) submission \(timeText(Optional(submission.submittedAtUTC)))",
                payload: submission.responsesJson
            )
        }

        return rows
    }

    private func appendRawPayload(
        _ rows: inout [(title: String, payload: String)],
        title: String,
        payload: String?
    ) {
        let trimmed = payload?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        rows.append((title, trimmed))
    }

    private func dose2TimingFlagText(_ outcome: InsightDose2OutcomeContext?) -> String {
        guard let outcome else { return "—" }
        if outcome.takenEarly && outcome.takenLate {
            return "Early + Late flags"
        }
        if outcome.takenEarly {
            return "Early"
        }
        if outcome.takenLate {
            return "Late"
        }
        if outcome.hasExtraDose {
            return "Extra dose recorded"
        }
        return "None"
    }

    private func metricCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.bold())
                .foregroundColor(accent)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func supplementalCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func rawPayloadBlock(title: String, payload: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(rawPayloadPreview(payload))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .lineLimit(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func rawPayloadPreview(_ payload: String) -> String {
        let maxLength = 4_000
        guard payload.count > maxLength else {
            return payload
        }
        return "\(payload.prefix(maxLength))\n... truncated in view ..."
    }

    private func joinedText(_ values: [String]) -> String {
        values.isEmpty ? "—" : values.joined(separator: ", ")
    }

    private func labelOrDash(_ rawValue: String?, _ fallbackLabel: String?) -> String {
        rawValue ?? fallbackLabel ?? "—"
    }

    private func durationText(minutes: Double) -> String {
        let roundedMinutes = Int(minutes.rounded())
        let hours = roundedMinutes / 60
        let remainder = roundedMinutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    private func minutesText(_ minutes: Double?) -> String {
        guard let minutes else { return "—" }
        return "\(Int(minutes.rounded()))m"
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private func minutesLabel(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))m"
    }

    private func timingText(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }
        return "\(minutes)m"
    }

    private func rateText(_ value: Double?, unit: String) -> String {
        guard let value else { return "—" }
        let formatted = value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
        return "\(formatted) \(unit)"
    }

    private func label(for event: InsightEvent) -> String {
        switch event.type {
        case .dose1_taken:
            return "Dose 1"
        case .dose2_taken:
            return "Dose 2"
        case .dose2_skipped:
            return "Dose 2 Skipped"
        case .dose2_snoozed, .snooze:
            return "Snooze"
        case .bathroom:
            return "Bathroom"
        case .lights_out:
            return "Lights Out"
        case .wake_final:
            return "Wake Final"
        case .undo:
            return "Undo"
        case .app_opened:
            return "App Opened"
        case .notification_received:
            return "Notification Received"
        }
    }

    private func color(for event: InsightEvent) -> Color {
        switch event.kind {
        case .dose1:
            return .blue
        case .dose2:
            return .green
        case .dose2Skipped:
            return .red
        case .snooze:
            return .orange
        case .other:
            return .secondary
        }
    }

    private func timeText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    let sample = InsightSession(
        id: "2024-09-07",
        sessionDate: "2024-09-07",
        startedAt: Date(),
        endedAt: Date().addingTimeInterval(260 * 60),
        dose1Time: Date(),
        dose2Time: Date().addingTimeInterval(260 * 60),
        dose2Skipped: false,
        snoozeCount: 1,
        adherenceFlag: "late",
        sleepEfficiency: 84,
        whoopRecovery: 72,
        averageHeartRate: 64,
        notes: "Sample late night",
        events: [
            InsightEvent(id: UUID(), type: .dose1_taken, kind: .dose1, timestamp: Date(), details: nil),
            InsightEvent(id: UUID(), type: .bathroom, kind: .other, timestamp: Date().addingTimeInterval(90 * 60), details: "Brief wake"),
            InsightEvent(id: UUID(), type: .dose2_taken, kind: .dose2, timestamp: Date().addingTimeInterval(260 * 60), details: nil)
        ],
        preSleep: InsightPreSleepSummary(
            sessionId: "sample",
            completionState: "complete",
            loggedAtUTC: "2024-09-07T19:45:00Z",
            stressLevel: 3,
            stressDrivers: ["schedule"],
            laterReason: "late_meal",
            bodyPain: "mild",
            caffeineSources: [],
            alcohol: "none",
            exercise: "light",
            napToday: "no",
            lateMeal: "yes",
            screensInBed: "yes",
            roomTemp: "cool",
            noiseLevel: "quiet",
            sleepAids: ["magnesium"],
            notes: "Screen time ran late."
        ),
        morning: InsightMorningSummary(
            submittedAtUTC: Date(),
            sleepQuality: 4,
            feelRested: "mostly",
            grogginess: "mild",
            sleepInertiaDuration: "fiveToFifteen",
            dreamRecall: "some",
            mentalClarity: 4,
            mood: "steady",
            anxietyLevel: "low",
            stressLevel: 2,
            stressDrivers: [],
            readinessForDay: 4,
            hadSleepParalysis: false,
            hadHallucinations: false,
            hadAutomaticBehavior: false,
            fellOutOfBed: false,
            hadConfusionOnWaking: false,
            notes: "Felt decent."
        ),
        medications: [
            InsightMedicationSummary(
                id: "med-1",
                medicationId: "adderall",
                doseMg: 10,
                doseUnit: "mg",
                formulation: "ir",
                takenAtUTC: Date().addingTimeInterval(9 * 60 * 60),
                notes: nil
            )
        ]
    )
    return NightDetailView(session: sample)
}
