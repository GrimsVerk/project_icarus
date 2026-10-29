// The planner's contract is one function with a great many promises, and they
// are asserted here one test each. Splitting them across files would put half
// of this slice's tests in a file the plan does not declare.

@testable import IcarusCore
import XCTest

/// Requests built through the public initialisers, at fixed instants in the
/// fixtures' UTC calendar. The default user is a calibrated type II at
/// multiplier 1.0 and tan state 0: MED_personal 2.5 SED, standard target 2.25.
private enum Plans {
    static let budget: SED = 2.25
    static let typeII = Profile(skinType: .ii, ceiling: .standard)

    /// A flat UVI 8 forecast fetched an hour before the fixtures' noon.
    static func beach() throws -> ForecastCurve {
        try PlannerFixture.refetched(Curves.beachFlatUVI8(), at: PlannerFixture.at(11))
    }

    static func request(
        curve: ForecastCurve?,
        window: Window,
        now: Date = PlannerFixture.at(11, 50),
        posture: Posture = .upAndAbout,
        cover: Bool = false,
        intent: Intent = .bestMinutes,
        profile: Profile = typeII,
        state: DerivedState = PlannerFixture.state(),
        deviceLocation: Coordinate? = Curves.location,
        failure: ForecastFailureKind? = nil
    ) -> PlanRequest {
        PlanRequest(
            curve: curve, forecastFailure: failure, deviceLocation: deviceLocation, now: now,
            window: window, posture: posture, firstSide: .faceUp, coverHeadAndShoulders: cover,
            intent: intent, profile: profile, state: state, goal: TanningGoal()
        )
    }

    /// The default fixture: a two-hour beach window from the fixtures' noon.
    static func beachPlan(
        minutes: Double = 120,
        posture: Posture = .upAndAbout,
        cover: Bool = false,
        intent: Intent = .bestMinutes,
        profile: Profile = typeII,
        state: DerivedState = PlannerFixture.state()
    ) throws -> DoseResult {
        try Planner.plan(
            request(
                curve: beach(), window: PlannerFixture.window(12, minutes: minutes),
                posture: posture, cover: cover, intent: intent, profile: profile, state: state
            ),
            tunables: .current
        )
    }
}

/// Records every constant an outcome read, so a figure's provenance can be
/// checked against what the engine actually looked at (R30).
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = Set<String>()

    func add(_ key: String) {
        lock.lock()
        seen.insert(key)
        lock.unlock()
    }

    var keys: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }
}

// MARK: - R17: every edge case is a typed outcome

/// R17: the clock is an input, and each edge case answers with something
/// specific rather than a nil, a crash or an invented number.
final class PlannerOutcomeTests: XCTestCase {
    func testAWindowThatHasAlreadyEndedIsTheWindowPassedOutcome() throws {
        let passed = Window(start: PlannerFixture.at(9), end: PlannerFixture.at(10))
        let result = try Planner.plan(
            Plans.request(curve: Plans.beach(), window: passed, now: PlannerFixture.at(12)),
            tunables: .current
        )
        XCTAssertEqual(result.outcome, .windowPassed)
        XCTAssertTrue(result.copyKeys.contains(.windowPassed))
    }

    func testAWindowThatHasPartlyPassedIsSolvedFromNow() throws {
        let result = try Planner.plan(
            Plans.request(
                curve: Plans.beach(), window: PlannerFixture.window(12, minutes: 60),
                now: PlannerFixture.at(12, 30)
            ),
            tunables: .current
        )
        let plan = try XCTUnwrap(exposurePlan(result))
        XCTAssertGreaterThanOrEqual(plan.span.start, PlannerFixture.at(12, 30))
    }

    func testAForecastWithNoLocationSaysThatIsWhyItIsMissing() {
        let result = Planner.plan(
            Plans.request(
                curve: nil, window: PlannerFixture.window(12, minutes: 60),
                deviceLocation: nil, failure: .noLocation
            ),
            tunables: .current
        )
        XCTAssertEqual(result.outcome, .missingForecast(.noLocation))
        XCTAssertTrue(result.copyKeys.contains(.missingForecastNoLocation))
    }

