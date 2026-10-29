import Foundation
import IcarusCore
import IcarusData
import XCTest

// MARK: - The simulated user, driven through the real store

/// The S3 simulation again, but every day goes through `HistoryStore` —
/// `upsertPlanned` → `log` → `addReport` — instead of a hand-assembled
/// `History`, so the whole loop the app actually runs is what the S3 bounds are
/// asserted against (`store.state(now:)`).
///
/// The response model is the engine's and never this file's judgement: the
/// answer comes from `Tunables.reporterAnswer(ratio:)`, and the user's own tan
/// state follows the same rise-and-decay rule the engine models. This is copied
/// from `Tests/IcarusCoreTests/Fixtures/SimulatedUser.swift` because that is
/// another test target and cannot be imported from here.
///
/// Every session is three hours, lying down and turning over, on a flat UVI 8
/// day, and every region is dosed at its own target, so the dose fraction that
/// drives the tan state is exactly 1.0.
private struct StoreSimulation {
    /// One session day: an offset in whole days from the run's first day, and
    /// an optional answer that replaces the truthful one (S3's outliers).
    struct Day {
        let offset: Int
        let answer: SkinAnswer?

        init(_ offset: Int, answer: SkinAnswer? = nil) {
            self.offset = offset
            self.answer = answer
        }
    }

    /// What one run produced. The history lives in the store; these are the
    /// numbers the assertions need beside it.
    struct Run {
        let store: HistoryStore
        var effects: [CalibrationEffect] = []
        var answers: [SkinAnswer] = []
        /// The front region's dose each day, which is that region's target.
        var doses: [SED] = []
        var sessionEnds: [Date] = []

        var lastSessionEnd: Date {
            sessionEnds.last ?? .distantPast
        }

        /// Nothing in the history is later than `finish`: it is an hour past
        /// the last answer, which came twenty hours after the last session.
        var finish: Date {
            lastSessionEnd.addingTimeInterval(21 * 3600)
        }

        func state() async throws -> DerivedState {
            try await store.state(now: finish)
        }

        func multiplier() async throws -> Double {
            try await state().multiplier
        }

        func front() async throws -> RegionState {
            try await state().regions[.front] ?? RegionState()
        }

        func totals() async throws -> Totals {
            try await store.totals(now: finish)
        }

        /// The dose of every session that ended inside the seven days before
        /// `finish` — what the weekly total must add up to.
        var dosesInTheLastSevenDays: SED {
            let opens = finish.addingTimeInterval(-7 * 24 * 3600)
            return zip(doses, sessionEnds)
                .filter { $0.1 > opens && $0.1 <= finish }
                .reduce(0) { $0 + $1.0 }
        }

        var everyDose: SED {
            doses.reduce(0, +)
        }
    }

    var trueMultiplier: Double = 1
    var trueGainScale: Double = 1
    var zone: TimeZone = StoreSimulation.utc
    var skinType: SkinType = .ii
    var ceiling: Ceiling = .standard
    var tunables: Tunables = .current

    static let utc = TimeZone(identifier: "UTC") ?? .gmt
    static let location = Coordinate(latitude: 59.9, longitude: 10.75)
    /// Local noon, and three hours out.
    static let sessionHour = 12.0
    static let sessionHours = 3.0

    var profile: Profile {
        Profile(skinType: skinType, ceiling: ceiling)
    }

    // MARK: Running a schedule

    /// Runs the schedule against a fresh in-memory store: on every session day
    /// the user asks the store what it knows, does exactly what that implies,
    /// logs it, and answers the skin check twenty hours later.
    func run(_ days: [Day], from start: Date) async throws -> Run {
        var run = Run(store: HistoryStore.inMemory(tunables: tunables, profile: profile))
        var trueTan = 0.0
        var previous: Int?
        for (index, day) in days.enumerated() {
            let opens = Self.noon(start, day.offset)
            let closes = opens.addingTimeInterval(Self.sessionHours * 3600)
            if let previous {
                trueTan = decayedTrueTan(trueTan, days: Double(day.offset - previous))
            }

            let state = try await run.store.state(now: opens)
            let targets = targets(state: state, at: opens)
            let doses = targets.mapValues(\.target)

            let record = try planned(index: index, opens: opens, closes: closes)
            let id = try await run.store.upsertPlanned(record, replacing: nil)
            try await run.store.log(
                id, actual: record.plannedIntervals, sunscreen: nil, doses: doses,
                factors: targets.mapValues(\.adaptationFactor), targets: doses
            )

            let front = doses[.front] ?? 0
            let answer = day.answer ?? tunables.reporterAnswer(ratio: front / trueThreshold(tanState: trueTan))
            let effect = try await run.store.addReport(report(index: index, opens: opens, closes: closes,
                                                              answer: answer))

            run.effects.append(effect)
            run.answers.append(answer)
            run.doses.append(front)
            run.sessionEnds.append(closes)
            trueTan = risenTrueTan(trueTan)
            previous = day.offset
        }
        return run
    }

