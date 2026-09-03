@testable import IcarusCore
import XCTest

/// Fixed state and profiles for the target tests. Never `Date()`: every target
/// is asked for at the same instant in the fixtures' UTC calendar.
private enum TargetFixture {
    static let now = Curves.date(2026, 6, 15, 12)

    /// A replayed state at multiplier 1.0. `reports` sets both the all-time and
    /// the cycle-windowed count, so a test never depends on which one a gate
    /// reads; `redness` is the count that narrows the upper edge of the range.
    static func state(reports: Int = 0, redness: Int = 0, tanState: Double = 0, doseToday: SED = 0) -> DerivedState {
        var state = DerivedState.initial(tunables: .current)
        state.multiplier = 1.0
        state.reportCount = reports
        state.totalReports = reports
        state.rednessReportCount = redness
        for region in Region.allCases {
            state.regions[region]?.tanState = tanState
            state.regions[region]?.doseToday = doseToday
        }
        return state
    }

    static func target(
        _ type: SkinType,
        _ ceiling: Ceiling,
        state: DerivedState,
        stale: Bool = false
    ) -> RegionTarget {
        TanningGoal().target(
            for: .front,
            profile: Profile(skinType: type, ceiling: ceiling, manualMultiplier: nil),
            state: state, now: now, stale: stale, tunables: .current
        )
    }

    /// Calibrated, with a redness report in the cycle: every ceiling is honoured.
    static var calibrated: DerivedState { state(reports: 5, redness: 1) }
}

/// R6: `target = min(MED_personal × melanogenicFraction, MED_personal) × scale`.
/// The scale applies to whichever bound binds, and the target never passes the
/// personal threshold for any type or setting (S1).
final class TargetModelFormulaTests: XCTestCase {
    func testTypeFourPlansALowerFractionOfItsThresholdThanTypeTwo() {
        let state = TargetFixture.calibrated
        let four = TargetFixture.target(.iv, .standard, state: state)
        let two = TargetFixture.target(.ii, .standard, state: state)
        XCTAssertLessThan(four.target / four.medPersonal, two.target / two.medPersonal)
    }

    func testTypeFourIsBoundByTheMelanogenicDose() {
        let four = TargetFixture.target(.iv, .standard, state: TargetFixture.calibrated)
        XCTAssertEqual(four.boundBy, .melanogenic)
        XCTAssertEqual(four.melanogenic, four.medPersonal * 0.75, accuracy: 1e-9)
    }

    func testTypeTwoIsBoundByTheBurnLine() {
        let two = TargetFixture.target(.ii, .standard, state: TargetFixture.calibrated)
        XCTAssertEqual(two.boundBy, .burnLine)
        XCTAssertEqual(two.medPersonal, 2.5, accuracy: 1e-9)
        XCTAssertEqual(two.target, 2.25, accuracy: 1e-9)
    }

    func testTypeThreeStandardBindsTheMelanogenicDoseAtNinetyFivePercent() {
        let three = TargetFixture.target(.iii, .standard, state: TargetFixture.calibrated)
        XCTAssertEqual(three.boundBy, .melanogenic)
        XCTAssertEqual(three.target, three.medPersonal * 0.95 * 0.90, accuracy: 1e-9)
    }

    func testNoTypeAtAnyCeilingIsPlannedAboveThePersonalThreshold() {
        let state = TargetFixture.calibrated
        for type in SkinType.allCases {
            for ceiling in Ceiling.allCases {
                let target = TargetFixture.target(type, ceiling, state: state)
                XCTAssertLessThanOrEqual(target.target, target.medPersonal + 1e-12,
                                         "\(type) at \(ceiling) planned above MED_personal")
            }
        }
    }

    func testTheSelectorChangesTheTargetForEveryType() {
        let state = TargetFixture.calibrated
        for type in SkinType.allCases {
            let low = TargetFixture.target(type, .conservative, state: state).target
            let mid = TargetFixture.target(type, .standard, state: state).target
            let high = TargetFixture.target(type, .aggressive, state: state).target
            XCTAssertLessThan(low, mid, "conservative did not move the number for \(type)")
            XCTAssertLessThan(mid, high, "aggressive did not move the number for \(type)")
        }
    }

    func testTheAdaptationFactorIsOnePlusTheBandGainTimesTanState() {
        let region = RegionState(tanState: 0.4,
                                 lastExposure: nil,
                                 cycleStart: nil,
                                 rednessBoundInCycle: false,
                                 noColourNearCeiling: 0,
                                 doseToday: 0,
                                 doseInCycle: 0,
                                 factorAtLastSession: 1.0,
                                 tanStateAtLastSession: 0)
        XCTAssertEqual(TanningGoal.adaptationFactor(region, skinType: .ii, tunables: .current),
                       1 + 1.25 * 0.4, accuracy: 1e-9)
        XCTAssertEqual(TanningGoal.adaptationFactor(region, skinType: .iv, tunables: .current),
                       1 + 2.0 * 0.4, accuracy: 1e-9)
    }

