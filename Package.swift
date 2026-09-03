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
    .target(name: "IcarusContent", resources: [.copy("Resources")]),
    .target(name: "IcarusData", dependencies: ["IcarusCore"], resources: [.copy("Resources")]),
    .testTarget(name: "IcarusCoreTests", dependencies: ["IcarusCore"]),
    .testTarget(name: "IcarusContentTests", dependencies: ["IcarusContent"]),
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
