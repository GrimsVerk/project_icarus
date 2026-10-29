#if canImport(SwiftUI)
    import Combine
    import Foundation
    import IcarusAds
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// Everything the screens are given, in one object.
    ///
    /// It composes the packages and does nothing else: no calculation lives
    /// here, and no screen builds a service of its own. Three things it does own,
    /// because they belong to the app rather than to any one screen: the
    /// foreground refresh (R1's trigger), dropping planned sessions nobody ever
    /// reported (R45), and turning a deep link into a destination (R27).
    ///
    /// `clock` is injected so every screen reads the same time and a test can
    /// hold it still.
    @MainActor
    public final class AppEnvironment: ObservableObject {
        public let forecast: ForecastService
        public let location: LocationService
        public let history: HistoryStore
        public let profile: any ProfileStore
        public let prompts: PromptScheduler
        public let ads: any AdBannerProvider
        public let tunables: Tunables
        public let clock: () -> Date

        /// The place the last location answer named, kept so a refresh has
        /// somewhere to fetch for even when the answer this time is a denial.
        public private(set) var lastCoordinate: Coordinate?

        /// The owner's privacy policy page (R41), or nil where none is set.
        public var privacyPolicyURL: URL?

        /// Apple's weather attribution (R29). Nothing outside the live
        /// environment asks WeatherKit for it.
        public var weatherAttribution: @Sendable () async -> WeatherAttribution? = { nil }

        /// The zone of the cached forecast's place, once there is one. The
        /// Calculator shows the slot in it (screen review F1).
        @Published public private(set) var forecastTimeZone: TimeZone?

        /// Whether the ad provider has been prepared this run.
        private var adsPrepared = false

        public init(
            forecast: ForecastService,
            location: LocationService,
            history: HistoryStore,
            profile: any ProfileStore,
            prompts: PromptScheduler,
            ads: any AdBannerProvider,
            tunables: Tunables,
            clock: @escaping () -> Date
        ) {
            self.forecast = forecast
            self.location = location
            self.history = history
            self.profile = profile
            self.prompts = prompts
            self.ads = ads
            self.tunables = tunables
            self.clock = clock
        }

        /// The app came to the foreground.
        ///
        /// The forecast is refetched only when the cached one is missing or
        /// older than the fetch interval (R1): coming back to the app twice in a
        /// minute must not cost two requests. Then every planned session whose
        /// skin-check window has closed unanswered is discarded (R45), so a
        /// session the user planned and never did stops counting.
        public func didBecomeActive() async {
            let now = clock()
            let answer = await location.location(now: now)
            if let coordinate = answer.coordinate {
                lastCoordinate = coordinate
            }
            if await needsRefresh(now: now), let coordinate = lastCoordinate {
                _ = await forecast.current(for: coordinate, now: now)
            }
            if let zone = await forecast.cached().curve?.timeZone {
                forecastTimeZone = zone
            }
            _ = try? await history.discardPlanned(before: now)
        }

        /// Runs the ad network's consent flow where it is required, once per run
        /// and never before onboarding is done, and records that it was shown.
        /// The banners load once this has answered (R39).
        public func prepareAds() async {
            guard !adsPrepared, profile.flags().onboardingComplete else { return }
            adsPrepared = true
            _ = await ads.prepare(region: .none)
            if ads.requestConfiguration.consentShown {
                var flags = profile.flags()
                flags.adConsentDone = true
                profile.setFlags(flags)
            }
        }

        /// The destination a URL names, or nil when it names none.
        public func handle(_ url: URL) -> DeepLink? {
            DeepLink(url: url)
        }

        /// True when there is no cached curve at all, or the one on disk is
        /// older than the interval R1 fixes.
        private func needsRefresh(now: Date) async -> Bool {
            guard let curve = await forecast.cached().curve else { return true }
            return now.timeIntervalSince(curve.fetchedAt) >= tunables.fetchMinIntervalHours * 3600
        }

        // MARK: - Composed environments

        /// The environment the app runs on: WeatherKit behind the forecast
        /// service, the forecast cached in Application Support, CoreLocation with
        /// Apple's geocoder for manual entry, the SwiftData history, the profile
        /// in `UserDefaults`, the system notification centre, the AdMob banner
        /// for the ad unit and the privacy policy the app's Info.plist names.
        public static func live() -> AppEnvironment {
            let tunables = Tunables.current
            let profile = UserDefaultsProfileStore()
            let history = HistoryStore(
                persistence: livePersistence(),
                tunables: tunables,
                profileProvider: { profile.load() ?? AppEnvironment.startingProfile }
            )
            let environment = AppEnvironment(
                forecast: ForecastService(
                    provider: WeatherKitProvider(),
                    cache: FileForecastCache(directory: cacheDirectory()),
                    tunables: tunables
                ),
                location: LocationService(source: CoreLocationSource(), resolver: AppleGeocoder()),
                history: history,
                profile: profile,
                prompts: PromptScheduler(port: UserNotificationAdapter(), tunables: tunables),
                ads: IcarusAds.liveProvider(),
                tunables: tunables,
                clock: { Date() }
            )
            environment.weatherAttribution = { await WeatherKitProvider.attribution() }
            if let page = Bundle.main.object(forInfoDictionaryKey: "IcarusPrivacyPolicyURL") as? String {
                environment.privacyPolicyURL = URL(string: page)
            }
            return environment
        }

        /// What the preview starts with beyond the recorded forecast, so the
        /// screenshot walk can reach the screens a fresh, empty run never shows
        /// (screen review F11).
        public enum PreviewScenario: Sendable {
            /// Nothing on disk.
            case plain
            /// One logged session the day before, with no skin report yet: the
            /// skin check asks its questions and History has a past session.
            case sessionYesterday
            /// The forecast provider refuses every request and nothing is
            /// cached: the Result the phone shows without WeatherKit.
            case noForecast
        }

        /// The environment previews and UI tests run on: the recorded Oslo
        /// forecast, nothing on disk, notifications that are granted and go
        /// nowhere, no ads, and a clock that does not move. The privacy policy
        /// and Apple's weather credit are stand-ins, so Settings shows the rows
        /// the phone shows (screen review F12).
        ///
        /// `onboarded` starts it with the starting profile saved and onboarding
        /// done, for a UI test that begins past the first launch.
        public static func preview(onboarded: Bool = false, scenario: PreviewScenario = .plain) -> AppEnvironment {
            let tunables = Tunables.current
            guard let fixture = try? FakeForecastProvider.fixture(named: previewFixture) else {
                preconditionFailure("the preview fixture \(previewFixture) is missing from IcarusData")
            }
            let persistence = MemoryPersistence()
            if scenario == .sessionYesterday {
                try? persistence.replaceAll(History(sessions: [previewSessionYesterday()]))
            }
            let profile = MemoryProfileStore(profile: onboarded ? startingProfile : nil)
            if onboarded {
                var flags = profile.flags()
                flags.onboardingComplete = true
                flags.disclaimerAcknowledged = true
                profile.setFlags(flags)
            }
            let refusal: ProviderError? = scenario == .noForecast ? .unavailable("preview without a forecast") : nil
            let environment = AppEnvironment(
                forecast: ForecastService(
                    provider: FakeForecastProvider(fixture: fixture, failing: refusal),
                    cache: MemoryForecastCache(),
                    tunables: tunables
                ),
                location: LocationService(
                    source: FakeLocationSource(reading: .fix(oslo, accuracyKm: 1)),
                    resolver: FakePlaceResolver(table: [:])
                ),
                history: HistoryStore(
                    persistence: persistence, tunables: tunables, profileProvider: { startingProfile }
                ),
                profile: profile,
                prompts: PromptScheduler(port: FakeNotificationPort(authorization: .granted), tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { previewNow }
            )
            environment.privacyPolicyURL = URL(string: "https://example.com/privacy")
            // Apple's legal page, and a mark that never loads, so the row
            // shows its placeholder and the link as the phone does before
            // WeatherKit answers.
            environment.weatherAttribution = {
                WeatherAttribution(
                    legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
                    markLightURL: URL(fileURLWithPath: "/preview/no-mark.png"),
                    markDarkURL: URL(fileURLWithPath: "/preview/no-mark.png")
                )
            }
            return environment
        }

        /// Half an hour up and about in the early afternoon of the day before
        /// the preview clock's day, logged, on a flat UV index 6 day in Oslo.
        private static func previewSessionYesterday() -> SessionRecord {
            let zone = TimeZone(identifier: "Europe/Oslo") ?? TimeZone(secondsFromGMT: 7200)!
            let opens = previewNow.addingTimeInterval(-21 * 3600)
            let window = Window(start: opens, end: opens.addingTimeInterval(1800))
            let interval = [ExposureInterval(exposure: .upAndAbout, window: window)]
            let midnight = previewNow.addingTimeInterval(-33 * 3600)
            let curve = StoredCurve(
                hourly: (0 ... 24).map { HourlyUVI(time: midnight.addingTimeInterval(Double($0) * 3600), uvi: 6) },
                solarNoon: midnight.addingTimeInterval(11 * 3600 + 1200),
                timeZoneID: zone.identifier,
                location: oslo,
                fetchedAt: midnight.addingTimeInterval(6 * 3600)
            )
            return SessionRecord(
                day: DayKey(opens, timeZone: zone),
                createdAt: opens,
                plannedWindow: window,
                plannedIntervals: interval,
                firstSide: .faceUp,
                actualIntervals: interval,
                posture: .upAndAbout,
                coverHeadAndShoulders: false,
                intent: .bestMinutes,
                ceilingAtPlan: startingProfile.ceiling,
                state: .logged,
                dosePerRegion: [.front: 0.8, .back: 0.8, .headAndShoulders: 1.6],
                curveUsed: curve,
                forecastFetchedAt: curve.fetchedAt,
                forecastPlace: oslo
            )
        }

        /// The profile the app replays under before onboarding has saved one.
        /// Type III at the conservative setting: the middle band, planned short,
        /// so nothing is ever computed against a bolder profile than the user
        /// actually chose.
        nonisolated static let startingProfile = Profile(skinType: .iii, ceiling: .conservative)

        /// The recorded forecast the preview and the offline demo replay (S8).
        nonisolated static let previewFixture = "beach-oslo"

        nonisolated static let oslo = Coordinate(latitude: 59.9139, longitude: 10.7522)

        /// 2026-06-15T09:00:00Z — the morning of the recorded fixture's day.
        nonisolated static let previewNow = Date(timeIntervalSince1970: 1_781_514_000)

        private static func livePersistence() -> any HistoryPersistence {
            #if canImport(SwiftData)
                // A container that will not open is a device problem, not a
                // reason to lose the session the user is about to plan: the run
                // continues in memory and the next launch tries the disk again.
                if let store = try? SwiftDataPersistence.onDisk() {
                    return store
                }
            #endif
            return MemoryPersistence()
        }

        private static func cacheDirectory() -> URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            return base.appendingPathComponent("Icarus", isDirectory: true)
        }
    }
#endif
