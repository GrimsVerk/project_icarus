import Foundation
import IcarusCore
@testable import IcarusData
import XCTest

/// The export is the whole record: every session with the curve it was planned
/// on, every report, the profile, and the constant set it was all computed
/// under. Importing it puts that record back exactly, or refuses it whole.
final class ExportRoundTripTests: XCTestCase {
    private let now = StoreFixtures.date(2026, 7, 1, 12)

    private func filled() async throws -> HistoryStore {
        let store = HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
        try await StoreFixtures.seed(store, index: 1, opens: StoreFixtures.date(2026, 6, 21, 12),
                                     dose: [.front: 1.0, .back: 1.0, .headAndShoulders: 0.5])
        try await StoreFixtures.seed(store, index: 2, opens: StoreFixtures.date(2026, 6, 29, 12),
                                     dose: [.front: 1.2, .back: 0.8, .headAndShoulders: 0.4])
        _ = try await store.addReport(StoreFixtures.report(20, .faintPink, on: StoreFixtures.date(2026, 6, 29, 12)))
        return store
    }

    func testExportThenImportRestoresTheHistoryAndTheState() async throws {
        let source = try await filled()
        let data = try await ExportService.export(store: source, profile: StoreFixtures.profile, now: now)
        let target = HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
        let summary = try await ExportService.import(data, into: target)

        XCTAssertEqual(summary.sessions, 2)
        XCTAssertEqual(summary.reports, 1)
        XCTAssertEqual(summary.tunablesVersion, StoreFixtures.tunables.version)
        let expected = try await source.history()
        let restored = try await target.history()
        XCTAssertEqual(StoreFixtures.ordered(restored), StoreFixtures.ordered(expected))
        let expectedState = try await source.state(now: now)
        let restoredState = try await target.state(now: now)
        XCTAssertEqual(restoredState, expectedState)
    }

    func testEveryExportedSessionKeepsItsStoredCurve() async throws {
        let source = try await filled()
        let data = try await ExportService.export(store: source, profile: StoreFixtures.profile, now: now)
        let target = HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
        _ = try await ExportService.import(data, into: target)

        let sessions = try await target.history().sessions
        XCTAssertEqual(sessions.count, 2)
        for session in sessions {
            XCTAssertFalse(session.curveUsed.hourly.isEmpty)
            XCTAssertEqual(session.curveUsed.timeZoneID, StoreFixtures.zone.identifier)
            XCTAssertNoThrow(try session.curveUsed.curve())
        }
    }

    func testImportReportsTheProfileTheFileCarried() async throws {
        let carried = Profile(skinType: .v, ceiling: .conservative, manualMultiplier: 1.3)
        let source = try await filled()
        let data = try await ExportService.export(store: source, profile: carried, now: now)
        let target = HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)

        let summary = try await ExportService.import(data, into: target)
        XCTAssertEqual(summary.profile, carried)
    }

    func testImportReplacesEverythingTheStoreHeld() async throws {
        let source = try await filled()
        let data = try await ExportService.export(store: source, profile: StoreFixtures.profile, now: now)
        let target = HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
        try await StoreFixtures.seed(target, index: 9, opens: StoreFixtures.date(2026, 5, 4, 12),
                                     dose: [.front: 3.0, .back: 3.0, .headAndShoulders: 3.0])

        _ = try await ExportService.import(data, into: target)
        let restored = try await target.history()
        XCTAssertEqual(restored.sessions.count, 2)
        XCTAssertFalse(restored.sessions.contains { $0.id == StoreFixtures.uuid(9) })
    }
}

/// The file: version 1, its constant set, ISO-8601 instants, sorted keys, and
/// per-region doses as a JSON object.
final class ExportFileShapeTests: XCTestCase {
    private let now = StoreFixtures.date(2026, 7, 1, 12)

    private func exported() async throws -> Data {
        let store = HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
        try await StoreFixtures.seed(store, index: 1, opens: StoreFixtures.date(2026, 6, 29, 12),
                                     dose: [.front: 1.2, .back: 0.8, .headAndShoulders: 0.4])
        return try await ExportService.export(store: store, profile: StoreFixtures.profile, now: now)
    }

