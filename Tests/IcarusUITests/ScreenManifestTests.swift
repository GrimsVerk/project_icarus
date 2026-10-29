#if canImport(SwiftUI)
    import Foundation
    import IcarusUI
    import XCTest

    /// Every screen declares its two slots up front, and the table is what S15
    /// reads: the banner belongs to the Calculator entry and the Learn list and
    /// nowhere else, and the entry screen carries no figure (R39, R40).
    final class ScreenManifestTests: XCTestCase {
        /// The declaration this slice promises, screen by screen.
        private static let expected: [String: (banner: Bool, figures: Bool)] = [
            "CalculatorEntryView": (true, false),
            "LearnListView": (true, false),
            "ModuleView": (false, false),
            "ResultView": (false, true),
            "FlipTimerView": (false, true),
            "OnboardingFlow": (false, false),
            "SkinCheckFlow": (false, false),
            "LastingColourFlow": (false, false),
            "HistoryView": (false, true),
            "SettingsView": (false, true),
        ]

        func testTheTableNamesEveryScreenExactlyOnce() {
            let names = ScreenTable.all.map(\.name)
            XCTAssertEqual(names.count, Self.expected.count)
            XCTAssertEqual(Set(names), Set(Self.expected.keys))
            XCTAssertEqual(names.count, Set(names).count, "a screen is declared twice")
        }

        func testEveryScreenDeclaresTheSlotsItsRowPromises() throws {
            for (name, slots) in Self.expected {
                let row = try XCTUnwrap(ScreenTable.all.first { $0.name == name }, name)
                XCTAssertEqual(row.hasBanner, slots.banner, "\(name) banner slot")
                XCTAssertEqual(row.showsFigures, slots.figures, "\(name) figures")
            }
        }

        /// The banner lives on exactly two screens. Stated on its own, because
        /// this is the line R39 draws and the one a new screen is most likely
        /// to cross by accident.
        func testOnlyTheCalculatorEntryAndTheLearnListCarryABanner() {
            let banners = ScreenTable.all.filter(\.hasBanner).map(\.name)
            XCTAssertEqual(Set(banners), ["CalculatorEntryView", "LearnListView"])
        }

        /// The entry screen holds inputs only: every figure the user could act
        /// on lives on the Result screen (R39).
        func testTheCalculatorEntryScreenShowsNoFigure() throws {
            let entry = try XCTUnwrap(ScreenTable.all.first { $0.name == "CalculatorEntryView" })
            XCTAssertFalse(entry.showsFigures)
        }
    }
#endif
