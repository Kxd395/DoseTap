import Foundation
import Combine
import UserNotifications
import DoseCore
import os.log

@MainActor
final class DaytimePromptService: ObservableObject {
    nonisolated static let requestID = "dosetap_daytime_prompt"
    nonisolated static let categoryID = "DOSETAP_DAYTIME_PROMPT"
    static let shared = DaytimePromptService(repository: .shared, client: SystemAlarmNotificationCenterClient())
    static var category: UNNotificationCategory {
        UNNotificationCategory(identifier: categoryID, actions: [
            UNNotificationAction(identifier: "daytime_later", title: "Remind me later", options: []),
            UNNotificationAction(identifier: "daytime_skip", title: "Skip this check-in", options: [])
        ], intentIdentifiers: [], options: [])
    }
    @Published private(set) var ledger = DaytimePromptLedger()
    @Published private(set) var status = "Not checked"
    @Published private(set) var isBusy = false
    @Published private(set) var scheduledThrough: Date?
    @Published var promptToOpen: DaytimePrompt?
    private let repository: SessionRepository
    private let client: AlarmNotificationCenterClient
    private let now: () -> Date
    private var again = false
    private var actions: [(UUID, String, CheckedContinuation<Void, Never>)] = []
    private let log = Logger(subsystem: "com.dosetap.app", category: "DaytimePrompt")
    init(repository: SessionRepository, client: AlarmNotificationCenterClient, now: @escaping () -> Date = Date.init) {
        self.repository = repository; self.client = client; self.now = now
    }
    var permitsForegroundPresentation: Bool {
        guard let value = try? repository.daytimePrompts(), value.enabled, !repository.daytimePromptSleepActive,
              let zone = value.current.flatMap({ TimeZone(identifier: $0.timeZone) }) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let minute = calendar.component(.hour, from: now()) * 60 + calendar.component(.minute, from: now())
        return !DaytimePromptSchedule.isQuiet(minute: minute, start: value.quietStart, end: value.quietEnd)
    }
    func reconcile() async { _ = await change { _ in } }
    @discardableResult func change(requestPermission: Bool = false, _ mutation: (inout DaytimePromptLedger) throws -> Void) async -> Bool {
        guard !isBusy else { again = true; return false }
        isBusy = true
        defer {
            isBusy = false
            if !actions.isEmpty {
                let next = actions.removeFirst(); Task { await handle(promptID: next.0, action: next.1); next.2.resume() }
            } else if again { again = false; Task { await reconcile() } }
        }
        do {
            var value = try repository.daytimePrompts()
            try mutation(&value)
            // Recover a response committed before a crash or a failed prompt-status write.
            for assessment in try repository.daytimeCheckIns().revisions where assessment.predecessorID == nil {
                if let id = assessment.promptID, value.prompts.contains(where: { $0.id == id && $0.assessmentID == nil }) {
                    try value.respond(id: id, assessmentID: assessment.id, assessedAt: assessment.assessedAt, at: assessment.recordedAt)
                }
            }
            try repository.saveDaytimePrompts(value); ledger = value
            try await cancelOwnedRequests()
            var permission = await client.authorizationStatus()
            if value.enabled && requestPermission && permission == .notDetermined {
                _ = try await client.requestAuthorization(options: [.alert])
                permission = await client.authorizationStatus()
            }
            guard try repository.daytimePrompts().encodedPayload() == value.encodedPayload() else { throw DaytimeDiaryError.conflict }
            guard value.enabled else {
                if let delivered = await client.deliveredIdentifiers() { client.removeDeliveredNotifications(withIdentifiers: delivered.filter { Self.owns($0) }) }
                promptToOpen = nil; status = "Reminders paused"; return true
            }
            guard permission == .authorized || permission == .provisional || permission == .ephemeral else {
                value.suppress(reason: "Notification permission unavailable", at: now())
                try repository.saveDaytimePrompts(value); ledger = value
                status = "Enable notifications in iOS Settings to receive reminders."; return true
            }
            guard !repository.daytimePromptSleepActive else {
                value.suppressDue(at: now(), reason: "Known sleep or nap active")
                try repository.saveDaytimePrompts(value); ledger = value
                status = "Suppressed during known sleep or nap. Rechecked when the app records wake or nap end."; return true
            }
            let upcoming = value.prepareHorizon(at: now())
            guard let schedule = value.current, let zone = TimeZone(identifier: schedule.timeZone) else { throw DaytimeDiaryError.invalid }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let eligible = upcoming.filter { prompt in
                let minute = calendar.component(.hour, from: prompt.nextAttemptAt) * 60 + calendar.component(.minute, from: prompt.nextAttemptAt)
                if DaytimePromptSchedule.isQuiet(minute: minute, start: value.quietStart, end: value.quietEnd) {
                    value.suppress(id: prompt.id, reason: "Inside configured quiet hours"); return false
                }
                return true
            }
            try repository.saveDaytimePrompts(value); ledger = value
            // Preserve capacity for dose requests and all other notification owners.
            let existing = await client.pendingRequests()
            guard existing.count + eligible.count <= 64 else {
                status = "Reminder queue is full. Existing dose reminders were preserved; retry after pending reminders clear."
                return true
            }
            for prompt in eligible {
                let content = UNMutableNotificationContent()
                content.title = "DoseTap"; content.body = "Your optional check-in is ready when it is safe to pause."
                content.categoryIdentifier = Self.categoryID; content.interruptionLevel = .passive
                content.userInfo = ["prompt_id": prompt.id.uuidString]
                let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.timeZone, .year, .month, .day, .hour, .minute, .second], from: prompt.nextAttemptAt), repeats: false)
                try await client.add(UNNotificationRequest(identifier: Self.requestID + "." + prompt.id.uuidString, content: content, trigger: trigger))
            }
            guard try repository.daytimePrompts().encodedPayload() == value.encodedPayload() else { throw DaytimeDiaryError.conflict }
            let pending = await client.pendingRequests()
            guard Set(pending.filter { Self.owns($0.identifier) }.map(\.identifier)) == Set(eligible.map { Self.requestID + "." + $0.id.uuidString }),
                  try repository.daytimePrompts().encodedPayload() == value.encodedPayload(), eligible.allSatisfy({ prompt in
                pending.contains { request in
                    request.identifier == Self.requestID + "." + prompt.id.uuidString
                    && request.content.userInfo["prompt_id"] as? String == prompt.id.uuidString
                    && (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() == prompt.nextAttemptAt
                }
            }) else { throw DaytimeDiaryError.notCommitted }
            if repository.daytimePromptSleepActive {
                try await cancelOwnedRequests()
                guard try repository.daytimePrompts().encodedPayload() == value.encodedPayload() else { throw DaytimeDiaryError.conflict }
                value.suppressDue(at: now(), reason: "Known sleep or nap active")
                status = "Queued reminders paused during known sleep or nap."
            } else {
                scheduledThrough = eligible.last?.nextAttemptAt
                status = eligible.isEmpty ? "No reminders queued: the selected time is inside quiet hours." : "Routine reminders queued for up to seven days. Delivery is controlled by iOS."
            }
            try repository.saveDaytimePrompts(value); ledger = value
            return true
        } catch {
            try? await cancelOwnedRequests()
            if let current = try? repository.daytimePrompts() {
                ledger = current
                if !current.prompts.contains(where: { $0.id == promptToOpen?.id }) { promptToOpen = nil }
            }
            status = "Reminder update failed. Existing records are retained; retry when ready."
            log.error("Daytime reminder update failed")
            return false
        }
    }
    private func cancelOwnedRequests() async throws {
        let requests = await client.pendingRequests()
        client.removePendingRequests(withIdentifiers: requests.map(\.identifier).filter { Self.owns($0) })
        scheduledThrough = nil
        guard await client.pendingRequests().allSatisfy({ !Self.owns($0.identifier) }) else { throw DaytimeDiaryError.notCommitted }
    }
    nonisolated static func owns(_ identifier: String) -> Bool {
        identifier == requestID || identifier.hasPrefix(requestID + ".")
    }
    func handle(promptID: UUID, action: String) async {
        guard [UNNotificationDefaultActionIdentifier, "open", "daytime_skip", "daytime_later"].contains(action) else { return }
        if isBusy { await withCheckedContinuation { actions.append((promptID, action, $0)) }; return }
        let changed = await change { value in
            if action == "daytime_skip" { try value.skip(id: promptID) }
            else if action == "daytime_later" { try value.deferPrompt(id: promptID, until: Date(timeIntervalSince1970: ceil(now().timeIntervalSince1970 + 1800)), now: now()) }
            else { try value.open(id: promptID, at: now()) }
        }
        if changed && action != "daytime_skip" && action != "daytime_later" {
            promptToOpen = ledger.prompts.first { $0.id == promptID }
        }
    }
    func markResponded(_ assessment: DaytimeCheckIn) async {
        guard let id = assessment.promptID else { return }
        _ = await change { try $0.respond(id: id, assessmentID: assessment.id, assessedAt: assessment.assessedAt, at: assessment.recordedAt) }
    }
}
