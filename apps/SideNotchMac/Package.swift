// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SideNotchMac",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../packages/SideNotchCore"),
        .package(path: "../../packages/ProviderKit"),
        .package(path: "../../packages/NotchKit"),
        .package(path: "../../packages/UsageKit"),
    ],
    targets: [
        .executableTarget(
            name: "SideNotchMac",
            dependencies: ["SideNotchCore", "ProviderKit", "NotchKit", "UsageKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
