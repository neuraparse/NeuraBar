// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NeuraBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NeuraBar",
            path: "Sources/NeuraBar"
        ),
        .testTarget(
            name: "NeuraBarTests",
            dependencies: ["NeuraBar"],
            path: "Tests/NeuraBarTests"
        )
    ]
)
