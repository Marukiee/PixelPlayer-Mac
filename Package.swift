// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PixelPlayerMac",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "PixelPlayerMac", targets: ["PixelPlayerMac"]),
    ],
    targets: [
        // A design prototype: sample data only, no playback, scanning or networking yet.
        .executableTarget(
            name: "PixelPlayerMac",
            path: "Sources/PixelPlayerMac",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
