import Foundation
import IcarusCore
@testable import IcarusData
import XCTest

/// Fixtures for the location slice. Every date is a fixed instant in UTC and
/// every zone is named explicitly; nothing here reads the wall clock or the
/// host's time zone. The shape is copied from `Curves` in the IcarusCore test
/// target, which test targets cannot import from one another.
private enum Fixed {
    static let utc = TimeZone(identifier: "UTC")!
    static let paris = TimeZone(identifier: "Europe/Paris")!
    static let oslo = TimeZone(identifier: "Europe/Oslo")!

    /// A fixed instant in the fixtures' UTC calendar. Never derived from `Date()`.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }

    static let now = date(2026, 6, 15, 12, 0)
    static let later = date(2026, 6, 15, 15, 30)

    /// The cached forecast's place in the Core fixtures, and a device fix
    /// 0.09 degrees of latitude north of it — 10.01 km away.
    static let cacheLocation = Coordinate(latitude: 59.9, longitude: 10.75)
    static let deviceNearCache = Coordinate(latitude: 59.99, longitude: 10.75)

    static let niceLocation = Coordinate(latitude: 43.7102, longitude: 7.262)
    static let cannesLocation = Coordinate(latitude: 43.5528, longitude: 7.0174)

    static let nice = Place(name: "Nice", coordinate: niceLocation, timeZone: paris)
    static let cannes = Place(name: "Cannes", coordinate: cannesLocation, timeZone: paris)
    static let osloPlace = Place(name: "Oslo", coordinate: cacheLocation, timeZone: oslo)

    /// The geocoder table the fake resolver answers from.
    static let table = [
        "Nice": [nice],
        "Oslo": [osloPlace],
        "Riviera": [nice, cannes],
    ]

    static func service(
        reading: LocationReading,
        table: [String: [Place]] = Fixed.table
    ) -> LocationService {
        LocationService(
            source: FakeLocationSource(reading: reading),
            resolver: FakePlaceResolver(table: table)
        )
    }
}

/// `LocationService` answers one question: where should the forecast be for?
/// The device says so when it can, a typed place overrides it, and a refusal
/// is reported as a refusal rather than as a missing coordinate (R2, S8).
final class LocationServiceTests: XCTestCase {
    // MARK: - The device path

    func testADeviceFixIsAnsweredWithItsCoordinate() async {
        let service = Fixed.service(reading: .fix(Fixed.deviceNearCache, accuracyKm: 1.0))
        let answer = await service.location(now: Fixed.now)
        XCTAssertEqual(answer, .device(Fixed.deviceNearCache))
    }

    func testADeviceAnswerCarriesTheDeviceCoordinate() async {
        let service = Fixed.service(reading: .fix(Fixed.deviceNearCache, accuracyKm: 0.5))
        let answer = await service.location(now: Fixed.now)
        XCTAssertEqual(answer.coordinate, Fixed.deviceNearCache)
    }

    func testTheDeviceAnswerMeasuresDistanceFromTheCachedForecastPlace() async throws {
        let service = Fixed.service(reading: .fix(Fixed.deviceNearCache, accuracyKm: 1.0))
        let answer = await service.location(now: Fixed.now)
        let coordinate = try XCTUnwrap(answer.coordinate)
        XCTAssertEqual(coordinate.distanceKm(to: Fixed.cacheLocation), 10.01, accuracy: 0.1)
    }

    // MARK: - Denial and the missing fix

    func testDenialIsReportedAsNeedingAManualPlace() async {
        let service = Fixed.service(reading: .denied)
        let answer = await service.location(now: Fixed.now)
        XCTAssertEqual(answer, .needsManual(reason: .denied))
    }

    func testADeniedAnswerHasNoCoordinate() async {
        let service = Fixed.service(reading: .denied)
        let answer = await service.location(now: Fixed.now)
        XCTAssertNil(answer.coordinate)
    }

    func testAnUnavailableSourceIsReportedWithItsOwnReason() async {
        let service = Fixed.service(reading: .unavailable)
        let answer = await service.location(now: Fixed.now)
        XCTAssertEqual(answer, .needsManual(reason: .unavailable))
        XCTAssertNil(answer.coordinate)
    }

    // MARK: - The manual place

    func testAManualPlaceOverridesADeviceFix() async {
        let service = Fixed.service(reading: .fix(Fixed.deviceNearCache, accuracyKm: 1.0))
        await service.useManual(Fixed.nice)
        let answer = await service.location(now: Fixed.now)
        XCTAssertEqual(answer, .manual(Fixed.nice))
    }

    func testAManualPlaceAlsoAnswersWhenTheDeviceIsDenied() async {
        let service = Fixed.service(reading: .denied)
        await service.useManual(Fixed.nice)
        let answer = await service.location(now: Fixed.now)
        XCTAssertEqual(answer, .manual(Fixed.nice))
    }

    func testAManualAnswerCarriesThePlacesCoordinate() async {
        let service = Fixed.service(reading: .denied)
        await service.useManual(Fixed.nice)
        let answer = await service.location(now: Fixed.now)
        XCTAssertEqual(answer.coordinate, Fixed.niceLocation)
    }

