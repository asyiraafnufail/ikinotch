// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IkiNotch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "IkiNotchCore",
            targets: ["IkiNotchCore"]
        ),
        .executable(
            name: "IkiNotch",
            targets: ["IkiNotch"]
        )
    ],
    targets: [
        .target(
            name: "IkiNotchCore",
            dependencies: []
        ),
        .executableTarget(
            name: "IkiNotch",
            dependencies: ["IkiNotchCore"]
        ),
        .testTarget(
            name: "IkiNotchCoreTests",
            dependencies: ["IkiNotchCore"]
        )
    ]
)
