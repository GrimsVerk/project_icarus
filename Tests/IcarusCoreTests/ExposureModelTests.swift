@testable import IcarusCore
import XCTest

/// Requests built from the public initialisers, at fixed instants in the
/// fixtures' UTC calendar. A calibrated type II at multiplier 1.0 and tan state
/// 0 has MED_personal 2.5 SED and a standard target of 2.25 SED per region.
private enum PlanFixture {
    static let budget: SED = 2.25
    static let profile = Profile(skinType: .ii, ceiling: .standard, manualMultiplier: nil)
    /// Noon to 15:00 — long enough that no solve is cut short by the window.
    static let threeHours = window(12, minutes: 180)

    static func window(_ hour: Int, _ minute: Int = 0, minutes: Double) -> Window {
        let start = Curves.date(2026, 6, 15, hour, minute)
        return Window(start: start, end: start.addingTimeInterval(minutes * 60))
    }

    static func state(spent: [Region: SED]) -> DerivedState {
        var state = DerivedState.initial(tunables: .current)
        state.multiplier = 1.0
        state.reportCount = 5
        state.totalReports = 5
        state.rednessReportCount = 1
        for region in Region.allCases {
            state.regions[region]?.doseToday = spent[region] ?? 0
        }
        return state
    }

    static func targets(spent: [Region: SED] = [:]) -> [Region: RegionTarget] {
        let derived = state(spent: spent)
        var built = [Region: RegionTarget]()
        for region in Region.allCases {
            built[region] = TanningGoal().target(
                for: region, profile: profile, state: derived,
                now: threeHours.start, stale: false, tunables: .current
            )
        }
        return built
    }

    static func request(
        _ curve: ForecastCurve,
        _ window: Window,
        posture: Posture = .lyingTurning,
        firstSide: Side = .faceUp,
        cover: Bool = false,
        intent: Intent = .bestMinutes,
        spent: [Region: SED] = [:]
    ) -> ExposureRequest {
        var doses = [Region: SED]()
        for region in Region.allCases {
            doses[region] = spent[region] ?? 0
        }
        return ExposureRequest(
            window: window, now: window.start.addingTimeInterval(-3600), posture: posture,
            firstSide: firstSide, coverHeadAndShoulders: cover, intent: intent,
            targets: targets(spent: spent), doseToday: doses, curve: curve
        )
    }

    static func solve(
        _ curve: ForecastCurve,
        _ window: Window,
        posture: Posture = .lyingTurning,
        firstSide: Side = .faceUp,
        cover: Bool = false,
        spent: [Region: SED] = [:]
    ) -> ExposurePlan? {
        ExposureModel.solve(
            request(curve, window, posture: posture, firstSide: firstSide, cover: cover, spent: spent),
            tunables: .current
        )
    }

    static func dose(_ exposure: Exposure, cover: Bool = false, on curve: ForecastCurve) -> [Region: SED] {
        ExposureModel.dose(
            exposure, coverHeadAndShoulders: cover, over: window(12, minutes: 60),
            curve: curve, tunables: .current
        )
    }

    static func minutes(_ plan: ExposurePlan, _ exposure: Exposure) -> Double {
        plan.sides.first { $0.exposure == exposure }?.window.minutes ?? 0
    }
}

private func region(of warning: Warning) -> Region {
    switch warning {
    case let .pastTarget(region, _), let .reachesThreshold(region, _): region
    }
}

private func dayTotal(of warning: Warning) -> SED {
    switch warning {
    case let .pastTarget(_, total), let .reachesThreshold(_, total): total
    }
}

/// R9, R10: what each posture credits to each region, and the one attenuation
/// function every logging path calls (R15).
final class ExposureDoseTests: XCTestCase {
    /// One hour at UVI 8.
    private let hour = 8 * 60 / 66.7

    func testUpAndAboutGivesHeadAndShouldersTheWholeDoseAndEachTorsoSideAHalf() throws {
        let doses = try PlanFixture.dose(.upAndAbout, on: Curves.beachFlatUVI8())
        XCTAssertEqual(doses[.headAndShoulders] ?? 0, hour, accuracy: 1e-9)
        XCTAssertEqual(doses[.front] ?? 0, hour * 0.5, accuracy: 1e-9)
        XCTAssertEqual(doses[.back] ?? 0, hour * 0.5, accuracy: 1e-9)
    }

