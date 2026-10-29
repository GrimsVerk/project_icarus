#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    @testable import IcarusUI
    import XCTest

    /// The Result screen's figures carry the owner's words (FIG-1 to FIG-13,
    /// VO-1), not the engine's keys, and no figure is labelled in a unit it
    /// is not in.
    final class FigureLabelsTests: XCTestCase {
        func testARegionFigureNamesTheRegionInWords() {
            let figure = Figure(key: .remainingBudget, region: .headAndShoulders, value: 1.2, unit: .sed, reads: [])
            let label = FigureLabels.label(for: figure)
            XCTAssertEqual(label, AppCopy.text(.figRemainingBudget, args: ["region": "head and shoulders"]))
            XCTAssertFalse(label.contains("headAndShoulders"), label)
            XCTAssertFalse(label.contains("{"), label)
        }

        func testEqualSidesAreOneFigurePerSide() {
            let shown = FigureLabels.shown([
                Figure(key: .headlineMinutes, value: 40, unit: .minutes, reads: []),
                Figure(key: .sideMinutes, exposure: .lying(.faceUp), value: 20, unit: .minutes, reads: []),
                Figure(key: .sideMinutes, exposure: .lying(.faceDown), value: 20, unit: .minutes, reads: []),
            ])
            XCTAssertEqual(shown.map(\.label), [AppCopy.text(.figHeadlineMinutes), AppCopy.text(.figSideMinutes)])
        }

        func testUnequalSidesAreNamedBySide() {
            let shown = FigureLabels.shown([
                Figure(key: .sideMinutes, exposure: .lying(.faceUp), value: 22, unit: .minutes, reads: []),
                Figure(key: .sideMinutes, exposure: .lying(.faceDown), value: 18, unit: .minutes, reads: []),
            ])
            XCTAssertEqual(
                shown.map(\.label),
                [AppCopy.text(.figSideMinutesFaceUp), AppCopy.text(.figSideMinutesFaceDown)]
            )
        }

        /// F3: the range is minutes on the recommendation (R7), labelled by
        /// FIG-8 to FIG-10, with the clipped upper edge saying redness is
        /// likely beyond it.
        func testTheRangeEdgesAreMinutesWithTheOwnersLabels() {
            let labels = [FigureKey.rangeLower, .rangeUpper, .rangeUpperClipped].map {
                FigureLabels.label(for: Figure(key: $0, value: 25, unit: .minutes, reads: []))
            }
            XCTAssertEqual(labels, [
                AppCopy.text(.figRangeLower), AppCopy.text(.figRangeUpper), AppCopy.text(.figRangeUpperClipped),
            ])
        }

        func testTheEstimateBadgeNamesEachAssumptionOnceInWords() {
            let spoken = CopyWords.estimate([
                "melanogenicFraction.dark", "melanogenicFraction.medium", "decayHalfLifeDays",
            ])
            let named = [AppCopy.text(.assumptionMelanogenicFraction), AppCopy.text(.assumptionDecayHalfLifeDays)]
            XCTAssertEqual(spoken, AppCopy.text(.voEstimate, args: ["assumptions": named.joined(separator: ", ")]))
            XCTAssertFalse(spoken.contains("decayHalfLifeDays"), spoken)
        }
    }
#endif
