// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BleTransport",
    platforms: [
        .iOS(.v13),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "BleTransport",
            targets: ["BleTransport"]),
    ],
    targets: [
        .target(
            name: "BleTransport"),
        .testTarget(
            name: "BleTransportTests",
            dependencies: ["BleTransport"]),
    ]
)
