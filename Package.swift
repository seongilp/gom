// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Gom",
    platforms: [.macOS(.v13)],
    targets: [
        .systemLibrary(
            name: "Clibmpv",
            path: "Sources/Clibmpv",
            pkgConfig: "mpv",
            providers: [.brew(["mpv"])]
        ),
        .executableTarget(
            name: "Gom",
            dependencies: ["Clibmpv"],
            path: "Sources/Gom"
        )
    ]
)
