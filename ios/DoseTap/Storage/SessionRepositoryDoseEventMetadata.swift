import DoseCore
import Foundation

@MainActor
extension SessionRepository {
    func morningDoseEventMetadata(
        eventType: CanonicalDoseEventType,
        sessionDate: String,
        amountMg: Int? = nil,
        reason: String? = nil,
        reasonNotes: String? = nil,
        isEstimate: Bool = false,
        estimatedTiming: MedicationTiming? = nil
    ) -> String? {
        let existingMetadata = fetchDoseEvents(forSessionDate: sessionDate)
            .first { CanonicalDoseEventType(canonicalizing: $0.eventType) == eventType }?.metadata
        return doseEventMetadata(
            existingMetadata: existingMetadata, amountMg: amountMg, source: "morning_reconciliation",
            reason: reason, reasonNotes: reasonNotes, estimatedAt: isEstimate ? clock() : nil,
            estimatedTiming: estimatedTiming
        )
    }

    func doseEventMetadata(
        existingMetadata: String? = nil,
        amountMg: Int?,
        source: String?,
        reason: String? = nil,
        reasonNotes: String? = nil,
        estimatedAt: Date? = nil,
        estimatedTiming: MedicationTiming? = nil
    ) -> String? {
        var metadata = jsonDictionary(from: existingMetadata)
        if let source {
            metadata["source"] = source
        }
        if let amountMg {
            metadata["amount_mg"] = amountMg
        }
        if let estimatedAt {
            metadata["time_precision"] = "approximate"
            metadata["entry_mode"] = "retrospective"
            metadata["surface"] = "morning_check_in"
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            metadata["recorded_at_utc"] = formatter.string(from: estimatedAt)
            if let estimatedTiming {
                metadata["is_early"] = estimatedTiming == .early
                metadata["is_late"] = estimatedTiming == .late
            }
        }
        upsertMetadataString(reason, forKey: "reason", in: &metadata)
        upsertMetadataString(reasonNotes, forKey: "reason_notes", in: &metadata)
        guard !metadata.isEmpty else {
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: metadata) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func jsonDictionary(from jsonString: String?) -> [String: Any] {
        guard
            let jsonString,
            let data = jsonString.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    private func upsertMetadataString(_ value: String?, forKey key: String, in metadata: inout [String: Any]) {
        guard let value else {
            metadata.removeValue(forKey: key)
            return
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            metadata.removeValue(forKey: key)
        } else {
            metadata[key] = trimmed
        }
    }
}

extension StoredDoseEvent {
    var hasApproximateOccurrence: Bool {
        guard let metadata,
              let value = (try? JSONSerialization.jsonObject(with: Data(metadata.utf8))) as? [String: Any] else { return false }
        return value["time_precision"] as? String == "approximate"
    }
}
