// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UsageKit", targets: ["UsageKit"])
    ],
    dependencies: [
        .package(path: "../SideNotchCore"),
        .package(path: "../ProviderKit"),
    ],
    targets: [
        .target(name: "UsageKit", dependencies: ["SideNotchCore", "ProviderKit"]),
        .testTarget(name: "UsageKitTests", dependencies: ["UsageKit", "SideNotchCore", "ProviderKit"]),
    ]
)
