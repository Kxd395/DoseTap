import Foundation

/// A retrospective record change, never an instruction to take medication.
public struct HistoryDoseChange: Equatable, Sendable {
    public static let doseTypes = ["dose1", "dose2", "dose2_skipped", "extra_dose"]
    public let eventType: String
    public let timestamp: Date
    public let replacingEventID: String?
    public let remove: Bool
    public let reason: String

    public init(eventType: String, timestamp: Date, replacingEventID: String? = nil,
                remove: Bool = false, reason: String) {
        self.eventType = eventType
        self.timestamp = timestamp
        self.replacingEventID = replacingEventID
        self.remove = remove
        self.reason = reason
    }

    public func validationError(existing: [StoredDoseEvent], now: Date) -> String? {
        guard Self.doseTypes.contains(eventType) else { return "Choose a supported medication record." }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 500 else {
            return "Explain the entry or correction in 1–500 characters."
        }
        guard now.timeIntervalSince1970.isFinite,
              remove || (timestamp.timeIntervalSince1970.isFinite && timestamp <= now) else {
            return "Enter an actual occurrence time, not a future time."
        }
        if remove, eventType == "dose1", existing.contains(where: { $0.eventType == "snooze" }) {
            return "A snoozed session needs its Dose 1 record. Correct its time instead."
        }
        if let id = replacingEventID {
            guard let original = existing.first(where: { $0.id == id }), Self.doseTypes.contains(original.eventType) else {
                return "The original record changed. Reload before editing."
            }
            let secondOutcomes = ["dose2", "dose2_skipped"]
            guard original.eventType == eventType || (secondOutcomes.contains(original.eventType) && secondOutcomes.contains(eventType)) else {
                return "Correct this record's time or outcome; do not change its dose number."
            }
        } else if remove { return "Select the erroneous record before removing it." }
        var rows = existing.filter { $0.id != replacingEventID && Self.doseTypes.contains($0.eventType) }
        if !remove {
            rows.append(StoredDoseEvent(id: "new", eventType: eventType, timestamp: timestamp, sessionDate: ""))
        }
        let first = rows.filter { $0.eventType == "dose1" }
        let second = rows.filter { $0.eventType == "dose2" || $0.eventType == "dose2_skipped" }
        let extras = rows.filter { $0.eventType == "extra_dose" }
        guard first.count <= 1, second.count <= 1 else {
            return "A record already exists. Edit that record instead of adding a duplicate outcome."
        }
        if !second.isEmpty || !extras.isEmpty {
            guard let dose1 = first.first else { return "Record the actual Dose 1 first; its time cannot be inferred." }
            guard second.allSatisfy({ $0.timestamp >= dose1.timestamp }) else { return "Dose 2 cannot precede Dose 1." }
        }
        if !extras.isEmpty {
            guard let dose2 = second.first, dose2.eventType == "dose2" else {
                return "Extra doses require a recorded Dose 1 and Dose 2. Correct dependent records first."
            }
            guard extras.allSatisfy({ $0.timestamp >= dose2.timestamp }) else { return "An extra dose cannot precede Dose 2." }
        }
        return nil
    }

    public func needsTimingWarning(existing: [StoredDoseEvent]) -> Bool {
        guard !remove else { return false }
        if eventType == "extra_dose" { return true }
        let first = eventType == "dose1" ? timestamp : existing.first(where: { $0.eventType == "dose1" })?.timestamp
        let second = eventType == "dose2" ? timestamp : existing.first(where: { $0.eventType == "dose2" })?.timestamp
        guard let first, let second else { return false }
        return MedicationTiming.classify(dose1: first, dose2: second) != .inWindow
    }
}
