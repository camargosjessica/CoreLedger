// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KausMedia",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "KausMedia",
            targets: ["KausMedia"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "KausMedia",
            dependencies: ["ZIPFoundation"]
        ),
        .testTarget(
            name: "KausMediaTests",
            dependencies: ["KausMedia"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
