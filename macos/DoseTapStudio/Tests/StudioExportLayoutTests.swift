import XCTest
import SwiftUI
import AppKit
@testable import DoseTapStudio

final class StudioExportLayoutTests: XCTestCase {
    @MainActor
    func testExportScreenPreviewsAtCompactAndWideWidths() async throws {
        guard let output = ProcessInfo.processInfo.environment["DOSETAP_EXPORT_LAYOUT_PREVIEW"],
              let fixture = ProcessInfo.processInfo.environment["DOSETAP_IOS_EXPORT_FIXTURE"] else {
            throw XCTSkip("Set DOSETAP_EXPORT_LAYOUT_PREVIEW and DOSETAP_IOS_EXPORT_FIXTURE for visual review.")
        }
        let store = DataStore()
        await store.loadAll(from: URL(fileURLWithPath: fixture))
        XCTAssertEqual(store.insightSessions.count, 1)
        XCTAssertNotNil(store.importedInsightsBundle?.appVersion)
        for width in [640, 1000] {
            let host = NSHostingView(rootView: ExportView(dataStore: store)
                .frame(width: CGFloat(width), height: 900)
                .environment(\.colorScheme, .dark))
            host.frame = NSRect(x: 0, y: 0, width: width, height: 900)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, width)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "\(output)-\(width).png"))
            XCTAssertGreaterThan(png.count, 1000)
        }
        // PNG generation is not a no-clipping assertion. Inspect both previews and native controls.
    }
}
