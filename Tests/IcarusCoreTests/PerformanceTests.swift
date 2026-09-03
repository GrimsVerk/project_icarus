@testable import IcarusCore
import XCTest

/// R38, S14: the two performance bounds the design states, measured with `Date`
/// deltas rather than `measure {}` so a failure names the time it actually took.
///
/// Both are measured on work the engine is meant to repeat: a window change on
/// an already-built curve, and one replay of a season's history.
final class PerformanceTests: XCTestCase {
    private let planBudgetMilliseconds = 100.0
    private let replayBudgetMilliseconds = 200.0

    /// A window change recomputes the result from the cached curve. The curve is
    /// built once, outside the loop, because that is what the app has by then.
    func testAHundredPlansOnACachedCurveEachStayInsideTheBudget() throws {
        let curve = try Curves.beachFlatUVI8()
        var worst = 0.0
        var worstIndex = 0
        for index in 0 ..< 100 {
            let request = PlanRequest(
                curve: curve, forecastFailure: nil, deviceLocation: Curves.location,
                now: PlannerFixture.at(11, 50),
                window: PlannerFixture.window(12, minutes: 60 + Double(index)),
                posture: .lyingTurning, firstSide: .faceUp, coverHeadAndShoulders: false,
                intent: .bestMinutes, profile: Profile(skinType: .ii, ceiling: .standard),
                state: PlannerFixture.state(), goal: TanningGoal()
            )
            let started = Date()
            _ = Planner.plan(request, tunables: .current)
            let elapsed = Date().timeIntervalSince(started) * 1000
            if elapsed > worst {
                worst = elapsed
                worstIndex = index
            }
        }
        XCTAssertLessThan(
            worst, planBudgetMilliseconds,
            "the slowest of 100 plans (window \(60 + worstIndex) minutes) took \(worst) ms"
        )
    }

    /// A season's history: 160 logged sessions and 40 skin reports, replayed
    /// once, recomputing every historical factor (R44).
    func testReplayingTwoHundredRecordsStaysInsideTheBudget() throws {
        let history = try HistoryFixture.season(sessions: 160, reports: 40)
        XCTAssertEqual(history.sessions.count + history.reports.count, 200)
        let started = Date()
        let replayed = Replay.replay(
            history, skinType: .ii, now: PlannerFixture.at(23), tunables: .current
        )
        let elapsed = Date().timeIntervalSince(started) * 1000
        XCTAssertEqual(replayed.effects.count, history.reports.count)
        XCTAssertLessThan(elapsed, replayBudgetMilliseconds, "replaying 200 records took \(elapsed) ms")
    }
}

/// A season of history built from fixed dates: one session a day back from the
/// fixtures' day, with a skin report every fourth one.
private enum HistoryFixture {
    static func season(sessions count: Int, reports reportCount: Int) throws -> History {
        let curve = try Curves.beachFlatUVI8()
        let stored = curve.stored(for: PlannerFixture.day)
        var sessions = [SessionRecord]()
        var reports = [SkinReport]()
        for index in 0 ..< count {
            let day = DayKey(
                PlannerFixture.at(12).addingTimeInterval(-Double(count - index) * 86400),
                timeZone: Curves.zone
            )
            sessions.append(session(on: day, curve: stored, place: curve.location))
            if reports.count < reportCount, index % 4 == 0 {
                reports.append(report(on: day, index: index))
            }
        }
        return History(sessions: sessions, reports: reports)
    }

    private static func session(on day: DayKey, curve: StoredCurve, place: Coordinate) -> SessionRecord {
        let window = Window(start: day.start().addingTimeInterval(12 * 3600),
                            end: day.start().addingTimeInterval(12 * 3600 + 1800))
        return SessionRecord(
            day: day, createdAt: window.start, plannedWindow: window,
            plannedIntervals: [ExposureInterval(exposure: .upAndAbout, window: window)],
            firstSide: .faceUp,
            actualIntervals: [ExposureInterval(exposure: .upAndAbout, window: window)],
            posture: .upAndAbout, coverHeadAndShoulders: false, intent: .bestMinutes,
            ceilingAtPlan: .standard, state: .logged,
            dosePerRegion: [.front: 1.0, .back: 1.0, .headAndShoulders: 2.0],
            curveUsed: curve, forecastFetchedAt: day.start(), forecastPlace: place
        )
    }

    private static func report(on day: DayKey, index: Int) -> SkinReport {
        SkinReport(
            day: day, reportedAt: day.start().addingTimeInterval(32 * 3600),
            answer: index % 8 == 0 ? .faintPink : .normal,
            timing: index % 8 == 0 ? .nextMorning : nil,
            region: .allExposed, channel: .notification
        )
    }
}
