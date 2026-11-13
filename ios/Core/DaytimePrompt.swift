import Foundation

public struct DaytimePromptSchedule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let hour: Int
    public let minute: Int
    public let timeZone: String
    public let createdAt: Date
    public let rule: DaytimePromptRule?
    public init(hour: Int, minute: Int, timeZone: String, createdAt: Date, rule: DaytimePromptRule? = nil) throws {
        guard (0...23).contains(hour), (0...59).contains(minute), TimeZone(identifier: timeZone) != nil,
              createdAt.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.invalid }
        try rule?.validate(); self.rule = rule
        id = UUID(); self.hour = hour; self.minute = minute; self.timeZone = timeZone; self.createdAt = DaytimePromptLedger.canonicalDate(createdAt)
    }
    public func next(after date: Date) -> Date? {
        guard let zone = TimeZone(identifier: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute),
                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }
    public static func isQuiet(minute: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        return start < end ? (start..<end).contains(minute) : minute >= start || minute < end
    }
}

public struct DaytimePrompt: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, deferred, suppressed, skipped, expired, responded }
    public let id: UUID
    public let scheduleID: UUID
    public let intendedAt: Date
    public var nextAttemptAt: Date
    public var status: Status = .pending
    public var reason: String?
    public var openedAt: Date?
    public var respondedAt: Date?
    public var assessedAt: Date?
    public var assessmentID: UUID?
    public var anchor: DaytimePromptAnchorResolution?
    public var anchorDayKey: String?
    public var windowIndex: Int?
    public var windowStart: Date?
    public var windowEnd: Date?
    public enum EnvironmentalSuppression: String {
        case permission = "Notification permission unavailable"
        case quietHours = "Inside configured quiet hours"
        case knownSleep = "Known sleep or nap active"
    }
    public var environmentalSuppression: EnvironmentalSuppression? {
        status == .suppressed ? reason.flatMap(EnvironmentalSuppression.init(rawValue:)) : nil
    }
    public var isOutstanding: Bool { status == .pending || status == .deferred }
}

