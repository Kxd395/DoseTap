import Foundation
import Combine
import DoseCore
import DoseTapNearby

/// A reporting copy only; this target never opens the phone's clinical storage.
@MainActor
final class DashboardModel: ObservableObject {
    let connection = NearbyReportingSession(role: .reader)
    @Published private(set) var report: DashboardReportProjection?
    @Published private(set) var questionnaires: DashboardQuestionnaireProjection?
    @Published private(set) var snapshot: CloudDashboardSnapshot?
    @Published private(set) var error: String?
    private let cacheURL: URL
    private let now: () -> Date
    private let scope = "authenticated-nearby-report"
    private var cache: CloudDashboardCache?
    private var requiresForget = false
    private static let maximumBytes = 32 * 1024 * 1024

    init(cacheURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.now = now
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask)[0].appendingPathComponent("report.json")
        loadSavedReport()
        connection.onSnapshot = { [weak self] data, context in
            self?.receive(data, context: context)
        }
    }

    func request() {
        guard !requiresForget else {
            error = "The saved report could not be validated. Forget it before selecting a new source."
            return
        }
        do { try connection.requestSnapshot(); error = nil }
        catch { self.error = "Could not request a report. Check the nearby connection and try again." }
    }

    func presentConnectionError(_ message: String) { error = message }

    /// Clear the durable source pin only after deletion succeeds.
    func forgetReport() {
        connection.stop()
        do {
            do { try FileManager.default.removeItem(at: cacheURL) }
            catch {
                guard Self.isMissing(error) else { throw error }
            }
            cache = nil; report = nil; questionnaires = nil; snapshot = nil; requiresForget = false; error = nil
        } catch {
            self.error = "Could not remove the saved report. Its source remains selected; try Forget again."
        }
    }

    private func loadSavedReport() {
        do {
            let handle = try FileHandle(forReadingFrom: cacheURL)
            defer { try? handle.close() }
            var bytes = Data()
            while let chunk = try handle.read(upToCount: min(64 * 1024, Self.maximumBytes + 1 - bytes.count)), !chunk.isEmpty {
                bytes.append(chunk)
                guard bytes.count <= Self.maximumBytes else { throw DashboardSnapshotError.invalidPayload }
            }
            let candidate = try JSONDecoder().decode(CloudDashboardSnapshot.self, from: bytes)
            var next = CloudDashboardCache(accountScope: scope, sourceID: candidate.sourceID)
            try next.accept(candidate, accountScope: scope, now: now())
            let projected = try DashboardReportProjection(snapshot: candidate, now: now())
            let answers = try DashboardQuestionnaireProjection(snapshot: candidate, now: now())
            try protectExistingCache()
            cache = next; snapshot = candidate; report = projected; questionnaires = answers
        } catch {
            if Self.isMissing(error) { return }
            requiresForget = true
            self.error = "The saved report is unavailable or invalid. It was not replaced. Try reopening after unlocking, or explicitly forget it."
        }
    }

    private static func isMissing(_ error: Error) -> Bool {
        let failure = error as NSError
        return failure.domain == NSCocoaErrorDomain
            && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code)
    }

    /// Internal for adapter tests; the transport authenticates before invoking it.
    func receive(_ bytes: Data, context: UUID) {
        guard connection.contextID == context else { return }
        guard !requiresForget else {
            error = "The previous saved report needs review or explicit removal before another source can be accepted."
            return
        }
        do {
            guard bytes.count <= Self.maximumBytes else { throw DashboardSnapshotError.invalidPayload }
            let candidate = try JSONDecoder().decode(CloudDashboardSnapshot.self, from: bytes)
            if let snapshot, snapshot.sourceID != candidate.sourceID {
                error = "This report is from a different source. Forget the saved report before changing sources."
                return
            }
            var next = cache ?? CloudDashboardCache(accountScope: scope, sourceID: candidate.sourceID)
            let changed = try next.accept(candidate, accountScope: scope, now: now())
            let projected = try DashboardReportProjection(snapshot: candidate, now: now())
            let answers = try DashboardQuestionnaireProjection(snapshot: candidate, now: now())
            guard connection.contextID == context else { return }
            if changed { try persist(bytes) }
            guard connection.contextID == context else { return }
            cache = next; snapshot = candidate; report = projected; questionnaires = answers; error = nil
        } catch {
            self.error = "The new report could not be validated or saved. The previous report remains unchanged."
        }
    }

    private func protectExistingCache() throws {
        var directory = cacheURL.deletingLastPathComponent()
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        try directory.setResourceValues(excluded)
        var file = cacheURL; try file.setResourceValues(excluded)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: cacheURL.path)
        #endif
    }

    /// Stage protected bytes and metadata first. Never delete the last good file
    /// as a fallback when atomic replacement fails.
    private func persist(_ bytes: Data) throws {
        let manager = FileManager.default
        var directory = cacheURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        try directory.setResourceValues(excluded)
        var staged = directory.appendingPathComponent(".report-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: staged) }
        #if os(iOS)
        try bytes.write(to: staged, options: [.atomic, .completeFileProtection])
        #else
        try bytes.write(to: staged, options: [.atomic])
        #endif
        try staged.setResourceValues(excluded)
        if manager.fileExists(atPath: cacheURL.path) {
            _ = try manager.replaceItemAt(cacheURL, withItemAt: staged, backupItemName: nil, options: .usingNewMetadataOnly)
        } else {
            try manager.moveItem(at: staged, to: cacheURL)
        }
    }
}
