// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pixelwright",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PixelwrightCore", targets: ["PixelwrightCore"]),
        .executable(name: "Pixelwright", targets: ["Pixelwright"]),
    ],
    targets: [
        // Pure-Swift image engine: resampling, canvas size, size math. No UI imports.
        .target(name: "PixelwrightCore"),
        .executableTarget(
            name: "Pixelwright",
            dependencies: ["PixelwrightCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PixelwrightCoreTests",
            dependencies: ["PixelwrightCore"]
        ),
        // File reading and writing, and the batch pipeline, tested against real files.
        .testTarget(
            name: "PixelwrightAppTests",
            dependencies: ["Pixelwright", "PixelwrightCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
