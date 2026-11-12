// swift-tools-version:5.9
// KiteKit: the platform-independent half of KiteLink. Profiles, subscriptions, the runtime config builder and the
// mihomo API client live here so every native app (macOS today, iOS and others later) shares one implementation.
import PackageDescription

let package = Package(
    name: "KiteKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "KiteKit", targets: ["KiteKit"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0")],
    targets: [
        .target(name: "KiteKit", dependencies: ["Yams"]),
        .testTarget(name: "KiteKitTests", dependencies: ["KiteKit"]),
    ]
)
