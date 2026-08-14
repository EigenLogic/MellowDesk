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
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle.git",
            exact: "2.9.5"
        )
    ],
    targets: [
        .target(
            name: "MellowDeskCore",
            path: "Sources/MellowDeskCore"
        ),
        .executableTarget(
            name: "MellowDesk",
            dependencies: [
                "MellowDeskCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
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
