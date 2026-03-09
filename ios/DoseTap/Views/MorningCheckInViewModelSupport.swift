import Foundation
import DoseCore

@MainActor
extension MorningCheckInViewModel {
    func upsertPainEntries(_ entries: [PreSleepLogAnswers.PainEntry], replacingEntryKey: String?) {
        if let replacingEntryKey {
            painEntries.removeAll { $0.entryKey == replacingEntryKey }
        }
        for entry in entries {
            if let idx = painEntries.firstIndex(where: { $0.entryKey == entry.entryKey }) {
                painEntries[idx] = entry
            } else {
                painEntries.append(entry)
            }
        }
        syncLegacyPainSummary()
    }

    func removePainEntry(_ entryKey: String) {
        painEntries.removeAll { $0.entryKey == entryKey }
        syncLegacyPainSummary()
    }

    func syncLegacyPainSummary() {
        painEntries.sort { $0.entryKey < $1.entryKey }
        guard !painEntries.isEmpty else {
            painLocations = []
            painSeverity = 0
            painType = .aching
            return
        }

        painLocations = Set(painEntries.compactMap { bodyPart(for: $0.area) })
        painSeverity = painEntries.map(\.intensity).max() ?? 0
        if let first = painEntries.first?.sensations.first {
            painType = legacyPainType(for: first)
        }
    }

    func bodyPart(for area: PreSleepLogAnswers.PainArea) -> BodyPart? {
        switch area {
        case .headFace: return .head
        case .neck: return .neck
        case .upperBack: return .upperBack
        case .midBack, .lowerBack: return .lowerBack
        case .shoulder: return .shoulders
        case .armElbow: return .arms
        case .wristHand: return .hands
        case .chestRibs: return .chest
        case .abdomen: return .abdomen
        case .hipGlute: return .hips
        case .knee: return .knees
        case .ankleFoot: return .feet
        case .other: return nil
        }
    }

    func legacyPainType(for sensation: PreSleepLogAnswers.PainSensation) -> PainType {
        switch sensation {
        case .aching: return .aching
        case .sharp, .shooting, .stabbing: return .sharp
        case .burning: return .burning
        case .throbbing: return .throbbing
        case .cramping, .tightness: return .cramping
        case .radiating, .pinsNeedles, .numbness, .other: return .aching
        }
    }

    func configureDoseReconciliationState() {
        let sessionRepo = SessionRepository.shared
        let doseLog = sessionRepo.fetchDoseLog(forSession: sessionDate)
        let doseEvents = sessionRepo.fetchDoseEvents(forSessionDate: sessionDate)
        let preSleepAnswers = sessionRepo.fetchMostRecentPreSleepLog(sessionId: sessionId)?.answers

        let plannedDose1 = Self.normalizedDoseAmount(
            Self.parseDoseAmount(from: doseEvents, eventType: "dose1")
                ?? Self.plannedDoseAmount(from: preSleepAnswers, eventType: "dose1")
                ?? Self.defaultDoseAmountMg()
        )
        let plannedDose2 = Self.normalizedDoseAmount(
            Self.parseDoseAmount(from: doseEvents, eventType: "dose2")
                ?? Self.plannedDoseAmount(from: preSleepAnswers, eventType: "dose2")
                ?? Self.defaultDoseAmountMg()
        )

        loggedDose1Time = doseLog?.dose1Time
        loggedDose2Time = doseLog?.dose2Time
        loggedDose2Skipped = doseLog?.dose2Skipped ?? doseEvents.contains(where: { $0.eventType == "dose2_skipped" })

        reconcileDose1Taken = loggedDose1Time == nil
        reconcileDose1Time = doseLog?.dose1Time ?? Self.defaultDose1Time(for: sessionDate)
        reconcileDose2Time = doseLog?.dose2Time ?? Self.defaultDose2Time(for: sessionDate, dose1Time: reconcileDose1Time)
        reconcileDose1AmountMg = plannedDose1
        reconcileDose2AmountMg = plannedDose2
        dose2Reconciliation = loggedDose2Time != nil
            ? .leaveAsIs
            : (loggedDose2Skipped ? .skipped : .taken)
    }

    func applyDoseReconciliation() {
        let sessionRepo = SessionRepository.shared

        if loggedDose1Time == nil, reconcileDose1Taken {
            sessionRepo.reconcileDose1(
                sessionDate: sessionDate,
                takenAt: reconcileDose1Time,
                amountMg: Self.normalizedDoseAmount(reconcileDose1AmountMg)
            )
        }

        if loggedDose2Time == nil {
            switch dose2Reconciliation {
            case .leaveAsIs:
                break
            case .taken:
                sessionRepo.reconcileDose2(
                    sessionDate: sessionDate,
                    takenAt: reconcileDose2Time,
                    amountMg: Self.normalizedDoseAmount(reconcileDose2AmountMg)
                )
            case .skipped:
                sessionRepo.reconcileDose2Skipped(sessionDate: sessionDate, timestamp: reconcileDose2Time)
            }
        }
    }

    static func parseDoseAmount(from events: [DoseCore.StoredDoseEvent], eventType: String) -> Int? {
        guard
            let metadata = events.first(where: { $0.eventType == eventType })?.metadata,
            let data = metadata.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return intValue(from: object["amount_mg"])
    }

    static func plannedDoseAmount(from answers: PreSleepLogAnswers?, eventType: String) -> Int? {
        guard let answers else { return nil }
        if eventType == "dose1", let explicit = answers.plannedDose1Mg {
            return explicit
        }
        if eventType == "dose2", let explicit = answers.plannedDose2Mg {
            return explicit
        }
        guard let total = answers.resolvedPlannedTotalNightlyMg else { return nil }
        let ratioIndex = eventType == "dose1" ? 0 : 1
        return Int((Double(total) * answers.resolvedPlannedDoseSplitRatio[ratioIndex]).rounded())
    }

    static func defaultDoseAmountMg() -> Int {
        DoseCore.MedicationConfig.nightMedications.first(where: { $0.id != "lumryz" })?.defaultDoseMg
            ?? DoseCore.MedicationConfig.nightMedications.first?.defaultDoseMg
            ?? 4500
    }

    static func normalizedDoseAmount(_ value: Int) -> Int {
        max(250, min(maxDoseAmountMg, value))
    }

    static func defaultDose1Time(for sessionDate: String) -> Date {
        guard let night = AppFormatters.sessionDate.date(from: sessionDate) else {
            return Date()
        }
        return Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: night) ?? night
    }

    static func defaultDose2Time(for sessionDate: String, dose1Time: Date) -> Date {
        if let parsedNight = AppFormatters.sessionDate.date(from: sessionDate),
           let nextMorning = Calendar.current.date(byAdding: .day, value: 1, to: parsedNight),
           let morningDefault = Calendar.current.date(bySettingHour: 1, minute: 0, second: 0, of: nextMorning) {
            return morningDefault
        }
        return dose1Time.addingTimeInterval(3 * 60 * 60)
    }
}