    func testLyingFaceUpCreditsTheFrontAndTheHeadAndShouldersInFull() throws {
        let doses = try PlanFixture.dose(.lying(.faceUp), on: Curves.beachFlatUVI8())
        XCTAssertEqual(doses[.front] ?? 0, hour, accuracy: 1e-9)
        XCTAssertEqual(doses[.headAndShoulders] ?? 0, hour, accuracy: 1e-9)
        XCTAssertEqual(doses[.back] ?? 0, 0, accuracy: 1e-12)
    }

    func testLyingFaceDownCreditsTheBackInFullAndTheShouldersAtHalf() throws {
        let doses = try PlanFixture.dose(.lying(.faceDown), on: Curves.beachFlatUVI8())
        XCTAssertEqual(doses[.back] ?? 0, hour, accuracy: 1e-9)
        XCTAssertEqual(doses[.headAndShoulders] ?? 0, hour * 0.5, accuracy: 1e-9)
        XCTAssertEqual(doses[.front] ?? 0, 0, accuracy: 1e-12)
    }

    func testCoverLogsHeadAndShouldersAtZeroWithoutTouchingTheTorso() throws {
        let doses = try PlanFixture.dose(.upAndAbout, cover: true, on: Curves.beachFlatUVI8())
        XCTAssertEqual(doses[.headAndShoulders] ?? 0, 0, accuracy: 1e-12)
        XCTAssertEqual(doses[.front] ?? 0, hour * 0.5, accuracy: 1e-9)
    }

    func testTheWholeWindowRawLyingDoseIsTwoEqualHalvesInSideOrder() throws {
        let raw = try ExposureModel.wholeWindowRaw(
            PlanFixture.threeHours, posture: .lyingTurning, firstSide: .faceUp,
            coverHeadAndShoulders: false, curve: Curves.beachFlatUVI8(), tunables: .current
        )
        let half = 1.5 * hour
        XCTAssertEqual(raw[.front] ?? 0, half, accuracy: 1e-9)
        XCTAssertEqual(raw[.back] ?? 0, half, accuracy: 1e-9)
        XCTAssertEqual(raw[.headAndShoulders] ?? 0, half + 0.5 * half, accuracy: 1e-9)
    }

    func testTheWholeWindowRawUpAndAboutDoseIsTheWholeWindow() throws {
        let curve = try Curves.beachFlatUVI8()
        let raw = ExposureModel.wholeWindowRaw(
            PlanFixture.threeHours, posture: .upAndAbout, firstSide: .faceUp,
            coverHeadAndShoulders: false, curve: curve, tunables: .current
        )
        XCTAssertEqual(raw[.headAndShoulders] ?? 0, 3 * hour, accuracy: 1e-9)
        XCTAssertEqual(raw[.front] ?? 0, 1.5 * hour, accuracy: 1e-9)
    }

    func testFiftySPFAppliedNormallyDividesEveryRegionByAboutSeven() {
        let bare: [Region: SED] = [.front: 2.0, .back: 1.5, .headAndShoulders: 3.0]
        let worn = ExposureModel.attenuated(
            bare, sunscreen: SunscreenChoice(spfLabel: 50, application: .normal), coverHeadAndShoulders: false
        )
        for (region, dose) in bare {
            XCTAssertEqual(worn[region] ?? 0, dose / 7.0710678118654755, accuracy: 1e-9)
        }
    }

    func testAttenuationWithoutSunscreenOnlyZeroesTheCoveredRegion() {
        let bare: [Region: SED] = [.front: 2.0, .back: 1.5, .headAndShoulders: 3.0]
        let worn = ExposureModel.attenuated(bare, sunscreen: nil, coverHeadAndShoulders: true)
        XCTAssertEqual(worn[.headAndShoulders] ?? 0, 0, accuracy: 1e-12)
        XCTAssertEqual(worn[.front] ?? 0, 2.0, accuracy: 1e-12)
        XCTAssertEqual(worn[.back] ?? 0, 1.5, accuracy: 1e-12)
    }

    func testTheAttenuationRegionIsTheOnePushedHardestAgainstItsRemaining() {
        let targets = PlanFixture.targets(spent: [.back: 2.0])
        let raw: [Region: SED] = [.front: 1.0, .back: 1.0, .headAndShoulders: 1.0]
        XCTAssertEqual(ExposureModel.attenuationRegion(raw: raw, targets: targets), .back)
    }

