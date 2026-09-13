// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "TokenBarCore",
            path: "Sources/TokenBarCore"
        ),
        .executableTarget(
            name: "TokenBar",
            dependencies: ["TokenBarCore"],
            path: "Sources/TokenBar"
        ),
        .testTarget(
            name: "TokenBarCoreTests",
            dependencies: ["TokenBarCore"],
            path: "Tests/TokenBarCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
