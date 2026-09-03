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
the profile and reproduce every figure, and the prompt scheduler. Revision 2
lands the tactical review.

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
public struct WeatherKitProvider: UVForecastProvider { public init() }
    // WeatherService.shared.weather(for:including: .hourly, .daily); timeZone from the placemark of the coordinate (CLGeocoder reverse, cached per coordinate) — the location's zone, not the device's
public struct FakeForecastProvider: UVForecastProvider {
    public init(fixture: ProviderForecast, delay: Duration = .zero, failing: ProviderError? = nil, malformed: Bool = false)
    public static func fixture(named: String) throws -> ProviderForecast
}
public struct CachedForecast: Codable, Sendable { public let curve: ForecastCurve; public let providerName: String }
public protocol ForecastCacheStore: Sendable { func load() throws -> CachedForecast?; func save(_: CachedForecast) throws }
public struct FileForecastCache: ForecastCacheStore { public init(directory: URL) }     // JSON file, atomic write
public struct MemoryForecastCache: ForecastCacheStore { public init() }
public enum ForecastFailure: Error, Sendable, Equatable { case provider(ProviderError), malformed(ForecastCurveError), cacheUnreadable(String)
    public var kind: ForecastFailureKind }
public enum CacheReason: Sendable, Equatable { case withinInterval, providerFailed(ForecastFailure) }
public enum ForecastResult: Sendable { case fresh(ForecastCurve), cached(ForecastCurve, reason: CacheReason), none(ForecastFailure)
    public var curve: ForecastCurve?; public var failure: ForecastFailure? }
public actor ForecastService {
    public init(provider: any UVForecastProvider, cache: any ForecastCacheStore, tunables: Tunables)
    public func current(for location: Coordinate, now: Date, force: Bool = false) async -> ForecastResult
    public func cached() -> ForecastResult     // .cached(curve, .withinInterval) or .none(.cacheUnreadable/…) — never fetches
}
// Promises (S8):
//  two calls 30 min apart, same place → one provider call; a 10.1 km move → a second call; force → a call
//  provider failing → .cached(curve, .providerFailed(.provider(e))) if a cache exists, else .none(.provider(e))
//  a one-sample response → .none(.malformed(.tooFewSamples)) with no cache, .cached(_, .providerFailed(.malformed(…))) with one — never .provider
//  a corrupt cache file → current() still fetches; cached() → .none(.cacheUnreadable)
//  round-trip preserves location, timeZone, fetchedAt, horizonEnd, every sample, solarNoon per day
//  the WeatherKit fixture → hourly count == 24 × horizonDays, solarNoon per day, timeZone == the fixture's
```

### Internals

```text
current(location, now, force):
  c = try? cache.load()   // an unreadable cache is logged as .cacheUnreadable in `cached()`; here it just means "no cache"
  if !force, let c, now − c.curve.fetchedAt < fetchMinIntervalHours, distance ≤ fetchMoveKm → .cached(c.curve, .withinInterval)
  do { p = try await provider.forecast(at, days: forecastHorizonDays); curve = try ForecastCurve(location, timeZone: p.timeZone, fetchedAt: now, hourly: p.hourly, solarNoon: p.solarNoon)
       try cache.save(…); return .fresh(curve) }
  catch let e as ProviderError { f = .provider(e) } catch let e as ForecastCurveError { f = .malformed(e) }
  return c != nil ? .cached(c.curve, .providerFailed(f)) : .none(f)
WeatherKitProvider under `#if canImport(WeatherKit)`; on Linux the type is absent and AppEnvironment.live is unavailable
FileForecastCache: Codable JSON at directory/forecast.json; temp + rename
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
public enum LocationAnswer: Sendable, Equatable { case device(Coordinate), manual(Place), needsManual(reason: LocationReading)
    public var coordinate: Coordinate? }