    func testTheAttenuationRegionIsATorsoSideWhenHeadAndShouldersIsCovered() throws {
        let raw = try ExposureModel.wholeWindowRaw(
            PlanFixture.threeHours, posture: .lyingTurning, firstSide: .faceUp,
            coverHeadAndShoulders: true, curve: Curves.beachFlatUVI8(), tunables: .current
        )
        let found = ExposureModel.attenuationRegion(raw: raw, targets: PlanFixture.targets())
        XCTAssertTrue(found == .front || found == .back, "expected a torso side, got \(String(describing: found))")
    }

    func testASpentRegionOutranksEveryRegionThatStillHasBudget() {
        let targets = PlanFixture.targets(spent: [.front: PlanFixture.budget])
        let raw: [Region: SED] = [.front: 0.01, .back: 2.0, .headAndShoulders: 2.0]
        XCTAssertEqual(ExposureModel.attenuationRegion(raw: raw, targets: targets), .front)
    }

    func testThereIsNoAttenuationRegionWhenNothingIsExposed() {
        let raw: [Region: SED] = [.front: 0, .back: 0, .headAndShoulders: 0]
        XCTAssertNil(ExposureModel.attenuationRegion(raw: raw, targets: PlanFixture.targets()))
    }
}

/// R8, R9, R17: the coupled per-side solve. Every region limits, the sides are
/// consecutive from the best start, and a window that cannot reach the budget
/// is planned in full rather than as no minutes at all.
final class ExposureSolveTests: XCTestCase {
    private let morning = Window(start: Curves.date(2026, 6, 15, 9), end: Curves.date(2026, 6, 15, 12))

    func testUpAndAboutOnARisingCurveTakesTheLastMinutesOfTheWindow() throws {
        let curve = try Curves.morningRising()
        let plan = try XCTUnwrap(PlanFixture.solve(curve, morning, posture: .upAndAbout))
        XCTAssertEqual(plan.span.end.timeIntervalSince(morning.end), 0, accuracy: 1)
        XCTAssertLessThan(plan.totalMinutes, morning.minutes)
    }

    func testLyingSidesAreConsecutiveAndInsideTheWindow() throws {
        let plan = try XCTUnwrap(PlanFixture.solve(Curves.morningRising(), morning))
        XCTAssertEqual(plan.intervals.count, 2)
        let first = try XCTUnwrap(plan.intervals.first)
        let second = try XCTUnwrap(plan.intervals.last)
        XCTAssertEqual(first.exposure, .lying(.faceUp))
        XCTAssertEqual(second.window.start, first.window.end)
        XCTAssertGreaterThanOrEqual(first.window.start, morning.start)
        XCTAssertLessThanOrEqual(second.window.end, morning.end)
    }

    func testTheSecondSideIsTheOtherWayUp() throws {
        let plan = try XCTUnwrap(PlanFixture.solve(Curves.beachFlatUVI8(),
                                                   PlanFixture.threeHours,
                                                   firstSide: .faceDown))
        XCTAssertEqual(plan.intervals.first?.exposure, .lying(.faceDown))
        XCTAssertEqual(plan.intervals.last?.exposure, .lying(.faceUp))
    }

    func testAWindowThatCannotReachTheBudgetIsPlannedInFull() throws {
        let short = PlanFixture.window(12, minutes: 30)
        let plan = try XCTUnwrap(PlanFixture.solve(Curves.shoulderHourUVI2(), short, posture: .upAndAbout))
        XCTAssertTrue(plan.fillsWindow)
        XCTAssertEqual(plan.totalMinutes, 30, accuracy: 1e-6)
        XCTAssertEqual(plan.span.start, short.start)
        XCTAssertEqual(plan.span.end, short.end)
    }

    func testAShortLyingWindowIsFilledByTwoNonEmptySides() throws {
        let short = PlanFixture.window(12, minutes: 30)
        let plan = try XCTUnwrap(PlanFixture.solve(Curves.shoulderHourUVI2(), short))
        let faceUp = PlanFixture.minutes(plan, .lying(.faceUp))
        let faceDown = PlanFixture.minutes(plan, .lying(.faceDown))
        XCTAssertGreaterThan(faceUp, 0)
        XCTAssertGreaterThan(faceDown, 0)
        XCTAssertEqual(faceUp + faceDown, short.minutes, accuracy: 1e-6)
    }

