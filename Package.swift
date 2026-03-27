// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlexBank",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "FlexBankCore",
            targets: ["FlexBankCore"]
        ),
        .executable(
            name: "FlexBank",
            targets: ["FlexBank"]
        ),
        .executable(
            name: "FlexBankSeedDemo",
            targets: ["FlexBankSeedDemo"]
        ),
    ],
    targets: [
        .target(
            name: "FlexBankCore"
        ),
        .executableTarget(
            name: "FlexBank",
            dependencies: ["FlexBankCore"]
        ),
        .executableTarget(
            name: "FlexBankSeedDemo",
            dependencies: ["FlexBankCore"]
        ),
        .testTarget(
            name: "FlexBankCoreTests",
            dependencies: ["FlexBankCore"]
        ),
    ]
)
