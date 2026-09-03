// swift-tools-version: 6.0
// The Icarus package. One root manifest, five library targets (D-2026-09-03-F1).
// On Linux only IcarusCore, IcarusContent and IcarusData exist: the UI and ad
// targets need Apple frameworks, so they are declared under `#if !os(Linux)`
// and the Linux CI job (`core-tests`) builds and tests the engine alone (F6).
import PackageDescription

var products: [Product] = [
    .library(name: "IcarusCore", targets: ["IcarusCore"]),
    .library(name: "IcarusContent", targets: ["IcarusContent"]),
    .library(name: "IcarusData", targets: ["IcarusData"]),
]

var targets: [Target] = [
    .target(name: "IcarusCore"),
    // Content depends on Core for `CopyKey` and `SkinType`: the app copy is
    // keyed by the engine's enum, never by strings (D-2026-09-03-F7).
    .target(name: "IcarusContent", dependencies: ["IcarusCore"], resources: [.copy("Resources")]),
    .target(name: "IcarusData", dependencies: ["IcarusCore"], resources: [.copy("Resources")]),
    // The Learn module files are generated from docs/LEARN_CONTENT.md by this
    // executable (D-2026-09-03-F4). It is Linux-safe, so it is always built.
    .executableTarget(name: "split-learn-content", dependencies: ["IcarusContent"]),
    // The app copy is generated from docs/APP_COPY.md the same way (R42).
    .executableTarget(name: "build-app-copy", dependencies: ["IcarusContent"]),
    .testTarget(name: "IcarusCoreTests", dependencies: ["IcarusCore"]),
    .testTarget(name: "IcarusContentTests", dependencies: ["IcarusContent", "IcarusCore"]),
    .testTarget(name: "IcarusDataTests", dependencies: ["IcarusData"]),
]

#if !os(Linux)
    products += [
        .library(name: "IcarusAds", targets: ["IcarusAds"]),
        .library(name: "IcarusUI", targets: ["IcarusUI"]),
    ]

    targets += [
        .target(name: "IcarusAds"),
        .target(
            name: "IcarusUI",
            dependencies: ["IcarusCore", "IcarusData", "IcarusContent", "IcarusAds"]
        ),
        .testTarget(name: "IcarusAdsTests", dependencies: ["IcarusAds"]),
        .testTarget(name: "IcarusUITests", dependencies: ["IcarusUI"]),
    ]
#endif

let package = Package(
    name: "Icarus",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: products,
    targets: targets
)