    func testAFilledLyingWindowSpendsTheSameShareOfEachSidesBudget() throws {
        let short = PlanFixture.window(12, minutes: 30)
        let plan = try XCTUnwrap(PlanFixture.solve(Curves.shoulderHourUVI2(), short))
        let front = (plan.perRegionDose[.front] ?? 0) / PlanFixture.budget
        let back = (plan.perRegionDose[.back] ?? 0) / PlanFixture.budget
        XCTAssertEqual(front, back, accuracy: 1e-6)
        XCTAssertGreaterThan(front, 0)
    }

    func testEqualSidesOnAFlatCurveAreShownAsOneFigure() throws {
        let plan = try XCTUnwrap(PlanFixture.solve(Curves.beachFlatUVI8(), PlanFixture.threeHours, cover: true))
        let faceUp = PlanFixture.minutes(plan, .lying(.faceUp))
        XCTAssertEqual(PlanFixture.minutes(plan, .lying(.faceDown)), faceUp, accuracy: 1e-6)
        XCTAssertEqual(plan.totalMinutes, 2 * faceUp, accuracy: 1e-6)
        XCTAssertFalse(plan.showTwoFigures)
    }

    func testASlopingCurveGivesTheSidesDifferentTimesAndTwoFigures() throws {
        let rising = Window(start: Curves.date(2026, 6, 15, 9), end: Curves.date(2026, 6, 15, 11))
        let plan = try XCTUnwrap(PlanFixture.solve(Curves.morningRising(), rising, cover: true))
        XCTAssertGreaterThan(PlanFixture.minutes(plan, .lying(.faceUp)),
                             PlanFixture.minutes(plan, .lying(.faceDown)))
        XCTAssertTrue(plan.showTwoFigures)
    }

    func testHeadAndShouldersIsCreditedWithFaceUpPlusHalfOfFaceDown() throws {
        let curve = try Curves.beachFlatUVI8()
        let plan = try XCTUnwrap(PlanFixture.solve(curve, PlanFixture.threeHours))
        let faceUp = try XCTUnwrap(plan.sides.first { $0.exposure == .lying(.faceUp) }).window
        let faceDown = try XCTUnwrap(plan.sides.first { $0.exposure == .lying(.faceDown) }).window
        let expected = curve.sed(from: faceUp.start, to: faceUp.end)
            + 0.5 * curve.sed(from: faceDown.start, to: faceDown.end)
        XCTAssertEqual(plan.perRegionDose[.headAndShoulders] ?? 0, expected, accuracy: 1e-6)
    }

    func testTheHeadAndShouldersCreditIsKeptInsideItsOwnBudget() throws {
        let request = try PlanFixture.request(Curves.beachFlatUVI8(), PlanFixture.threeHours)
        let plan = try XCTUnwrap(ExposureModel.solve(request, tunables: .current))
        let remaining = try XCTUnwrap(request.targets[.headAndShoulders]).remaining
        XCTAssertLessThanOrEqual(plan.perRegionDose[.headAndShoulders] ?? 0, remaining + 1e-6)
        XCTAssertEqual(plan.limitingRegion, .headAndShoulders)
    }

    func testAHeadAndShouldersLimitShortensTheSidesAndSaysWhatCoverWouldBuy() throws {
        let curve = try Curves.beachFlatUVI8()
        let limited = try XCTUnwrap(PlanFixture.solve(curve, PlanFixture.threeHours))
        let covered = try XCTUnwrap(PlanFixture.solve(curve, PlanFixture.threeHours, cover: true))
        XCTAssertLessThan(PlanFixture.minutes(limited, .lying(.faceUp)),
                          PlanFixture.minutes(covered, .lying(.faceUp)))
        XCTAssertGreaterThan(limited.extraMinutesIfCovered[.lying(.faceUp)] ?? 0, 0)
    }

