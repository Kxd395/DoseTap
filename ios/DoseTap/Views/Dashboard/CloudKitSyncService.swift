import SwiftUI
import DoseCore
import os.log
#if canImport(CloudKit)
import CloudKit
#endif

private let cloudSyncLogger = Logger(subsystem: "com.dosetap.app", category: "CloudKitSync")

@MainActor
// MARK: - CloudKit Sync (P1-5: DEFERRED — requires iCloud entitlement + Apple Developer Team)
//
// This service is a complete implementation (~600 LOC) but is non-functional because:
// 1. iCloud entitlement is not enabled in the Xcode project
// 2. Requires a paid Apple Developer Team profile for CloudKit container
//
// The code is guarded behind `DoseTapCloudSyncEnabled` Info.plist flag (defaults to false).
// Dashboard shows "Cloud Sync · Disabled" with explanation when inactive.
//
// To enable: add iCloud entitlement -> create CloudKit container -> set DoseTapCloudSyncEnabled=true
// See: docs/IMPROVEMENT_ROADMAP.md P1-5 for full plan.
final class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var statusMessage: String = "Not synced yet"

    private let sessionRepo = SessionRepository.shared
    private let sessionDateFormatter: DateFormatter = AppFormatters.sessionDate

    #if canImport(CloudKit)
    private let zoneID = CKRecordZone.ID(zoneName: "DoseTapZone", ownerName: CKCurrentUserDefaultName)
    private let zoneChangeTokenDefaultsKey = "cloudkit.zone.token.dosetap.v1"
    private let sessionRecordType = "DoseTapSession"
    private let sleepEventRecordType = "DoseTapSleepEvent"
    private let doseEventRecordType = "DoseTapDoseEvent"
    private let morningCheckInRecordType = "DoseTapMorningCheckIn"
    private let preSleepLogRecordType = "DoseTapPreSleepLog"
    private let medicationEventRecordType = "DoseTapMedicationEvent"

    private struct ZoneDeletedRecord {
        let recordID: CKRecord.ID
        let recordType: String?
    }

    private struct ZoneChangeBatch {
        let changedRecords: [CKRecord]
        let deletedRecords: [ZoneDeletedRecord]
        let newToken: CKServerChangeToken?
    }

    private lazy var hasCloudKitEntitlement: Bool = {
        // iOS does not provide a public entitlements API here.
        // Prefer explicit config if present; otherwise allow runtime account checks
        // to decide availability.
        if let flag = Bundle.main.object(forInfoDictionaryKey: "DoseTapCloudSyncEnabled") {
            if let boolValue = flag as? Bool {
                return boolValue
            }
            if let numberValue = flag as? NSNumber {
                return numberValue.boolValue
            }
            if let stringValue = flag as? String {
                return ["1", "true", "yes"].contains(stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
        }
        // Fail closed if the build has no explicit cloud-sync toggle.
        return false
    }()

    private struct CloudKitContext {
        let container: CKContainer
        let privateDatabase: CKDatabase
    }

    private lazy var cloudKitContext: CloudKitContext? = {
        guard hasCloudKitEntitlement else { return nil }
        let container = CKContainer.default()
        return CloudKitContext(container: container, privateDatabase: container.privateCloudDatabase)
    }()

    private var cloudKitContainer: CKContainer? {
        cloudKitContext?.container
    }

    private var cloudKitDatabase: CKDatabase? {
        cloudKitContext?.privateDatabase
    }
    #endif

    enum SyncError: LocalizedError {
        case cloudKitUnavailable
        case accountNotAvailable
        case zoneSetupFailed
        case syncDisabledByBuild

        var errorDescription: String? {
            switch self {
            case .cloudKitUnavailable:
                return "CloudKit is unavailable on this platform build."
            case .accountNotAvailable:
                return "iCloud account is not available for private database sync."
            case .zoneSetupFailed:
                return "Could not initialize CloudKit zone."
            case .syncDisabledByBuild:
                return "Cloud sync is disabled for this build."
            }
        }
    }

    var cloudSyncAvailableInBuild: Bool {
        #if canImport(CloudKit)
        return hasCloudKitEntitlement
        #else
        return false
        #endif
    }

    func syncNow(days: Int = 120) async throws {
        guard days > 0 else { return }
        isSyncing = true
        defer { isSyncing = false }

        #if canImport(CloudKit)
        guard hasCloudKitEntitlement else {
            statusMessage = "Cloud sync unavailable in this build (missing iCloud entitlement)."
            throw SyncError.syncDisabledByBuild
        }

        statusMessage = "Checking iCloud account..."
        let accountStatus = try await fetchAccountStatus()
        guard accountStatus == .available else {
            throw SyncError.accountNotAvailable
        }

        statusMessage = "Preparing CloudKit zone..."
        try await ensureZoneExists()

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let cutoffKey = sessionDateFormatter.string(from: cutoffDate)

        statusMessage = "Uploading local records..."
        let uploadRecords = buildUploadRecords(cutoffKey: cutoffKey)
        try await saveRecordsInChunks(uploadRecords, chunkSize: 200)

        statusMessage = "Uploading deletions..."
        let tombstones = sessionRepo.fetchCloudKitTombstones(limit: 5000)
        let clearedTombstoneKeys = try await applyCloudKitDeletesInChunks(tombstones, chunkSize: 200)
        if !clearedTombstoneKeys.isEmpty {
            sessionRepo.clearCloudKitTombstones(keys: Array(clearedTombstoneKeys))
        }

        statusMessage = "Downloading incremental changes..."
        let previousToken = loadServerChangeToken()
        let changes = try await fetchZoneChangesWithRecovery(previousToken: previousToken)

        applyChangedRecords(changes.changedRecords)
        applyDeletedRecords(changes.deletedRecords)
        sessionRepo.finalizeSyncImport()
        saveServerChangeToken(changes.newToken)

        lastSyncDate = Date()
        statusMessage = "Sync complete (\(uploadRecords.count) up, \(clearedTombstoneKeys.count) outbound deletes, \(changes.changedRecords.count) changed, \(changes.deletedRecords.count) inbound deletes)"
        #else
        throw SyncError.cloudKitUnavailable
        #endif
    }

    #if canImport(CloudKit)
    private func buildUploadRecords(cutoffKey: String) -> [CKRecord] {
        let keys = sessionRepo
            .allSessionDatesForSync()
            .filter { $0 >= cutoffKey }

        var records: [CKRecord] = []
        for sessionDate in keys {
            let sessionId = sessionRepo.fetchSessionId(forSessionDate: sessionDate) ?? sessionDate
            let doseLog = sessionRepo.fetchDoseLog(forSession: sessionDate)
            let sleepEvents = sessionRepo.fetchSleepEvents(for: sessionDate)
            let doseEvents = sessionRepo.fetchDoseEvents(forSessionDate: sessionDate)
            let morningCheckIn = sessionRepo.fetchMorningCheckIn(for: sessionDate)
            let preSleepLog = sessionRepo.fetchPreSleepLog(forSessionDate: sessionDate)
            let medicationEvents = sessionRepo.fetchStoredMedicationEntries(for: sessionDate)

            if doseLog != nil || !sleepEvents.isEmpty || !doseEvents.isEmpty || morningCheckIn != nil || preSleepLog != nil || !medicationEvents.isEmpty {
                records.append(sessionRecord(
                    sessionDate: sessionDate,
                    sessionId: sessionId,
                    doseLog: doseLog,
                    sleepEvents: sleepEvents.count,
                    doseEvents: doseEvents.count,
                    hasMorningCheckIn: morningCheckIn != nil,
                    hasPreSleepLog: preSleepLog != nil,
                    medicationEvents: medicationEvents.count
                ))
            }

            for event in sleepEvents {
                records.append(sleepEventRecord(event: event, sessionId: sessionId))
            }

            for event in doseEvents {
                records.append(doseEventRecord(event: event, sessionId: sessionId))
            }

            if let checkIn = morningCheckIn {
                records.append(morningCheckInRecord(checkIn: checkIn))
            }
            if let preSleepLog {
                records.append(preSleepLogRecord(log: preSleepLog, sessionDate: sessionDate))
            }
            for medication in medicationEvents {
                records.append(medicationEventRecord(entry: medication))
            }
        }
        return records
    }

    private func sessionRecord(
        sessionDate: String,
        sessionId: String,
        doseLog: StoredDoseLog?,
        sleepEvents: Int,
        doseEvents: Int,
        hasMorningCheckIn: Bool,
        hasPreSleepLog: Bool,
        medicationEvents: Int
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: sessionDate, zoneID: zoneID)
        let record = CKRecord(recordType: sessionRecordType, recordID: recordID)
        record["sessionDate"] = sessionDate as CKRecordValue
        record["sessionId"] = sessionId as CKRecordValue
        record["dose1At"] = doseLog?.dose1Time as CKRecordValue?
        record["dose2At"] = doseLog?.dose2Time as CKRecordValue?
        record["dose2Skipped"] = (doseLog?.dose2Skipped ?? false) as CKRecordValue
        record["snoozeCount"] = (doseLog?.snoozeCount ?? 0) as CKRecordValue
        record["sleepEventCount"] = sleepEvents as CKRecordValue
        record["doseEventCount"] = doseEvents as CKRecordValue
        record["hasMorningCheckIn"] = hasMorningCheckIn as CKRecordValue
        record["hasPreSleepLog"] = hasPreSleepLog as CKRecordValue
        record["medicationEventCount"] = medicationEvents as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        return record
    }

    private func sleepEventRecord(event: StoredSleepEvent, sessionId: String) -> CKRecord {
        let recordID = CKRecord.ID(recordName: event.id, zoneID: zoneID)
        let record = CKRecord(recordType: sleepEventRecordType, recordID: recordID)
        record["eventType"] = event.eventType as CKRecordValue
        record["timestamp"] = event.timestamp as CKRecordValue
        record["sessionDate"] = event.sessionDate as CKRecordValue
        record["sessionId"] = sessionId as CKRecordValue
        record["colorHex"] = event.colorHex as CKRecordValue?
        record["notes"] = event.notes as CKRecordValue?
        record["updatedAt"] = Date() as CKRecordValue
        return record
    }

    private func doseEventRecord(event: DoseCore.StoredDoseEvent, sessionId: String) -> CKRecord {
        let recordID = CKRecord.ID(recordName: event.id, zoneID: zoneID)
        let record = CKRecord(recordType: doseEventRecordType, recordID: recordID)
        record["eventType"] = event.eventType as CKRecordValue
        record["timestamp"] = event.timestamp as CKRecordValue
        record["sessionDate"] = event.sessionDate as CKRecordValue
        record["sessionId"] = sessionId as CKRecordValue
        record["metadata"] = event.metadata as CKRecordValue?
        record["updatedAt"] = Date() as CKRecordValue
        return record
    }

    private func morningCheckInRecord(checkIn: StoredMorningCheckIn) -> CKRecord {
        let recordID = CKRecord.ID(recordName: checkIn.id, zoneID: zoneID)
        let record = CKRecord(recordType: morningCheckInRecordType, recordID: recordID)
        record["sessionId"] = checkIn.sessionId as CKRecordValue
        record["sessionDate"] = checkIn.sessionDate as CKRecordValue
        record["timestamp"] = checkIn.timestamp as CKRecordValue
        record["sleepQuality"] = checkIn.sleepQuality as CKRecordValue
        record["feelRested"] = checkIn.feelRested as CKRecordValue
        record["grogginess"] = checkIn.grogginess as CKRecordValue
        record["sleepInertiaDuration"] = checkIn.sleepInertiaDuration as CKRecordValue
        record["dreamRecall"] = checkIn.dreamRecall as CKRecordValue
        record["hasPhysicalSymptoms"] = checkIn.hasPhysicalSymptoms as CKRecordValue
        record["physicalSymptomsJson"] = checkIn.physicalSymptomsJson as CKRecordValue?
        record["hasRespiratorySymptoms"] = checkIn.hasRespiratorySymptoms as CKRecordValue
        record["respiratorySymptomsJson"] = checkIn.respiratorySymptomsJson as CKRecordValue?
        record["mentalClarity"] = checkIn.mentalClarity as CKRecordValue
        record["mood"] = checkIn.mood as CKRecordValue
        record["anxietyLevel"] = checkIn.anxietyLevel as CKRecordValue
        record["stressLevel"] = checkIn.stressLevel as CKRecordValue?
        record["stressContextJson"] = checkIn.stressContextJson as CKRecordValue?
        record["readinessForDay"] = checkIn.readinessForDay as CKRecordValue
        record["hadSleepParalysis"] = checkIn.hadSleepParalysis as CKRecordValue
        record["hadHallucinations"] = checkIn.hadHallucinations as CKRecordValue
        record["hadAutomaticBehavior"] = checkIn.hadAutomaticBehavior as CKRecordValue
        record["fellOutOfBed"] = checkIn.fellOutOfBed as CKRecordValue
        record["hadConfusionOnWaking"] = checkIn.hadConfusionOnWaking as CKRecordValue
        record["usedSleepTherapy"] = checkIn.usedSleepTherapy as CKRecordValue
        record["sleepTherapyJson"] = checkIn.sleepTherapyJson as CKRecordValue?
        record["hasSleepEnvironment"] = checkIn.hasSleepEnvironment as CKRecordValue
        record["sleepEnvironmentJson"] = checkIn.sleepEnvironmentJson as CKRecordValue?
        record["notes"] = checkIn.notes as CKRecordValue?
        record["updatedAt"] = Date() as CKRecordValue
        return record
    }

    private func preSleepLogRecord(log: StoredPreSleepLog, sessionDate: String) -> CKRecord {
        let recordID = CKRecord.ID(recordName: log.id, zoneID: zoneID)
        let record = CKRecord(recordType: preSleepLogRecordType, recordID: recordID)
        record["sessionId"] = log.sessionId as CKRecordValue?
        record["sessionDate"] = sessionDate as CKRecordValue
        record["createdAtUTC"] = (AppFormatters.iso8601Fractional.date(from: log.createdAtUtc) ?? Date()) as CKRecordValue
        record["localOffsetMinutes"] = log.localOffsetMinutes as CKRecordValue
        record["completionState"] = log.completionState as CKRecordValue
        if let answers = log.answers,
           let data = try? JSONEncoder().encode(answers),
           let json = String(data: data, encoding: .utf8) {
            record["answersJson"] = json as CKRecordValue
        } else {
            record["answersJson"] = "{}" as CKRecordValue
        }
        record["updatedAt"] = Date() as CKRecordValue
        return record
    }

    private func medicationEventRecord(entry: StoredMedicationEntry) -> CKRecord {
        let recordID = CKRecord.ID(recordName: entry.id, zoneID: zoneID)
        let record = CKRecord(recordType: medicationEventRecordType, recordID: recordID)
        record["sessionId"] = entry.sessionId as CKRecordValue?
        record["sessionDate"] = entry.sessionDate as CKRecordValue
        record["medicationId"] = entry.medicationId as CKRecordValue
        record["doseMg"] = entry.doseMg as CKRecordValue
        record["doseUnit"] = entry.doseUnit as CKRecordValue
        record["formulation"] = entry.formulation as CKRecordValue
        record["takenAtUTC"] = entry.takenAtUTC as CKRecordValue
        record["localOffsetMinutes"] = entry.localOffsetMinutes as CKRecordValue
        record["notes"] = entry.notes as CKRecordValue?
        record["confirmedDuplicate"] = entry.confirmedDuplicate as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        return record
    }

    private func applySleepRecords(_ records: [CKRecord]) {
        for record in records {
            guard
                let eventType = record["eventType"] as? String,
                let timestamp = record["timestamp"] as? Date,
                let sessionDate = record["sessionDate"] as? String
            else {
                continue
            }
            let sessionId = record["sessionId"] as? String
            let colorHex = record["colorHex"] as? String
            let notes = record["notes"] as? String
            sessionRepo.upsertSleepEventFromSync(
                id: record.recordID.recordName,
                eventType: eventType,
                timestamp: timestamp,
                sessionDate: sessionDate,
                sessionId: sessionId,
                colorHex: colorHex,
                notes: notes
            )
        }
    }

    private func applyDoseRecords(_ records: [CKRecord]) {
        for record in records {
            guard
                let eventType = record["eventType"] as? String,
                let timestamp = record["timestamp"] as? Date,
                let sessionDate = record["sessionDate"] as? String
            else {
                continue
            }
            let sessionId = record["sessionId"] as? String
            let metadata = record["metadata"] as? String
            sessionRepo.upsertDoseEventFromSync(
                id: record.recordID.recordName,
                eventType: eventType,
                timestamp: timestamp,
                sessionDate: sessionDate,
                sessionId: sessionId,
                metadata: metadata
            )
        }
    }

    private func applyMorningCheckInRecords(_ records: [CKRecord]) {
        for record in records {
            guard
                let sessionId = record["sessionId"] as? String,
                let sessionDate = record["sessionDate"] as? String,
                let timestamp = record["timestamp"] as? Date
            else {
                continue
            }

            let checkIn = StoredMorningCheckIn(
                id: record.recordID.recordName,
                sessionId: sessionId,
                timestamp: timestamp,
                sessionDate: sessionDate,
                sleepQuality: record["sleepQuality"] as? Int ?? 3,
                feelRested: record["feelRested"] as? String ?? "moderate",
                grogginess: record["grogginess"] as? String ?? "mild",
                sleepInertiaDuration: record["sleepInertiaDuration"] as? String ?? "fiveToFifteen",
                dreamRecall: record["dreamRecall"] as? String ?? "none",
                hasPhysicalSymptoms: record["hasPhysicalSymptoms"] as? Bool ?? false,
                physicalSymptomsJson: record["physicalSymptomsJson"] as? String,
                hasRespiratorySymptoms: record["hasRespiratorySymptoms"] as? Bool ?? false,
                respiratorySymptomsJson: record["respiratorySymptomsJson"] as? String,
                mentalClarity: record["mentalClarity"] as? Int ?? 5,
                mood: record["mood"] as? String ?? "neutral",
                anxietyLevel: record["anxietyLevel"] as? String ?? "none",
                stressLevel: record["stressLevel"] as? Int,
                stressContextJson: record["stressContextJson"] as? String,
                readinessForDay: record["readinessForDay"] as? Int ?? 3,
                hadSleepParalysis: record["hadSleepParalysis"] as? Bool ?? false,
                hadHallucinations: record["hadHallucinations"] as? Bool ?? false,
                hadAutomaticBehavior: record["hadAutomaticBehavior"] as? Bool ?? false,
                fellOutOfBed: record["fellOutOfBed"] as? Bool ?? false,
                hadConfusionOnWaking: record["hadConfusionOnWaking"] as? Bool ?? false,
                usedSleepTherapy: record["usedSleepTherapy"] as? Bool ?? false,
                sleepTherapyJson: record["sleepTherapyJson"] as? String,
                hasSleepEnvironment: record["hasSleepEnvironment"] as? Bool ?? false,
                sleepEnvironmentJson: record["sleepEnvironmentJson"] as? String,
                notes: record["notes"] as? String
            )
            sessionRepo.upsertMorningCheckInFromSync(checkIn)
        }
    }

    private func applyPreSleepLogRecords(_ records: [CKRecord]) {
        for record in records {
            guard
                let sessionDate = record["sessionDate"] as? String,
                let createdAtUTC = record["createdAtUTC"] as? Date,
                let completionState = record["completionState"] as? String
            else {
                continue
            }

            let sessionId = record["sessionId"] as? String
            let localOffsetMinutes = record["localOffsetMinutes"] as? Int ?? 0
            let answersJson = record["answersJson"] as? String ?? "{}"
            let answers: PreSleepLogAnswers?
            if let data = answersJson.data(using: .utf8) {
                answers = try? JSONDecoder().decode(PreSleepLogAnswers.self, from: data)
            } else {
                answers = nil
            }

            let log = StoredPreSleepLog(
                id: record.recordID.recordName,
                sessionId: sessionId,
                createdAtUtc: AppFormatters.iso8601Fractional.string(from: createdAtUTC),
                localOffsetMinutes: localOffsetMinutes,
                completionState: completionState,
                answers: answers
            )
            sessionRepo.upsertPreSleepLogFromSync(log, sessionDate: sessionDate)
        }
    }

    private func applyMedicationRecords(_ records: [CKRecord]) {
        for record in records {
            guard
                let sessionDate = record["sessionDate"] as? String,
                let medicationId = record["medicationId"] as? String,
                let doseMg = record["doseMg"] as? Int,
                let doseUnit = record["doseUnit"] as? String,
                let formulation = record["formulation"] as? String,
                let takenAtUTC = record["takenAtUTC"] as? Date
            else {
                continue
            }

            let entry = StoredMedicationEntry(
                id: record.recordID.recordName,
                sessionId: record["sessionId"] as? String,
                sessionDate: sessionDate,
                medicationId: medicationId,
                doseMg: doseMg,
                takenAtUTC: takenAtUTC,
                doseUnit: doseUnit,
                formulation: formulation,
                localOffsetMinutes: record["localOffsetMinutes"] as? Int ?? 0,
                notes: record["notes"] as? String,
                confirmedDuplicate: record["confirmedDuplicate"] as? Bool ?? false
            )
            sessionRepo.upsertMedicationEventFromSync(entry)
        }
    }

    private func applyChangedRecords(_ records: [CKRecord]) {
        var sleepRecords: [CKRecord] = []
        var doseRecords: [CKRecord] = []
        var morningRecords: [CKRecord] = []
        var preSleepRecords: [CKRecord] = []
        var medicationRecords: [CKRecord] = []

        for record in records {
            switch record.recordType {
            case sleepEventRecordType:
                sleepRecords.append(record)
            case doseEventRecordType:
                doseRecords.append(record)
            case morningCheckInRecordType:
                morningRecords.append(record)
            case preSleepLogRecordType:
                preSleepRecords.append(record)
            case medicationEventRecordType:
                medicationRecords.append(record)
            default:
                continue
            }
        }

        applySleepRecords(sleepRecords)
        applyDoseRecords(doseRecords)
        applyMorningCheckInRecords(morningRecords)
        applyPreSleepLogRecords(preSleepRecords)
        applyMedicationRecords(medicationRecords)
    }

    private func applyDeletedRecords(_ records: [ZoneDeletedRecord]) {
        guard !records.isEmpty else { return }

        for deleted in records {
            switch deleted.recordType {
            case sessionRecordType:
                let key = deleted.recordID.recordName
                if looksLikeSessionDate(key) {
                    sessionRepo.deleteSessionFromSync(sessionDate: key)
                }
            case sleepEventRecordType:
                sessionRepo.deleteSleepEventFromSync(id: deleted.recordID.recordName)
            case doseEventRecordType:
                sessionRepo.deleteDoseEventFromSync(id: deleted.recordID.recordName)
            case morningCheckInRecordType:
                sessionRepo.deleteMorningCheckInFromSync(id: deleted.recordID.recordName)
            case preSleepLogRecordType:
                sessionRepo.deletePreSleepLogFromSync(id: deleted.recordID.recordName)
            case medicationEventRecordType:
                sessionRepo.deleteMedicationEventFromSync(id: deleted.recordID.recordName)
            default:
                let key = deleted.recordID.recordName
                if looksLikeSessionDate(key) {
                    sessionRepo.deleteSessionFromSync(sessionDate: key)
                }
            }
        }
    }

    private func fetchAccountStatus() async throws -> CKAccountStatus {
        guard let container = cloudKitContainer else {
            throw SyncError.syncDisabledByBuild
        }
        return try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func ensureZoneExists() async throws {
        guard let db = cloudKitDatabase else {
            throw SyncError.syncDisabledByBuild
        }
        let zone = CKRecordZone(zoneID: zoneID)
        try await withCheckedThrowingContinuation { continuation in
            let op = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            op.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case .failure(let error):
                    cloudSyncLogger.error("CloudKit zone ensure failed: \(error.localizedDescription)")
                    continuation.resume(throwing: SyncError.zoneSetupFailed)
                }
            }
            db.add(op)
        }
    }

    private func saveRecordsInChunks(_ records: [CKRecord], chunkSize: Int) async throws {
        guard !records.isEmpty else { return }
        guard let db = cloudKitDatabase else {
            throw SyncError.syncDisabledByBuild
        }
        var index = 0
        while index < records.count {
            let end = min(index + chunkSize, records.count)
            let chunk = Array(records[index..<end])
            try await withCheckedThrowingContinuation { continuation in
                let op = CKModifyRecordsOperation(recordsToSave: chunk, recordIDsToDelete: nil)
                op.savePolicy = .changedKeys
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: ())
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                db.add(op)
            }
            index = end
        }
    }

    private func applyCloudKitDeletesInChunks(_ tombstones: [CloudKitTombstone], chunkSize: Int) async throws -> Set<String> {
        guard !tombstones.isEmpty else { return [] }

        var clearedKeys: Set<String> = []
        var index = 0
        while index < tombstones.count {
            let end = min(index + chunkSize, tombstones.count)
            let chunk = Array(tombstones[index..<end])
            let succeeded = try await deleteCloudKitChunk(chunk)
            clearedKeys.formUnion(succeeded)
            index = end
        }

        return clearedKeys
    }

    private func deleteCloudKitChunk(_ chunk: [CloudKitTombstone]) async throws -> Set<String> {
        guard !chunk.isEmpty else { return [] }
        guard let db = cloudKitDatabase else {
            throw SyncError.syncDisabledByBuild
        }

        let ids = chunk.map { CKRecord.ID(recordName: $0.recordName, zoneID: zoneID) }
        var keyByRecordID: [CKRecord.ID: String] = [:]
        for tombstone in chunk {
            let recordID = CKRecord.ID(recordName: tombstone.recordName, zoneID: zoneID)
            keyByRecordID[recordID] = tombstone.key
        }

        return try await withCheckedThrowingContinuation { continuation in
            let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: Set(chunk.map(\.key)))
                case .failure(let error):
                    if let ckError = error as? CKError {
                        if ckError.code == .unknownItem {
                            continuation.resume(returning: Set(chunk.map(\.key)))
                            return
                        }

                        if ckError.code == .partialFailure,
                           let partial = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                            var failedKeys: Set<String> = []
                            for (key, itemError) in partial {
                                guard let recordID = key as? CKRecord.ID else { continue }
                                if let itemCKError = itemError as? CKError, itemCKError.code == .unknownItem {
                                    continue
                                }
                                if let tombstoneKey = keyByRecordID[recordID] {
                                    failedKeys.insert(tombstoneKey)
                                }
                            }

                            let allKeys = Set(chunk.map(\.key))
                            let succeeded = allKeys.subtracting(failedKeys)
                            if !succeeded.isEmpty {
                                continuation.resume(returning: succeeded)
                                return
                            }
                        }
                    }
                    continuation.resume(throwing: error)
                }
            }
            db.add(op)
        }
    }

    private func fetchZoneChangesWithRecovery(previousToken: CKServerChangeToken?) async throws -> ZoneChangeBatch {
        do {
            return try await fetchZoneChanges(previousToken: previousToken)
        } catch let ckError as CKError where ckError.code == .changeTokenExpired {
            statusMessage = "Cloud history token expired, refreshing full state..."
            clearServerChangeToken()
            return try await fetchZoneChanges(previousToken: nil)
        }
    }

    private func fetchZoneChanges(previousToken: CKServerChangeToken?) async throws -> ZoneChangeBatch {
        guard let db = cloudKitDatabase else {
            throw SyncError.syncDisabledByBuild
        }
        return try await withCheckedThrowingContinuation { continuation in
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = previousToken

            let op = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )

            let lock = NSLock()
            var changedRecords: [CKRecord] = []
            var deletedRecords: [ZoneDeletedRecord] = []
            var newestToken: CKServerChangeToken? = previousToken

            op.recordWasChangedBlock = { _, result in
                if case let .success(record) = result {
                    lock.lock()
                    changedRecords.append(record)
                    lock.unlock()
                }
            }

            op.recordWithIDWasDeletedBlock = { recordID, recordType in
                lock.lock()
                deletedRecords.append(ZoneDeletedRecord(recordID: recordID, recordType: recordType))
                lock.unlock()
            }

            op.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
                guard let token else { return }
                lock.lock()
                newestToken = token
                lock.unlock()
            }

            op.recordZoneFetchResultBlock = { _, result in
                if case let .success(zoneResult) = result {
                    let token = zoneResult.serverChangeToken
                    lock.lock()
                    newestToken = token
                    lock.unlock()
                }
            }

            op.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    lock.lock()
                    let output = ZoneChangeBatch(
                        changedRecords: changedRecords,
                        deletedRecords: deletedRecords,
                        newToken: newestToken
                    )
                    lock.unlock()
                    continuation.resume(returning: output)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            db.add(op)
        }
    }

    private func looksLikeSessionDate(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        return sessionDateFormatter.date(from: value) != nil
    }

    private func loadServerChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: zoneChangeTokenDefaultsKey) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveServerChangeToken(_ token: CKServerChangeToken?) {
        guard let token else {
            clearServerChangeToken()
            return
        }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: zoneChangeTokenDefaultsKey)
        }
    }

    private func clearServerChangeToken() {
        UserDefaults.standard.removeObject(forKey: zoneChangeTokenDefaultsKey)
    }
    #endif
}
