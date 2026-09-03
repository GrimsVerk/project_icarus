@testable import IcarusData
import XCTest

/// Keeps the IcarusDataTests target non-empty until its first real slice lands.
final class IcarusDataPlaceholderTests: XCTestCase {
    func testModuleIsPresent() {
        XCTAssertNotNil(IcarusData.self)
    }
}
