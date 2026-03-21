// swift-tools-version: 6.2
// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import PackageDescription

let package = Package(
    name: "spfk-filesystem",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(
            name: "SPFKFileSystem",
            targets: ["SPFKFileSystem"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ryanfrancesconi/spfk-base", from: "0.0.3"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-raw-codable", from: "0.0.1"),
        .package(url: "https://github.com/ryanfrancesconi/spfk-testing", from: "0.0.9"),
        .package(url: "https://github.com/orchetect/swift-extensions", from: "2.0.0"),
        .package(url: "https://github.com/jozefizso/swift-xattr", from: "3.0.1"),
    ],
    targets: [
        .target(
            name: "SPFKFileSystem",
            dependencies: [
                .product(name: "SPFKBase", package: "spfk-base"),
                .product(name: "RawCodable", package: "spfk-raw-codable"),
                .product(name: "SwiftExtensions", package: "swift-extensions"),
                .product(name: "XAttr", package: "swift-xattr"),
            ]
        ),
        .testTarget(
            name: "SPFKFileSystemTests",
            dependencies: [
                .targetItem(name: "SPFKFileSystem", condition: nil),
                .product(name: "SPFKTesting", package: "spfk-testing"),
            ]
        ),
    ]
)
