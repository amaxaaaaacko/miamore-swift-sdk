// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "miamore-swift-sdk",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "miamore-swift-sdk",
            targets: ["miamore-swift-sdk"]
        ),
    ],
    targets: [
        .target(
            name: "miamore-swift-sdk"
        ),
        .testTarget(
            name: "miamore-swift-sdkTests",
            dependencies: ["miamore-swift-sdk"]
        ),
    ]
)
