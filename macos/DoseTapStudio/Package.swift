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
    dependencies: [.package(name: "DoseTap", path: "../..")],
    targets: [
        .executableTarget(
            name: "DoseTapStudio",
            dependencies: [.product(name: "DoseCore", package: "DoseTap")],
            path: "Sources"
        ),
        .testTarget(
            name: "DoseTapStudioTests",
            dependencies: ["DoseTapStudio"],
            path: "Tests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
