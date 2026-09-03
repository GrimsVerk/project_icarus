@testable import IcarusContent
import XCTest

/// Keeps the IcarusContentTests target non-empty until its first real slice lands.
final class IcarusContentPlaceholderTests: XCTestCase {
    func testModuleIsPresent() {
        XCTAssertNotNil(IcarusContent.self)
    }
}
