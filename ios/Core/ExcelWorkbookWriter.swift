import Foundation

/// A local-only SpreadsheetML writer. All records are typed values; there is no formula API.
public enum ExcelWorkbookWriter {
    public static func encode(sheets: [WorkbookSheet]) throws -> Data {
        try ExcelWorkbookZIP.archive { emit in
            try forEachPart(sheets: sheets, emit: emit)
        }
    }

    /// Collecting adapter for inspection/tests. Production encoding consumes one part at a time.
    public static func parts(sheets: [WorkbookSheet]) throws -> [String: Data] {
        var output: [String: Data] = [:]
        try forEachPart(sheets: sheets) { output[$0] = $1 }
        return output
    }

    private static func forEachPart(sheets: [WorkbookSheet], emit: (String, Data) throws -> Void) throws {
        try WorkbookXML.validate(sheets)
        func put(_ path: String, _ xml: String) throws {
            var data = Data()
            data.reserveCapacity(WorkbookXML.declaration.utf8.count + xml.utf8.count)
            data.append(contentsOf: WorkbookXML.declaration.utf8)
            data.append(contentsOf: xml.utf8)
            try emit(path, data)
        }
        let relationships = WorkbookXML.relationships
        try put("_rels/.rels", relations([
            ("rIdWorkbook", "officeDocument", "xl/workbook.xml"),
            ("rIdApp", "extended-properties", "docProps/app.xml")]))
        try put("docProps/app.xml", "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\"><Application>DoseTap</Application></Properties>")
        var sheetTags = ""; var workbookRelations: [(String, String, String)] = []
        var overrides = [("/xl/workbook.xml", "sheet.main"), ("/xl/styles.xml", "styles")]
        for (index, sheet) in sheets.enumerated() {
            let id = index + 1
            sheetTags += "<sheet name=\"\(try WorkbookXML.attribute(sheet.name))\" sheetId=\"\(id)\" r:id=\"rId\(id)\"/>"
            workbookRelations.append(("rId\(id)", "worksheet", "worksheets/sheet\(id).xml"))
            overrides.append(("/xl/worksheets/sheet\(id).xml", "worksheet"))
            overrides.append(("/xl/tables/table\(id).xml", "table"))
            try put("xl/worksheets/sheet\(id).xml", try worksheet(sheet, sheets: sheets))
            try put("xl/tables/table\(id).xml", try table(sheet, id: id))
            var sheetRelations = [("rIdTable", "table", "../tables/table\(id).xml")]
            if let chart = sheet.chart {
                sheetRelations.append(("rIdDrawing", "drawing", "../drawings/drawing\(id).xml"))
                try put("xl/charts/chart\(id).xml", try chartXML(chart))
                try put("xl/drawings/drawing\(id).xml", drawing(id: id, row: sheet.rows.count + 7))
                try put("xl/drawings/_rels/drawing\(id).xml.rels", relations([("rIdChart", "chart", "../charts/chart\(id).xml")]))
            }
            try put("xl/worksheets/_rels/sheet\(id).xml.rels", relations(sheetRelations))
        }
        workbookRelations.append(("rIdStyles", "styles", "styles.xml"))
        try put("xl/_rels/workbook.xml.rels", relations(workbookRelations))
        try put("xl/workbook.xml", "<workbook xmlns=\"\(WorkbookXML.main)\" xmlns:r=\"\(relationships)\"><workbookPr date1904=\"0\"/><bookViews><workbookView activeTab=\"0\"/></bookViews><sheets>\(sheetTags)</sheets></workbook>")
        try put("xl/styles.xml", styles)
        var types = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        for (path, type) in overrides { types += "<Override PartName=\"\(path)\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.\(type)+xml\"/>" }
        types += "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>"
        for (index, sheet) in sheets.enumerated() where sheet.chart != nil {
            let id = index + 1
            types += "<Override PartName=\"/xl/charts/chart\(id).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawingml.chart+xml\"/>"
            types += "<Override PartName=\"/xl/drawings/drawing\(id).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.drawing+xml\"/>"
        }
        try put("[Content_Types].xml", types + "</Types>")
    }

