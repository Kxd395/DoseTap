import Foundation
#if canImport(Compression)
import Compression
#endif
import XCTest
@testable import DoseCore

final class ExcelWorkbookWriterTests: XCTestCase {
    func testEveryFieldHasNamedTableFilterAndFrozenHeaders() throws {
        let parts = try ExcelWorkbookWriter.parts(sheets: [sample()])
        let table = string(parts, "xl/tables/table1.xml")
        XCTAssertTrue(table.contains("name=\"ReviewEvents\""))
        XCTAssertTrue(table.contains("ref=\"A4:F5\""))
        XCTAssertTrue(table.contains("<autoFilter ref=\"A4:F5\""))
        XCTAssertTrue(table.contains("tableColumns count=\"6\""))
        let sheet = string(parts, "xl/worksheets/sheet1.xml")
        XCTAssertTrue(sheet.contains("xSplit=\"1\" ySplit=\"4\""))
        XCTAssertTrue(sheet.contains("topLeftCell=\"B5\""))
        XCTAssertTrue(sheet.contains("tablePart r:id=\"rIdTable\""))
        XCTAssertFalse(string(parts, "xl/workbook.xml").contains("state=\"hidden\""))
    }

    func testTypedValuesKeepZeroMissingDateAndDurationDistinct() throws {
        let parts = try ExcelWorkbookWriter.parts(sheets: [sample()])
        let sheet = string(parts, "xl/worksheets/sheet1.xml")
        XCTAssertTrue(sheet.contains("r=\"B5\" s=\"5\"><v>0</v>"))
        XCTAssertTrue(sheet.contains("r=\"C5\" s=\"4\"/>") )
        XCTAssertTrue(sheet.contains("<v>25569</v>")) // 1970-01-01 UTC
        XCTAssertTrue(sheet.contains("<v>0.25</v>")) // Six hours is a quarter day.
        let styles = string(parts, "xl/styles.xml")
        XCTAssertTrue(styles.contains("[h]&quot;h &quot;mm&quot;m&quot;"))
        XCTAssertTrue(styles.contains("Arial"))
        XCTAssertTrue(styles.contains("numFmtId=\"166\" formatCode=\"General\""))
        XCTAssertTrue(styles.contains("FF0D7479"))
    }

    func testTypedDateColumnsFitFullUTCFormatEvenWithShortHeaders() throws {
        let sheet = WorkbookSheet(name: "Dates", columns: ["Period start", "Count"],
            rows: [[.blank, .number(2)], [.date(Date(timeIntervalSince1970: 0)), .number(0)]],
            tableName: "PeriodDates")
        let xml = string(try ExcelWorkbookWriter.parts(sheets: [sheet]), "xl/worksheets/sheet1.xml")
        XCTAssertTrue(xml.contains("<col min=\"1\" max=\"1\" width=\"32\""))
        XCTAssertTrue(xml.contains("<col min=\"2\" max=\"2\" width=\"18\""))
    }

    func testUserStringsNeverBecomeFormulaAndLiteralEscapesSurvive() throws {
        let cells: [WorkbookCell] = [.text("=HYPERLINK(\"https://example.test\")"), .text("+1"),
            .text("@SUM(A1)"), .text("_x0041_ & < > \" '\r\n")]
        let sheet = WorkbookSheet(name: "Literal", columns: ["A", "B", "C", "D"], rows: [cells], tableName: "LiteralData")
        let xml = string(try ExcelWorkbookWriter.parts(sheets: [sheet]), "xl/worksheets/sheet1.xml")
        XCTAssertFalse(xml.contains("<f"))
        XCTAssertTrue(xml.contains("t=\"inlineStr\""))
        XCTAssertTrue(xml.contains("_x005F_x0041_"))
        XCTAssertTrue(xml.contains("&amp; &lt; &gt; &quot; &apos;_x000D_\n"))
    }

