import SwiftUI
import DoseCore

struct DaytimeReminderView: View {
    @ObservedObject private var service = DaytimePromptService.shared
    @State private var enabled = false
    @State private var time = Date()
    @State private var quietStart = Date()
    @State private var quietEnd = Date()
    @State private var anchor = DaytimePromptRule.Anchor.clock
    @State private var weekdays = Set(1...7)
    @State private var wakeOffset = 240
    @State private var offDayAnchor = DaytimePromptRule.Anchor.clock
    @State private var offDayTime = Date()
    @State private var timeZoneID = TimeZone.current.identifier
    var body: some View {
        Form {
            Section("Optional routine reminder") {
                Toggle("Enable daytime reminder", isOn: $enabled)
                Picker("Reminder anchor", selection: $anchor) {
                    ForEach(DaytimePromptRule.Anchor.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if anchor == .clock { DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute) }
                if anchor == .shiftMidpoint || anchor == .shiftBreak {
                    Picker("Off-day anchor", selection: $offDayAnchor) {
                        Text("Clock time").tag(DaytimePromptRule.Anchor.clock)
                        Text("After main wake").tag(DaytimePromptRule.Anchor.mainWake)
                    }
                    if offDayAnchor == .clock { DatePicker("Off-day time", selection: $offDayTime, displayedComponents: .hourAndMinute) }
                }
                if anchor == .mainWake || ((anchor == .shiftMidpoint || anchor == .shiftBreak) && offDayAnchor == .mainWake) {
                    Stepper("After reported main wake: \(wakeOffset) minutes", value: $wakeOffset, in: 0...1440, step: 15)
                }
                ForEach(1...7, id: \.self) { day in
                    Toggle(Calendar(identifier: .gregorian).weekdaySymbols[day - 1], isOn: Binding(
                        get: { weekdays.contains(day) },
                        set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } }))
                }
                if enabled && weekdays.isEmpty { Text("Select at least one day.").foregroundStyle(.red) }
                Text("Selected days refer to the clock date, reported main-wake date, or originating work date in the saved timezone. A wake offset or overnight shift can notify on the following date.").font(.caption)
                DatePicker("Quiet hours begin", selection: $quietStart, displayedComponents: .hourAndMinute)
                DatePicker("Quiet hours end", selection: $quietEnd, displayedComponents: .hourAndMinute)
                Text("Schedule timezone: \(timeZoneID). Equal quiet times disable the quiet window.")
                    .font(.caption)
                Button("Use current timezone") { timeZoneID = TimeZone.current.identifier }
                Button("Save reminder") { Task { await save() } }.disabled(service.isBusy || (enabled && weekdays.isEmpty))
            }
            Section("Status") {
                Text(service.status)
                if !service.anchorAvailability.isEmpty {
                    DisclosureGroup("Unscheduled dates") {
                        ForEach(service.anchorAvailability, id: \.self) { Text($0).font(.caption) }
                    }
                }
                if let schedule = service.ledger.current { Text("Saved timezone: \(schedule.timeZone)").font(.caption) }
                Button("Retry / refresh status") { Task { await service.reconcile() } }.disabled(service.isBusy)
                if let through = service.scheduledThrough { Text("Scheduled through: \(through.formatted())") }
                Text("Up to seven reminders within the next seven civil days are queued. Open DoseTap regularly to renew this window. Wake anchors require a recorded final wake in your night outcome; ending a session does not provide it. Missing or ambiguous anchors stay unscheduled. Routine notifications respect iOS Focus and have no sound or health details. Known sleep or naps pause queued reminders until wake is recorded. No delivery time is inferred.")
                    .font(.caption)
            }
            Section("Prompt history") {
                ForEach(service.ledger.prompts.reversed()) { prompt in
                    VStack(alignment: .leading, spacing: 5) {
                        if let anchor = prompt.anchor { Text(anchor.label).font(.headline) }
                        Text(prompt.intendedAt, format: .dateTime.month().day().hour().minute())
                        Text(prompt.status.rawValue.capitalized)
                        if let reason = prompt.reason { Text(reason).font(.caption) }
                        if let actual = prompt.assessedAt { Text("Assessed: \(actual.formatted())").font(.caption) }
                        if prompt.assessmentID == nil && prompt.intendedAt <= Date() {
                            Button("Check in now") { Task { await service.handle(promptID: prompt.id, action: "open") } }
                            if prompt.isOutstanding {
                                HStack {
                                    Button("Later (30 min)") { Task { await service.handle(promptID: prompt.id, action: "daytime_later") } }
                                    Button("Skip") { Task { await service.handle(promptID: prompt.id, action: "daytime_skip") } }
                                }
                            }
                        }
                    }.disabled(service.isBusy)
                }
                Text("Skipped and unanswered prompts say nothing about symptoms. A delayed check-in rates the present moment.").font(.caption)
            }
        }
        .navigationTitle("Daytime reminder")
        .task {
            await service.reconcile()
            enabled = service.ledger.enabled
            let rule = service.ledger.current?.rule
            anchor = rule?.anchor ?? .clock; weekdays = Set(rule?.selectedWeekdays ?? Array(1...7))
            wakeOffset = rule?.wakeOffsetMinutes ?? 240; offDayAnchor = rule?.offDayAnchor ?? .clock
            offDayTime = clock(hour: rule?.offDayHour ?? 14, minute: rule?.offDayMinute ?? 0)
            timeZoneID = service.ledger.current?.timeZone ?? TimeZone.current.identifier
            time = clock(hour: service.ledger.current?.hour ?? 14, minute: service.ledger.current?.minute ?? 0)
            quietStart = clock(hour: service.ledger.quietStart / 60, minute: service.ledger.quietStart % 60)
            quietEnd = clock(hour: service.ledger.quietEnd / 60, minute: service.ledger.quietEnd % 60)
        }
    }
    private func clock(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
    private func save() async {
        let calendar = Calendar.current
        let savedDays = weekdays.isEmpty ? Set(service.ledger.current?.rule?.selectedWeekdays ?? Array(1...7)) : weekdays
        _ = await service.change(requestPermission: enabled) { value in
            value.quietStart = calendar.component(.hour, from: quietStart) * 60 + calendar.component(.minute, from: quietStart)
            value.quietEnd = calendar.component(.hour, from: quietEnd) * 60 + calendar.component(.minute, from: quietEnd)
            try value.configure(hour: calendar.component(.hour, from: time), minute: calendar.component(.minute, from: time),
                                timeZone: timeZoneID, enabled: enabled, at: Date(),
                                rule: DaytimePromptRule(anchor: anchor, selectedWeekdays: savedDays,
                                    wakeOffsetMinutes: wakeOffset, offDayAnchor: offDayAnchor,
                                    offDayHour: calendar.component(.hour, from: offDayTime),
                                    offDayMinute: calendar.component(.minute, from: offDayTime)))
        }
    }
}

struct DaytimePromptPresentation: ViewModifier {
    @ObservedObject private var service = DaytimePromptService.shared
    func body(content: Content) -> some View {
        content.sheet(item: $service.promptToOpen) { prompt in
            DaytimeCheckInEditor(promptID: prompt.id, samplingProtocolID: prompt.scheduleID,
                                samplingProtocolLabel: service.protocolLabel(for: prompt)) { assessment in
                Task { await service.markResponded(assessment) }
            }
        }
    }
}
