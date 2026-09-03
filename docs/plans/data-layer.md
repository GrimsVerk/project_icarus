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
the forecast cache at R1's cadence, the SwiftData history whose state is only
ever replayed, JSON export and import that reproduce every figure, and the
prompt scheduler. Tests run on macOS against the fake provider and an in-memory
store; no live WeatherKit before the owner's S8 check.

Non-goals:
- We do NOT compute doses or targets; every number comes from IcarusCore.
- We do NOT show anything; views are M3+.
- We do NOT call WeatherKit for real in CI; the entitlement and signing are M7.

Owner costs:
- None until M7 (the WeatherKit capability needs the developer membership).

Rulings: D-2026-09-03-F1, F5 (docs/DECISIONS.md); design revisions 2 and 3 for derived state and prompts

## The slices

## Slice 1 — A forecast, from WeatherKit or a fake, cached on disk at the ruled cadence

- **Delivers:** `ForecastService.current(for:now:)` returns a `ForecastCurve` for a coordinate: from the cache when it is within the hour and within 10 km, else fetched through the provider; the cache survives relaunch with location, fetch time, horizon and solar noon; the fake provider replays recorded fixtures so the engine runs end to end with no network.
- **Files:** `Sources/IcarusData/UVForecastProvider.swift`, `Sources/IcarusData/WeatherKitProvider.swift`, `Sources/IcarusData/FakeForecastProvider.swift`, `Sources/IcarusData/ForecastCache.swift`, `Sources/IcarusData/ForecastService.swift`, `Tests/IcarusDataTests/ForecastServiceTests.swift`, `Tests/IcarusDataTests/Fixtures/weatherkit-response.json`
- **Estimate:** ~420 lines

### Signatures

```text
public protocol UVForecastProvider: Sendable {
    func forecast(at: Coordinate, days: Int) async throws -> ProviderForecast   // days = forecastHorizonDays
    var name: String { get }
}
public struct ProviderForecast: Codable, Sendable { public let hourly: [HourlyUVI]; public let solarNoon: [DayKey: Date]; public let horizonDays: Int }
public struct HourlyUVI: Codable, Sendable, Equatable { public let time: Date; public let uvi: UVI }
public struct WeatherKitProvider: UVForecastProvider { public init() }
    // maps WeatherService.shared.weather(for:including: .hourly, .daily) → hourly uvIndex.value, daily sun.solarNoon
    // throws ProviderError.unavailable(underlying) ; never called in tests
public struct FakeForecastProvider: UVForecastProvider {
    public init(fixture: ProviderForecast, delay: Duration = .zero, failing: Bool = false)
    public static func fixture(named: String) throws -> ProviderForecast   // loads Tests fixtures / preview bundle
}
public struct CachedForecast: Codable, Sendable { public let curve: ForecastCurve; public let providerName: String }
public protocol ForecastCacheStore: Sendable { func load() throws -> CachedForecast?; func save(_: CachedForecast) throws }
public struct FileForecastCache: ForecastCacheStore { public init(directory: URL) }     // JSON file, atomic write
public struct MemoryForecastCache: ForecastCacheStore { public init() }
public actor ForecastService {
    public init(provider: any UVForecastProvider, cache: any ForecastCacheStore, tunables: Tunables)
    public func current(for location: Coordinate, now: Date, force: Bool = false) async -> ForecastResult
    public func cached() -> CachedForecast?
}
public enum ForecastResult: Sendable { case fresh(ForecastCurve), cached(ForecastCurve, reason: CacheReason), none(ProviderError?) }
public enum CacheReason: Sendable, Equatable { case withinInterval, offline }

// Promises (S8):
//  two calls 30 min apart, same place → one provider call; a 10.1 km move → a second call; force → a call
//  provider failing → .cached(curve, .offline) if a cache exists, else .none(error)
//  round-trip through FileForecastCache preserves location, fetchedAt, horizonEnd, every sample, solarNoon per day
//  WeatherKit fixture JSON (recorded shape) → the same ForecastCurve the engine expects: hourly count == 24 × horizonDays, solarNoon per day present
```

### Internals

