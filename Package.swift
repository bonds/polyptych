// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "polyptych",
    platforms: [.macOS(.v15)],
    targets: [
        .systemLibrary(
            name: "Clibmpv",
            path: "Dependencies/Clibmpv"
        ),
        .executableTarget(
            name: "polyptych",
            dependencies: ["Clibmpv"],
            linkerSettings: [
                .unsafeFlags(["-L", "/nix/store/03zfgn8fi73mrnr848y69vhb6nn04zwp-mpv-0.41.0/lib"])
            ]
        )
    ]
)
