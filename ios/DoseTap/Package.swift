// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DoseTap",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "DoseTap",
            targets: ["DoseTap"]
        ),
    ],
    targets: [
        .target(
            name: "DoseTap",
            path: "."
        ),
    ]
)
