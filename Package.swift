// swift-tools-version: 5.10
import PackageDescription
import Foundation

// libmpv is supplied by the nix flake via
//   swift build ... -Xlinker -L<libmpv>/lib
// For a standalone `swift build`, point LIBMPV_DIR at a libmpv lib directory:
//   LIBMPV_DIR=$(nix build --print-out-paths 'nixpkgs#mpv')/lib swift build -c release
//
// Do NOT hardcode a /nix/store path here. It goes stale when nixpkgs updates
// and then wins the link order, binding the app to a libmpv the nix closure
// does not track — nix GCs it and launch dies with dyld "Library not loaded".
let linkerSettings: [LinkerSetting] =
    ProcessInfo.processInfo.environment["LIBMPV_DIR"].map {
        [.unsafeFlags(["-L", $0])]
    } ?? []

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
            dependencies: ["Clibmpv"],
            linkerSettings: linkerSettings
        )
    ]
)
