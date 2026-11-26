import XCTest
import UIKit
import PDFKit
import DoseCore
@testable import DoseTapDashboard

@MainActor
final class CompanionPhysicianPrintTests: XCTestCase {
    private final class Pages: UIPrintPageRenderer {
        override var paperRect: CGRect { CGRect(x: 0, y: 0, width: 612, height: 792) }
        override var printableRect: CGRect { paperRect.insetBy(dx: 36, dy: 36) }
    }
    func testActualFormatterPaginatesCompleteCapturedReport() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let period = try PhysicianReportPeriod.resolve(.days7, ledger: .init(), asOf: now, timeZone: .gmt)
        let observations = (0..<80).map { index in
            PhysicianReportObservation(id: String(format: "synthetic-%03d", index), observedAt: now.addingTimeInterval(-60),
                metricID: "synthetic.review", value: nil, state: .needsReview, unit: "source detail", source: "Synthetic test",
                definitionVersion: "test.v1", detail: String(repeating: "Synthetic source detail for pagination verification. ", count: 16)
                    + "End of synthetic review \(index)", recordIDs: ["record-\(index)"], requiresReview: true, detailOnly: true)
        }
        let report = try PhysicianReportSnapshot(period: period, observations: observations, notes: [], questions: [],
            appVersion: "test", generatedAt: now, coverageDescription: "Synthetic pagination fixture")
        let formatter = try CompanionPhysicianView.printFormatter(for: report)
        XCTAssertEqual(formatter.text, report.reviewText)
        let pages = Pages(); pages.addPrintFormatter(formatter, startingAtPageAt: 0)
        pages.prepare(forDrawingPages: NSRange(location: 0, length: 1))
        XCTAssertGreaterThan(pages.numberOfPages, 1)
        let data = UIGraphicsPDFRenderer(bounds: pages.paperRect).pdfData { context in
            for page in 0..<pages.numberOfPages {
                context.beginPage(); pages.drawPage(at: page, in: pages.paperRect)
            }
        }
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, pages.numberOfPages)
        let content = try XCTUnwrap(document.string)
        let rendered = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
        rendered.name = "Synthetic captured report pagination"; rendered.lifetime = .keepAlways; add(rendered)
        let extracted = XCTAttachment(string: content)
        extracted.name = "Synthetic extracted print text"; extracted.lifetime = .keepAlways; add(extracted)
        let textWithoutLayoutBreaks = content.filter { !$0.isWhitespace }
        XCTAssertTrue(textWithoutLayoutBreaks.contains("Endofsyntheticreview79"))
        XCTAssertTrue(textWithoutLayoutBreaks.contains("record-79"))
        XCTAssertTrue(textWithoutLayoutBreaks.contains(report.id.uuidString))
    }
}
