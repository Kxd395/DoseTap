import Foundation

extension DashboardAnalyticsModel {
    var metricsCatalog: [DashboardMetricCategory] {
        [
            DashboardMetricCategory(
                id: "dosing",
                title: "Dosing & Timing",
                metrics: [
                    "Dose 1 timestamp",
                    "Dose 2 timestamp",
                    "Dose 2 skipped status",
                    "Inter-dose interval (minutes)",
                    "On-time dosing (150-240m window)",
                    "Snooze count",
                    "Extra dose count",
                    "Consecutive on-time streak"
                ]
            ),
            DashboardMetricCategory(
                id: "sleep",
                title: "Sleep (Apple Health + Manual)",
                metrics: [
                    "Total sleep minutes",
                    "Time to first wake (TTFW)",
                    "Wake count (Apple Health)",
                    "Sleep source",
                    "Bathroom wake count",
                    "Lights Out and Wake Up events",
                    "Nap count and duration",
                    "Sleep quality (morning check-in)",
                    "Readiness for day"
                ]
            ),
            DashboardMetricCategory(
                id: "checkins",
                title: "Check-Ins & Symptoms",
                metrics: [
                    "Morning check-in completion",
                    "Sleep quality and restedness",
                    "Grogginess and sleep inertia",
                    "Dream recall",
                    "Physical and respiratory symptom flags",
                    "Mood, anxiety, stress, readiness",
                    "Stressors and stress progression",
                    "Sleep therapy and environment flags"
                ]
            ),
            DashboardMetricCategory(
                id: "quality",
                title: "Data Quality & Reliability",
                metrics: [
                    "Duplicate event cluster count",
                    "Completeness score (0.0-1.0)",
                    "Missing Dose 2 outcome",
                    "Missing HealthKit summary",
                    "Missing morning check-in",
                    "Morning check-in completion rate",
                    "Pre-sleep log completion rate",
                    "Integration authorization state"
                ]
            )
        ]
    }
}
