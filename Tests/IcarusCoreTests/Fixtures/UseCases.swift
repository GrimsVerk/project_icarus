// The eight §4 use cases are one fixture file by the plan's file list: each is
// a whole request with its expected answer, and splitting them would put half
// of S18 in a file no slice declares.
// swiftlint:disable file_length

@testable import IcarusCore
import XCTest

// MARK: - Shared builders

/// The pieces every planner fixture is made of: fixed instants in the fixtures'
/// UTC calendar, a replayed state built by hand, and a curve re-stamped with the
/// fetch time a use case needs. Nothing here reads the wall clock.
enum PlannerFixture {
    /// The day every fixture happens on.
    static var day: DayKey {
        DayKey(Curves.date(2026, 6, 15), timeZone: Curves.zone)
    }

    static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        Curves.date(2026, 6, 15, hour, minute)
    }

    static func window(_ hour: Int, _ minute: Int = 0, minutes: Double) -> Window {
        let start = at(hour, minute)
        return Window(start: start, end: start.addingTimeInterval(minutes * 60))
    }

    /// The same forecast, stamped with a different fetch time — what separates a
    /// fresh forecast from a stale one (R3). Solar noon is carried across
    /// explicitly so the rebuilt curve answers exactly as the original did.
    static func refetched(_ curve: ForecastCurve, at fetchedAt: Date) throws -> ForecastCurve {
        var noons = [DayKey: Date]()
        var day = curve.day(curve.hourly[0].time)
        let last = curve.day(curve.horizonEnd)
        while day <= last {
            noons[day] = curve.solarNoon(on: day)
            day = day.adding(days: 1)
        }
        return try ForecastCurve(
            location: curve.location, timeZone: curve.timeZone,
            fetchedAt: fetchedAt, hourly: curve.hourly, solarNoon: noons
        )
    }

    /// A replayed state, written out rather than replayed: the tests for the
    /// replay itself live in S3, and a planner fixture only needs the state a
    /// history would have produced.
    static func state(
        skinType: SkinType = .ii,
        reports: Int = 5,
        redness: Int = 1,
        bound: Bool = true,
        tanState: Double = 0,
        tanStateAtLastSession: Double? = nil,
        lastExposure: Date? = nil,
        spent: [Region: SED] = [:],
        noColour: Int = 0,
        doseInCycle: SED = 0,
        cycleStart: DayKey? = nil
    ) -> DerivedState {
        var derived = DerivedState.initial(tunables: .current)
        derived.reportCount = reports
        derived.totalReports = reports
        derived.rednessReportCount = redness
        derived.today = day
        derived.cycleStarts = cycleStart.map { [$0.start()] } ?? []
        let previous = tanStateAtLastSession ?? tanState
        let gain = Tunables.current.adaptationGain(skinType.band)
        for region in Region.allCases {
            derived.regions[region] = RegionState(
                tanState: tanState, lastExposure: lastExposure, cycleStart: cycleStart,
                rednessBoundInCycle: bound, noColourNearCeiling: noColour,
                doseToday: spent[region] ?? 0, doseInCycle: doseInCycle,
                factorAtLastSession: 1 + gain * previous, tanStateAtLastSession: previous
            )
        }
        return derived
    }
}

// MARK: - The fixture

/// Which outcome came back, without its payload — what S18 compares.
enum OutcomeKind: String {
    case plan, tooWeak, noViableWindow, windowPassed, budgetSpent, missingForecast

    init(_ outcome: Outcome) {
        switch outcome {
        case .plan: self = .plan
        case .tooWeak: self = .tooWeak
        case .noViableWindow: self = .noViableWindow
        case .windowPassed: self = .windowPassed
        case .budgetSpent: self = .budgetSpent
        case .missingForecast: self = .missingForecast
        }
    }
}