    func testAForecastTheProviderNeverReturnedCarriesItsOwnKind() {
        let result = Planner.plan(
            Plans.request(curve: nil, window: PlannerFixture.window(12, minutes: 60), failure: .provider),
            tunables: .current
        )
        XCTAssertEqual(result.outcome, .missingForecast(.provider))
        XCTAssertTrue(result.copyKeys.contains(.missingForecast))
    }

    /// Viability is judged against what is left, not against the whole target:
    /// 0.3 SED of budget and a 0.5 SED window is a session, not a refusal.
    func testASecondSessionWithLittleBudgetLeftIsStillAPlan() throws {
        let spent = Plans.budget - 0.3
        let result = try Plans.beachPlan(
            minutes: 4.1667, posture: .lyingTurning, cover: true,
            state: PlannerFixture.state(spent: [.front: spent, .back: spent])
        )
        XCTAssertEqual(OutcomeKind(result.outcome), .plan)
    }

    /// A window worth going out for that cannot reach the budget is planned in
    /// full — never as zero minutes.
    func testAViableWindowThatCannotReachTheBudgetFillsTheWholeWindow() throws {
        let window = PlannerFixture.window(12, minutes: 50)
        let curve = try PlannerFixture.refetched(Curves.shoulderHourUVI2(), at: PlannerFixture.at(11))
        let result = Planner.plan(Plans.request(curve: curve, window: window), tunables: .current)
        let plan = try XCTUnwrap(exposurePlan(result))
        XCTAssertEqual(headline(result), .wholeWindowFits)
        XCTAssertEqual(plan.span.start, window.start)
        XCTAssertEqual(plan.span.end, window.end)
        XCTAssertEqual(plan.totalMinutes, 50, accuracy: 1e-6)
    }

    func testATooWeakWindowCarriesTheShortfallFromTheMelanogenicDose() throws {
        let window = PlannerFixture.window(12, minutes: 10)
        let curve = try PlannerFixture.refetched(Curves.shoulderHourUVI2(), at: PlannerFixture.at(11))
        let result = Planner.plan(Plans.request(curve: curve, window: window), tunables: .current)
        guard case let .tooWeak(shortfall, _) = result.outcome else {
            return XCTFail("expected the too-weak outcome, got \(result.outcome)")
        }
        let melanogenic = try XCTUnwrap(result.targets[.headAndShoulders]).melanogenic
        XCTAssertEqual(shortfall, melanogenic - curve.sed(from: window.start, to: window.end), accuracy: 1e-6)
        XCTAssertTrue(result.copyKeys.contains(.tooWeak))
    }

    func testATooWeakWindowNamesTheNextViableWindowInsideTheHorizon() throws {
        let curve = try PlannerFixture.refetched(Curves.shoulderHourUVI2(), at: PlannerFixture.at(11))
        let result = Planner.plan(
            Plans.request(curve: curve, window: PlannerFixture.window(12, minutes: 10)),
            tunables: .current
        )
        guard case let .tooWeak(_, next) = result.outcome else {
            return XCTFail("expected the too-weak outcome, got \(result.outcome)")
        }
        let viable = try XCTUnwrap(next, "a flat UVI 2 day has a viable window later on")
        XCTAssertGreaterThanOrEqual(viable.start, PlannerFixture.at(11, 50))
        XCTAssertLessThanOrEqual(viable.start, curve.horizonEnd)
    }

    /// Nothing in the horizon reaches viability, so the answer names the days
    /// and the peak — and never claims a season.
    func testAHorizonWithNothingViableNamesTheDaysAndThePeakUVI() throws {
        let curve = try Curves.winterLow()
        let result = Planner.plan(
            Plans.request(curve: curve, window: PlannerFixture.window(12, minutes: 120)),
            tunables: .current
        )
        guard case let .noViableWindow(days, peak) = result.outcome else {
            return XCTFail("expected no viable window, got \(result.outcome)")
        }
        XCTAssertEqual(days, Tunables.current.forecastHorizonDays)
        XCTAssertEqual(peak, 0.1, accuracy: 1e-9)
        XCTAssertTrue(result.copyKeys.contains(.noViableWindow))
    }

