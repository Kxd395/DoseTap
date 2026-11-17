import Foundation

public enum SupplyQuantityKind: String, Codable { case baseline, preparation, discard, doseLink }

/// A source snapshot for an allocation, never a second medication event.
public struct SupplyDoseEvidence: Codable, Equatable {
    public var eventID: String
    public var sessionID: String
    public var eventType: String
    public var occurredAt: Date
    public init(eventID: String, sessionID: String, eventType: String, occurredAt: Date) {
        self.eventID = eventID; self.sessionID = sessionID; self.eventType = eventType; self.occurredAt = occurredAt
    }
}

public struct SupplyQuantityEntry: Codable, Equatable, Identifiable {
    public var id: UUID
    public var bottleID: UUID
    public var kind: SupplyQuantityKind
    public var amountMg: Int
    public var occurredAt: Date
    public var recordedAt: Date
    public var reason: String
    public var preparationID: UUID?
    public var dose: SupplyDoseEvidence?
    public var voidedAt: Date?
    public init(id: UUID, bottleID: UUID, kind: SupplyQuantityKind, amountMg: Int,
                occurredAt: Date, recordedAt: Date, reason: String,
                preparationID: UUID? = nil, dose: SupplyDoseEvidence? = nil) {
        self.id = id; self.bottleID = bottleID; self.kind = kind; self.amountMg = amountMg
        self.occurredAt = occurredAt; self.recordedAt = recordedAt; self.reason = reason
        self.preparationID = preparationID; self.dose = dose
    }
    public func preparationLimitReached(at now: Date) -> Bool {
        kind == .preparation && now.timeIntervalSince(occurredAt) >= SupplyQuantity.xywavPreparationLimit
    }
}

public enum SupplyQuantity {
    public static let xywavBottleMg = 90_000
    public static let xywavMgPerML = 500
    public static let referenceDoseMg = 4_500
    public static let xywavPreparationLimit: TimeInterval = 86_400
}

public enum SupplyQuantityError: LocalizedError {
    case invalid, conflict, dependentCorrection
    public var errorDescription: String? {
        switch self {
        case .invalid: return "Check the bottle balance, amount and dates. Record a starting balance before preparations. No changes were saved."
        case .conflict: return "Supply changed or this action already has different details. Reload before retrying."
        case .dependentCorrection: return "Undo the latest quantity action for this bottle first. History will be retained."
        }
    }
}

extension SupplyBackup {
    public var unresolvedPreparations: [SupplyQuantityEntry] {
        let active = (quantityEntries ?? []).filter { $0.voidedAt == nil }
        let resolved = Set(active.compactMap(\.preparationID))
        return active.filter { $0.kind == .preparation && !resolved.contains($0.id) }
    }

    public func remainingBottleMg(_ bottleID: UUID) -> Int? {
        guard isValid else { return nil }
        return quantityBalances()?[bottleID]
    }

    var quantityIsValid: Bool {
        guard version == 3 else { return quantityEntries == nil }
        return quantityEntries != nil && quantityBalances() != nil
    }

