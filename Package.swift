// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FundPulse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FundPulse", targets: ["FundPulse"])
    ],
    targets: [
        .executableTarget(
            name: "FundPulse",
            path: "Sources/FundPulse"
        ),
        .testTarget(
            name: "FundPulseTests",
            dependencies: ["FundPulse"],
            path: "Tests/FundPulseTests"
        )
    ]
)
