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

var dependencies: [Package.Dependency] = []

var targets: [Target] = [
    .target(name: "IcarusCore"),
    // Content depends on Core for `CopyKey` and `SkinType`: the app copy is
    // keyed by the engine's enum, never by strings (D-2026-09-03-F7).
    // Resources are copied by their children, never as `.copy("Resources")`:
    // a bundle with a top-level `Resources/` folder is not a valid shallow iOS
    // bundle, and Xcode 26+ codesign rejects it on a signed simulator build.
    .target(
        name: "IcarusContent",
        dependencies: ["IcarusCore"],
        resources: [.copy("Resources/app-copy.json"), .copy("Resources/Learn")]
    ),
    .target(name: "IcarusData", dependencies: ["IcarusCore"], resources: [.copy("Resources/Fixtures")]),
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
    // MarkdownUI renders the Learn modules, including the tables two of them
    // carry, which Apple's `AttributedString` markdown does not render
    // (D-2026-09-03-DEP1, MIT). Pinned exactly, and declared here rather than at
    // the top so the Linux build never even resolves it: IcarusUI, its only
    // client, does not exist there (D-2026-09-03-F6).
    dependencies += [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1"),
    ]

    // The Google Mobile Ads SDK and its User Messaging Platform, for the one
    // banner and the regional consent form (D-2026-09-03-DEP2, Google's
    // licence). Pinned exactly; iOS only, because the SDK ships no macOS slice.
    // Only IcarusAds links them (R40).
    dependencies += [
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads", exact: "13.11.0"),
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-user-messaging-platform",
            exact: "3.1.0"
        ),
    ]

    products += [
        .library(name: "IcarusAds", targets: ["IcarusAds"]),
        .library(name: "IcarusUI", targets: ["IcarusUI"]),
    ]

    targets += [
        .target(
            name: "IcarusAds",
            dependencies: [
                .product(
                    name: "GoogleMobileAds",
                    package: "swift-package-manager-google-mobile-ads",
                    condition: .when(platforms: [.iOS])
                ),
                .product(
                    name: "GoogleUserMessagingPlatform",
                    package: "swift-package-manager-google-user-messaging-platform",
                    condition: .when(platforms: [.iOS])
                ),
            ]
        ),
        .target(
            name: "IcarusUI",
            dependencies: [
                "IcarusCore",
                "IcarusData",
                "IcarusContent",
                "IcarusAds",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        ),
        .testTarget(name: "IcarusAdsTests", dependencies: ["IcarusAds"]),
        .testTarget(name: "IcarusUITests", dependencies: ["IcarusUI"]),
    ]
#endif

let package = Package(
    name: "Icarus",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
