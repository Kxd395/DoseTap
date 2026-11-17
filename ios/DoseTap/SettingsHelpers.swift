import SwiftUI
import DoseCore

// Extracted from SettingsView.swift — Shared helpers, formatters, and reusable rows

// MARK: - DateFormatter Extension for Export
extension DateFormatter {
    static let exportDateFormatter: DateFormatter = AppFormatters.exportFilename
}

// MARK: - Typical Week Row
struct TypicalWeekRow: View {
    let weekday: Int
    let entry: TypicalWeekEntry
    var onChange: (Date, Bool) -> Void
    
    @State private var wakeTime: Date
    
    init(weekday: Int, entry: TypicalWeekEntry, onChange: @escaping (Date, Bool) -> Void) {
        self.weekday = weekday
        self.entry = entry
        self.onChange = onChange
        _wakeTime = State(initialValue: TypicalWeekRow.makeDate(from: entry))
    }
    
    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { entry.enabled },
                set: { newValue in onChange(wakeTime, newValue) }
            )) {
                Text(weekdayName(weekday))
            }
            .toggleStyle(.switch)
            
            DatePicker(
                "",
                selection: Binding(
                    get: { wakeTime },
                    set: { newValue in
                        wakeTime = newValue
                        onChange(newValue, entry.enabled)
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .onChange(of: entry) { newEntry in
            wakeTime = TypicalWeekRow.makeDate(from: newEntry)
        }
    }
    
    private func weekdayName(_ index: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let normalized = (index - 1 + symbols.count) % symbols.count
        return symbols[normalized]
    }
    
    private static func makeDate(from entry: TypicalWeekEntry) -> Date {
        var comps = DateComponents()
        comps.hour = entry.wakeByHour
        comps.minute = entry.wakeByMinute
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
}

// MARK: - Sleep Plan Settings Row
struct SleepPlanSettingsRow: View {
    let title: String
    let minutes: Int
    let step: Int
    let range: ClosedRange<Int>
    var onChange: (Int) -> Void
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Stepper(value: Binding(
                get: { minutes },
                set: { newValue in onChange(newValue) }
            ), in: range, step: step) {
                Text("\(minutes) min")
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Export failure presentation

struct StudioExportFailure: Error {
    let step: String
    let underlying: Error
}

enum StudioExportFailureMessage {
    static func make(_ error: Error, step: String) -> String {
        if let failure = error as? StudioExportFailure {
            return make(failure.underlying, step: failure.step)
        }
        let explanation: String
        if let failure = error as? MedicationStorageInjectedFailure {
            let guidance: String
            switch failure.code {
            case .diskFull:
                guidance = "The database reported insufficient space. Check device storage and try again."
            case .precondition, .constraint:
                guidance = "Keep your records intact. This needs record review; retrying alone may not resolve it."
            case .busy:
                guidance = "The database is busy. Wait a moment and try again."
            default:
                guidance = "Keep your records intact and try again. If it continues, report this message."
            }
            explanation = "\(failure.detail) [\(failure.code.rawValue)]\n\n\(guidance)"
        } else if error is ExportReadError {
            explanation = "Some stored records could not be read completely. Keep your records intact and try again. If it continues, report this message."
        } else if error is DecodingError {
            explanation = "A stored record could not be decoded. Keep your records intact and report this message."
        } else {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError {
                explanation = "The file system reported insufficient space. Check device storage and try again."
            } else {
                explanation = "The export could not be completed. Try again. If it continues, report this message."
            }
        }
        return "\(step) failed.\n\n\(explanation)\n\nNo archive was shared. Your saved records were not changed."
    }
}

// Export request metadata, retained unchanged while separating presentation helpers.
struct InsightsWHOOPEnrichment: Encodable {
    let version = 1
    var sleepStatus = "not_attempted"
    var recoveryStatus = "not_attempted"
    var queryStartUTC: Date?
    var queryEndUTC: Date?
    var sleepRecordCount: Int?
    var recoveryRecordCount: Int?
    var eligibleNightCount: Int?
    var notAttemptedReason: String?

    func warnings(hasExportedSleep: Bool) -> [String] {
        var messages: [String] = []
        if sleepStatus == "failed" {
            messages.append("WHOOP sleep could not be fetched; WHOOP enrichment is unavailable.")
        }
        if recoveryStatus == "failed" {
            messages.append(hasExportedSleep ? "WHOOP sleep was fetched, but recovery could not be fetched; available sleep data is retained." :
                "WHOOP recovery could not be fetched; no WHOOP sleep summary is included in this export.")
        }
        if sleepStatus == "completed" && sleepRecordCount == 0 {
            messages.append("WHOOP sleep query completed with no records.")
        } else if sleepStatus == "completed" && eligibleNightCount == 0 {
            messages.append("WHOOP sleep records were fetched, but none met the existing sleep-summary criteria.")
        }
        switch notAttemptedReason {
        case "feature_disabled": messages.append("WHOOP enrichment was not attempted because the integration is disabled.")
        case "preference_disabled": messages.append("WHOOP enrichment was not attempted because the WHOOP preference is off.")
        case "disconnected": messages.append("WHOOP enrichment was not attempted because the account is disconnected.")
        case "no_sessions": messages.append("WHOOP enrichment was not attempted because there are no sessions to export.")
        case "invalid_range": messages.append("WHOOP enrichment was not attempted because no valid query range was available.")
        default: break
        }
        return messages
    }
}