    /// Replays confirmed inventory actions; no use of dose counts or elapsed nights.
    private func quantityBalances() -> [UUID: Int]? {
        let entries = quantityEntries ?? []
        guard entries.count <= Self.maximumRecordCount,
              Set(entries.map(\.id)).count == entries.count,
              Set(bottleStarts.map(\.id)).count == bottleStarts.count else { return nil }
        let bottles = Dictionary(uniqueKeysWithValues: bottleStarts.map { ($0.id, $0) })
        var balances: [UUID: Int] = [:], inventoryTime: [UUID: Date] = [:]
        var preparations: [UUID: SupplyQuantityEntry] = [:]
        var resolved = Set<UUID>(), doses = Set<String>()
        var lastRecorded = Date.distantPast
        for e in entries {
            guard let bottle = bottles[e.bottleID], e.occurredAt.timeIntervalSince1970.isFinite,
                  e.recordedAt.timeIntervalSince1970.isFinite, e.occurredAt >= bottle.openedAt,
                  e.occurredAt <= e.recordedAt, e.recordedAt >= bottle.recordedAt,
                  e.recordedAt >= lastRecorded, (0...SupplyQuantity.xywavBottleMg).contains(e.amountMg),
                  !e.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, e.reason.count <= 300,
                  e.voidedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= e.recordedAt }) ?? true else { return nil }
            lastRecorded = e.recordedAt
            switch e.kind {
            case .baseline, .preparation:
                guard e.preparationID == nil, e.dose == nil,
                      e.kind != .preparation || e.amountMg > 0 else { return nil }
            case .discard, .doseLink:
                guard e.amountMg == 0, e.preparationID != nil else { return nil }
                if e.kind == .discard { guard e.dose == nil else { return nil } }
                else {
                    guard let dose = e.dose, !dose.eventID.isEmpty, dose.eventID.count <= 200,
                          !dose.sessionID.isEmpty, dose.sessionID.count <= 200,
                          ["dose1", "dose2", "extra_dose"].contains(dose.eventType),
                          dose.occurredAt == e.occurredAt else { return nil }
                }
            }
            if e.voidedAt != nil { continue }
            guard bottle.voidedAt == nil else { return nil }
            switch e.kind {
            case .baseline, .preparation:
                guard e.occurredAt >= (inventoryTime[e.bottleID] ?? bottle.openedAt) else { return nil }
                inventoryTime[e.bottleID] = e.occurredAt
                if e.kind == .baseline { balances[e.bottleID] = e.amountMg }
                else {
                    guard let remaining = balances[e.bottleID], e.amountMg <= remaining else { return nil }
                    balances[e.bottleID] = remaining - e.amountMg
                    preparations[e.id] = e
                }
            case .discard, .doseLink:
                guard let id = e.preparationID, let preparation = preparations[id],
                      preparation.bottleID == e.bottleID, preparation.occurredAt <= e.occurredAt,
                      resolved.insert(id).inserted else { return nil }
                if let dose = e.dose { guard doses.insert(dose.eventID).inserted else { return nil } }
            }
        }
        return balances
    }

    public mutating func recordQuantity(_ entry: SupplyQuantityEntry, now: Date) throws {
        try recordQuantities([entry], now: now)
    }

    public mutating func recordQuantities(_ entries: [SupplyQuantityEntry], now: Date) throws {
        guard isValid, !entries.isEmpty, now.timeIntervalSince1970.isFinite else { throw SupplyQuantityError.invalid }
        var candidate = self
        candidate.version = 3; candidate.receipts = receipts ?? []; candidate.quantityEntries = quantityEntries ?? []
        for entry in entries {
            if let existing = candidate.quantityEntries?.first(where: { $0.id == entry.id }) {
                guard existing == entry else { throw SupplyQuantityError.conflict }
            } else {
                guard entry.recordedAt <= now, entry.voidedAt == nil else { throw SupplyQuantityError.invalid }
                candidate.quantityEntries?.append(entry)
            }
        }
        guard candidate.isValid else { throw SupplyQuantityError.invalid }
        self = candidate
    }

    public mutating func voidQuantity(id: UUID, at time: Date, now: Date) throws {
        guard isValid, time <= now, let index = quantityEntries?.firstIndex(where: { $0.id == id })
        else { throw SupplyQuantityError.invalid }
        if quantityEntries?[index].voidedAt == time { return }
        let bottle = quantityEntries![index].bottleID
        guard quantityEntries?.last(where: { $0.bottleID == bottle && $0.voidedAt == nil })?.id == id
        else { throw SupplyQuantityError.dependentCorrection }
        var candidate = self
        candidate.quantityEntries?[index].voidedAt = time
        guard candidate.isValid else { throw SupplyQuantityError.dependentCorrection }
        self = candidate
    }
}
