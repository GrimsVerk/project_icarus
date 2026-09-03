@testable import IcarusCore
import XCTest

private let utc = TimeZone(identifier: "UTC")!
private let oslo = TimeZone(identifier: "Europe/Oslo")!
private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

/// `DayKey` is the day identity the export, the notification ids and the
/// solar-noon table are all keyed by. Every date here is explicit; nothing
/// reads the host's time zone or the wall clock.
final class DayKeyTests: XCTestCase {
    func testTheSameInstantIsADifferentDayKeyInADifferentZone() {
        let instant = Curves.date(2026, 9, 3, 23, 30)
        XCTAssertNotEqual(DayKey(instant, timeZone: utc), DayKey(instant, timeZone: losAngeles))
    }

    func testTheCalendarDayIsTheLocalOne() {
        let instant = Curves.date(2026, 9, 3, 3, 0)
        XCTAssertEqual(DayKey(instant, timeZone: utc).day, 3)
        XCTAssertEqual(DayKey(instant, timeZone: losAngeles).day, 2)
    }

    func testIdCarriesTheDateAndTheZone() {
        let key = DayKey(Curves.date(2026, 9, 3, 10, 0), timeZone: oslo)
        XCTAssertEqual(key.id, "2026-09-03@Europe/Oslo")
    }

    func testIdRoundTripsBackToTheSameDay() {
        let first = DayKey(Curves.date(2026, 9, 3, 10, 0), timeZone: oslo)
        let second = DayKey(Curves.date(2026, 1, 1, 0, 30), timeZone: utc)
        let third = DayKey(Curves.date(2026, 12, 31, 23, 30), timeZone: losAngeles)
        for key in [first, second, third] {
            XCTAssertEqual(DayKey(id: key.id), key)
        }
    }

    func testAMalformedIdIsRejected() {
        XCTAssertNil(DayKey(id: "garbage"))
        XCTAssertNil(DayKey(id: ""))
        XCTAssertNil(DayKey(id: "2026-09-03"))
        XCTAssertNil(DayKey(id: "@Europe/Oslo"))
    }

    func testStartIsLocalMidnight() {
        let key = DayKey(Curves.date(2026, 9, 3, 10, 0), timeZone: oslo)
        XCTAssertEqual(key.start(), Curves.date(2026, 9, 2, 22, 0))
    }

    func testAnOrdinaryDaySpansTwentyFourHours() {
        let key = DayKey(Curves.date(2026, 9, 3, 10, 0), timeZone: oslo)
        let span = key.end().timeIntervalSince(key.start())
        XCTAssertGreaterThanOrEqual(span, 86399)
        XCTAssertLessThanOrEqual(span, 86400)
    }

    func testTheDaySummerTimeEndsSpansTwentyFiveHours() {
        let key = DayKey(Curves.date(2026, 10, 25, 10, 0), timeZone: oslo)
        let span = key.end().timeIntervalSince(key.start())
        XCTAssertGreaterThanOrEqual(span, 89999)
        XCTAssertLessThanOrEqual(span, 90000)
    }

    func testAddingDaysCrossesAMonthEnd() {
        let january = DayKey(Curves.date(2026, 1, 31, 12, 0), timeZone: oslo)
        XCTAssertEqual(january.adding(days: 1), DayKey(Curves.date(2026, 2, 1, 12, 0), timeZone: oslo))
        let february = DayKey(Curves.date(2026, 2, 28, 12, 0), timeZone: oslo)
        XCTAssertEqual(february.adding(days: 1), DayKey(Curves.date(2026, 3, 1, 12, 0), timeZone: oslo))
        XCTAssertEqual(february.adding(days: -28), DayKey(Curves.date(2026, 1, 31, 12, 0), timeZone: oslo))
    }

    func testDaysAreOrderedByDate() {
        let earlier = DayKey(Curves.date(2026, 1, 31, 12, 0), timeZone: utc)
        let later = DayKey(Curves.date(2026, 2, 1, 12, 0), timeZone: utc)
        XCTAssertLessThan(earlier, later)
        XCTAssertFalse(later < earlier)
    }

    func testDaysWorkAsDictionaryKeys() {
        let first = DayKey(Curves.date(2026, 6, 15, 12, 0), timeZone: utc)
        let second = DayKey(Curves.date(2026, 6, 16, 12, 0), timeZone: utc)
        var table: [DayKey: Int] = [:]
        table[first] = 1
        table[second] = 2
        XCTAssertEqual(table[DayKey(Curves.date(2026, 6, 15, 3, 0), timeZone: utc)], 1)
        XCTAssertEqual(table.count, 2)
    }
}

