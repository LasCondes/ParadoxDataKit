// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ParadoxDataKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "ParadoxDataKit",
            targets: ["ParadoxDataKit"]
        ),
        .executable(
            name: "ParadoxDataBrowser",
            targets: ["ParadoxDataBrowser"]
        )
    ],
    targets: [
        .target(
            name: "ParadoxDataKit"
        ),
        .executableTarget(
            name: "ParadoxDataBrowser",
            dependencies: ["ParadoxDataKit"],
            resources: [
            ]
        ),
        .testTarget(
            name: "ParadoxDataKitTests",
            dependencies: ["ParadoxDataKit"]
        )
    ]
)
