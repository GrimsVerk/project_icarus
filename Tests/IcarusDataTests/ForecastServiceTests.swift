// Slice 1 has one promise per test, and the recorded WeatherKit response is
// embedded here so the mapping test does not depend on the test target
// declaring resources. Splitting either out would put half of this slice's
// tests in a file the plan does not declare.
// swiftlint:disable file_length

import Foundation
import IcarusCore
import IcarusData
import XCTest

// MARK: - Fixtures

/// Deterministic fixtures for the forecast tests. Every instant is a fixed UTC
/// date; nothing here reads the wall clock.
private enum Fixture {
    static let oslo = Coordinate(latitude: 59.9, longitude: 10.75)
    static let osloZone = TimeZone(identifier: "Europe/Oslo")!

    /// About 10.1 km north of `oslo` — just past `fetchMoveKm`.
    static let farFromOslo = Coordinate(latitude: 59.9908, longitude: 10.75)

    /// About 5 km north of `oslo` — well inside `fetchMoveKm`.
    static let nearOslo = Coordinate(latitude: 59.945, longitude: 10.75)

    static let tunables = Tunables.current

    /// A fixed instant in UTC. Never derived from `Date()`.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }

    /// Midnight UTC on the fixtures' first day.
    static var start: Date { date(2026, 6, 15) }

    /// The working instant of most tests: 12:00 UTC on the first day.
    static var noon: Date { date(2026, 6, 15, 12) }

    /// `days` whole days of hourly samples in Oslo's zone: a hump peaking at
    /// UVI 7 at 11:00 UTC, with solar noon at 11:15 UTC every day.
    static func providerForecast(days: Int = 2) -> ProviderForecast {
        var hourly: [HourlyUVI] = []
        for index in 0 ..< (days * 24) {
            let time = start.addingTimeInterval(Double(index) * 3600)
            hourly.append(HourlyUVI(time: time, uvi: hump(hour: index % 24)))
        }
        var noons: [DayKey: Date] = [:]
        for index in 0 ..< days {
            let dayStart = start.addingTimeInterval(Double(index) * 86400)
            noons[DayKey(dayStart, timeZone: osloZone)] = dayStart.addingTimeInterval(11 * 3600 + 15 * 60)
        }
        return ProviderForecast(hourly: hourly, solarNoon: noons, timeZone: osloZone, horizonDays: days)
    }

    /// A forecast no curve can be built from: one sample is too few.
    static func tooFewSamples() -> ProviderForecast {
        ProviderForecast(hourly: [HourlyUVI(time: start, uvi: 1)],
                         solarNoon: [:],
                         timeZone: osloZone,
                         horizonDays: 1)
    }

    static func curve(fetchedAt: Date, at location: Coordinate = oslo, days: Int = 2) throws -> ForecastCurve {
        let forecast = providerForecast(days: days)
        return try ForecastCurve(location: location,
                                 timeZone: forecast.timeZone,
                                 fetchedAt: fetchedAt,
                                 hourly: forecast.hourly,
                                 solarNoon: forecast.solarNoon)
    }

    /// The local calendar day `index` days after the fixtures' first day.
    static func day(_ index: Int) -> DayKey {
        DayKey(start.addingTimeInterval(Double(index) * 86400), timeZone: osloZone)
    }

    static func hump(hour: Int) -> Double {
        Double(max(0, 7 - abs(hour - 11)))
    }
}

/// A provider that records what it was asked for. This mocks the network
/// boundary the `UVForecastProvider` protocol marks — never the service itself.
private actor CountingProvider: UVForecastProvider {
    nonisolated let name = "counting"

    private var asked: [(location: Coordinate, days: Int)] = []
    private let answer: Result<ProviderForecast, ProviderError>

    init(_ answer: Result<ProviderForecast, ProviderError>) {
        self.answer = answer
    }

    var callCount: Int { asked.count }
    var lastCoordinate: Coordinate? { asked.last?.location }
    var lastDays: Int? { asked.last?.days }

    func forecast(at location: Coordinate, days: Int) async throws(ProviderError) -> ProviderForecast {
        asked.append((location: location, days: days))
        switch answer {
        case let .success(forecast): return forecast
        case let .failure(error): throw error
        }
    }
}

