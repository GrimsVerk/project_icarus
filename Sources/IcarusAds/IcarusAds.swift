#if canImport(SwiftUI)
    import Foundation

    /// The ad package's one entry point for the app.
    public enum IcarusAds {
        /// The provider the app runs on: AdMob for the ad unit the app's
        /// Info.plist names under `IcarusAdUnitID` (from the
        /// `ADMOB_BANNER_UNIT_ID` build setting in `project.yml`), or the no-op
        /// provider where the SDK is not linked or no unit is named.
        @MainActor public static func liveProvider(bundle: Bundle = .main) -> any AdBannerProvider {
            #if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform) && canImport(UIKit)
                if let unit = bundle.object(forInfoDictionaryKey: "IcarusAdUnitID") as? String, !unit.isEmpty {
                    return AdMobBannerProvider(adUnitID: unit)
                }
            #endif
            return NoAdsProvider()
        }
    }
#endif
