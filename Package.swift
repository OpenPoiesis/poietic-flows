// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "poietic-flows",
    platforms: [.macOS("15"), .custom("linux", versionString: "1")],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PoieticFlows",
            targets: ["PoieticFlows"]),
    ],
    dependencies: [
        .package(url: "https://github.com/openpoiesis/poietic-core", branch: "main"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.1.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "PoieticFlows",
            dependencies: [
                .product(name: "PoieticCore", package: "poietic-core")
            ]
        ),

        .testTarget(
            name: "PoieticFlowsTests",
            dependencies: ["PoieticFlows"]),
    ]
)
