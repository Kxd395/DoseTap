// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoseTapiOS",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .executable(name: "DoseTapiOS", targets: ["DoseTapiOS"])
    ],
    targets: [
        .executableTarget(
            name: "DoseTapiOS",
            resources: [.process("../../Info.plist")]
        )
    ]
)
