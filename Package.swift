// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacTape",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MacTapeCore", targets: ["MacTapeCore"]),
        .executable(name: "MacTape", targets: ["MacTapeApp"]),
        .executable(name: "mactape", targets: ["mactape"]),
    ],
    targets: [
        .target(
            name: "MacTapeCore",
            path: "Sources/MacTapeCore"
        ),
        .executableTarget(
            name: "MacTapeApp",
            dependencies: ["MacTapeCore"],
            path: "Sources/MacTapeApp"
        ),
        .executableTarget(
            name: "mactape",
            dependencies: ["MacTapeCore"],
            path: "Sources/mactape"
        ),
        .testTarget(
            name: "MacTapeCoreTests",
            dependencies: ["MacTapeCore"],
            path: "Tests/MacTapeCoreTests"
        ),
    ]
)