    func testTheTargetCarriesTheAdaptationFactorTheUIMustLog() {
        let state = TargetFixture.state(reports: 5, redness: 1, tanState: 0.4)
        let target = TargetFixture.target(.ii, .standard, state: state)
        XCTAssertEqual(target.adaptationFactor, 1.5, accuracy: 1e-9)
    }

    func testThePersonalThresholdIsTheBaselineTimesMultiplierTimesTheFactor() {
        let state = TargetFixture.state(reports: 5, redness: 1, tanState: 0.4)
        let target = TargetFixture.target(.ii, .standard, state: state)
        XCTAssertEqual(target.medPersonal, 2.5 * 1.0 * 1.5, accuracy: 1e-9)
    }

    func testRemainingIsTheTargetLessTodaysDose() {
        let state = TargetFixture.state(reports: 5, redness: 1, doseToday: 1.0)
        let target = TargetFixture.target(.ii, .standard, state: state)
        XCTAssertEqual(target.remaining, target.target - 1.0, accuracy: 1e-9)
    }

    func testRemainingNeverGoesBelowZero() {
        let state = TargetFixture.state(reports: 5, redness: 1, doseToday: 4.0)
        let target = TargetFixture.target(.ii, .standard, state: state)
        XCTAssertEqual(target.remaining, 0, accuracy: 1e-12)
    }
}

/// R7: conservative until calibrated, aggressive only once unlocked.
final class TargetModelScaleTests: XCTestCase {
    func testTheNumberIsConservativeBeforeTheCalibrationCountIsReached() {
        let scale = TanningGoal.effectiveScale(profile: Profile(skinType: .ii,
                                                                ceiling: .standard,
                                                                manualMultiplier: nil),
                                               state: TargetFixture.state(reports: 0),
                                               tunables: .current)
        XCTAssertEqual(scale.scale, 0.75, accuracy: 1e-9)
        XCTAssertTrue(scale.conservativeForced)
    }

    func testTheSelectedScaleAppliesOnceTheCalibrationCountIsReached() {
        let scale = TanningGoal.effectiveScale(profile: Profile(skinType: .ii,
                                                                ceiling: .standard,
                                                                manualMultiplier: nil),
                                               state: TargetFixture.state(reports: 3),
                                               tunables: .current)
        XCTAssertEqual(scale.scale, 0.90, accuracy: 1e-9)
        XCTAssertFalse(scale.conservativeForced)
    }

    func testTheUncalibratedTargetIsTheConservativeOne() {
        let uncalibrated = TargetFixture.target(.ii, .standard, state: TargetFixture.state(reports: 0))
        XCTAssertEqual(uncalibrated.scaleUsed, 0.75, accuracy: 1e-9)
        XCTAssertEqual(uncalibrated.target, uncalibrated.medPersonal * 0.75, accuracy: 1e-9)
    }

    func testAggressiveIsRefusedWithoutFiveReportsIncludingRedness() {
        let profile = Profile(skinType: .ii, ceiling: .aggressive, manualMultiplier: nil)
        let tooFew = TanningGoal.effectiveScale(profile: profile,
                                                state: TargetFixture.state(reports: 4, redness: 2),
                                                tunables: .current)
        XCTAssertTrue(tooFew.aggressiveRefused)
        XCTAssertLessThan(tooFew.scale, 1.0)
    }

    func testAggressiveIsRefusedWithoutARednessReportInTheCycle() {
        let profile = Profile(skinType: .ii, ceiling: .aggressive, manualMultiplier: nil)
        let noRedness = TanningGoal.effectiveScale(profile: profile,
                                                   state: TargetFixture.state(reports: 6, redness: 0),
                                                   tunables: .current)
        XCTAssertTrue(noRedness.aggressiveRefused)
        XCTAssertLessThan(noRedness.scale, 1.0)
    }

    func testAggressiveUnlocksAtFiveReportsWithRedness() {
        let profile = Profile(skinType: .ii, ceiling: .aggressive, manualMultiplier: nil)
        let unlocked = TanningGoal.effectiveScale(profile: profile,
                                                  state: TargetFixture.state(reports: 5, redness: 1),
                                                  tunables: .current)
        XCTAssertFalse(unlocked.aggressiveRefused)
        XCTAssertEqual(unlocked.scale, 1.0, accuracy: 1e-9)
    }
}

