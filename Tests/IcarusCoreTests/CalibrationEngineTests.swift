@testable import IcarusCore
import XCTest

/// Fixed state, sessions and reports for the calibration tests. A type II's
/// baseline is 2.5 SED, so with the multiplier at 1.0 and an untanned region
/// the estimated threshold a report is judged against is 2.5 SED exactly.
private enum Calib {
    static let tunables = Tunables.current
    static let day = Curves.date(2026, 6, 15, 12)
    static let baseline: SED = 2.5

    /// A replayed state at one multiplier and one tan state, where the factor
    /// recorded for the last session agrees with that tan state — the state a
    /// real session leaves behind.
    static func state(multiplier: Double = 1, reports: Int = 0, tanState: Double = 0) -> DerivedState {
        var state = DerivedState.initial(tunables: tunables)
        state.multiplier = multiplier
        state.reportCount = reports
        state.totalReports = reports
        for region in Region.allCases {
            state.regions[region] = RegionState(
                tanState: tanState,
                lastExposure: day,
                cycleStart: DayKey(day, timeZone: Curves.zone),
                factorAtLastSession: 1 + tunables.adaptationGain(.fair) * tanState,
                tanStateAtLastSession: tanState
            )
        }
        return state
    }

    /// The estimated threshold that state implies for a type II.
    static func estimate(multiplier: Double = 1, tanState: Double = 0) -> SED {
        baseline * multiplier * (1 + tunables.adaptationGain(.fair) * tanState)
    }

    /// Applies one report to one day's session, dosed equally everywhere.
    static func apply(
        _ report: SkinReport,
        dose: SED,
        state: DerivedState,
        manualMultiplier: Double? = nil
    ) throws -> (DerivedState, CalibrationEffect) {
        let doses = [Region.front: dose, .back: dose, .headAndShoulders: dose]
        let session = try SessionFixture.logged(at: day, dose: doses, manualMultiplier: manualMultiplier)
        return CalibrationEngine.apply(report, daySessions: [session], state: state,
                                       skinType: .ii, tunables: tunables)
    }

    static func tanState(_ state: DerivedState) -> Double {
        state.regions[.front]?.tanState ?? 0
    }
}

/// The confidence weighting: `min(1, (burn ? 2 : 1) × k / (min(n, nCap) + k))`
/// (R21). A report's weight never falls below about 0.11, which is the only
/// recency the multiplier has.
final class CalibrationWeightTests: XCTestCase {
    func testTheFirstReportCarriesFullWeight() {
        XCTAssertEqual(CalibrationEngine.weight(n: 0, isBurn: false, tunables: Calib.tunables),
                       1.0, accuracy: 1e-9)
    }

    func testABurnAtFifteenReportsCarriesTwiceANoReactionsWeight() {
        let burn = CalibrationEngine.weight(n: 15, isBurn: true, tunables: Calib.tunables)
        let quiet = CalibrationEngine.weight(n: 15, isBurn: false, tunables: Calib.tunables)
        XCTAssertEqual(burn, 0.286, accuracy: 0.001)
        XCTAssertEqual(burn, 2 * quiet, accuracy: 1e-9)
    }

    func testTheCountIsCappedSoAReportNeverStopsCounting() {
        XCTAssertGreaterThanOrEqual(CalibrationEngine.weight(n: 100, isBurn: true, tunables: Calib.tunables), 0.11)
        XCTAssertEqual(CalibrationEngine.weight(n: 100, isBurn: true, tunables: Calib.tunables),
                       CalibrationEngine.weight(n: 20, isBurn: true, tunables: Calib.tunables), accuracy: 1e-12)
    }

    func testTheNoReactionFloorIsAboutAnEighth() {
        XCTAssertEqual(CalibrationEngine.weight(n: 20, isBurn: false, tunables: Calib.tunables),
                       0.111, accuracy: 0.001)
    }
}

/// Which region a report is evidence about (R21, D-2026-09-03-T4).
final class CalibrationEvidenceRegionTests: XCTestCase {
    private func sessions(front: SED, back: SED, head: SED) throws -> [SessionRecord] {
        try [SessionFixture.logged(at: Calib.day, dose: [.front: front, .back: back, .headAndShoulders: head])]
    }

    func testANamedRegionIsItsOwnEvidence() throws {
        let report = SessionFixture.report(.clearlyPink, on: Calib.day, region: .back)
        let day = try sessions(front: 3.0, back: 1.0, head: 0.5)
        XCTAssertEqual(CalibrationEngine.evidenceRegion(report, daySessions: day), .back)
    }

    func testAllExposedAndNormalTakesTheHighestDoseRegion() throws {
        let report = SessionFixture.report(.normal, on: Calib.day, region: .allExposed)
        let day = try sessions(front: 3.0, back: 1.0, head: 0.5)
        XCTAssertEqual(CalibrationEngine.evidenceRegion(report, daySessions: day), .front)
    }