    func testTheExportNamesFormatVersionOneTheTunablesVersionAndTheProfile() async throws {
        let data = try await exported()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(ExportFile.self, from: data)

        XCTAssertEqual(file.formatVersion, 1)
        XCTAssertEqual(file.tunablesVersion, StoreFixtures.tunables.version)
        XCTAssertEqual(file.profile, StoreFixtures.profile)
        XCTAssertEqual(file.exportedAt, now)
        XCTAssertEqual(file.history.sessions.count, 1)
    }

    func testTheExportedJSONHasDosePerRegionAsAnObject() async throws {
        let data = try await exported()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let history = try XCTUnwrap(root["history"] as? [String: Any])
        let sessions = try XCTUnwrap(history["sessions"] as? [[String: Any]])
        let doses = try XCTUnwrap(sessions.first?["dosePerRegion"] as? [String: Any])

        XCTAssertEqual(doses["front"] as? Double, 1.2)
        XCTAssertEqual(doses["back"] as? Double, 0.8)
        XCTAssertEqual(doses["headAndShoulders"] as? Double, 0.4)
    }

    func testTheExportedJSONHasISO8601InstantsAndSortedKeys() async throws {
        let data = try await exported()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"exportedAt\":\"2026-07-01T12:00:00Z\""))

        let exportedAt = try XCTUnwrap(text.range(of: "\"exportedAt\""))
        let format = try XCTUnwrap(text.range(of: "\"formatVersion\""))
        let version = try XCTUnwrap(text.range(of: "\"tunablesVersion\""))
        XCTAssertTrue(exportedAt.lowerBound < format.lowerBound)
        XCTAssertTrue(format.lowerBound < version.lowerBound)
    }
}

/// A file the validator refuses is refused whole: the store keeps what it had.
final class ExportImportValidationTests: XCTestCase {
    private func refuse(_ data: Data, _ what: String) async throws {
        let store = HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
        try await StoreFixtures.seed(store, index: 1, opens: StoreFixtures.date(2026, 6, 29, 12),
                                     dose: [.front: 1.2, .back: 0.8, .headAndShoulders: 0.4])
        let before = try await store.history()
        do {
            _ = try await ExportService.import(data, into: store)
            XCTFail("the import of \(what) should have been refused")
        } catch {}
        let after = try await store.history()
        XCTAssertEqual(after, before, "the store was changed by \(what)")
    }

    func testAnImportWithANegativeDoseIsRefusedAndLeavesTheStoreUntouched() async throws {
        var session = try StoreFixtures.logged(2, opens: StoreFixtures.date(2026, 6, 30, 12), dose: [.front: 1.0])
        session.dosePerRegion = [.front: -0.5]
        let data = try StoreFixtures.encoded(History(sessions: [session]))
        try await refuse(data, "a negative dose")
    }

    func testAnImportWithIntervalsOutOfOrderIsRefusedAndLeavesTheStoreUntouched() async throws {
        let opens = StoreFixtures.date(2026, 6, 30, 12)
        var session = try StoreFixtures.logged(2, opens: opens, dose: [.front: 1.0])
        session.actualIntervals = [
            ExposureInterval(exposure: .lying(.faceUp),
                             window: Window(start: opens.addingTimeInterval(3600),
                                            end: opens.addingTimeInterval(7200))),
            ExposureInterval(exposure: .lying(.faceDown),
                             window: Window(start: opens, end: opens.addingTimeInterval(1800))),
        ]
        let data = try StoreFixtures.encoded(History(sessions: [session]))
        try await refuse(data, "intervals out of order")
    }

    func testAnImportWhoseStoredCurveCannotBeRebuiltIsRefused() async throws {
        var session = try StoreFixtures.logged(2, opens: StoreFixtures.date(2026, 6, 30, 12), dose: [.front: 1.0])
        session.curveUsed = StoredCurve(hourly: [], solarNoon: StoreFixtures.date(2026, 6, 30, 12),
                                        timeZoneID: StoreFixtures.zone.identifier,
                                        location: StoreFixtures.location,
                                        fetchedAt: StoreFixtures.date(2026, 6, 30))
        let data = try StoreFixtures.encoded(History(sessions: [session]))
        try await refuse(data, "an unusable stored curve")
    }

