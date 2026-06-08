// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacBull",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacBull", targets: ["MacBull"])
    ],
    targets: [
        .executableTarget(
            name: "MacBull",
            path: "Sources/MacBull"
        )
    ],
    swiftLanguageModes: [.v5]
)