    func testAllExposedAndRednessTakesTheLowestDoseRegionThatGotAnyDose() throws {
        let report = SessionFixture.report(.clearlyPink, on: Calib.day, region: .allExposed)
        let day = try sessions(front: 3.0, back: 1.0, head: 0)
        XCTAssertEqual(CalibrationEngine.evidenceRegion(report, daySessions: day), .back)
    }

    func testADayWithNoDoseIsEvidenceAboutNothing() {
        let report = SessionFixture.report(.clearlyPink, on: Calib.day, region: .allExposed)
        XCTAssertNil(CalibrationEngine.evidenceRegion(report, daySessions: []))
    }
}

/// A "normal" report is one-sided evidence: below the estimate it confirms and
/// changes nothing, above it the excess goes to tan state first (R21).
final class CalibrationTolerantReportTests: XCTestCase {
    func testAReportBelowTheEstimateChangesNothing() throws {
        let (updated, effect) = try Calib.apply(SessionFixture.report(.normal, on: Calib.day),
                                                dose: 2.0, state: Calib.state())
        XCTAssertEqual(effect, CalibrationEffect.none)
        XCTAssertEqual(updated.multiplier, 1.0, accuracy: 1e-12)
        XCTAssertEqual(Calib.tanState(updated), 0, accuracy: 1e-12)
    }

    func testATolerantSurpriseGoesToTanStateAndNotToTheMultiplier() throws {
        let (updated, effect) = try Calib.apply(SessionFixture.report(.normal, on: Calib.day),
                                                dose: 3.0, state: Calib.state())
        guard case let .tanStateCredited(region, _) = effect else {
            return XCTFail("a tolerant surprise below saturation should credit tan state, got \(effect)")
        }
        XCTAssertEqual(region, .front)
        XCTAssertEqual(updated.multiplier, 1.0, accuracy: 1e-12)
    }

    func testTheCreditIsHalfTheExcessTheSkinTolerated() throws {
        // Dose 3.0 against an estimate of 2.5 is an excess of 0.2.
        let (updated, _) = try Calib.apply(SessionFixture.report(.normal, on: Calib.day),
                                           dose: 3.0, state: Calib.state())
        XCTAssertEqual(Calib.tanState(updated), 0.5 * 0.2, accuracy: 1e-9)
    }

    func testTheEffectCarriesTheCreditItMade() throws {
        let (updated, effect) = try Calib.apply(SessionFixture.report(.normal, on: Calib.day),
                                                dose: 3.0, state: Calib.state())
        guard case let .tanStateCredited(_, credited) = effect else {
            return XCTFail("expected a tan-state credit, got \(effect)")
        }
        XCTAssertEqual(credited, Calib.tanState(updated), accuracy: 1e-9)
    }

    func testSaturatedSkinRaisesTheMultiplierByNoMoreThanTheExcess() throws {
        let saturated = Calib.state(tanState: 1.0)
        let dose = Calib.estimate(tanState: 1.0) * 1.2
        let (updated, _) = try Calib.apply(SessionFixture.report(.normal, on: Calib.day),
                                           dose: dose, state: saturated)
        XCTAssertGreaterThan(updated.multiplier, 1.0)
        XCTAssertLessThanOrEqual(updated.multiplier, 1.2 + 1e-9)
    }

    func testAConfoundedSurpriseIsDiscountedAndSaysSo() throws {
        // Dose 3.5 against an estimate of 2.5 is an excess of 0.4, and alcohol
        // discounts the credit to a quarter of what it would have been.
        let report = SessionFixture.report(.normal, on: Calib.day, confounders: [.alcohol])
        let (updated, effect) = try Calib.apply(report, dose: 3.5, state: Calib.state())
        XCTAssertEqual(effect, .discounted)
        XCTAssertEqual(Calib.tanState(updated), 0.25 * 0.5 * 0.4, accuracy: 1e-9)
    }
}

/// A redness report moves the learned multiplier toward the threshold it
/// implies, weighted by confidence and clamped (R21).
final class CalibrationRednessReportTests: XCTestCase {
    func testTheLearnedMultiplierMovesAllTheWayOnTheFirstReport() throws {
        // Planned under a manual override of 0.8, so the estimate was 2.0 SED
        // and a faint pink at exactly that dose implies a multiplier of 0.8.
        let (updated, effect) = try Calib.apply(SessionFixture.report(.faintPink, on: Calib.day),
                                                dose: 2.0, state: Calib.state(), manualMultiplier: 0.8)
        guard case let .multiplierMoved(was, became) = effect else {
            return XCTFail("a redness report must move the learned multiplier, got \(effect)")
        }
        XCTAssertEqual(was, 1.0, accuracy: 1e-12)
        XCTAssertEqual(became, 0.8, accuracy: 1e-9)
        XCTAssertEqual(updated.multiplier, 0.8, accuracy: 1e-9)
    }

    func testTheLearnedMultiplierMovesFromItselfAndNeverJumpsToTheOverride() throws {
        let (updated, _) = try Calib.apply(SessionFixture.report(.faintPink, on: Calib.day),
                                           dose: 2.0, state: Calib.state(reports: 20),
                                           manualMultiplier: 0.8)
        XCTAssertEqual(updated.multiplier, 0.956, accuracy: 0.001)
    }