/// One §4 use case as the engine sees it: everything `Planner.plan` is given,
/// and everything the design says must come back (S18).
struct UseCaseFixture {
    /// What the design says the result must carry. A number the use case does
    /// not state is left nil rather than invented.
    struct Expectation {
        let outcome: OutcomeKind
        let headline: Headline?
        let headlineMinutes: Double?
        let doses: [Region: SED]
        let keys: [CopyKey]
        let absentKeys: [CopyKey]
        let extra: ((DoseResult) throws -> Void)?

        init(
            outcome: OutcomeKind,
            headline: Headline? = nil,
            headlineMinutes: Double? = nil,
            doses: [Region: SED] = [:],
            keys: [CopyKey] = [],
            absentKeys: [CopyKey] = [],
            extra: ((DoseResult) throws -> Void)? = nil
        ) {
            self.outcome = outcome
            self.headline = headline
            self.headlineMinutes = headlineMinutes
            self.doses = doses
            self.keys = keys
            self.absentKeys = absentKeys
            self.extra = extra
        }
    }

    let name: String
    let curve: ForecastCurve?
    let forecastFailure: ForecastFailureKind?
    let deviceLocation: Coordinate?
    let now: Date
    let window: Window
    let posture: Posture
    let firstSide: Side
    let cover: Bool
    let intent: Intent
    let profile: Profile
    let state: DerivedState
    let expected: Expectation

    var request: PlanRequest {
        PlanRequest(
            curve: curve, forecastFailure: forecastFailure, deviceLocation: deviceLocation, now: now,
            window: window, posture: posture, firstSide: firstSide, coverHeadAndShoulders: cover,
            intent: intent, profile: profile, state: state, goal: TanningGoal()
        )
    }
}

// MARK: - The registry

/// The §4 use cases, one builder each. M1 covers 1–6, 8 and 9; use case 7 is
/// M5's and appends itself with `register(_:)` from its own file, so adding it
/// never edits this one.
enum UseCases {
    nonisolated(unsafe) static var builders: [() throws -> UseCaseFixture] = [
        lunchHourSlot, eveningSunbather, longWeekend, secondSessionOfTheDay,
        returnAfterABreak, plateau, wantingToPush, offlineAtTheBeach,
    ]

    static func register(_ builder: @escaping () throws -> UseCaseFixture) {
        builders.append(builder)
    }

    static func all() throws -> [UseCaseFixture] {
        try builders.map { try $0() }
    }
}

// MARK: - Use cases 1 to 4

extension UseCases {
    /// 1 — the lunch-hour slot. An uncalibrated type II, 12:30 to 13:15 entered
    /// at 12:20, up and about at UVI 7: 1.875 SED at the conservative scale is
    /// about 18 minutes, head and shoulders take it in full and the torso about
    /// half, and the whole 45 minutes would overshoot.
    static func lunchHourSlot() throws -> UseCaseFixture {
        try UseCaseFixture(
            name: "1 — the lunch-hour slot",
            curve: PlannerFixture.refetched(Curves.steadyUVI(7), at: PlannerFixture.at(12)),
            forecastFailure: nil, deviceLocation: Curves.location,
            now: PlannerFixture.at(12, 20), window: PlannerFixture.window(12, 30, minutes: 45),
            posture: .upAndAbout, firstSide: .faceUp, cover: false, intent: .bestMinutes,
            profile: Profile(skinType: .ii, ceiling: .standard),
            state: PlannerFixture.state(reports: 0, redness: 0, bound: false),
            expected: .init(
                outcome: .plan, headline: .bareSubWindow, headlineMinutes: 17.86,
                doses: [.headAndShoulders: 1.875, .front: 0.9375, .back: 0.9375],
                keys: [.conservativeUntilCalibrated, .fairSkinPreCalibration, .thinMargin, .coverToRunLonger],
                absentKeys: [.warnPastTarget, .warnReachesThreshold],
                extra: { result in
                    XCTAssertNotNil(sunscreenAdvice(result), "the whole slot overshoots, so it must be priced")
                }
            )
        )
    }

