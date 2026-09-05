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
                    "In-window recorded pairs (150 to less than 240 minutes)",
                    "Snooze count",
                    "Extra dose count",
                    "Pending and unrecorded Dose 2 outcomes"
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
                id: "whoop",
                title: "WHOOP Recovery & Biometrics",
                metrics: [
                    "Recovery score and HRV",
                    "Resting heart rate and respiratory rate",
                    "Sleep efficiency and disturbances",
                    "REM, deep, light and awake minutes"
                ]
            ),
            DashboardMetricCategory(
                id: "lifestyle",
                title: "Pre-Sleep & Lifestyle",
                metrics: [
                    "Caffeine, alcohol, exercise, screens and late meals",
                    "Bedtime and morning stress with reported stressors",
                    "Answered-log counts; unanswered questions are excluded"
                ]
            ),
            DashboardMetricCategory(
                id: "quality",
                title: "Data Quality & Reliability",
                metrics: [
                    "Duplicate event cluster count",
                    "Nights with at least 3 of 4 data categories",
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