// Promises (S8): denied → .needsManual(.denied); after useManual → .manual regardless of device; resolve("Nice") through the fake returns the fixture place with its time zone
```

### Internals

```text
location(now): manual set → .manual; r = await source.current(); .fix → .device; else .needsManual(r)
CoreLocationSource: CLLocationManager + continuation; when-in-use if notDetermined; one-shot; 10 s timeout → .unavailable
AppleGeocoder: CLGeocoder.geocodeAddressString → placemarks (name/locality, coordinate, placemark.timeZone ?? .current); `#if canImport(CoreLocation)`
```

## Slice 3 — One history store, replayed state, export and import that carry the profile

- **Delivers:** `HistoryStore` is one actor over a `HistoryPersistence` protocol (SwiftData on Apple platforms, memory everywhere); it upserts planned sessions, logs them with the attenuated doses, discards stale planned ones, adds reports and returns their calibration effect from the replay, records lasting colour with its timestamp (refusing a day with no report), exposes derived state that is invalidated by every write and by a profile change, exports the full history with stored curves and the profile, imports atomically and reports the profile the file carried, and deletes everything. A result recomputed from an exported session's stored curve matches its stored doses.
- **Files:** `Sources/IcarusData/Store/HistoryPersistence.swift`, `Sources/IcarusData/Store/SwiftDataPersistence.swift`, `Sources/IcarusData/Store/MemoryPersistence.swift`, `Sources/IcarusData/Store/SessionEntity.swift`, `Sources/IcarusData/Store/ReportEntity.swift`, `Sources/IcarusData/HistoryStore.swift`, `Sources/IcarusData/ExportService.swift`, `Tests/IcarusDataTests/HistoryStoreTests.swift`, `Tests/IcarusDataTests/ExportServiceTests.swift`
- **Estimate:** ~560 lines

### Signatures

```text
public protocol HistoryPersistence: Sendable {
    func load() throws -> History
    func replaceAll(_ h: History) throws              // atomic: all or nothing
    func upsertSession(_ s: SessionRecord) throws; func upsertReport(_ r: SkinReport) throws
}
public struct MemoryPersistence: HistoryPersistence { public init() }
public struct SwiftDataPersistence: HistoryPersistence { public init(container: ModelContainer) }   // `#if canImport(SwiftData)`
public enum HistoryError: Error, Sendable, Equatable { case noReport(DayKey), alreadyReported(DayKey), unknownSession(UUID), notPlanned(UUID) }
public actor HistoryStore {
    public init(persistence: any HistoryPersistence, tunables: Tunables, profileProvider: @Sendable () -> Profile)
    public static func inMemory(tunables:, profile:) -> HistoryStore          // MemoryPersistence on every platform
    public func history() throws -> History
    public func state(now: Date) throws -> DerivedState                       // Replay under (history, tunables, profileProvider()); memo keyed by all four
    public func invalidate()                                                  // Settings calls this after any profile change
    public func upsertPlanned(_ s: SessionRecord, replacing id: UUID?) throws -> UUID
    public func log(_ id: UUID, actual: Window, sunscreen: SunscreenChoice?, doses: [Region: SED], factors: [Region: Double], targets: [Region: SED]) throws
    public func discard(_ id: UUID) throws
    public func discardPlanned(before cutoff: Date) throws -> Int             // planned sessions whose in-app skin-check window has closed
    public func plannedSessions(on: DayKey) throws -> [SessionRecord]
    public func sessions(on: DayKey) throws -> [SessionRecord]                // planned or logged
    public func addReport(_ r: SkinReport) throws -> CalibrationEffect         // throws .alreadyReported; effect from the replay the write triggers
    public func setLastingColour(day: DayKey, _ lc: LastingColour, at: Date) throws   // throws .noReport
    public func deleteAll() throws
    public func totals(now: Date) throws -> Totals
}
public struct Totals: Sendable, Equatable { public let week: [Region: SED]; public let cycle: [Region: SED] }
public struct ExportFile: Codable, Sendable { public let formatVersion: Int; public let tunablesVersion: String; public let profile: Profile; public let history: History; public let exportedAt: Date }
public struct ImportSummary: Sendable, Equatable { public let sessions: Int; public let reports: Int; public let tunablesVersion: String; public let profile: Profile }
public enum ExportService {
    public static func export(store:, profile:, now:) async throws -> Data
    public static func `import`(_ data: Data, into store:) async throws -> ImportSummary   // decode + validate fully, then replaceAll; a failure leaves the history untouched; refuses formatVersion > current
    public static func reproduce(_ s: SessionRecord, skinType:, stateBefore: DerivedState, tunables:) throws -> [Region: SED]   // re-plans from s.curveUsed with s's posture, cover, sides, actual window and confirmed sunscreen through ExposureModel.dose + attenuated
}
// Promises (S10):
//  state(now) after log then addReport equals Replay over history(); addReport returns the same effect Replay.effects holds for that report
//  a Tunables change followed by state(now) changes the result; invalidate() after a profile change changes state(now) without a write
//  upsertPlanned twice with the same replacing id → one planned session; discardPlanned(before:) removes planned sessions older than 72 h after their end
//  setLastingColour on a day with no report → .noReport; addReport twice on one day → .alreadyReported
//  export → import → history() equal, state equal, summary.profile == exported profile; a corrupt file → throws and history() unchanged
//  reproduce(session) == session.dosePerRegion within 1e-6 for a session logged with SPF 30 normal
//  deleteAll → history() empty, state == initial; totals: week = last 7 days, cycle = since cycleStart, per region
```

### Internals

```text
HistoryStore.state: key = (history hash, tunables.version, DayKey(now, lastSessionZone), profileProvider()) → (DerivedState, effects); invalidate on every write
addReport: guard no report that day; persist; recompute replay; return effects[r.id]
log(id, …): entity = fetch; guard .planned; set actual, sunscreen, doses, factorsShown, targetsShown, state .logged
discardPlanned(before): every .planned with plannedWindow.end + inAppSkinCheckWindowHours.upperBound < cutoff → .discarded
ExportService.export: ExportFile(1, tunables.version, profile, history, now) → JSONEncoder(iso8601, sortedKeys)
import: decode; guard formatVersion ≤ 1; validate every record (windows ordered, doses ≥ 0, curves decode); store.replaceAll(history); return summary(profile)
reproduce: curve = try s.curveUsed.curve(); sides from s.posture/firstSide/actualWindow via ExposureModel.dose(exposure, cover, over side window); attenuated(Σ, s.sunscreen, cover)
```

## Slice 4 — Prompts: one skin check per session day, lasting colour after a report, in-app fallbacks, timer alerts

- **Delivers:** `PromptScheduler` schedules one skin-check notification about 20 h after the day's last planned-or-logged session, reschedules as sessions are added, cancels when the day's last session is discarded, schedules the lasting-colour notification only when a report is added, reports which session days are due for the in-app fallback windows, and schedules the flip timer's side-end, reapplication, and session-end alerts; with notifications denied it reports so and the in-app path is the only one.
- **Files:** `Sources/IcarusData/PromptScheduler.swift`, `Sources/IcarusData/NotificationCenterAdapter.swift`, `Tests/IcarusDataTests/PromptSchedulerTests.swift`
- **Estimate:** ~340 lines

### Signatures

```text
public protocol NotificationPort: Sendable {
    func authorization() async -> NotificationAuthorization
    func schedule(_ n: PendingNotification) async; func cancel(idPrefix: String) async; func pending() async -> [PendingNotification]
}
public enum NotificationAuthorization: Sendable, Equatable { case granted, denied, notDetermined }
public struct PendingNotification: Sendable, Equatable { public let id: String; public let fireAt: Date; public let kind: NotificationKind }
public enum NotificationKind: Sendable, Equatable { case skinCheck(DayKey), lastingColour(DayKey), timerSideEnd, timerReapply(Int), timerSessionEnd }
public struct UserNotificationAdapter: NotificationPort { public init() }
public actor FakeNotificationPort: NotificationPort { public init(authorization: NotificationAuthorization) }
public actor PromptScheduler {
    public init(port: any NotificationPort, tunables: Tunables)
    public func sessionsChanged(on day: DayKey, lastSessionEnd: Date?) async   // nil → cancel the day's skin check; else (re)schedule at +20 h
    public func reportAdded(on day: DayKey, at: Date) async                    // schedules lastingColour at + lastingColourDelayDays
    public func scheduleTimer(sideEnd: Date?, reapply: [Date], sessionEnd: Date) async
    public func cancelTimer() async
    public func dueInApp(history: History, now: Date) -> [DuePrompt]
}
public enum DuePrompt: Sendable, Equatable { case skinCheck(DayKey), lastingColour(DayKey) }
// Promises (S10): one planned + one logged session on a day → exactly one skinCheck at lastEnd+20h; adding a later session moves it; sessionsChanged(nil) cancels it;
//  no lastingColour is pending until reportAdded; reportAdded → exactly one at +4 d; denied → schedule is a no-op and dueInApp lists the day
//  from 12 h to 72 h after its last planned-or-logged session; a reported day is due for colour from 3 to 10 days; timer: sideEnd (if any), N reapply, sessionEnd all pending
```

### Internals

```text
ids: "skin-<day>", "colour-<day>", "timer-side", "timer-reapply-<i>", "timer-end"
dueInApp: days with any planned-or-logged session and no report, now ∈ [lastEnd+12h, lastEnd+72h] → .skinCheck; days with a report and no lastingColour, now ∈ [reportedAt+3d, +10d] → .lastingColour
UserNotificationAdapter: UNUserNotificationCenter; `#if canImport(UserNotifications)`
```
