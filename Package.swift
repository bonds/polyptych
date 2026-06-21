// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "polyptych",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "Clibmpv",
            path: "Dependencies/Clibmpv"
        ),
        .executableTarget(
            name: "polyptych",
            dependencies: ["Clibmpv"]
        )
    ]
)
