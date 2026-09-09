// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DoubaoCaret",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DoubaoCaret", targets: ["DoubaoCaret"])],
    targets: [.executableTarget(name: "DoubaoCaret")]
)
