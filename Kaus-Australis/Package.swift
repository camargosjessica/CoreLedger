// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KausAustralis",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.0.0"),
        .package(path: "../Kaus-Media")
    ],
    targets: [
        .executableTarget(
            name: "KausAustralis",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "KausMedia", package: "Kaus-Media")
            ]
        )
    ]
)
