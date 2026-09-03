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
            _ = try? await history.discardPlanned(before: now)
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
        /// in `UserDefaults`, the system notification centre, and — until M7 —
        /// no ads at all.
        public static func live() -> AppEnvironment {
            let tunables = Tunables.current
            let profile = UserDefaultsProfileStore()
            let history = HistoryStore(
                persistence: livePersistence(),
                tunables: tunables,
                profileProvider: { profile.load() ?? AppEnvironment.startingProfile }
            )
            return AppEnvironment(
                forecast: ForecastService(
                    provider: WeatherKitProvider(),
                    cache: FileForecastCache(directory: cacheDirectory()),
                    tunables: tunables
                ),
                location: LocationService(source: CoreLocationSource(), resolver: AppleGeocoder()),
                history: history,
                profile: profile,
                prompts: PromptScheduler(port: UserNotificationAdapter(), tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { Date() }
            )
        }

        /// The environment previews and UI tests run on: the recorded Oslo
        /// forecast, nothing on disk, notifications that are granted and go
        /// nowhere, no ads, and a clock that does not move.
        public static func preview() -> AppEnvironment {
            let tunables = Tunables.current
            guard let fixture = try? FakeForecastProvider.fixture(named: previewFixture) else {
                preconditionFailure("the preview fixture \(previewFixture) is missing from IcarusData")
            }
            let profile = MemoryProfileStore(profile: nil)
            return AppEnvironment(
                forecast: ForecastService(
                    provider: FakeForecastProvider(fixture: fixture),
                    cache: MemoryForecastCache(),
                    tunables: tunables
                ),
                location: LocationService(
                    source: FakeLocationSource(reading: .fix(oslo, accuracyKm: 1)),
                    resolver: FakePlaceResolver(table: [:])
                ),
                history: HistoryStore.inMemory(tunables: tunables, profile: startingProfile),
                profile: profile,
                prompts: PromptScheduler(port: FakeNotificationPort(authorization: .granted), tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { previewNow }
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
