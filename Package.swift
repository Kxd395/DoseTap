// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoseTap",
    platforms: [
        .iOS(.v16),
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
                "APIClientQueueIntegration.swift",
                "TimeEngine.swift",
                "RecommendationEngine.swift",
                "DoseTapCore.swift",
                "SleepEvent.swift",
                "UnifiedSleepSession.swift",
                "DoseUndoManager.swift",
                "MorningCheckIn.swift"
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
                "Dose2EdgeCaseTests.swift"
            ]
        )
    ]
)
