#if canImport(SwiftUI)
    import Foundation
    import IcarusAds
    import IcarusCore
    import IcarusData
    @testable import IcarusUI
    import XCTest

    // Slice 3 of `calculator-ui`, asserted against the model and never against a
    // rendered view: a view test would need a host application, and every promise
    // the slice makes about the calculator is reachable without one.
    //
    // The boundaries are faked and nothing else is — the forecast provider (the
    // network), the location source (the device), the notification port (the
    // system centre) and the clock. `CalculatorModel` itself, which is what this
    // slice delivers, runs for real against the real engine, the real history
    // store and the real prompt scheduler.
    //
    // Every type here is file-private on purpose: a fixture in a test target is
    // shared with every other file in it, and these names are ours alone.

    // MARK: - Fixtures

    /// The network, counted. A provider built without an answer refuses every
    /// request, which is how a named forecast failure is produced offline.
    private actor CountingProvider: UVForecastProvider {
        nonisolated let name = "calculator-test"
        private let answer: ProviderForecast?
        private(set) var calls = 0

        init(answer: ProviderForecast?) {
            self.answer = answer
        }

        func forecast(at _: Coordinate, days _: Int) async throws(ProviderError) -> ProviderForecast {
            calls += 1
            guard let answer else { throw ProviderError.network("the test provider is offline") }
            return answer
        }
    }

    /// Fixed values only: one flat day at one place, read in UTC. Nothing here
    /// reads the wall clock, and no answer below turns on where the peak is.
    ///
    /// The numbers this produces, all of them checked against the engine: a type
    /// III user at the standard selector plans at the conservative scale until
    /// the app has three reports, which is 2.1375 SED per region, and a flat UV
    /// index of 8 is 7.196 SED an hour to bare skin.
    private enum Fixed {
        static let zone = TimeZone(identifier: "UTC")!
        static let oslo = Coordinate(latitude: 59.91, longitude: 10.75)
        static let profile = Profile(skinType: .iii, ceiling: .standard)
        static let place = Place(name: "Oslo", coordinate: oslo, timeZone: zone)

        static func at(_ hour: Int, _ minute: Int = 0) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: hour, minute: minute))!
        }

        /// 10:07 — deliberately off the quarter hour, so "the next quarter hour"
        /// has one answer rather than two.
        static let now = at(10, 7)
        static var day: DayKey {
            DayKey(now, timeZone: zone)
        }

        /// Flat UV index 8 for two whole days from local midnight.
        static var hourly: [HourlyUVI] {
            let opens = day.start()
            return (0 ... 48).map { HourlyUVI(time: opens.addingTimeInterval(Double($0) * 3600), uvi: 8) }
        }

        static var noons: [DayKey: Date] {
            let tomorrow = day.adding(days: 1)
            return [day: day.start().addingTimeInterval(43200), tomorrow: tomorrow.start().addingTimeInterval(43200)]
        }

        static func curve(fetchedAt: Date = at(9)) throws -> ForecastCurve {
            try ForecastCurve(location: oslo, timeZone: zone, fetchedAt: fetchedAt, hourly: hourly, solarNoon: noons)
        }

        static var answer: ProviderForecast {
            ProviderForecast(hourly: hourly, solarNoon: noons, timeZone: zone, horizonDays: 2)
        }

        /// An hour: about three times the head-and-shoulders budget, which SPF 15
        /// applied normally covers.
        static var hour: Window {
            Window(start: at(10, 15), end: at(11, 15))
        }

        /// Twelve minutes: viable, but too short to reach the budget, so the
        /// session is the whole window.
        static var short: Window {
            Window(start: at(10, 15), end: at(10, 27))
        }

        /// Three hours: ten times the budget, which no realistic product covers.
        static var long: Window {
            Window(start: at(10, 15), end: at(13, 15))
        }
    }

    /// A composed environment with the fakes kept to hand, so a test can count
    /// the fetches and read the pending alerts.
    @MainActor
    private struct Harness {
        let environment: AppEnvironment
        let provider: CountingProvider
        let port: FakeNotificationPort

        static func make(
            reading: LocationReading = .fix(Fixed.oslo, accuracyKm: 1),
            cacheFetchedAt: Date? = Fixed.at(9),
            providerAnswers: Bool = true
        ) throws -> Harness {
            let tunables = Tunables.current
            let cache = MemoryForecastCache()
            if let cacheFetchedAt {
                try cache.save(CachedForecast(curve: Fixed.curve(fetchedAt: cacheFetchedAt), providerName: "seed"))
            }
            let provider = CountingProvider(answer: providerAnswers ? Fixed.answer : nil)
            let port = FakeNotificationPort(authorization: .granted)
            let environment = AppEnvironment(
                forecast: ForecastService(provider: provider, cache: cache, tunables: tunables),
                location: LocationService(
                    source: FakeLocationSource(reading: reading), resolver: FakePlaceResolver(table: [:])
                ),
                history: HistoryStore.inMemory(tunables: tunables, profile: Fixed.profile),
                profile: MemoryProfileStore(profile: Fixed.profile),
                prompts: PromptScheduler(port: port, tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { Fixed.now }
            )
            return Harness(environment: environment, provider: provider, port: port)
        }

        func model(
            window: Window,
            posture: Posture = .upAndAbout,
            cover: Bool = false,
            stay: Bool = false
        ) -> CalculatorModel {
            let model = CalculatorModel(env: environment)
            model.window = window
            model.posture = posture
            model.cover = cover
            model.stay = stay
            return model
        }

        func sessions() async throws -> [SessionRecord] {
            try await environment.history.history().sessions
        }

        func onlySession(file: StaticString = #filePath, line: UInt = #line) async throws -> SessionRecord {
            let all = try await sessions()
            XCTAssertEqual(all.count, 1, "expected exactly one session", file: file, line: line)
            return try XCTUnwrap(all.first, file: file, line: line)
        }

        func skinChecks() async -> [PendingNotification] {
            await port.pending().filter { $0.kind == .skinCheck(Fixed.day) }
        }
    }

    /// The three parts of a session there is something to do about.
    private struct Solved {
        let plan: ExposurePlan
        let sunscreen: SunscreenOutcome
        let headline: Headline
    }

    /// The plan a result carries, or a failure naming the outcome that came out
    /// instead — which is the thing worth reading when one of these fails.
    private func solved(_ result: DoseResult?) throws -> Solved {
        let outcome = try XCTUnwrap(result, "nothing was computed").outcome
        guard case let .plan(plan, sunscreen, headline) = outcome else {
            return try XCTUnwrap(nil as Solved?, "expected a session to do, got \(outcome)")
        }
        return Solved(plan: plan, sunscreen: sunscreen, headline: headline)
    }

    /// Doses are floating point: compare region by region, to the last place a
    /// difference could mean anything.
    private func assertDoses(
        _ actual: [Region: SED],
        _ expected: [Region: SED],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(actual.keys), Set(expected.keys), file: file, line: line)
        for (region, value) in expected {
            XCTAssertEqual(actual[region] ?? .nan, value, accuracy: 1e-9, "\(region)", file: file, line: line)
        }
    }

    // MARK: - What the entry screen starts with

    /// The entry screen asks four questions and nothing else, so the model starts
    /// with an answer to each of them and no result at all.
    @MainActor
    final class CalculatorEntryDefaultsTests: XCTestCase {
        func testANewModelAsksAboutTheNextHourUpAndAboutAndHasComputedNothing() throws {
            let harness = try Harness.make()

            let model = CalculatorModel(env: harness.environment)

            XCTAssertEqual(model.window.start, Fixed.at(10, 15))
            XCTAssertEqual(model.window.end, Fixed.at(11, 15))
            XCTAssertEqual(model.posture, .upAndAbout)
            XCTAssertFalse(model.cover)
            XCTAssertFalse(model.stay)
            XCTAssertEqual(model.confirmedSunscreen, .none)
            XCTAssertNil(model.result)
            XCTAssertNil(model.forecastStatus)
            XCTAssertNil(model.plannedSessionID)
        }
    }

    // MARK: - The request the calculator and the timer share

    /// `request(window:firstSide:now:)` is the one place the engine's inputs are
    /// assembled, and the flip timer assembles its own through the same call
    /// (Slice 4) — so what it carries is a promise in its own right.
    @MainActor
    final class CalculatorRequestTests: XCTestCase {
        func testTheRequestCarriesTheCachedCurveTheDeviceAndEveryEnteredInput() async throws {
            let harness = try Harness.make()
            let model = harness.model(window: Fixed.hour, posture: .lyingTurning, cover: true, stay: true)
            let state = try await harness.environment.history.state(now: Fixed.now)

            let request = try await model.request(window: Fixed.hour, firstSide: .faceDown, now: Fixed.now)

            let curve = try XCTUnwrap(request.curve)
            XCTAssertEqual(curve.location, Fixed.oslo)
            XCTAssertEqual(curve.fetchedAt, Fixed.at(9))
            XCTAssertNil(request.forecastFailure)
            XCTAssertEqual(request.deviceLocation, Fixed.oslo)
            XCTAssertEqual(request.window, Fixed.hour)
            XCTAssertEqual(request.posture, .lyingTurning)
            XCTAssertEqual(request.firstSide, .faceDown)
            XCTAssertTrue(request.coverHeadAndShoulders)
            XCTAssertEqual(request.intent, .stayWholeWindow)
            XCTAssertEqual(request.profile, Fixed.profile)
            XCTAssertEqual(request.state, state)
            XCTAssertTrue(request.goal is TanningGoal)
            let calls = await harness.provider.calls
            XCTAssertEqual(calls, 0, "assembling a request must never reach for the network")
        }

        /// With no forecast and no place, the request says which of the two is
        /// missing — and a user who has not said they are staying is asking for
        /// the best minutes, not for the whole window.
        func testADeniedLocationWithNoCacheMakesTheRequestSayThereIsNoLocation() async throws {
            let harness = try Harness.make(reading: .denied, cacheFetchedAt: nil)
            let model = harness.model(window: Fixed.hour)

            let request = try await model.request(window: Fixed.hour, firstSide: .faceUp, now: Fixed.now)

            XCTAssertNil(request.curve)
            XCTAssertNil(request.deviceLocation)
            XCTAssertEqual(request.forecastFailure, .noLocation)
            XCTAssertEqual(request.intent, .bestMinutes)
        }
    }

    // MARK: - Computing (R45, S10)

    /// Computing keeps exactly one planned session for the window on the screen,
    /// records what it was solved from, and moves the day's skin check to it.
    @MainActor
    final class CalculatorComputeTests: XCTestCase {
        func testComputingWritesOnePlannedSessionRecordingWhatItWasSolvedFrom() async throws {
            let harness = try Harness.make()
            let model = harness.model(window: Fixed.hour, posture: .lyingTurning, stay: true)

            await model.compute()

            let plan = try solved(model.result).plan
            let result = try XCTUnwrap(model.result)
            let session = try await harness.onlySession()
            XCTAssertEqual(session.id, model.plannedSessionID)
            XCTAssertEqual(session.state, .planned)
            XCTAssertEqual(session.day, Fixed.day)
            XCTAssertEqual(session.plannedWindow, Fixed.hour)
            XCTAssertEqual(session.plannedIntervals, plan.intervals)
            XCTAssertEqual(session.firstSide, .faceUp)
            XCTAssertEqual(session.posture, .lyingTurning)
            XCTAssertFalse(session.coverHeadAndShoulders)
            XCTAssertEqual(session.intent, .stayWholeWindow)
            XCTAssertTrue(session.dosePerRegion.isEmpty, "a planned session has taken no dose yet")
            XCTAssertEqual(session.factorsShown, result.targets.mapValues(\.adaptationFactor))
            XCTAssertEqual(session.targetsShown, result.targets.mapValues(\.target))
            XCTAssertEqual(session.forecastFetchedAt, Fixed.at(9))
            XCTAssertEqual(session.forecastPlace, Fixed.oslo)
        }

        /// A second answer replaces the first: the user is planning one session,
        /// not collecting them (R45).
        func testComputingTwiceLeavesExactlyOnePlannedSessionForTheSecondWindow() async throws {
            let harness = try Harness.make()
            let model = harness.model(window: Fixed.hour)

            await model.compute()
            model.window = Fixed.long
            await model.compute()

            let sessions = try await harness.sessions()
            XCTAssertEqual(sessions.count, 1)
            let session = try XCTUnwrap(sessions.first)
            XCTAssertEqual(session.state, .planned)
            XCTAssertEqual(session.plannedWindow, Fixed.long)
            XCTAssertEqual(session.id, model.plannedSessionID)
        }

        func testThePlannedSessionCarriesThePrescribedPairAndOnlyWhenThereIsOne() async throws {
            let wearing = try Harness.make()
            let bare = try Harness.make()
            let staying = wearing.model(window: Fixed.hour, stay: true)
            let brief = bare.model(window: Fixed.short)

            await staying.compute()
            await brief.compute()

            let prescribed = try XCTUnwrap(solved(staying.result).sunscreen.prescribedChoice)
            let worn = try await wearing.onlySession()
            XCTAssertEqual(worn.prescribedSunscreen, prescribed)
            XCTAssertNil(worn.sunscreen, "nothing is confirmed until the user logs")
            XCTAssertEqual(try solved(brief.result).sunscreen, .notNeeded(uvaHeavy: false))
            let unprescribed = try await bare.onlySession()
            XCTAssertNil(unprescribed.prescribedSunscreen)
        }

        /// One skin check per day, moved to the end of the day's last session and
        /// asked the ruled twenty hours after it.
        func testComputingSchedulesOneSkinCheckTwentyHoursAfterTheWindowEnds() async throws {
            let harness = try Harness.make()
            let model = harness.model(window: Fixed.hour)

            await model.compute()
            model.window = Fixed.long
            await model.compute()

            let checks = await harness.skinChecks()
            XCTAssertEqual(checks.count, 1)
            XCTAssertEqual(try XCTUnwrap(checks.first).fireAt, Fixed.long.end.addingTimeInterval(20 * 3600))
        }

        /// Changing the window is free. This is the whole reason the engine takes
        /// the forecast as an input rather than fetching one of its own.
        func testChangingTheWindowOrThePostureNeverFetches() async throws {
            let harness = try Harness.make()
            let model = harness.model(window: Fixed.hour)

            await model.compute()
            model.window = Fixed.long
            await model.compute()
            model.posture = .lyingTurning
            await model.compute()

            let calls = await harness.provider.calls
            XCTAssertEqual(calls, 0)
            XCTAssertNotNil(model.result)
        }

        /// Asking for the forecast again is the one thing that does fetch, and it
        /// fetches even when the cached one is young enough to have been reused.
        func testRefreshingTheForecastFetchesEvenWithAFreshCache() async throws {
            let harness = try Harness.make(cacheFetchedAt: Fixed.at(10, 0))
            let model = harness.model(window: Fixed.hour)

            await model.refreshForecast()

            let calls = await harness.provider.calls
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(try XCTUnwrap(model.forecastStatus?.curve).fetchedAt, Fixed.now)
        }
    }

    // MARK: - No forecast, and the way back from it (R1, R2, R3)

    /// A denied location with nothing cached is still an answer, and the way out
    /// of it is naming the place by hand.
    @MainActor
    final class CalculatorMissingForecastTests: XCTestCase {
        /// With no place at all there is nowhere to fetch for, so refreshing asks
        /// nothing of the network rather than asking for a guess — and the result
        /// says which fact is missing rather than showing a number.
        func testADeniedLocationWithAnEmptyCacheSaysSoAndPlansNothing() async throws {
            let harness = try Harness.make(reading: .denied, cacheFetchedAt: nil)
            let model = harness.model(window: Fixed.hour)

            await model.refreshForecast()
            await model.compute()

            let calls = await harness.provider.calls
            XCTAssertEqual(calls, 0)
            XCTAssertEqual(try XCTUnwrap(model.result).outcome, .missingForecast(.noLocation))
            XCTAssertNil(model.plannedSessionID)
            let sessions = try await harness.sessions()
            XCTAssertTrue(sessions.isEmpty, "a result with no session to do plans none")
        }

        /// R2's manual entry, end to end: the place the user picked is fetched
        /// for, and the result that had no forecast becomes a session to do.
        func testChoosingAPlaceByHandFetchesForItAndProducesASession() async throws {
            let harness = try Harness.make(reading: .denied, cacheFetchedAt: nil)
            let model = harness.model(window: Fixed.hour)
            await model.compute()

            await model.useManualPlace(Fixed.place)

            let calls = await harness.provider.calls
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(try XCTUnwrap(model.forecastStatus?.curve).location, Fixed.place.coordinate)
            XCTAssertGreaterThan(try solved(model.result).plan.totalMinutes, 0)
            XCTAssertNotNil(model.plannedSessionID)
        }

        /// A known place whose forecast is refused, as WeatherKit refuses every
        /// request from a build signed without its entitlement (a free Personal
        /// Team): the result names the provider failure and plans nothing.
        func testARefusedForecastWithAnEmptyCacheNamesTheProviderAndPlansNothing() async throws {
            let harness = try Harness.make(cacheFetchedAt: nil, providerAnswers: false)
            let model = harness.model(window: Fixed.hour)

            await model.compute()

            let calls = await harness.provider.calls
            XCTAssertEqual(calls, 1)
            XCTAssertNil(model.forecastStatus?.curve)
            XCTAssertEqual(try XCTUnwrap(model.result).outcome, .missingForecast(.provider))
            XCTAssertNil(model.plannedSessionID)
            let sessions = try await harness.sessions()
            XCTAssertTrue(sessions.isEmpty, "a result with no session to do plans none")
        }
    }

    // MARK: - "I did this" (R15, R45, S10)

    /// What is logged is what the headline told the user to do — never a whole
    /// window of unattenuated sun the result never recommended.
    @MainActor
    final class CalculatorDidThisTests: XCTestCase {
        /// Both bare headlines log the same way: the plan's own intervals, at the
        /// plan's own doses. The hour is a sub-window inside a longer slot; the
        /// twelve minutes are a session the whole window fits.
        func testDoingABareSessionLogsThePlansOwnIntervalsAndDoses() async throws {
            for (window, headline) in [(Fixed.hour, Headline.bareSubWindow), (Fixed.short, .wholeWindowFits)] {
                let harness = try Harness.make()
                let model = harness.model(window: window)
                await model.compute()
                let plan = try solved(model.result).plan
                XCTAssertEqual(try solved(model.result).headline, headline)

                try await model.didThis()

                let session = try await harness.onlySession()
                XCTAssertEqual(session.state, .logged)
                XCTAssertEqual(session.actualIntervals, plan.intervals)
                assertDoses(session.dosePerRegion, plan.perRegionDose)
                XCTAssertNil(session.sunscreen)
            }
        }

        /// Staying out under the prescribed pair: the whole entered window is
        /// what was faced, and the dose is that window through the sunscreen.
        func testDoingTheSunscreenedWholeWindowLogsThatWindowAttenuated() async throws {
            let harness = try Harness.make()
            let model = harness.model(window: Fixed.hour, stay: true)
            await model.compute()
            XCTAssertEqual(try solved(model.result).headline, .sunscreenForWholeWindow)
            let prescribed = try XCTUnwrap(solved(model.result).sunscreen.prescribedChoice)
            model.confirmedSunscreen = .asPrescribed

            try await model.didThis()

            let result = try XCTUnwrap(model.result)
            let session = try await harness.onlySession()
            XCTAssertEqual(session.actualIntervals, [
                ExposureInterval(exposure: .upAndAbout, window: Fixed.hour),
            ])
            assertDoses(session.dosePerRegion, ExposureModel.attenuated(
                result.wholeWindowRaw, sunscreen: prescribed, coverHeadAndShoulders: false
            ))
            XCTAssertEqual(session.sunscreen, prescribed)
        }

        /// Lying down, the same window is two halves in side order, and the dose
        /// is still the whole window's, attenuated.
        func testDoingTheSunscreenedWholeWindowLyingLogsBothHalves() async throws {
            let harness = try Harness.make()
            let model = harness.model(window: Fixed.hour, posture: .lyingTurning, stay: true)
            await model.compute()
            XCTAssertEqual(try solved(model.result).headline, .sunscreenForWholeWindow)
            let prescribed = try XCTUnwrap(solved(model.result).sunscreen.prescribedChoice)
            model.confirmedSunscreen = .asPrescribed

            try await model.didThis()

            let middle = Fixed.hour.start.addingTimeInterval(Fixed.hour.minutes * 30)
            let result = try XCTUnwrap(model.result)
            let session = try await harness.onlySession()
            XCTAssertEqual(session.actualIntervals, [
                ExposureInterval(exposure: .lying(.faceUp), window: Window(start: Fixed.hour.start, end: middle)),
                ExposureInterval(exposure: .lying(.faceDown), window: Window(start: middle, end: Fixed.hour.end)),
            ])
            assertDoses(session.dosePerRegion, ExposureModel.attenuated(
                result.wholeWindowRaw, sunscreen: prescribed, coverHeadAndShoulders: false
            ))
        }

        /// "I don't have that SPF", confirmed: the log is credited against what
        /// the user actually wore, never against what was prescribed.
        func testDoingTheWindowUnderTheUsersOwnSunscreenLogsThatProduct() async throws {
            let harness = try Harness.make()
            let model = harness.model(window: Fixed.hour, stay: true)
            await model.compute()
            let choice = SunscreenChoice(spfLabel: 20, application: .normal)
            model.confirmedSunscreen = .alternative(choice)

            try await model.didThis()

            let result = try XCTUnwrap(model.result)
            let session = try await harness.onlySession()
            XCTAssertEqual(session.actualIntervals, [
                ExposureInterval(exposure: .upAndAbout, window: Fixed.hour),
            ])
            assertDoses(session.dosePerRegion, ExposureModel.attenuated(
                result.wholeWindowRaw, sunscreen: choice, coverHeadAndShoulders: false
            ))
            XCTAssertEqual(session.sunscreen, choice)
        }

        /// When no realistic product covers the window the honest answer is a
        /// shorter session, so a whole window of bare sun is never what is
        /// logged.
        func testWhenNothingRealisticCoversTheWindowTheLogIsNotTheBareWholeWindow() async throws {
            let harness = try Harness.make()
            let model = harness.model(window: Fixed.long, stay: true)
            await model.compute()
            let answer = try solved(model.result)
            guard case .nothingRealistic = answer.sunscreen else {
                return XCTFail("three hours should be past every realistic product")
            }

            try await model.didThis()

            let result = try XCTUnwrap(model.result)
            let session = try await harness.onlySession()
            XCTAssertEqual(session.actualIntervals, answer.plan.intervals)
            assertDoses(session.dosePerRegion, answer.plan.perRegionDose)
            XCTAssertNil(session.sunscreen)
            let region = try XCTUnwrap(result.attenuationRegion)
            let logged = try XCTUnwrap(session.dosePerRegion[region])
            XCTAssertLessThan(logged, try XCTUnwrap(result.wholeWindowRaw[region]))
        }

        /// The confirmation is `.asPrescribed` only against a result that
        /// prescribed something and led with it; a result that prescribes
        /// nothing puts it back to none.
        func testAResultWithNothingToPrescribeLeavesTheConfirmationAtNone() async throws {
            let harness = try Harness.make()
            let model = harness.model(window: Fixed.hour, stay: true)
            await model.compute()
            model.confirmedSunscreen = .asPrescribed

            model.window = Fixed.long
            await model.compute()

            XCTAssertEqual(model.confirmedSunscreen, .none)
        }
    }

    // MARK: - "I don't have that SPF" (R15)

    /// The re-solve is against the region the whole window pushes hardest and
    /// against what is left of that region's budget — the same two numbers the
    /// prescription itself was solved from.
    @MainActor
    final class CalculatorAlternativeTests: XCTestCase {
        func testTheAlternativeIsSolvedAgainstTheRegionTheWindowPushesHardest() async throws {
            let harness = try Harness.make()
            let model = harness.model(window: Fixed.hour, stay: true)
            await model.compute()
            let have = SunscreenChoice(spfLabel: 20, application: .normal)

            let alternative = try XCTUnwrap(model.alternative(have: have))

            let result = try XCTUnwrap(model.result)
            let region = try XCTUnwrap(result.attenuationRegion)
            XCTAssertEqual(alternative, try SunscreenSolver.alternative(
                have: have,
                rawSED: XCTUnwrap(result.wholeWindowRaw[region]),
                budgetSED: XCTUnwrap(result.targets[region]?.remaining),
                window: Fixed.hour,
                curve: Fixed.curve(),
                tunables: Tunables.current
            ))
        }

        func testThereIsNoAlternativeWithoutASessionToSolveFor() async throws {
            let harness = try Harness.make(reading: .denied, cacheFetchedAt: nil)
            let model = harness.model(window: Fixed.hour, stay: true)
            let have = SunscreenChoice(spfLabel: 30, application: .normal)

            await model.compute()
            XCTAssertNil(model.alternative(have: have))
        }
    }

    // MARK: - What the Result screen may show (R19, R30)

    /// The two facts the Result renders conditionally: a warning belongs to a
    /// user who said they are staying, and an estimate badge belongs to a figure
    /// that read an assumption.
    @MainActor
    final class CalculatorResultContentTests: XCTestCase {
        func testAWindowPastTheBurnLineWarnsOnlyWhenTheUserSaysTheyAreStaying() async throws {
            let staying = try Harness.make().model(window: Fixed.long, stay: true)
            let leaving = try Harness.make().model(window: Fixed.long)

            await staying.compute()
            await leaving.compute()

            XCTAssertFalse(try solved(staying.result).plan.warnings.isEmpty)
            XCTAssertTrue(try XCTUnwrap(staying.result).copyKeys.contains(.warnReachesThreshold))
            XCTAssertTrue(try solved(leaving.result).plan.warnings.isEmpty)
            let keys = try XCTUnwrap(leaving.result).copyKeys
            XCTAssertFalse(keys.contains(.warnReachesThreshold))
            XCTAssertFalse(keys.contains(.warnPastTarget))
        }

        /// Whether a number is an estimate is the engine's answer, never the
        /// screen's guess: a figure is an estimate exactly when it names the
        /// assumptions it read, and those are assumptions the constants declare.
        func testEveryEstimateNamesItsAssumptionsAndNothingElseDoes() async throws {
            let model = try Harness.make().model(window: Fixed.hour, stay: true)

            await model.compute()

            let figures = try XCTUnwrap(model.result).figures
            XCTAssertTrue(figures.contains { $0.key == .headlineMinutes })
            XCTAssertTrue(figures.contains(where: \.isEstimate), "no figure was an estimate")
            XCTAssertTrue(figures.contains { !$0.isEstimate }, "every figure was an estimate")
            for figure in figures {
                XCTAssertTrue(
                    Tunables.assumptionKeys.isSuperset(of: figure.assumptionKeys),
                    "\(figure.key) names something that is not an assumption"
                )
            }
        }
    }

    // MARK: - The two screens declare their slots (R39, S15)

    @MainActor
    final class CalculatorScreenManifestTests: XCTestCase {
        /// The entry screen is inputs only: it carries the banner and shows no
        /// figure the user could act on. The Result is nothing but figures, so
        /// no banner may sit under it.
        func testTheEntryScreenCarriesTheBannerAndTheResultCarriesTheFigures() {
            XCTAssertTrue(CalculatorEntryView.hasBannerSlot)
            XCTAssertFalse(CalculatorEntryView.showsFigures)
            XCTAssertFalse(ResultView.hasBannerSlot)
            XCTAssertTrue(ResultView.showsFigures)
        }

        func testBothScreensAgreeWithTheirRowsInTheTable() throws {
            let entry = try XCTUnwrap(ScreenTable.row("CalculatorEntryView"))
            XCTAssertEqual(entry.hasBanner, CalculatorEntryView.hasBannerSlot)
            XCTAssertEqual(entry.showsFigures, CalculatorEntryView.showsFigures)

            let result = try XCTUnwrap(ScreenTable.row("ResultView"))
            XCTAssertEqual(result.hasBanner, ResultView.hasBannerSlot)
            XCTAssertEqual(result.showsFigures, ResultView.showsFigures)
        }
    }
#endif
