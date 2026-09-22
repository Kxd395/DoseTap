// Compile with the ExcelWorkbook and StudioWorkbook Core sources; see the delivery record.
import Foundation

@main struct WorkbookBenchmark {
    static func main() throws {
        let args = CommandLine.arguments
        guard (2...3).contains(args.count) else {
            fatalError("Usage: workbook-benchmark OUTPUT.xlsx [FINALIZED_STUDIO_DIRECTORY]")
        }
        let sheets: [WorkbookSheet]
        if args.count > 2 {
            let source = URL(fileURLWithPath: args[2])
            sheets = try StudioWorkbookProjection.sheets(
                bundleData: Data(contentsOf: source.appendingPathComponent("insights_bundle.json")),
                inventoryCSV: String(contentsOf: source.appendingPathComponent("inventory.csv"), encoding: .utf8))
        } else {
            let rows: [[WorkbookCell]] = (0..<40000).map { row in
                [.text("row-\(row)"), .number(Double(row)), .date(Date(timeIntervalSince1970: Double(row) * 60)),
                 .durationMinutes(Double(row % 500)), .blank, .text("literal & <xml> _x0041_ =1+1 👣 日本\n" + String(repeating: "evidence ", count: 8))]
            }
            sheets = (1...6).map { WorkbookSheet(name: "Records \($0)", columns: ["ID", "Value", "UTC", "Duration", "Missing", "Notes"], rows: rows, tableName: "Records\($0)") }
        }
        let data = try ExcelWorkbookWriter.encode(sheets: sheets)
        try data.write(to: URL(fileURLWithPath: args[1]), options: .atomic)
        print("sheets=\(sheets.count) rows=\(sheets.reduce(0) { $0 + $1.rows.count }) bytes=\(data.count)")
    }
}
