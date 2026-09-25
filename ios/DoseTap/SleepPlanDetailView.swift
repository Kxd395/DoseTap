import SwiftUI
import DoseCore

/// One explicit draft/save boundary for recurring wake times and work advisories.
struct SleepPlanDetailView: View {
    @State private var draft = WorkWakeSchedule()
    @State private var loaded = false
    @State private var error: String?
    @State private var receipt = false
    @State private var legacyWarning: String?
    @State private var reviewedLegacy = false
    @State private var selectedDays: Set<Int> = []
    @State private var fillTime = Date()
    private let repository = SessionRepository.shared
    private let weekdays = [2, 3, 4, 5, 6, 7, 1]
    private var zone: TimeZone { TimeZone(identifier: draft.timeZoneIdentifier) ?? .current }
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = zone; return value }

    var body: some View {
        List {
            if loaded {
                Section {
                    Text("Choose the day you wake up. Monday applies to sleep ending on Monday, including sleep that began Sunday.")
                    Text("Times use \(draft.timeZoneIdentifier). A workday is a recurring plan, not proof of attendance.").font(.caption)
                    Button("Use Current Timezone") { draft.timeZoneIdentifier = TimeZone.current.identifier }
                    Toggle("Set working days", isOn: Binding(get: { draft.workingWeekdays != nil }, set: {
                        draft.workingWeekdays = $0 ? [] : nil
                    })).accessibilityIdentifier("weekly-work-known")
                    if draft.workingWeekdays == nil { Text("Work status not recorded. No work advisory will be inferred.").font(.caption) }
                }
                if let legacyWarning {
                    Section("Review existing settings") {
                        Text(legacyWarning)
                        Toggle("Use the daily times below for work warnings", isOn: $reviewedLegacy)
                            .accessibilityIdentifier("weekly-review-legacy")
                    }
                }
                Section {
                    DisclosureGroup("Fill selected days") {
                        Text("A shortcut for this draft. Select days, apply a time, then Save Schedule.").font(.caption)
                        ForEach(weekdays, id: \.self) { day in
                            Toggle(dayName(day), isOn: Binding(get: { selectedDays.contains(day) }, set: {
                                if $0 { selectedDays.insert(day) } else { selectedDays.remove(day) }
                            })).accessibilityIdentifier("weekly-fill-\(day)")
                        }
                        DatePicker("Wake time to apply", selection: $fillTime, displayedComponents: .hourAndMinute)
                        Button("Apply to selected days") {
                            for day in selectedDays {
                                var value = entry(day); value.enabled = true
                                value.wakeByHour = calendar.component(.hour, from: fillTime)
                                value.wakeByMinute = calendar.component(.minute, from: fillTime)
                                update(value)
                            }
                            selectedDays.removeAll()
                        }.disabled(selectedDays.isEmpty)
                    }
                }
                ForEach(weekdays, id: \.self) { day in
                    Section(dayName(day)) {
                        Toggle("Required wake time", isOn: Binding(get: { entry(day).enabled }, set: {
                            var value = entry(day); value.enabled = $0; update(value)
                        })).accessibilityIdentifier("weekly-required-\(day)")
                        if entry(day).enabled {
                            DatePicker("Wake by", selection: Binding(get: {
                                time(entry(day).wakeByHour * 60 + entry(day).wakeByMinute)
                            }, set: {
                                var value = entry(day)
                                value.wakeByHour = calendar.component(.hour, from: $0)
                                value.wakeByMinute = calendar.component(.minute, from: $0); update(value)
                            }), displayedComponents: .hourAndMinute).accessibilityIdentifier("weekly-time-\(day)")
                        } else { Text("No required wake time").foregroundStyle(.secondary) }
                        if draft.workingWeekdays != nil {
                            Toggle("Working day", isOn: Binding(get: { draft.workingWeekdays?.contains(day) == true }, set: {
                                if $0 { draft.workingWeekdays?.insert(day) } else { draft.workingWeekdays?.remove(day) }
                            })).accessibilityIdentifier("weekly-work-\(day)")
                        }
                    }
                }
                Section("Work warning preferences") {
                    Picker("Warning target", selection: $draft.target) {
                        ForEach(WorkWarningTarget.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("work-warning-target")
                    if draft.target == .fixedCutoff {
                        DatePicker("Work-night cutoff", selection: Binding(get: { time(draft.cutoffMinutes) }, set: {
                            draft.cutoffMinutes = calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0)
                        }), displayedComponents: .hourAndMinute)
                    } else if draft.target == .wakeBuffer {
                        Stepper("My buffer: \(draft.bufferMinutes) minutes", value: $draft.bufferMinutes, in: 0...1440, step: 15)
                    }
                    Text("Uses the working days and required wake times above. These planning warnings do not change medication windows or set alarms.").font(.caption)
                    if !draft.exceptions.isEmpty {
                        Text("\(draft.exceptions.count) dated work/wake exceptions retained. They still take priority for work warnings.").font(.caption)
                    }
                }
            }
            if let error {
                Section {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("weekly-error")
                    Button("Reload saved schedule (discard draft)") { load() }
                }
            }
        }
        .environment(\.timeZone, zone)
        .navigationTitle("Weekly Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                Text(legacyWarning != nil && !reviewedLegacy ? "Review existing settings before saving." : "Changes apply only after saving.").font(.caption)
                Button("Save Schedule", action: save).buttonStyle(.borderedProminent)
                    .disabled(!loaded || (legacyWarning != nil && !reviewedLegacy))
                    .accessibilityIdentifier("weekly-save")
            }.frame(maxWidth: .infinity).padding(8).background(.regularMaterial)
        }
        .onAppear { if !loaded { load() } }
        .alert("Schedule saved", isPresented: $receipt) {
            Button("OK", role: .cancel) {}
        } message: { Text("Weekly wake times and work preferences saved. No medication or alarm was changed.") }
    }

    private func entry(_ day: Int) -> TypicalWeekEntry { draft.weeklySchedule!.entry(for: day) }
    private func update(_ value: TypicalWeekEntry) {
        guard let index = draft.weeklySchedule?.entries.firstIndex(where: { $0.weekdayIndex == value.weekdayIndex }) else { return }
        draft.weeklySchedule?.entries[index] = value
    }
    private func dayName(_ day: Int) -> String { Calendar.current.weekdaySymbols[day - 1] }
    private func time(_ minutes: Int) -> Date {
        calendar.date(from: DateComponents(year: 2020, month: 1, day: 15, hour: minutes / 60, minute: minutes % 60)) ?? Date()
    }
    private func load() {
        do {
            var saved = try repository.workWakeSchedule()
            legacyWarning = nil; reviewedLegacy = false
            if saved.weeklySchedule == nil {
                saved.weeklySchedule = SleepPlanStore.shared.schedule
                if saved.workingWeekdays != nil {
                    legacyWarning = "The previous work warning used \(String(format: "%02d:%02d", saved.wakeMinutes / 60, saved.wakeMinutes % 60)) in \(saved.timeZoneIdentifier). Review the daily planner times below before combining them. No settings have changed yet."
                } else { saved.timeZoneIdentifier = TimeZone.current.identifier }
            }
            guard saved.isValid else { throw CocoaError(.coderReadCorrupt) }
            draft = saved; loaded = true; error = nil; selectedDays.removeAll()
            fillTime = time(7 * 60)
        } catch {
            loaded = false
            self.error = "The saved schedule could not be read. Saving is disabled. Reload to try again; your saved settings have not been changed."
        }
    }
    private func save() {
        guard loaded, legacyWarning == nil || reviewedLegacy else { return }
        let result = repository.saveWorkWakeSchedule(draft)
        guard result.isCommitted else {
            error = "Your changes were not saved. Retry, or reload if the schedule changed elsewhere. \(result.failure?.detail ?? "")"
            return
        }
        // Read back the new revision before another edit can be submitted.
        load()
        if loaded { receipt = true }
        else { error = "The schedule was saved, but could not be reloaded. Reload before making further changes." }
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
