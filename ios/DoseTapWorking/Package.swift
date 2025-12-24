// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoseTapWorking",
    platforms: [.iOS(.v16)],
    products: [
        .executable(name: "DoseTapWorking", targets: ["DoseTapWorking"])
    ],
    targets: [
        .executableTarget(
            name: "DoseTapWorking",
            path: ".",
            exclude: ["Sources/"],
            sources: ["DoseTapWorkingApp.swift"]
        ),
    ]
)
