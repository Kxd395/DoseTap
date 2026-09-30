import SwiftUI
import DoseCore

struct DaytimeReminderView: View {
    @ObservedObject private var service = DaytimePromptService.shared
    @State private var enabled = false
    @State private var time = Date()
    @State private var quietStart = Date()
    @State private var quietEnd = Date()
    var body: some View {
        Form {
            Section("Optional routine reminder") {
                Toggle("Enable daytime reminder", isOn: $enabled)
                DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute)
                DatePicker("Quiet hours begin", selection: $quietStart, displayedComponents: .hourAndMinute)
                DatePicker("Quiet hours end", selection: $quietEnd, displayedComponents: .hourAndMinute)
                Text("Save uses your current timezone: \(TimeZone.current.identifier). Equal quiet times disable the quiet window.")
                    .font(.caption)
                Button("Save reminder") { Task { await save() } }.disabled(service.isBusy)
            }
            Section("Status") {
                Text(service.status)
                if let schedule = service.ledger.current { Text("Saved timezone: \(schedule.timeZone)").font(.caption) }
                Button("Retry / refresh status") { Task { await service.reconcile() } }.disabled(service.isBusy)
                if let through = service.scheduledThrough { Text("Scheduled through: \(through.formatted())") }
                Text("Up to seven daily reminders are queued. Open DoseTap before the scheduled-through date to renew them. Routine notifications respect iOS Focus and have no sound or health details. Known sleep or naps pause queued reminders until wake is recorded. No delivery time is inferred.")
                    .font(.caption)
            }
            Section("Prompt history") {
                ForEach(service.ledger.prompts.reversed()) { prompt in
                    VStack(alignment: .leading, spacing: 5) {
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
        _ = await service.change(requestPermission: enabled) { value in
            value.quietStart = calendar.component(.hour, from: quietStart) * 60 + calendar.component(.minute, from: quietStart)
            value.quietEnd = calendar.component(.hour, from: quietEnd) * 60 + calendar.component(.minute, from: quietEnd)
            try value.configure(hour: calendar.component(.hour, from: time), minute: calendar.component(.minute, from: time),
                                timeZone: TimeZone.current.identifier, enabled: enabled, at: Date())
        }
    }
}

struct DaytimePromptPresentation: ViewModifier {
    @ObservedObject private var service = DaytimePromptService.shared
    func body(content: Content) -> some View {
        content.sheet(item: $service.promptToOpen) { prompt in
            DaytimeCheckInEditor(promptID: prompt.id) { assessment in
                Task { await service.markResponded(assessment) }
            }
        }
    }
}
