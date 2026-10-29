// swift-tools-version: 6.0
import PackageDescription

// Everything in SkillsHub that isn't SwiftUI: the index models, catalog queries, and the
// services that read what's installed. Foundation-only, so `swift test` also runs on Linux.
let package = Package(
    name: "SkillsHubCore",
    platforms: [.macOS("15.6")],
    products: [
        .library(name: "SkillsHubCore", targets: ["SkillsHubCore"]),
    ],
    targets: [
        .target(name: "SkillsHubCore"),
        .testTarget(
            name: "SkillsHubCoreTests",
            dependencies: ["SkillsHubCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
