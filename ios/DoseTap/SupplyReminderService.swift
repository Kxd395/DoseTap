import Foundation
import Combine
import UserNotifications
import DoseCore

@MainActor
final class SupplyReminderService: ObservableObject {
    static let requestID = "dosetap_supply_order_reminder"
    static let shared = SupplyReminderService(repository: .shared, client: SystemAlarmNotificationCenterClient())

    @Published private(set) var backup: SupplyBackup?
    @Published private(set) var status = "Not checked"
    @Published private(set) var isBusy = false
    @Published private(set) var needsSettings = false
    private let repository: SessionRepository
    private let client: AlarmNotificationCenterClient
    private let now: () -> Date
    private let timeZone: () -> TimeZone
    private var reconcileAgain = false

    init(repository: SessionRepository, client: AlarmNotificationCenterClient,
         now: @escaping () -> Date = Date.init, timeZone: @escaping () -> TimeZone = { .current }) {
        self.repository = repository
        self.client = client
        self.now = now
        self.timeZone = timeZone
    }

    func reconcile(requestPermission: Bool = false) async {
        guard !isBusy else { reconcileAgain = true; return }
        isBusy = true
        defer { finish() }
        await reconcileLocked(requestPermission: requestPermission)
    }

    /// UI commands serialize source writes with OS effects. Dose commands never wait here.
    @discardableResult
    func change(requestPermission: Bool = false, _ mutation: (inout SupplyBackup) throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { finish() }
        do {
            var value = try repository.loadSupply()
            try mutation(&value)
            try repository.saveSupply(value)
            backup = value
        } catch {
            status = "Failed: \(error.localizedDescription)"
            return false
        }
        await reconcileLocked(requestPermission: requestPermission)
        return true
    }

    func save(_ entry: SupplyReminderEntry) async -> Bool {
        await change(requestPermission: true) { value in
            if var document = value.reminder {
                document.replace(with: entry, at: now())
                value.reminder = document
            } else {
                var entry = entry
                entry.changedAt = now()
                value.reminder = SupplyReminderDocument(current: entry)
            }
        }
    }

    func setHandledOrDisabled(handled: Bool) async {
        await change { value in
            guard var document = value.reminder else { return }
            var entry = document.current
            entry.enabled = false
            entry.handledAt = handled ? now() : nil
            document.replace(with: entry, at: now(), source: handled ? "handled" : "disabled")
            value.reminder = document
        }
    }

    func recordBottleStart(at date: Date) async -> Bool {
        await change { value in
            guard date <= now() else { throw SupplyStorageError.invalid }
            value.bottleStarts.append(SupplyBottleStart(openedAt: date, recordedAt: now()))
        }
    }

    private func finish() {
        isBusy = false
        if reconcileAgain {
            reconcileAgain = false
            Task { await reconcile() }
        }
    }

    private func cancel() {
        client.removePendingRequests(withIdentifiers: [Self.requestID])
        client.removeDeliveredNotifications(withIdentifiers: [Self.requestID])
    }

    private func stillCurrent(_ generation: UInt) -> Bool {
        guard generation == repository.supplyGeneration else {
            cancel()
            status = "Needs attention: supply information changed; checking again."
            reconcileAgain = true
            return false
        }
        return true
    }

    private func reconcileLocked(requestPermission: Bool) async {
        needsSettings = false
        status = "Checking reminder…"
        do {
            backup = try repository.loadSupply()
            let generation = repository.supplyGeneration
            guard let entry = backup?.reminder?.current else {
                cancel(); status = "Disabled — no reminder set"; return
            }
            guard entry.enabled, entry.handledAt == nil else {
                cancel()
                status = entry.handledAt == nil ? "Disabled" : "Handled — acknowledged in DoseTap"
                return
            }
            let zone = timeZone()
            guard let fireDate = entry.fireDate(in: zone) else {
                cancel(); status = "Needs attention: this local time does not exist. Choose another time."; return
            }
            guard fireDate > now() else {
                cancel(); status = "Needs attention: reminder date has arrived. Mark handled or choose a new date."; return
            }
            var authorization = await client.authorizationStatus()
            guard stillCurrent(generation) else { return }
            if authorization == .notDetermined && requestPermission {
                _ = try await client.requestAuthorization(options: [.alert, .sound])
                guard stillCurrent(generation) else { return }
                authorization = await client.authorizationStatus()
                guard stillCurrent(generation) else { return }
            }
            guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral else {
                cancel(); needsSettings = authorization == .denied
                status = "Needs attention: allow notifications to schedule this reminder."
                return
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
            parts.timeZone = zone
            parts.calendar = calendar
            let content = UNMutableNotificationContent()
            content.title = "DoseTap"
            content.body = "DoseTap reminder due."
            content.sound = .default
            content.userInfo = ["supplyRevision": entry.revision.uuidString]
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger)
            let pending = await client.pendingRequests()
            guard stillCurrent(generation) else { return }
            if !pending.contains(where: { matches($0, expected: request, fireDate: fireDate) }) {
                // Replacing this stable identifier cannot touch a medication alarm.
                cancel()
                try await client.add(request)
                guard stillCurrent(generation) else { return }
            }
            let verified = await client.pendingRequests()
            guard stillCurrent(generation) else { return }
            guard verified.contains(where: { matches($0, expected: request, fireDate: fireDate) }) else {
                cancel(); status = "Failed: iOS did not confirm the reminder. Retry scheduling."; return
            }
            status = "Scheduled: \(fireDate.formatted(date: .abbreviated, time: .shortened)) (\(zone.identifier))"
        } catch {
            cancel()
            status = "Failed: \(error.localizedDescription) Retry scheduling."
        }
    }

    private func matches(_ actual: UNNotificationRequest, expected: UNNotificationRequest, fireDate: Date) -> Bool {
        guard actual.identifier == Self.requestID,
              actual.content.userInfo["supplyRevision"] as? String == expected.content.userInfo["supplyRevision"] as? String,
              actual.content.body == expected.content.body,
              let trigger = actual.trigger as? UNCalendarNotificationTrigger,
              let expectedTrigger = expected.trigger as? UNCalendarNotificationTrigger,
              !trigger.repeats, trigger.dateComponents == expectedTrigger.dateComponents,
              let next = trigger.nextTriggerDate() else { return false }
        return abs(next.timeIntervalSince(fireDate)) < 1
    }
}