    func testEmptySourceUsesExplicitBlankTablePlaceholderWithoutFakeObservation() throws {
        let sheet = WorkbookSheet(name: "Inventory", columns: ["ID", "Amount"], rows: [], note: "No records exported.", tableName: "SupplyInventory")
        let parts = try ExcelWorkbookWriter.parts(sheets: [sheet])
        XCTAssertTrue(string(parts, "xl/tables/table1.xml").contains("ref=\"A4:B5\""))
        let xml = string(parts, "xl/worksheets/sheet1.xml")
        XCTAssertTrue(xml.contains("<row r=\"5\""))
        XCTAssertTrue(xml.contains("Blank row is an Excel table placeholder, not an observation."))
        XCTAssertTrue(xml.contains("<c r=\"A5\" s=\"4\"/><c r=\"B5\" s=\"4\"/>"))
        XCTAssertTrue(sheet.rows.isEmpty)
        XCTAssertFalse(xml.contains("<v>0</v>"))
    }

    func testUnsafeOrOversizeInputsFailRatherThanCreateBrokenArchive() {
        let badText = String(repeating: "x", count: 32_768)
        let invalidCells: [WorkbookCell] = [.number(.infinity), .number(.nan), .number(1e15),
            .durationMinutes(-1), .date(Date(timeIntervalSince1970: .infinity)), .text(badText)]
        for cell in invalidCells {
            XCTAssertThrowsError(try ExcelWorkbookWriter.encode(sheets: [single(cell)]))
        }
        XCTAssertNoThrow(try ExcelWorkbookWriter.encode(sheets: [single(.text(String(repeating: "x", count: 32_767)))]))
        XCTAssertThrowsError(try ExcelWorkbookWriter.encode(sheets: [single(.text(String(repeating: "😀", count: 16_384)))]))
    }

    func testOrdinaryXMLTextFastPathPreservesUnicodeWhitespaceAndUnderscores() throws {
        for value in ["ordinary", "source_record_id", "0", "\tplain\n", "Café 👣 日本", "_xy", "_X0001_"] {
            XCTAssertEqual(try WorkbookXML.text(value), value)
        }
        XCTAssertEqual(try WorkbookXML.text("literal _x0001_"), "literal _x005F_x0001_")
        XCTAssertEqual(try WorkbookXML.text("\u{fffe}\u{ffff}"), "_xFFFE__xFFFF_")
    }

    func testHistoricalControlCharactersAreEscapedLosslessly() throws {
        let xml = string(try ExcelWorkbookWriter.parts(sheets: [single(.text("before\u{01}after\u{00}\r\t\n"))]), "xl/worksheets/sheet1.xml")
        XCTAssertTrue(xml.contains("before_x0001_after_x0000__x000D_\t\n"))
        XCTAssertTrue(XMLParser(data: Data(xml.utf8)).parse())
    }

    func testInvalidNamesShapeAndDuplicateColumnsFailExplicitly() {
        XCTAssertThrowsError(try ExcelWorkbookWriter.parts(sheets: []))
        XCTAssertThrowsError(try ExcelWorkbookWriter.parts(sheets: [single(.blank, name: "Bad/Name")]))
        XCTAssertThrowsError(try ExcelWorkbookWriter.parts(sheets: [single(.blank), single(.blank, name: "sheet")]))
        XCTAssertThrowsError(try ExcelWorkbookWriter.parts(sheets: [WorkbookSheet(name: "Shape", columns: ["A"], rows: [[.blank, .blank]], tableName: "ShapeData")]))
        XCTAssertThrowsError(try ExcelWorkbookWriter.parts(sheets: [WorkbookSheet(name: "Columns", columns: ["ID", "id"], rows: [], tableName: "ColumnData")]))
        XCTAssertThrowsError(try ExcelWorkbookWriter.parts(sheets: [WorkbookSheet(name: "Table", columns: ["A"], rows: [], tableName: "A1")]))
    }

    func testHeaderWhitespaceSurvivesXMLAttributeNormalization() throws {
        let sheet = WorkbookSheet(name: "Headers", columns: ["First\nSecond", "A\tB"], rows: [], tableName: "HeaderData")
        let parts = try ExcelWorkbookWriter.parts(sheets: [sheet])
        XCTAssertTrue(string(parts, "xl/tables/table1.xml").contains("First&#10;Second"))
        XCTAssertTrue(string(parts, "xl/tables/table1.xml").contains("A&#9;B"))
        XCTAssertTrue(string(parts, "xl/worksheets/sheet1.xml").contains("First\nSecond"))
    }

