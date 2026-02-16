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
