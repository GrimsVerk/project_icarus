@testable import IcarusAds
import XCTest

/// The no-op provider is what previews and tests receive (R40, S15): it shows
/// nothing and asks for nothing, and still declares non-personalised requests.
@MainActor
final class NoAdsProviderTests: XCTestCase {
    func testShowsNothingAndAsksForNothing() async {
        let provider = NoAdsProvider()
        XCTAssertNil(provider.banner(width: 320))
        let readiness = await provider.prepare(region: .requiresConsent)
        XCTAssertEqual(readiness, .unavailable)
        XCTAssertTrue(provider.requestConfiguration.nonPersonalised)
        XCTAssertFalse(provider.requestConfiguration.consentShown)
        XCTAssertFalse(provider.privacyOptionsRequired)
    }

    func testWithoutAnAdUnitTheLiveProviderIsTheNoOp() {
        XCTAssertTrue(IcarusAds.liveProvider(bundle: Bundle(for: Self.self)) is NoAdsProvider)
    }
}
