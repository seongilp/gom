// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Gom",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Gom",
            path: "Sources/Gom"
        )
    ]
)