    func testASpentRegionIsTheBudgetSpentOutcome() throws {
        let result = try Plans.beachPlan(state: PlannerFixture.state(spent: [.headAndShoulders: Plans.budget]))
        XCTAssertEqual(result.outcome, .budgetSpent(.headAndShoulders))
        XCTAssertTrue(result.copyKeys.contains(.budgetSpent))
    }
}

// MARK: - R15: the two answers and which one leads

/// R15: overshoot and the sunscreen are judged on the region the whole window
/// pushes hardest, and the order of the two answers follows the user's intent.
final class PlannerSunscreenTests: XCTestCase {
    func testTheAttenuationRegionIsTheOneTheWholeWindowPushesHardest() throws {
        let result = try Plans.beachPlan(
            minutes: 180, state: PlannerFixture.state(spent: [.front: 2.0])
        )
        XCTAssertEqual(result.attenuationRegion, .front)
    }

    /// Lying at the standard scale with equal budgets on a flat curve, head and
    /// shoulders covered: the torso is what the sunscreen is solved for, and
    /// 10.79 SED against 2.25 needs SPF 30 applied normally.
    func testTheLyingFixtureSolvesTheSunscreenForATorsoSide() throws {
        let result = try Plans.beachPlan(minutes: 180, posture: .lyingTurning, cover: true)
        let region = try XCTUnwrap(result.attenuationRegion)
        XCTAssertTrue(region == .front || region == .back, "expected a torso side, got \(region)")
        let advice = try XCTUnwrap(sunscreenAdvice(result))
        XCTAssertEqual(advice.prescribed, SunscreenChoice(spfLabel: 30, application: .normal))
        XCTAssertEqual(advice.prescribed.spfLabel, lowestSufficientLabel(result))
    }

    /// Screen review F2: which side goes first is the flip timer's question
    /// (R11). On the result it had nothing to answer it with.
    func testALyingResultLeavesWhichSideFirstToTheTimer() throws {
        let result = try Plans.beachPlan(minutes: 180, posture: .lyingTurning)
        XCTAssertFalse(result.copyKeys.contains(.whichSideFirst))
    }

    func testThePrescribedPairKeepsEveryExposedRegionInsideItsBudget() throws {
        let result = try Plans.beachPlan(minutes: 60, state: PlannerFixture.state(spent: [.front: 1.0]))
        try expectTheProtectionCoversEveryRegion(result)
    }

    func testStayingTheWholeWindowMakesTheSunscreenTheHeadline() throws {
        let result = try Plans.beachPlan(
            minutes: 60, intent: .stayWholeWindow, state: PlannerFixture.state(spent: [.front: 1.0])
        )
        XCTAssertEqual(headline(result), .sunscreenForWholeWindow)
        XCTAssertTrue(result.copyKeys.contains(.planStayWearThis))
    }

    func testWantingTheBestMinutesKeepsTheBareSubWindowAsTheHeadline() throws {
        let result = try Plans.beachPlan(minutes: 60, state: PlannerFixture.state(spent: [.front: 1.0]))
        XCTAssertEqual(headline(result), .bareSubWindow)
        XCTAssertTrue(result.copyKeys.contains(.planBareSubWindow))
    }

    /// No realistic product covers two hours against 0.3375 SED, so the
    /// headline goes back to the bare sub-window rather than to an answer the
    /// user cannot act on.
    func testNothingRealisticNeverBecomesTheStayHeadline() throws {
        let spent = 0.85 * Plans.budget
        let result = try Plans.beachPlan(
            minutes: 120, posture: .lyingTurning, cover: true, intent: .stayWholeWindow,
            state: PlannerFixture.state(spent: [.front: spent, .back: spent])
        )
        XCTAssertEqual(headline(result), .bareSubWindow)
        XCTAssertTrue(result.copyKeys.contains(.nothingRealistic))
    }

    func testAWindowThatFitsWholeCarriesTheWholeWindowFitsKey() throws {
        let curve = try PlannerFixture.refetched(Curves.shoulderHourUVI2(), at: PlannerFixture.at(11))
        let result = Planner.plan(
            Plans.request(curve: curve, window: PlannerFixture.window(12, minutes: 50)),
            tunables: .current
        )
        XCTAssertEqual(headline(result), .wholeWindowFits)
        XCTAssertTrue(result.copyKeys.contains(.planStayWholeWindowFits))
    }