    func testAManualPlaceHoldsAcrossLaterAsks() async {
        let service = Fixed.service(reading: .fix(Fixed.deviceNearCache, accuracyKm: 1.0))
        await service.useManual(Fixed.nice)
        let first = await service.location(now: Fixed.now)
        let second = await service.location(now: Fixed.later)
        XCTAssertEqual(first, .manual(Fixed.nice))
        XCTAssertEqual(second, .manual(Fixed.nice))
    }

    func testTheLatestManualPlaceWins() async {
        let service = Fixed.service(reading: .denied)
        await service.useManual(Fixed.nice)
        await service.useManual(Fixed.cannes)
        let answer = await service.location(now: Fixed.now)
        XCTAssertEqual(answer, .manual(Fixed.cannes))
    }

    // MARK: - Clearing the manual place

    func testClearingTheManualPlaceReturnsToTheDevice() async {
        let service = Fixed.service(reading: .fix(Fixed.deviceNearCache, accuracyKm: 1.0))
        await service.useManual(Fixed.nice)
        await service.clearManual()
        let answer = await service.location(now: Fixed.later)
        XCTAssertEqual(answer, .device(Fixed.deviceNearCache))
    }

    func testClearingTheManualPlaceOnADeniedDeviceAsksForAPlaceAgain() async {
        let service = Fixed.service(reading: .denied)
        await service.useManual(Fixed.nice)
        await service.clearManual()
        let answer = await service.location(now: Fixed.later)
        XCTAssertEqual(answer, .needsManual(reason: .denied))
        XCTAssertNil(answer.coordinate)
    }

    func testClearingWithNoManualPlaceSetChangesNothing() async {
        let service = Fixed.service(reading: .fix(Fixed.deviceNearCache, accuracyKm: 1.0))
        await service.clearManual()
        let answer = await service.location(now: Fixed.now)
        XCTAssertEqual(answer, .device(Fixed.deviceNearCache))
    }
}

/// The typed-place half of R2: the geocoder boundary and the `Place` value the
/// manual path stores. `FakePlaceResolver` is the stand-in for Apple's
/// geocoder, so the suite runs offline (S8).
final class PlaceResolutionTests: XCTestCase {
    func testResolvingAFixturePlaceNameReturnsThatPlace() async throws {
        let resolver = FakePlaceResolver(table: Fixed.table)
        let results = try await resolver.resolve("Nice")
        XCTAssertEqual(results, [Fixed.nice])
    }

    func testAResolvedPlaceCarriesItsOwnTimeZone() async throws {
        let resolver = FakePlaceResolver(table: Fixed.table)
        let matches = try await resolver.resolve("Nice")
        let nice = try XCTUnwrap(matches.first)
        XCTAssertEqual(nice.name, "Nice")
        XCTAssertEqual(nice.coordinate, Fixed.niceLocation)
        XCTAssertEqual(nice.timeZone.identifier, "Europe/Paris")
    }

    func testTwoPlacesWithDifferentZonesResolveToTheirOwnZones() async throws {
        let resolver = FakePlaceResolver(table: Fixed.table)
        let niceMatches = try await resolver.resolve("Nice")
        let osloMatches = try await resolver.resolve("Oslo")
        let nice = try XCTUnwrap(niceMatches.first)
        let oslo = try XCTUnwrap(osloMatches.first)
        XCTAssertEqual(nice.timeZone.identifier, "Europe/Paris")
        XCTAssertEqual(oslo.timeZone.identifier, "Europe/Oslo")
    }

    func testEveryMatchIsReturnedInTheTablesOrder() async throws {
        let resolver = FakePlaceResolver(table: Fixed.table)
        let results = try await resolver.resolve("Riviera")
        XCTAssertEqual(results, [Fixed.nice, Fixed.cannes])
    }

    func testAResolvedPlaceCanBeUsedAsTheManualPlace() async throws {
        let resolver = FakePlaceResolver(table: Fixed.table)
        let matches = try await resolver.resolve("Nice")
        let nice = try XCTUnwrap(matches.first)
        let service = Fixed.service(reading: .denied)
        await service.useManual(nice)
        let answer = await service.location(now: Fixed.now)
        XCTAssertEqual(answer, .manual(Fixed.nice))
        XCTAssertEqual(answer.coordinate, Fixed.niceLocation)
    }

    // MARK: - The stored value

    func testAPlaceRoundTripsThroughJSONWithItsZone() throws {
        let data = try JSONEncoder().encode(Fixed.nice)
        let decoded = try JSONDecoder().decode(Place.self, from: data)
        XCTAssertEqual(decoded, Fixed.nice)
        XCTAssertEqual(decoded.timeZone.identifier, "Europe/Paris")
        XCTAssertEqual(decoded.coordinate, Fixed.niceLocation)
    }

    func testTheEncodedPlaceNamesItsZoneByIdentifier() throws {
        let data = try JSONEncoder().encode(Fixed.nice)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("Europe/Paris"), "expected the zone identifier in \(json)")
        XCTAssertTrue(json.contains("Nice"), "expected the place name in \(json)")
    }
}
