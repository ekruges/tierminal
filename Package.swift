// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tierminal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Tierminal", path: "Sources/Tierminal")
    ]
)
