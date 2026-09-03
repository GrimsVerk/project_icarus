#if canImport(SwiftUI)
    import Foundation
    import IcarusAds
    import IcarusContent
    import IcarusCore
    import IcarusData
    import IcarusUI
    import XCTest

    /// Counts the fetches the environment makes. The provider is the real
    /// boundary — the network — so faking it leaves `AppEnvironment` itself,
    /// the thing this slice delivers, running for real.
    actor CountingForecastProvider: UVForecastProvider {
        nonisolated let name = "counting"
        private let answer: ProviderForecast
        private(set) var calls = 0

        init(answer: ProviderForecast) {
            self.answer = answer
        }

        func forecast(at _: Coordinate, days _: Int) async throws(ProviderError) -> ProviderForecast {
            calls += 1
            return answer
        }
    }

    /// Fixed values only: a flat curve over a fixed day, at a fixed place. No
    /// test here reads the wall clock.
    enum EnvironmentFixture {
        static let zone = TimeZone(identifier: "UTC")!
        static let oslo = Coordinate(latitude: 59.91, longitude: 10.75)
        static let profile = Profile(skinType: .iii, ceiling: .standard)

        static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) else {
                preconditionFailure("fixture date \(year)-\(month)-\(day) \(hour)h is not a date")
            }
            return date
        }

        static func day(_ moment: Date) -> DayKey {
            DayKey(moment, timeZone: zone)
        }

        /// Flat UVI 8 across two whole days from `moment`'s local midnight.
        static func hourly(around moment: Date) -> [HourlyUVI] {
            let opens = day(moment).start()
            return (0 ... 48).map { HourlyUVI(time: opens.addingTimeInterval(Double($0) * 3600), uvi: 8) }
        }

        static func solarNoon(around moment: Date) -> [DayKey: Date] {
            [day(moment): day(moment).start().addingTimeInterval(12 * 3600)]
        }

        static func curve(fetchedAt: Date, around moment: Date) throws -> ForecastCurve {
            try ForecastCurve(
                location: oslo,
                timeZone: zone,
                fetchedAt: fetchedAt,
                hourly: hourly(around: moment),
                solarNoon: solarNoon(around: moment)
            )
        }

        static func answer(around moment: Date) -> ProviderForecast {
            ProviderForecast(
                hourly: hourly(around: moment),
                solarNoon: solarNoon(around: moment),
                timeZone: zone,
                horizonDays: 2
            )
        }

        /// A planned lying session, face up then face down, an hour each.
        static func planned(opens: Date) throws -> SessionRecord {
            let middle = opens.addingTimeInterval(3600)
            let closes = opens.addingTimeInterval(7200)
            return try SessionRecord(
                day: day(opens),
                createdAt: opens,
                plannedWindow: Window(start: opens, end: closes),
                plannedIntervals: [
                    ExposureInterval(exposure: .lying(.faceUp), window: Window(start: opens, end: middle)),
                    ExposureInterval(exposure: .lying(.faceDown), window: Window(start: middle, end: closes)),
                ],
                firstSide: .faceUp,
                posture: .lyingTurning,
                coverHeadAndShoulders: false,
                intent: .bestMinutes,
                ceilingAtPlan: .standard,
                state: .planned,
                dosePerRegion: [:],
                curveUsed: curve(fetchedAt: opens, around: opens).stored(for: day(opens)),
                forecastFetchedAt: opens,
                forecastPlace: oslo
            )
        }
    }

    /// The environment composes the packages, refreshes on foreground at the
    /// ruled cadence (R1), clears sessions that were never faced (R45), and
    /// routes deep links (R27).
    @MainActor
    final class AppEnvironmentTests: XCTestCase {
        private let now = EnvironmentFixture.date(2026, 6, 15, 12)

        private func makeEnvironment(
            cacheFetchedAt: Date?,
            history: HistoryStore? = nil,
            reading: LocationReading = .fix(EnvironmentFixture.oslo, accuracyKm: 1)
        ) throws -> (AppEnvironment, CountingForecastProvider) {
            let tunables = Tunables.current
            let moment = now
            let provider = CountingForecastProvider(answer: EnvironmentFixture.answer(around: now))
            let cache = MemoryForecastCache()
            if let cacheFetchedAt {
                let curve = try EnvironmentFixture.curve(fetchedAt: cacheFetchedAt, around: now)
                try cache.save(CachedForecast(curve: curve, providerName: "seed"))
            }
            let environment = AppEnvironment(
                forecast: ForecastService(provider: provider, cache: cache, tunables: tunables),
                location: LocationService(
                    source: FakeLocationSource(reading: reading),
                    resolver: FakePlaceResolver(table: [:])
                ),
                history: history ?? HistoryStore.inMemory(tunables: tunables, profile: EnvironmentFixture.profile),
                profile: MemoryProfileStore(profile: nil),
                prompts: PromptScheduler(port: FakeNotificationPort(authorization: .granted), tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { moment }
            )
            return (environment, provider)
        }

        // MARK: - The foreground trigger

        func testForegroundingWithACacheOlderThanAnHourFetchesTheForecast() async throws {
            let (environment, provider) = try makeEnvironment(cacheFetchedAt: now.addingTimeInterval(-2 * 3600))

            await environment.didBecomeActive()

            let calls = await provider.calls
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(environment.lastCoordinate, EnvironmentFixture.oslo)
        }

        func testForegroundingWithACacheFromTenMinutesAgoFetchesNothing() async throws {
            let (environment, provider) = try makeEnvironment(cacheFetchedAt: now.addingTimeInterval(-600))

            await environment.didBecomeActive()

            let calls = await provider.calls
            XCTAssertEqual(calls, 0)
        }

        /// A session that was planned and never faced stops counting once its
        /// skin-check window has closed unanswered (R45).
        func testForegroundingDiscardsAPlannedSessionNobodyEverAnsweredFor() async throws {
            let tunables = Tunables.current
            let store = HistoryStore.inMemory(tunables: tunables, profile: EnvironmentFixture.profile)
            let opens = EnvironmentFixture.date(2026, 6, 10, 10)
            let stale = try EnvironmentFixture.planned(opens: opens)
            _ = try await store.upsertPlanned(stale, replacing: nil)
            let (environment, _) = try makeEnvironment(
                cacheFetchedAt: now.addingTimeInterval(-600), history: store
            )

            await environment.didBecomeActive()

            let planned = try await store.plannedSessions(on: EnvironmentFixture.day(opens))
            XCTAssertTrue(planned.isEmpty)
            let sessions = try await store.sessions(on: EnvironmentFixture.day(opens))
            XCTAssertEqual(sessions.map(\.state), [.discarded])
        }

        // MARK: - Deep links

        func testADeepLinkRoutesToItsLearnModule() throws {
            let (environment, _) = try makeEnvironment(cacheFetchedAt: nil)
            let url = try XCTUnwrap(URL(string: "icarus://learn/3"))
            let module = try XCTUnwrap(ModuleID(rawValue: 3))

            XCTAssertEqual(environment.handle(url), .learn(module))
        }

        func testAURLThatIsNotOursRoutesNowhere() throws {
            let (environment, _) = try makeEnvironment(cacheFetchedAt: nil)
            let foreign = try XCTUnwrap(URL(string: "https://example.com/learn/3"))
            let unknown = try XCTUnwrap(URL(string: "icarus://learn/99"))

            XCTAssertNil(environment.handle(foreign))
            XCTAssertNil(environment.handle(unknown))
        }

        // MARK: - The preview environment and the profile store

        func testThePreviewEnvironmentRunsOfflineWithNoProfileAndAFixedClock() {
            let environment = AppEnvironment.preview()

            XCTAssertNil(environment.profile.load())
            XCTAssertNil(environment.ads.banner(width: 320))
            XCTAssertEqual(environment.clock(), EnvironmentFixture.date(2026, 6, 15, 9))
        }

        func testTheProfileStoreRoundTripsTheProfileAndItsFlags() {
            let environment = AppEnvironment.preview()

            var flags = environment.profile.flags()
            XCTAssertFalse(flags.onboardingComplete)
            XCTAssertFalse(flags.disclaimerAcknowledged)
            XCTAssertFalse(flags.adConsentDone)

            let profile = Profile(skinType: .ii, ceiling: .aggressive)
            environment.profile.save(profile)
            XCTAssertEqual(environment.profile.load(), profile)

            flags.disclaimerAcknowledged = true
            environment.profile.setFlags(flags)
            XCTAssertTrue(environment.profile.flags().disclaimerAcknowledged)
            XCTAssertFalse(environment.profile.flags().onboardingComplete)
        }
    }

    /// Until M7 the app carries the protocol and nothing behind it: no banner,
    /// and a request configuration that asks for non-personalised ads (R40).
    @MainActor
    final class NoAdsProviderTests: XCTestCase {
        func testTheNoOpProviderShowsNoBanner() {
            XCTAssertNil(NoAdsProvider().banner(width: 320))
        }

        func testTheNoOpProviderAsksForNonPersonalisedAdsAndShowsNoConsentForm() {
            let configuration = NoAdsProvider().requestConfiguration
            XCTAssertTrue(configuration.nonPersonalised)
            XCTAssertFalse(configuration.consentShown)
        }

        func testTheNoOpProviderIsNeverReadyInEitherConsentRegion() async {
            let provider = NoAdsProvider()
            let consented = await provider.prepare(region: .requiresConsent)
            let free = await provider.prepare(region: .none)

            XCTAssertEqual(consented, .unavailable)
            XCTAssertEqual(free, .unavailable)
        }
    }
#endif