    func testBytesThatAreNotAnExportFileAreRefused() async throws {
        try await refuse(Data("{\"formatVersion\":1,\"nonsense\":true}".utf8), "a truncated file")
    }
}

/// `reproduce` rebuilds a session's doses from the intervals actually faced and
/// the curve stored with it — no derived state, no forecast fetch (R22, R25).
final class ExportReproduceTests: XCTestCase {
    private let opens = StoreFixtures.date(2026, 6, 29, 12)

    private func assertReproduces(_ session: SessionRecord) throws -> [Region: SED] {
        let again = try ExportService.reproduce(session, tunables: StoreFixtures.tunables)
        for region in Region.allCases {
            XCTAssertEqual(again[region] ?? 0, session.dosePerRegion[region] ?? 0, accuracy: 1e-6,
                           "\(region) did not reproduce")
        }
        return again
    }

    func testReproduceMatchesTheStoredDosesOfALoggedSession() throws {
        let choice = SunscreenChoice(spfLabel: 30, application: .normal)
        let faced = ExposureInterval(exposure: .lying(.faceUp),
                                     window: Window(start: opens, end: opens.addingTimeInterval(3600)))
        let session = try StoreFixtures.faced(3, opens: opens, intervals: [faced], sunscreen: choice)

        let again = try assertReproduces(session)
        // Flat UVI 8 for sixty minutes, face up, under SPF 30 applied normally.
        let bare = 8.0 * 60 / StoreFixtures.tunables.uviMinutesPerSED
        XCTAssertEqual(again[.front] ?? 0, bare / choice.effectiveSPF, accuracy: 1e-6)
    }

    func testReproduceMatchesALyingSessionStoppedBeforeItsFlip() throws {
        let faced = ExposureInterval(exposure: .lying(.faceUp),
                                     window: Window(start: opens, end: opens.addingTimeInterval(1200)))
        let session = try StoreFixtures.faced(4, opens: opens, intervals: [faced], sunscreen: nil)

        let again = try assertReproduces(session)
        XCTAssertEqual(again[.back] ?? 0, 0, accuracy: 1e-9, "the second side was never faced")
        XCTAssertGreaterThan(again[.front] ?? 0, 0)
    }

    func testReproduceOfASessionThatFacedNothingIsEmpty() throws {
        let planned = try StoreFixtures.planned(5, opens: opens)
        let again = try ExportService.reproduce(planned, tunables: StoreFixtures.tunables)
        XCTAssertTrue(again.isEmpty)
    }
}

// MARK: - Fixtures shared with HistoryStoreTests

/// Deterministic fixtures for the Slice 3 tests, copied from the IcarusCore
/// test target (`Curves`, `SessionFixture`) and renamed, because test targets
/// cannot import each other's code. Every instant is fixed and in UTC.
enum StoreFixtures {
    static let zone = TimeZone(identifier: "UTC")!
    static let location = Coordinate(latitude: 59.9, longitude: 10.75)
    static let tunables = Tunables.current
    static let profile = Profile(skinType: .ii, ceiling: .standard)