```text
ForecastService.current(location, now, force):
  c = cache.load()
  if !force, let c, now − c.curve.fetchedAt < fetchMinIntervalHours, c.curve.location.distanceKm(location) ≤ fetchMoveKm → .cached(c.curve, .withinInterval)
  do { p = try await provider.forecast(at: location, days: forecastHorizonDays)
       curve = try ForecastCurve(location, fetchedAt: now, hourly: p.hourly, solarNoon: p.solarNoon)
       cache.save(CachedForecast(curve, provider.name)); return .fresh(curve) }
  catch { if let c → .cached(c.curve, .offline) else .none(error as? ProviderError) }
WeatherKitProvider: `import WeatherKit` guarded by `#if canImport(WeatherKit)` so the target builds on Linux (provider absent there)
FileForecastCache: Codable JSON at directory/forecast.json; write to temp + rename
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
public struct Place: Sendable, Equatable, Codable { public let name: String; public let coordinate: Coordinate }
public struct CoreLocationSource: LocationSource { public init() }          // kCLLocationAccuracyKilometer, when-in-use
public struct AppleGeocoder: PlaceResolver { public init() }                // CLGeocoder.geocodeAddressString
public struct FakeLocationSource: LocationSource { public init(reading: LocationReading) }
public struct FakePlaceResolver: PlaceResolver { public init(table: [String: [Place]]) }
public actor LocationService {
    public init(source: any LocationSource, resolver: any PlaceResolver)
    public func location(now: Date) async -> LocationAnswer
    public func useManual(_ place: Place)
    public func clearManual()
}
public enum LocationAnswer: Sendable, Equatable { case device(Coordinate), manual(Place), needsManual(reason: LocationReading) }
// Promises (S8): denied → .needsManual(.denied); after useManual → .manual regardless of device; resolve("Nice") through the fake returns the fixture place
```

### Internals

```text
location(now): if manual set → .manual; r = await source.current(); .fix → .device; else .needsManual(r)
CoreLocationSource: CLLocationManager with a continuation; request when-in-use if notDetermined; one-shot; timeout 10 s → .unavailable
AppleGeocoder: CLGeocoder.geocodeAddressString(text) → map placemarks (name/locality, coordinate); `#if canImport(CoreLocation)`
```

## Slice 3 — The history store, replayed state, export and import

- **Delivers:** `HistoryStore` persists sessions and reports in SwiftData, exposes the ordered `History`, returns `DerivedState` only via `Replay` under the current Tunables (cached per launch and after every write), exports the full history with stored curves and the tunables version to one JSON file, imports it, and deletes everything behind the R44 warning contract. A result recomputed from an exported session's stored curve matches its stored doses.
- **Files:** `Sources/IcarusData/Store/SessionEntity.swift`, `Sources/IcarusData/Store/ReportEntity.swift`, `Sources/IcarusData/HistoryStore.swift`, `Sources/IcarusData/ExportService.swift`, `Tests/IcarusDataTests/HistoryStoreTests.swift`, `Tests/IcarusDataTests/ExportServiceTests.swift`
- **Estimate:** ~480 lines

### Signatures

```text
@Model final class SessionEntity { /* mirrors SessionRecord field for field; curveUsed stored as Data (JSON) */ }
@Model final class ReportEntity  { /* mirrors SkinReport */ }
public actor HistoryStore {
    public init(container: ModelContainer, tunables: Tunables, profileProvider: @Sendable () -> Profile)
    public static func inMemory(tunables:, profile:) throws -> HistoryStore
    public func history() throws -> History
    public func state(now: Date) throws -> DerivedState            // Replay.replay(history, profile, now, tunables); memoized until the next write
    public func addPlanned(_ s: SessionRecord) throws
    public func log(_ id: UUID, actual: Window, sunscreen: SunscreenChoice?, doses: [Region: SED], factors: [Region: Double], targets: [Region: SED]) throws
    public func discard(_ id: UUID) throws
    public func plannedSessions(on: DayKey) throws -> [SessionRecord]
    public func addReport(_ r: SkinReport) throws
    public func setLastingColour(day: DayKey, _ lc: LastingColour) throws
    public func deleteAll() throws                                  // the UI shows the R44 warning first; the store just deletes
    public func totals(now: Date) throws -> Totals                  // weekly and cycle-to-date per region, from the history
}
public struct Totals: Sendable, Equatable { public let week: [Region: SED]; public let cycle: [Region: SED] }
public struct ExportFile: Codable, Sendable { public let formatVersion: Int; public let tunablesVersion: String; public let profile: Profile; public let history: History; public let exportedAt: Date }
public enum ExportService {
    public static func export(store:, profile:, now:) async throws -> Data
    public static func `import`(_ data: Data, into store:) async throws -> ImportSummary   // replaces the history; refuses formatVersion > current
    public static func reproduce(_ s: SessionRecord, profile:, stateBefore: DerivedState, tunables:) -> [Region: SED]   // re-plans from s.curveUsed; used by S10
}
public struct ImportSummary: Sendable, Equatable { public let sessions: Int; public let reports: Int; public let tunablesVersion: String }

