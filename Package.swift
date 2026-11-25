// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PixelPlayerMac",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "PixelPlayerMac", targets: ["PixelPlayerMac"]),
        .executable(name: "PixelPlayerChecks", targets: ["PixelPlayerChecks"]),
    ],
    targets: [
        // Everything that can be checked without a window: the Navidrome client, the local library,
        // matching local files to server songs, sync rules, Sonos and the phone link.
        .target(
            name: "PixelPlayerKit",
            path: "Sources/PixelPlayerKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "PixelPlayerMac",
            dependencies: ["PixelPlayerKit"],
            path: "Sources/PixelPlayerMac",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Checks of the kit. A plain program because Swift Testing and XCTest need a full Xcode.
        .executableTarget(
            name: "PixelPlayerChecks",
            dependencies: ["PixelPlayerKit"],
            path: "Sources/PixelPlayerChecks",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
