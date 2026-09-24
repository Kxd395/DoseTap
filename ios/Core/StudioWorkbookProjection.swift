import Foundation
import CoreFoundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum StudioWorkbookProjectionError: Error, LocalizedError {
    case unsupportedBundle, malformedInventory
    public var errorDescription: String? {
        switch self {
        case .unsupportedBundle: return "This Studio bundle has an unsupported or incomplete structure. No workbook was shared."
        case .malformedInventory: return "The inventory table could not be read completely. No workbook was shared."
        }
    }
}

/// A read-only projection of one finalized archive. No storage, settings, provider or clock access.
public enum StudioWorkbookProjection {
    public static func sheets(bundleData: Data, inventoryCSV: String) throws -> [WorkbookSheet] {
        let data = try StudioWorkbookData(bundleData: bundleData, inventoryCSV: inventoryCSV)
        return [data.overviewSheet(), data.doseSummarySheet(), data.medicationLogSheet(), data.nightsSheet(), data.nightReviewSheet(), data.eventsSheet(),
                data.questionnaireSheet(morning: false), data.questionnaireSheet(morning: true),
                data.painSheet(), data.daytimeSheet(), data.sleepMeasuresSheet(), data.sleepIntervalsSheet(),
                data.medicationsSheet(), data.inventorySheet(), data.sourceFieldsSheet(),
                data.reviewIssuesSheet(), data.fieldGuideSheet()]
    }
}

typealias SWObject = [String: Any]

enum SW {
    static func object(_ value: Any?) -> SWObject { value as? SWObject ?? [:] }
    static func objects(_ value: Any?) -> [SWObject] { value as? [SWObject] ?? [] }
    static func string(_ value: Any?) -> String? { value as? String }
    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    static func nonnegative(_ value: Any?) -> Double? { number(value).flatMap { $0 >= 0 && $0 < 1e15 ? $0 : nil } }
    static func boolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return value.boolValue
    }
    static func sha256(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return "SHA-256 unavailable on this runtime"
        #endif
    }
    static func canonical(_ value: Any) -> String {
        guard let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]),
              let text = String(data: bytes, encoding: .utf8) else { return "" }
        return text
    }
    static func parse(_ value: Any?) -> Any? {
        guard let string = value as? String, let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let iso = ISO8601DateFormatter(); iso.formatOptions.insert(.withFractionalSeconds)
        if let date = iso.date(from: text) { return validDate(date) }
        iso.formatOptions.remove(.withFractionalSeconds)
        if let date = iso.date(from: text) { return validDate(date) }
        // SQLite CURRENT_TIMESTAMP values are UTC; only timestamp fields call this fallback.
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return format.date(from: text).flatMap(validDate)
    }
    static func validDate(_ value: Date) -> Date? {
        let seconds = value.timeIntervalSince1970
        return seconds >= -2_208_988_800 && seconds < 253_402_300_800 ? value : nil
    }
    static func day(_ value: String) -> Date? {
        guard value.count == 10 else { return nil }
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "yyyy-MM-dd"; format.isLenient = false
        guard let date = format.date(from: value), format.string(from: date) == value else { return nil }
        return date
    }
    static func local(_ date: Date?, timezone: TimeZone) -> WorkbookCell {
        guard let date else { return .blank }
        let iso = ISO8601DateFormatter(); iso.timeZone = timezone; iso.formatOptions.insert(.withFractionalSeconds)
        return .text(iso.string(from: date))
    }
    static func stamp(_ value: Any?) -> WorkbookCell { date(value).map(WorkbookCell.date) ?? .blank }
    static func duration(_ value: Double?) -> WorkbookCell { value.map(WorkbookCell.durationMinutes) ?? .blank }
    static func numeric(_ value: Double?) -> WorkbookCell { value.map(WorkbookCell.number) ?? .blank }
    static func escapedControls(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { scalar in
            let n = scalar.value
            return (n < 32 && ![9, 10, 13].contains(n)) || n == 0xFFFE || n == 0xFFFF
        }) else { return value }
        return value.unicodeScalars.map { scalar in
            let n = scalar.value
            // Escape literal backslashes too, so a control character and the literal
            // text "\\u0000" remain distinguishable in this labeled representation.
            if n == 92 { return "\\\\" }
            return (n < 32 && ![9, 10, 13].contains(n)) || n == 0xFFFE || n == 0xFFFF
                ? String(format: "\\u%04X", n) : String(scalar)
        }.joined()
    }
    static func chunks(_ value: String, limit: Int = 16_000) -> [String] {
        if value.utf16.count <= limit { return [value] }
        var chunks: [String] = [], current = "", count = 0
        for scalar in value.unicodeScalars {
            let length = scalar.value > 0xFFFF ? 2 : 1
            if count + length > limit { chunks.append(current); current = ""; count = 0 }
            current.unicodeScalars.append(scalar); count += length
        }
        chunks.append(current); return chunks
    }
    static func text(_ value: String?) -> WorkbookCell {
        guard let value else { return .blank }
        let safe = escapedControls(value)
        if safe.utf16.count <= 4_000 { return .text(safe) }
        return .text(chunks(safe, limit: 3_900)[0] + "… [Full value in Source Fields]")
    }
    static func isTimestamp(_ key: String) -> Bool {
        let last = key.components(separatedBy: ".").last ?? key
        return last.hasSuffix("UTC") || last.hasSuffix("_utc") || last.hasSuffix("StoredUTC") ||
            last.hasSuffix("At") || ["timestamp", "created_at", "updated_at", "start", "end", "reviewedAt", "assessedAt"].contains(last)
    }
    static func isID(_ key: String) -> Bool {
        let last = key.components(separatedBy: ".").last ?? key
        return last == "id" || last.hasSuffix("Id") || last.hasSuffix("ID") || last.hasSuffix("_id")
    }
    static func cell(_ value: Any?, key: String = "") -> WorkbookCell {
        guard let value, !(value is NSNull) else { return .blank }
        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .text(value.boolValue ? "true" : "false") }
            if isID(key) || abs(value.doubleValue) >= 1e15 { return text(value.stringValue) }
            return value.doubleValue.isFinite ? .number(value.doubleValue) : text(value.stringValue)
        }
        if let value = value as? String {
            if isTimestamp(key), let date = date(value) { return .date(date) }
            return text(value)
        }
        return text(canonical(value))
    }
    static func strings(_ value: Any?) -> String? {
        if let value = value as? [String] { return value.joined(separator: "; ") }
        return value as? String
    }
    static func table(_ name: String, _ columns: [String], _ rows: [[WorkbookCell]], note: String,
                      chart: WorkbookChart? = nil) -> WorkbookSheet {
        let identifier = "DoseTap" + name.filter { $0.isLetter || $0.isNumber }
        var used = Set<String>()
        let safeColumns = columns.enumerated().map { index, original -> String in
            let escaped = escapedControls(original)
            let base = escaped.utf16.count > 200 ? chunks(escaped, limit: 175)[0] + " [field \(index + 1)]" : escaped
            var label = base.isEmpty ? "Field \(index + 1)" : base, suffix = 2
            while !used.insert(label.lowercased()).inserted { label = base + " (\(suffix))"; suffix += 1 }
            return label
        }
        return WorkbookSheet(name: name, columns: safeColumns, rows: rows, note: note,
                             tableName: identifier, freezeColumns: min(2, columns.count), chart: chart)
    }
}