// Promises (S10):
//  state(now) after log then addReport equals Replay over history() — never a stored number
//  a Tunables change (different halfLife) followed by state(now) changes the result for the same history
//  export → import → history() equal and state equal; every session's curveUsed present
//  reproduce(session) == session.dosePerRegion within 1e-6
//  deleteAll → history() empty, state == DerivedState.initial
//  totals: week sums the last 7 days' logged doses per region; cycle sums since cycleStart per region
```

### Internals

```text
SwiftData models are storage only; mapping to/from Core value types in one file each; `#if canImport(SwiftData)` — on Linux the Data target compiles the protocol surface and an in-memory JSON-backed store used by tests there
HistoryStore.state: cache (history hash, tunables.version, DayKey(now)) → DerivedState; invalidate on every write
log(id …): fetch entity, set actual, sunscreen, doses, factorsShown, targetsShown, state = .logged; invalidate
ExportService.export: ExportFile(formatVersion 1, tunables.version, profile, history, now) → JSONEncoder (iso8601, sorted keys)
import: decode; guard formatVersion ≤ 1; store.replaceAll(history) ; return summary
reproduce: curve = ForecastCurve(from: s.curveUsed); Planner.plan(request rebuilt from s, state: stateBefore) → perRegionDose of the logged actual window (ExposureModel.dose per side over actual sub-intervals with the confirmed sunscreen)
```

## Slice 4 — Prompts: one skin check per session day, lasting colour, in-app fallbacks, timer alerts

- **Delivers:** `PromptScheduler` schedules one skin-check notification about 20 h after the day's last planned-or-logged session and one lasting-colour notification four days later, reschedules as sessions are added, cancels on discard, reports which session days are unanswered and due for the in-app fallback windows, and schedules the flip timer's side-end, reapplication, and session-end alerts; with notifications denied it reports so and the in-app path is the only one.
- **Files:** `Sources/IcarusData/PromptScheduler.swift`, `Sources/IcarusData/NotificationCenterAdapter.swift`, `Tests/IcarusDataTests/PromptSchedulerTests.swift`
- **Estimate:** ~330 lines

### Signatures

```text
public protocol NotificationPort: Sendable {
    func authorization() async -> NotificationAuthorization
    func schedule(_ n: PendingNotification) async
    func cancel(idPrefix: String) async
    func pending() async -> [PendingNotification]
}
public enum NotificationAuthorization: Sendable, Equatable { case granted, denied, notDetermined }
public struct PendingNotification: Sendable, Equatable { public let id: String; public let fireAt: Date; public let kind: NotificationKind }
public enum NotificationKind: Sendable, Equatable { case skinCheck(DayKey), lastingColour(DayKey), timerSideEnd, timerReapply(Int), timerSessionEnd }
public struct UserNotificationAdapter: NotificationPort { public init() }
public actor FakeNotificationPort: NotificationPort { public init(authorization: NotificationAuthorization) }
public actor PromptScheduler {
    public init(port: any NotificationPort, tunables: Tunables)
    public func sessionsChanged(on day: DayKey, lastSessionEnd: Date) async     // (re)schedule skinCheck day+20h, lastingColour +4d
    public func sessionDayDiscarded(_ day: DayKey) async                        // cancel both if no sessions remain that day
    public func scheduleTimer(sideEnd: Date?, reapply: [Date], sessionEnd: Date) async
    public func cancelTimer() async
    public func dueInApp(history: History, now: Date) -> [DuePrompt]           // unanswered days inside the in-app windows
}
public enum DuePrompt: Sendable, Equatable { case skinCheck(DayKey), lastingColour(DayKey) }
// Promises (S10): one planned + one logged session on a day → exactly one skinCheck at lastEnd+20h and one lastingColour at +4d;
//  adding a later session moves both; discarding the last session cancels both; denied → schedule is a no-op and dueInApp lists the day
//  from 12 h to 72 h after its last session; a lasting-colour day is due from 3 to 10 days; timer: sideEnd, N reapply, sessionEnd all pending
```

### Internals

```text
ids: "skin-<day>", "colour-<day>", "timer-side", "timer-reapply-<i>", "timer-end"
sessionsChanged: cancel(idPrefix "skin-<day>"), schedule(skinCheck at lastSessionEnd + skinCheckDelayHours); same for colour at + lastingColourDelayDays
dueInApp: for each day with any planned-or-logged session and no report: if now ∈ [lastEnd+12h, lastEnd+72h] → .skinCheck; for each day with a report and no lastingColour: if now ∈ [+3d, +10d] → .lastingColour
UserNotificationAdapter: UNUserNotificationCenter; category ids for the two prompts; `#if canImport(UserNotifications)`
```
