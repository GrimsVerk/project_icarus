@testable import IcarusCore
import XCTest

/// Fixed instants and hand-built region states for the adaptation tests. Never
/// `Date()`: every question is asked at the same instant in the fixtures' UTC
/// calendar.
private enum Adapt {
    static let tunables = Tunables.current
    static let now = Curves.date(2026, 7, 6, 12)

    /// A region that last saw the sun `daysAgo` days before `now`, whose tan
    /// state and the factor recorded for its last session agree with each other
    /// — the state a real session leaves behind.
    static func region(
        tanState: Double,
        daysAgo: Double = 0,
        bound: Bool = false,
        noColour: Int = 0
    ) -> RegionState {
        RegionState(
            tanState: tanState,
            lastExposure: now.addingTimeInterval(-daysAgo * 86400),
            cycleStart: DayKey(now.addingTimeInterval(-daysAgo * 86400), timeZone: Curves.zone),
            rednessBoundInCycle: bound,
            noColourNearCeiling: noColour,
            doseToday: 0,
            doseInCycle: 4.0,
            factorAtLastSession: 1 + tunables.adaptationGain(.fair) * tanState,
            tanStateAtLastSession: tanState
        )
    }

    /// `count` sessions one day apart, each delivering exactly the day's target,
    /// through the engine's own decay-then-rise pair.
    static func daily(sessions count: Int) -> RegionState {
        var state = RegionState()
        for index in 0 ..< count {
            let moment = now.addingTimeInterval(Double(index) * 86400)
            state = AdaptationModel.decayed(state, to: moment, tunables: tunables)
            state = AdaptationModel.advanced(state, doseFraction: 1.0, skinType: .ii,
                                             at: moment, tunables: tunables)
        }
        return state
    }
}

/// The decay, and the gap that ends a tan cycle (R12, R14).
final class AdaptationDecayTests: XCTestCase {
    func testTheTanStateHalvesOverOneHalfLife() {
        let decayed = AdaptationModel.decayed(Adapt.region(tanState: 0.8, daysAgo: 21),
                                              to: Adapt.now, tunables: Adapt.tunables)
        XCTAssertEqual(decayed.tanState, 0.4, accuracy: 1e-9)
    }

    func testARegionThatHasNeverSeenTheSunDoesNotDecay() {
        let untouched = RegionState(tanState: 0.5)
        let decayed = AdaptationModel.decayed(untouched, to: Adapt.now, tunables: Adapt.tunables)
        XCTAssertEqual(decayed.tanState, 0.5, accuracy: 1e-12)
    }

    func testAGapPastTheCycleLimitEndsTheCycle() {
        let region = Adapt.region(tanState: 0.8, daysAgo: 20, bound: true, noColour: 3)
        let decayed = AdaptationModel.decayed(region, to: Adapt.now, tunables: Adapt.tunables)
        XCTAssertNil(decayed.cycleStart)
        XCTAssertFalse(decayed.rednessBoundInCycle)
        XCTAssertEqual(decayed.doseInCycle, 0, accuracy: 1e-12)
        XCTAssertEqual(decayed.noColourNearCeiling, 0)
    }

    func testAGapInsideTheCycleLimitLeavesTheCycleRunning() {
        let region = Adapt.region(tanState: 0.8, daysAgo: 13, bound: true, noColour: 3)
        let decayed = AdaptationModel.decayed(region, to: Adapt.now, tunables: Adapt.tunables)
        XCTAssertNotNil(decayed.cycleStart)
        XCTAssertTrue(decayed.rednessBoundInCycle)
        XCTAssertEqual(decayed.doseInCycle, 4.0, accuracy: 1e-12)
        XCTAssertEqual(decayed.noColourNearCeiling, 3)
    }
}

/// The leaky-integrator rise, and the closed-form figures the rise constant was
/// solved for (R12, D-2026-09-03-T1).
final class AdaptationRiseTests: XCTestCase {
    func testOneSessionAtTheTargetRisesByTheLeakyIntegratorStep() {
        let risen = AdaptationModel.advanced(RegionState(), doseFraction: 1.0, skinType: .ii,
                                             at: Adapt.now, tunables: Adapt.tunables)
        XCTAssertEqual(risen.tanState, 1 - exp(-1.0 / 7.2), accuracy: 1e-9)
    }

