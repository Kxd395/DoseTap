import Foundation

/// One application-process allocator. MainActor serializes reservation/write;
/// extensions or multiple writers require an explicit interprocess coordinator.
@MainActor
final class DashboardPublisherIdentity {
    struct Reservation: Codable, Equatable {
        let schemaVersion: Int
        let sourceID: String
        let sequence: UInt64
    }
    enum Failure: Error { case invalidState, exhausted }
    private let directory: URL
    private var stateURL: URL { directory.appendingPathComponent("publisher-identity.json") }
    init(directory: URL? = nil) throws {
        self.directory = try directory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("DashboardReporting", isDirectory: true)
    }
    /// Gaps are allowed after failed capture/send. An issued sequence is never reused.
    /// Missing state creates a new source, which requires reader source selection.
    func reserve() throws -> Reservation {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var folder = directory; try folder.setResourceValues(excluded)
        let previous: Reservation?
        do {
            let bytes = try Data(contentsOf: stateURL)
            let value = try JSONDecoder().decode(Reservation.self, from: bytes)
            guard value.schemaVersion == 1, UUID(uuidString: value.sourceID)?.uuidString == value.sourceID,
                  value.sequence > 0 else { throw Failure.invalidState }
            previous = value
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            previous = nil
        }
        guard previous?.sequence != UInt64.max else { throw Failure.exhausted }
        let next = Reservation(schemaVersion: 1, sourceID: previous?.sourceID ?? UUID().uuidString,
            sequence: (previous?.sequence ?? 0) + 1)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(next)
        try bytes.write(to: stateURL, options: [.atomic, .completeFileProtection])
        var file = stateURL; try file.setResourceValues(excluded)
        let handle = try FileHandle(forWritingTo: stateURL)
        defer { try? handle.close() }
        try handle.synchronize()
        // Do not return a reservation until the persisted bytes read back exactly.
        guard try Data(contentsOf: stateURL) == bytes else { throw Failure.invalidState }
        return next
    }
}