// MARK: - Result readers

private func freshCurve(
    _ result: ForecastResult,
    file: StaticString = #filePath,
    line: UInt = #line
) -> ForecastCurve? {
    guard case let .fresh(curve) = result else {
        XCTFail("expected .fresh, got \(result)", file: file, line: line)
        return nil
    }
    return curve
}

private func cachedResult(
    _ result: ForecastResult,
    file: StaticString = #filePath,
    line: UInt = #line
) -> (curve: ForecastCurve, reason: CacheReason)? {
    guard case let .cached(curve, reason) = result else {
        XCTFail("expected .cached, got \(result)", file: file, line: line)
        return nil
    }
    return (curve, reason)
}

private func noneFailure(
    _ result: ForecastResult,
    file: StaticString = #filePath,
    line: UInt = #line
) -> ForecastFailure? {
    guard case let .none(failure) = result else {
        XCTFail("expected .none, got \(result)", file: file, line: line)
        return nil
    }
    return failure
}

private extension XCTestCase {
    /// A directory of this test's own, removed when the test ends.
    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("icarus-forecast-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func makeService(
        _ provider: any UVForecastProvider,
        _ cache: any ForecastCacheStore
    ) -> ForecastService {
        ForecastService(provider: provider, cache: cache, tunables: Fixture.tunables)
    }
}

// MARK: - Cadence (R1)

final class ForecastFetchCadenceTests: XCTestCase {
    func testTheFirstCallFetchesTheTunedHorizonForTheRequestedPlace() async {
        let provider = CountingProvider(.success(Fixture.providerForecast()))
        let service = makeService(provider, MemoryForecastCache())

        let result = await service.current(for: Fixture.oslo, now: Fixture.noon)

        XCTAssertNotNil(freshCurve(result))
        let calls = await provider.callCount
        let days = await provider.lastDays
        let coordinate = await provider.lastCoordinate
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(days, Fixture.tunables.forecastHorizonDays)
        XCTAssertEqual(coordinate, Fixture.oslo)
    }

