// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kite",
    products: [
        .library(name: "KiteCore", targets: ["KiteCore"]),
        .executable(name: "kite", targets: ["kite"]),
    ],
    targets: [
        .target(name: "KiteCore"),
        .executableTarget(
            name: "kite",
            dependencies: ["KiteCore"]),
        .testTarget(
            name: "KiteCoreTests",
            dependencies: ["KiteCore"]),
    ],
    swiftLanguageModes: [.v5]
)
