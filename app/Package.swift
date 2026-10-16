// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EarPodsAIKeys",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "EarPodsAIKeys", targets: ["EarPodsApp"]),
               .executable(name: "EarPodsUninstallHelper", targets: ["EarPodsUninstallHelper"])],
    targets: [
        .target(name: "EarPodsCore"),
        .target(name: "EarPodsMac", dependencies: ["EarPodsCore"]),
        .executableTarget(name: "EarPodsApp", dependencies: ["EarPodsCore", "EarPodsMac"]),
        .executableTarget(name: "EarPodsUninstallHelper", dependencies: ["EarPodsCore"]),
        .testTarget(name: "EarPodsCoreTests", dependencies: ["EarPodsCore"]),
        .testTarget(name: "EarPodsMacTests", dependencies: ["EarPodsMac", "EarPodsCore"])
    ],
    swiftLanguageModes: [.v5]
)
