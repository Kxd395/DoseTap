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
    @Published private var verifiedAttempts: [Date] = []
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var notificationPermission: UNAuthorizationStatus?
    @Published private(set) var hasLoadedLedger = false
    var scheduledThrough: Date? { verifiedAttempts.last }
    var nextReminderAt: Date? { verifiedAttempts.first { $0 > now() } }
    @Published private(set) var anchorAvailability: [String] = []
    @Published var promptToOpen: DaytimePrompt?
    private let repository: SessionRepository
    private let client: AlarmNotificationCenterClient
    private let now: () -> Date
    private let contextProvider: (DaytimePromptSchedule, DaytimePromptLedger, Date) throws -> [DaytimePromptAnchorContext]
    private var again = false
    private var actions: [(UUID, String, CheckedContinuation<Void, Never>)] = []
    private let log = Logger(subsystem: "com.dosetap.app", category: "DaytimePrompt")
    init(repository: SessionRepository, client: AlarmNotificationCenterClient, now: @escaping () -> Date = Date.init,
         contexts: ((DaytimePromptSchedule, DaytimePromptLedger, Date) throws -> [DaytimePromptAnchorContext])? = nil) {
        self.repository = repository; self.client = client; self.now = now
        contextProvider = contexts ?? { try repository.daytimePromptContexts(for: $0, ledger: $1, asOf: $2) }
    }
    var permitsForegroundPresentation: Bool {
        guard let value = try? repository.daytimePrompts(), value.enabled, !repository.daytimePromptSleepActive,
              let zone = value.current.flatMap({ TimeZone(identifier: $0.timeZone) }) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let minute = calendar.component(.hour, from: now()) * 60 + calendar.component(.minute, from: now())
        return !DaytimePromptSchedule.isQuiet(minute: minute, start: value.quietStart, end: value.quietEnd)
    }
    func protocolLabel(for prompt: DaytimePrompt) -> String {
        guard let schedule = ledger.schedules.first(where: { $0.id == prompt.scheduleID }),
              let zone = TimeZone(identifier: schedule.timeZone) else { return "Schedule definition unavailable" }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let weekdays = schedule.rule?.selectedWeekdays ?? Array(1...7)
        let days = weekdays.count == 7 ? "Every day" : weekdays.map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        let clock = String(format: "%02d:%02d", calendar.component(.hour, from: prompt.intendedAt), calendar.component(.minute, from: prompt.intendedAt))
        let fixedTime = prompt.anchor == nil || prompt.anchor?.kind == .clock ? " \(clock)" : ""
        return "\(prompt.anchor?.label ?? "Clock time")\(fixedTime) · \(days) · \(schedule.timeZone)"
    }
    func reconcile() async { _ = await change { _ in } }
    @discardableResult func change(requestPermission: Bool = false, _ mutation: (inout DaytimePromptLedger) throws -> Void) async -> Bool {
        guard !isBusy else { again = true; return false }
        isBusy = true; anchorAvailability = []; verifiedAttempts = []
        notificationPermission = nil
        hasLoadedLedger = false
        defer {
            lastCheckedAt = now()
            isBusy = false
            if !actions.isEmpty {
                let next = actions.removeFirst(); Task { await handle(promptID: next.0, action: next.1); next.2.resume() }
            } else if again { again = false; Task { await reconcile() } }
        }
        do {
            var value = try repository.daytimePrompts()
            ledger = value; hasLoadedLedger = true
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
            notificationPermission = permission
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
            guard let schedule = value.current, let zone = TimeZone(identifier: schedule.timeZone) else { throw DaytimeDiaryError.invalid }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let sampledAt = now(), contexts = try contextProvider(schedule, value, now())
            _ = value.prepareHorizon(at: sampledAt, contexts: contexts)
            for assessment in try repository.daytimeCheckIns().revisions where assessment.predecessorID == nil && assessment.promptID == nil && assessment.origin != .retrospective && assessment.status != .incomplete {
                try value.satisfyRandomizedWindow(assessmentID: assessment.id, assessedAt: assessment.assessedAt, recordedAt: assessment.recordedAt)
            }
            let upcoming = value.prepareHorizon(at: sampledAt, contexts: contexts)
            if let rule = schedule.rule {
                let grouped = Dictionary(grouping: contexts, by: \.dayKey)
                anchorAvailability = (0...7).compactMap { offset in
                    guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: sampledAt)),
                          rule.selectedWeekdays.contains(calendar.component(.weekday, from: day)) else { return nil }
                    let key = DaytimePromptRule.dayKey(day, timeZone: schedule.timeZone), candidates = grouped[key] ?? []
                    let resolution = rule.resolve(day: day, clockHour: schedule.hour, clockMinute: schedule.minute,
                        timeZone: schedule.timeZone, context: candidates.count == 1 ? candidates.first : nil, now: sampledAt)
                    if rule.randomizedWake != nil && candidates.first?.working == nil { return "\(key): not queued — work or off-day status needs review." }
                    if let reason = resolution.unavailableReason { return "\(key): not queued — \(reason)." }
                    if rule.randomizedWake == nil, let intended = resolution.intendedAt, intended <= sampledAt { return "\(key): selected anchor has passed; no new reminder queued." }
                    return nil
                }
            }
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
            guard try repository.daytimePrompts().encodedPayload() == value.encodedPayload(),
                  try contextProvider(schedule, value, now()) == contexts else { throw DaytimeDiaryError.conflict }
            var triggerCalendar = Calendar(identifier: .gregorian)
            triggerCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
            for prompt in eligible {
                let content = UNMutableNotificationContent()
                content.title = "DoseTap"; content.body = "Your optional check-in is ready when it is safe to pause."
                content.categoryIdentifier = Self.categoryID; content.interruptionLevel = .passive
                content.userInfo = ["prompt_id": prompt.id.uuidString]
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerCalendar.dateComponents([.timeZone, .year, .month, .day, .hour, .minute, .second], from: prompt.nextAttemptAt), repeats: false)
                try await client.add(UNNotificationRequest(identifier: Self.requestID + "." + prompt.id.uuidString, content: content, trigger: trigger))
            }
            guard try repository.daytimePrompts().encodedPayload() == value.encodedPayload(),
                  try contextProvider(schedule, value, now()) == contexts else { throw DaytimeDiaryError.conflict }
            let pending = await client.pendingRequests()
            guard Set(pending.filter { Self.owns($0.identifier) }.map(\.identifier)) == Set(eligible.map { Self.requestID + "." + $0.id.uuidString }),
                  try repository.daytimePrompts().encodedPayload() == value.encodedPayload(),
                  try contextProvider(schedule, value, now()) == contexts, eligible.allSatisfy({ prompt in
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
                status = eligible.isEmpty ? "No reminders queued. Review available anchors, selected days and quiet hours." : (schedule.rule?.randomizedWake != nil ? "Wake-based check-ins queued for recorded wake days. Record your next main wake to schedule that day. Delivery is controlled by iOS." : "Routine reminders queued for up to seven days. Delivery is controlled by iOS.")
            }
            try repository.saveDaytimePrompts(value); ledger = value
            if !repository.daytimePromptSleepActive {
                verifiedAttempts = eligible.map(\.nextAttemptAt).sorted()
            }
            return true
        } catch {
            try? await cancelOwnedRequests()
            hasLoadedLedger = false
            if let current = try? repository.daytimePrompts() {
                ledger = current; hasLoadedLedger = true
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
        verifiedAttempts = []
        guard await client.pendingRequests().allSatisfy({ !Self.owns($0.identifier) }) else { throw DaytimeDiaryError.notCommitted }
    }
    nonisolated static func owns(_ identifier: String) -> Bool {
        identifier == requestID || identifier.hasPrefix(requestID + ".")
    }
    func handle(promptID: UUID, action: String) async {
        guard [UNNotificationDefaultActionIdentifier, "open", "daytime_skip", "daytime_later"].contains(action) else { return }
        if isBusy { await withCheckedContinuation { actions.append((promptID, action, $0)) }; return }
        if action == "daytime_later" {
            do {
                var preview = try repository.daytimePrompts()
                try preview.deferPrompt(id: promptID, until: Date(timeIntervalSince1970: ceil(now().timeIntervalSince1970 + 1800)), now: now())
            } catch {
                status = "This check-in cannot be postponed within its window. Check in now or skip it."
                return
            }
        }
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