    /// 2 — the evening sunbather. A calibrated type III lying by a pool from
    /// 17:00 to 19:00 on a falling curve, six hours from solar noon.
    static func eveningSunbather() throws -> UseCaseFixture {
        try UseCaseFixture(
            name: "2 — the evening sunbather",
            curve: PlannerFixture.refetched(Curves.eveningFalling(), at: PlannerFixture.at(16)),
            forecastFailure: nil, deviceLocation: Curves.location,
            now: PlannerFixture.at(16, 50), window: PlannerFixture.window(17, minutes: 120),
            posture: .lyingTurning, firstSide: .faceUp, cover: false, intent: .bestMinutes,
            profile: Profile(skinType: .iii, ceiling: .standard),
            state: PlannerFixture.state(skinType: .iii),
            expected: .init(
                outcome: .plan, headline: .bareSubWindow,
                keys: [.uvaHeavy], absentKeys: [.thinMargin],
                extra: { result in
                    let plan = try XCTUnwrap(exposurePlan(result))
                    XCTAssertTrue(result.notices.uvaHeavy)
                    XCTAssertEqual(plan.intervals.count, 2)
                    XCTAssertEqual(plan.intervals.last?.window.start, plan.intervals.first?.window.end)
                    XCTAssertGreaterThan(minutes(plan, .lying(.faceDown)), minutes(plan, .lying(.faceUp)))
                    XCTAssertGreaterThan(plan.extraMinutesIfCovered[.lying(.faceUp)] ?? 0, 0)
                }
            )
        )
    }

    /// 3 — the long weekend. A calibrated, part-tanned type II lying on a beach
    /// at UVI 8 for three hours and marking that they will stay: the headline is
    /// what to wear, with the UVA multiple and the reapplication times.
    static func longWeekend() throws -> UseCaseFixture {
        try UseCaseFixture(
            name: "3 — the long weekend",
            curve: PlannerFixture.refetched(Curves.beachFlatUVI8(), at: PlannerFixture.at(11)),
            forecastFailure: nil, deviceLocation: Curves.location,
            now: PlannerFixture.at(11, 50), window: PlannerFixture.window(12, minutes: 180),
            posture: .lyingTurning, firstSide: .faceUp, cover: false, intent: .stayWholeWindow,
            profile: Profile(skinType: .ii, ceiling: .standard),
            state: PlannerFixture.state(tanState: 0.45, lastExposure: PlannerFixture.at(12).addingTimeInterval(-86400)),
            expected: .init(
                outcome: .plan, headline: .sunscreenForWholeWindow, headlineMinutes: 180,
                keys: [.uvaMultiple, .reapply],
                extra: { result in
                    let advice = try XCTUnwrap(sunscreenAdvice(result))
                    XCTAssertEqual(advice.prescribed.application, .normal)
                    XCTAssertEqual(advice.prescribed.spfLabel, try XCTUnwrap(lowestSufficientLabel(result)))
                    XCTAssertGreaterThan(advice.uvaMultiple, 1)
                    XCTAssertFalse(advice.reapplyAt.isEmpty)
                    try expectTheProtectionCoversEveryRegion(result)
                }
            )
        )
    }

    /// 4 — two sessions in a day. The front and back are at 15% of their budget,
    /// the head and shoulders are covered, and the user means to stay: the
    /// number is small, no realistic product covers the two hours, and the day
    /// would reach the burn line.
    static func secondSessionOfTheDay() throws -> UseCaseFixture {
        let spent: SED = 0.85 * 2.25
        return try UseCaseFixture(
            name: "4 — two sessions in a day",
            curve: PlannerFixture.refetched(Curves.beachFlatUVI8(), at: PlannerFixture.at(14)),
            forecastFailure: nil, deviceLocation: Curves.location,
            now: PlannerFixture.at(14, 50), window: PlannerFixture.window(15, minutes: 120),
            posture: .lyingTurning, firstSide: .faceUp, cover: true, intent: .stayWholeWindow,
            profile: Profile(skinType: .ii, ceiling: .standard),
            state: PlannerFixture.state(spent: [.front: spent, .back: spent]),
            expected: .init(
                outcome: .plan, headline: .bareSubWindow, headlineMinutes: 5.625,
                doses: [.front: 0.3375, .back: 0.3375, .headAndShoulders: 0],
                keys: [.nothingRealistic],
                extra: { result in
                    let warned = result.copyKeys.contains(.warnReachesThreshold)
                        || result.copyKeys.contains(.warnPastTarget)
                    XCTAssertTrue(warned, "staying the whole window past the budget must warn")
                }
            )
        )
    }
}

