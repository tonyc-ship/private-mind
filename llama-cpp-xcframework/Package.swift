// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "llama-cpp-xcframework",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .visionOS(.v1),
        .tvOS(.v13)
    ],
    products: [
        .library(
            name: "LlamaFramework",
            targets: ["LlamaFramework"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "LlamaFramework",
            path: "LlamaFramework.xcframework"
        )
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx17
)

