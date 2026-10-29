#if canImport(SwiftUI)
    import SwiftUI

    /// Whether the ad network requires its own consent flow here (R39). The
    /// owner's understanding is that the EEA and the UK do, regardless of
    /// personalisation; the rest of the world does not.
    public enum ConsentRegion: Sendable, Equatable {
        case requiresConsent
        case none
    }

    /// What the provider can serve after `prepare`. Refusing consent serves
    /// limited ads and never removes the slot (R39), so refusal is `.limited`
    /// and not `.unavailable`.
    public enum AdReadiness: Sendable, Equatable {
        case ready
        case limited
        case unavailable
    }

    /// What every request carries. Non-personalised is set before the first
    /// request, never after it (R41), which is why it is a property of the
    /// provider rather than an argument to one call.
    public struct AdRequestConfiguration: Sendable, Equatable {
        public let nonPersonalised: Bool
        public let consentShown: Bool

        public init(nonPersonalised: Bool, consentShown: Bool) {
            self.nonPersonalised = nonPersonalised
            self.consentShown = consentShown
        }
    }

    /// The whole surface the app has on advertising (R40).
    ///
    /// The SDK lives behind this and nowhere else: no ad code or import appears
    /// in Core, Data, Content, or the rest of UI, and `acceptance/S11.sh` checks
    /// that. `banner` answers nil when there is nothing to show, and the screen
    /// keeps its slot either way — a provider never decides the layout.
    public protocol AdBannerProvider: Sendable {
        /// Ask the network for what it needs before the first request: the
        /// consent flow where the region requires one, nothing where it does not.
        func prepare(region: ConsentRegion) async -> AdReadiness

        /// The banner view for a width, or nil when there is no ad to show.
        @MainActor func banner(width: CGFloat) -> AnyView?

        /// The flags every request is made with.
        var requestConfiguration: AdRequestConfiguration { get }

        /// Whether Settings has to offer the network's privacy options, where a
        /// user who answered the consent form changes the answer.
        @MainActor var privacyOptionsRequired: Bool { get }

        /// Shows the network's privacy options form.
        @MainActor func presentPrivacyOptions() async
    }
#endif