    func testTheEstimateUsesTheFactorInForceBeforeTheSession() throws {
        // Tan state has already risen to 0.4, but the session was planned — and
        // must be judged — against the factor of 1.0 that stood before it.
        var state = Calib.state()
        state.regions[.front] = RegionState(tanState: 0.4, lastExposure: Calib.day,
                                            factorAtLastSession: 1.0, tanStateAtLastSession: 0)
        let (updated, _) = try Calib.apply(SessionFixture.report(.faintPink, on: Calib.day),
                                           dose: 2.0, state: state)
        XCTAssertEqual(updated.multiplier, 0.8, accuracy: 1e-9)
    }

    func testARedAndSoreReportAtFifteenReportsMovesTheMultiplierDown() throws {
        let before = Calib.state(reports: 15)
        let (updated, _) = try Calib.apply(SessionFixture.report(.redSore, on: Calib.day),
                                           dose: 2.25, state: before)
        let moved = updated.multiplier - before.multiplier
        XCTAssertLessThanOrEqual(moved, -0.10)
        XCTAssertGreaterThanOrEqual(moved, -0.20)
    }

    func testARedAndSoreReportPastTheCapStillMovesTheMultiplier() throws {
        let before = Calib.state(reports: 40)
        let (updated, _) = try Calib.apply(SessionFixture.report(.redSore, on: Calib.day),
                                           dose: 2.25, state: before)
        XCTAssertLessThanOrEqual(updated.multiplier - before.multiplier, -0.10)
    }

    func testImmediateDarkeningIsReclassifiedAsNormal() throws {
        let report = SessionFixture.report(.faintPink, on: Calib.day, timing: .withinHourGoneByEvening)
        let (updated, effect) = try Calib.apply(report, dose: 2.0, state: Calib.state())
        XCTAssertEqual(effect, .reclassifiedAsNormal)
        XCTAssertEqual(updated.multiplier, 1.0, accuracy: 1e-12)
    }

    func testHittingTheClampPromptsTheUserToRevisitTheirSkinType() throws {
        // A faint pink at 1.0 SED against an estimate of 2.5 implies 0.4, below
        // the clamp's floor.
        let (updated, effect) = try Calib.apply(SessionFixture.report(.faintPink, on: Calib.day),
                                                dose: 1.0, state: Calib.state())
        XCTAssertEqual(effect, .clampHit(revisitSkinType: true))
        XCTAssertEqual(updated.multiplier, Calib.tunables.multiplierClamp.lowerBound, accuracy: 1e-12)
    }

    func testAReportOnADayWithNoLoggedDoseIsRecordedAndNeverCalibrated() {
        let report = SessionFixture.report(.redSore, on: Calib.day)
        let before = Calib.state(reports: 4)
        let (updated, effect) = CalibrationEngine.apply(report, daySessions: [], state: before,
                                                        skinType: .ii, tunables: Calib.tunables)
        XCTAssertEqual(effect, .noDoseThatDay)
        XCTAssertEqual(updated, before)
    }
}

/// Blistering is corrected immediately, whatever the app thought it knew (R21).
final class CalibrationBlisterTests: XCTestCase {
    func testBlisteringCorrectsOnTheVeryFirstReport() throws {
        let (updated, effect) = try Calib.apply(SessionFixture.report(.blistered, on: Calib.day),
                                                dose: 2.5, state: Calib.state())
        guard case let .blisterCorrection(was, became, pauseDays) = effect else {
            return XCTFail("a blistering report must correct, got \(effect)")
        }
        XCTAssertEqual(was, 1.0, accuracy: 1e-12)
        XCTAssertLessThan(became, was)
        XCTAssertEqual(pauseDays, 4)
        XCTAssertEqual(updated.multiplier, became, accuracy: 1e-12)
    }

    func testTheCorrectionIsTheProtectiveFactor() throws {
        // A blister at 2.5 SED on a type II at multiplier 1.0 implies a
        // threshold of 2.5 / 4.0 SED, so an implied multiplier of 0.25; the
        // protective factor cuts that further, and the clamp holds the result
        // at its floor (R21).
        let (updated, _) = try Calib.apply(SessionFixture.report(.blistered, on: Calib.day),
                                           dose: 2.5, state: Calib.state())
        let implied = 2.5 / (2.5 * 1.0 * Calib.tunables.impliedRatio(.blistered))
        let corrected = max(Calib.tunables.multiplierClamp.lowerBound,
                            implied * Calib.tunables.blisterProtectiveFactor)
        XCTAssertEqual(updated.multiplier, corrected, accuracy: 1e-9)
    }

    func testBlisteringCorrectsPastTheConfidenceCapToo() throws {
        let (_, effect) = try Calib.apply(SessionFixture.report(.blistered, on: Calib.day),
                                          dose: 2.5, state: Calib.state(reports: 40))
        guard case let .blisterCorrection(_, _, pauseDays) = effect else {
            return XCTFail("a blistering report must correct at any n, got \(effect)")
        }
        XCTAssertEqual(pauseDays, Calib.tunables.blisterPauseDays)
    }
}
