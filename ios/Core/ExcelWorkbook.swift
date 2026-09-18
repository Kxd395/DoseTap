import Foundation

/// A reporting value, never an executable spreadsheet formula. Dates are UTC Excel dates.
public enum WorkbookCell: Equatable, Sendable {
    case blank
    case text(String)
    case number(Double)
    case date(Date)
    case durationMinutes(Double)
    case link(label: String, target: String)
}

public struct WorkbookChart: Equatable, Sendable {
    public let title: String
    public let categories: [String]
    public let values: [Double?]
    public init(title: String, categories: [String], values: [Double?]) {
        self.title = title; self.categories = categories; self.values = values
    }
}

public struct WorkbookSheet: Equatable, Sendable {
    public let name: String
    public let columns: [String]
    public let rows: [[WorkbookCell]]
    public let note: String
    public let tableName: String
    public let freezeColumns: Int
    public let chart: WorkbookChart?

    public init(name: String, columns: [String], rows: [[WorkbookCell]], note: String = "",
                tableName: String, freezeColumns: Int = 1, chart: WorkbookChart? = nil) {
        self.name = name; self.columns = columns; self.rows = rows; self.note = note
        self.tableName = tableName; self.freezeColumns = freezeColumns; self.chart = chart
    }
}

public enum ExcelWorkbookError: LocalizedError, Equatable {
    case invalidWorkbook(String)
    public var errorDescription: String? {
        switch self {
        case .invalidWorkbook(let reason): return "The Excel workbook could not be created. \(reason) Your saved records were not changed."
        }
    }
}

/// OOXML validation and escaping are shared by worksheets, table headers and charts.
enum WorkbookXML {
    static let declaration = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>"
    static let main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    static let relationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let packageRelationships = "http://schemas.openxmlformats.org/package/2006/relationships"

    static func text(_ value: String) throws -> String {
        guard value.utf16.count <= 32_767 else { throw failure("A value exceeds Excel's cell limit; split it into numbered parts before exporting.") }
        if !requiresEscaping(value) { return value }
        // OOXML's own escape syntax must not reinterpret a literal user string such as _x0041_.
        let protected = value.replacingOccurrences(of: "_(x[0-9A-Fa-f]{4}_)", with: "_x005F_$1", options: .regularExpression)
        let encoded = protected.unicodeScalars.map { scalar -> String in
            let number = scalar.value
            if (number < 0x20 && number != 9 && number != 10) || number == 0xfffe || number == 0xffff {
                return String(format: "_x%04X_", number)
            }
            return String(scalar)
        }.joined()
        return encoded.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func requiresEscaping(_ value: String) -> Bool {
        var underscore = false
        for byte in value.utf8 {
            // EF includes U+FFFE/U+FFFF. Conservatively route any EF sequence through
            // the full scalar path; all other non-ASCII UTF-8 is already valid XML text.
            switch byte {
            case 0x26, 0x3c, 0x3e, 0x22, 0x27, 0xef: return true
            case 0x00...0x1f where byte != 9 && byte != 10: return true
            default: break
            }
            if underscore && byte == 0x78 { return true }
            underscore = byte == 0x5f
        }
        return false
    }

    static func attribute(_ value: String) throws -> String {
        // Literal tabs/newlines in attributes would otherwise normalize to spaces on XML read.
        try text(value).replacingOccurrences(of: "\n", with: "&#10;")
            .replacingOccurrences(of: "\t", with: "&#9;")
    }

    static func number(_ value: Double) throws -> String {
        guard value.isFinite, abs(value) < 1e15 else {
            throw failure("A numeric value is nonfinite or exceeds Excel's reliable precision; identifiers must be exported as text.")
        }
        return String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value == 0 ? 0 : value)
    }

    static func column(_ index: Int) -> String {
        var number = index + 1; var result = ""
        while number > 0 {
            number -= 1
            result = String(UnicodeScalar(65 + number % 26)!) + result
            number /= 26
        }
        return result
    }