/// R7: the range is the uncertainty in the threshold, centred on the target.
/// Its upper edge is clipped at `MED_personal` and narrows only with redness
/// reports; staleness widens both edges (R3).
final class TargetModelRangeTests: XCTestCase {
    func testTheRangeContainsTheTarget() {
        let target = TargetFixture.target(.ii, .standard, state: TargetFixture.calibrated)
        XCTAssertTrue(target.range.contains(target.target))
    }

    func testTheUpperEdgeIsClippedAtTheThresholdBeforeAnyRednessReport() {
        let target = TargetFixture.target(.ii, .standard, state: TargetFixture.state(reports: 3, redness: 0))
        XCTAssertTrue(target.rangeClipped)
        XCTAssertEqual(target.range.upperBound, target.medPersonal, accuracy: 1e-9)
    }

    func testTheUpperEdgeUnclipsOnceRednessReportsHaveNarrowedIt() {
        let target = TargetFixture.target(.ii, .standard, state: TargetFixture.state(reports: 5, redness: 5))
        XCTAssertFalse(target.rangeClipped)
        XCTAssertLessThan(target.range.upperBound, target.medPersonal)
    }

    func testStaleWidensBothEdgesByHalfAgain() {
        let state = TargetFixture.state(reports: 5, redness: 5)
        let fresh = TargetFixture.target(.ii, .standard, state: state)
        let stale = TargetFixture.target(.ii, .standard, state: state, stale: true)
        // Half-widths as a fraction of the target each range is centred on, so
        // the comparison survives the 5% stale reduction of the number itself.
        let freshLower = (fresh.target - fresh.range.lowerBound) / fresh.target
        let staleLower = (stale.target - stale.range.lowerBound) / stale.target
        let freshUpper = (fresh.range.upperBound - fresh.target) / fresh.target
        let staleUpper = (stale.range.upperBound - stale.target) / stale.target
        XCTAssertEqual(staleLower / freshLower, 1.5, accuracy: 0.1)
        XCTAssertEqual(staleUpper / freshUpper, 1.5, accuracy: 0.1)
    }

    func testStaleReducesTheNumberByTheStaleReduction() {
        let state = TargetFixture.state(reports: 5, redness: 5)
        let fresh = TargetFixture.target(.ii, .standard, state: state)
        let stale = TargetFixture.target(.ii, .standard, state: state, stale: true)
        XCTAssertEqual(stale.target, fresh.target * 0.95, accuracy: 1e-9)
    }

    func testTheWidenedUpperEdgeStillNeverPassesTheThreshold() {
        let stale = TargetFixture.target(.ii, .standard,
                                         state: TargetFixture.state(reports: 3, redness: 0),
                                         stale: true)
        XCTAssertTrue(stale.rangeClipped)
        XCTAssertLessThanOrEqual(stale.range.upperBound, stale.medPersonal + 1e-12)
    }
}

/// The maintenance scaling the plateau outcome applies (R14).
final class RegionTargetScalingTests: XCTestCase {
    private func maintained(doseToday: SED) -> (full: RegionTarget, scaled: RegionTarget) {
        let state = TargetFixture.state(reports: 5, redness: 1, doseToday: doseToday)
        let full = TargetFixture.target(.ii, .standard, state: state)
        return (full, full.scaled(by: 0.7))
    }

    func testScalingScalesTheTarget() {
        let pair = maintained(doseToday: 1.0)
        XCTAssertEqual(pair.scaled.target, pair.full.target * 0.7, accuracy: 1e-9)
    }

    func testScalingRecomputesTheRemainingBudgetAgainstTodaysDose() {
        let pair = maintained(doseToday: 1.0)
        XCTAssertEqual(pair.scaled.remaining, pair.full.target * 0.7 - 1.0, accuracy: 1e-9)
    }

    func testScalingNeverLeavesANegativeRemaining() {
        let pair = maintained(doseToday: 2.0)
        XCTAssertEqual(pair.scaled.remaining, 0, accuracy: 1e-12)
    }

    func testScalingLeavesTheThresholdsAndTheBoundAlone() {
        let pair = maintained(doseToday: 1.0)
        XCTAssertEqual(pair.scaled.medPersonal, pair.full.medPersonal, accuracy: 1e-12)
        XCTAssertEqual(pair.scaled.melanogenic, pair.full.melanogenic, accuracy: 1e-12)
        XCTAssertEqual(pair.scaled.adaptationFactor, pair.full.adaptationFactor, accuracy: 1e-12)
        XCTAssertEqual(pair.scaled.boundBy, pair.full.boundBy)
        XCTAssertEqual(pair.scaled.region, pair.full.region)
        XCTAssertEqual(pair.scaled.scaleUsed, pair.full.scaleUsed, accuracy: 1e-12)
    }
}