    /// The dose the app recommends for each region: that region's whole target
    /// for the day, which is what "the user does exactly what it says" means.
    func targets(state: DerivedState, at moment: Date) -> [Region: RegionTarget] {
        var targets = [Region: RegionTarget]()
        for region in Region.allCases {
            targets[region] = TanningGoal().target(for: region, profile: profile, state: state,
                                                   now: moment, stale: false, tunables: tunables)
        }
        return targets
    }

    // MARK: Building the records

    private func planned(index: Int, opens: Date, closes: Date) throws -> SessionRecord {
        let day = DayKey(opens, timeZone: zone)
        let middle = opens.addingTimeInterval(closes.timeIntervalSince(opens) / 2)
        return try SessionRecord(
            id: StoreFixtures.uuid(1000 + index), day: day, createdAt: opens,
            plannedWindow: Window(start: opens, end: closes),
            plannedIntervals: [
                ExposureInterval(exposure: .lying(.faceUp), window: Window(start: opens, end: middle)),
                ExposureInterval(exposure: .lying(.faceDown), window: Window(start: middle, end: closes)),
            ],
            firstSide: .faceUp, posture: .lyingTurning, coverHeadAndShoulders: false,
            intent: .stayWholeWindow, ceilingAtPlan: ceiling, state: .planned,
            dosePerRegion: [:], curveUsed: storedCurve(on: day),
            forecastFetchedAt: day.start(), forecastPlace: Self.location
        )
    }

    private func report(index: Int, opens: Date, closes: Date, answer: SkinAnswer) -> SkinReport {
        SkinReport(
            id: StoreFixtures.uuid(2000 + index),
            day: DayKey(opens, timeZone: zone),
            reportedAt: closes.addingTimeInterval(tunables.skinCheckDelayHours * 3600),
            answer: answer,
            timing: answer == .normal ? nil : .thatEvening,
            region: .front,
            channel: .notification
        )
    }

    /// Flat UVI 8 across the day, in the run's own zone.
    private func storedCurve(on day: DayKey) throws -> StoredCurve {
        let opens = day.start()
        let samples = (0 ... 48).map { HourlyUVI(time: opens.addingTimeInterval(Double($0) * 3600), uvi: 8) }
        let curve = try ForecastCurve(location: Self.location, timeZone: zone, fetchedAt: opens,
                                      hourly: samples, solarNoon: [day: opens.addingTimeInterval(12 * 3600)])
        return curve.stored(for: day)
    }

    // MARK: The user's own skin

    /// `MED_baseline × trueMultiplier × (1 + trueGainScale × gain × tanState)`.
    func trueThreshold(tanState: Double) -> SED {
        tunables.medBaselineSED(skinType) * trueMultiplier
            * (1 + trueGainScale * tunables.adaptationGain(skinType.band) * tanState)
    }

    private func decayedTrueTan(_ tanState: Double, days: Double) -> Double {
        tanState * pow(0.5, days / tunables.decayHalfLifeDays)
    }

    private func risenTrueTan(_ tanState: Double) -> Double {
        let step = tunables.riseMultiplier(skinType.band) / tunables.riseTimeConstantDays
        return tanState + (1 - tanState) * (1 - exp(-step))
    }

    static func noon(_ start: Date, _ offset: Int) -> Date {
        start.addingTimeInterval(Double(offset) * 86400 + sessionHour * 3600)
    }

    /// Consecutive days, one session each.
    static func daily(_ count: Int) -> [Day] {
        (0 ..< count).map { Day($0) }
    }
}

// MARK: - S3 through the store

/// S3's bounds, held against the state the real store replays rather than
/// against a history the test assembled: the loop the app runs — plan, log,
/// report — is what moves the multiplier here.
final class EndToEndCalibrationTests: XCTestCase {
    private let start = StoreFixtures.date(2026, 6, 15)

    private func user(trueMultiplier: Double = 1, zone: TimeZone = StoreSimulation.utc) -> StoreSimulation {
        StoreSimulation(trueMultiplier: trueMultiplier, zone: zone)
    }

    func testASensitiveUserIsFoundWithinEightReportsThroughTheStore() async throws {
        let run = try await user(trueMultiplier: 0.75).run(StoreSimulation.daily(8), from: start)
        let found = try await run.multiplier()
        XCTAssertEqual(found, 0.75, accuracy: 0.05)
    }

    func testATruthfulUserAtTheStandardScaleIsLeftAloneThroughTheStore() async throws {
        let run = try await user().run(StoreSimulation.daily(20), from: start)
        let found = try await run.multiplier()
        XCTAssertEqual(found, 1.0, accuracy: 0.05)
    }

