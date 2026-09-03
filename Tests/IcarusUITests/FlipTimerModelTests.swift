#if canImport(SwiftUI)
    import Foundation
    import IcarusAds
    import IcarusCore
    import IcarusData
    @testable import IcarusUI
    import XCTest

    // Slice 4 of `calculator-ui`, asserted against the model and never against a
    // rendered view: a view test would need a host application, and every promise
    // the slice makes about the flip timer is reachable without one.
    //
    // The boundaries are faked and nothing else is — the forecast provider (the
    // network), the location source (the device), the notification port (the
    // system centre) and the clock. `FlipTimerModel` itself, which is what this
    // slice delivers, runs for real against the real engine, the real history
    // store, the real prompt scheduler and the real `CalculatorModel` it plans
    // through.
    //
    // Every type here is file-private on purpose: a fixture in a test target is
    // shared with every other file in it, and these names are ours alone.

    // MARK: - Fixtures

    /// The network, offline. Everything below plans from the seeded cache, so a
    /// provider that answered would hide a fetch nobody asked for.
    private struct OfflineProvider: UVForecastProvider {
        let name = "flip-timer-test"

        func forecast(at _: Coordinate, days _: Int) async throws(ProviderError) -> ProviderForecast {
            throw ProviderError.network("the test provider is offline")
        }
    }

    /// Fixed values only: one flat day at one place, read in UTC. Nothing here
    /// reads the wall clock.
    ///
    /// The numbers, all of them derived from the shipped constants: a type III
    /// user at the standard selector plans at the conservative scale until the
    /// app has three reports, so every region's budget is
    /// `3.0 × 0.95 × 0.75 = 2.1375` SED; a flat UV index of 8 is `8/66.7` SED a
    /// minute to bare skin, so one region's budget takes 17.821 minutes. Lying
    /// down, each side runs that long until the head-and-shoulders credit —
    /// the face-up dose in full plus half the face-down dose — is fitted back
    /// inside the same budget, which takes both sides to two thirds of it.
    private enum Fixed {
        static let zone = TimeZone(identifier: "UTC")!
        static let oslo = Coordinate(latitude: 59.91, longitude: 10.75)
        static let profile = Profile(skinType: .iii, ceiling: .standard)

        static func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let parts = DateComponents(year: 2026, month: 6, day: 15, hour: hour, minute: minute)
            return calendar.date(from: parts)!.addingTimeInterval(Double(dayOffset) * 86400)
        }

        /// 10:07 — deliberately off the quarter hour and off solar noon.
        static let now = at(10, 7)

        static var day: DayKey {
            DayKey(now, timeZone: zone)
        }

        /// Flat UV index 8 for two whole days from local midnight.
        static var hourly: [HourlyUVI] {
            let opens = day.start()
            return (0 ... 48).map { HourlyUVI(time: opens.addingTimeInterval(Double($0) * 3600), uvi: 8) }
        }

        /// Solar noon at 09:00, before every window below. The curve is flat, so
        /// every start is equally short and the engine breaks the tie on the
        /// distance from solar noon: with noon behind us the session starts at
        /// the clock time the timer was started at, which is what R11 asks for.
        static var noons: [DayKey: Date] {
            let tomorrow = day.adding(days: 1)
            return [day: day.start().addingTimeInterval(9 * 3600),
                    tomorrow: tomorrow.start().addingTimeInterval(9 * 3600)]
        }

        static func curve() throws -> ForecastCurve {
            try ForecastCurve(location: oslo, timeZone: zone, fetchedAt: at(9), hourly: hourly, solarNoon: noons)
        }

        /// The bare SED a flat UV index of 8 delivers over a span, at the
        /// constant the curve integrates with (66.7 UVI·minutes per SED).
        static func sed(seconds: Double) -> SED {
            8 * (seconds / 60) / 66.7
        }

        /// Two hours from now: room for the whole bare session and then some, so
        /// nothing below is shortened by the window running out.
        static var bare: Window {
            Window(start: now, end: at(12, 7))
        }

        /// 128 minutes from now: 5.39 times the bare session, which is inside
        /// SPF 30's effective protection (√30 = 5.48) and past SPF 20's, so the
        /// engine prescribes SPF 30 applied normally.
        static var sunscreened: Window {
            Window(start: now, end: at(12, 15))
        }

        /// Five minutes: far under half of what is left of the budget, so there
        /// is no session worth doing and the timer has nothing to run.
        static var tooShort: Window {
            Window(start: now, end: at(10, 12))
        }

        /// One region's budget for the day, in SED.
        static let target: SED = 2.1375

        /// How long each side of the bare lying session runs, in seconds:
        /// `2.1375 × 66.7 / 8 × 2/3` minutes.
        static let sideSeconds = 712.85625

        static var sessionSeconds: Double {
            sideSeconds * 2
        }

        /// What the front takes over its own side of the bare session.
        static var sideDose: SED {
            sed(seconds: sideSeconds)
        }
    }

    /// A composed environment with the notification port kept to hand, so a test
    /// can read the alerts the timer left pending.
    @MainActor
    private struct Harness {
        let environment: AppEnvironment
        let port: FakeNotificationPort

        static func make(authorization: NotificationAuthorization = .granted) throws -> Harness {
            let tunables = Tunables.current
            let cache = MemoryForecastCache()
            try cache.save(CachedForecast(curve: Fixed.curve(), providerName: "seed"))
            let port = FakeNotificationPort(authorization: authorization)
            let environment = AppEnvironment(
                forecast: ForecastService(provider: OfflineProvider(), cache: cache, tunables: tunables),
                location: LocationService(
                    source: FakeLocationSource(reading: .fix(Fixed.oslo, accuracyKm: 1)),
                    resolver: FakePlaceResolver(table: [:])
                ),
                history: HistoryStore.inMemory(tunables: tunables, profile: Fixed.profile),
                profile: MemoryProfileStore(profile: Fixed.profile),
                prompts: PromptScheduler(port: port, tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { Fixed.now }
            )
            return Harness(environment: environment, port: port)
        }
    }

    /// The calculator has answered, so the timer has a planned session to log
    /// against and a confirmed sunscreen to plan with — which is the only way
    /// either screen is ever reached.
    @MainActor
    private func models(
        _ harness: Harness,
        window: Window,
        posture: Posture = .lyingTurning,
        stay: Bool = false
    ) async -> (calculator: CalculatorModel, timer: FlipTimerModel) {
        let calculator = CalculatorModel(env: harness.environment)
        calculator.window = window
        calculator.posture = posture
        calculator.stay = stay
        await calculator.compute()
        return (calculator, FlipTimerModel(env: harness.environment, calculator: calculator))
    }

    @MainActor
    private func onlySession(
        _ harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> SessionRecord {
        let sessions = try await harness.environment.history.history().sessions
        XCTAssertEqual(sessions.count, 1, "expected exactly one session", file: file, line: line)
        return try XCTUnwrap(sessions.first, file: file, line: line)
    }

    /// The alerts the timer owns. The day's skin check is not one of them.
    @MainActor
    private func timerAlerts(_ harness: Harness) async -> [PendingNotification] {
        await harness.port.pending().filter { notification in
            switch notification.kind {
            case .timerSideEnd, .timerReapply, .timerSessionEnd: true
            case .skinCheck, .lastingColour: false
            }
        }
    }

    private func isReapply(_ notification: PendingNotification) -> Bool {
        if case .timerReapply = notification.kind {
            return true
        }
        return false
    }

    private func prescribed(_ result: DoseResult?) -> SunscreenChoice? {
        guard let result, case let .plan(_, sunscreen, _) = result.outcome else { return nil }
        return sunscreen.prescribedChoice
    }

    /// How long the running session lasts, in seconds from the start.
    @MainActor
    private func sessionSpan(_ timer: FlipTimerModel) throws -> Double {
        guard case let .running(_, _, sessionEnd) = timer.phase else {
            return try XCTUnwrap(nil as Double?, "the timer is not running: \(timer.phase)")
        }
        return sessionEnd.timeIntervalSince(Fixed.now)
    }

    /// Clock assertions are to the second: the engine interpolates inside the
    /// minute, so a whole-minute comparison would be the wrong question.
    private func assertSeconds(
        _ moment: Date,
        _ expected: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(moment.timeIntervalSince(Fixed.now), expected, accuracy: 1, file: file, line: line)
    }

    private func assertDose(
        _ actual: SED?,
        _ expected: SED,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual ?? .nan, expected, accuracy: 1e-3, file: file, line: line)
    }

    // MARK: - What the timer starts with (R11, D-2026-09-03-F8)

    @MainActor
    final class FlipTimerDefaultsTests: XCTestCase {
        /// Face up first is the default the ruling fixes, and nothing is running
        /// or refused until the user says so.
        func testANewTimerAsksForFaceUpFirstAndHasNotStarted() async throws {
            let harness = try Harness.make()

            let pair = await models(harness, window: Fixed.bare)

            XCTAssertEqual(pair.timer.firstSide, .faceUp)
            XCTAssertEqual(pair.timer.phase, .idle)
            XCTAssertFalse(pair.timer.notificationsDenied)
        }
    }

    // MARK: - Starting (R11, R45, S10)

    /// Starting plans from the real clock and logs the session it is about to
    /// run, so a session the user actually did is in the record from the moment
    /// it begins.
    @MainActor
    final class FlipTimerStartTests: XCTestCase {
        func testStartingLogsTheSessionFromThePlansOwnIntervals() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.bare)

            try await pair.timer.start(now: Fixed.now)

            let session = try await onlySession(harness)
            XCTAssertEqual(session.state, .logged)
            let intervals = try XCTUnwrap(session.actualIntervals)
            XCTAssertEqual(intervals.count, 2)
            XCTAssertEqual(intervals[0].exposure, .lying(.faceUp))
            XCTAssertEqual(intervals[1].exposure, .lying(.faceDown))
            XCTAssertEqual(intervals[0].window.start, Fixed.now, "the session starts at the clock time (R11)")
            XCTAssertEqual(intervals[1].window.start, intervals[0].window.end)
            assertSeconds(intervals[0].window.end, Fixed.sideSeconds)
            assertSeconds(intervals[1].window.end, Fixed.sessionSeconds)
            assertDose(session.dosePerRegion[.front], Fixed.sideDose)
            assertDose(session.dosePerRegion[.back], Fixed.sideDose)
            assertDose(session.dosePerRegion[.headAndShoulders], Fixed.target)
            XCTAssertNil(session.sunscreen, "a bare session wore nothing")
        }

        /// The phase is what the screen draws: which side is up, when to flip,
        /// and when the whole thing is over.
        func testStartingRunsTheFirstSideUntilTheFlipAndNamesTheSessionsEnd() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.bare)

            try await pair.timer.start(now: Fixed.now)

            guard case let .running(exposure, endsAt, sessionEnd) = pair.timer.phase else {
                return XCTFail("the timer should be running, not \(pair.timer.phase)")
            }
            XCTAssertEqual(exposure, .lying(.faceUp))
            assertSeconds(endsAt, Fixed.sideSeconds)
            assertSeconds(sessionEnd, Fixed.sessionSeconds)
        }

        /// The question the timer asks is answered by the user, so the answer has
        /// to reach the plan: face down first runs the back first.
        func testStartingFaceDownRunsThatSideFirst() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.bare)
            pair.timer.firstSide = .faceDown

            try await pair.timer.start(now: Fixed.now)

            let session = try await onlySession(harness)
            let intervals = try XCTUnwrap(session.actualIntervals)
            XCTAssertEqual(intervals.map(\.exposure), [.lying(.faceDown), .lying(.faceUp)])
            guard case let .running(exposure, _, _) = pair.timer.phase else {
                return XCTFail("the timer should be running, not \(pair.timer.phase)")
            }
            XCTAssertEqual(exposure, .lying(.faceDown))
        }

        /// A window that cannot deliver a worthwhile share of the budget is not a
        /// session, and the timer says which outcome came out instead of running
        /// one anyway (R17).
        func testAWindowTooWeakToPlanRefusesToStartAndLogsNothing() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.tooShort)

            do {
                try await pair.timer.start(now: Fixed.now)
                XCTFail("a window with no session to do must not start a timer")
            } catch let error as TimerError {
                guard case let .cannotStart(outcome) = error else {
                    return XCTFail("expected .cannotStart, got \(error)")
                }
                guard case .tooWeak = outcome else {
                    return XCTFail("expected the too-weak outcome, got \(outcome)")
                }
            }
            XCTAssertEqual(pair.timer.phase, .idle)
            let sessions = try await harness.environment.history.history().sessions
            XCTAssertTrue(sessions.isEmpty, "a refused start writes nothing")
        }

        /// R11's last sentence: with notifications denied the timer says so
        /// before it starts, and starting anyway is the user's call.
        func testStartingWithNotificationsDeniedIsRefusedUntilTheUserInsists() async throws {
            let harness = try Harness.make(authorization: .denied)
            let pair = await models(harness, window: Fixed.bare)

            do {
                try await pair.timer.start(now: Fixed.now)
                XCTFail("a denied permission must be said out loud before the timer starts")
            } catch let error as TimerError {
                XCTAssertEqual(error, .notificationsDenied)
            }
            XCTAssertTrue(pair.timer.notificationsDenied)
            XCTAssertEqual(pair.timer.phase, .idle)
            let refused = try await onlySession(harness)
            XCTAssertEqual(refused.state, .planned, "nothing is logged by a refusal")

            try await pair.timer.start(now: Fixed.now, ignoringNotifications: true)

            guard case .running = pair.timer.phase else {
                return XCTFail("starting anyway must run the session")
            }
            let insisted = try await onlySession(harness)
            XCTAssertEqual(insisted.state, .logged)
        }
    }

    // MARK: - The sunscreened session (R15, R11)

    /// With a pair confirmed, the timer plans the window the sunscreen covers
    /// rather than the bare block inside it — otherwise the user would be told
    /// to come in while wearing the thing that lets them stay out.
    @MainActor
    final class FlipTimerSunscreenTests: XCTestCase {
        func testAConfirmedPrescriptionStretchesTheSessionAcrossTheWholeWindow() async throws {
            let covered = try Harness.make()
            let plain = try Harness.make()
            let wearing = await models(covered, window: Fixed.sunscreened, stay: true)
            let without = await models(plain, window: Fixed.sunscreened, stay: true)
            without.calculator.confirmedSunscreen = SunscreenConfirmation.none

            try await wearing.timer.start(now: Fixed.now)
            try await without.timer.start(now: Fixed.now)

            XCTAssertEqual(wearing.calculator.confirmedSunscreen, .asPrescribed)
            let choice = try XCTUnwrap(prescribed(wearing.calculator.result))
            XCTAssertEqual(choice, SunscreenChoice(spfLabel: 30, application: .normal))
            let coveredSpan = try sessionSpan(wearing.timer)
            let bareSpan = try sessionSpan(without.timer)
            XCTAssertEqual(
                coveredSpan, Fixed.sunscreened.end.timeIntervalSince(Fixed.now), accuracy: 1,
                "the covered session runs to the end of the window it covers"
            )
            XCTAssertEqual(coveredSpan / bareSpan, choice.effectiveSPF, accuracy: 0.2)
        }

        /// The point of the stretch: the dose at the end of it is still the day's
        /// target, not a multiple of it.
        func testAConfirmedPrescriptionLogsAboutTheTargetAndNotTheRawWindow() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.sunscreened, stay: true)

            try await pair.timer.start(now: Fixed.now)

            let session = try await onlySession(harness)
            XCTAssertEqual(session.sunscreen, SunscreenChoice(spfLabel: 30, application: .normal))
            let head = try XCTUnwrap(session.dosePerRegion[.headAndShoulders])
            XCTAssertEqual(head, Fixed.target, accuracy: 0.1)
            XCTAssertLessThan(head, Fixed.target, "the prescribed pair covers the window with a little room")
        }
    }

    // MARK: - The alerts (R11, S9, S10)

    /// The timer alerts with the screen locked, which is scheduled notifications
    /// and nothing else.
    @MainActor
    final class FlipTimerAlertTests: XCTestCase {
        func testStartingSchedulesTheSideEndAndTheSessionEndAndNothingElse() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.bare)

            try await pair.timer.start(now: Fixed.now)

            let alerts = await timerAlerts(harness)
            XCTAssertEqual(alerts.count, 2, "a bare session has nothing to reapply")
            let sideEnd = try XCTUnwrap(alerts.first { $0.kind == .timerSideEnd })
            let sessionEnd = try XCTUnwrap(alerts.first { $0.kind == .timerSessionEnd })
            assertSeconds(sideEnd.fireAt, Fixed.sideSeconds)
            assertSeconds(sessionEnd.fireAt, Fixed.sessionSeconds)
        }

        /// A sunscreened session is alerted the same way, plus each reapplication
        /// time — every one of which belongs inside the session it is about.
        func testASunscreenedSessionAlertsAtEachSideAndReappliesInsideItsOwnSpan() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.sunscreened, stay: true)

            try await pair.timer.start(now: Fixed.now)

            let alerts = await timerAlerts(harness)
            let sideEnd = try XCTUnwrap(alerts.first { $0.kind == .timerSideEnd })
            let sessionEnd = try XCTUnwrap(alerts.first { $0.kind == .timerSessionEnd })
            assertSeconds(sideEnd.fireAt, Fixed.sunscreened.minutes * 30)
            assertSeconds(sessionEnd.fireAt, Fixed.sunscreened.minutes * 60)
            for (index, reapply) in alerts.filter(isReapply).enumerated() {
                assertSeconds(reapply.fireAt, Double(index + 1) * 2 * 3600)
                XCTAssertLessThan(reapply.fireAt, sessionEnd.fireAt)
                XCTAssertGreaterThan(reapply.fireAt, Fixed.now)
            }
        }

        func testStoppingCancelsEveryAlertTheTimerScheduled() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.bare)
            try await pair.timer.start(now: Fixed.now)

            try await pair.timer.stop(now: Fixed.now.addingTimeInterval(120))

            let alerts = await timerAlerts(harness)
            XCTAssertTrue(alerts.isEmpty, "a stopped timer has nothing left to say")
        }
    }

    // MARK: - Stopping (R11, R22, S10)

    /// Stopping writes what was actually faced, so the record shortens with the
    /// session rather than keeping the plan nobody finished.
    @MainActor
    final class FlipTimerStopTests: XCTestCase {
        func testStoppingHalfwayThroughTheFirstSideHalvesItsDoseAndWritesOneInterval() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.bare)
            try await pair.timer.start(now: Fixed.now)
            let half = Fixed.now.addingTimeInterval(Fixed.sideSeconds / 2)

            try await pair.timer.stop(now: half)

            let session = try await onlySession(harness)
            let intervals = try XCTUnwrap(session.actualIntervals)
            XCTAssertEqual(intervals.count, 1, "the side that never ran is not an interval")
            XCTAssertEqual(intervals[0].exposure, .lying(.faceUp))
            XCTAssertEqual(intervals[0].window.start, Fixed.now)
            XCTAssertEqual(intervals[0].window.end, half)
            assertDose(session.dosePerRegion[.front], Fixed.sideDose / 2)
            assertDose(session.dosePerRegion[.back], 0)
            assertDose(session.dosePerRegion[.headAndShoulders], Fixed.sideDose / 2)
            XCTAssertEqual(pair.timer.phase, .finished(stoppedAtPlannedEnd: false))
        }

        func testStoppingAfterTheFlipWritesBothSidesAsTheyActuallyRan() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.bare)
            try await pair.timer.start(now: Fixed.now)
            let stop = Fixed.now.addingTimeInterval(1000)

            try await pair.timer.stop(now: stop)

            let session = try await onlySession(harness)
            let intervals = try XCTUnwrap(session.actualIntervals)
            XCTAssertEqual(intervals.count, 2)
            XCTAssertEqual(intervals[1].window.start, intervals[0].window.end)
            assertSeconds(intervals[0].window.end, Fixed.sideSeconds)
            XCTAssertEqual(intervals[1].window.end, stop)
            let backSeconds = 1000 - Fixed.sideSeconds
            assertDose(session.dosePerRegion[.front], Fixed.sideDose)
            assertDose(session.dosePerRegion[.back], Fixed.sed(seconds: backSeconds))
            assertDose(
                session.dosePerRegion[.headAndShoulders],
                Fixed.sideDose + Fixed.sed(seconds: backSeconds) / 2
            )
        }

        /// The whole reason the stop rewrites the record: a session cut short
        /// leaves the user less spent than the plan said it would.
        func testStoppingEarlyCreditsLessThanTheSessionThatWasStarted() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.bare)
            try await pair.timer.start(now: Fixed.now)
            let planned = try await onlySession(harness).dosePerRegion

            try await pair.timer.stop(now: Fixed.now.addingTimeInterval(300))

            let stopped = try await onlySession(harness).dosePerRegion
            for region in Region.allCases {
                XCTAssertLessThan(stopped[region] ?? 0, planned[region] ?? 0, "\(region)")
            }
        }
    }

    // MARK: - The clock (R11)

    /// The timer is the session clock: it turns the user over at the flip, ends
    /// itself at the end, and refuses to run into a day the budget is not for.
    @MainActor
    final class FlipTimerClockTests: XCTestCase {
        func testTickingMovesToTheSecondSideAtTheFlipAndFinishesAtTheEnd() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.bare)
            try await pair.timer.start(now: Fixed.now)

            pair.timer.tick(now: Fixed.now.addingTimeInterval(60))
            guard case let .running(first, _, _) = pair.timer.phase else {
                return XCTFail("a minute in, the first side is still up")
            }
            XCTAssertEqual(first, .lying(.faceUp))

            pair.timer.tick(now: Fixed.now.addingTimeInterval(Fixed.sideSeconds + 1))
            guard case let .running(second, endsAt, sessionEnd) = pair.timer.phase else {
                return XCTFail("past the flip, the second side is up")
            }
            XCTAssertEqual(second, .lying(.faceDown))
            XCTAssertEqual(endsAt, sessionEnd, "the last side ends when the session does")
            assertSeconds(sessionEnd, Fixed.sessionSeconds)

            pair.timer.tick(now: Fixed.now.addingTimeInterval(Fixed.sessionSeconds + 1))
            XCTAssertEqual(pair.timer.phase, .finished(stoppedAtPlannedEnd: false))
        }

        /// A timer left running overnight is stopped at its planned end, not at
        /// the moment the app came back: the minutes after it were never faced,
        /// and they belong to another day's budget anyway.
        func testATimerLeftRunningPastMidnightStopsItselfAtThePlannedEnd() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.bare)
            try await pair.timer.start(now: Fixed.now)

            await pair.timer.foregrounded(now: Fixed.at(0, 30, dayOffset: 1))

            XCTAssertEqual(pair.timer.phase, .finished(stoppedAtPlannedEnd: true))
            let session = try await onlySession(harness)
            let intervals = try XCTUnwrap(session.actualIntervals)
            XCTAssertEqual(intervals.count, 2)
            assertSeconds(intervals[1].window.end, Fixed.sessionSeconds)
            assertDose(session.dosePerRegion[.headAndShoulders], Fixed.target)
            let alerts = await timerAlerts(harness)
            XCTAssertTrue(alerts.isEmpty)
        }

        func testForegroundingDuringTheSessionLeavesItRunning() async throws {
            let harness = try Harness.make()
            let pair = await models(harness, window: Fixed.bare)
            try await pair.timer.start(now: Fixed.now)

            await pair.timer.foregrounded(now: Fixed.now.addingTimeInterval(120))

            guard case .running = pair.timer.phase else {
                return XCTFail("two minutes in is not past midnight: \(pair.timer.phase)")
            }
        }
    }

    // MARK: - The screen declares its slots (R39, S15)

    @MainActor
    final class FlipTimerScreenManifestTests: XCTestCase {
        /// The timer is nothing but figures — the minutes left on a side — so no
        /// banner may sit under it.
        func testTheTimerCarriesNoBannerAndShowsFigures() throws {
            XCTAssertFalse(FlipTimerView.hasBannerSlot)
            XCTAssertTrue(FlipTimerView.showsFigures)
            let row = try XCTUnwrap(ScreenTable.row("FlipTimerView"))
            XCTAssertEqual(row.hasBanner, FlipTimerView.hasBannerSlot)
            XCTAssertEqual(row.showsFigures, FlipTimerView.showsFigures)
        }
    }
#endif