struct SWGroup {
    let key: String
    let date: String
    let original: SWObject
    let originalIndex: Int
    var issues: [String]
    var eligible: Bool { issues.isEmpty }
    var identity: String { eligible ? "Resolved" : "Needs record review" }
    var health: SWObject { SW.object(original["healthKit"]) }
    var collected: SWObject { SW.object(original["collectedNight"]) }
    var context: SWObject { SW.object(original["context"]) }
}

struct SWRecord {
    let key: String
    let baseKey: String
    let id: String
    let table: String
    let representation: String
    let payload: SWObject
    let fields: SWObject
    var groupKeys: Set<String>
    var dates: Set<String>
    var variantCount = 1
    var dateLabel: String { dates.sorted().joined(separator: "; ") }
    var association: String { dates.count > 1 ? "Multiple dates — review" : "One date" }
    var sessionID: String? { SW.string(fields["session_id"] ?? fields["sessionId"]) }
    var dateSort: String { dates.sorted().last ?? "" }
}

struct SWIssue {
    let group: String
    let date: String
    let category: String
    let reason: String
    let source: String
}

/// Owned by one synchronous projection call, never a static/shared formatter or live clock.
final class SWProjectionCache {
    let timestamps: SWTimestampParser
    var sourceValues: [SWSourceValue]?
    init(timezone: TimeZone) { timestamps = SWTimestampParser(timezone: timezone) }
}

final class SWTimestampParser {
    private let fractional = ISO8601DateFormatter()
    private let whole = ISO8601DateFormatter()
    private let local = ISO8601DateFormatter()
    private let sqlite = DateFormatter()
    private let dayFormat = DateFormatter()
    private var dates: [String: Date] = [:], invalid = Set<String>(), days: [String: Date] = [:]
    private var localStrings: [Date: String] = [:]
    init(timezone: TimeZone) {
        fractional.formatOptions.insert(.withFractionalSeconds)
        local.formatOptions.insert(.withFractionalSeconds); local.timeZone = timezone
        for formatter in [sqlite, dayFormat] {
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        }
        sqlite.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dayFormat.dateFormat = "yyyy-MM-dd"; dayFormat.isLenient = false
    }
    func parse(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        if let date = dates[string] { return date }
        if invalid.contains(string) { return nil }
        guard let date = (fractional.date(from: string) ?? whole.date(from: string) ?? sqlite.date(from: string)).flatMap(SW.validDate)
        else { invalid.insert(string); return nil }
        dates[string] = date; return date
    }
    func day(_ string: String) -> Date? {
        if let date = days[string] { return date }
        guard string.count == 10, let date = dayFormat.date(from: string), dayFormat.string(from: date) == string,
              SW.validDate(date) != nil else { return nil }
        days[string] = date; return date
    }
    func localCell(_ date: Date?) -> WorkbookCell {
        guard let date else { return .blank }
        if let string = localStrings[date] { return .text(string) }
        let string = local.string(from: date); localStrings[date] = string; return .text(string)
    }
}
