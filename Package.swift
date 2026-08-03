// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DisplayListDescription",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "DisplayListDescription",
            targets: ["DisplayListDescription"]
        ),
        .executable(
            name: "DisplayListWeb",
            targets: ["DisplayListWeb"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftwasm/JavaScriptKit.git",
            exact: "0.57.0"
        ),
    ],
    targets: [
        .target(
            name: "DisplayListDescription"
        ),
        .executableTarget(
            name: "DisplayListWeb",
            dependencies: [
                "DisplayListDescription",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ]
        ),
        .testTarget(
            name: "DisplayListDescriptionTests",
            dependencies: ["DisplayListDescription"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
