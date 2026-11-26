import SwiftUI
import UniformTypeIdentifiers

/// A deliberate local export of the immutable reporting copy currently inspected.
struct CompanionReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    var contentType: UTType
    init(data: Data = Data(), contentType: UTType = .commaSeparatedText) {
        self.data = data; self.contentType = contentType
    }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data; contentType = configuration.contentType
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
