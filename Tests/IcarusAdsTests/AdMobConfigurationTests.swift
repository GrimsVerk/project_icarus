#if canImport(GoogleMobileAds) && canImport(UserMessagingPlatform) && canImport(UIKit)
    import GoogleMobileAds
    @testable import IcarusAds
    import XCTest

    /// S15: the AdMob provider asks for nothing before consent is settled,
    /// requests non-personalised ads only, and keeps the slot on refusal.
    @MainActor
    final class AdMobConfigurationTests: XCTestCase {
        func testEveryRequestIsNonPersonalised() {
            let provider = makeProvider(FakeConsent(region: .none))
            XCTAssertTrue(provider.requestConfiguration.nonPersonalised)

            let request = provider.makeRequest()
            let extras = request.adNetworkExtras(for: Extras.self) as? Extras
            XCTAssertEqual(extras?.additionalParameters?["npa"] as? String, "1")
            XCTAssertEqual(provider.recordedRequests.count, 1)
        }

        func testNothingIsRequestedBeforePrepare() {
            let consent = FakeConsent(region: .requiresConsent)
            let provider = makeProvider(consent)

            XCTAssertNotNil(provider.banner(width: 320))
            XCTAssertTrue(provider.recordedRequests.isEmpty)
            XCTAssertEqual(consent.events, [])
        }

        func testConsentRegionShowsTheFlowBeforeTheSDKStarts() async {
            let consent = FakeConsent(region: .requiresConsent, outcome: .consented)
            let provider = AdMobBannerProvider(adUnitID: Self.testUnit, consent: consent) {
                consent.events.append("start")
            }

            let readiness = await provider.prepare(region: .none)

            XCTAssertEqual(readiness, .ready)
            XCTAssertEqual(consent.events, ["region", "present", "start"])
            XCTAssertTrue(provider.requestConfiguration.consentShown)
        }

        func testAFixtureRegionThatRequiresConsentShowsTheFlowEvenIfTheNetworkSaysNot() async {
            let consent = FakeConsent(region: .none, outcome: .consented)
            let provider = makeProvider(consent)

            _ = await provider.prepare(region: .requiresConsent)

            XCTAssertEqual(consent.events, ["region", "present"])
        }

        func testRefusalServesLimitedAdsAndKeepsTheSlot() async {
            let consent = FakeConsent(region: .requiresConsent, outcome: .refused)
            let provider = makeProvider(consent)

            let readiness = await provider.prepare(region: .none)

            XCTAssertEqual(readiness, .limited)
            XCTAssertNotNil(provider.banner(width: 320))
        }

        func testTheFlowRunsOnce() async {
            let consent = FakeConsent(region: .requiresConsent, outcome: .consented)
            let provider = makeProvider(consent)

            _ = await provider.prepare(region: .none)
            _ = await provider.prepare(region: .none)

            XCTAssertEqual(consent.events.filter { $0 == "present" }.count, 1)
        }

        func testNoRegionRequirementShowsNoFlow() async {
            let consent = FakeConsent(region: .none)
            let provider = makeProvider(consent)

            let readiness = await provider.prepare(region: .none)

            XCTAssertEqual(readiness, .ready)
            XCTAssertEqual(consent.events, ["region"])
            XCTAssertFalse(provider.requestConfiguration.consentShown)
        }

        func testANetworkThatAllowsNoRequestKeepsTheSlotEmpty() async {
            let consent = FakeConsent(region: .none, canRequestAds: false)
            let provider = makeProvider(consent)

            let readiness = await provider.prepare(region: .none)

            XCTAssertEqual(readiness, .unavailable)
            XCTAssertNotNil(provider.banner(width: 320))
        }

        // MARK: - Inside

        /// Google's published test banner unit: it only ever serves test ads.
        private static let testUnit = "ca-app-pub-3940256099942544/2435281174"

        private func makeProvider(_ consent: FakeConsent) -> AdMobBannerProvider {
            AdMobBannerProvider(adUnitID: Self.testUnit, consent: consent) {}
        }
    }

    /// A consent service that answers from its fixture and records the order
    /// it was asked in.
    @MainActor
    private final class FakeConsent: ConsentGateway {
        var events: [String] = []
        private let answer: ConsentRegion
        private let outcome: ConsentOutcome
        let canRequestAds: Bool
        let privacyOptionsRequired = false

        init(region: ConsentRegion, outcome: ConsentOutcome = .consented, canRequestAds: Bool = true) {
            answer = region
            self.outcome = outcome
            self.canRequestAds = canRequestAds
        }

        func region() async -> ConsentRegion {
            events.append("region")
            return answer
        }

        func present() async -> ConsentOutcome {
            events.append("present")
            return outcome
        }

        func presentPrivacyOptions() async {}
    }
#endif