    func testAWindowThatNeedsNoSunscreenStillSurfacesTheOption() throws {
        let result = try Plans.beachPlan(minutes: 15)
        guard case let .plan(_, sunscreen, _) = result.outcome else {
            return XCTFail("expected a plan, got \(result.outcome)")
        }
        XCTAssertEqual(sunscreen, .notNeeded(uvaHeavy: false))
        XCTAssertTrue(result.copyKeys.contains(.sunscreenNotNeeded))
    }
}

// MARK: - R3: how old, and how far away

/// R3: staleness is age and place together, it degrades the answer and never
/// refuses it.
final class PlannerStalenessTests: XCTestCase {
    private func level(fetchedAt: Date, now: Date, device: Coordinate?) throws -> StaleLevel {
        let curve = try PlannerFixture.refetched(Curves.beachFlatUVI8(), at: fetchedAt)
        return Planner.staleLevel(curve: curve, now: now, deviceLocation: device, tunables: .current)
    }

    func testAForecastFetchedAnHourAgoAtThisPlaceIsFresh() throws {
        let stale = try level(fetchedAt: PlannerFixture.at(11), now: PlannerFixture.at(12), device: Curves.location)
        XCTAssertEqual(stale, .fresh)
    }

    func testAThreeHourOldForecastIsAHeadsUpThatNamesItsAge() throws {
        let stale = try level(fetchedAt: PlannerFixture.at(9), now: PlannerFixture.at(12), device: Curves.location)
        guard case let .headsUp(hours) = stale else {
            return XCTFail("expected a heads-up, got \(stale)")
        }
        XCTAssertEqual(hours, 3, accuracy: 1e-6)
    }

    func testASixHourOldForecastIsAWarning() throws {
        let stale = try level(fetchedAt: PlannerFixture.at(6), now: PlannerFixture.at(12), device: Curves.location)
        guard case let .warn(hours, far) = stale else {
            return XCTFail("expected a warning, got \(stale)")
        }
        XCTAssertEqual(hours, 6, accuracy: 1e-6)
        XCTAssertFalse(far)
    }

    func testACacheThirtyKilometresAwayIsAWarningAtAnyAge() throws {
        let stale = try level(
            fetchedAt: PlannerFixture.at(11), now: PlannerFixture.at(12),
            device: Coordinate(latitude: 60.17, longitude: 10.75)
        )
        guard case let .warn(_, far) = stale else {
            return XCTFail("expected a warning, got \(stale)")
        }
        XCTAssertTrue(far)
    }

    func testAnUnknownLocationIsAWarningAtAnyAge() throws {
        let stale = try level(fetchedAt: PlannerFixture.at(11), now: PlannerFixture.at(12), device: nil)
        guard case .warn = stale else {
            return XCTFail("expected a warning, got \(stale)")
        }
    }

    func testAStaleForecastTrimsTheTargetAndWidensTheRange() throws {
        let window = PlannerFixture.window(12, minutes: 60)
        let fresh = try Planner.plan(Plans.request(curve: Plans.beach(), window: window), tunables: .current)
        let old = try PlannerFixture.refetched(Curves.beachFlatUVI8(), at: PlannerFixture.at(4))
        let stale = Planner.plan(Plans.request(curve: old, window: window), tunables: .current)
        let before = try XCTUnwrap(fresh.targets[.front])
        let after = try XCTUnwrap(stale.targets[.front])
        XCTAssertEqual(after.target, before.target * (1 - Tunables.current.staleReduction), accuracy: 1e-9)
        XCTAssertGreaterThan(width(after.range), width(before.range))
        XCTAssertTrue(stale.copyKeys.contains(.staleWarn))
    }

    private func width(_ range: ClosedRange<SED>) -> Double {
        range.upperBound - range.lowerBound
    }
}

// MARK: - R7, R13, R14, R43: the notices

/// R7, R13, R14, R43: which lines the result carries, and when.
final class PlannerNoticeTests: XCTestCase {
    func testFairSkinAlwaysCarriesTheThinMarginLine() throws {
        let result = try Plans.beachPlan(minutes: 60)
        XCTAssertTrue(result.notices.thinMargin)
        XCTAssertTrue(result.copyKeys.contains(.thinMargin))
    }

