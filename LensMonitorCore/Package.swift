// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LensMonitorCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LensMonitorCore", targets: ["LensMonitorCore"]),
    ],
    targets: [
        .target(name: "LensMonitorCore"),
        .testTarget(name: "LensMonitorCoreTests", dependencies: ["LensMonitorCore"]),
    ]
)
