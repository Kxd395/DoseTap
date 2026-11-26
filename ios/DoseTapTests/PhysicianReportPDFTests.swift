import XCTest
import PDFKit
import DoseCore
@testable import DoseTap

@MainActor
final class PhysicianReportPDFTests: XCTestCase {
    func testPDFPreservesSourceDenominatorAndLongQuestionsAcrossPages() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let period = try PhysicianReportPeriod.resolve(.days28, ledger: .init(), asOf: now, timeZone: TimeZone(identifier: "America/New_York")!)
        let observation = PhysicianReportObservation(id: "source-1", observedAt: now.addingTimeInterval(-1), metricID: "Synthetic sleep",
            value: 120, state: .available, unit: "minutes", source: "Synthetic source", definitionVersion: "definition.v1", detail: "Preserved detail", recordIDs: ["raw-1"])
        let questions = (0..<18).map { index in String(repeating: "Synthetic question \(index). ", count: 60) }
        let snapshot = try PhysicianReportSnapshot(period: period, observations: [observation], notes: [],
            questions: questions + ["FINAL QUESTION RETAINED"], appVersion: "test", generatedAt: now)
        let data = try PhysicianReportPDF.render(snapshot)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "Physician review synthetic pagination"; attachment.lifetime = .keepAlways; add(attachment)
        let pdf = try XCTUnwrap(PDFDocument(data: data)), text = try XCTUnwrap(pdf.string)
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(text.contains("Synthetic source"))
        XCTAssertTrue(text.contains("1/1 eligible"))
        XCTAssertTrue(text.contains("America/New_York"))
        XCTAssertTrue(text.contains("2026-12"))
        XCTAssertTrue(text.contains("No observations recorded"))
        XCTAssertTrue(text.contains("13 calendar days"))
        XCTAssertTrue(text.contains("FINAL QUESTION RETAINED"))
        XCTAssertTrue(text.contains(snapshot.id.uuidString))
    }
}