    func testTypeThreeNeverCarriesTheThinMarginLine() throws {
        let result = try Plans.beachPlan(
            minutes: 60, profile: Profile(skinType: .iii, ceiling: .standard),
            state: PlannerFixture.state(skinType: .iii)
        )
        XCTAssertFalse(result.notices.thinMargin)
        XCTAssertFalse(result.copyKeys.contains(.thinMargin))
    }

    func testFairSkinBeforeThreeReportsCarriesThePreCalibrationLine() throws {
        let result = try Plans.beachPlan(
            minutes: 60, state: PlannerFixture.state(reports: 0, redness: 0, bound: false)
        )
        XCTAssertTrue(result.notices.fairSkinPreCalibration)
        XCTAssertTrue(result.copyKeys.contains(.fairSkinPreCalibration))
    }

    func testFairSkinAfterThreeReportsDropsThePreCalibrationLine() throws {
        let result = try Plans.beachPlan(minutes: 60, state: PlannerFixture.state(reports: 3))
        XCTAssertFalse(result.notices.fairSkinPreCalibration)
        XCTAssertFalse(result.copyKeys.contains(.fairSkinPreCalibration))
    }

    func testTypeThreeNeverCarriesThePreCalibrationLine() throws {
        let result = try Plans.beachPlan(
            minutes: 60, profile: Profile(skinType: .iii, ceiling: .standard),
            state: PlannerFixture.state(skinType: .iii, reports: 0, redness: 0, bound: false)
        )
        XCTAssertFalse(result.notices.fairSkinPreCalibration)
    }

    func testTheNumberSitsAtTheConservativeScaleUntilTheAppHasLearnedTheSkin() throws {
        let result = try Plans.beachPlan(
            minutes: 60, state: PlannerFixture.state(reports: 0, redness: 0, bound: false)
        )
        XCTAssertTrue(result.notices.conservativeForced)
        XCTAssertEqual(try XCTUnwrap(result.targets[.front]).scaleUsed, 0.75, accuracy: 1e-9)
        XCTAssertTrue(result.copyKeys.contains(.conservativeUntilCalibrated))
    }

    func testTheAggressiveScaleIsRefusedUntilARednessReportUnlocksIt() throws {
        let result = try Plans.beachPlan(
            minutes: 60, profile: Profile(skinType: .ii, ceiling: .aggressive),
            state: PlannerFixture.state(redness: 0, bound: false)
        )
        XCTAssertTrue(result.notices.aggressiveRefused)
        XCTAssertEqual(try XCTUnwrap(result.targets[.front]).scaleUsed, 0.90, accuracy: 1e-9)
        XCTAssertTrue(result.copyKeys.contains(.aggressiveLocked))
    }

    func testAFactorBelowTheNoticeLineSaysNothingAboutEscalation() throws {
        let result = try Plans.beachPlan(
            minutes: 60, state: PlannerFixture.state(tanState: 0.4, lastExposure: PlannerFixture.at(0))
        )
        XCTAssertNil(result.notices.escalation)
        XCTAssertFalse(result.copyKeys.contains(.escalationRisen))
    }

    func testAFactorPastTheNoticeLineSaysSoAndShowsTheCycleDose() throws {
        let result = try Plans.beachPlan(
            minutes: 60,
            state: PlannerFixture.state(
                tanState: 0.7, lastExposure: PlannerFixture.at(0), doseInCycle: 30,
                cycleStart: DayKey(Curves.date(2026, 5, 11), timeZone: Curves.zone)
            )
        )
        XCTAssertNotNil(result.notices.escalation)
        XCTAssertTrue(result.copyKeys.contains(.escalationRisen))
        XCTAssertEqual(result.cycleDose[.front] ?? 0, 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(result.figures.first { $0.key == .cycleDose }).value, 30, accuracy: 1e-9)
    }

