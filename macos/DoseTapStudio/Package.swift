// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoseTapStudio",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DoseTapStudio",
            targets: ["DoseTapStudio"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DoseTapStudio",
            path: "Sources"
        ),
        .testTarget(
            name: "DoseTapStudioTests",
            dependencies: ["DoseTapStudio"],
            path: "Tests"
        )
    ]
)
