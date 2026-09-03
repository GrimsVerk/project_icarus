@testable import IcarusContent
import XCTest

/// Slice 1 — `icarus://learn/<n>` addresses a module in both directions, and
/// only the twelve real modules are addressable (R27).
final class DeepLinkTests: XCTestCase {
    func testDeepLinkForModuleThree() throws {
        let id = try XCTUnwrap(ModuleID(3))
        XCTAssertEqual(ModuleIndex.deepLink(id), URL(string: "icarus://learn/3"))
    }

    func testParsingModuleSix() throws {
        let url = try XCTUnwrap(URL(string: "icarus://learn/6"))
        let id = try XCTUnwrap(ModuleID(6))
        XCTAssertEqual(DeepLink(url: url), .learn(id))
    }

    func testEveryModuleRoundTripsThroughItsDeepLink() throws {
        for number in 1 ... 12 {
            let id = try XCTUnwrap(ModuleID(number))
            let url = ModuleIndex.deepLink(id)
            XCTAssertEqual(url.absoluteString, "icarus://learn/\(number)", "module \(number)")
            XCTAssertEqual(DeepLink(url: url), .learn(id), "module \(number) parses back")
            XCTAssertEqual(DeepLink.learn(id).url, url, "module \(number) renders the same url")
            XCTAssertNotNil(ModuleIndex.module(id), "module \(number) resolves")
        }
    }

    func testAWrongSchemeIsRejected() throws {
        XCTAssertNil(try DeepLink(url: XCTUnwrap(URL(string: "https://learn/3"))))
        XCTAssertNil(try DeepLink(url: XCTUnwrap(URL(string: "icaru://learn/3"))))
    }

    func testAWrongHostIsRejected() throws {
        XCTAssertNil(try DeepLink(url: XCTUnwrap(URL(string: "icarus://module/3"))))
        XCTAssertNil(try DeepLink(url: XCTUnwrap(URL(string: "icarus://calculator/3"))))
    }

    func testAModuleNumberOutsideOneToTwelveIsRejected() throws {
        XCTAssertNil(try DeepLink(url: XCTUnwrap(URL(string: "icarus://learn/0"))))
        XCTAssertNil(try DeepLink(url: XCTUnwrap(URL(string: "icarus://learn/13"))))
        XCTAssertNil(try DeepLink(url: XCTUnwrap(URL(string: "icarus://learn/-1"))))
    }

    func testAMissingOrExtraPathComponentIsRejected() throws {
        XCTAssertNil(try DeepLink(url: XCTUnwrap(URL(string: "icarus://learn"))))
        XCTAssertNil(try DeepLink(url: XCTUnwrap(URL(string: "icarus://learn/"))))
        XCTAssertNil(try DeepLink(url: XCTUnwrap(URL(string: "icarus://learn/3/4"))))
        XCTAssertNil(try DeepLink(url: XCTUnwrap(URL(string: "icarus://learn/three"))))
    }
}