/// The export format promise (S10): every record type encodes as a JSON
/// object with readable string keys, never an array of alternating values.
final class ModelCodingTests: XCTestCase {
    func testARegionKeyedDictionaryEncodesAsAJSONObject() throws {
        let doses: [Region: SED] = [.front: 1.0, .back: 2.0, .headAndShoulders: 3.0]
        let data = try JSONEncoder().encode(doses)
        let decoded = try JSONDecoder().decode([String: Double].self, from: data)
        XCTAssertEqual(decoded["front"], 1.0)
        XCTAssertEqual(decoded["back"], 2.0)
        XCTAssertEqual(decoded["headAndShoulders"], 3.0)
    }

    func testExposureEncodesAsATaggedObjectOrABareString() throws {
        let lying = try JSONEncoder().encode([Exposure.lying(.faceUp)])
        XCTAssertEqual(try text(lying), "[{\"lying\":\"faceUp\"}]")
        let about = try JSONEncoder().encode([Exposure.upAndAbout])
        XCTAssertEqual(try text(about), "[\"upAndAbout\"]")
    }

    func testExposureRoundTripsThroughJSON() throws {
        let values: [Exposure] = [.lying(.faceUp), .lying(.faceDown), .upAndAbout]
        let data = try JSONEncoder().encode(values)
        XCTAssertEqual(try JSONDecoder().decode([Exposure].self, from: data), values)
    }

    func testCaseIterableEnumsEncodeAsTheirRawValues() throws {
        try assertEncodesAsRawStrings(SkinBand.self)
        try assertEncodesAsRawStrings(Region.self)
        try assertEncodesAsRawStrings(Ceiling.self)
        try assertEncodesAsRawStrings(SkinAnswer.self)
        try assertEncodesAsRawStrings(Confounder.self)
        try assertEncodesAsRawStrings(Application.self)
        try assertEncodesAsRawStrings(FigureKey.self)
        try assertEncodesAsRawStrings(CopyKey.self)
    }

    func testTheRemainingPayloadFreeEnumsEncodeAsStrings() throws {
        try assertEncodesAsRawString(Side.faceUp)
        try assertEncodesAsRawString(Posture.lyingTurning)
        try assertEncodesAsRawString(Intent.stayWholeWindow)
        try assertEncodesAsRawString(RednessTiming.withinHourGoneByEvening)
        try assertEncodesAsRawString(ReportRegion.allExposed)
        try assertEncodesAsRawString(LastingColour.aLittle)
        try assertEncodesAsRawString(Channel.notification)
        try assertEncodesAsRawString(SessionState.planned)
    }

    func testSkinTypeEncodesAsItsNumber() throws {
        let data = try JSONEncoder().encode([SkinType.iv])
        XCTAssertEqual(try text(data), "[4]")
    }

    private func text(_ data: Data) throws -> String {
        try XCTUnwrap(String(bytes: data, encoding: .utf8))
    }

    private func assertEncodesAsRawStrings<T: CaseIterable & Encodable & RawRepresentable>(
        _ type: T.Type, file: StaticString = #filePath, line: UInt = #line
    ) throws where T.RawValue == String {
        XCTAssertFalse(T.allCases.isEmpty, "\(type) has no cases", file: file, line: line)
        for value in T.allCases {
            try assertEncodesAsRawString(value, file: file, line: line)
        }
    }

    private func assertEncodesAsRawString<T: Encodable & RawRepresentable>(
        _ value: T, file: StaticString = #filePath, line: UInt = #line
    ) throws where T.RawValue == String {
        let data = try JSONEncoder().encode([value])
        XCTAssertEqual(try text(data), "[\"\(value.rawValue)\"]", file: file, line: line)
    }
}

/// R15's density model: `SPF_effective = SPF_label ^ (density / 2)`.
final class SunscreenChoiceTests: XCTestCase {
    func testApplicationDensitiesAreTheReferencePoints() {
        XCTAssertEqual(Application.thin.density, 0.5, accuracy: 1e-9)
        XCTAssertEqual(Application.normal.density, 1.0, accuracy: 1e-9)
        XCTAssertEqual(Application.thick.density, 2.0, accuracy: 1e-9)
    }

    func testLabelFiftyGivesFullLabelOnlyWhenAppliedThick() {
        XCTAssertEqual(SunscreenChoice(spfLabel: 50, application: .thick).effectiveSPF, 50, accuracy: 0.01)
        XCTAssertEqual(SunscreenChoice(spfLabel: 50, application: .normal).effectiveSPF, 7.07, accuracy: 0.01)
        XCTAssertEqual(SunscreenChoice(spfLabel: 50, application: .thin).effectiveSPF, 2.66, accuracy: 0.01)
    }

    func testAModerateLabelAppliedNormallyBeatsAHighOneAppliedThinly() {
        let moderate = SunscreenChoice(spfLabel: 30, application: .normal)
        let high = SunscreenChoice(spfLabel: 50, application: .thin)
        XCTAssertGreaterThan(moderate.effectiveSPF, high.effectiveSPF)
    }
}