    func testASecondCallHalfAnHourLaterAtTheSamePlaceDoesNotFetch() async {
        let provider = CountingProvider(.success(Fixture.providerForecast()))
        let service = makeService(provider, MemoryForecastCache())

        _ = await service.current(for: Fixture.oslo, now: Fixture.noon)
        let second = await service.current(for: Fixture.oslo, now: Fixture.noon.addingTimeInterval(30 * 60))

        guard let (curve, reason) = cachedResult(second) else { return }
        XCTAssertEqual(reason, .withinInterval)
        XCTAssertEqual(curve.fetchedAt, Fixture.noon)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 1)
    }

    func testACallAFullHourLaterFetchesAgain() async {
        let provider = CountingProvider(.success(Fixture.providerForecast()))
        let service = makeService(provider, MemoryForecastCache())
        let later = Fixture.noon.addingTimeInterval(Fixture.tunables.fetchMinIntervalHours * 3600)

        _ = await service.current(for: Fixture.oslo, now: Fixture.noon)
        let second = await service.current(for: Fixture.oslo, now: later)

        guard let curve = freshCurve(second) else { return }
        XCTAssertEqual(curve.fetchedAt, later)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 2)
    }

    func testAMoveOfMoreThanTenKilometresFetchesAgainWithinTheHour() async {
        XCTAssertGreaterThan(Fixture.farFromOslo.distanceKm(to: Fixture.oslo), Fixture.tunables.fetchMoveKm)
        XCTAssertLessThan(Fixture.farFromOslo.distanceKm(to: Fixture.oslo), 10.2)
        let provider = CountingProvider(.success(Fixture.providerForecast()))
        let service = makeService(provider, MemoryForecastCache())

        _ = await service.current(for: Fixture.oslo, now: Fixture.noon)
        let second = await service.current(for: Fixture.farFromOslo,
                                           now: Fixture.noon.addingTimeInterval(30 * 60))

        guard let curve = freshCurve(second) else { return }
        XCTAssertEqual(curve.location, Fixture.farFromOslo)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 2)
    }

    func testAMoveOfLessThanTenKilometresStaysOnTheCache() async {
        XCTAssertLessThan(Fixture.nearOslo.distanceKm(to: Fixture.oslo), Fixture.tunables.fetchMoveKm)
        let provider = CountingProvider(.success(Fixture.providerForecast()))
        let service = makeService(provider, MemoryForecastCache())

        _ = await service.current(for: Fixture.oslo, now: Fixture.noon)
        let second = await service.current(for: Fixture.nearOslo,
                                           now: Fixture.noon.addingTimeInterval(30 * 60))

        guard let (curve, reason) = cachedResult(second) else { return }
        XCTAssertEqual(reason, .withinInterval)
        XCTAssertEqual(curve.location, Fixture.oslo)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 1)
    }

    func testForceFetchesEvenInsideTheIntervalAtTheSamePlace() async {
        let provider = CountingProvider(.success(Fixture.providerForecast()))
        let service = makeService(provider, MemoryForecastCache())
        let aMinuteLater = Fixture.noon.addingTimeInterval(60)

        _ = await service.current(for: Fixture.oslo, now: Fixture.noon)
        let second = await service.current(for: Fixture.oslo, now: aMinuteLater, force: true)

        guard let curve = freshCurve(second) else { return }
        XCTAssertEqual(curve.fetchedAt, aMinuteLater)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 2)
    }

    func testASuccessfulFetchIsSavedAndSurvivesARelaunch() async throws {
        let directory = try makeTemporaryDirectory()
        let fetching = CountingProvider(.success(Fixture.providerForecast()))
        let first = makeService(fetching, FileForecastCache(directory: directory))
        _ = await first.current(for: Fixture.oslo, now: Fixture.noon)

        // A new service over a new cache on the same directory: the app relaunched.
        let offline = CountingProvider(.failure(.network("no network")))
        let second = makeService(offline, FileForecastCache(directory: directory))
        let result = await second.current(for: Fixture.oslo, now: Fixture.noon.addingTimeInterval(10 * 60))

        guard let (curve, reason) = cachedResult(result) else { return }
        XCTAssertEqual(reason, .withinInterval)
        XCTAssertEqual(curve.fetchedAt, Fixture.noon)
        XCTAssertEqual(curve.hourly, Fixture.providerForecast().hourly)
        let calls = await offline.callCount
        XCTAssertEqual(calls, 0)
    }

    func testTheSavedForecastRecordsTheProviderItCameFrom() async throws {
        let directory = try makeTemporaryDirectory()
        let provider = CountingProvider(.success(Fixture.providerForecast()))
        let service = makeService(provider, FileForecastCache(directory: directory))

        _ = await service.current(for: Fixture.oslo, now: Fixture.noon)

        let stored = try XCTUnwrap(FileForecastCache(directory: directory).load())
        XCTAssertEqual(stored.providerName, provider.name)
        XCTAssertEqual(stored.curve.fetchedAt, Fixture.noon)
    }
}

// MARK: - The curve the service builds

final class ForecastCurveFromProviderTests: XCTestCase {
    func testTheFreshCurveIsForTheRequestedPlaceAtTheGivenInstantInTheProvidersZone() async {
        let provider = CountingProvider(.success(Fixture.providerForecast()))
        let service = makeService(provider, MemoryForecastCache())

        let result = await service.current(for: Fixture.oslo, now: Fixture.noon)

        guard let curve = freshCurve(result) else { return }
        XCTAssertEqual(curve.location, Fixture.oslo)
        XCTAssertEqual(curve.timeZone, Fixture.osloZone)
        XCTAssertEqual(curve.fetchedAt, Fixture.noon)
    }

