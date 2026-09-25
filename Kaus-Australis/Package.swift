// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KausAustralis",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 O Framework Web (Vapor)
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        // 🔗 O nosso pacote compartilhado de contratos
        .package(path: "../Kaus-Media")
    ],
    targets: [
        .executableTarget(
            name: "KausAustralis",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "KausMedia", package: "Kaus-Media")
            ]
        )
    ]
)
