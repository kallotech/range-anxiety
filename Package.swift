// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RangeAnxiety",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RangeAnxiety", targets: ["RangeAnxiety"]),
        .executable(name: "ra", targets: ["RangeAnxietyCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "RangeAnxiety",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/RangeAnxiety",
            linkerSettings: [
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .executableTarget(
            name: "RangeAnxietyCLI",
            path: "Sources/RangeAnxietyCLI"
        ),
        .testTarget(
            name: "RangeAnxietyTests",
            dependencies: ["RangeAnxiety"],
            path: "Tests/RangeAnxietyTests"
        )
    ]
)