    func testDateSerialHandles1900LeapConventionAndRejectsEarlierDates() throws {
        let rows: [[WorkbookCell]] = [[.date(Date(timeIntervalSince1970: -2208988800))],
            [.date(Date(timeIntervalSince1970: -2203977600))], [.date(Date(timeIntervalSince1970: -2203891200))]]
        let sheet = WorkbookSheet(name: "Dates", columns: ["UTC"], rows: rows, tableName: "DateValues")
        let xml = string(try ExcelWorkbookWriter.parts(sheets: [sheet]), "xl/worksheets/sheet1.xml")
        XCTAssertTrue(xml.contains("<v>1</v>"))
        XCTAssertTrue(xml.contains("<v>59</v>"))
        XCTAssertTrue(xml.contains("<v>61</v>"))
        XCTAssertThrowsError(try ExcelWorkbookWriter.parts(sheets: [single(.date(Date(timeIntervalSince1970: -2209075200)))]))
    }

    func testInternalLinksAreLiteralAndExternalLinksAreRejected() throws {
        let source = WorkbookSheet(name: "Overview", columns: ["Open"], rows: [[.link(label: "Night", target: "'Night Review'!A5")]], tableName: "OverviewData")
        let target = single(.text("night"), name: "Night Review", tableName: "NightData")
        let xml = string(try ExcelWorkbookWriter.parts(sheets: [source, target]), "xl/worksheets/sheet1.xml")
        XCTAssertTrue(xml.contains("location=\"&apos;Night Review&apos;!A5\""))
        XCTAssertFalse(xml.contains("<f"))
        XCTAssertThrowsError(try ExcelWorkbookWriter.parts(sheets: [single(.link(label: "Open", target: "https://example.test"))]))
        XCTAssertThrowsError(try ExcelWorkbookWriter.parts(sheets: [single(.link(label: "Open", target: "Missing!A5"))]))
    }

    func testChartLeavesUnavailableValuesAsGaps() throws {
        let chart = WorkbookChart(title: "Sleep duration", categories: ["One", "Two", "Three"], values: [6, nil, 7])
        let sheet = WorkbookSheet(name: "Overview", columns: ["Metric"], rows: [], tableName: "OverviewData", chart: chart)
        let parts = try ExcelWorkbookWriter.parts(sheets: [sheet])
        let xml = string(parts, "xl/charts/chart1.xml")
        XCTAssertTrue(xml.contains("<c:dispBlanksAs val=\"gap\"/>"))
        XCTAssertTrue(xml.contains("<c:ptCount val=\"3\"/>"))
        XCTAssertTrue(xml.contains("<c:pt idx=\"0\"><c:v>6</c:v>"))
        XCTAssertFalse(xml.contains("<c:pt idx=\"1\"><c:v>0"))
        XCTAssertNotNil(parts["xl/drawings/drawing1.xml"])
        XCTAssertNotNil(parts["xl/drawings/_rels/drawing1.xml.rels"])
        XCTAssertThrowsError(try ExcelWorkbookWriter.parts(sheets: [WorkbookSheet(name: "Bad", columns: ["A"], rows: [], tableName: "BadData", chart: WorkbookChart(title: "Bad", categories: ["A"], values: []))]))
    }