    func testAWindowFarFromSolarNoonIsFlaggedUVAHeavy() throws {
        let curve = try PlannerFixture.refetched(Curves.eveningFalling(), at: PlannerFixture.at(16))
        let result = Planner.plan(
            Plans.request(
                curve: curve, window: PlannerFixture.window(17, minutes: 120),
                now: PlannerFixture.at(16, 50), posture: .lyingTurning,
                profile: Profile(skinType: .iii, ceiling: .standard),
                state: PlannerFixture.state(skinType: .iii)
            ),
            tunables: .current
        )
        XCTAssertTrue(result.notices.uvaHeavy)
        XCTAssertTrue(result.copyKeys.contains(.uvaHeavy))
    }
}

// MARK: - R14: the plateau and the maintenance dose

/// R14: repeated "no lasting colour" near saturation drops the target to the
/// maintenance dose, before anything else is solved.
final class PlannerPlateauTests: XCTestCase {
    private func plateaued(bound: Bool = true, tanState: Double = 0.8, minutes: Double = 60) throws -> DoseResult {
        try Plans.beachPlan(
            minutes: minutes,
            state: PlannerFixture.state(
                bound: bound, tanState: tanState, lastExposure: PlannerFixture.at(0), noColour: 3
            )
        )
    }

    private func steady(bound: Bool = true, tanState: Double = 0.8, minutes: Double = 60) throws -> DoseResult {
        try Plans.beachPlan(
            minutes: minutes,
            state: PlannerFixture.state(bound: bound, tanState: tanState, lastExposure: PlannerFixture.at(0))
        )
    }

    func testThePlateauScalesEveryTargetBeforeTheSolve() throws {
        let maintained = try plateaued()
        let full = try steady()
        for region in Region.allCases {
            let dropped = try XCTUnwrap(maintained.targets[region]).target
            let whole = try XCTUnwrap(full.targets[region]).target
            XCTAssertEqual(dropped, whole * Tunables.current.maintenanceFraction, accuracy: 1e-9)
        }
        XCTAssertTrue(maintained.notices.maintenanceApplied)
        XCTAssertTrue(maintained.copyKeys.contains(.maintenance))
    }

    /// 15.71 SED over 131 minutes needs SPF 15 against the full 4.5 SED budget
    /// and SPF 30 against the maintained 3.15: the prescription proves which
    /// budget the sunscreen was solved against.
    func testTheSunscreenIsSolvedAgainstTheMaintainedBudget() throws {
        let advice = try XCTUnwrap(sunscreenAdvice(plateaued(minutes: 131)))
        XCTAssertEqual(advice.prescribed, SunscreenChoice(spfLabel: 30, application: .normal))
    }

    func testThePlateauSurvivesAWeekendOfDecay() throws {
        let result = try plateaued(tanState: 0.71)
        XCTAssertNotNil(result.notices.plateau)
        XCTAssertTrue(result.notices.maintenanceApplied)
    }

    func testARednessBoundInTheCycleMakesItTheCeilingMessage() throws {
        let result = try plateaued(bound: true)
        XCTAssertEqual(result.notices.plateau, .ceiling)
        XCTAssertTrue(result.copyKeys.contains(.ceilingReached))
        XCTAssertFalse(result.copyKeys.contains(.underDosed))
    }

    func testWithoutARednessBoundItIsTheUnderDosedMessage() throws {
        let result = try plateaued(bound: false)
        XCTAssertEqual(result.notices.plateau, .underDosed)
        XCTAssertTrue(result.copyKeys.contains(.underDosed))
        XCTAssertFalse(result.copyKeys.contains(.ceilingReached))
    }

    func testNoPlateauIsReportedBeforeTheCountIsReached() throws {
        let result = try steady()
        XCTAssertNil(result.notices.plateau)
        XCTAssertFalse(result.notices.maintenanceApplied)
    }
}

// MARK: - R7: the range, in minutes on the recommendation

/// R7, screen review F3: the range is the uncertainty in the threshold shown
/// in minutes beside the number, never a dose per region; its upper edge stops
/// at the minutes to `MED_personal` and then says so.
final class PlannerRangeTests: XCTestCase {
    private static let rangeKeys: [FigureKey] = [.rangeLower, .rangeUpper, .rangeUpperClipped]

    private struct Edges {
        let lower: Figure
        let upper: Figure
        let headline: Figure
    }

