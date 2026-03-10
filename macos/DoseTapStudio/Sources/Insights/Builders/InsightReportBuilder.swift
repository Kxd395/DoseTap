import Foundation

struct InsightReportBuilder {
    func buildProviderSummary(sessions: [InsightSession], maxSessions: Int = 30) -> String {
        let selected = Array(sessions.prefix(maxSessions))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let dateRange = reportDateRange(for: selected, formatter: formatter)
        let intervalValues = selected.compactMap(\.intervalMinutes)
        let sleepQualityValues = selected.compactMap(\.morningSleepQuality)
        let readinessValues = selected.compactMap(\.morningReadiness)
        let lateCount = selected.filter(\.isLateDose2).count
        let skippedCount = selected.filter(\.dose2Skipped).count
        let highStressCount = selected.filter { ($0.preSleepStressLevel ?? 0) >= 4 }.count
        let missingMorningCount = selected.filter { $0.morning == nil }.count

        let onTimeQuality = average(of: selected.filter(\.isOnTimeDose2).compactMap(\.morningSleepQuality))
        let lateQuality = average(of: selected.filter(\.isLateDose2).compactMap(\.morningSleepQuality))
        let flaggedSessions = selected.filter { !$0.qualityFlags.isEmpty || $0.dose2Skipped || $0.isLateDose2 }

        var lines: [String] = [
            "DoseTap Insights Provider Summary",
            "Generated: \(formatter.string(from: Date()))",
            "Included nights: \(selected.count)",
            "Date range: \(dateRange)",
            "",
            "Overview",
            "Average Dose 2 interval: \(formattedAverage(intervalValues, suffix: " min"))",
            "Late Dose 2 nights: \(lateCount)",
            "Dose 2 skipped nights: \(skippedCount)",
            "Average morning sleep quality: \(formattedAverage(sleepQualityValues, suffix: " / 5"))",
            "Average morning readiness: \(formattedAverage(readinessValues, suffix: " / 5"))",
            "High-stress pre-sleep nights: \(highStressCount)",
            "Missing morning check-ins: \(missingMorningCount)",
            "",
            "Quick comparison",
            "On-time nights avg morning quality: \(formattedAverage(onTimeQuality, suffix: " / 5"))",
            "Late nights avg morning quality: \(formattedAverage(lateQuality, suffix: " / 5"))",
            ""
        ]

        if flaggedSessions.isEmpty {
            lines.append("Flagged nights")
            lines.append("None in the exported range.")
        } else {
            lines.append("Flagged nights")
            for session in flaggedSessions.prefix(10) {
                lines.append("- \(session.sessionDate): \(flagSummary(for: session))")
            }
        }

        lines.append("")
        lines.append("Notes")
        lines.append("This summary is generated from local DoseTap exports and is intended for review, not diagnosis.")
        return lines.joined(separator: "\n")
    }

    func buildSessionCSV(sessions: [InsightSession]) -> String {
        var rows: [String] = []
        rows.reserveCapacity(sessions.count)

        for session in sessions {
            let sessionDate = session.sessionDate
            let dose1UTC = iso8601(session.dose1Time)
            let dose2UTC = iso8601(session.dose2Time)
            let dose2Skipped = session.dose2Skipped ? "true" : "false"
            let intervalMinutes = session.intervalMinutes.map(String.init) ?? ""
            let eventCount = String(session.eventCount)
            let preSleepStress = session.preSleepStressLevel.map(String.init) ?? ""
            let morningSleepQuality = session.morningSleepQuality.map(String.init) ?? ""
            let morningReadiness = session.morningReadiness.map(String.init) ?? ""
            let medicationCount = String(session.medicationCount)
            let qualityFlags = session.qualityFlags.joined(separator: "; ")
            let notes = session.notes ?? ""

            let values = [
                sessionDate,
                dose1UTC,
                dose2UTC,
                dose2Skipped,
                intervalMinutes,
                eventCount,
                preSleepStress,
                morningSleepQuality,
                morningReadiness,
                medicationCount,
                qualityFlags,
                notes
            ]
            rows.append(values.map(csvField).joined(separator: ","))
        }

        return ([
            "session_date,dose1_utc,dose2_utc,dose2_skipped,interval_minutes,event_count,pre_sleep_stress,morning_sleep_quality,morning_readiness,medication_count,quality_flags,notes"
        ] + rows).joined(separator: "\n") + "\n"
    }

    private func reportDateRange(for sessions: [InsightSession], formatter: DateFormatter) -> String {
        let dates = sessions.compactMap(\.startedAt)
        guard let earliest = dates.min(), let latest = dates.max() else {
            return "Unavailable"
        }
        return "\(formatter.string(from: earliest)) to \(formatter.string(from: latest))"
    }

    private func average(of values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }

    private func formattedAverage(_ values: [Int], suffix: String) -> String {
        formattedAverage(average(of: values), suffix: suffix)
    }

    private func formattedAverage(_ value: Double?, suffix: String) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%@", value, suffix)
    }

    private func flagSummary(for session: InsightSession) -> String {
        if session.dose2Skipped {
            return "Dose 2 skipped"
        }
        if session.isLateDose2 {
            return "Late Dose 2"
        }
        return session.qualityFlags.joined(separator: ", ")
    }

    private func iso8601(_ date: Date?) -> String {
        guard let date else { return "" }
        return Self.isoFormatter.string(from: date)
    }

    private func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