public struct DaytimePromptLedger: Codable, Equatable, Sendable {
    public var enabled = false
    public var quietStart = 1320
    public var quietEnd = 420
    public private(set) var schedules: [DaytimePromptSchedule] = []
    public private(set) var prompts: [DaytimePrompt] = []
    public var current: DaytimePromptSchedule? { schedules.last }
    public init() {}
    public mutating func configure(hour: Int, minute: Int, timeZone: String, enabled: Bool, at: Date, rule: DaytimePromptRule? = nil) throws {
        let schedule = try DaytimePromptSchedule(hour: hour, minute: minute, timeZone: timeZone, createdAt: at, rule: rule)
        suppress(reason: "Schedule changed", at: at)
        schedules.append(schedule); self.enabled = enabled
    }
    @discardableResult public mutating func prepare(at now: Date) -> DaytimePrompt? {
        for index in prompts.indices where prompts[index].isOutstanding && now.timeIntervalSince(prompts[index].nextAttemptAt) >= 86400 {
            prompts[index].status = .expired; prompts[index].reason = "No response recorded"
        }
        guard enabled, let schedule = current else { return nil }
        if schedule.rule != nil { return prepareHorizon(at: now).first }
        if let existing = prompts.last(where: { $0.isOutstanding }) { return existing }
        // An explicit skip/suppression never creates another slot on the same civil day.
        let after = max(now, prompts.filter { $0.scheduleID == schedule.id }.map(\.intendedAt).max() ?? now)
        guard let intended = schedule.next(after: after) else { return nil }
        let prompt = DaytimePrompt(id: UUID(), scheduleID: schedule.id, intendedAt: intended, nextAttemptAt: intended)
        prompts.append(prompt); return prompt
    }
    public mutating func prepareHorizon(at now: Date, contexts: [DaytimePromptAnchorContext] = []) -> [DaytimePrompt] {
        guard enabled, let schedule = current else { return [] }
        for index in prompts.indices where prompts[index].isOutstanding && now.timeIntervalSince(prompts[index].nextAttemptAt) >= 86400 {
            prompts[index].status = .expired; prompts[index].reason = "No response recorded"
        }
        for index in prompts.indices where prompts[index].scheduleID == schedule.id && prompts[index].status == .suppressed
            && prompts[index].nextAttemptAt > now
            && prompts[index].environmentalSuppression != nil {
            prompts[index].status = .pending; prompts[index].reason = nil
        }
        if schedule.rule?.randomizedWake != nil { return prepareRandomizedHorizon(schedule: schedule, at: now, contexts: contexts) }
        if schedule.rule != nil { return prepareAnchoredHorizon(schedule: schedule, at: now, contexts: contexts) }
        var cursor = now
        for _ in 0..<7 {
            guard let date = schedule.next(after: cursor) else { break }
            if !prompts.contains(where: { $0.scheduleID == schedule.id && $0.intendedAt == date }) {
                let stamp = UInt64(bitPattern: Int64(date.timeIntervalSince1970)) & 0xFFFFFFFFFFFF
                guard let id = UUID(uuidString: String(schedule.id.uuidString.prefix(24)) + String(format: "%012llx", stamp)) else { break }
                prompts.append(DaytimePrompt(id: id, scheduleID: schedule.id, intendedAt: date, nextAttemptAt: date))
            }
            cursor = date
        }
        return Array(prompts.filter { $0.scheduleID == schedule.id && $0.isOutstanding && $0.nextAttemptAt > now }
            .sorted { $0.nextAttemptAt < $1.nextAttemptAt }.prefix(7))
    }
    private mutating func prepareAnchoredHorizon(schedule: DaytimePromptSchedule, at now: Date,
                                                 contexts: [DaytimePromptAnchorContext]) -> [DaytimePrompt] {
        guard now.timeIntervalSince1970.isFinite, let rule = schedule.rule,
              let zone = TimeZone(identifier: schedule.timeZone) else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 7, to: now) else { return [] }
        let grouped = Dictionary(grouping: contexts, by: \.dayKey)
        for offset in -1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let key = DaytimePromptRule.dayKey(day, timeZone: schedule.timeZone)
            let candidates = grouped[key] ?? []
            let resolution = rule.resolve(day: day, clockHour: schedule.hour, clockMinute: schedule.minute,
                timeZone: schedule.timeZone, context: candidates.count == 1 ? candidates.first : nil, now: now)
            let previous = prompts.indices.filter { prompts[$0].scheduleID == schedule.id && prompts[$0].anchorDayKey == key }
            if let index = previous.last {
                let old = prompts[index]
                // Never turn a potentially delivered slot or an explicit outcome into a second routine prompt.
                if old.intendedAt <= now || old.status == .responded || old.status == .skipped { continue }
                if old.anchor == resolution && old.isOutstanding { continue }
                let changedIdentity = old.anchor?.kind == .mainWake && resolution.kind == .mainWake && old.anchor?.sourceID != resolution.sourceID
                if old.isOutstanding {
                    prompts[index].status = .suppressed
                    prompts[index].reason = changedIdentity ? "Original main-wake source unavailable; review the routine" :
                        (resolution.unavailableReason ?? "Anchor evidence changed")
                }
                if changedIdentity { continue }
            }
            guard let intended = resolution.intendedAt, intended > now, intended <= end else { continue }
            // Stable schedule/day/revision identity, independent of process-randomized Swift hashing.
            var hash: UInt64 = 14695981039346656037
            for byte in "\(key)#\(previous.count)".utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
            guard let id = UUID(uuidString: String(schedule.id.uuidString.prefix(24)) + String(format: "%012llx", hash & 0xFFFFFFFFFFFF)),
                  !prompts.contains(where: { $0.id == id }) else { continue }
            let attempt = Date(timeIntervalSince1970: ceil(intended.timeIntervalSince1970))
            prompts.append(DaytimePrompt(id: id, scheduleID: schedule.id, intendedAt: intended, nextAttemptAt: attempt,
                                        anchor: resolution, anchorDayKey: key))
        }
        return Array(prompts.filter { $0.scheduleID == schedule.id && $0.isOutstanding && $0.nextAttemptAt > now && $0.nextAttemptAt <= end }
            .sorted { $0.nextAttemptAt < $1.nextAttemptAt }.prefix(7))
    }
    private mutating func prepareRandomizedHorizon(schedule: DaytimePromptSchedule, at now: Date,
                                                   contexts: [DaytimePromptAnchorContext]) -> [DaytimePrompt] {
        guard now.timeIntervalSince1970.isFinite, let rule = schedule.rule, let routine = rule.randomizedWake,
              let zone = TimeZone(identifier: schedule.timeZone) else { return [] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let grouped = Dictionary(grouping: contexts, by: \.dayKey)
        for offset in -1...0 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let key = DaytimePromptRule.dayKey(day, timeZone: schedule.timeZone)
            let matches = grouped[key] ?? []
            let context = matches.count == 1 ? matches.first : nil
            let resolution = rule.resolve(day: day, clockHour: schedule.hour, clockMinute: schedule.minute,
                                          timeZone: schedule.timeZone, context: context, now: now)
            let previous = prompts.indices.filter { prompts[$0].scheduleID == schedule.id && prompts[$0].anchorDayKey == key }
            if !previous.isEmpty {
                for index in previous where prompts[index].isOutstanding && prompts[index].nextAttemptAt > now {
                    let old = prompts[index].anchor
                    if resolution.intendedAt == nil || context?.working == nil || old?.sourceID != resolution.sourceID ||
                        old?.sourceRevision != resolution.sourceRevision || old?.sourceAt != resolution.sourceAt ||
                        old?.working != context?.working || old?.workSourceID != context?.workSourceID || old?.workRevision != context?.workRevision {
                        prompts[index].status = .suppressed; prompts[index].reason = "Wake or work evidence changed; review the routine"
                    }
                }
                continue
            }
            guard resolution.intendedAt != nil, let wake = resolution.sourceAt, let working = context?.working,
                  let cutoff = routine.cutoff(wake: wake, working: working, timeZone: schedule.timeZone) else { continue }
            var last: Date?
            for (index, window) in routine.windows(working: working).enumerated() {
                let lower = wake.addingTimeInterval(Double(window.lowerBound * 60))
                let upper = min(wake.addingTimeInterval(Double(window.upperBound * 60)), cutoff)
                let start = Date(timeIntervalSince1970: ceil(max(lower, last?.addingTimeInterval(7200) ?? lower).timeIntervalSince1970))
                guard start <= upper else { continue }
                let seed = RandomizedWakeRoutine.hash("\(schedule.id)#\(key)#\(index)")
                let minutes = Int(upper.timeIntervalSince(start) / 60)
                let choices = minutes + 1
                let firstChoice = Int(seed % UInt64(choices))
                guard let intended = (0..<choices).lazy.map({ offset in
                    start.addingTimeInterval(Double((firstChoice + offset) % choices) * 60)
                }).first(where: { candidate in
                    prompts.filter { $0.scheduleID == schedule.id && $0.windowIndex != nil }
                        .allSatisfy { abs($0.nextAttemptAt.timeIntervalSince(candidate)) >= 7200 }
                }) else { continue }
                last = intended
                guard intended > now, intended <= upper else { continue }
                // Saving a different routine cannot repeat an already attempted or explicitly resolved window.
                guard !prompts.contains(where: { $0.anchorDayKey == key && $0.windowIndex == index &&
                    ($0.intendedAt <= now || $0.status == .responded || $0.status == .skipped) }) else { continue }
                guard let id = UUID(uuidString: String(schedule.id.uuidString.prefix(24)) + String(format: "%012llx", seed & 0xFFFFFFFFFFFF)) else { continue }
                let anchor = DaytimePromptAnchorResolution(intendedAt: intended, sourceID: resolution.sourceID,
                    sourceRevision: resolution.sourceRevision, sourceAt: wake,
                    label: "\(working ? "Workday" : "Off-day") check-in \(index + 1) · after main wake", unavailableReason: nil,
                    kind: .mainWake, working: working, workSourceID: context?.workSourceID, workRevision: context?.workRevision)
                prompts.append(DaytimePrompt(id: id, scheduleID: schedule.id, intendedAt: intended, nextAttemptAt: intended,
                    anchor: anchor, anchorDayKey: key, windowIndex: index, windowStart: lower, windowEnd: upper))
            }
        }
        reconcileRandomizedSpacing(scheduleID: schedule.id, at: now)
        return Array(prompts.filter { $0.scheduleID == schedule.id && $0.isOutstanding && $0.nextAttemptAt > now }
            .sorted { $0.nextAttemptAt < $1.nextAttemptAt }.prefix(7))
    }
    private mutating func reconcileRandomizedSpacing(scheduleID: UUID, at now: Date) {
        // Read old plans without redrawing them. Preserve all potentially delivered history.
        var last = prompts.filter { $0.scheduleID == scheduleID && $0.windowIndex != nil && $0.nextAttemptAt <= now }
            .map(\.nextAttemptAt).max()
        let future = prompts.indices.filter { prompts[$0].scheduleID == scheduleID && prompts[$0].windowIndex != nil &&
            prompts[$0].isOutstanding && prompts[$0].nextAttemptAt > now }.sorted {
                let left = prompts[$0], right = prompts[$1]
                return left.nextAttemptAt == right.nextAttemptAt ? left.id.uuidString < right.id.uuidString : left.nextAttemptAt < right.nextAttemptAt
            }
        for index in future {
            if let prior = last, prompts[index].nextAttemptAt.timeIntervalSince(prior) < 7200 {
                prompts[index].status = .suppressed; prompts[index].reason = "Spacing conflict; review the routine"
            } else { last = prompts[index].nextAttemptAt }
        }
    }
    public mutating func satisfyRandomizedWindow(assessmentID: UUID, assessedAt: Date, recordedAt: Date) throws {
        guard let index = prompts.firstIndex(where: { $0.scheduleID == current?.id && ($0.isOutstanding || $0.environmentalSuppression != nil) &&
            $0.windowStart.map { assessedAt >= $0 } == true && $0.windowEnd.map { assessedAt <= $0 } == true }) else { return }
        try respond(id: prompts[index].id, assessmentID: assessmentID, assessedAt: assessedAt, at: recordedAt)
    }
    public mutating func suppressDue(at now: Date, reason _: String) {
        for index in prompts.indices where prompts[index].isOutstanding && prompts[index].nextAttemptAt <= now {
            prompts[index].status = .expired; prompts[index].reason = "No response recorded; earlier delivery unknown"
        }
    }
    public mutating func suppress(id: UUID, reason: String) {
        guard let index = prompts.firstIndex(where: { $0.id == id }), prompts[index].isOutstanding else { return }
        prompts[index].status = .suppressed; prompts[index].reason = reason
    }
    public mutating func suppress(reason: String, at: Date) {
        for index in prompts.indices where prompts[index].isOutstanding && prompts[index].nextAttemptAt > at {
            prompts[index].status = .suppressed; prompts[index].reason = reason
        }
    }
    public mutating func open(id: UUID, at: Date) throws {
        guard let index = prompts.firstIndex(where: { $0.id == id }), prompts[index].status != .responded else { throw DaytimeDiaryError.conflict }
        guard at.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.invalid }
        if prompts[index].openedAt == nil { prompts[index].openedAt = Self.canonicalDate(at) }
    }
    public mutating func skip(id: UUID) throws {
        guard let index = prompts.firstIndex(where: { $0.id == id }), prompts[index].isOutstanding else { throw DaytimeDiaryError.conflict }
        prompts[index].status = .skipped; prompts[index].reason = "Skipped by user"
    }
    public mutating func deferPrompt(id: UUID, until: Date, now: Date) throws {
        guard until.timeIntervalSince1970.isFinite, now.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.invalid }
        let attempt = Self.canonicalDate(until)
        guard let index = prompts.firstIndex(where: { $0.id == id }), prompts[index].isOutstanding,
              attempt > now else { throw DaytimeDiaryError.invalid }
        if let end = prompts[index].windowEnd {
            guard attempt <= end, attempt >= (prompts[index].windowStart ?? attempt), prompts.filter({ $0.id != id && $0.scheduleID == prompts[index].scheduleID && $0.windowIndex != nil })
                .allSatisfy({ abs($0.nextAttemptAt.timeIntervalSince(attempt)) >= 7200 }) else { throw DaytimeDiaryError.invalid }
        }
        prompts[index].status = .deferred; prompts[index].nextAttemptAt = attempt; prompts[index].reason = "Deferred by user"
    }
    public mutating func respond(id: UUID, assessmentID: UUID, assessedAt: Date, at: Date) throws {
        guard let index = prompts.firstIndex(where: { $0.id == id }), assessedAt <= at,
              [assessedAt, at].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              prompts[index].assessmentID == nil || (prompts[index].assessmentID == assessmentID && prompts[index].assessedAt == Self.canonicalDate(assessedAt) && prompts[index].respondedAt == Self.canonicalDate(at)) else { throw DaytimeDiaryError.conflict }
        prompts[index].assessmentID = assessmentID; prompts[index].assessedAt = Self.canonicalDate(assessedAt)
        prompts[index].respondedAt = Self.canonicalDate(at); prompts[index].status = .responded
    }
    public func validate() throws {
        guard (0..<1440).contains(quietStart), (0..<1440).contains(quietEnd),
              Set(schedules.map(\.id)).count == schedules.count, Set(prompts.map(\.id)).count == prompts.count else { throw DaytimeDiaryError.invalid }
        for schedule in schedules {
            _ = try DaytimePromptSchedule(hour: schedule.hour, minute: schedule.minute, timeZone: schedule.timeZone, createdAt: schedule.createdAt, rule: schedule.rule)
        }
        for prompt in prompts {
            guard let schedule = schedules.first(where: { $0.id == prompt.scheduleID }),
                  schedule.rule == nil || (prompt.anchor != nil && prompt.anchorDayKey != nil)
            else { throw DaytimeDiaryError.invalid }
            if schedule.rule?.randomizedWake != nil {
                guard let index = prompt.windowIndex, let working = prompt.anchor?.working,
                      schedule.rule!.randomizedWake!.windows(working: working).indices.contains(index),
                      let start = prompt.windowStart, let end = prompt.windowEnd,
                      start <= prompt.intendedAt, prompt.intendedAt <= end, prompt.nextAttemptAt <= end,
                      start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite else { throw DaytimeDiaryError.invalid }
            }
            if let anchor = prompt.anchor {
                guard anchor.intendedAt == prompt.intendedAt, anchor.kind != nil, let key = prompt.anchorDayKey,
                      key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                      [anchor.sourceAt, anchor.sourceEndAt].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite })
                else { throw DaytimeDiaryError.invalid }
            }
            guard schedules.contains(where: { $0.id == prompt.scheduleID }),
                  [prompt.intendedAt, prompt.nextAttemptAt, prompt.openedAt, prompt.assessedAt, prompt.respondedAt].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }),
                  (prompt.assessedAt ?? .distantPast) <= (prompt.respondedAt ?? .distantFuture),
                  prompt.status != .responded || (prompt.assessmentID != nil && prompt.assessedAt != nil && prompt.respondedAt != nil)
            else { throw DaytimeDiaryError.invalid }
        }
    }
}

extension DaytimePromptLedger {
    public static func canonicalDate(_ value: Date) -> Date {
        Date(timeIntervalSince1970: (value.timeIntervalSince1970 * 1000).rounded() / 1000)
    }
    private static func formatter() -> ISO8601DateFormatter {
        let result = ISO8601DateFormatter()
        result.timeZone = TimeZone(secondsFromGMT: 0)
        result.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return result
    }
    public func encodedPayload() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let timestampFormatter = Self.formatter()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestampFormatter.string(from: Self.canonicalDate(date)))
        }
        return try encoder.encode(self)
    }
    public static func decodePayload(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        let timestampFormatter = Self.formatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer(), text = try container.decode(String.self)
            guard text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$"#, options: .regularExpression) != nil,
                  let date = timestampFormatter.date(from: text) else { throw DaytimeDiaryError.invalid }
            let normalized = Self.canonicalDate(date)
            guard timestampFormatter.string(from: normalized) == text else { throw DaytimeDiaryError.invalid }
            return normalized
        }
        let value = try decoder.decode(Self.self, from: data)
        try value.validate(); return value
    }
}
