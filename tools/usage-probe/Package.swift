// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "usage-probe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../packages/SideNotchCore"),
        .package(path: "../../packages/ProviderKit"),
    ],
    targets: [
        .executableTarget(
            name: "usage-probe",
            dependencies: ["SideNotchCore", "ProviderKit"]
        )
    ]
)
