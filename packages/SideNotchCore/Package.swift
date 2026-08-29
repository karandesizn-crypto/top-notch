// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SideNotchCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "SideNotchCore", targets: ["SideNotchCore"])
    ],
    targets: [
        .target(name: "SideNotchCore"),
        .testTarget(name: "SideNotchCoreTests", dependencies: ["SideNotchCore"]),
    ]
)