    func testHalfADoseRisesLessThanAWholeOne() {
        let half = AdaptationModel.advanced(RegionState(), doseFraction: 0.5, skinType: .ii,
                                            at: Adapt.now, tunables: Adapt.tunables)
        XCTAssertEqual(half.tanState, 1 - exp(-0.5 / 7.2), accuracy: 1e-9)
    }

    func testDarkerSkinRisesByTheBandMultiplier() {
        let risen = AdaptationModel.advanced(RegionState(), doseFraction: 1.0, skinType: .v,
                                             at: Adapt.now, tunables: Adapt.tunables)
        XCTAssertEqual(risen.tanState, 1 - exp(-1.5 / 7.2), accuracy: 1e-9)
    }

    func testTheRiseRecordsWhereTheSkinStoodBeforeIt() {
        // The region carries the factor of an older session, 1.0; advancing it
        // must record the 1.5 that stood before this one, not keep the stale
        // number and not record the one the rise just produced.
        let before = RegionState(tanState: 0.4, lastExposure: Adapt.now.addingTimeInterval(-86400),
                                 factorAtLastSession: 1.0, tanStateAtLastSession: 0)
        let risen = AdaptationModel.advanced(before, doseFraction: 1.0, skinType: .ii,
                                             at: Adapt.now, tunables: Adapt.tunables)
        XCTAssertEqual(risen.tanStateAtLastSession, 0.4, accuracy: 1e-9)
        XCTAssertEqual(risen.factorAtLastSession, 1.5, accuracy: 1e-9)
        XCTAssertEqual(risen.lastExposure, Adapt.now)
    }

    func testTwentyOneDailySessionsAtTheTargetReachFourFifths() {
        XCTAssertEqual(Adapt.daily(sessions: 21).tanState, 0.80, accuracy: 0.02)
    }

    func testDailySessionsSaturateJustAboveFourFifths() {
        XCTAssertEqual(Adapt.daily(sessions: 120).tanState, 0.82, accuracy: 0.02)
    }

    func testTheTanStateNeverPassesSaturation() {
        XCTAssertLessThanOrEqual(Adapt.daily(sessions: 400).tanState, 1.0)
    }
}

/// A tolerant surprise goes to tan state first, and only what tan state cannot
/// absorb is left for the multiplier (R21).
final class AdaptationTolerantCreditTests: XCTestCase {
    func testTheCreditIsTheTunableShareOfTheExcess() {
        let (credited, _) = AdaptationModel.creditTolerant(Adapt.region(tanState: 0.2),
                                                           excess: 0.4, tunables: Adapt.tunables)
        XCTAssertEqual(credited.tanState, 0.2 + 0.5 * 0.4, accuracy: 1e-9)
    }

    func testAnExcessTanStateCanAbsorbLeavesNothingForTheMultiplier() {
        let (_, unabsorbed) = AdaptationModel.creditTolerant(Adapt.region(tanState: 0.2),
                                                             excess: 0.4, tunables: Adapt.tunables)
        XCTAssertEqual(unabsorbed, 0, accuracy: 1e-9)
    }

    func testSaturatedSkinAbsorbsNothingAndHandsTheWholeExcessOn() {
        let (credited, unabsorbed) = AdaptationModel.creditTolerant(Adapt.region(tanState: 1.0),
                                                                    excess: 0.3, tunables: Adapt.tunables)
        XCTAssertEqual(credited.tanState, 1.0, accuracy: 1e-12)
        XCTAssertEqual(unabsorbed, 0.3, accuracy: 1e-9)
    }

    func testTheCreditNeverPushesTanStatePastSaturation() {
        let (credited, unabsorbed) = AdaptationModel.creditTolerant(Adapt.region(tanState: 0.95),
                                                                    excess: 0.4, tunables: Adapt.tunables)
        XCTAssertEqual(credited.tanState, 1.0, accuracy: 1e-9)
        XCTAssertGreaterThan(unabsorbed, 0)
    }
}