// MARK: - Use cases 5, 6, 8 and 9

extension UseCases {
    /// 5 — the return after a break. Three weeks off is one half-life, which
    /// undoes exactly half the rise: the tolerance-dropped message, and a dose
    /// at least a quarter smaller than the last one they did.
    static func returnAfterABreak() throws -> UseCaseFixture {
        try UseCaseFixture(
            name: "5 — the return after a break",
            curve: PlannerFixture.refetched(Curves.beachFlatUVI8(), at: PlannerFixture.at(11)),
            forecastFailure: nil, deviceLocation: Curves.location,
            now: PlannerFixture.at(11, 50), window: PlannerFixture.window(12, minutes: 120),
            posture: .upAndAbout, firstSide: .faceUp, cover: false, intent: .bestMinutes,
            profile: Profile(skinType: .ii, ceiling: .standard),
            state: PlannerFixture.state(
                // One full half-life before `now` (11:50 on the 15th), and a
                // little more: the gap notice is inclusive at exactly 21 days
                // (D-2026-09-03-T5), and 20 days 23 h 50 min is not 21 days.
                tanState: 0.45, tanStateAtLastSession: 0.9,
                lastExposure: Curves.date(2026, 5, 25, 11), doseInCycle: 20,
                cycleStart: DayKey(Curves.date(2026, 5, 1), timeZone: Curves.zone)
            ),
            expected: .init(
                outcome: .plan, keys: [.toleranceDropped],
                extra: { result in
                    // The factor at the last session was 1 + 1.25 × 0.9 = 2.125,
                    // so the dose then was the target now in that proportion.
                    let target = try XCTUnwrap(result.targets[.front])
                    let beforeTheGap = target.target * 2.125 / target.adaptationFactor
                    XCTAssertLessThanOrEqual(target.target, 0.75 * beforeTheGap)
                }
            )
        )
    }

    /// 6 — the plateau. Five weeks of regular sessions have taken the factor
    /// well past the notice line, and the result shows the cycle-to-date dose
    /// beside it.
    static func plateau() throws -> UseCaseFixture {
        try UseCaseFixture(
            name: "6 — the plateau",
            curve: PlannerFixture.refetched(Curves.beachFlatUVI8(), at: PlannerFixture.at(11)),
            forecastFailure: nil, deviceLocation: Curves.location,
            now: PlannerFixture.at(11, 50), window: PlannerFixture.window(12, minutes: 120),
            posture: .upAndAbout, firstSide: .faceUp, cover: false, intent: .bestMinutes,
            profile: Profile(skinType: .ii, ceiling: .standard),
            state: PlannerFixture.state(
                reports: 6, tanState: 0.7, lastExposure: Curves.date(2026, 6, 14, 12),
                doseInCycle: 30, cycleStart: DayKey(Curves.date(2026, 5, 11), timeZone: Curves.zone)
            ),
            expected: .init(
                outcome: .plan, keys: [.escalationRisen],
                extra: { result in
                    XCTAssertEqual(result.cycleDose[.front] ?? 0, 30, accuracy: 1e-9)
                    let figure = result.figures.first { $0.key == .cycleDose }
                    XCTAssertEqual(try XCTUnwrap(figure).value, 30, accuracy: 1e-9)
                }
            )
        )
    }