    func testTheFreshCurveKeepsEverySampleAndTheSolarNoonOfEachDay() async {
        let forecast = Fixture.providerForecast(days: 2)
        let provider = CountingProvider(.success(forecast))
        let service = makeService(provider, MemoryForecastCache())

        let result = await service.current(for: Fixture.oslo, now: Fixture.noon)

        guard let curve = freshCurve(result) else { return }
        XCTAssertEqual(curve.hourly, forecast.hourly)
        XCTAssertEqual(curve.horizonEnd, forecast.hourly.last?.time)
        XCTAssertEqual(curve.solarNoon(on: Fixture.day(0)), Fixture.date(2026, 6, 15, 11, 15))
        XCTAssertEqual(curve.solarNoon(on: Fixture.day(1)), Fixture.date(2026, 6, 16, 11, 15))
    }
}

// MARK: - Named failures (R37)

final class ForecastFailureTests: XCTestCase {
    func testAProviderFailureWithACacheReturnsTheCachedCurveNamingTheProviderFailure() async throws {
        let store = MemoryForecastCache()
        let stale = Fixture.date(2026, 6, 15, 9)
        try store.save(CachedForecast(curve: Fixture.curve(fetchedAt: stale), providerName: "recorded"))
        let provider = CountingProvider(.failure(.network("no network")))
        let service = makeService(provider, store)

        let result = await service.current(for: Fixture.oslo, now: Fixture.noon)

        guard let (curve, reason) = cachedResult(result) else { return }
        XCTAssertEqual(reason, .providerFailed(.provider(.network("no network"))))
        XCTAssertEqual(curve.fetchedAt, stale)
        XCTAssertNotNil(result.curve)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 1)
    }

    func testAProviderFailureWithNoCacheIsReturnedByNameAndNotMaskedAsOffline() async {
        let provider = CountingProvider(.failure(.unauthorized))
        let service = makeService(provider, MemoryForecastCache())

        let result = await service.current(for: Fixture.oslo, now: Fixture.noon)

        guard let failure = noneFailure(result) else { return }
        XCTAssertEqual(failure, .provider(.unauthorized))
        XCTAssertEqual(result.failure, .provider(.unauthorized))
        XCTAssertNil(result.curve)
        guard case .provider = failure.kind else {
            return XCTFail("a provider failure should have the .provider kind")
        }
    }

    func testAForecastTheCurveCannotBeBuiltFromIsMalformedNotAProviderFailure() async {
        let provider = CountingProvider(.success(Fixture.tooFewSamples()))
        let service = makeService(provider, MemoryForecastCache())

        let result = await service.current(for: Fixture.oslo, now: Fixture.noon)

        guard let failure = noneFailure(result) else { return }
        XCTAssertEqual(failure, .malformed(.tooFewSamples))
        if case .provider = failure {
            XCTFail("a malformed forecast must never be reported as a provider failure")
        }
        guard case .malformed = failure.kind else {
            return XCTFail("a malformed forecast should have the .malformed kind")
        }
    }

    func testTheFakeProvidersMalformedFixtureIsReportedAsMalformed() async {
        let provider = FakeForecastProvider(fixture: Fixture.providerForecast(), malformed: true)
        let service = makeService(provider, MemoryForecastCache())

        let result = await service.current(for: Fixture.oslo, now: Fixture.noon)

        guard let failure = noneFailure(result) else { return }
        if case .provider = failure {
            XCTFail("a malformed forecast must never be reported as a provider failure")
        }
        guard case .malformed = failure.kind else {
            return XCTFail("a malformed forecast should have the .malformed kind")
        }
    }

    func testAnUnreadableCacheIsNamedByCachedAndDoesNotStopCurrentFromFetching() async throws {
        let directory = try makeTemporaryDirectory()
        try Data("this is not a forecast".utf8)
            .write(to: directory.appendingPathComponent("forecast.json"))
        let provider = CountingProvider(.success(Fixture.providerForecast()))
        let service = makeService(provider, FileForecastCache(directory: directory))

        let stored = await service.cached()
        guard let failure = noneFailure(stored) else { return }
        if case .cacheUnreadable = failure {} else {
            XCTFail("an unreadable cache should be reported as .cacheUnreadable, got \(failure)")
        }
        guard case .cacheUnreadable = failure.kind else {
            return XCTFail("an unreadable cache should have the .cacheUnreadable kind")
        }
        XCTAssertNil(stored.curve)
        let beforeFetching = await provider.callCount
        XCTAssertEqual(beforeFetching, 0)

        let result = await service.current(for: Fixture.oslo, now: Fixture.noon)
        XCTAssertNotNil(freshCurve(result))
        let afterFetching = await provider.callCount
        XCTAssertEqual(afterFetching, 1)
    }

    func testCachedReadsTheStoreAndNeverFetches() async throws {
        let store = MemoryForecastCache()
        try store.save(CachedForecast(curve: Fixture.curve(fetchedAt: Fixture.noon), providerName: "recorded"))
        let provider = CountingProvider(.success(Fixture.providerForecast()))
        let service = makeService(provider, store)

        let result = await service.cached()

        XCTAssertEqual(result.curve?.fetchedAt, Fixture.noon)
        XCTAssertEqual(result.curve?.location, Fixture.oslo)
        let calls = await provider.callCount
        XCTAssertEqual(calls, 0)
    }
}

