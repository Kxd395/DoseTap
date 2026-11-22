import DoseCore
import SwiftUI

struct SavedDaytimeReminderSection: View {
    let ledger: DaytimePromptLedger?

    init(record: StoredExportSourceRecord) {
        ledger = try? DaytimePromptLedger.decodePayload(record.savedReminderPayload())
    }

    var body: some View {
        Section("Reminder history") {
            if let ledger {
                LabeledContent("Saved reminder preference", value: ledger.enabled ? "On" : "Off")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("saved-reminder-preference")
                if ledger.prompts.isEmpty {
                    Text("No reminders were recorded.")
                } else {
                    NavigationLink {
                        SavedDaytimeReminderList(ledger: ledger)
                    } label: {
                        LabeledContent("Saved reminders", value: ledger.prompts.count.formatted())
                    }
                    .accessibilityIdentifier("saved-reminder-activity")
                }
            } else {
                Text("Reminder history could not be read. The original payload is available below.")
            }
        }
    }
}

private struct SavedDaytimeReminderList: View {
    let ledger: DaytimePromptLedger

    var body: some View {
        let schedules = Dictionary(uniqueKeysWithValues: ledger.schedules.map { ($0.id, $0.timeZone) })
        List(ledger.prompts.sorted { $0.intendedAt > $1.intendedAt }) { prompt in
            VStack(alignment: .leading, spacing: 4) {
                Text(statusLabel(prompt.status)).font(.headline)
                if let identifier = schedules[prompt.scheduleID], let zone = TimeZone(identifier: identifier) {
                    let time = plannedTime(prompt.intendedAt, in: zone)
                    Text("Planned for \(time)")
                }
                if let reason = prompt.reason { Text(reason).foregroundStyle(.secondary) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("saved-reminder-\(prompt.id.uuidString)")
        }
        .navigationTitle("Saved reminders")
    }

    private func plannedTime(_ date: Date, in zone: TimeZone) -> String {
        var style = Date.FormatStyle().year().month().day().hour().minute().timeZone(.specificName(.short))
        style.timeZone = zone
        return date.formatted(style)
    }

    private func statusLabel(_ status: DaytimePrompt.Status) -> String {
        switch status {
        case .pending: "Planned"
        case .deferred: "Deferred"
        case .suppressed: "Suppressed"
        case .skipped: "Skipped"
        case .expired: "Expired"
        case .responded: "Answered"
        }
    }
}