    /// 8 — the type II who wants to push. Five reports, one of them pink, so the
    /// aggressive scale is unlocked: the target sits exactly on the burn line.
    static func wantingToPush() throws -> UseCaseFixture {
        try UseCaseFixture(
            name: "8 — wanting to push",
            curve: PlannerFixture.refetched(Curves.beachFlatUVI8(), at: PlannerFixture.at(11)),
            forecastFailure: nil, deviceLocation: Curves.location,
            now: PlannerFixture.at(11, 50), window: PlannerFixture.window(12, minutes: 60),
            posture: .upAndAbout, firstSide: .faceUp, cover: false, intent: .bestMinutes,
            profile: Profile(skinType: .ii, ceiling: .aggressive),
            state: PlannerFixture.state(),
            expected: .init(
                outcome: .plan, headline: .bareSubWindow,
                keys: [.thinMargin], absentKeys: [.aggressiveLocked, .conservativeUntilCalibrated],
                extra: { result in
                    let target = try XCTUnwrap(result.targets[.headAndShoulders])
                    XCTAssertEqual(target.target, target.medPersonal, accuracy: 1e-9)
                    XCTAssertFalse(result.notices.aggressiveRefused)
                }
            )
        )
    }

    /// 9 — offline at the beach. The forecast is thirteen hours old and the
    /// cache is 30 km away; it is 13:00 and the slot was 12:30 to 13:15, so the
    /// fifteen minutes left are solved from now and still carry a number.
    static func offlineAtTheBeach() throws -> UseCaseFixture {
        try UseCaseFixture(
            name: "9 — offline at the beach",
            curve: Curves.beachFlatUVI8(), forecastFailure: nil,
            deviceLocation: Coordinate(latitude: 60.17, longitude: 10.75),
            now: PlannerFixture.at(13), window: PlannerFixture.window(12, 30, minutes: 45),
            posture: .upAndAbout, firstSide: .faceUp, cover: false, intent: .bestMinutes,
            profile: Profile(skinType: .ii, ceiling: .standard),
            state: PlannerFixture.state(),
            expected: .init(
                outcome: .plan, headline: .wholeWindowFits, headlineMinutes: 15,
                doses: [.headAndShoulders: 1.79910, .front: 0.89955, .back: 0.89955],
                keys: [.staleWarn, .staleFarFromCache],
                extra: { result in
                    let plan = try XCTUnwrap(exposurePlan(result))
                    XCTAssertGreaterThanOrEqual(plan.span.start, PlannerFixture.at(13))
                }
            )
        )
    }
}

// MARK: - Reading a result

/// The plan inside a `.plan` outcome, or nil for any other outcome.
func exposurePlan(_ result: DoseResult) -> ExposurePlan? {
    guard case let .plan(plan, _, _) = result.outcome else { return nil }
    return plan
}

/// The prescribed pair inside a `.plan` outcome, when there is one.
func sunscreenAdvice(_ result: DoseResult) -> SunscreenAdvice? {
    guard case let .plan(_, sunscreen, _) = result.outcome,
          case let .prescribe(advice) = sunscreen else { return nil }
    return advice
}

func headline(_ result: DoseResult) -> Headline? {
    guard case let .plan(_, _, headline) = result.outcome else { return nil }
    return headline
}

func minutes(_ plan: ExposurePlan, _ exposure: Exposure) -> Double {
    plan.sides.first { $0.exposure == exposure }?.window.minutes ?? 0
}

/// The number the headline actually shows: the solved session, or the whole
/// window when the answer is what to wear for it (R15).
func headlineMinutes(_ result: DoseResult, window: Window, now: Date) -> Double? {
    guard let plan = exposurePlan(result), let headline = headline(result) else { return nil }
    switch headline {
    case .bareSubWindow, .wholeWindowFits: return plan.totalMinutes
    case .sunscreenForWholeWindow: return DoseCalculator.clip(window, toStartNoEarlierThan: now)?.minutes
    }
}

/// The lowest label on the ladder whose normal application covers what the
/// whole window does to the region it pushes hardest — computed from the
/// result's own published figures, never from the solver.
func lowestSufficientLabel(_ result: DoseResult, tunables: Tunables = .current) -> Int? {
    guard let region = result.attenuationRegion,
          let target = result.targets[region], target.remaining > 0 else { return nil }
    let needed = (result.wholeWindowRaw[region] ?? 0) / target.remaining
    return tunables.spfLadder.sorted().first { pow(Double($0), tunables.densityDefault / 2) >= needed }
}

