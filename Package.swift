// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "progress",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ProgressCore",
            path: "Sources/ProgressCore"
        ),
        .executableTarget(
            name: "ProgressMenuBar",
            dependencies: ["ProgressCore"],
            path: "Sources/ProgressMenuBar"
        ),
        .executableTarget(
            name: "progress",
            dependencies: [
                "ProgressCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/progress"
        ),
        // Tests require Xcode (XCTest). Uncomment when Xcode is installed.
        // .testTarget(
        //     name: "ProgressCoreTests",
        //     dependencies: ["ProgressCore"],
        //     path: "Tests/ProgressCoreTests"
        // ),
    ]
)
