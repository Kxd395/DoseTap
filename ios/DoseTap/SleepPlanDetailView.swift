import SwiftUI
import DoseCore

/// Detailed view for configuring typical week schedule
struct SleepPlanDetailView: View {
    @ObservedObject private var sleepPlanStore = SleepPlanStore.shared
    @State private var workdayWake = SleepPlanDetailView.makeDate(hour: 6, minute: 30)
    @State private var offdayWake = SleepPlanDetailView.makeDate(hour: 8, minute: 0)
    @State private var workdays: Set<Int> = [2, 4, 6] // Mon / Wed / Fri default
    @State private var offdaysEnabled = true
    
    var body: some View {
        List {
            Section {
                TimePickerSheetRow(
                    title: "Workday Wake",
                    selection: $workdayWake
                )
                TimePickerSheetRow(
                    title: "Off-day Wake",
                    selection: $offdayWake
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Workdays")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    WorkdaySelector(selectedDays: $workdays)
                }

                Toggle("Keep off-days enabled", isOn: $offdaysEnabled)

                Button {
                    sleepPlanStore.applyWorkWeekTemplate(
                        workdays: workdays,
                        workdayWake: workdayWake,
                        offdayWake: offdayWake,
                        offdaysEnabled: offdaysEnabled
                    )
                } label: {
                    Label("Apply Workday Pattern", systemImage: "calendar.badge.clock")
                }
            } header: {
                Label("Quick Weekly Setup", systemImage: "briefcase.fill")
            } footer: {
                Text("Set one wake time for your workdays and another for non-workdays. This is ideal for split schedules, including 3-day work weeks.")
                    .font(.caption)
            }

            Section {
                ForEach(1...7, id: \.self) { weekday in
                    TypicalWeekRowInternal(
                        weekday: weekday,
                        entry: sleepPlanStore.schedule.entry(for: weekday)
                    ) { date, enabled in
                        sleepPlanStore.updateEntry(weekday: weekday, wakeTime: date, enabled: enabled)
                    }
                }
            } header: {
                Label("Typical Week Schedule", systemImage: "calendar.badge.clock")
            } footer: {
                Text("Set your typical wake times for each day. These help the Tonight planner suggest optimal dose times based on your schedule.")
                    .font(.caption)
            }
            
            Section {
                Text("The wake time you set for each day feeds into the Sleep Planner and helps calculate optimal bedtimes. Your actual dose window (150-240 minutes) remains unchanged.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Weekly Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            seedTemplateFields()
        }
    }

    private func seedTemplateFields() {
        // Preserve current custom choices once user starts editing in this session.
        guard workdays == Set([2, 4, 6]) else { return }

        let monday = sleepPlanStore.schedule.entry(for: 2)
        let sunday = sleepPlanStore.schedule.entry(for: 1)

        workdayWake = SleepPlanDetailView.makeDate(from: monday)
        offdayWake = SleepPlanDetailView.makeDate(from: sunday)

        let offdayIndexes = Set(1...7).subtracting(workdays)
        offdaysEnabled = sleepPlanStore.schedule.entries
            .filter { offdayIndexes.contains($0.weekdayIndex) }
            .allSatisfy(\.enabled)
    }

    private static func makeDate(from entry: TypicalWeekEntry) -> Date {
        makeDate(hour: entry.wakeByHour, minute: entry.wakeByMinute)
    }

    private static func makeDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }
}

/// Internal copy of TypicalWeekRow for use in this detail view
private struct TypicalWeekRowInternal: View {
    let weekday: Int
    let entry: TypicalWeekEntry
    let onChange: (Date, Bool) -> Void
    
    @State private var showPicker = false
    
    private var weekdayName: String {
        let symbols = Calendar.current.weekdaySymbols
        let normalized = (weekday - 1 + symbols.count) % symbols.count
        return symbols[normalized]
    }
    
    private var wakeTime: Date {
        var components = DateComponents()
        components.hour = entry.wakeByHour
        components.minute = entry.wakeByMinute
        return Calendar.current.date(from: components) ?? Date()
    }
    
    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { entry.enabled },
                set: { enabled in
                    onChange(wakeTime, enabled)
                }
            )) {
                Text(weekdayName)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            Button {
                showPicker.toggle()
            } label: {
                Text(wakeTime, style: .time)
                    .foregroundColor(entry.enabled ? .primary : .secondary)
            }
            .disabled(!entry.enabled)
        }
        .sheet(isPresented: $showPicker) {
            NavigationView {
                DatePicker(
                    "Wake Time",
                    selection: Binding(
                        get: { wakeTime },
                        set: { newTime in
                            onChange(newTime, entry.enabled)
                        }
                    ),
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .navigationTitle("\(weekdayName) Wake Time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showPicker = false
                        }
                    }
                }
            }
        }
    }
}

struct TimePickerSheetRow: View {
    let title: String
    @Binding var selection: Date
    var accessibilityLabel: String?
    @State private var showPicker = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                showPicker = true
            } label: {
                Text(selection, style: .time)
                    .foregroundColor(.primary)
            }
            .accessibilityLabel(accessibilityLabel ?? title)
        }
        .sheet(isPresented: $showPicker) {
            NavigationView {
                DatePicker(
                    title,
                    selection: $selection,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showPicker = false
                        }
                    }
                }
            }
        }
    }
}

private struct WorkdaySelector: View {
    @Binding var selectedDays: Set<Int>
    private let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1] // Mon ... Sun

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                let isSelected = selectedDays.contains(weekday)
                Button {
                    if isSelected {
                        selectedDays.remove(weekday)
                    } else {
                        selectedDays.insert(weekday)
                    }
                } label: {
                    Text(shortName(for: weekday))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.accentColor : Color(.secondarySystemFill))
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shortName(for weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let normalized = (weekday - 1 + symbols.count) % symbols.count
        return symbols[normalized]
    }
}

#Preview {
    NavigationView {
        SleepPlanDetailView()
    }
}
