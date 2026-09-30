import Foundation
import SQLite3
import DoseCore

@MainActor
extension EventStorage {
    /// Transport-independent source evidence, not normalized clinical observations.
    /// Caller owns durable installation identity and monotonic generation allocation.
    /// An existing write transaction is rejected so uncommitted records cannot escape.
    func dashboardSnapshot(sourceID: String, sequence: UInt64, capturedAt: Date, sleepEvidence: DashboardSleepEvidence? = nil) throws -> CloudDashboardSnapshot {
        guard !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, sequence > 0,
              capturedAt.timeIntervalSince1970.isFinite else { throw DashboardSnapshotError.invalidMetadata }
        let capturedTimeZoneID = TimeZone.current.identifier
        guard databaseInitializationFailure == nil, let db, sqlite3_get_autocommit(db) != 0,
              sqlite3_exec(db, "BEGIN DEFERRED", nil, nil, nil) == SQLITE_OK else {
            throw ExportReadError.unreadable
        }
        var committed = false
        defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }

        // Every SELECT shares one SQLite snapshot, including canonical medication
        // validation. No date discovery, row caps, source repair, or legacy sync.
        let sessions = try dashboardRows("sleep_sessions") + dashboardRows("current_session")
        let doses = try dashboardRows("dose_events")
        let quickLogs = try dashboardRows("sleep_events")
        let preSleep = try dashboardRows("pre_sleep_logs")
        let morning = try dashboardRows("morning_checkins")
        let answers = try dashboardRows("checkin_submissions")
        let medications = try dashboardRows("medication_events")
        _ = try medicationPresetExportSnapshot()
        let presets = try dashboardRows("medication_preset_revisions")
        let administrations = try dashboardRows("confirmed_medication_administrations")
        let inventory = try dashboardRows("inventory_snapshots") + dashboardRows("supply_state")
        let workSchedule = try dashboardRows("work_wake_schedule") + dashboardRows("work_block_context")
        let napDiary = try dashboardRows("nap_diary")
        // Audit/cache rows retain their own source tables; never count them as
        // additional symptom observations or rebuild them during a reporting read.
        let symptoms = try ["symptom_events", "symptom_locations", "body_map_points",
            "symptom_command_log", "symptom_summaries"].flatMap { try dashboardRows($0) }
        // Existing diary/window evidence is embedded in these original answers.
        // Shared rows are references, not additional observations or measured sleep.
        // Preserve the full envelope, including revisions and unknown future fields.
        let daytime = try dashboardRows("daytime_checkins") + dashboardRows("daytime_events")
        let nightOutcomes = answers.filter { $0.columns["checkin_type"]?.text == "night_outcome" }
        var sections: [DashboardSnapshotSection] = []
        for (dataset, records): (DashboardDataset, [StoredExportSourceRecord]) in [
            (.sessions, sessions), (.doseEvents, doses), (.quickLogs, quickLogs),
            (.preSleep, preSleep), (.morning, morning), (.normalizedAnswers, answers),
            (.medicationEntries, medications), (.presetVersions, presets), (.administrations, administrations),
            (.daytimeDiary, morning + nightOutcomes + daytime + napDiary), (.reviewedSleepWindows, nightOutcomes), (.inventory, inventory),
            (.symptoms, symptoms), (.workSchedule, workSchedule)
        ] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            sections.append(DashboardSnapshotSection(dataset: dataset, rows: try encoder.encode(records), rowCount: records.count))
        }
        // Amendment domain values exist, but this schema has no durable ledger.
        // Not-collected is deliberately different from a complete measured empty set.
        sections.append(DashboardSnapshotSection(notCollected: .amendments))
        for provider: DashboardDataset in [.appleHealth, .whoop] {
            sections.append(DashboardSnapshotSection(unavailable: provider,
                reason: "Provider reporting is unavailable pending explicit consent and permitted transport handling."))
        }
        let ledgers = try dashboardDoseReviews(now: capturedAt)
        var reviews: [DashboardSharedDoseReview] = []
        // Keep raw source export tolerant when there is no review to bind.
        if !ledgers.isEmpty {
            for local in try dashboardLocalSessions(inTransaction: true) where !local.needsReview {
                guard let sessionID = local.sessionID, let review = ledgers[local.id]?.current,
                      let shared = DashboardSharedDoseReview.project(review, sessionID: sessionID,
                          treatmentDate: local.sessionDate, events: local.doses, capturedAt: capturedAt) else { continue }
                reviews.append(shared)
            }
        }
        let visits = try physicianVisits(now: capturedAt).dashboardShared(now: capturedAt)
        // The opted-in packet and exact reviewed bindings share the same local
        // read transaction. No provider query or inferred date join occurs here.
        let sleepEpisodes = try sleepEvidence.map { try dashboardSharedSleepEpisodes(evidence: $0, capturedAt: capturedAt) }
        if let sleepEvidence, let index = sections.firstIndex(where: { $0.dataset == .appleHealth }) {
            sections[index] = try sleepEvidence.section()
        }
        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw ExportReadError.unreadable }
        committed = true
        var snapshot = CloudDashboardSnapshot(sourceID: sourceID, sequence: sequence, capturedAt: capturedAt, sections: sections)
        snapshot.reportingTimeZoneID = capturedTimeZoneID
        snapshot.doseReviews = reviews.sorted { $0.observationID < $1.observationID }
        snapshot.completedVisits = visits
        snapshot.sleepEpisodes = sleepEpisodes
        return snapshot
    }

    func dashboardRows(_ table: String) throws -> [StoredExportSourceRecord] {
        // Only the fixed producer mapping above can supply a table name.
        try readExportRows("SELECT * FROM \(table) ORDER BY rowid") { statement in
            var columns: [String: StoredExportColumn] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                guard let name = sqlite3_column_name(statement, index) else { throw ExportReadError.unreadable }
                columns[String(cString: name)] = try StoredExportColumn(statement: statement, index: index)
            }
            return StoredExportSourceRecord(sourceTable: table, columns: columns)
        }
    }
}
