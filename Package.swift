// swift-tools-version: 6.2
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
            name: "ParadoxDataKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .executableTarget(
            name: "ParadoxDataBrowser",
            dependencies: ["ParadoxDataKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ParadoxDataKitTests",
            dependencies: ["ParadoxDataKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ]
)