    func testASpentFrontLeavesTheFaceUpSideAtNoMinutes() throws {
        let plan = try XCTUnwrap(PlanFixture.solve(Curves.beachFlatUVI8(),
                                                   PlanFixture.threeHours,
                                                   spent: [.front: PlanFixture.budget]))
        XCTAssertEqual(PlanFixture.minutes(plan, .lying(.faceUp)), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(PlanFixture.minutes(plan, .lying(.faceDown)), 0)
        XCTAssertEqual(plan.intervals.count, 1)
    }

    func testUpAndAboutIsLimitedByHeadAndShoulders() throws {
        let plan = try XCTUnwrap(PlanFixture.solve(Curves.beachFlatUVI8(),
                                                   PlanFixture.threeHours,
                                                   posture: .upAndAbout))
        XCTAssertEqual(plan.limitingRegion, .headAndShoulders)
    }

    func testCoveringHeadAndShouldersMovesTheLimitToTheTorso() throws {
        let plan = try XCTUnwrap(PlanFixture.solve(Curves.beachFlatUVI8(),
                                                   PlanFixture.threeHours,
                                                   posture: .upAndAbout,
                                                   cover: true))
        XCTAssertNotEqual(plan.limitingRegion, .headAndShoulders)
        XCTAssertEqual(plan.perRegionDose[.headAndShoulders] ?? 0, 0, accuracy: 1e-12)
    }

    func testThereIsNoPlanWhenTheHeadAndShouldersBudgetIsSpent() throws {
        XCTAssertNil(try PlanFixture.solve(Curves.beachFlatUVI8(),
                                           PlanFixture.threeHours,
                                           spent: [.headAndShoulders: PlanFixture.budget]))
    }

    func testThereIsNoPlanWhenBothTorsoSidesAreSpent() throws {
        XCTAssertNil(try PlanFixture.solve(Curves.beachFlatUVI8(),
                                           PlanFixture.threeHours,
                                           spent: [.front: PlanFixture.budget, .back: PlanFixture.budget]))
    }

    func testThereIsNoUpAndAboutPlanWhenEveryExposedRegionIsSpent() throws {
        let spent: [Region: SED] = [.front: PlanFixture.budget,
                                    .back: PlanFixture.budget,
                                    .headAndShoulders: PlanFixture.budget]
        XCTAssertNil(try PlanFixture.solve(Curves.beachFlatUVI8(),
                                           PlanFixture.threeHours,
                                           posture: .upAndAbout,
                                           spent: spent))
    }
}

/// R19: warnings compare today's total, and only when the user means to stay.
final class ExposureWarningTests: XCTestCase {
    /// Two 16.675-minute sides at UVI 8: the front's half of the window is
    /// exactly 2.0 SED.
    private let twoSED = PlanFixture.window(12, minutes: 33.35)

    func testThereAreNoWarningsWhenTheUserOnlyWantsTheBestMinutes() throws {
        let request = try PlanFixture.request(Curves.beachFlatUVI8(), twoSED,
                                              intent: .bestMinutes, spent: [.front: 2.0])
        XCTAssertEqual(ExposureModel.warnings(entered: twoSED, r: request, tunables: .current), [])
    }

    func testStayingUntilTheDayReachesTheThresholdWarnsWithTheDayTotal() throws {
        // 2.0 SED already logged plus 2.0 SED to come is past MED_personal 2.5.
        let request = try PlanFixture.request(Curves.beachFlatUVI8(), twoSED,
                                              intent: .stayWholeWindow, spent: [.front: 2.0])
        let warnings = ExposureModel.warnings(entered: twoSED, r: request, tunables: .current)
        let front = try XCTUnwrap(warnings.first { region(of: $0) == .front })
        guard case .reachesThreshold = front else {
            return XCTFail("expected the strong warning for the front, got \(front)")
        }
        XCTAssertEqual(dayTotal(of: front), 4.0, accuracy: 1e-6)
    }

    func testStayingPastTheTargetButShortOfTheThresholdWarnsPlainly() throws {
        // 0.3 SED on top of 2.0 already logged: past the 2.25 target, short of
        // the 2.5 threshold.
        let brief = PlanFixture.window(12, minutes: 5)
        let request = try PlanFixture.request(Curves.beachFlatUVI8(), brief,
                                              intent: .stayWholeWindow, spent: [.front: 2.0])
        let warnings = ExposureModel.warnings(entered: brief, r: request, tunables: .current)
        let front = try XCTUnwrap(warnings.first { region(of: $0) == .front })
        guard case .pastTarget = front else {
            return XCTFail("expected the plain warning for the front, got \(front)")
        }
        XCTAssertEqual(dayTotal(of: front), 2.0 + 8 * 2.5 / 66.7, accuracy: 1e-6)
    }
}
