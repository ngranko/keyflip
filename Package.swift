// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Keyflip",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LayoutConversion", targets: ["LayoutConversion"]),
        .executable(name: "Keyflip", targets: ["Keyflip"]),
    ],
    targets: [
        .target(
            name: "LayoutConversion",
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "Keyflip",
            dependencies: ["LayoutConversion"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "LayoutConversionTests",
            dependencies: ["LayoutConversion"]
        ),
    ]
)
