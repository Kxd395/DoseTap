import UIKit
import DoseCore

@MainActor
enum PhysicianReportPDF {
    enum ExportError: Error { case layoutFailed }
    static func render(_ snapshot: PhysicianReportSnapshot) throws -> Data {
        try snapshot.validate()
        let paragraph = NSMutableParagraphStyle(); paragraph.paragraphSpacing = 7
        let text = NSTextStorage(string: snapshot.reviewText, attributes: [
            .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black, .paragraphStyle: paragraph
        ])
        let layout = NSLayoutManager(); text.addLayoutManager(layout)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "DoseTap physician review",
                               kCGPDFContextCreator as String: "DoseTap \(snapshot.appVersion)"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792), format: format)
        var failed = false
        let data = renderer.pdfData { context in
            var consumed = 0, page = 0
            while consumed < layout.numberOfGlyphs {
                let container = NSTextContainer(size: CGSize(width: 540, height: 708))
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                let range = layout.glyphRange(for: container)
                guard range.length > 0, NSMaxRange(range) > consumed else { failed = true; break }
                context.beginPage(); page += 1
                layout.drawBackground(forGlyphRange: range, at: CGPoint(x: 36, y: 36))
                layout.drawGlyphs(forGlyphRange: range, at: CGPoint(x: 36, y: 36))
                ("DoseTap • page \(page) • \(snapshot.id.uuidString)" as NSString).draw(at: CGPoint(x: 36, y: 760),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray])
                consumed = NSMaxRange(range)
            }
        }
        guard !failed, !data.isEmpty else { throw ExportError.layoutFailed }
        return data
    }
}