// MARK: - The cache on disk (R25)

final class ForecastCacheStoreTests: XCTestCase {
    func testAForecastRoundTripsThroughTheFileCacheAcrossInstances() throws {
        let directory = try makeTemporaryDirectory()
        let curve = try Fixture.curve(fetchedAt: Fixture.noon)
        try FileForecastCache(directory: directory)
            .save(CachedForecast(curve: curve, providerName: "recorded"))

        let loaded = try XCTUnwrap(FileForecastCache(directory: directory).load())

        XCTAssertEqual(loaded.providerName, "recorded")
        XCTAssertEqual(loaded.curve.location, curve.location)
        XCTAssertEqual(loaded.curve.timeZone, curve.timeZone)
        XCTAssertEqual(loaded.curve.fetchedAt, curve.fetchedAt)
        XCTAssertEqual(loaded.curve.horizonEnd, curve.horizonEnd)
        XCTAssertEqual(loaded.curve.hourly, curve.hourly)
        XCTAssertEqual(loaded.curve.solarNoon(on: Fixture.day(0)), curve.solarNoon(on: Fixture.day(0)))
        XCTAssertEqual(loaded.curve.solarNoon(on: Fixture.day(1)), curve.solarNoon(on: Fixture.day(1)))
    }

    func testTheFileCacheHoldsNothingBeforeAnythingIsSaved() throws {
        let directory = try makeTemporaryDirectory()

        XCTAssertNil(try FileForecastCache(directory: directory).load())
    }

    func testASecondSaveReplacesTheFirst() throws {
        let directory = try makeTemporaryDirectory()
        let cache = FileForecastCache(directory: directory)
        try cache.save(CachedForecast(curve: Fixture.curve(fetchedAt: Fixture.noon), providerName: "first"))

        let later = Fixture.noon.addingTimeInterval(7200)
        try cache.save(CachedForecast(curve: Fixture.curve(fetchedAt: later), providerName: "second"))

        let loaded = try XCTUnwrap(FileForecastCache(directory: directory).load())
        XCTAssertEqual(loaded.providerName, "second")
        XCTAssertEqual(loaded.curve.fetchedAt, later)
    }