    func testZipCRCMatchesEveryXMLPartAndArchiveIsDeterministic() throws {
        let sheets = [sample()]
        let expected = try ExcelWorkbookWriter.parts(sheets: sheets)
        let archive = try ExcelWorkbookWriter.encode(sheets: sheets)
        XCTAssertEqual(archive, try ExcelWorkbookWriter.encode(sheets: sheets))
        var offset = 0
        var found: [String: Data] = [:]
        while read32(archive, offset) == 0x04034b50 {
            let method = read16(archive, offset + 8)
            XCTAssertTrue([0, 8].contains(method))
            let count = Int(read32(archive, offset + 18))
            let nameLength = Int(read16(archive, offset + 26))
            let extraLength = Int(read16(archive, offset + 28))
            let nameStart = offset + 30
            let name = String(decoding: archive[nameStart..<(nameStart + nameLength)], as: UTF8.self)
            let dataStart = nameStart + nameLength + extraLength
            let encoded = archive.subdata(in: dataStart..<(dataStart + count))
            let payload = decodeZIPPayload(encoded, method: method, size: Int(read32(archive, offset + 22)))
            XCTAssertEqual(crc32(payload), read32(archive, offset + 14), name)
            found[name] = payload
            offset = dataStart + count
        }
        XCTAssertEqual(read32(archive, offset), 0x02014b50)
        XCTAssertEqual(read32(archive, archive.count - 22), 0x06054b50)
        XCTAssertEqual(found, expected)
        for (name, bytes) in expected where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            XCTAssertTrue(XMLParser(data: bytes).parse(), name)
        }
    }

    func testDeflateStreamsMultipleBuffersAndKeepsCentralDirectorySizesCorrect() throws {
        var random = UInt64(47)
        let noise = (0..<(128 * 1024)).map { _ -> UInt8 in
            random = random &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: random >> 56)
        }
        let source = Data(noise) + Data(repeating: 65, count: 128 * 1024)
        let archive = try ExcelWorkbookZIP.archive(parts: ["source.bin": source])
        let method = read16(archive, 8)
        let compressedSize = Int(read32(archive, 18))
        let originalSize = Int(read32(archive, 22))
        let dataStart = 30 + Int(read16(archive, 26))
        #if canImport(Compression)
        XCTAssertEqual(method, 8)
        XCTAssertLessThan(compressedSize, source.count)
        XCTAssertGreaterThan(compressedSize, 64 * 1024)
        #else
        XCTAssertEqual(method, 0)
        #endif
        XCTAssertEqual(originalSize, source.count)
        let compressed = archive.subdata(in: dataStart..<(dataStart + compressedSize))
        XCTAssertEqual(decodeZIPPayload(compressed, method: method, size: originalSize), source)
        let central = dataStart + compressedSize
        XCTAssertEqual(read16(archive, central + 10), method)
        XCTAssertEqual(read32(archive, central + 20), UInt32(compressedSize))
        XCTAssertEqual(read32(archive, central + 24), UInt32(originalSize))
        XCTAssertEqual(read32(archive, central + 16), crc32(source))
    }

    func testTinyEmptyAndIncompressiblePartsUseStoredFallback() throws {
        for source in [Data(), Data([1, 2, 3]), Data((0...255).map(UInt8.init))] {
            let archive = try ExcelWorkbookZIP.archive(parts: ["value.bin": source])
            XCTAssertEqual(read16(archive, 8), 0)
            XCTAssertEqual(read32(archive, 18), UInt32(source.count))
            XCTAssertEqual(read32(archive, 22), UInt32(source.count))
        }
    }

    private func decodeZIPPayload(_ data: Data, method: UInt16, size: Int) -> Data {
        if method == 0 { return data }
        #if canImport(Compression)
        var decoded = Data(count: size)
        let count = decoded.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        XCTAssertEqual(count, size)
        return decoded
        #else
        XCTFail("DEFLATE entry created on a platform without its codec")
        return Data()
        #endif
    }

    private func sample() -> WorkbookSheet {
        WorkbookSheet(name: "Events", columns: ["ID", "Value", "Missing", "UTC", "Duration", "Notes"],
            rows: [[.text("00123"), .number(0), .blank, .date(Date(timeIntervalSince1970: 0)), .durationMinutes(360), .text("literal")]], tableName: "ReviewEvents")
    }
    private func single(_ cell: WorkbookCell, name: String = "Sheet", tableName: String = "SingleData") -> WorkbookSheet {
        WorkbookSheet(name: name, columns: ["Value"], rows: [[cell]], tableName: tableName)
    }
    private func string(_ parts: [String: Data], _ name: String) -> String {
        String(decoding: parts[name] ?? Data(), as: UTF8.self)
    }
    private func read16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }
    private func read32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(read16(data, offset)) | UInt32(read16(data, offset + 2)) << 16
    }
    private func crc32(_ bytes: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        return ~crc
    }
}