/// The prescribed pair has to keep every exposed region inside its budget, not
/// only the one it was solved for.
func expectTheProtectionCoversEveryRegion(_ result: DoseResult, cover: Bool = false) throws {
    let advice = try XCTUnwrap(sunscreenAdvice(result))
    let worn = ExposureModel.attenuated(
        result.wholeWindowRaw, sunscreen: advice.prescribed, coverHeadAndShoulders: cover
    )
    for region in Region.allCases where (worn[region] ?? 0) > 0 {
        let remaining = try XCTUnwrap(result.targets[region]).remaining
        XCTAssertLessThanOrEqual(worn[region] ?? 0, remaining + 1e-6, "\(region) is over its budget")
    }
}

// MARK: - The fixtures as tests (S18)

/// Every §4 use case, run through `Planner.plan` and checked against the
/// numbers the design states: the outcome type, the headline minutes within
/// ±10%, the per-region doses, and the copy keys the use case names.
final class UseCaseTests: XCTestCase {
    func testEveryUseCaseReturnsTheOutcomeTypeItsDesignStates() throws {
        for fixture in try UseCases.all() {
            let result = Planner.plan(fixture.request, tunables: .current)
            XCTAssertEqual(OutcomeKind(result.outcome), fixture.expected.outcome, fixture.name)
        }
    }

    func testEveryUseCaseReturnsTheHeadlineItsDesignStates() throws {
        for fixture in try UseCases.all() where fixture.expected.headline != nil {
            let result = Planner.plan(fixture.request, tunables: .current)
            XCTAssertEqual(headline(result), fixture.expected.headline, fixture.name)
        }
    }

    func testEveryUseCaseHeadlineIsWithinTenPercentOfItsStatedMinutes() throws {
        for fixture in try UseCases.all() {
            guard let expected = fixture.expected.headlineMinutes else { continue }
            let result = Planner.plan(fixture.request, tunables: .current)
            let shown = try XCTUnwrap(headlineMinutes(result, window: fixture.window, now: fixture.now))
            XCTAssertEqual(shown, expected, accuracy: 0.1 * expected, fixture.name)
        }
    }

    func testEveryUseCaseDeliversThePerRegionDosesItsDesignStates() throws {
        for fixture in try UseCases.all() where !fixture.expected.doses.isEmpty {
            let result = Planner.plan(fixture.request, tunables: .current)
            let plan = try XCTUnwrap(exposurePlan(result), fixture.name)
            for (region, dose) in fixture.expected.doses {
                XCTAssertEqual(plan.perRegionDose[region] ?? 0, dose, accuracy: 0.1 * max(dose, 0.01),
                               "\(fixture.name): \(region)")
            }
        }
    }

    func testEveryUseCaseCarriesTheCopyKeysItsDesignNames() throws {
        for fixture in try UseCases.all() {
            let result = Planner.plan(fixture.request, tunables: .current)
            for key in fixture.expected.keys {
                XCTAssertTrue(result.copyKeys.contains(key), "\(fixture.name): missing \(key)")
            }
            for key in fixture.expected.absentKeys {
                XCTAssertFalse(result.copyKeys.contains(key), "\(fixture.name): unexpected \(key)")
            }
        }
    }

    func testEveryUseCaseMeetsItsOwnParticularChecks() throws {
        for fixture in try UseCases.all() {
            guard let extra = fixture.expected.extra else { continue }
            try extra(Planner.plan(fixture.request, tunables: .current))
        }
    }

    /// The engine takes its zone from the forecast, never from the device, so
    /// the machine's zone cannot change an answer (S18).
    func testEveryUseCaseIsIdenticalUnderUTCAndOslo() throws {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        for fixture in try UseCases.all() {
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "UTC"))
            let utc = Planner.plan(fixture.request, tunables: .current)
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
            let oslo = Planner.plan(fixture.request, tunables: .current)
            XCTAssertEqual(utc, oslo, fixture.name)
        }
    }
}