    func testTheMemoryCacheHoldsTheOneValueItWasGiven() throws {
        let cache = MemoryForecastCache()
        XCTAssertNil(try cache.load())

        try cache.save(CachedForecast(curve: Fixture.curve(fetchedAt: Fixture.noon), providerName: "recorded"))

        let loaded = try XCTUnwrap(cache.load())
        XCTAssertEqual(loaded.providerName, "recorded")
        XCTAssertEqual(loaded.curve.fetchedAt, Fixture.noon)
        XCTAssertNil(try MemoryForecastCache().load())
    }
}

// MARK: - The WeatherKit mapping (R1, S8)

final class WeatherKitMappingTests: XCTestCase {
    private func recordedResponse() throws -> WeatherKitHourlyResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WeatherKitHourlyResponse.self, from: Data(recordedWeatherKitJSON.utf8))
    }

    func testTheRecordedResponseMapsToTwentyFourSamplesPerHorizonDay() throws {
        let forecast = try WeatherKitMapping.forecast(from: recordedResponse(), horizonDays: 2)

        XCTAssertEqual(forecast.horizonDays, 2)
        XCTAssertEqual(forecast.hourly.count, 24 * forecast.horizonDays)
        XCTAssertEqual(forecast.timeZone, Fixture.osloZone)
    }

    func testTheMappingKeepsEveryHourInOrderWithItsIndexAsADouble() throws {
        let forecast = try WeatherKitMapping.forecast(from: recordedResponse(), horizonDays: 2)

        XCTAssertEqual(forecast.hourly.first, HourlyUVI(time: Fixture.date(2026, 6, 15), uvi: 0))
        XCTAssertEqual(forecast.hourly[11], HourlyUVI(time: Fixture.date(2026, 6, 15, 11), uvi: 7))
        XCTAssertEqual(forecast.hourly[35], HourlyUVI(time: Fixture.date(2026, 6, 16, 11), uvi: 7))
        XCTAssertEqual(forecast.hourly.last, HourlyUVI(time: Fixture.date(2026, 6, 16, 23), uvi: 0))
        let times = forecast.hourly.map(\.time)
        XCTAssertEqual(times, times.sorted())
    }

    func testTheMappingKeysSolarNoonByTheDayInTheResponsesZone() throws {
        let forecast = try WeatherKitMapping.forecast(from: recordedResponse(), horizonDays: 2)

        XCTAssertEqual(forecast.solarNoon.count, 2)
        XCTAssertEqual(Fixture.day(0).id, "2026-06-15@Europe/Oslo")
        XCTAssertEqual(forecast.solarNoon[Fixture.day(0)], Fixture.date(2026, 6, 15, 11, 15))
        XCTAssertEqual(forecast.solarNoon[Fixture.day(1)], Fixture.date(2026, 6, 16, 11, 15))
    }

    func testADayWithoutASolarNoonIsNotKeyed() throws {
        let hours = [WeatherKitHour(date: Fixture.date(2026, 6, 15), uvIndex: 0),
                     WeatherKitHour(date: Fixture.date(2026, 6, 15, 1), uvIndex: 1)]
        let days = [WeatherKitDay(date: Fixture.date(2026, 6, 15), solarNoon: nil),
                    WeatherKitDay(date: Fixture.date(2026, 6, 16), solarNoon: Fixture.date(2026, 6, 16, 11, 15))]
        let response = WeatherKitHourlyResponse(hours: hours, days: days, timeZoneIdentifier: "Europe/Oslo")

        let forecast = try WeatherKitMapping.forecast(from: response, horizonDays: 1)

        XCTAssertEqual(forecast.solarNoon.count, 1)
        XCTAssertNil(forecast.solarNoon[Fixture.day(0)])
        XCTAssertEqual(forecast.solarNoon[Fixture.day(1)], Fixture.date(2026, 6, 16, 11, 15))
    }

    func testAnUnknownTimeZoneIsAnUnavailableProviderError() {
        let hours = [WeatherKitHour(date: Fixture.date(2026, 6, 15), uvIndex: 0),
                     WeatherKitHour(date: Fixture.date(2026, 6, 15, 1), uvIndex: 1)]
        let response = WeatherKitHourlyResponse(hours: hours, days: [], timeZoneIdentifier: "Nowhere/Atlantis")

        do {
            _ = try WeatherKitMapping.forecast(from: response, horizonDays: 1)
            XCTFail("an unknown time zone should be an unavailable provider error")
        } catch {
            XCTAssertEqual(error, ProviderError.unavailable("time zone"))
        }
    }
}

