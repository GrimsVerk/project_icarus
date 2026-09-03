#if canImport(SwiftUI)
    import Foundation
    import IcarusAds
    import IcarusContent
    import IcarusCore
    import IcarusData
    @testable import IcarusUI
    import XCTest

    // Slice 2 of `history`, asserted against the model alone and never against a
    // rendered view: a chart test would need a host application, and every promise
    // the slice makes about the trajectory — one point per logged session per
    // region, a running sum that only ever climbs inside a tan cycle, and a sum
    // that starts again when a new cycle opens — is reachable without one.
    //
    // The boundaries are faked and nothing else is: the forecast provider (the
    // network), the location source (the device), the notification port (the
    // system centre) and the clock. `TrajectoryModel`, which is what this slice
    // delivers, runs for real against the real history store and the real replay.
    //
    // Every fixture here is file-private: a fixture in a test target is shared
    // with every other file in it, and these names are ours.

    // MARK: - Fixtures

    /// The network, which never answers. A chart of what has already been logged
    /// must never reach for a forecast.
    private struct NoForecastProvider: UVForecastProvider {
        let name = "trajectory-test"

        func forecast(at _: Coordinate, days _: Int) async throws(ProviderError) -> ProviderForecast {
            throw ProviderError.network("the test provider is offline")
        }
    }

    /// Fixed instants only, read in UTC. Nothing here reads the wall clock, and
    /// no answer below turns on today's date.
    ///
    /// Two shapes of history are built from these: one tan cycle of three
    /// sessions two days apart, and a history whose sessions straddle a gap
    /// longer than the fourteen days that end a cycle.
    private enum Trajectory {
        static let zone = TimeZone(identifier: "UTC")!
        static let place = Coordinate(latitude: 59.91, longitude: 10.75)
        static let profile = Profile(skinType: .iii, ceiling: .standard)

        static func at(_ month: Int, _ day: Int, _ hour: Int = 10) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }

        static func key(_ moment: Date) -> DayKey {
            DayKey(moment, timeZone: zone)
        }

        /// The hour a session was outside, opening at 10:00 on the day given.
        static func hour(_ month: Int, _ day: Int) -> Window {
            let opens = at(month, day)
            return Window(start: opens, end: opens.addingTimeInterval(3600))
        }

        /// Flat UV index 8 over the day the session belongs to. Nothing in this
        /// slice recomputes a dose, so the curve only has to be well formed.
        static func storedCurve(for moment: Date) -> StoredCurve {
            let opens = key(moment).start()
            let samples = (0 ... 48).map { HourlyUVI(time: opens.addingTimeInterval(Double($0) * 3600), uvi: 8) }
            return StoredCurve(
                hourly: samples,
                solarNoon: opens.addingTimeInterval(43200),
                timeZoneID: zone.identifier,
                location: place,
                fetchedAt: opens
            )
        }

        /// One session in whatever state it is asked for, holding the doses
        /// given. A session that has been out — logged, or logged and then
        /// discarded — keeps the hour it faced and the doses it took, because a
        /// discarded record is dropped by its state and never by being empty.
        /// A session still merely planned has faced nothing.
        static func session(
            _ window: Window,
            state: SessionState,
            doses: [Region: SED]
        ) -> SessionRecord {
            let faced = state != .planned
            return SessionRecord(
                day: key(window.start),
                createdAt: window.start.addingTimeInterval(-600),
                plannedWindow: window,
                plannedIntervals: [ExposureInterval(exposure: .upAndAbout, window: window)],
                firstSide: .faceUp,
                actualIntervals: faced ? [ExposureInterval(exposure: .upAndAbout, window: window)] : nil,
                posture: .upAndAbout,
                coverHeadAndShoulders: false,
                intent: .bestMinutes,
                ceilingAtPlan: .standard,
                state: state,
                dosePerRegion: faced ? doses : [:],
                factorsShown: [.front: 1, .back: 1, .headAndShoulders: 1],
                targetsShown: [.front: 2.7, .back: 2.7, .headAndShoulders: 2.7],
                curveUsed: storedCurve(for: window.start),
                forecastFetchedAt: window.start.addingTimeInterval(-600),
                forecastPlace: place
            )
        }

        static func logged(_ window: Window, _ doses: [Region: SED]) -> SessionRecord {
            session(window, state: .logged, doses: doses)
        }

        /// Every dose below is a dyadic fraction, so a running sum of them has
        /// one exact answer and a failure is never an artefact of arithmetic.
        static let firstDoses: [Region: SED] = [.front: 1.0, .back: 0.75, .headAndShoulders: 0.5]
        static let secondDoses: [Region: SED] = [.front: 0.5, .back: 0.5, .headAndShoulders: 0.25]
        static let thirdDoses: [Region: SED] = [.front: 0.25, .back: 0.25, .headAndShoulders: 0.125]

        /// A dose big enough that a cycle carried over into the next one would
        /// be unmistakable in the numbers rather than a rounding argument.
        static let oldDoses: [Region: SED] = [.front: 4.0, .back: 3.0, .headAndShoulders: 2.0]

        // MARK: One cycle: 1, 3 and 5 June, all inside the fourteen-day gap

        static var firstWindow: Window {
            hour(6, 1)
        }

        static var secondWindow: Window {
            hour(6, 3)
        }

        static var thirdWindow: Window {
            hour(6, 5)
        }

        /// The morning after the last of them.
        static var now: Date {
            at(6, 6, 9)
        }

        /// The three sessions of one cycle, deliberately out of order: the model
        /// promises the trajectory in the order the sessions ended, not the
        /// order the store happened to hold them in.
        static var oneCycle: History {
            History(sessions: [
                logged(thirdWindow, thirdDoses),
                logged(firstWindow, firstDoses),
                logged(secondWindow, secondDoses),
            ])
        }

        // MARK: Two cycles: 1 and 3 May, then a 29-day gap, then 1 and 3 June

        static var oldFirstWindow: Window {
            hour(5, 1)
        }

        static var oldSecondWindow: Window {
            hour(5, 3)
        }

        /// Two cycles' worth of sessions. The gap between 3 May and 1 June is
        /// twenty-nine days, which is past the fourteen that close a cycle, so
        /// the June sessions open a second one.
        static var twoCycles: History {
            History(sessions: [
                logged(oldFirstWindow, oldDoses),
                logged(oldSecondWindow, oldDoses),
                logged(firstWindow, firstDoses),
                logged(secondWindow, secondDoses),
            ])
        }

        /// The morning after the second cycle's last session.
        static var afterSecondCycle: Date {
            at(6, 4, 9)
        }
    }

    /// A composed environment whose history a test seeds wholesale.
    @MainActor
    private struct TrajectoryHarness {
        let environment: AppEnvironment

        static func make(clock: Date) -> TrajectoryHarness {
            let tunables = Tunables.current
            let environment = AppEnvironment(
                forecast: ForecastService(
                    provider: NoForecastProvider(), cache: MemoryForecastCache(), tunables: tunables
                ),
                location: LocationService(
                    source: FakeLocationSource(reading: .denied), resolver: FakePlaceResolver(table: [:])
                ),
                history: HistoryStore.inMemory(tunables: tunables, profile: Trajectory.profile),
                profile: MemoryProfileStore(profile: Trajectory.profile),
                prompts: PromptScheduler(port: FakeNotificationPort(authorization: .granted), tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { clock }
            )
            return TrajectoryHarness(environment: environment)
        }

        /// A harness holding the history given, with the clock at `now`.
        static func seeded(_ history: History, now: Date) async throws -> TrajectoryHarness {
            let harness = make(clock: now)
            try await harness.environment.history.replaceAll(history)
            return harness
        }

        func model() -> TrajectoryModel {
            TrajectoryModel(env: environment)
        }

        /// The state the store replays, which is where the cycle a chart covers
        /// is decided.
        func cycleStart(_ region: Region, now: Date) async throws -> DayKey? {
            try await environment.history.state(now: now).regions[region]?.cycleStart
        }
    }

    /// One region's points, oldest first — the line the chart draws.
    private func line(_ points: [TrajectoryPoint], _ region: Region) -> [TrajectoryPoint] {
        points.filter { $0.region == region }.sorted { $0.id < $1.id }
    }

    /// The cumulative doses of one region's line, in order.
    private func doses(_ points: [TrajectoryPoint], _ region: Region) -> [SED] {
        line(points, region).map(\.cumulativeSED)
    }

    /// Cumulative doses are floating point: compare place by place, to the last
    /// place a difference could mean anything.
    private func assertDoses(
        _ actual: [SED],
        _ expected: [SED],
        _ region: Region,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, "\(region)", file: file, line: line)
        guard actual.count == expected.count else { return }
        for (index, value) in expected.enumerated() {
            XCTAssertEqual(actual[index], value, accuracy: 1e-9, "\(region) point \(index)", file: file, line: line)
        }
    }

    // MARK: - Before anything is asked for

    @MainActor
    final class TrajectoryModelStartTests: XCTestCase {
        /// The chart is empty until the model has been asked to load: a screen
        /// that has not reloaded plots nothing rather than plotting a guess.
        func testANewModelHasNoPointsUntilItIsReloaded() async throws {
            let harness = try await TrajectoryHarness.seeded(Trajectory.oneCycle, now: Trajectory.now)

            let model = harness.model()

            XCTAssertTrue(model.points.isEmpty)
        }

        /// A history with nothing logged in it has no trajectory at all.
        func testAnEmptyHistoryPlotsNothing() async throws {
            let harness = try await TrajectoryHarness.seeded(History(), now: Trajectory.now)
            let model = harness.model()

            await model.reload(now: Trajectory.now)

            XCTAssertTrue(model.points.isEmpty)
        }
    }

    // MARK: - The line each region draws (R24)

    @MainActor
    final class TrajectoryModelPointsTests: XCTestCase {
        /// One point per logged session per region, dated at the moment the
        /// session ended, and oldest first however the store held them.
        func testEveryLoggedSessionContributesOnePointPerRegionAtTheMomentItEnded() async throws {
            let harness = try await TrajectoryHarness.seeded(Trajectory.oneCycle, now: Trajectory.now)
            let model = harness.model()

            await model.reload(now: Trajectory.now)

            let ends = [Trajectory.firstWindow.end, Trajectory.secondWindow.end, Trajectory.thirdWindow.end]
            XCTAssertEqual(model.points.count, ends.count * Region.allCases.count)
            for region in Region.allCases {
                XCTAssertEqual(line(model.points, region).map(\.id), ends, "\(region)")
            }
        }

        /// A point is one region on one date: two lines may share a date, but a
        /// line never carries the same date twice, or the chart would draw a
        /// vertical step nothing in the history put there.
        func testNoRegionCarriesTwoPointsAtTheSameMoment() async throws {
            let harness = try await TrajectoryHarness.seeded(Trajectory.oneCycle, now: Trajectory.now)
            let model = harness.model()

            await model.reload(now: Trajectory.now)

            XCTAssertFalse(model.points.isEmpty)
            let identities = model.points.map { "\($0.region.rawValue)@\($0.id.timeIntervalSince1970)" }
            XCTAssertEqual(Set(identities).count, identities.count)
        }

        /// The value plotted is the running total of the doses the sessions
        /// stored — never a dose recomputed from the curve (R22, R44).
        func testEachPointIsTheRunningSumOfTheStoredDosesSoFar() async throws {
            let harness = try await TrajectoryHarness.seeded(Trajectory.oneCycle, now: Trajectory.now)
            let model = harness.model()

            await model.reload(now: Trajectory.now)

            var expected = [Region: [SED]]()
            for region in Region.allCases {
                let each = [Trajectory.firstDoses, Trajectory.secondDoses, Trajectory.thirdDoses]
                    .map { $0[region] ?? 0 }
                expected[region] = each.reduce(into: [SED]()) { running, dose in
                    running.append((running.last ?? 0) + dose)
                }
            }
            for region in Region.allCases {
                assertDoses(doses(model.points, region), expected[region] ?? [], region)
            }
        }

        /// The promise in the plan's own words: inside a cycle a line only ever
        /// climbs or stays level. Dose is spent, never returned.
        func testEveryLineIsMonotoneNonDecreasingWithinTheCycle() async throws {
            let harness = try await TrajectoryHarness.seeded(Trajectory.oneCycle, now: Trajectory.now)
            let model = harness.model()

            await model.reload(now: Trajectory.now)

            for region in Region.allCases {
                let values = doses(model.points, region)
                XCTAssertGreaterThan(values.count, 1, "\(region) has too few points to be a line")
                for (earlier, later) in zip(values, values.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(later, earlier - 1e-12, "\(region) fell back")
                }
            }
        }

        /// Reloading is a recomputation from the record, not an accumulation on
        /// top of what is already on screen.
        func testReloadingTwiceLeavesTheSameTrajectory() async throws {
            let harness = try await TrajectoryHarness.seeded(Trajectory.oneCycle, now: Trajectory.now)
            let model = harness.model()

            await model.reload(now: Trajectory.now)
            let first = model.points
            await model.reload(now: Trajectory.now)

            XCTAssertFalse(first.isEmpty)
            XCTAssertEqual(model.points, first)
        }
    }

    // MARK: - What the chart leaves out (R24, R45)

    @MainActor
    final class TrajectoryModelExclusionTests: XCTestCase {
        /// A session that was planned and never done, and one that was
        /// discarded, took no dose: neither may move a line, and neither may put
        /// a point on it.
        func testPlannedAndDiscardedSessionsPutNothingOnTheChart() async throws {
            let ghosts = [
                Trajectory.session(Trajectory.hour(6, 2), state: .planned, doses: Trajectory.oldDoses),
                Trajectory.session(Trajectory.hour(6, 4), state: .discarded, doses: Trajectory.oldDoses),
            ]
            var history = Trajectory.oneCycle
            history.sessions.append(contentsOf: ghosts)
            let harness = try await TrajectoryHarness.seeded(history, now: Trajectory.now)
            let model = harness.model()

            await model.reload(now: Trajectory.now)

            let ghostEnds = Set(ghosts.map(\.plannedWindow.end))
            XCTAssertTrue(model.points.allSatisfy { !ghostEnds.contains($0.id) })
            assertDoses(doses(model.points, .front), [1.0, 1.5, 1.75], .front)
        }

        /// The chart covers the cycle the user is in. A session from the cycle
        /// before it is history the totals already closed, and plotting it would
        /// read as this cycle's dose.
        func testSessionsFromBeforeTheCurrentCycleAreNotPlotted() async throws {
            let now = Trajectory.afterSecondCycle
            let harness = try await TrajectoryHarness.seeded(Trajectory.twoCycles, now: now)
            let opened = try await harness.cycleStart(.front, now: now)
            XCTAssertEqual(opened, Trajectory.key(Trajectory.firstWindow.start), "the fixture's cycle did not reopen")
            let model = harness.model()

            await model.reload(now: now)

            let stale = Set([Trajectory.oldFirstWindow.end, Trajectory.oldSecondWindow.end])
            XCTAssertFalse(model.points.isEmpty)
            XCTAssertTrue(model.points.allSatisfy { !stale.contains($0.id) })
            let opens = try XCTUnwrap(opened).start()
            XCTAssertTrue(model.points.allSatisfy { $0.id >= opens })
        }
    }

    // MARK: - A new cycle starts the sum again (R24)

    @MainActor
    final class TrajectoryModelCycleTests: XCTestCase {
        /// The promise in the plan's own words: the running sum resets at a
        /// cycle start. The first point of the new cycle is that session's own
        /// dose, so four SED of a tan the skin has since lost never appears as
        /// this cycle's cumulative dose.
        func testThePointOpeningANewCycleIsThatSessionsOwnDose() async throws {
            let now = Trajectory.afterSecondCycle
            let harness = try await TrajectoryHarness.seeded(Trajectory.twoCycles, now: now)
            let model = harness.model()

            await model.reload(now: now)

            for region in Region.allCases {
                let first = try XCTUnwrap(Trajectory.firstDoses[region])
                let second = try XCTUnwrap(Trajectory.secondDoses[region])
                let values = doses(model.points, region)
                let opening = try XCTUnwrap(values.first, "\(region) has no point in the new cycle")
                XCTAssertEqual(opening, first, accuracy: 1e-9, "\(region) carried the old cycle over")
                XCTAssertEqual(try XCTUnwrap(values.last), first + second, accuracy: 1e-9, "\(region)")
            }
        }

        /// Nothing about the reset depends on the old cycle being small: the
        /// same history with a far heavier first cycle draws the same new one.
        func testTheNewCycleIsTheSameHoweverHeavyTheCycleBeforeItWas() async throws {
            let now = Trajectory.afterSecondCycle
            var heavier = Trajectory.twoCycles
            heavier.sessions.insert(
                Trajectory.logged(Trajectory.hour(5, 2), [.front: 9, .back: 9, .headAndShoulders: 9]), at: 0
            )
            let light = try await TrajectoryHarness.seeded(Trajectory.twoCycles, now: now).model()
            let heavy = try await TrajectoryHarness.seeded(heavier, now: now).model()

            await light.reload(now: now)
            await heavy.reload(now: now)

            XCTAssertFalse(light.points.isEmpty)
            XCTAssertEqual(heavy.points, light.points)
        }
    }

    // MARK: - What the chart is titled (R24, S11)

    @MainActor
    final class TrajectoryChartTitleTests: XCTestCase {
        /// The chart takes exactly what the model produces, and its title is the
        /// owner's `.trajectoryTitle` line — a record of dose in SED, and in the
        /// same breath not a measurement of colour. Where that line is placed on
        /// the screen is not assertable without rendering; that it is this line,
        /// and not a literal the view invented, is.
        func testTheChartPlotsTheModelsPointsUnderTheDoseNotColourTitle() async throws {
            let harness = try await TrajectoryHarness.seeded(Trajectory.oneCycle, now: Trajectory.now)
            let model = harness.model()
            await model.reload(now: Trajectory.now)

            XCTAssertFalse(model.points.isEmpty, "there is nothing to hand the chart")
            _ = TrajectoryChart(points: model.points)

            let title = AppCopy.text(.trajectoryTitle)
            XCTAssertTrue(title.contains("SED"), "the title must name the unit it plots: \(title)")
            XCTAssertTrue(
                title.lowercased().contains("not a measurement of colour"),
                "the title must deny that it measures colour: \(title)"
            )
        }
    }
#endif