    private func edges(_ result: DoseResult) throws -> Edges {
        let range = result.figures.filter { Self.rangeKeys.contains($0.key) }
        XCTAssertEqual(range.count, 2, "one lower and one upper edge, not one per region")
        return try Edges(
            lower: XCTUnwrap(range.first { $0.key == .rangeLower }),
            upper: XCTUnwrap(range.first { $0.key != .rangeLower }),
            headline: XCTUnwrap(result.figures.first { $0.key == .headlineMinutes })
        )
    }

    func testTheRangeIsMinutesAroundTheNumber() throws {
        let found = try edges(Plans.beachPlan(minutes: 120))
        for edge in [found.lower, found.upper] {
            XCTAssertEqual(edge.unit, .minutes, "\(edge.key)")
            XCTAssertNil(edge.region, "the range belongs to the recommendation, not to a region")
        }
        XCTAssertLessThan(found.lower.value, found.headline.value)
        XCTAssertGreaterThan(found.upper.value, found.headline.value)
    }

    /// A calibrated type II at the standard scale: the range's upper edge in
    /// SED passes the burn line, so in minutes it is the session the
    /// aggressive scale (whose number is the burn line) would plan.
    func testAClippedUpperEdgeIsTheMinutesToTheRednessLine() throws {
        let standard = try edges(Plans.beachPlan(minutes: 120))
        let atTheLine = try edges(Plans.beachPlan(minutes: 120, profile: Profile(skinType: .ii, ceiling: .aggressive)))
        XCTAssertEqual(standard.upper.key, .rangeUpperClipped)
        XCTAssertEqual(standard.upper.value, atTheLine.headline.value, accuracy: 0.05)
        XCTAssertEqual(atTheLine.upper.value, atTheLine.headline.value, accuracy: 1e-9, "nothing past the line")
    }

    func testAnUpperEdgeBelowTheRednessLineIsNotMarkedClipped() throws {
        let uncalibrated = PlannerFixture.state(reports: 0, redness: 0, bound: false)
        let result = try Plans.beachPlan(minutes: 120, state: uncalibrated)
        XCTAssertEqual(try edges(result).upper.key, .rangeUpper)
    }

    func testAnOutcomeWithoutAPlanShowsNoRange() throws {
        let passed = Window(start: PlannerFixture.at(9), end: PlannerFixture.at(10))
        let result = try Planner.plan(
            Plans.request(curve: Plans.beach(), window: passed, now: PlannerFixture.at(12)),
            tunables: .current
        )
        XCTAssertFalse(result.figures.contains { Self.rangeKeys.contains($0.key) })
    }
}

// MARK: - R30: per-figure provenance

/// R30: the estimate label belongs to the individual figure, and it is the
/// engine that decides, from the constants the figure actually read.
final class PlannerProvenanceTests: XCTestCase {
    func testAFigureIsAnEstimateExactlyWhenItReadAnAssumption() throws {
        let result = try Plans.beachPlan(minutes: 60)
        XCTAssertFalse(result.figures.isEmpty)
        for figure in result.figures {
            let assumed = figure.reads.intersection(Tunables.assumptionKeys)
            XCTAssertEqual(figure.isEstimate, !assumed.isEmpty, "\(figure.key)")
            XCTAssertEqual(Set(figure.assumptionKeys), assumed, "\(figure.key)")
        }
    }

    func testTheRecordedReadsAreExactlyTheUnionOfTheFiguresReads() throws {
        let recorder = Recorder()
        let request = try Plans.request(curve: Plans.beach(), window: PlannerFixture.window(12, minutes: 60))
        let result = Planner.plan(request, tunables: Tunables.current.recording { recorder.add($0) })
        XCTAssertEqual(recorder.keys, Set(result.figures.flatMap(\.reads)))
    }

    func testEveryFigureTheResultShowsCarriesTheConstantsBehindIt() throws {
        let result = try Plans.beachPlan(minutes: 60)
        let headline = try XCTUnwrap(result.figures.first { $0.key == .headlineMinutes })
        XCTAssertEqual(headline.unit, .minutes)
        XCTAssertTrue(headline.reads.contains("uviMinutesPerSED"))
    }
}