// MARK: - The fake provider (R37, S8)

final class FakeForecastProviderTests: XCTestCase {
    func testTheShippedFixtureIsTenOsloDaysPeakingAtSeven() throws {
        let forecast = try FakeForecastProvider.fixture(named: "beach-oslo")

        XCTAssertEqual(forecast.horizonDays, 10)
        XCTAssertEqual(forecast.hourly.count, 24 * 10)
        XCTAssertEqual(forecast.timeZone, Fixture.osloZone)
        XCTAssertEqual(forecast.solarNoon.count, 10)
        XCTAssertEqual(forecast.hourly.first?.time, Fixture.start)
        XCTAssertEqual(forecast.hourly.map(\.uvi).max(), 7)
        let eleven = Fixture.date(2026, 6, 15, 11)
        XCTAssertEqual(forecast.hourly.first { $0.time == eleven }?.uvi, 7)
        XCTAssertEqual(forecast.solarNoon[Fixture.day(0)], Fixture.date(2026, 6, 15, 11, 15))
        XCTAssertEqual(forecast.solarNoon[Fixture.day(9)], Fixture.date(2026, 6, 24, 11, 15))
    }

    func testAMissingFixtureThrows() {
        XCTAssertThrowsError(try FakeForecastProvider.fixture(named: "no-such-fixture"))
    }

    func testTheEngineGetsACurveFromTheShippedFixtureWithNoNetwork() async throws {
        let provider = try FakeForecastProvider(fixture: FakeForecastProvider.fixture(named: "beach-oslo"))
        let service = makeService(provider, MemoryForecastCache())

        let result = await service.current(for: Fixture.oslo, now: Fixture.noon)

        guard let curve = freshCurve(result) else { return }
        XCTAssertEqual(curve.timeZone, Fixture.osloZone)
        XCTAssertEqual(curve.uvi(at: Fixture.date(2026, 6, 15, 11)), 7, accuracy: 0.0001)
        XCTAssertGreaterThan(curve.sed(from: Fixture.date(2026, 6, 15, 10),
                                       to: Fixture.date(2026, 6, 15, 12)), 0)
        XCTAssertEqual(curve.solarNoon(on: Fixture.day(0)), Fixture.date(2026, 6, 15, 11, 15))
    }

    func testTheFakeProviderReportsTheFailureItWasGiven() async {
        let provider = FakeForecastProvider(fixture: Fixture.providerForecast(), failing: .unavailable("no key"))
        let service = makeService(provider, MemoryForecastCache())

        let result = await service.current(for: Fixture.oslo, now: Fixture.noon)

        guard let failure = noneFailure(result) else { return }
        XCTAssertEqual(failure, .provider(.unavailable("no key")))
    }
}

// MARK: - The recorded response

