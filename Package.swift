// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "TypeByHand",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "TypeByHand", path: "Sources/TypeByHand")]
)
