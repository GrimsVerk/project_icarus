---
slug: data-layer
status: draft
created: 2026-09-02
design: M2 — Data
covers: [R1, R2, R3, R22, R25, R32, R37, R45]
format: pseudocode
---

# Data layer — Plan

## Summary

Everything that touches the outside world or the disk, behind protocols the
engine never sees: WeatherKit and a fake provider, location with manual entry,
the forecast cache at R1's cadence, one history store over a persistence
protocol whose state is only ever replayed, JSON export and import that carry
the profile and reproduce every figure from the intervals actually faced, and
the prompt scheduler keyed by the day's zone-carrying id. Revision 3 lands the
second tactical pass.

Non-goals:
- We do NOT compute doses or targets; every number comes from IcarusCore.
- We do NOT show anything; views are M3+.
- We do NOT call WeatherKit for real in CI; the entitlement and signing are M7.

Owner costs:
- None until M7 (the WeatherKit capability needs the developer membership).

Rulings: D-2026-09-03-F1, F5 (docs/DECISIONS.md); design revisions 2 and 3 for derived state and prompts

## The slices

## Slice 1 — A forecast, from WeatherKit or a fake, cached on disk at the ruled cadence, with the failure named

- **Delivers:** `ForecastService.current(for:now:)` returns a `ForecastCurve` (with the location's time zone) for a coordinate: from the cache when it is within the hour and within 10 km, else fetched through the provider; every failure is named (provider, malformed, cache unreadable), never masked as "offline"; the cache survives relaunch; the fake provider replays recorded fixtures so the engine runs end to end with no network.
- **Files:** `Sources/IcarusData/UVForecastProvider.swift`, `Sources/IcarusData/WeatherKitProvider.swift`, `Sources/IcarusData/FakeForecastProvider.swift`, `Sources/IcarusData/ForecastCache.swift`, `Sources/IcarusData/ForecastService.swift`, `Tests/IcarusDataTests/ForecastServiceTests.swift`, `Tests/IcarusDataTests/Fixtures/weatherkit-response.json`
- **Estimate:** ~440 lines

### Signatures

```text
public protocol UVForecastProvider: Sendable {
    func forecast(at: Coordinate, days: Int) async throws(ProviderError) -> ProviderForecast
    var name: String { get }
}
public enum ProviderError: Error, Sendable, Equatable { case unavailable(String), unauthorized, network(String) }
public struct ProviderForecast: Codable, Sendable { public let hourly: [HourlyUVI]; public let solarNoon: [DayKey: Date]; public let timeZone: TimeZone; public let horizonDays: Int }
public struct WeatherKitProvider: UVForecastProvider { public init() }      // location's zone from a reverse geocode, cached per coordinate
public struct FakeForecastProvider: UVForecastProvider {
    public init(fixture: ProviderForecast, delay: Duration = .zero, failing: ProviderError? = nil, malformed: Bool = false)
    public static func fixture(named: String) throws -> ProviderForecast
}
public struct CachedForecast: Codable, Sendable { public let curve: ForecastCurve; public let providerName: String }
public protocol ForecastCacheStore: Sendable { func load() throws -> CachedForecast?; func save(_: CachedForecast) throws }
public struct FileForecastCache: ForecastCacheStore { public init(directory: URL) }
public struct MemoryForecastCache: ForecastCacheStore { public init() }
public enum ForecastFailure: Error, Sendable, Equatable { case provider(ProviderError), malformed(ForecastCurveError), cacheUnreadable(String)
    public var kind: ForecastFailureKind }
public enum CacheReason: Sendable, Equatable { case withinInterval, providerFailed(ForecastFailure) }
public enum ForecastResult: Sendable { case fresh(ForecastCurve), cached(ForecastCurve, reason: CacheReason), none(ForecastFailure)
    public var curve: ForecastCurve?; public var failure: ForecastFailure? }
public actor ForecastService {
    public init(provider: any UVForecastProvider, cache: any ForecastCacheStore, tunables: Tunables)
    public func current(for location: Coordinate, now: Date, force: Bool = false) async -> ForecastResult
    public func cached() -> ForecastResult     // never fetches
}
// Promises (S8): as revision 2 — cadence, named failures, malformed never reported as provider, corrupt cache → current() still fetches and cached() → .none(.cacheUnreadable), round-trip, fixture mapping
```

### Internals

```text
current(location, now, force): c = try? cache.load(); within interval and distance → .cached(.withinInterval); else fetch; provider error → .provider; curve error → .malformed; return .cached(_, .providerFailed(f)) if c else .none(f)
WeatherKitProvider under `#if canImport(WeatherKit)`; FileForecastCache: JSON temp + rename
```

## Slice 2 — Location: device, or a typed place, with distance from the cache

- **Delivers:** `LocationService` yields the device coordinate at kilometre accuracy with when-in-use permission, reports denial, resolves a typed place name through the geocoder, and tells the engine how far the device is from the cached forecast's place.
- **Files:** `Sources/IcarusData/LocationService.swift`, `Sources/IcarusData/Geocoder.swift`, `Tests/IcarusDataTests/LocationServiceTests.swift`
- **Estimate:** ~260 lines

### Signatures

```text
public protocol LocationSource: Sendable { func current() async -> LocationReading }
public enum LocationReading: Sendable, Equatable { case fix(Coordinate, accuracyKm: Double), denied, unavailable }
public protocol PlaceResolver: Sendable { func resolve(_ text: String) async throws -> [Place] }
public struct Place: Sendable, Equatable, Codable { public let name: String; public let coordinate: Coordinate; public let timeZone: TimeZone }
public struct CoreLocationSource: LocationSource { public init() }
public struct AppleGeocoder: PlaceResolver { public init() }
public struct FakeLocationSource: LocationSource { public init(reading: LocationReading) }
public struct FakePlaceResolver: PlaceResolver { public init(table: [String: [Place]]) }
public actor LocationService {
    public init(source: any LocationSource, resolver: any PlaceResolver)
    public func location(now: Date) async -> LocationAnswer
    public func useManual(_ place: Place); public func clearManual()
}
public enum LocationAnswer: Sendable, Equatable { case device(Coordinate), manual(Place), needsManual(reason: LocationReading); public var coordinate: Coordinate? }
// Promises (S8): denied → .needsManual(.denied) with coordinate nil; after useManual → .manual regardless of device; resolve("Nice") through the fake returns the fixture place with its zone
```

### Internals

```text
location(now): manual set → .manual; r = await source.current(); .fix → .device; else .needsManual(r)
CoreLocationSource: CLLocationManager + continuation; one-shot; 10 s timeout → .unavailable; AppleGeocoder: placemark.timeZone ?? .current; `#if canImport(CoreLocation)`
```

## Slice 3 — One history store, replayed state, export and import that carry the profile

- **Delivers:** `HistoryStore` is one actor over a `HistoryPersistence` protocol (SwiftData on Apple platforms, memory everywhere); it upserts planned sessions with the prescribed pair, logs them from the intervals actually faced (a logged session may be updated in place, which is what the timer's stop does), discards stale planned ones, adds reports and returns their calibration effect from the replay, records lasting colour with its timestamp (refusing a day with no report), exposes derived state invalidated by every write and by a profile change, exports the full history with stored curves and the profile, imports atomically and reports the profile the file carried, and deletes everything. A result recomputed from an exported lying session stopped before its flip matches its stored doses.
- **Files:** `Sources/IcarusData/Store/HistoryPersistence.swift`, `Sources/IcarusData/Store/SwiftDataPersistence.swift`, `Sources/IcarusData/Store/MemoryPersistence.swift`, `Sources/IcarusData/Store/SessionEntity.swift`, `Sources/IcarusData/Store/ReportEntity.swift`, `Sources/IcarusData/HistoryStore.swift`, `Sources/IcarusData/ExportService.swift`, `Tests/IcarusDataTests/HistoryStoreTests.swift`, `Tests/IcarusDataTests/ExportServiceTests.swift`
- **Estimate:** ~580 lines

### Signatures

```text
public protocol HistoryPersistence: Sendable {
    func load() throws -> History
    func replaceAll(_ h: History) throws              // atomic: all or nothing
    func upsertSession(_ s: SessionRecord) throws; func upsertReport(_ r: SkinReport) throws
}
public struct MemoryPersistence: HistoryPersistence { public init() }
public struct SwiftDataPersistence: HistoryPersistence { public init(container: ModelContainer) }   // `#if canImport(SwiftData)`
public enum HistoryError: Error, Sendable, Equatable { case noReport(DayKey), alreadyReported(DayKey), unknownSession(UUID), discarded(UUID) }
public actor HistoryStore {
    public init(persistence: any HistoryPersistence, tunables: Tunables, profileProvider: @Sendable () -> Profile)
    public static func inMemory(tunables:, profile:) -> HistoryStore
    public func history() throws -> History
    public func state(now: Date) throws -> DerivedState                       // Replay under (history, tunables, profileProvider()); memo keyed by all four
    public func invalidate()
    public func upsertPlanned(_ s: SessionRecord, replacing id: UUID?) throws -> UUID
    public func log(_ id: UUID, actual: [ExposureInterval], sunscreen: SunscreenChoice?, doses: [Region: SED], factors: [Region: Double], targets: [Region: SED]) throws
        // .planned → .logged; .logged → updated in place (the timer's stop); .discarded → throws .discarded
    public func discard(_ id: UUID) throws
    public func discardPlanned(before cutoff: Date) throws -> Int
    public func plannedSessions(on: DayKey) throws -> [SessionRecord]; public func sessions(on: DayKey) throws -> [SessionRecord]
    public func addReport(_ r: SkinReport) throws -> CalibrationEffect
    public func setLastingColour(day: DayKey, _ lc: LastingColour, at: Date) throws
    public func deleteAll() throws
    public func totals(now: Date) throws -> Totals
}
public struct Totals: Sendable, Equatable { public let week: [Region: SED]; public let cycle: [Region: SED] }
public struct ExportFile: Codable, Sendable { public let formatVersion: Int; public let tunablesVersion: String; public let profile: Profile; public let history: History; public let exportedAt: Date }
public struct ImportSummary: Sendable, Equatable { public let sessions: Int; public let reports: Int; public let tunablesVersion: String; public let profile: Profile }
public enum ExportService {
    public static func export(store:, profile:, now:) async throws -> Data
    public static func `import`(_ data: Data, into store:) async throws -> ImportSummary
    public static func reproduce(_ s: SessionRecord, tunables:) throws -> [Region: SED]
        // attenuated(Σ over actualIntervals of dose(i.exposure, cover, over i.window, curve: s.curveUsed.curve()), s.sunscreen, cover) — no state needed
}
// Promises (S10): as revision 2, plus: log on a .logged session updates in place and state(now) reflects it; log on a .discarded → .discarded;
//  reproduce(lying session stopped before the flip, one interval) == its stored doses within 1e-6; the export's JSON has "dosePerRegion" as an object;
//  upsertPlanned stores prescribedSunscreen and plannedIntervals
```

### Internals

```text
state memo key: (history hash, tunables.version, DayKey(now, lastSessionZone).id, profileProvider()); invalidate on every write
log(id, actual, …): entity = fetch; guard state != .discarded; set actualIntervals, sunscreen, doses, factorsShown, targetsShown, state .logged
discardPlanned(before): every .planned with plannedWindow.end + inAppSkinCheckWindowHours.upperBound < cutoff → .discarded
export: ExportFile(1, …) → JSONEncoder(iso8601, sortedKeys); import: decode, validate every record (intervals ordered, doses ≥ 0, curves decode), replaceAll; summary.profile
```

## Slice 4 — Prompts: one skin check per session day, lasting colour after a report, in-app fallbacks, timer alerts

- **Delivers:** `PromptScheduler` schedules one skin-check notification about 20 h after the day's last planned-or-logged session, keyed by the day's zone-carrying id, reschedules as sessions are added, cancels when the day's last session is discarded, schedules the lasting-colour notification only when a report is added, reports which session days are due for the in-app fallback windows, and schedules the flip timer's side-end, reapplication, and session-end alerts.
- **Files:** `Sources/IcarusData/PromptScheduler.swift`, `Sources/IcarusData/NotificationCenterAdapter.swift`, `Tests/IcarusDataTests/PromptSchedulerTests.swift`
- **Estimate:** ~340 lines

### Signatures

```text
public protocol NotificationPort: Sendable { func authorization() async -> NotificationAuthorization; func schedule(_ n: PendingNotification) async; func cancel(idPrefix: String) async; func pending() async -> [PendingNotification] }
public enum NotificationAuthorization: Sendable, Equatable { case granted, denied, notDetermined }
public struct PendingNotification: Sendable, Equatable { public let id: String; public let fireAt: Date; public let kind: NotificationKind }
public enum NotificationKind: Sendable, Equatable { case skinCheck(DayKey), lastingColour(DayKey), timerSideEnd, timerReapply(Int), timerSessionEnd }
public struct UserNotificationAdapter: NotificationPort { public init() }
public actor FakeNotificationPort: NotificationPort { public init(authorization: NotificationAuthorization) }
public actor PromptScheduler {
    public init(port: any NotificationPort, tunables: Tunables)
    public func sessionsChanged(on day: DayKey, lastSessionEnd: Date?) async
    public func reportAdded(on day: DayKey, at: Date) async
    public func scheduleTimer(sideEnd: Date?, reapply: [Date], sessionEnd: Date) async; public func cancelTimer() async
    public func dueInApp(history: History, now: Date) -> [DuePrompt]
    public static func day(fromNotificationID: String) -> DayKey?       // "skin-<day.id>" / "colour-<day.id>" → DayKey(id:); nil if malformed
}
public enum DuePrompt: Sendable, Equatable { case skinCheck(DayKey), lastingColour(DayKey) }
// Promises (S10): as revision 2, plus: the pending skinCheck id == "skin-" + day.id and day(fromNotificationID:) round-trips it for a DayKey in Europe/Oslo on a UTC host
```

### Internals

```text
ids: "skin-\(day.id)", "colour-\(day.id)", "timer-side", "timer-reapply-<i>", "timer-end"
dueInApp windows as revision 2; UserNotificationAdapter under `#if canImport(UserNotifications)`
```