    /// A fixed instant in the fixtures' UTC calendar. Never derived from `Date()`.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func day(_ moment: Date) -> DayKey {
        DayKey(moment, timeZone: zone)
    }

    /// Ids that read as numbers, so a failure names the record it is about.
    static func uuid(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
    }

    /// Flat UVI 8 across two whole days from `moment`'s local midnight.
    static func curve(from moment: Date) throws -> ForecastCurve {
        let opens = day(moment).start()
        let samples = (0 ... 48).map { HourlyUVI(time: opens.addingTimeInterval(Double($0) * 3600), uvi: 8) }
        return try ForecastCurve(location: location, timeZone: zone, fetchedAt: opens,
                                 hourly: samples, solarNoon: [day(moment): opens.addingTimeInterval(12 * 3600)])
    }

    static func stored(on moment: Date) throws -> StoredCurve {
        try curve(from: moment).stored(for: day(moment))
    }

    /// A planned lying session: face up, then face down, an hour each.
    static func planned(
        _ index: Int,
        opens: Date,
        prescribed: SunscreenChoice? = nil,
        createdAt: Date? = nil
    ) throws -> SessionRecord {
        let middle = opens.addingTimeInterval(3600)
        let closes = opens.addingTimeInterval(7200)
        let curveUsed = try stored(on: opens)
        return SessionRecord(
            id: uuid(index), day: day(opens), createdAt: createdAt ?? opens,
            plannedWindow: Window(start: opens, end: closes),
            plannedIntervals: [
                ExposureInterval(exposure: .lying(.faceUp), window: Window(start: opens, end: middle)),
                ExposureInterval(exposure: .lying(.faceDown), window: Window(start: middle, end: closes)),
            ],
            firstSide: .faceUp, posture: .lyingTurning, coverHeadAndShoulders: false,
            intent: .bestMinutes, ceilingAtPlan: .standard, prescribedSunscreen: prescribed,
            state: .planned, dosePerRegion: [:], curveUsed: curveUsed,
            forecastFetchedAt: day(opens).start(), forecastPlace: location
        )
    }

    /// The three hours a seeded session is logged as having faced.
    static func facedHours(from opens: Date) -> [ExposureInterval] {
        [ExposureInterval(exposure: .lying(.faceUp),
                          window: Window(start: opens, end: opens.addingTimeInterval(3 * 3600)))]
    }

    /// A three-hour logged session holding the doses given.
    static func logged(_ index: Int, opens: Date, dose: [Region: SED]) throws -> SessionRecord {
        var record = try planned(index, opens: opens)
        record.actualIntervals = facedHours(from: opens)
        record.state = .logged
        record.dosePerRegion = dose
        return record
    }

    /// A logged session whose stored doses are exactly what the intervals faced
    /// under the stored curve deliver — what `reproduce` must arrive back at.
    static func faced(
        _ index: Int,
        opens: Date,
        intervals: [ExposureInterval],
        sunscreen: SunscreenChoice?
    ) throws -> SessionRecord {
        var record = try planned(index, opens: opens)
        let shape = try curve(from: opens)
        var bare = [Region: SED]()
        for interval in intervals {
            let part = ExposureModel.dose(interval.exposure, coverHeadAndShoulders: false,
                                          over: interval.window, curve: shape, tunables: tunables)
            for (region, value) in part {
                bare[region, default: 0] += value
            }
        }
        record.actualIntervals = intervals
        record.sunscreen = sunscreen
        record.state = .logged
        record.dosePerRegion = ExposureModel.attenuated(bare, sunscreen: sunscreen, coverHeadAndShoulders: false)
        return record
    }

    /// The skin check for `opens`' day, answered twenty-three hours later.
    static func report(_ index: Int, _ answer: SkinAnswer, on opens: Date) -> SkinReport {
        SkinReport(id: uuid(index), day: day(opens), reportedAt: opens.addingTimeInterval(23 * 3600),
                   answer: answer, region: .front, channel: .notification)
    }

    /// Plan a session and log it — the only way a session reaches the store.
    static func seed(_ store: HistoryStore, index: Int, opens: Date, dose: [Region: SED]) async throws {
        let record = try planned(index, opens: opens)
        _ = try await store.upsertPlanned(record, replacing: nil)
        try await store.log(record.id, actual: facedHours(from: opens), sunscreen: nil, doses: dose,
                            factors: [.front: 1.2], targets: [.front: 2.0])
    }

    /// Records in a fixed order, so a comparison never turns on storage order.
    static func ordered(_ history: History) -> History {
        History(sessions: history.sessions.sorted { $0.id.uuidString < $1.id.uuidString },
                reports: history.reports.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    /// A history written out as an export file, for the import validator.
    static func encoded(_ history: History) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(ExportFile(
            formatVersion: 1, tunablesVersion: tunables.version, profile: profile,
            history: history, exportedAt: date(2026, 7, 1, 12)
        ))
    }
}

/// The constant keys a replay read, so a test can show the state was folded.
final class ConstantRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Set<String> = []

    var keys: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ key: String) {
        lock.lock()
        storage.insert(key)
        lock.unlock()
    }

    /// Forget what has been read so far, so the next call can be judged alone.
    func reset() {
        lock.lock()
        storage = []
        lock.unlock()
    }
}

/// A profile the test can change under the store.
final class ProfileBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Profile

    init(_ profile: Profile) {
        storage = profile
    }

    var profile: Profile {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ profile: Profile) {
        lock.lock()
        storage = profile
        lock.unlock()
    }
}