    private static func relations(_ items: [(String, String, String)]) -> String {
        let elements = items.map { id, type, target in
            "<Relationship Id=\"\(id)\" Type=\"\(WorkbookXML.relationships)/\(type)\" Target=\"\(target)\"/>"
        }.joined()
        return "<Relationships xmlns=\"\(WorkbookXML.packageRelationships)\">\(elements)</Relationships>"
    }

    private static func worksheet(_ sheet: WorkbookSheet, sheets: [WorkbookSheet]) throws -> String {
        let lastColumn = WorkbookXML.column(sheet.columns.count - 1)
        let lastRow = max(1, sheet.rows.count) + 4
        let note = sheet.rows.isEmpty
            ? "0 records. Blank row is an Excel table placeholder, not an observation. " + sheet.note
            : sheet.note
        let firstUnfrozen = WorkbookXML.column(sheet.freezeColumns)
        let pane = sheet.freezeColumns > 0 ? "bottomRight" : "bottomLeft"
        let xSplit = sheet.freezeColumns > 0 ? "xSplit=\"\(sheet.freezeColumns)\" " : ""
        // A short header (for example, "Period start") does not imply a short date.
        // Size by the typed data so Excel shows the UTC timestamp instead of ####.
        var dateColumns = Set<Int>()
        for row in sheet.rows {
            for (index, value) in row.enumerated() {
                if case .date = value { dateColumns.insert(index) }
            }
        }
        var xml = "<worksheet xmlns=\"\(WorkbookXML.main)\" xmlns:r=\"\(WorkbookXML.relationships)\"><sheetPr><tabColor rgb=\"FF0D7479\"/></sheetPr>"
        xml += "<dimension ref=\"A1:\(lastColumn)\(lastRow)\"/><sheetViews><sheetView showGridLines=\"0\" zoomScale=\"90\" workbookViewId=\"0\"><pane \(xSplit)ySplit=\"4\" topLeftCell=\"\(firstUnfrozen)5\" activePane=\"\(pane)\" state=\"frozen\"/><selection pane=\"\(pane)\" activeCell=\"\(firstUnfrozen)5\" sqref=\"\(firstUnfrozen)5\"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight=\"30\"/><cols>"
        for (index, header) in sheet.columns.enumerated() {
            let name = header.lowercased()
            let width = dateColumns.contains(index) ? 32 :
                name.contains("note") || name.contains("detail") || name.contains("value") ? 48 :
                name.contains("id") || name.contains("utc") || name.contains("time") ? 25 : max(18, min(34, header.count + 3))
            xml += "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
        }
        xml += "</cols><sheetData><row r=\"1\" ht=\"34\" customHeight=\"1\">\(try inline(sheet.name, reference: "A1", style: 1))</row>"
        xml += "<row r=\"2\" ht=\"48\" customHeight=\"1\">\(try inline(note, reference: "A2", style: 2))</row><row r=\"4\" ht=\"32\" customHeight=\"1\">"
        for (index, header) in sheet.columns.enumerated() { xml += try inline(header, reference: "\(WorkbookXML.column(index))4", style: 3) }
        xml += "</row>"
        var hyperlinks = ""
        // Excel repairs away a header-only table. The physical blank row is not a source record.
        let physicalRows = sheet.rows.isEmpty ? [Array(repeating: WorkbookCell.blank, count: sheet.columns.count)] : sheet.rows
        for (index, row) in physicalRows.enumerated() {
            let rowNumber = index + 5
            xml += "<row r=\"\(rowNumber)\">"
            for (column, value) in row.enumerated() {
                let reference = "\(WorkbookXML.column(column))\(rowNumber)"
                xml += try cell(value, reference: reference, stripe: index % 2 == 1)
                if case let .link(_, target) = value {
                    let location = try WorkbookXML.linkLocation(target, sheets: sheets)
                    hyperlinks += "<hyperlink ref=\"\(reference)\" location=\"\(try WorkbookXML.attribute(location))\"/>"
                }
            }
            xml += "</row>"
        }
        xml += "</sheetData>"
        if sheet.columns.count > 1 { xml += "<mergeCells count=\"2\"><mergeCell ref=\"A1:\(lastColumn)1\"/><mergeCell ref=\"A2:\(lastColumn)2\"/></mergeCells>" }
        if !hyperlinks.isEmpty { xml += "<hyperlinks>\(hyperlinks)</hyperlinks>" }
        xml += "<pageMargins left=\"0.3\" right=\"0.3\" top=\"0.4\" bottom=\"0.4\" header=\"0.2\" footer=\"0.2\"/>"
        if sheet.chart != nil { xml += "<drawing r:id=\"rIdDrawing\"/>" }
        xml += "<tableParts count=\"1\"><tablePart r:id=\"rIdTable\"/></tableParts></worksheet>"
        return xml
    }

