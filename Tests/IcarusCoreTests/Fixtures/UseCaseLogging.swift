// Use case 7 — "the day after" — is M5's, and it appends itself to the §4
// registry from here so that adding it never edits `UseCases.swift`.

import Foundation
@testable import IcarusCore
import XCTest

// MARK: - The day after

/// The history use case 7 describes, built the way the app builds it: one
/// session planned for the day, the skin check answering "yes" to "did you do
/// this session?" — which is what turns the planned record into a logged one —
/// and then Q1 answered "faint pink" about that day, twenty hours later.
enum DayAfter {
    static let tunables = Tunables.current
    static let skinType = SkinType.ii
    static let ceiling = Ceiling.standard
    /// Fixed ids, so the effect this report produced can be looked up by it.
    static let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000107")!
    static let reportID = UUID(uuidString: "00000000-0000-0000-0000-000000000207")!

    static var profile: Profile {
        Profile(skinType: skinType, ceiling: ceiling)
    }

    /// The session: noon to 15:00 on the fixtures' first day, lying and turning.
    static var sessionOpens: Date {
        Curves.date(2026, 6, 15, 12)
    }

    static var sessionCloses: Date {
        sessionOpens.addingTimeInterval(3 * 3600)
    }

    /// The skin check, `skinCheckDelayHours` after the session ended.
    static var reportedAt: Date {
        sessionCloses.addingTimeInterval(tunables.skinCheckDelayHours * 3600)
    }

    /// The day after: the user opens the app again an hour after answering.
    static var planningAt: Date {
        Curves.date(2026, 6, 16, 11, 50)
    }

    static var window: Window {
        Window(start: Curves.date(2026, 6, 16, 12), end: Curves.date(2026, 6, 16, 13))
    }

    static var day: DayKey {
        DayKey(sessionOpens, timeZone: Curves.zone)
    }

    /// The whole target for each region, at the state the app held before the
    /// session — the dose the user gets by doing exactly what it recommended.
    static func doses() -> [Region: SED] {
        let state = DerivedState.initial(tunables: tunables)
        var doses = [Region: SED]()
        for region in Region.allCases {
            doses[region] = TanningGoal().target(for: region, profile: profile, state: state,
                                                 now: sessionOpens, stale: false, tunables: tunables).target
        }
        return doses
    }

    /// The one session, planned and then logged from the intervals faced.
    static func session() throws -> SessionRecord {
        let middle = sessionOpens.addingTimeInterval(1.5 * 3600)
        let intervals = [
            ExposureInterval(exposure: .lying(.faceUp), window: Window(start: sessionOpens, end: middle)),
            ExposureInterval(exposure: .lying(.faceDown), window: Window(start: middle, end: sessionCloses)),
        ]
        return try SessionRecord(
            id: sessionID, day: day, createdAt: sessionOpens,
            plannedWindow: Window(start: sessionOpens, end: sessionCloses),
            plannedIntervals: intervals, firstSide: .faceUp, actualIntervals: intervals,
            posture: .lyingTurning, coverHeadAndShoulders: false, intent: .stayWholeWindow,
            ceilingAtPlan: ceiling, state: .logged, dosePerRegion: doses(),
            curveUsed: Curves.beachFlatUVI8().stored(for: day),
            forecastFetchedAt: Curves.start, forecastPlace: Curves.location
        )
    }

    /// Q1 "faint pink", on the default region the flow offers.
    static func report() -> SkinReport {
        SkinReport(id: reportID, day: day, reportedAt: reportedAt, answer: .faintPink,
                   timing: .thatEvening, region: .allExposed, channel: .notification)
    }

    static func history() throws -> History {
        try History(sessions: [session()], reports: [report()])
    }

    /// What the replay makes of it at the moment the next plan is asked for.
    static func replayed() throws -> (state: DerivedState, effects: [UUID: CalibrationEffect]) {
        try Replay.replay(history(), skinType: skinType, now: planningAt, tunables: tunables)
    }

    static func effect() throws -> CalibrationEffect {
        let replayed = try replayed()
        return replayed.effects[reportID] ?? .none
    }
}

// MARK: - The fixture