    static func failure(_ reason: String) -> ExcelWorkbookError { .invalidWorkbook(reason) }

    static func validate(_ sheets: [WorkbookSheet]) throws {
        guard !sheets.isEmpty else { throw failure("There are no sheets to export.") }
        var names = Set<String>(); var tables = Set<String>()
        for sheet in sheets {
            guard !sheet.name.isEmpty, sheet.name.utf16.count <= 31,
                sheet.name.rangeOfCharacter(from: CharacterSet(charactersIn: "[]:*?/\\")) == nil,
                !sheet.name.hasPrefix("'"), !sheet.name.hasSuffix("'"),
                sheet.name.rangeOfCharacter(from: .controlCharacters) == nil else { throw failure("A worksheet name is invalid.") }
            guard names.insert(sheet.name.lowercased()).inserted else { throw failure("Worksheet names must be unique.") }
            let table = sheet.tableName
            guard table.utf16.count <= 255, table.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil,
                table.range(of: "^[A-Za-z]{1,3}[1-9][0-9]*$", options: .regularExpression) == nil,
                table.range(of: "^R[0-9]+C[0-9]+$", options: [.regularExpression, .caseInsensitive]) == nil,
                !["r", "c"].contains(table.lowercased()), tables.insert(table.lowercased()).inserted else {
                throw failure("Excel table names must be unique identifiers, not cell references.")
            }
            guard !sheet.columns.isEmpty, sheet.columns.count <= 16_384, sheet.rows.count <= 1_048_572,
                sheet.freezeColumns >= 0, sheet.freezeColumns < 16_384, sheet.freezeColumns <= sheet.columns.count,
                sheet.rows.allSatisfy({ $0.count == sheet.columns.count }) else {
                throw failure("A worksheet exceeds Excel's dimensions or has a row with mismatched columns.")
            }
            var headers = Set<String>()
            for header in sheet.columns {
                guard !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, header.utf16.count <= 255,
                    headers.insert(header.lowercased()).inserted else { throw failure("Every table needs distinct, nonempty column headers of at most 255 characters.") }
                _ = try text(header)
            }
            _ = try text(sheet.name); _ = try text(sheet.note)
            if let chart = sheet.chart {
                guard chart.categories.count == chart.values.count, chart.categories.count <= 1_048_576 else {
                    throw failure("A chart's categories and measurements do not match.")
                }
                _ = try text(chart.title)
                for category in chart.categories { _ = try text(category) }
                for value in chart.values.compactMap({ $0 }) { _ = try number(value) }
            }
        }
    }

    static func linkLocation(_ target: String, sheets: [WorkbookSheet]) throws -> String {
        let value = target.hasPrefix("#") ? String(target.dropFirst()) : target
        guard let separator = value.lastIndex(of: "!") else { throw failure("A workbook link does not identify a worksheet cell.") }
        var name = String(value[..<separator])
        if name.hasPrefix("'"), name.hasSuffix("'"), name.count >= 2 {
            name = String(name.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        let address = String(value[value.index(after: separator)...]).uppercased()
        guard sheets.contains(where: { $0.name == name }),
            address.range(of: "^\\$?[A-Z]{1,3}\\$?[1-9][0-9]{0,6}$", options: .regularExpression) != nil else {
            throw failure("Only links to existing workbook sheets and valid cells are supported.")
        }
        let letters = address.filter(\.isLetter)
        let columnNumber = letters.utf8.reduce(0) { $0 * 26 + Int($1) - 64 }
        guard columnNumber <= 16_384, let row = Int(address.filter(\.isNumber)), row <= 1_048_576 else {
            throw failure("A workbook link exceeds Excel's worksheet dimensions.")
        }
        return "'\(name.replacingOccurrences(of: "'", with: "''"))'!\(address)"
    }
}
