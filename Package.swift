// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GlanceSwitch",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "GlanceSwitch",
            path: "Sources/GlanceSwitch"
        )
    ],
    swiftLanguageVersions: [.v5]
)