    private static func inline(_ value: String, reference: String, style: Int) throws -> String {
        "<c r=\"\(reference)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(try WorkbookXML.text(value))</t></is></c>"
    }

    private static func cell(_ value: WorkbookCell, reference: String, stripe: Bool) throws -> String {
        let base = stripe ? 9 : 4
        switch value {
        case .blank: return "<c r=\"\(reference)\" s=\"\(base)\"/>"
        case .text(let text): return try inline(text, reference: reference, style: base)
        case .link(let label, _): return try inline(label, reference: reference, style: base + 4)
        case .number(let value): return "<c r=\"\(reference)\" s=\"\(base + 1)\"><v>\(try WorkbookXML.number(value))</v></c>"
        case .durationMinutes(let minutes):
            guard minutes >= 0 else { throw WorkbookXML.failure("A duration is negative; preserve it as a conflict rather than an elapsed time.") }
            return "<c r=\"\(reference)\" s=\"\(base + 3)\"><v>\(try WorkbookXML.number(minutes / 1440))</v></c>"
        case .date(let date):
            let unix = date.timeIntervalSince1970
            // The 1900 date system has a nonexistent leap day; dates before March need one less day.
            let serial = unix / 86400 + 25569 - (unix < -2203891200 ? 1 : 0)
            guard serial.isFinite, serial >= 1, serial < 2_958_466 else { throw WorkbookXML.failure("A date is outside Excel's supported 1900–9999 range.") }
            return "<c r=\"\(reference)\" s=\"\(base + 2)\"><v>\(try WorkbookXML.number(serial))</v></c>"
        }
    }

    private static func table(_ sheet: WorkbookSheet, id: Int) throws -> String {
        let range = "A4:\(WorkbookXML.column(sheet.columns.count - 1))\(max(1, sheet.rows.count) + 4)"
        var xml = "<table xmlns=\"\(WorkbookXML.main)\" id=\"\(id)\" name=\"\(sheet.tableName)\" displayName=\"\(sheet.tableName)\" ref=\"\(range)\" headerRowCount=\"1\" totalsRowShown=\"0\"><autoFilter ref=\"\(range)\"/><tableColumns count=\"\(sheet.columns.count)\">"
        for (index, header) in sheet.columns.enumerated() { xml += "<tableColumn id=\"\(index + 1)\" name=\"\(try WorkbookXML.attribute(header))\"/>" }
        return xml + "</tableColumns><tableStyleInfo name=\"DoseTapTable\" showFirstColumn=\"0\" showLastColumn=\"0\" showRowStripes=\"1\" showColumnStripes=\"0\"/></table>"
    }

