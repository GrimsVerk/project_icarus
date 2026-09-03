@testable import IcarusAds
import XCTest

/// Keeps the IcarusAdsTests target non-empty until its first real slice lands.
final class IcarusAdsPlaceholderTests: XCTestCase {
    func testModuleIsPresent() {
        XCTAssertNotNil(IcarusAds.self)
    }
}
