// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-image-diff",
    platforms: [
        .macOS(.v14), .iOS(.v16), .tvOS(.v16), .visionOS(.v1),
    ],
    products: [
        .library(name: "ImageDiff", targets: ["ImageDiff"]),
    ],
    targets: [
        .target(name: "ImageDiff"),
        .testTarget(name: "ImageDiffTests", dependencies: ["ImageDiff"]),
    ]
)