    private static var styles: String {
        let font = "<sz val=\"11\"/><name val=\"Arial\"/>"
        let alignment = "<alignment vertical=\"top\" wrapText=\"1\"/>"
        func xf(_ font: Int, _ fill: Int, _ format: Int = 0) -> String {
            "<xf numFmtId=\"\(format)\" fontId=\"\(font)\" fillId=\"\(fill)\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyFill=\"1\" applyNumberFormat=\"1\" applyAlignment=\"1\">\(alignment)</xf>"
        }
        var cellStyles = xf(0, 0) + xf(1, 2) + xf(2, 0) + xf(3, 3)
        for fill in [0, 4] { cellStyles += xf(0, fill) + xf(0, fill, 166) + xf(0, fill, 164) + xf(0, fill, 165) + xf(4, fill) }
        return """
        <styleSheet xmlns="\(WorkbookXML.main)">
        <numFmts count="3"><numFmt numFmtId="164" formatCode="yyyy-mm-dd hh:mm:ss&quot; UTC&quot;"/><numFmt numFmtId="165" formatCode="[h]&quot;h &quot;mm&quot;m&quot;"/><numFmt numFmtId="166" formatCode="General"/></numFmts>
        <fonts count="5"><font>\(font)<color rgb="FF173344"/></font><font><b/><sz val="18"/><name val="Arial"/><color rgb="FFFFFFFF"/></font><font>\(font)<color rgb="FF536774"/></font><font><b/>\(font)<color rgb="FFFFFFFF"/></font><font><u/>\(font)<color rgb="FF006E76"/></font></fonts>
        <fills count="5"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF173344"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0D7479"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFEAF5F4"/><bgColor indexed="64"/></patternFill></fill></fills>
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="14">\(cellStyles)</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        <dxfs count="3"><dxf><font><color rgb="FF173344"/></font></dxf><dxf><font><b/><color rgb="FFFFFFFF"/></font><fill><patternFill patternType="solid"><fgColor rgb="FF0D7479"/><bgColor indexed="64"/></patternFill></fill></dxf><dxf><fill><patternFill patternType="solid"><fgColor rgb="FFEAF5F4"/><bgColor indexed="64"/></patternFill></fill></dxf></dxfs>
        <tableStyles count="1" defaultTableStyle="DoseTapTable" defaultPivotStyle="PivotStyleLight16"><tableStyle name="DoseTapTable" pivot="0" count="3"><tableStyleElement type="wholeTable" dxfId="0"/><tableStyleElement type="headerRow" dxfId="1"/><tableStyleElement type="secondRowStripe" size="1" dxfId="2"/></tableStyle></tableStyles>
        </styleSheet>
        """
    }

    private static func chartXML(_ chart: WorkbookChart) throws -> String {
        var categories = ""; var values = ""
        for (index, category) in chart.categories.enumerated() {
            categories += "<c:pt idx=\"\(index)\"><c:v>\(try WorkbookXML.text(category))</c:v></c:pt>"
            if let value = chart.values[index] { values += "<c:pt idx=\"\(index)\"><c:v>\(try WorkbookXML.number(value))</c:v></c:pt>" }
        }
        return """
        <c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><c:chart><c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US"/><a:t>\(try WorkbookXML.text(chart.title))</a:t></a:r></a:p></c:rich></c:tx></c:title><c:plotArea><c:layout/><c:lineChart><c:grouping val="standard"/><c:ser><c:idx val="0"/><c:order val="0"/><c:spPr><a:ln w="25400"><a:solidFill><a:srgbClr val="0D7479"/></a:solidFill></a:ln></c:spPr><c:marker><c:symbol val="circle"/><c:size val="4"/></c:marker><c:cat><c:strLit><c:ptCount val="\(chart.categories.count)"/>\(categories)</c:strLit></c:cat><c:val><c:numLit><c:formatCode>0.0</c:formatCode><c:ptCount val="\(chart.values.count)"/>\(values)</c:numLit></c:val><c:smooth val="0"/></c:ser><c:axId val="1"/><c:axId val="2"/></c:lineChart><c:catAx><c:axId val="1"/><c:scaling><c:orientation val="minMax"/></c:scaling><c:axPos val="b"/><c:crossAx val="2"/><c:crosses val="autoZero"/><c:auto val="1"/><c:lblAlgn val="ctr"/><c:lblOffset val="100"/></c:catAx><c:valAx><c:axId val="2"/><c:scaling><c:orientation val="minMax"/><c:min val="0"/></c:scaling><c:axPos val="l"/><c:majorGridlines/><c:numFmt formatCode="0.0" sourceLinked="0"/><c:crossAx val="1"/><c:crosses val="autoZero"/><c:crossBetween val="between"/></c:valAx></c:plotArea><c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart></c:chartSpace>
        """
    }

    private static func drawing(id: Int, row: Int) -> String {
        """
        <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><xdr:oneCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(row)</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from><xdr:ext cx="9144000" cy="3657600"/><xdr:graphicFrame macro=""><xdr:nvGraphicFramePr><xdr:cNvPr id="\(id)" name="Sleep chart"/><xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr><xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="\(WorkbookXML.relationships)" r:id="rIdChart"/></a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>
        """
    }
}
