// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RangeAnxiety",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RangeAnxiety", targets: ["RangeAnxiety"])
    ],
    targets: [
        .executableTarget(
            name: "RangeAnxiety",
            path: "Sources/RangeAnxiety",
            linkerSettings: [
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "RangeAnxietyTests",
            dependencies: ["RangeAnxiety"],
            path: "Tests/RangeAnxietyTests"
        )
    ]
)