    /// The store answers every `addReport` with what the replay did, so twenty
    /// days of the loop leave twenty effects and none of them is the
    /// "nothing was logged that day" one.
    func testEveryReportTheStoreRecordedCameBackWithItsEffect() async throws {
        let run = try await user().run(StoreSimulation.daily(20), from: start)
        XCTAssertEqual(run.effects.count, 20)
        XCTAssertFalse(run.effects.contains(.noDoseThatDay))
    }

    /// The multiplier with the outlier, minus the multiplier without it: the
    /// difference S3 puts bounds on.
    private func moved(by answer: SkinAnswer, atReport index: Int) async throws -> Double {
        var days = StoreSimulation.daily(20)
        let simulation = user(trueMultiplier: 0.75)
        let plain = try await simulation.run(days, from: start).multiplier()
        days[index - 1] = StoreSimulation.Day(index - 1, answer: answer)
        let outlying = try await simulation.run(days, from: start).multiplier()
        return outlying - plain
    }

    func testANormalOutlierLateOnBarelyMovesTheMultiplierThroughTheStore() async throws {
        let moved = try await moved(by: .normal, atReport: 15)
        XCTAssertLessThanOrEqual(abs(moved), 0.05)
    }

    func testARedAndSoreOutlierLateOnMovesTheMultiplierDownThroughTheStore() async throws {
        let moved = try await moved(by: .redSore, atReport: 15)
        XCTAssertLessThanOrEqual(moved, -0.10)
        XCTAssertGreaterThanOrEqual(moved, -0.20)
    }

    /// The same instants recorded under a different zone's `DayKey`s: the
    /// history folds by the day it was recorded in, so the machine's zone
    /// cannot change what the store learned.
    func testTheWholeLoopLearnsTheSameMultiplierInUTCAndInOslo() async throws {
        let oslo = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let here = try await user(trueMultiplier: 0.75).run(StoreSimulation.daily(8), from: start).multiplier()
        let there = try await user(trueMultiplier: 0.75, zone: oslo)
            .run(StoreSimulation.daily(8), from: start).multiplier()
        XCTAssertEqual(here, there, accuracy: 1e-12)
    }

    func testTheWholeLoopReachesTheSameTanStateInUTCAndInOslo() async throws {
        let oslo = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let here = try await user().run(StoreSimulation.daily(8), from: start).front()
        let there = try await user(zone: oslo).run(StoreSimulation.daily(8), from: start).front()
        XCTAssertEqual(here.tanState, there.tanState, accuracy: 1e-12)
        XCTAssertGreaterThan(here.tanState, 0)
    }
}

// MARK: - Totals over a run the loop produced

/// R24: the two spans History shows, added up from a history the loop actually
/// wrote rather than one seeded by hand.
final class EndToEndTotalsTests: XCTestCase {
    private let start = StoreFixtures.date(2026, 6, 15)

    private func twentyDays() async throws -> StoreSimulation.Run {
        try await StoreSimulation().run(StoreSimulation.daily(20), from: start)
    }

    func testTheWeeklyTotalHoldsOnlyTheLastSevenDaysOfLoggedDose() async throws {
        let run = try await twentyDays()
        let totals = try await run.totals()
        XCTAssertEqual(totals.week[.front] ?? 0, run.dosesInTheLastSevenDays, accuracy: 1e-9)
        XCTAssertLessThan(totals.week[.front] ?? 0, run.everyDose)
    }

    func testTheCycleTotalHoldsEveryLoggedDoseSinceTheCycleOpened() async throws {
        let run = try await twentyDays()
        let totals = try await run.totals()
        XCTAssertEqual(totals.cycle[.front] ?? 0, run.everyDose, accuracy: 1e-9)
    }

    /// Both spans are per region, and twenty unbroken days are one cycle, so
    /// every region carries its own pair of figures with the cycle at least the
    /// week.
    func testEveryExposedRegionCarriesItsOwnPairOfFigures() async throws {
        let run = try await twentyDays()
        let totals = try await run.totals()
        for region in Region.allCases {
            XCTAssertGreaterThan(totals.week[region] ?? 0, 0, "\(region) logged no dose in the last week")
            XCTAssertGreaterThan(totals.cycle[region] ?? 0, totals.week[region] ?? 0, "\(region)")
        }
    }

    /// The loop leaves nothing behind: a day that was planned and then logged
    /// has no planned session left for the skin check to ask about again.
    func testALoggedDayHasNoPlannedSessionLeft() async throws {
        let run = try await StoreSimulation().run(StoreSimulation.daily(2), from: start)
        let day = DayKey(StoreSimulation.noon(start, 1), timeZone: StoreSimulation.utc)
        let planned = try await run.store.plannedSessions(on: day)
        let sessions = try await run.store.sessions(on: day)
        XCTAssertTrue(planned.isEmpty)
        XCTAssertEqual(sessions.filter { $0.state == .logged }.count, 1)
    }
}
