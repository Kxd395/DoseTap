import Foundation

public struct SupplyBottleReceipt: Codable, Equatable, Identifiable {
    public var id: UUID
    public var count: Int
    public var receivedAt: Date
    public var recordedAt: Date
    public var voidedAt: Date?
    public init(id: UUID, count: Int, receivedAt: Date, recordedAt: Date) {
        self.id = id; self.count = count; self.receivedAt = receivedAt; self.recordedAt = recordedAt
    }
}

public enum SupplyTrackingError: LocalizedError {
    case invalid, conflictingIdentity, noStock, correctionUnavailable
    public var errorDescription: String? {
        switch self {
        case .invalid: return "Check the bottle count and dates. No supply changes were saved."
        case .conflictingIdentity: return "This supply action was already recorded with different details. Reload supply before trying again."
        case .noStock: return "No unopened bottles remain in this receipt. Record received bottles first."
        case .correctionUnavailable: return "Undo the latest bottle opening first. A receipt with an active opening cannot be undone."
        }
    }
}

extension SupplyBackup {
    public var activeBottleStart: SupplyBottleStart? {
        bottleStarts.filter { $0.voidedAt == nil }.max { $0.openedAt < $1.openedAt }
    }
    public var trackedUnopenedBottleCount: Int? {
        receipts.map { $0.filter { $0.voidedAt == nil }.reduce(0) { $0 + $1.count } -
            bottleStarts.filter { $0.receiptID != nil && $0.voidedAt == nil }.count }
    }
    public var currentReceiptOrdinal: Int? {
        guard let active = activeBottleStart, let id = active.receiptID else { return nil }
        return bottleStarts.filter { $0.receiptID == id && $0.voidedAt == nil && $0.openedAt <= active.openedAt }.count
    }
    var trackingIsValid: Bool {
        if version == 1 { return receipts == nil && bottleStarts.allSatisfy { $0.receiptID == nil && $0.voidedAt == nil } }
        guard let receipts, receipts.count <= Self.maximumRecordCount,
              Set(receipts.map(\.id)).count == receipts.count else { return false }
        let byID = Dictionary(uniqueKeysWithValues: receipts.map { ($0.id, $0) })
        let startsByReceipt = Dictionary(grouping: bottleStarts.filter { $0.receiptID != nil }, by: { $0.receiptID! })
        for receipt in receipts {
            guard (1...100).contains(receipt.count),
                  receipt.receivedAt.timeIntervalSince1970.isFinite,
                  receipt.recordedAt.timeIntervalSince1970.isFinite,
                  receipt.receivedAt <= receipt.recordedAt,
                  receipt.voidedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= receipt.recordedAt }) ?? true
            else { return false }
            let starts = startsByReceipt[receipt.id] ?? []
            guard starts.filter({ $0.voidedAt == nil }).count <= receipt.count else { return false }
            if let voided = receipt.voidedAt,
               starts.contains(where: { $0.voidedAt == nil || $0.voidedAt! > voided }) { return false }
        }
        let openedTimes = Dictionary(grouping: bottleStarts.filter { $0.voidedAt == nil }, by: \.openedAt)
        for start in bottleStarts {
            if let id = start.receiptID {
                guard let receipt = byID[id], start.openedAt >= receipt.receivedAt,
                      start.recordedAt >= receipt.recordedAt else { return false }
            }
            if start.receiptID != nil, start.voidedAt == nil, (openedTimes[start.openedAt]?.count ?? 0) > 1 { return false }
        }
        return true
    }

    public mutating func receiveBottles(id: UUID, count: Int, receivedAt: Date, recordedAt: Date, now: Date = Date()) throws {
        let entry = SupplyBottleReceipt(id: id, count: count, receivedAt: receivedAt, recordedAt: recordedAt)
        guard isValid else { throw SupplyTrackingError.invalid }
        if let prior = receipts?.first(where: { $0.id == id }) {
            guard prior == entry else { throw SupplyTrackingError.conflictingIdentity }
            return
        }
        guard recordedAt <= now else { throw SupplyTrackingError.invalid }
        var candidate = self
        candidate.version = max(version, 2)
        candidate.receipts = (receipts ?? []) + [entry]
        try accept(candidate)
    }

    public mutating func startBottle(id: UUID, receiptID: UUID, openedAt: Date, recordedAt: Date, now: Date = Date()) throws {
        let entry = SupplyBottleStart(id: id, openedAt: openedAt, recordedAt: recordedAt, receiptID: receiptID)
        guard isValid else { throw SupplyTrackingError.invalid }
        if let prior = bottleStarts.first(where: { $0.id == id }) {
            guard prior == entry else { throw SupplyTrackingError.conflictingIdentity }
            return
        }
        guard let receipt = receipts?.first(where: { $0.id == receiptID && $0.voidedAt == nil }),
              bottleStarts.filter({ $0.receiptID == receiptID && $0.voidedAt == nil }).count < receipt.count
        else { throw SupplyTrackingError.noStock }
        guard recordedAt <= now, activeBottleStart.map({ openedAt > $0.openedAt }) ?? true else { throw SupplyTrackingError.invalid }
        var candidate = self
        candidate.version = max(version, 2)
        candidate.bottleStarts.append(entry)
        try accept(candidate)
    }

    public mutating func voidBottleStart(id: UUID, at time: Date, now: Date = Date()) throws {
        guard isValid, time <= now, let index = bottleStarts.firstIndex(where: { $0.id == id }) else { throw SupplyTrackingError.invalid }
        if bottleStarts[index].voidedAt == time { return }
        guard activeBottleStart?.id == id else { throw SupplyTrackingError.correctionUnavailable }
        var candidate = self
        candidate.version = max(version, 2)
        candidate.receipts = receipts ?? []
        candidate.bottleStarts[index].voidedAt = time
        try accept(candidate)
    }

    public mutating func voidReceipt(id: UUID, at time: Date, now: Date = Date()) throws {
        guard isValid, time <= now, let index = receipts?.firstIndex(where: { $0.id == id }) else { throw SupplyTrackingError.invalid }
        if receipts?[index].voidedAt == time { return }
        guard receipts?[index].voidedAt == nil,
              !bottleStarts.contains(where: { $0.receiptID == id && $0.voidedAt == nil }) else { throw SupplyTrackingError.correctionUnavailable }
        var candidate = self
        candidate.receipts?[index].voidedAt = time
        try accept(candidate)
    }

    private mutating func accept(_ candidate: SupplyBackup) throws {
        guard candidate.isValid else { throw SupplyTrackingError.invalid }
        self = candidate
    }
}
