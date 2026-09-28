import Foundation

extension StudioWorkbookData {
    static func decodeSupplyState(_ root: SWObject) throws -> SupplyBackup? {
        guard root["supplyStateJSON"] != nil || root["supplyStateEncoding"] != nil else { return nil }
        guard root["supplyStateEncoding"] as? String == "json-date-seconds-since-2001-v1",
              let text = root["supplyStateJSON"] as? String,
              let value = try? JSONDecoder().decode(SupplyBackup.self, from: Data(text.utf8)), value.isValid
        else { throw StudioWorkbookProjectionError.malformedSupply }
        return value
    }

    func bottleSupplySheets() -> [WorkbookSheet] {
        guard let supply = supplyState else { return [] }
        let columns = ["Record type", "Status", "Occurred (UTC)", "Occurred (local)", "Recorded (UTC)",
            "Bottles added", "Record ID", "Linked receipt ID", "Voided (UTC)", "Reminder mode",
            "Entered planning date/time", "Entered timezone", "Lead days", "Enabled", "Handled (UTC)", "Source"]
        func date(_ value: Date?) -> WorkbookCell {
            guard let value else { return .blank }
            return SW.validDate(value).map(WorkbookCell.date) ?? .text("Outside Excel date range; see Source Fields")
        }
        func row(_ type: String, _ status: String, _ occurrence: Date?, _ recorded: Date, _ id: UUID) -> [WorkbookCell] {
            var result = [WorkbookCell](repeating: .blank, count: columns.count)
            result[0] = .text(type); result[1] = .text(status); result[2] = date(occurrence)
            result[3] = occurrence.flatMap(SW.validDate).map { timestamps.localCell($0) } ?? date(occurrence)
            result[4] = date(recorded); result[6] = .text(id.uuidString)
            return result
        }
        var rows: [(Date, [WorkbookCell])] = []
        for receipt in supply.receipts ?? [] {
            var cells = row("Unopened stock added", receipt.voidedAt == nil ? "Recorded" : "Voided", receipt.receivedAt, receipt.recordedAt, receipt.id)
            cells[5] = .number(Double(receipt.count)); cells[8] = date(receipt.voidedAt)
            rows.append((receipt.recordedAt, cells))
        }
        for opening in supply.bottleStarts {
            var cells = row("Bottle opened", opening.voidedAt == nil ? "Recorded" : "Voided", opening.openedAt, opening.recordedAt, opening.id)
            cells[7] = SW.text(opening.receiptID?.uuidString); cells[8] = date(opening.voidedAt)
            cells[15] = .text(opening.receiptID == nil ? "Opening without receipt link" : "Linked bottle opening")
            rows.append((opening.recordedAt, cells))
        }
        if let reminder = supply.reminder {
            for entry in reminder.history + [reminder.current] {
                var cells = row("Order reminder", entry.revision == reminder.current.revision ? "Current" : "Previous revision", nil, entry.changedAt, entry.revision)
                cells[9] = .text(entry.mode.rawValue)
                cells[10] = .text(String(format: "%04d-%02d-%02d %02d:%02d", entry.year, entry.month, entry.day, entry.hour, entry.minute))
                cells[11] = SW.text(entry.enteredTimeZoneIdentifier); cells[12] = .number(Double(entry.leadDays))
                cells[13] = .text(entry.enabled ? "true" : "false"); cells[14] = date(entry.handledAt); cells[15] = SW.text(entry.source)
                rows.append((entry.changedAt, cells))
            }
        }
        let sorted = rows.sorted { a, b in
            a.0 == b.0 ? String(describing: a.1[6]) < String(describing: b.1[6]) : a.0 > b.0
        }.map(\.1)
        return [SW.table("Bottle & Supply", columns, sorted, note: "One reported unopened-stock entry, opening or order-reminder revision from supply_state. Counts may represent only the unopened portion of a delivery, not the total shipment. Voided records remain visible and are not active stock. Opening a bottle does not mean a dose was taken or the previous bottle was empty. Reminder dates are planning inputs, not delivery claims. Inventory contains separate manual snapshots; quantities remaining and bottle-specific dose consumption are not inferred here. Full precision and all source fields remain under /supplyStateJSON in Source Fields and the Studio ZIP. \(timezoneNote)")]
    }
}
