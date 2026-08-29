// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SideNotchMac",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../packages/SideNotchCore"),
        .package(path: "../../packages/ProviderKit"),
    ],
    targets: [
        .executableTarget(
            name: "SideNotchMac",
            dependencies: ["SideNotchCore", "ProviderKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
