// swift-tools-version: 6.2
import PackageDescription

// GameCore is the authoritative game simulation. It must stay pure Swift
// (no RealityKit/SwiftUI/UIKit) so it can later run on a Linux server.
let package = Package(
    name: "GameCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
    ],
    targets: [
        .target(name: "GameCore"),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
    ]
)
