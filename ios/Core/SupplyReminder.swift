import Foundation

public enum SupplyBackupFileError: LocalizedError, Equatable {
    case invalid
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .invalid: return "The supply backup is invalid."
        case .tooLarge: return "The supply backup is larger than the 10 MB limit."
        }
    }
}

public enum SupplyReminderDateMode: String, Codable, CaseIterable {
    case reminderDate, cycleEnd, receivedDate
}

/// Entered planning values, independent of inventory and medication events.
public struct SupplyReminderEntry: Codable, Equatable {
    public var revision: UUID = UUID()
    public var changedAt: Date = Date()
    public var source = "settings"
    public var mode: SupplyReminderDateMode = .reminderDate
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var leadDays: Int = 7
    public var enabled = true
    public var handledAt: Date?
    public var timeZonePolicy = "current-device-wall-clock-v1"
    public var enteredTimeZoneIdentifier = TimeZone.current.identifier

    public init(year: Int, month: Int, day: Int, hour: Int, minute: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    public var isValid: Bool {
        guard (2000...9999).contains(year), (1...12).contains(month),
              (1...31).contains(day), (0...23).contains(hour),
              (0...59).contains(minute), (0...365).contains(leadDays),
              changedAt.timeIntervalSince1970.isFinite,
              handledAt?.timeIntervalSince1970.isFinite != false,
              timeZonePolicy == "current-device-wall-clock-v1",
              TimeZone(identifier: enteredTimeZoneIdentifier) != nil,
              !source.isEmpty, source.count <= 100 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: parts) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == year && actual.month == month && actual.day == day
    }

    /// Reject missing civil times instead of silently moving the reminder later.
    public func fireDate(in timeZone: TimeZone) -> Date? {
        guard isValid else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let offset = mode == .receivedDate ? 21 : (mode == .cycleEnd ? -leadDays : 0)
        guard let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              let targetDay = calendar.date(byAdding: .day, value: offset, to: noon)
        else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day], from: targetDay)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        let start = calendar.startOfDay(for: targetDay).addingTimeInterval(-1)
        return calendar.nextDate(after: start, matching: parts, matchingPolicy: .strict, repeatedTimePolicy: .first)
    }
}

public struct SupplyBottleStart: Codable, Equatable, Identifiable {
    public var id: UUID
    public var openedAt: Date
    public var recordedAt: Date
    public init(openedAt: Date, recordedAt: Date) {
        id = UUID()
        self.openedAt = openedAt
        self.recordedAt = recordedAt
    }
}

public struct SupplyBackup: Codable, Equatable {
    public static let maximumRecordCount = 10_000
    public var version = 1
    public var reminder: SupplyReminderDocument?
    public var bottleStarts: [SupplyBottleStart] = []
    public init(reminder: SupplyReminderDocument? = nil) { self.reminder = reminder }
    public var isValid: Bool {
        version == 1 && bottleStarts.count <= Self.maximumRecordCount
            && reminder?.isValid != false
            && Set(bottleStarts.map(\.id)).count == bottleStarts.count
            && bottleStarts.allSatisfy {
                $0.openedAt.timeIntervalSince1970.isFinite && $0.recordedAt.timeIntervalSince1970.isFinite
                    && $0.openedAt <= $0.recordedAt
            }
    }
}

/// Backup format includes the source correction lineage, never OS delivery claims.
public struct SupplyReminderDocument: Codable, Equatable {
    public var version = 1
    public var current: SupplyReminderEntry
    public var history: [SupplyReminderEntry] = []

    public init(current: SupplyReminderEntry) { self.current = current }

    public var isValid: Bool {
        guard version == 1, history.count <= SupplyBackup.maximumRecordCount else {
            return false
        }
        let entries = history + [current]
        return entries.allSatisfy(\.isValid)
            && Set(entries.map(\.revision)).count == entries.count
    }

    public mutating func replace(with entry: SupplyReminderEntry, at time: Date, source: String = "settings") {
        history.append(current)
        current = entry
        current.revision = UUID()
        current.changedAt = time
        current.source = source
    }
}

/// Reads at most the configured byte limit plus one sentinel byte. File-provider
/// metadata is advisory and cannot be trusted as the import allocation bound.
public enum SupplyBackupFileCodec {
    public static let maximumBytes = 10_000_000

    public static func decode(
        contentsOf url: URL,
        maximumBytes: Int = maximumBytes
    ) throws -> SupplyBackup {
        guard maximumBytes > 0, maximumBytes < Int.max else {
            throw SupplyBackupFileError.invalid
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        let data = handle.readData(ofLength: maximumBytes + 1)
        guard data.count <= maximumBytes else { throw SupplyBackupFileError.tooLarge }
        let value = try JSONDecoder().decode(SupplyBackup.self, from: data)
        guard value.isValid else { throw SupplyBackupFileError.invalid }
        return value
    }
}
