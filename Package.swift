// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PokeToy",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PokeToyCore"),
        .executableTarget(name: "PokeToy", dependencies: ["PokeToyCore"]),
        .testTarget(name: "PokeToyCoreTests", dependencies: ["PokeToyCore"]),
    ],
    swiftLanguageModes: [.v5]
)
