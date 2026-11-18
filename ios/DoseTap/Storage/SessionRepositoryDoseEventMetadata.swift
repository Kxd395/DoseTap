import DoseCore
import Foundation

@MainActor
extension SessionRepository {
    func doseEventMetadata(
        existingMetadata: String? = nil,
        amountMg: Int?,
        source: String?,
        reason: String? = nil,
        reasonNotes: String? = nil,
        estimatedAt: Date? = nil
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
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            metadata["recorded_at_utc"] = formatter.string(from: estimatedAt)
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
