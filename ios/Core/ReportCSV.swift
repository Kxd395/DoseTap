import Foundation

/// CSV for reports: quoted multiline fields and a reversible spreadsheet-text guard.
/// JSON remains the canonical, unmodified source. The apostrophe + zero-width-space
/// marker keeps text beginning with formula/control characters inert in spreadsheets.
public enum ReportCSV {
    private static let marker = "'\u{200B}"
    public enum ParseError: Error { case malformedQuotes }

    public static func field(_ raw: String) -> String {
        let first = raw.trimmingCharacters(in: .whitespacesAndNewlines).first
        let formula = first.map { "=+-@".contains($0) } == true && Double(raw) == nil
        let control = raw.first.map { "\t\r\n".contains($0) } == true
        let value = formula || control || raw.hasPrefix(marker) ? marker + raw : raw
        return value.contains(where: { ",\"\r\n".contains($0) })
            ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
    }

    public static func row(_ fields: [String]) -> String { fields.map(field).joined(separator: ",") }

    public static func rows(_ text: String) throws -> [[String]] {
        let chars = Array(text.unicodeScalars)
        var result: [[String]] = [], row: [String] = []
        var value = "", quoted = false, closed = false, index = 0
        func finishField() {
            row.append(value.hasPrefix(marker) ? String(value.dropFirst(marker.count)) : value)
            value = ""; closed = false
        }
        while index < chars.count {
            let c = chars[index]
            if quoted {
                if c == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" { value.append("\""); index += 1 }
                    else { quoted = false; closed = true }
                } else { value.unicodeScalars.append(c) }
            } else if c == "," { finishField() }
            else if c == "\r" || c == "\n" {
                finishField(); result.append(row); row = []
                if c == "\r", index + 1 < chars.count, chars[index + 1] == "\n" { index += 1 }
            } else if c == "\"", value.isEmpty, !closed { quoted = true }
            else {
                guard !closed && c != "\"" else { throw ParseError.malformedQuotes }
                value.unicodeScalars.append(c)
            }
            index += 1
        }
        guard !quoted else { throw ParseError.malformedQuotes }
        if !row.isEmpty || !value.isEmpty || closed { finishField(); result.append(row) }
        return result
    }
}
