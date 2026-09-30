import Foundation

public struct DaytimeAnchorSource: Codable, Equatable, Sendable {
    public let id: String
    public let revision: String
    public let at: Date
    public let endAt: Date?
    public init(id: String, revision: String, at: Date, endAt: Date? = nil) throws {
        guard !id.isEmpty, !revision.isEmpty, id.count <= 256, revision.count <= 256,
              [at, endAt].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              endAt.map({ $0 > at }) ?? true else { throw DaytimeDiaryError.invalid }
        self.id = id; self.revision = revision; self.at = DaytimePromptLedger.canonicalDate(at)
        self.endAt = endAt.map(DaytimePromptLedger.canonicalDate)
    }
}
public struct DaytimePromptAnchorContext: Equatable, Sendable {
    public let dayKey: String
    public let timeZone: String
    public let working: Bool?
    public let mainWake: DaytimeAnchorSource?
    public let shift: DaytimeAnchorSource?
    public let plannedBreak: DaytimeAnchorSource?
    public let workSourceID: String?
    public let workRevision: String?
    public init(dayKey: String, timeZone: String, working: Bool? = nil, mainWake: DaytimeAnchorSource? = nil,
                shift: DaytimeAnchorSource? = nil, plannedBreak: DaytimeAnchorSource? = nil,
                workSourceID: String? = nil, workRevision: String? = nil) {
        self.dayKey = dayKey; self.timeZone = timeZone; self.working = working
        self.mainWake = mainWake; self.shift = shift; self.plannedBreak = plannedBreak
        self.workSourceID = workSourceID; self.workRevision = workRevision
    }
}
public struct DaytimePromptAnchorResolution: Codable, Equatable, Sendable {
    public let intendedAt: Date?
    public let sourceID: String?
    public let sourceRevision: String?
    public let sourceAt: Date?
    public let label: String
    public let unavailableReason: String?
    public var kind: DaytimePromptRule.Anchor?
    public var sourceEndAt: Date?
    public var working: Bool?
    public var workSourceID: String?
    public var workRevision: String?
}
public struct DaytimePromptRule: Codable, Equatable, Sendable {
    public enum Anchor: String, Codable, CaseIterable, Sendable {
        case clock, mainWake, shiftMidpoint, shiftBreak
        public var title: String {
            switch self { case .clock: return "Clock time"; case .mainWake: return "After main wake"
            case .shiftMidpoint: return "Saved shift midpoint"; case .shiftBreak: return "Saved shift break" }
        }
    }
    public let anchor: Anchor
    public let selectedWeekdays: [Int]
    public let wakeOffsetMinutes: Int
    public let offDayAnchor: Anchor
    public let offDayHour: Int
    public let offDayMinute: Int
    public init(anchor: Anchor, selectedWeekdays: Set<Int> = Set(1...7), wakeOffsetMinutes: Int = 240,
                offDayAnchor: Anchor = .clock, offDayHour: Int = 14, offDayMinute: Int = 0) throws {
        guard !selectedWeekdays.isEmpty, selectedWeekdays.allSatisfy({ (1...7).contains($0) }),
              (0...1440).contains(wakeOffsetMinutes), [.clock, .mainWake].contains(offDayAnchor),
              (0...23).contains(offDayHour), (0...59).contains(offDayMinute) else { throw DaytimeDiaryError.invalid }
        self.anchor = anchor; self.selectedWeekdays = selectedWeekdays.sorted(); self.wakeOffsetMinutes = wakeOffsetMinutes
        self.offDayAnchor = offDayAnchor; self.offDayHour = offDayHour; self.offDayMinute = offDayMinute
    }
    public func validate() throws {
        _ = try Self(anchor: anchor, selectedWeekdays: Set(selectedWeekdays), wakeOffsetMinutes: wakeOffsetMinutes,
                     offDayAnchor: offDayAnchor, offDayHour: offDayHour, offDayMinute: offDayMinute)
        guard selectedWeekdays == Set(selectedWeekdays).sorted() else { throw DaytimeDiaryError.invalid }
    }
    public static func dayKey(_ date: Date, timeZone: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: timeZone)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    public func resolve(day: Date, clockHour: Int, clockMinute: Int, timeZone: String,
                        context: DaytimePromptAnchorContext?, now: Date) -> DaytimePromptAnchorResolution {
        func unavailable(_ text: String) -> DaytimePromptAnchorResolution {
            .init(intendedAt: nil, sourceID: nil, sourceRevision: nil, sourceAt: nil, label: anchor.title, unavailableReason: text)
        }
        guard let zone = TimeZone(identifier: timeZone), (try? validate()) != nil,
              (0...23).contains(clockHour), (0...59).contains(clockMinute) else { return unavailable("Invalid saved reminder rule") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard selectedWeekdays.contains(calendar.component(.weekday, from: day)) else { return unavailable("Weekday not selected") }
        let evidence = context.flatMap { $0.dayKey == Self.dayKey(day, timeZone: timeZone) && $0.timeZone == timeZone ? $0 : nil }
        var selected = anchor, label = anchor.title, hour = clockHour, minute = clockMinute
        if [.shiftMidpoint, .shiftBreak].contains(anchor) {
            guard let working = evidence?.working else { return unavailable("Work or off-day status needs review") }
            if !working { selected = offDayAnchor; label = "Off-day: " + selected.title; hour = offDayHour; minute = offDayMinute }
        }
        var date: Date?, source: DaytimeAnchorSource?
        switch selected {
        case .clock:
            date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first)
        case .mainWake:
            guard let wake = evidence?.mainWake, wake.at <= now,
                  Self.dayKey(wake.at, timeZone: timeZone) == Self.dayKey(day, timeZone: timeZone) else {
                return unavailable("Designated main-wake observation unavailable")
            }
            source = wake; date = wake.at.addingTimeInterval(Double(wakeOffsetMinutes) * 60)
            label += " + \(wakeOffsetMinutes) min"
        case .shiftMidpoint:
            guard let shift = evidence?.shift, let end = shift.endAt, end > shift.at else { return unavailable("Reviewed shift start and end unavailable") }
            source = shift; date = shift.at.addingTimeInterval(end.timeIntervalSince(shift.at) / 2)
        case .shiftBreak:
            guard let plannedBreak = evidence?.plannedBreak else { return unavailable("Reviewed shift break unavailable") }
            source = plannedBreak; date = plannedBreak.at
        }
        guard let date else { return unavailable("Anchor time could not be resolved") }
        return .init(intendedAt: DaytimePromptLedger.canonicalDate(date), sourceID: source?.id, sourceRevision: source?.revision,
                     sourceAt: source?.at, label: label, unavailableReason: nil, kind: selected, sourceEndAt: source?.endAt,
                     working: evidence?.working, workSourceID: evidence?.workSourceID, workRevision: evidence?.workRevision)
    }
}
