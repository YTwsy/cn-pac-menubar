// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "cn-pac-menubar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CNPacMenubarCore", targets: ["CNPacMenubarCore"]),
        .executable(name: "CNPacMenubar", targets: ["CNPacMenubar"])
    ],
    targets: [
        .target(
            name: "CNPacMenubarCore",
            path: "Sources/CNPacMenubarCore"
        ),
        .executableTarget(
            name: "CNPacMenubar",
            dependencies: ["CNPacMenubarCore"],
            path: "Sources/CNPacMenubar"
        ),
        .testTarget(
            name: "CNPacMenubarCoreTests",
            dependencies: ["CNPacMenubarCore"],
            path: "Tests/CNPacMenubarCoreTests"
        )
    ]
)
