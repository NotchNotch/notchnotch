// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchNotch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchNotch", targets: ["NotchNotch"]),
        .executable(name: "ExtensionRunner", targets: ["ExtensionRunner"]),
        .library(name: "NowPlayingAdapter", type: .dynamic, targets: ["NowPlayingAdapter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .target(name: "NotchProtocol", path: "native/NotchProtocol/Sources"),
        .target(name: "NotchCore", dependencies: ["NotchProtocol"], path: "native/NotchCore/Sources"),
        .target(name: "NotchRuntime", dependencies: ["NotchProtocol"], path: "native/NotchRuntime/Sources"),
        .target(name: "NotchConnections", dependencies: ["NotchProtocol"], path: "native/NotchConnections/Sources"),
        .target(name: "NotchExtensions", dependencies: ["NotchProtocol"], path: "native/NotchExtensions/Sources"),
        .target(name: "NotchRenderer", dependencies: ["NotchProtocol", "NotchCore"], path: "native/NotchRenderer/Sources"),
        .executableTarget(name: "ExtensionRunner", dependencies: ["NotchRuntime"], path: "native/ExtensionRunner/Sources"),
        // Loaded into /usr/bin/perl to read Now Playing (see NowPlayingAdapter.m); not linked into the app.
        .target(name: "NowPlayingAdapter", path: "native/NowPlayingAdapter/Sources",
                linkerSettings: [.linkedFramework("Foundation")]),
        .target(name: "NotchCapabilities", dependencies: ["NotchProtocol", "NotchCore", "NotchConnections"], path: "native/NotchCapabilities/Sources"),
        .testTarget(name: "NotchCapabilitiesTests", dependencies: ["NotchCapabilities"], path: "native/NotchCapabilities/Tests"),
        .executableTarget(name: "NotchNotch", dependencies: ["NotchCore", "NotchRenderer", "NotchConnections", "NotchExtensions", "NotchCapabilities",
                                                           .product(name: "Sparkle", package: "Sparkle")], path: "apps/macos/Sources"),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"], path: "native/NotchCore/Tests"),
        .testTarget(name: "NotchRuntimeTests", dependencies: ["NotchRuntime"], path: "native/NotchRuntime/Tests"),
        .testTarget(name: "NotchConnectionsTests", dependencies: ["NotchConnections"], path: "native/NotchConnections/Tests"),
        .testTarget(name: "NotchExtensionsTests", dependencies: ["NotchExtensions"], path: "native/NotchExtensions/Tests"),
    ],
    swiftLanguageModes: [.v6]
)
