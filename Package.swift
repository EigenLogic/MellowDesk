// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MellowDesk",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MellowDeskCore", targets: ["MellowDeskCore"]),
        .executable(name: "MellowDesk", targets: ["MellowDesk"])
    ],
    targets: [
        .target(
            name: "MellowDeskCore",
            path: "Sources/MellowDeskCore"
        ),
        .executableTarget(
            name: "MellowDesk",
            dependencies: ["MellowDeskCore"],
            path: "Sources/MellowDesk"
        ),
        .testTarget(
            name: "MellowDeskCoreTests",
            dependencies: ["MellowDeskCore"],
            path: "Tests/MellowDeskCoreTests"
        ),
        .testTarget(
            name: "MellowDeskTests",
            dependencies: ["MellowDesk"],
            path: "Tests/MellowDeskTests"
        )
    ]
)
