// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProviderKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ProviderKit", targets: ["ProviderKit"])
    ],
    dependencies: [
        .package(path: "../SideNotchCore")
    ],
    targets: [
        .target(name: "ProviderKit", dependencies: ["SideNotchCore"]),
        .testTarget(
            name: "ProviderKitTests",
            dependencies: ["ProviderKit", "SideNotchCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
