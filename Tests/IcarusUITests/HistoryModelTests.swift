#if canImport(SwiftUI)
    import Foundation
    import IcarusAds
    import IcarusCore
    import IcarusData
    @testable import IcarusUI
    import XCTest

    // Slice 1 of `history`, asserted against the model and never against a
    // rendered view: a view test would need a host application, and every promise
    // the slice makes about the session log is reachable without one.
    //
    // The boundaries are faked and nothing else is — the forecast provider (the
    // network), the location source (the device), the notification port (the
    // system centre) and the clock. `HistoryModel`, which is what this slice
    // delivers, runs for real against the real history store.
    //
    // Every fixture type here is file-private on purpose: a fixture in a test
    // target is shared with every other file in it, and these names are ours.

    // MARK: - Fixtures

    /// The network, which never answers. Nothing in History may reach for a
    /// forecast: every day it shows is over, and each record already holds the
    /// curve it was solved from.
    private struct SilentProvider: UVForecastProvider {
        let name = "history-test"

        func forecast(at _: Coordinate, days _: Int) async throws(ProviderError) -> ProviderForecast {
            throw ProviderError.network("the test provider is offline")
        }
    }

    /// Fixed values only: three flat days at one place, read in UTC. Nothing here
    /// reads the wall clock, and no assertion below turns on a computed dose —
    /// the doses are handed to the store, so what History sums is known exactly.
    private enum HistoryFixture {
        static let zone = TimeZone(identifier: "UTC")!
        static let place = Coordinate(latitude: 59.91, longitude: 10.75)
        static let profile = Profile(skinType: .iii, ceiling: .standard)
        static let sunscreen = SunscreenChoice(spfLabel: 30, application: .normal)

        /// A June 2026 instant, in the fixture's zone.
        static func at(day: Int, hour: Int, minute: Int = 0) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let parts = DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute)
            return calendar.date(from: parts)!
        }

        /// The thirteenth, the fourteenth and the fifteenth of June.
        static func day(_ dayOfMonth: Int) -> DayKey {
            DayKey(at(day: dayOfMonth, hour: 12), timeZone: zone)
        }

        /// Well after every session below, so nothing here depends on where the
        /// clock stands.
        static let now = at(day: 16, hour: 9)

        /// An hour on the given day.
        static func hour(_ dayOfMonth: Int, from startHour: Int) -> Window {
            Window(start: at(day: dayOfMonth, hour: startHour), end: at(day: dayOfMonth, hour: startHour + 1))
        }

        /// Flat UV index 8 from the day's local midnight through the day after.
        static func storedCurve(_ dayOfMonth: Int) -> StoredCurve {
            let opens = day(dayOfMonth).start()
            return StoredCurve(
                hourly: (0 ... 48).map { HourlyUVI(time: opens.addingTimeInterval(Double($0) * 3600), uvi: 8) },
                solarNoon: opens.addingTimeInterval(43200),
                timeZoneID: zone.identifier,
                location: place,
                fetchedAt: at(day: dayOfMonth, hour: 9)
            )
        }

        /// One session on a day, up and about unless asked otherwise.
        static func record(
            id: UUID = UUID(),
            on dayOfMonth: Int,
            window: Window? = nil,
            posture: Posture = .upAndAbout,
            cover: Bool = false,
            factors: [Region: Double] = [.front: 1.1, .back: 1.1, .headAndShoulders: 1.2],
            targets: [Region: SED] = [.front: 2.7, .back: 2.7, .headAndShoulders: 2.4]
        ) -> SessionRecord {
            let span = window ?? hour(dayOfMonth, from: 10)
            return SessionRecord(
                id: id,
                day: day(dayOfMonth),
                createdAt: span.start.addingTimeInterval(-600),
                plannedWindow: span,
                plannedIntervals: [ExposureInterval(exposure: .upAndAbout, window: span)],
                firstSide: .faceUp,
                posture: posture,
                coverHeadAndShoulders: cover,
                intent: .bestMinutes,
                ceilingAtPlan: .standard,
                prescribedSunscreen: sunscreen,
                state: .planned,
                dosePerRegion: [:],
                factorsShown: factors,
                targetsShown: targets,
                curveUsed: storedCurve(dayOfMonth),
                forecastFetchedAt: at(day: dayOfMonth, hour: 9),
                forecastPlace: place
            )
        }

        /// A dose the tests can add up in their heads.
        static func dose(_ amount: SED) -> [Region: SED] {
            [.front: amount, .back: amount, .headAndShoulders: amount * 2]
        }
    }

    /// A composed environment, with the store to hand so a test can plan, log and
    /// discard exactly what it means to show.
    @MainActor
    private struct HistoryHarness {
        let environment: AppEnvironment

        static func make() -> HistoryHarness {
            let tunables = Tunables.current
            let environment = AppEnvironment(
                forecast: ForecastService(
                    provider: SilentProvider(), cache: MemoryForecastCache(), tunables: tunables
                ),
                location: LocationService(
                    source: FakeLocationSource(reading: .denied), resolver: FakePlaceResolver(table: [:])
                ),
                history: HistoryStore.inMemory(tunables: tunables, profile: HistoryFixture.profile),
                profile: MemoryProfileStore(profile: HistoryFixture.profile),
                prompts: PromptScheduler(port: FakeNotificationPort(authorization: .granted), tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { HistoryFixture.now }
            )
            return HistoryHarness(environment: environment)
        }

        /// A session the user planned and never answered for.
        @discardableResult
        func plan(_ record: SessionRecord) async throws -> SessionRecord {
            try await environment.history.upsertPlanned(record, replacing: nil)
            return record
        }

        /// A session the user did, at the dose given.
        @discardableResult
        func log(
            _ record: SessionRecord,
            dose: [Region: SED],
            wearing: SunscreenChoice? = nil
        ) async throws -> SessionRecord {
            try await plan(record)
            try await environment.history.log(
                record.id,
                actual: record.plannedIntervals,
                sunscreen: wearing,
                doses: dose,
                factors: record.factorsShown,
                targets: record.targetsShown
            )
            return record
        }

        /// A session that was logged and then thrown away — its dose is still on
        /// the record, and History must count none of it.
        @discardableResult
        func loggedThenDiscarded(_ record: SessionRecord, dose: [Region: SED]) async throws -> SessionRecord {
            try await log(record, dose: dose)
            try await environment.history.discard(record.id)
            return record
        }

        @discardableResult
        func report(
            on dayOfMonth: Int,
            answer: SkinAnswer,
            timing: RednessTiming? = nil
        ) async throws -> SkinReport {
            let report = SkinReport(
                day: HistoryFixture.day(dayOfMonth),
                reportedAt: HistoryFixture.at(day: dayOfMonth + 1, hour: 9),
                answer: answer,
                timing: timing,
                region: .allExposed,
                channel: .inApp
            )
            _ = try await environment.history.addReport(report)
            return report
        }

        /// The model, reloaded at the fixture's instant.
        func reloaded() async -> HistoryModel {
            let model = HistoryModel(env: environment)
            await model.reload(now: HistoryFixture.now)
            return model
        }

        func storedSession(_ id: UUID) async throws -> SessionRecord {
            let sessions = try await environment.history.history().sessions
            return try XCTUnwrap(sessions.first { $0.id == id }, "no session \(id)")
        }
    }

    /// The row for a day, or a failure naming the days that were there instead —
    /// which is the thing worth reading when one of these fails.
    @MainActor
    private func row(
        _ model: HistoryModel,
        _ day: DayKey,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> DaySummaryRow {
        try XCTUnwrap(
            model.days.first { $0.id == day },
            "no row for \(day.id); the model listed \(model.days.map(\.id.id))",
            file: file,
            line: line
        )
    }

    /// Doses are floating point: compare region by region, to the last place a
    /// difference could mean anything. A region the row never mentions counts as
    /// no dose at all, so a missing key fails against a non-zero expectation.
    private func assertDoses(
        _ actual: [Region: SED],
        _ expected: [Region: SED],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (region, value) in expected {
            XCTAssertEqual(actual[region] ?? 0, value, accuracy: 1e-9, "\(region)", file: file, line: line)
        }
    }

    // MARK: - Nothing is read until it is asked for

    @MainActor
    final class HistoryModelLoadingTests: XCTestCase {
        /// A new model has read nothing, even with a history to read: the screen
        /// asks, and until it does there is nothing to show.
        func testANewModelListsNoDaysUntilItIsReloaded() async throws {
            let harness = HistoryHarness.make()
            try await harness.log(HistoryFixture.record(on: 15), dose: HistoryFixture.dose(1))

            let model = HistoryModel(env: harness.environment)

            XCTAssertTrue(model.days.isEmpty, "a model that has not reloaded has read nothing")

            await model.reload(now: HistoryFixture.now)

            XCTAssertEqual(model.days.count, 1, "the reload is what reads the record")
        }

        /// An empty history is a screen with nothing on it, not a failure.
        func testAHistoryWithNothingInItReloadsToNoDays() async {
            let harness = HistoryHarness.make()

            let model = await harness.reloaded()

            XCTAssertTrue(model.days.isEmpty)
        }

        /// Reloading is how the screen comes back after a change, so it replaces
        /// what it read rather than adding to it.
        func testReloadingTwiceLeavesTheSameRows() async throws {
            let harness = HistoryHarness.make()
            try await harness.log(HistoryFixture.record(on: 14), dose: HistoryFixture.dose(1))
            try await harness.log(HistoryFixture.record(on: 15), dose: HistoryFixture.dose(2))
            let model = await harness.reloaded()
            let first = model.days

            await model.reload(now: HistoryFixture.now)

            XCTAssertEqual(model.days, first)
            XCTAssertEqual(model.days.count, 2, "two days were logged, not more")
        }
    }

    // MARK: - The order the log is read in (R24)

    @MainActor
    final class HistoryModelOrderTests: XCTestCase {
        /// Newest first: the day the user is most likely to be looking for is the
        /// one they just had.
        func testTheDaysAreListedNewestFirst() async throws {
            let harness = HistoryHarness.make()
            for dayOfMonth in [13, 15, 14] {
                try await harness.log(HistoryFixture.record(on: dayOfMonth), dose: HistoryFixture.dose(1))
            }

            let model = await harness.reloaded()

            XCTAssertEqual(
                model.days.map(\.id),
                [HistoryFixture.day(15), HistoryFixture.day(14), HistoryFixture.day(13)]
            )
        }

        /// One row per day, however many sessions that day held.
        func testADayWithTwoSessionsIsOneRowCarryingBothOfThem() async throws {
            let harness = HistoryHarness.make()
            let morning = try await harness.log(
                HistoryFixture.record(on: 15, window: HistoryFixture.hour(15, from: 10)),
                dose: HistoryFixture.dose(1)
            )
            let afternoon = try await harness.log(
                HistoryFixture.record(on: 15, window: HistoryFixture.hour(15, from: 14)),
                dose: HistoryFixture.dose(2)
            )

            let model = await harness.reloaded()

            XCTAssertEqual(model.days.count, 1)
            let day = try row(model, HistoryFixture.day(15))
            XCTAssertEqual(Set(day.sessions.map(\.id)), [morning.id, afternoon.id])
        }
    }

    // MARK: - What the log leaves out (R24, R45)

    /// Only what the user actually did is a record of what they did: a session
    /// they planned and never answered for, and one they threw away, are both
    /// absent — and neither contributes a dose.
    @MainActor
    final class HistoryModelHiddenSessionsTests: XCTestCase {
        func testADiscardedSessionIsNotListedAndItsDoseIsNotCounted() async throws {
            let harness = HistoryHarness.make()
            let kept = try await harness.log(
                HistoryFixture.record(on: 15, window: HistoryFixture.hour(15, from: 10)),
                dose: HistoryFixture.dose(1)
            )
            try await harness.loggedThenDiscarded(
                HistoryFixture.record(on: 15, window: HistoryFixture.hour(15, from: 14)),
                dose: HistoryFixture.dose(5)
            )

            let model = await harness.reloaded()

            let day = try row(model, HistoryFixture.day(15))
            XCTAssertEqual(day.sessions.map(\.id), [kept.id])
            assertDoses(day.dosePerRegion, HistoryFixture.dose(1))
        }

        func testAPlannedSessionIsNotListedAndItsDayIsNotShown() async throws {
            let harness = HistoryHarness.make()
            try await harness.plan(HistoryFixture.record(on: 14))
            let done = try await harness.log(HistoryFixture.record(on: 15), dose: HistoryFixture.dose(1))

            let model = await harness.reloaded()

            XCTAssertEqual(model.days.map(\.id), [HistoryFixture.day(15)])
            XCTAssertEqual(try row(model, HistoryFixture.day(15)).sessions.map(\.id), [done.id])
        }

        /// A day whose only sessions were discarded is not a day the user did
        /// anything on, so the log does not show it at all.
        func testADayWhoseOnlySessionWasDiscardedIsNotADayAtAll() async throws {
            let harness = HistoryHarness.make()
            let thrownAway = try await harness.loggedThenDiscarded(
                HistoryFixture.record(on: 15), dose: HistoryFixture.dose(3)
            )

            let model = await harness.reloaded()

            XCTAssertTrue(model.days.isEmpty)
            let stored = try await harness.storedSession(thrownAway.id)
            XCTAssertEqual(stored.state, .discarded, "the record is still there; History just hides it")
        }
    }

    // MARK: - What each row carries (R22, R24)

    @MainActor
    final class HistoryModelRowContentTests: XCTestCase {
        /// The day's dose per region is the sum over its sessions, region by
        /// region. The two hours below are deliberately unequal, so a row that
        /// showed one session's dose could not pass.
        func testThePerRegionDoseIsTheSumOfTheDaysSessions() async throws {
            let harness = HistoryHarness.make()
            try await harness.log(
                HistoryFixture.record(on: 15, window: HistoryFixture.hour(15, from: 10)),
                dose: HistoryFixture.dose(1.5)
            )
            try await harness.log(
                HistoryFixture.record(on: 15, window: HistoryFixture.hour(15, from: 14)),
                dose: HistoryFixture.dose(0.25)
            )

            let model = await harness.reloaded()

            try assertDoses(row(model, HistoryFixture.day(15)).dosePerRegion, HistoryFixture.dose(1.75))
        }

        /// Each day's own dose, never the running total: two days are two rows
        /// with a dose each.
        func testEachDaysDoseIsItsOwnAndNotAccumulated() async throws {
            let harness = HistoryHarness.make()
            try await harness.log(HistoryFixture.record(on: 14), dose: HistoryFixture.dose(1))
            try await harness.log(HistoryFixture.record(on: 15), dose: HistoryFixture.dose(2))

            let model = await harness.reloaded()

            try assertDoses(row(model, HistoryFixture.day(14)).dosePerRegion, HistoryFixture.dose(1))
            try assertDoses(row(model, HistoryFixture.day(15)).dosePerRegion, HistoryFixture.dose(2))
        }

        /// The row hands the detail screen the record itself, so what the user
        /// was shown at the time — the factors, the targets, the curve and the
        /// place the forecast was for — survives to the screen that shows it
        /// (R22).
        func testTheListedSessionCarriesTheStoredFiguresAndTheForecastPlace() async throws {
            let harness = HistoryHarness.make()
            let record = HistoryFixture.record(on: 15)
            try await harness.log(record, dose: HistoryFixture.dose(1), wearing: HistoryFixture.sunscreen)

            let model = await harness.reloaded()

            let listed = try XCTUnwrap(try row(model, HistoryFixture.day(15)).sessions.first)
            XCTAssertEqual(listed.state, .logged)
            XCTAssertEqual(listed.factorsShown, record.factorsShown)
            XCTAssertEqual(listed.targetsShown, record.targetsShown)
            XCTAssertEqual(listed.forecastPlace, HistoryFixture.place)
            XCTAssertEqual(listed.curveUsed, record.curveUsed)
            XCTAssertEqual(listed.posture, record.posture)
            XCTAssertEqual(listed.sunscreen, HistoryFixture.sunscreen, "what was confirmed, not what was prescribed")
            XCTAssertEqual(listed.actualWindow, record.plannedWindow, "the window the user actually faced")
        }

        /// Sunscreen is the user's own confirmation: a session logged bare says
        /// so, whatever the result prescribed.
        func testASessionLoggedBareCarriesNoSunscreen() async throws {
            let harness = HistoryHarness.make()
            let record = HistoryFixture.record(on: 15)
            try await harness.log(record, dose: HistoryFixture.dose(1))

            let model = await harness.reloaded()

            let listed = try XCTUnwrap(try row(model, HistoryFixture.day(15)).sessions.first)
            XCTAssertNil(listed.sunscreen)
            XCTAssertEqual(listed.prescribedSunscreen, HistoryFixture.sunscreen, "the prescription is still on record")
        }
    }

    // MARK: - The day's outcome (R20, R24)

    /// The report is the day's outcome, and it belongs to the day it was about —
    /// never to the day it was answered on.
    @MainActor
    final class HistoryModelReportTests: XCTestCase {
        func testTheDaysReportIsAttachedToThatDayAndToNoOther() async throws {
            let harness = HistoryHarness.make()
            try await harness.log(HistoryFixture.record(on: 14), dose: HistoryFixture.dose(1))
            try await harness.log(HistoryFixture.record(on: 15), dose: HistoryFixture.dose(1))
            let answered = try await harness.report(on: 15, answer: .faintPink, timing: .nextMorning)

            let model = await harness.reloaded()

            let reported = try row(model, HistoryFixture.day(15))
            XCTAssertEqual(reported.report?.id, answered.id)
            XCTAssertEqual(reported.report?.answer, .faintPink)
            XCTAssertNil(try row(model, HistoryFixture.day(14)).report, "the fourteenth was never reported on")
        }

        /// A day nobody answered for is still a day the user had a session on.
        func testADayWithNoReportIsStillListed() async throws {
            let harness = HistoryHarness.make()
            let done = try await harness.log(HistoryFixture.record(on: 15), dose: HistoryFixture.dose(1))

            let model = await harness.reloaded()

            let day = try row(model, HistoryFixture.day(15))
            XCTAssertNil(day.report)
            XCTAssertEqual(day.sessions.map(\.id), [done.id])
        }

        /// A report about a day with no logged session has no row to sit on, and
        /// does not conjure one (R45): History lists what was done.
        func testAReportOnADayWithNothingLoggedAddsNoRow() async throws {
            let harness = HistoryHarness.make()
            try await harness.plan(HistoryFixture.record(on: 15))
            _ = try await harness.report(on: 15, answer: .normal)

            let model = await harness.reloaded()

            XCTAssertTrue(model.days.isEmpty)
        }
    }

    // MARK: - The screen declares its slots (R39, S15)

    @MainActor
    final class HistoryViewManifestTests: XCTestCase {
        /// History is nothing but figures — doses the user could act on — so no
        /// banner may sit under it.
        func testHistoryCarriesNoBannerAndShowsFigures() {
            XCTAssertFalse(HistoryView.hasBannerSlot)
            XCTAssertTrue(HistoryView.showsFigures)
        }

        func testHistoryAgreesWithItsRowInTheTable() throws {
            let row = try XCTUnwrap(ScreenTable.row("HistoryView"))
            XCTAssertEqual(row.hasBanner, HistoryView.hasBannerSlot)
            XCTAssertEqual(row.showsFigures, HistoryView.showsFigures)
            XCTAssertFalse(row.hasBanner)
            XCTAssertTrue(row.showsFigures)
        }
    }
#endif
