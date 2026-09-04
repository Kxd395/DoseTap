// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoseTap",
    platforms: [
        .iOS(.v16),
        .macOS(.v10_15),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "DoseCore", targets: ["DoseCore"])
    ],
    targets: [
        .target(
            name: "DoseCore",
            path: "ios/Core",
            sources: [
                "DoseWindowState.swift",
                "APIErrors.swift",
                "OfflineQueue.swift",
                "EventRateLimiter.swift",
                "APIClient.swift",
                "RecommendationEngine.swift",
                "DoseTapCore.swift",
                "SleepEvent.swift",
                "UnifiedSleepSession.swift",
                "DoseUndoManager.swift",
                "MorningCheckIn.swift",
                "CSVExporter.swift",
                "DataRedactor.swift",
                "MedicationConfig.swift",
                "SessionKey.swift",
                "SleepPlan.swift",
                "EventStore.swift",
                "TimeIntervalMath.swift",
                "DiagnosticEvent.swift",
                "DiagnosticLogger.swift",
                "DosingModels.swift",
                "MedicationInventoryModels.swift",
                "MedicationInventoryForecast.swift",
                "CertificatePinning.swift",
                "NightScoreCalculator.swift",
                "DoseRegistrationPolicy.swift",
                "DoseEffectivenessCalculator.swift"
            ]
        ),
        .testTarget(
            name: "DoseCoreTests",
            dependencies: ["DoseCore"],
            path: "Tests/DoseCoreTests",
            sources: [
                "DoseWindowStateTests.swift",
                "APIErrorsTests.swift",
                "APIClientTests.swift",
                "OfflineQueueTests.swift",
                "EventRateLimiterTests.swift",
                "DoseWindowEdgeTests.swift",
                "CRUDActionTests.swift",
                "SleepEventTests.swift",
                "DoseUndoManagerTests.swift",
                "SSOTComplianceTests.swift",
                "Dose2EdgeCaseTests.swift",
                "SleepEnvironmentTests.swift",
                "CSVExporterTests.swift",
                "DataRedactorTests.swift",
                "MedicationLoggerTests.swift",
                "TimeCorrectnessTests.swift",
                "SleepPlanCalculatorTests.swift",
                "WorkWakeScheduleTests.swift",
                "SessionIdBackfillTests.swift",
                "DosingAmountTests.swift",
                "UnifiedSleepSessionTests.swift",
                "DiagnosticEventTests.swift",
                "MorningCheckInTests.swift",
                "DosingModelsTests.swift",
                "MedicationInventoryForecastTests.swift",
                "CertificatePinningTests.swift",
                "DiagnosticLoggerTests.swift",
                "RecommendationEngineTests.swift",
                "EventStoreModelsTests.swift",
                "SessionRolloverRegressionTests.swift",
                "NightScoreCalculatorTests.swift",
                "DoseRegistrationPolicyTests.swift",
                "DoseEffectivenessCalculatorTests.swift",
                "TimeIntervalMathCharacterizationTests.swift",
                "DeletedEventSnapshotTests.swift"
            ],
            resources: [
                .copy("Fixtures/CertificatePinning")
            ]
        )
    ]
)
