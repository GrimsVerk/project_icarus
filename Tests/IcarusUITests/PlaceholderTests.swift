@testable import IcarusUI
import XCTest

/// Keeps the IcarusUITests target non-empty until its first real slice lands.
final class IcarusUIPlaceholderTests: XCTestCase {
    func testModuleIsPresent() {
        XCTAssertNotNil(IcarusUI.self)
    }
}