/// The same bytes as `Tests/IcarusDataTests/Fixtures/weatherkit-response.json`,
/// kept here as well so the mapping test does not depend on the test target
/// declaring resources. The file is the copy a human reads.
private let recordedWeatherKitJSON = #"""
{
  "hours": [
    {"date": "2026-06-15T00:00:00Z", "uvIndex": 0},
    {"date": "2026-06-15T01:00:00Z", "uvIndex": 0},
    {"date": "2026-06-15T02:00:00Z", "uvIndex": 0},
    {"date": "2026-06-15T03:00:00Z", "uvIndex": 0},
    {"date": "2026-06-15T04:00:00Z", "uvIndex": 0},
    {"date": "2026-06-15T05:00:00Z", "uvIndex": 1},
    {"date": "2026-06-15T06:00:00Z", "uvIndex": 2},
    {"date": "2026-06-15T07:00:00Z", "uvIndex": 3},
    {"date": "2026-06-15T08:00:00Z", "uvIndex": 4},
    {"date": "2026-06-15T09:00:00Z", "uvIndex": 5},
    {"date": "2026-06-15T10:00:00Z", "uvIndex": 6},
    {"date": "2026-06-15T11:00:00Z", "uvIndex": 7},
    {"date": "2026-06-15T12:00:00Z", "uvIndex": 6},
    {"date": "2026-06-15T13:00:00Z", "uvIndex": 5},
    {"date": "2026-06-15T14:00:00Z", "uvIndex": 4},
    {"date": "2026-06-15T15:00:00Z", "uvIndex": 3},
    {"date": "2026-06-15T16:00:00Z", "uvIndex": 2},
    {"date": "2026-06-15T17:00:00Z", "uvIndex": 1},
    {"date": "2026-06-15T18:00:00Z", "uvIndex": 0},
    {"date": "2026-06-15T19:00:00Z", "uvIndex": 0},
    {"date": "2026-06-15T20:00:00Z", "uvIndex": 0},
    {"date": "2026-06-15T21:00:00Z", "uvIndex": 0},
    {"date": "2026-06-15T22:00:00Z", "uvIndex": 0},
    {"date": "2026-06-15T23:00:00Z", "uvIndex": 0},
    {"date": "2026-06-16T00:00:00Z", "uvIndex": 0},
    {"date": "2026-06-16T01:00:00Z", "uvIndex": 0},
    {"date": "2026-06-16T02:00:00Z", "uvIndex": 0},
    {"date": "2026-06-16T03:00:00Z", "uvIndex": 0},
    {"date": "2026-06-16T04:00:00Z", "uvIndex": 0},
    {"date": "2026-06-16T05:00:00Z", "uvIndex": 1},
    {"date": "2026-06-16T06:00:00Z", "uvIndex": 2},
    {"date": "2026-06-16T07:00:00Z", "uvIndex": 3},
    {"date": "2026-06-16T08:00:00Z", "uvIndex": 4},
    {"date": "2026-06-16T09:00:00Z", "uvIndex": 5},
    {"date": "2026-06-16T10:00:00Z", "uvIndex": 6},
    {"date": "2026-06-16T11:00:00Z", "uvIndex": 7},
    {"date": "2026-06-16T12:00:00Z", "uvIndex": 6},
    {"date": "2026-06-16T13:00:00Z", "uvIndex": 5},
    {"date": "2026-06-16T14:00:00Z", "uvIndex": 4},
    {"date": "2026-06-16T15:00:00Z", "uvIndex": 3},
    {"date": "2026-06-16T16:00:00Z", "uvIndex": 2},
    {"date": "2026-06-16T17:00:00Z", "uvIndex": 1},
    {"date": "2026-06-16T18:00:00Z", "uvIndex": 0},
    {"date": "2026-06-16T19:00:00Z", "uvIndex": 0},
    {"date": "2026-06-16T20:00:00Z", "uvIndex": 0},
    {"date": "2026-06-16T21:00:00Z", "uvIndex": 0},
    {"date": "2026-06-16T22:00:00Z", "uvIndex": 0},
    {"date": "2026-06-16T23:00:00Z", "uvIndex": 0}
  ],
  "days": [
    {"date": "2026-06-15T00:00:00Z", "solarNoon": "2026-06-15T11:15:00Z"},
    {"date": "2026-06-16T00:00:00Z", "solarNoon": "2026-06-16T11:15:00Z"}
  ],
  "timeZoneIdentifier": "Europe/Oslo"
}
"""#
