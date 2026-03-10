import Foundation
import SwiftUI
import DoseCore

// MARK: - Export Card
struct ExportCard: View {
    let sessionKey: String
    @ObservedObject private var sessionRepo = SessionRepository.shared
    @State private var showingShareSheet = false
    @State private var exportContent: String = ""

    private var doseLog: StoredDoseLog? {
        sessionRepo.fetchDoseLog(forSession: sessionKey)
    }

    private var preSleepLog: StoredPreSleepLog? {
        sessionRepo.fetchMostRecentPreSleepLog(sessionId: sessionKey)
    }

    private var morningCheckIn: StoredMorningCheckIn? {
        sessionRepo.fetchMorningCheckIn(for: sessionKey)
    }

    private var sleepEvents: [StoredSleepEvent] {
        sessionRepo.fetchSleepEventsLocal(for: sessionKey).sorted { $0.timestamp < $1.timestamp }
    }

    private var medicationEntries: [MedicationEntry] {
        sessionRepo.listMedicationEntries(for: sessionKey).sorted { $0.takenAtUTC < $1.takenAtUTC }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📤 Export")
                .font(.headline)

            Text("Export this night's data for your sleep specialist or personal records.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button {
                    exportContent = generateExportContent(format: .text)
                    showingShareSheet = true
                } label: {
                    Label("Share Report", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    exportContent = generateExportContent(format: .csv)
                    showingShareSheet = true
                } label: {
                    Label("CSV", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .sheet(isPresented: $showingShareSheet) {
            ActivityViewController(activityItems: [exportContent])
        }
    }

    enum ExportFormat { case text, csv }

    private func generateExportContent(format: ExportFormat) -> String {
        switch format {
        case .text:
            return generateTextExport()
        case .csv:
            return generateCSVExport()
        }
    }

    private func generateTextExport() -> String {
        var lines: [String] = [
            "DoseTap Night Report",
            "Session: \(sessionDateLabel)",
            "Session Key: \(sessionKey)",
            "Generated: \(AppFormatters.mediumDateTime.string(from: Date()))"
        ]

        lines.append("")
        lines.append("Dose Timing")
        if let doseLog {
            appendTextField(&lines, label: "Dose 1", value: formatTime(doseLog.dose1Time))
            appendTextField(&lines, label: "Dose 2", value: doseLog.dose2Skipped ? "Skipped" : formatOptionalTime(doseLog.dose2Time))
            appendTextField(&lines, label: "Dose 2 Skipped", value: formatBoolean(doseLog.dose2Skipped))
            appendTextField(&lines, label: "Interval", value: doseLog.intervalMinutes.map(formatInterval))
            appendTextField(&lines, label: "Snooze Count", value: "\(doseLog.snoozeCount)")
        } else {
            lines.append("- No dose log recorded")
        }

        lines.append("")
        lines.append("Pre-Sleep Log")
        if let log = preSleepLog {
            appendTextField(&lines, label: "Status", value: log.completionState == "skipped" ? "Skipped" : "Completed")
            appendTextField(&lines, label: "Logged At", value: formatStoredTimestamp(log.createdAtUtc))

            if let answers = log.answers, log.completionState != "skipped" {
                appendTextField(&lines, label: "Intended Sleep Time", value: answers.intendedSleepTime?.displayText)
                if let stressLevel = answers.stressLevel {
                    appendTextField(&lines, label: "Stress Level", value: "\(formatStressLevel(stressLevel)) (\(stressLevel)/5)")
                }
                appendTextField(&lines, label: "Stress Driver", value: answers.primaryStressDriver?.displayText)
                if !answers.resolvedStressDrivers.isEmpty {
                    appendTextField(&lines, label: "Stress Drivers", value: answers.resolvedStressDrivers.map(\.displayText).joined(separator: ", "))
                }
                appendTextField(&lines, label: "Stress Progression", value: answers.stressProgression?.displayText)
                appendTextField(&lines, label: "Stress Notes", value: nonEmpty(answers.stressNotes))
                appendTextField(&lines, label: "Later Reason", value: answers.laterReason?.displayText)
                appendTextField(&lines, label: "Body Pain", value: answers.bodyPain?.displayText)

                if let painEntries = answers.painEntries, !painEntries.isEmpty {
                    for (index, entry) in painEntries.enumerated() {
                        appendTextField(&lines, label: "Pain Entry \(index + 1)", value: formatPainEntry(entry))
                    }
                }

                if let painLocations = answers.painLocations, !painLocations.isEmpty {
                    appendTextField(&lines, label: "Pain Locations", value: painLocations.map(\.displayText).joined(separator: ", "))
                }

                appendTextField(&lines, label: "Pain Type", value: answers.painType?.displayText)
                appendTextField(&lines, label: "Caffeine Sources", value: answers.caffeineSourceDisplayText ?? answers.stimulants?.displayText)
                appendTextField(&lines, label: "Caffeine Last Intake", value: answers.caffeineLastIntakeAt.map(formatTime))
                appendTextField(&lines, label: "Caffeine Last Amount", value: answers.caffeineLastAmountMg.map { "\($0) oz" })
                appendTextField(&lines, label: "Caffeine Daily Total", value: answers.caffeineDailyTotalMg.map { "\($0) oz" })
                appendTextField(&lines, label: "Alcohol", value: answers.alcohol?.displayText)
                appendTextField(&lines, label: "Alcohol Last Drink", value: answers.alcoholLastDrinkAt.map(formatTime))
                appendTextField(&lines, label: "Alcohol Last Amount", value: answers.alcoholLastAmountDrinks.map(formatDrinks))
                appendTextField(&lines, label: "Alcohol Daily Total", value: answers.alcoholDailyTotalDrinks.map(formatDrinks))
                appendTextField(&lines, label: "Exercise", value: answers.exercise?.displayText)
                appendTextField(&lines, label: "Exercise Type", value: answers.exerciseType?.displayText)
                appendTextField(&lines, label: "Exercise Last At", value: answers.exerciseLastAt.map(formatTime))
                appendTextField(&lines, label: "Exercise Duration", value: answers.exerciseDurationMinutes.map { "\($0) min" })
                appendTextField(&lines, label: "Nap Today", value: answers.napToday?.displayText)
                appendTextField(&lines, label: "Nap Count", value: answers.napCount.map { String($0) })
                appendTextField(&lines, label: "Nap Total Minutes", value: answers.napTotalMinutes.map { "\($0) min" })
                appendTextField(&lines, label: "Last Nap End", value: answers.napLastEndAt.map(formatTime))
                appendTextField(&lines, label: "Late Meal", value: answers.lateMeal?.displayText)
                appendTextField(&lines, label: "Late Meal Ended", value: answers.lateMealEndedAt.map(formatTime))
                appendTextField(&lines, label: "Screens In Bed", value: answers.screensInBed?.displayText)
                appendTextField(&lines, label: "Last Screen Use", value: answers.screensLastUsedAt.map(formatTime))
                appendTextField(&lines, label: "Room Temperature", value: answers.roomTemp?.displayText)
                appendTextField(&lines, label: "Noise Level", value: answers.noiseLevel?.displayText)
                appendTextField(&lines, label: "Sleep Aids", value: answers.sleepAidDisplayText ?? answers.sleepAids?.displayText)
                appendTextField(&lines, label: "Notes", value: nonEmpty(answers.notes))
            }
        } else {
            lines.append("- No pre-sleep log recorded")
        }

        lines.append("")
        lines.append("Medications")
        if medicationEntries.isEmpty {
            lines.append("- No medication entries logged")
        } else {
            for (index, entry) in medicationEntries.enumerated() {
                appendTextField(&lines, label: "Medication \(index + 1)", value: formattedMedicationEntry(entry))
            }
        }

        lines.append("")
        lines.append("Morning Check-In")
        if let checkIn = morningCheckIn {
            appendTextField(&lines, label: "Submitted At", value: AppFormatters.mediumDateTime.string(from: checkIn.timestamp))
            appendTextField(&lines, label: "Sleep Quality", value: "\(checkIn.sleepQuality)/5")
            appendTextField(&lines, label: "Feel Rested", value: humanize(checkIn.feelRested))
            appendTextField(&lines, label: "Grogginess", value: humanize(checkIn.grogginess))
            appendTextField(&lines, label: "Sleep Inertia", value: humanize(checkIn.sleepInertiaDuration))
            appendTextField(&lines, label: "Dream Recall", value: humanize(checkIn.dreamRecall))
            appendTextField(&lines, label: "Mental Clarity", value: "\(checkIn.mentalClarity)/5")
            appendTextField(&lines, label: "Mood", value: humanize(checkIn.mood))
            appendTextField(&lines, label: "Anxiety", value: humanize(checkIn.anxietyLevel))
            if let stressLevel = checkIn.stressLevel {
                appendTextField(&lines, label: "Stress Level", value: "\(formatStressLevel(stressLevel)) (\(stressLevel)/5)")
            }
            if !checkIn.resolvedStressDrivers.isEmpty {
                appendTextField(&lines, label: "Stress Drivers", value: checkIn.resolvedStressDrivers.map(\.displayText).joined(separator: ", "))
            }
            appendTextField(&lines, label: "Stress Progression", value: checkIn.stressProgression?.displayText)
            appendTextField(&lines, label: "Stress Notes", value: checkIn.stressNotes)
            appendTextField(&lines, label: "Readiness", value: "\(checkIn.readinessForDay)/5")

            let narcolepsySymptoms = formattedNarcolepsySymptoms(checkIn)
            appendTextField(&lines, label: "Narcolepsy Symptoms", value: narcolepsySymptoms.isEmpty ? "None" : narcolepsySymptoms.joined(separator: ", "))

            if checkIn.hasPhysicalSymptoms {
                let physical = jsonDictionary(from: checkIn.physicalSymptomsJson)
                appendTextField(&lines, label: "Physical Symptoms", value: "Yes")
                appendTextField(&lines, label: "Pain Severity", value: (physical["painSeverity"] as? Int).map { "\($0)/10" })
                appendTextField(&lines, label: "Pain Type", value: (physical["painType"] as? String).map(humanize))
                appendTextField(&lines, label: "Muscle Stiffness", value: (physical["muscleStiffness"] as? String).map(humanize))
                appendTextField(&lines, label: "Muscle Soreness", value: (physical["muscleSoreness"] as? String).map(humanize))
                appendTextField(&lines, label: "Headache", value: (physical["hasHeadache"] as? Bool).map(formatBoolean))
                appendTextField(&lines, label: "Headache Severity", value: (physical["headacheSeverity"] as? String).map(humanize))
                appendTextField(&lines, label: "Headache Location", value: (physical["headacheLocation"] as? String).map(humanize))

                let painEntries = formattedMorningPainEntries(from: physical)
                if !painEntries.isEmpty {
                    for (index, entry) in painEntries.enumerated() {
                        appendTextField(&lines, label: "Physical Pain Entry \(index + 1)", value: entry)
                    }
                } else if let painLocations = physical["painLocations"] as? [String], !painLocations.isEmpty {
                    appendTextField(&lines, label: "Pain Locations", value: painLocations.map(humanize).joined(separator: ", "))
                }

                appendTextField(&lines, label: "Physical Notes", value: nonEmpty(physical["notes"] as? String))
            } else {
                appendTextField(&lines, label: "Physical Symptoms", value: "No")
            }

            if checkIn.hasRespiratorySymptoms {
                let respiratory = jsonDictionary(from: checkIn.respiratorySymptomsJson)
                appendTextField(&lines, label: "Respiratory Symptoms", value: "Yes")
                appendTextField(&lines, label: "Congestion", value: (respiratory["congestion"] as? String).map(humanize))
                appendTextField(&lines, label: "Throat Condition", value: (respiratory["throatCondition"] as? String).map(humanize))
                appendTextField(&lines, label: "Cough Type", value: (respiratory["coughType"] as? String).map(humanize))
                appendTextField(&lines, label: "Sinus Pressure", value: (respiratory["sinusPressure"] as? String).map(humanize))
                appendTextField(&lines, label: "Feeling Feverish", value: (respiratory["feelingFeverish"] as? Bool).map(formatBoolean))
                appendTextField(&lines, label: "Sickness Level", value: (respiratory["sicknessLevel"] as? String).map(humanize))
                appendTextField(&lines, label: "Respiratory Notes", value: nonEmpty(respiratory["notes"] as? String))
            } else {
                appendTextField(&lines, label: "Respiratory Symptoms", value: "No")
            }

            if checkIn.usedSleepTherapy {
                let therapy = jsonDictionary(from: checkIn.sleepTherapyJson)
                appendTextField(&lines, label: "Sleep Therapy Used", value: "Yes")
                appendTextField(&lines, label: "Sleep Therapy Device", value: (therapy["device"] as? String).map(humanize))
                appendTextField(&lines, label: "Sleep Therapy Compliance", value: (therapy["compliance"] as? Int).map { "\($0)/10" })
                appendTextField(&lines, label: "Sleep Therapy Notes", value: nonEmpty(therapy["notes"] as? String))
            } else {
                appendTextField(&lines, label: "Sleep Therapy Used", value: "No")
            }

            appendTextField(&lines, label: "Notes", value: nonEmpty(checkIn.notes))
        } else {
            lines.append("- No morning check-in recorded")
        }

        lines.append("")
        lines.append("Sleep Events")
        if sleepEvents.isEmpty {
            lines.append("- No sleep events logged")
        } else {
            appendTextField(&lines, label: "Event Count", value: "\(sleepEvents.count)")
            for event in sleepEvents {
                appendTextField(&lines, label: formatTime(event.timestamp), value: formattedEventDetails(event))
            }
        }

        return lines.joined(separator: "\n")
    }

    private func generateCSVExport() -> String {
        var rows = ["session_key,session_date,section,field,value"]

        appendCSVRow(&rows, section: "meta", field: "generated_at", value: AppFormatters.mediumDateTime.string(from: Date()))
        appendCSVRow(&rows, section: "dose", field: "dose_1_time", value: doseLog.map { formatTime($0.dose1Time) })
        appendCSVRow(&rows, section: "dose", field: "dose_2_time", value: doseLog?.dose2Skipped == true ? "Skipped" : doseLog?.dose2Time.map(formatTime))
        appendCSVRow(&rows, section: "dose", field: "dose_2_skipped", value: doseLog.map { formatBoolean($0.dose2Skipped) })
        appendCSVRow(&rows, section: "dose", field: "interval", value: doseLog?.intervalMinutes.map(formatInterval))
        appendCSVRow(&rows, section: "dose", field: "snooze_count", value: doseLog.map { String($0.snoozeCount) })

        if let log = preSleepLog {
            appendCSVRow(&rows, section: "pre_sleep", field: "status", value: log.completionState == "skipped" ? "Skipped" : "Completed")
            appendCSVRow(&rows, section: "pre_sleep", field: "logged_at", value: formatStoredTimestamp(log.createdAtUtc))

            if let answers = log.answers, log.completionState != "skipped" {
                appendCSVRow(&rows, section: "pre_sleep", field: "intended_sleep_time", value: answers.intendedSleepTime?.displayText)
                if let stressLevel = answers.stressLevel {
                    appendCSVRow(&rows, section: "pre_sleep", field: "stress_level", value: "\(formatStressLevel(stressLevel)) (\(stressLevel)/5)")
                }
                appendCSVRow(&rows, section: "pre_sleep", field: "stress_driver", value: answers.primaryStressDriver?.displayText)
                if !answers.resolvedStressDrivers.isEmpty {
                    appendCSVRow(&rows, section: "pre_sleep", field: "stress_drivers", value: answers.resolvedStressDrivers.map(\.displayText).joined(separator: ", "))
                }
                appendCSVRow(&rows, section: "pre_sleep", field: "stress_progression", value: answers.stressProgression?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "stress_notes", value: nonEmpty(answers.stressNotes))
                appendCSVRow(&rows, section: "pre_sleep", field: "later_reason", value: answers.laterReason?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "body_pain", value: answers.bodyPain?.displayText)

                if let painEntries = answers.painEntries {
                    for (index, entry) in painEntries.enumerated() {
                        appendCSVRow(&rows, section: "pre_sleep", field: "pain_entry_\(index + 1)", value: formatPainEntry(entry))
                    }
                }

                if let painLocations = answers.painLocations, !painLocations.isEmpty {
                    appendCSVRow(&rows, section: "pre_sleep", field: "pain_locations", value: painLocations.map(\.displayText).joined(separator: ", "))
                }

                appendCSVRow(&rows, section: "pre_sleep", field: "pain_type", value: answers.painType?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "stimulants_summary", value: answers.stimulants?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "caffeine_sources", value: answers.caffeineSourceDisplayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "caffeine_last_intake", value: answers.caffeineLastIntakeAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "caffeine_last_amount_oz", value: answers.caffeineLastAmountMg.map { String($0) })
                appendCSVRow(&rows, section: "pre_sleep", field: "caffeine_daily_total_oz", value: answers.caffeineDailyTotalMg.map { String($0) })
                appendCSVRow(&rows, section: "pre_sleep", field: "alcohol", value: answers.alcohol?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "alcohol_last_drink", value: answers.alcoholLastDrinkAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "alcohol_last_amount", value: answers.alcoholLastAmountDrinks.map(formatDrinks))
                appendCSVRow(&rows, section: "pre_sleep", field: "alcohol_daily_total", value: answers.alcoholDailyTotalDrinks.map(formatDrinks))
                appendCSVRow(&rows, section: "pre_sleep", field: "exercise", value: answers.exercise?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "exercise_type", value: answers.exerciseType?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "exercise_last_at", value: answers.exerciseLastAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "exercise_duration_minutes", value: answers.exerciseDurationMinutes.map { String($0) })
                appendCSVRow(&rows, section: "pre_sleep", field: "nap_today", value: answers.napToday?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "nap_count", value: answers.napCount.map { String($0) })
                appendCSVRow(&rows, section: "pre_sleep", field: "nap_total_minutes", value: answers.napTotalMinutes.map { String($0) })
                appendCSVRow(&rows, section: "pre_sleep", field: "nap_last_end", value: answers.napLastEndAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "late_meal", value: answers.lateMeal?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "late_meal_ended", value: answers.lateMealEndedAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "screens_in_bed", value: answers.screensInBed?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "screens_last_used", value: answers.screensLastUsedAt.map(formatTime))
                appendCSVRow(&rows, section: "pre_sleep", field: "room_temp", value: answers.roomTemp?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "noise_level", value: answers.noiseLevel?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "sleep_aids", value: answers.sleepAidDisplayText ?? answers.sleepAids?.displayText)
                appendCSVRow(&rows, section: "pre_sleep", field: "notes", value: nonEmpty(answers.notes))
            }
        }

        if medicationEntries.isEmpty {
            appendCSVRow(&rows, section: "medication", field: "entries", value: "None")
        } else {
            for (index, entry) in medicationEntries.enumerated() {
                appendCSVRow(&rows, section: "medication", field: "entry_\(index + 1)", value: formattedMedicationEntry(entry))
            }
        }

        if let checkIn = morningCheckIn {
            appendCSVRow(&rows, section: "morning", field: "submitted_at", value: AppFormatters.mediumDateTime.string(from: checkIn.timestamp))
            appendCSVRow(&rows, section: "morning", field: "sleep_quality", value: "\(checkIn.sleepQuality)/5")
            appendCSVRow(&rows, section: "morning", field: "feel_rested", value: humanize(checkIn.feelRested))
            appendCSVRow(&rows, section: "morning", field: "grogginess", value: humanize(checkIn.grogginess))
            appendCSVRow(&rows, section: "morning", field: "sleep_inertia", value: humanize(checkIn.sleepInertiaDuration))
            appendCSVRow(&rows, section: "morning", field: "dream_recall", value: humanize(checkIn.dreamRecall))
            appendCSVRow(&rows, section: "morning", field: "mental_clarity", value: "\(checkIn.mentalClarity)/5")
            appendCSVRow(&rows, section: "morning", field: "mood", value: humanize(checkIn.mood))
            appendCSVRow(&rows, section: "morning", field: "anxiety", value: humanize(checkIn.anxietyLevel))
            if let stressLevel = checkIn.stressLevel {
                appendCSVRow(&rows, section: "morning", field: "stress_level", value: "\(formatStressLevel(stressLevel)) (\(stressLevel)/5)")
            }
            if !checkIn.resolvedStressDrivers.isEmpty {
                appendCSVRow(&rows, section: "morning", field: "stress_drivers", value: checkIn.resolvedStressDrivers.map(\.displayText).joined(separator: ", "))
            }
            appendCSVRow(&rows, section: "morning", field: "stress_progression", value: checkIn.stressProgression?.displayText)
            appendCSVRow(&rows, section: "morning", field: "stress_notes", value: checkIn.stressNotes)
            appendCSVRow(&rows, section: "morning", field: "readiness", value: "\(checkIn.readinessForDay)/5")

            let narcolepsySymptoms = formattedNarcolepsySymptoms(checkIn)
            appendCSVRow(&rows, section: "morning", field: "narcolepsy_symptoms", value: narcolepsySymptoms.isEmpty ? "None" : narcolepsySymptoms.joined(separator: ", "))

            if checkIn.hasPhysicalSymptoms {
                let physical = jsonDictionary(from: checkIn.physicalSymptomsJson)
                appendCSVRow(&rows, section: "morning", field: "physical_symptoms", value: "Yes")
                appendCSVRow(&rows, section: "morning", field: "pain_severity", value: (physical["painSeverity"] as? Int).map { "\($0)/10" })
                appendCSVRow(&rows, section: "morning", field: "pain_type", value: (physical["painType"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "muscle_stiffness", value: (physical["muscleStiffness"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "muscle_soreness", value: (physical["muscleSoreness"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "headache", value: (physical["hasHeadache"] as? Bool).map(formatBoolean))
                appendCSVRow(&rows, section: "morning", field: "headache_severity", value: (physical["headacheSeverity"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "headache_location", value: (physical["headacheLocation"] as? String).map(humanize))

                let painEntries = formattedMorningPainEntries(from: physical)
                for (index, entry) in painEntries.enumerated() {
                    appendCSVRow(&rows, section: "morning", field: "physical_pain_entry_\(index + 1)", value: entry)
                }

                if let painLocations = physical["painLocations"] as? [String], !painLocations.isEmpty {
                    appendCSVRow(&rows, section: "morning", field: "pain_locations", value: painLocations.map(humanize).joined(separator: ", "))
                }

                appendCSVRow(&rows, section: "morning", field: "physical_notes", value: nonEmpty(physical["notes"] as? String))
            } else {
                appendCSVRow(&rows, section: "morning", field: "physical_symptoms", value: "No")
            }

            if checkIn.hasRespiratorySymptoms {
                let respiratory = jsonDictionary(from: checkIn.respiratorySymptomsJson)
                appendCSVRow(&rows, section: "morning", field: "respiratory_symptoms", value: "Yes")
                appendCSVRow(&rows, section: "morning", field: "congestion", value: (respiratory["congestion"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "throat_condition", value: (respiratory["throatCondition"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "cough_type", value: (respiratory["coughType"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "sinus_pressure", value: (respiratory["sinusPressure"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "feeling_feverish", value: (respiratory["feelingFeverish"] as? Bool).map(formatBoolean))
                appendCSVRow(&rows, section: "morning", field: "sickness_level", value: (respiratory["sicknessLevel"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "respiratory_notes", value: nonEmpty(respiratory["notes"] as? String))
            } else {
                appendCSVRow(&rows, section: "morning", field: "respiratory_symptoms", value: "No")
            }

            if checkIn.usedSleepTherapy {
                let therapy = jsonDictionary(from: checkIn.sleepTherapyJson)
                appendCSVRow(&rows, section: "morning", field: "sleep_therapy_used", value: "Yes")
                appendCSVRow(&rows, section: "morning", field: "sleep_therapy_device", value: (therapy["device"] as? String).map(humanize))
                appendCSVRow(&rows, section: "morning", field: "sleep_therapy_compliance", value: (therapy["compliance"] as? Int).map { "\($0)/10" })
                appendCSVRow(&rows, section: "morning", field: "sleep_therapy_notes", value: nonEmpty(therapy["notes"] as? String))
            } else {
                appendCSVRow(&rows, section: "morning", field: "sleep_therapy_used", value: "No")
            }

            appendCSVRow(&rows, section: "morning", field: "notes", value: nonEmpty(checkIn.notes))
        }

        appendCSVRow(&rows, section: "sleep_events", field: "count", value: "\(sleepEvents.count)")
        for (index, event) in sleepEvents.enumerated() {
            appendCSVRow(&rows, section: "sleep_events", field: "event_\(index + 1)", value: formattedEvent(event))
        }

        return rows.joined(separator: "\n")
    }

    private var sessionDateLabel: String {
        guard let date = AppFormatters.sessionDate.date(from: sessionKey) else { return sessionKey }
        return AppFormatters.fullDate.string(from: date)
    }

    private func appendTextField(_ lines: inout [String], label: String, value: String?) {
        guard let value = nonEmpty(value) else { return }
        lines.append("- \(label): \(value)")
    }

    private func appendCSVRow(_ rows: inout [String], section: String, field: String, value: String?) {
        guard let value = nonEmpty(value) else { return }
        let columns = [sessionKey, sessionDateLabel, section, field, value].map(csvEscaped)
        rows.append(columns.joined(separator: ","))
    }

    private func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func formatStoredTimestamp(_ value: String) -> String {
        if let date = AppFormatters.parseISO8601Flexible(value) {
            return AppFormatters.mediumDateTime.string(from: date)
        }
        return value
    }

    private func formatTime(_ date: Date) -> String {
        AppFormatters.mediumDateTime.string(from: date)
    }

    private func formatOptionalTime(_ date: Date?) -> String {
        guard let date else { return "Not recorded" }
        return formatTime(date)
    }

    private func formatInterval(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours == 0 {
            return "\(remainingMinutes)m"
        }
        if remainingMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainingMinutes)m"
    }

    private func formatStressLevel(_ level: Int) -> String {
        switch level {
        case 0: return "None"
        case 1: return "Low"
        case 2: return "Mild"
        case 3: return "Medium"
        case 4: return "High"
        case 5: return "Very High"
        default: return "\(level)/5"
        }
    }

    private func formatDrinks(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return "\(Int(value.rounded())) drinks"
        }
        return String(format: "%.1f drinks", value)
    }

    private func formatBoolean(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private func formattedEvent(_ event: StoredSleepEvent) -> String {
        let parts = [
            AppFormatters.mediumDateTime.string(from: event.timestamp),
            formattedEventDetails(event)
        ]

        return parts.joined(separator: " | ")
    }

    private func formattedEventDetails(_ event: StoredSleepEvent) -> String {
        var parts = [
            humanize(event.eventType)
        ]

        if let notes = nonEmpty(event.notes) {
            parts.append(notes)
        }

        return parts.joined(separator: " | ")
    }

    private func formattedMedicationEntry(_ entry: MedicationEntry) -> String {
        let dose: String
        if let medication = MedicationConfig.type(for: entry.medicationId),
           medication.category == .sodiumOxybate {
            dose = String(format: "%.2f g", Double(entry.doseMg) / 1000.0)
        } else {
            dose = "\(entry.doseMg) mg"
        }

        var value = "\(entry.displayName) \(dose) at \(formatTime(entry.takenAtUTC))"
        if let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            value += " (\(notes))"
        }
        return value
    }

    private func formatPainEntry(_ entry: PreSleepLogAnswers.PainEntry) -> String {
        var parts = ["\(entry.area.displayText) (\(entry.side.displayText))", "Intensity \(entry.intensity)/10"]

        if !entry.sensations.isEmpty {
            parts.append(entry.sensations.map(\.displayText).joined(separator: ", "))
        }
        if let pattern = entry.pattern {
            parts.append(pattern.displayText)
        }
        if let notes = nonEmpty(entry.notes) {
            parts.append(notes)
        }

        return parts.joined(separator: " | ")
    }

    private func formattedNarcolepsySymptoms(_ checkIn: StoredMorningCheckIn) -> [String] {
        var values: [String] = []
        if checkIn.hadSleepParalysis { values.append("Sleep Paralysis") }
        if checkIn.hadHallucinations { values.append("Hallucinations") }
        if checkIn.hadAutomaticBehavior { values.append("Automatic Behavior") }
        if checkIn.fellOutOfBed { values.append("Fell Out Of Bed") }
        if checkIn.hadConfusionOnWaking { values.append("Confusion On Waking") }
        return values
    }

    private func formattedMorningPainEntries(from physical: [String: Any]) -> [String] {
        guard let entries = physical["painEntries"] as? [[String: Any]] else { return [] }

        return entries.compactMap { entry in
            let area = nonEmpty((entry["area"] as? String).map(humanize)) ?? "Unknown"
            let side = nonEmpty((entry["side"] as? String).map(humanize))
            let intensity = intValue(entry["intensity"])
            let sensations = (entry["sensations"] as? [String])?.map(humanize).joined(separator: ", ")
            let pattern = (entry["pattern"] as? String).map(humanize)
            let notes = nonEmpty(entry["notes"] as? String)

            var parts = [area + (side.map { " (\($0))" } ?? "")]
            if let intensity {
                parts.append("Intensity \(intensity)/10")
            }
            if let sensations = nonEmpty(sensations) {
                parts.append(sensations)
            }
            if let pattern = nonEmpty(pattern) {
                parts.append(pattern)
            }
            if let notes {
                parts.append(notes)
            }
            return parts.joined(separator: " | ")
        }
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? Double { return Int(value) }
        return nil
    }

    private func jsonDictionary(from raw: String?) -> [String: Any] {
        guard
            let raw,
            let data = raw.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return json
    }

    private func humanize(_ raw: String) -> String {
        let spaced = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )

        let acronyms = Set(["ahi", "apap", "bipap", "cpap", "rem"])

        return spaced
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                let value = String(token)
                return acronyms.contains(value.lowercased()) ? value.uppercased() : value.capitalized
            }
            .joined(separator: " ")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