/// The escalation notice and the gap notice (R13, D-2026-09-03-T1, T5).
final class AdaptationNoticeTests: XCTestCase {
    /// The fixture's `tanState` is the tan state as of the last session; the
    /// notice reads a region as Replay hands it out — decayed to `now` (R44) —
    /// so the region is faded to the clock first.
    private func notice(_ region: RegionState) -> EscalationNotice? {
        let faded = AdaptationModel.decayed(region, to: Adapt.now, tunables: Adapt.tunables)
        return AdaptationModel.escalationNotice(faded, now: Adapt.now, skinType: .ii, tunables: Adapt.tunables)
    }

    func testTheEscalationNoticeFiresAtHalfTheMaximumRise() {
        // Half of a fair band's 1.25 gain is a factor of 1.625, reached at tan
        // state 0.5 exactly. The boundary is inclusive.
        XCTAssertEqual(notice(Adapt.region(tanState: 0.5)), .risen(factor: 1.625))
    }

    func testTheEscalationNoticeIsSilentBelowHalfTheMaximumRise() {
        XCTAssertNil(notice(Adapt.region(tanState: 0.49)))
    }

    func testTheGapNoticeFiresAtTheHalfLifeBoundary() {
        // One half-life undoes exactly half the rise, which is the line, and
        // the line is inclusive (D-2026-09-03-T5).
        guard case let .dropped(fraction)? = notice(Adapt.region(tanState: 0.8, daysAgo: 21)) else {
            return XCTFail("a gap of exactly one half-life should report a dropped tolerance")
        }
        XCTAssertEqual(fraction, 0.5, accuracy: 1e-9)
    }

    func testTheGapNoticeReportsTheShareOfTheRiseTheGapUndid() {
        guard case let .dropped(fraction)? = notice(Adapt.region(tanState: 0.78, daysAgo: 28)) else {
            return XCTFail("a four-week gap should report a dropped tolerance")
        }
        XCTAssertEqual(fraction, 1 - pow(0.5, 28.0 / 21.0), accuracy: 1e-9)
    }

    func testAGapInsideTheCycleLimitProducesNoNotice() {
        XCTAssertNil(notice(Adapt.region(tanState: 0.6, daysAgo: 13)))
    }

    func testAGapThatUndidLessThanHalfTheRiseProducesNoNotice() {
        XCTAssertNil(notice(Adapt.region(tanState: 0.45, daysAgo: 16)))
    }
}

/// The plateau outcome hangs on the count, never on the tan state re-read at
/// plan time, so a weekend's decay does not flicker it away (R14).
final class AdaptationPlateauTests: XCTestCase {
    private func outcome(_ region: RegionState) -> PlateauOutcome? {
        AdaptationModel.plateauOutcome(region, tunables: Adapt.tunables)
    }

    func testTheOutcomeIsSilentBelowTheCount() {
        XCTAssertNil(outcome(Adapt.region(tanState: 0.8, noColour: 2)))
    }

    func testARednessBoundInTheCycleMakesItTheCeiling() {
        XCTAssertEqual(outcome(Adapt.region(tanState: 0.8, bound: true, noColour: 3)), .ceiling)
    }

    func testWithoutARednessBoundItIsUnderDosed() {
        XCTAssertEqual(outcome(Adapt.region(tanState: 0.8, bound: false, noColour: 3)), .underDosed)
    }

    func testTheOutcomeSurvivesAWeekendOfDecay() {
        let friday = Adapt.region(tanState: 0.78, bound: true, noColour: 3)
        let monday = AdaptationModel.decayed(friday, to: Adapt.now.addingTimeInterval(3 * 86400),
                                             tunables: Adapt.tunables)
        XCTAssertLessThan(monday.tanState, Adapt.tunables.plateauTanState)
        XCTAssertEqual(outcome(monday), .ceiling)
    }
}
