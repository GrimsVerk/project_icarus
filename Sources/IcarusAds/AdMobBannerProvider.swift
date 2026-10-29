#if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform) && canImport(UIKit)
    import GoogleMobileAds
    import SwiftUI
    import UIKit

    /// The AdMob banner (R39, R41), behind `AdBannerProvider` (R40).
    ///
    /// Every request is non-personalised: `npa=1` is part of the request this
    /// provider builds, so there is no request without it. Nothing is requested
    /// before `prepare` has run the consent flow where the network requires one;
    /// until then the slot is there and empty. A refusal serves the network's
    /// limited ads and never removes the slot.
    @MainActor
    public final class AdMobBannerProvider: AdBannerProvider {
        private let adUnitID: String
        private let consent: any ConsentGateway
        private let startSDK: @MainActor () -> Void
        private let state = BannerState()
        private let shown = LockedFlag()

        /// Every request built so far, in order: what S15 asserts on.
        private(set) var recordedRequests: [Request] = []

        /// - Parameters:
        ///   - adUnitID: the banner's ad unit.
        ///   - consent: the network's consent service; Google's by default.
        ///   - startSDK: starts the SDK once consent allows it.
        public init(
            adUnitID: String,
            consent: any ConsentGateway = UMPConsentGateway(),
            startSDK: @escaping @MainActor () -> Void = { MobileAds.shared.start(completionHandler: nil) }
        ) {
            self.adUnitID = adUnitID
            self.consent = consent
            self.startSDK = startSDK
        }

        /// Runs once; later calls answer what the first one decided.
        ///
        /// The network decides by geography whether its form is required; the
        /// `region` argument can only add the requirement, never waive it.
        public func prepare(region: ConsentRegion) async -> AdReadiness {
            if let decided = state.readiness {
                return decided
            }
            var readiness = AdReadiness.ready
            let networkRegion = await consent.region()
            if region == .requiresConsent || networkRegion == .requiresConsent {
                let outcome = await consent.present()
                shown.value = true
                if outcome == .refused {
                    readiness = .limited
                }
            }
            if consent.canRequestAds {
                startSDK()
            } else {
                readiness = .unavailable
            }
            state.readiness = readiness
            return readiness
        }

        public func banner(width: CGFloat) -> AnyView? {
            AnyView(BannerSlot(provider: self, state: state, width: width))
        }

        public nonisolated var requestConfiguration: AdRequestConfiguration {
            AdRequestConfiguration(nonPersonalised: true, consentShown: shown.value)
        }

        public var privacyOptionsRequired: Bool {
            consent.privacyOptionsRequired
        }

        public func presentPrivacyOptions() async {
            await consent.presentPrivacyOptions()
        }

        /// A request, non-personalised, recorded.
        func makeRequest() -> Request {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            let request = Request()
            request.register(extras)
            recordedRequests.append(request)
            return request
        }

        fileprivate var unitID: String {
            adUnitID
        }
    }

    /// What `prepare` decided, observed by every slot so each loads its banner
    /// only once a request is allowed.
    @MainActor
    final class BannerState: ObservableObject {
        @Published var readiness: AdReadiness?
    }

    /// A flag readable from any thread, for the nonisolated configuration.
    final class LockedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false

        var value: Bool {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    /// The slot: the banner's height is always kept, and the banner itself
    /// appears once a request is allowed.
    struct BannerSlot: View {
        let provider: AdMobBannerProvider
        @ObservedObject var state: BannerState
        let width: CGFloat

        var body: some View {
            let size = currentOrientationAnchoredAdaptiveBanner(width: width)
            Group {
                switch state.readiness {
                case .ready, .limited:
                    BannerRepresentable(provider: provider, size: size)
                case .unavailable, nil:
                    Color.clear
                }
            }
            .frame(width: size.size.width, height: size.size.height)
        }
    }

    struct BannerRepresentable: UIViewRepresentable {
        let provider: AdMobBannerProvider
        let size: AdSize

        func makeUIView(context _: Context) -> BannerView {
            let view = BannerView(adSize: size)
            view.adUnitID = provider.unitID
            view.load(provider.makeRequest())
            return view
        }

        func updateUIView(_ view: BannerView, context _: Context) {
            // The banner reaches its view controller once it is in a window.
            if view.rootViewController == nil {
                view.rootViewController = view.window?.rootViewController
            }
        }
    }
#endif
