#if canImport(SwiftUI)
    import SwiftUI

    /// The no-op provider (R40): no SDK, no network, no view.
    ///
    /// This is what previews, tests and CI receive, and what the app itself uses
    /// until the AdMob provider lands in M7. It shows nothing, so a screen's
    /// banner slot stays empty rather than absent, and it asks for nothing, so
    /// no consent flow ever appears behind it. Its request configuration is
    /// still the honest one: non-personalised, with no consent form shown.
    public struct NoAdsProvider: AdBannerProvider {
        public init() {}

        public func prepare(region _: ConsentRegion) async -> AdReadiness {
            .unavailable
        }

        @MainActor public func banner(width _: CGFloat) -> AnyView? {
            nil
        }

        public var requestConfiguration: AdRequestConfiguration {
            AdRequestConfiguration(nonPersonalised: true, consentShown: false)
        }

        @MainActor public var privacyOptionsRequired: Bool {
            false
        }

        @MainActor public func presentPrivacyOptions() async {}
    }
#endif