extension UseCases {
    /// 7 — the day after. One planned session, logged by the skin check's
    /// "yes"; Q1 answered "faint pink" about that day; and the plan the user
    /// asks for the next morning is made at the multiplier that answer moved.
    static func dayAfter() throws -> UseCaseFixture {
        let replayed = try DayAfter.replayed()
        let effect = try DayAfter.effect()
        return try UseCaseFixture(
            name: "7 — the day after",
            curve: PlannerFixture.refetched(Curves.beachFlatUVI8(), at: Curves.date(2026, 6, 16, 11)),
            forecastFailure: nil, deviceLocation: Curves.location,
            now: DayAfter.planningAt, window: DayAfter.window,
            posture: .upAndAbout, firstSide: .faceUp, cover: false, intent: .bestMinutes,
            profile: DayAfter.profile,
            state: replayed.state,
            expected: .init(
                outcome: .plan,
                extra: { result in
                    guard case .multiplierMoved = effect else {
                        return XCTFail("a faint-pink report about a dosed day must move the multiplier")
                    }
                    XCTAssertLessThan(replayed.state.multiplier, 1,
                                      "faint pink at the day's whole target means the skin is more sensitive")
                    // The plan the next morning is made at that multiplier:
                    // the burn line is the baseline scaled by it and by the
                    // adaptation the session earned, and nothing else.
                    let target = try XCTUnwrap(result.targets[.front])
                    XCTAssertEqual(
                        target.medPersonal,
                        DayAfter.tunables.medBaselineSED(.ii) * replayed.state.multiplier
                            * target.adaptationFactor,
                        accuracy: 1e-9
                    )
                }
            )
        )
    }
}

/// Appends use case 7 to the §4 registry once, whichever test asks first.
enum UseCaseLogging {
    private nonisolated(unsafe) static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        UseCases.register(UseCases.dayAfter)
    }
}

// MARK: - Its own promises (S18)

/// The day-after loop, asserted here as well as through the S18 runner, so the
/// promises hold whatever order the test classes run in.
final class DayAfterUseCaseTests: XCTestCase {
    override static func setUp() {
        super.setUp()
        UseCaseLogging.register()
    }

    func testTheDayAfterFixtureIsRegisteredWithTheUseCaseRunner() throws {
        let names = try UseCases.all().map(\.name)
        XCTAssertTrue(names.contains("7 — the day after"), "use case 7 never reached the S18 runner")
    }

    func testTheFaintPinkAnswerMovesTheMultiplier() throws {
        guard case let .multiplierMoved(from, to) = try DayAfter.effect() else {
            return try XCTFail("the day's report should have moved the multiplier, not \(DayAfter.effect())")
        }
        XCTAssertEqual(from, 1, accuracy: 1e-12)
        XCTAssertLessThan(to, from)
    }

    func testTheMultiplierTheNextMorningIsBelowOne() throws {
        let state = try DayAfter.replayed().state
        XCTAssertLessThan(state.multiplier, 1)
        XCTAssertEqual(state.totalReports, 1)
        XCTAssertEqual(state.rednessReportCount, 1)
    }

    /// The whole point of the loop: the next morning's number is smaller than
    /// the one the same window would have produced had nothing been reported.
    func testTheNextMorningsTargetIsSmallerThanTheUncalibratedOne() throws {
        let fixture = try UseCases.dayAfter()
        let learned = Planner.plan(fixture.request, tunables: DayAfter.tunables)
        let ignored = Planner.plan(
            PlanRequest(
                curve: fixture.curve, forecastFailure: nil, deviceLocation: fixture.deviceLocation,
                now: fixture.now, window: fixture.window, posture: fixture.posture,
                firstSide: fixture.firstSide, coverHeadAndShoulders: fixture.cover,
                intent: fixture.intent, profile: fixture.profile,
                state: fixture.state.withMultiplier(1), goal: TanningGoal()
            ),
            tunables: DayAfter.tunables
        )
        let learnedTarget = try XCTUnwrap(learned.targets[.front]).target
        let ignoredTarget = try XCTUnwrap(ignored.targets[.front]).target
        XCTAssertLessThan(learnedTarget, ignoredTarget)
    }
}

private extension DerivedState {
    /// The same state with the calibration undone — the comparison that shows
    /// the report, and not the session, is what shortened the next dose.
    func withMultiplier(_ multiplier: Double) -> DerivedState {
        var copy = self
        copy.multiplier = multiplier
        return copy
    }
}
