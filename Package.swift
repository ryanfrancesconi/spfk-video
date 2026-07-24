// swift-tools-version: 6.2
// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi

import PackageDescription

let package = Package(
    name: "spfk-video",
    defaultLocalization: "en",
    platforms: [.macOS(.v13), .iOS(.v16),],
    products: [
        .library(
            name: "SPFKVideo",
            targets: ["SPFKVideo"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ryanfrancesconi/spfk-base", from: "1.2.2"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-testing", from: "1.1.0"),
        .package(url: "https://github.com/orchetect/swift-timecode", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "SPFKVideo",
            dependencies: [
                .product(name: "SPFKBase", package: "spfk-base"),
                .product(name: "SwiftTimecode", package: "swift-timecode"),
            ]
        ),
        .testTarget(
            name: "SPFKVideoTests",
            dependencies: [
                .targetItem(name: "SPFKVideo", condition: nil),
                .product(name: "SPFKTesting", package: "spfk-testing"),
            ]
        ),
    ]
)
