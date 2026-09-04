import SwiftUI
import DoseCore

/// Detailed view for configuring typical week schedule
struct SleepPlanDetailView: View {
    @ObservedObject private var sleepPlanStore = SleepPlanStore.shared
    @State private var workdayWake = SleepPlanDetailView.makeDate(hour: 6, minute: 30)
    @State private var offdayWake = SleepPlanDetailView.makeDate(hour: 8, minute: 0)
    @State private var workdays: Set<Int> = [2, 4, 6] // Mon / Wed / Fri default
    @State private var offdaysEnabled = true
    @State private var workWarningPlan = WorkWakeSchedule()
    @State private var warningDays: Set<Int> = []
    @State private var warningWake = SleepPlanDetailView.makeDate(hour: 7, minute: 0)
    @State private var warningCutoff = SleepPlanDetailView.makeDate(hour: 2, minute: 0)
    @State private var workSaveMessage: String?
    private let repository = SessionRepository.shared
    
    var body: some View {
        List {
            Section("Work and Wake Warning") {
                Picker("Warning target", selection: $workWarningPlan.target) {
                    ForEach(WorkWarningTarget.allCases, id: \.self) { target in Text(target.title).tag(target) }
                }
                .accessibilityIdentifier("work-warning-target")
                Text("Working days for this advisory")
                WorkdaySelector(selectedDays: $warningDays)
                DatePicker("Required work wake time", selection: $warningWake, displayedComponents: .hourAndMinute)
                if workWarningPlan.target == .fixedCutoff {
                    DatePicker("Work-night cutoff", selection: $warningCutoff, displayedComponents: .hourAndMinute)
                } else if workWarningPlan.target == .wakeBuffer {
                    Stepper("My buffer: \(workWarningPlan.bufferMinutes) minutes", value: $workWarningPlan.bufferMinutes, in: 0...1440, step: 15)
                    Text("Choose your own planning buffer. DoseTap does not prescribe a buffer or change medication timing.").font(.caption)
                } else {
                    Text("Uses your saved Dose 2 target interval on working dates.").font(.caption)
                }
                Text("Times use \(workWarningPlan.timeZoneIdentifier). Dated exceptions take priority.").font(.caption)
                Button("Use Current Timezone") { workWarningPlan.timeZoneIdentifier = TimeZone.current.identifier }
                Button("Save Work Warning Schedule") { saveWorkWarningPlan() }
                if let workSaveMessage { Text(workSaveMessage).font(.subheadline) }
                if workWarningPlan.workingWeekdays == nil {
                    Text("Work status is unknown until you save. Enabled Typical Week days are not assumed to be working days.").font(.caption)
                }
            }
            .environment(\.timeZone, TimeZone(identifier: workWarningPlan.timeZoneIdentifier) ?? .current)
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
            do {
                workWarningPlan = try repository.workWakeSchedule()
                if workWarningPlan.workingWeekdays == nil { workWarningPlan.timeZoneIdentifier = TimeZone.current.identifier }
                warningDays = workWarningPlan.workingWeekdays ?? []
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: workWarningPlan.timeZoneIdentifier) ?? .current
                warningWake = calendar.date(bySettingHour: workWarningPlan.wakeMinutes / 60, minute: workWarningPlan.wakeMinutes % 60, second: 0, of: Date()) ?? Date()
                warningCutoff = calendar.date(bySettingHour: workWarningPlan.cutoffMinutes / 60, minute: workWarningPlan.cutoffMinutes % 60, second: 0, of: Date()) ?? Date()
            } catch { workSaveMessage = "The saved work schedule could not be read. Review and save it again." }
        }
    }

    private func saveWorkWarningPlan() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: workWarningPlan.timeZoneIdentifier) ?? .current
        var proposed = workWarningPlan
        proposed.workingWeekdays = warningDays
        proposed.wakeMinutes = calendar.component(.hour, from: warningWake) * 60 + calendar.component(.minute, from: warningWake)
        proposed.cutoffMinutes = calendar.component(.hour, from: warningCutoff) * 60 + calendar.component(.minute, from: warningCutoff)
        let result = repository.saveWorkWakeSchedule(proposed)
        if result.isCommitted {
            workWarningPlan = (try? repository.workWakeSchedule()) ?? proposed
            workSaveMessage = "Work warning schedule saved. No medication record changed."
        } else { workSaveMessage = result.failure?.detail ?? "Schedule could not be saved. Please retry." }
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
