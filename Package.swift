// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Allow2",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "Allow2",
            targets: ["Allow2"]
        ),
        .library(
            name: "Allow2UI",
            targets: ["Allow2UI"]
        ),
    ],
    targets: [
        .target(
            name: "Allow2",
            path: "Sources/Allow2"
        ),
        .target(
            name: "Allow2UI",
            dependencies: ["Allow2"],
            path: "Sources/Allow2UI"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
