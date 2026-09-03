#if canImport(SwiftUI)
    import Foundation
    import IcarusAds
    import IcarusContent
    import IcarusCore
    import IcarusData
    @testable import IcarusUI
    import XCTest

    // Slice 2 of `logging-calibration`, asserted against the model alone and never
    // against a rendered view: the promise is what the answer does to the day's
    // stored report, and that is reachable without a host application.
    //
    // The boundaries are faked and nothing else is — the forecast provider (the
    // network), the location source (the device), the notification port (the
    // system centre) and the clock. `LastingColourModel`, which is what this slice
    // delivers, runs for real against the real history store and the real prompt
    // scheduler.
    //
    // Every fixture here is file-private: a fixture in a test target is shared
    // with every other file in it, and these names are ours.

    // MARK: - Fixtures

    /// The network, which never answers. Nothing in the lasting-colour question
    /// may reach for a forecast: it is about a day that is days gone.
    private struct SilentProvider: UVForecastProvider {
        let name = "lasting-colour-test"

        func forecast(at _: Coordinate, days _: Int) async throws(ProviderError) -> ProviderForecast {
            throw ProviderError.network("the test provider is offline")
        }
    }

    /// Fixed instants only: one flat session day, the morning after it when the
    /// skin check was answered, and the day four days later when the colour
    /// question is asked. Nothing here reads the wall clock.
    private enum ColourFixture {
        static let zone = TimeZone(identifier: "UTC")!
        static let place = Coordinate(latitude: 59.91, longitude: 10.75)
        static let profile = Profile(skinType: .iii, ceiling: .standard)
        static let oneDay: TimeInterval = 86400

        static func at(_ hour: Int, _ minute: Int = 0) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: hour, minute: minute))!
        }

        /// 09:00 the day after the session: when the skin check was answered.
        static let reportedAt = at(9).addingTimeInterval(oneDay)

        /// Four days after that answer: when the colour question is asked (R20).
        static let answeredAt = reportedAt.addingTimeInterval(4 * oneDay)

        static var day: DayKey {
            DayKey(at(10), timeZone: zone)
        }

        /// The day after the session day — a second reported day, so a test can
        /// show that answering one leaves the other alone.
        static var nextDay: DayKey {
            DayKey(at(10).addingTimeInterval(oneDay), timeZone: zone)
        }

        /// The hour that day was spent outside, in that day's own local morning.
        static func morning(of key: DayKey) -> Window {
            let opens = key.start().addingTimeInterval(10 * 3600)
            return Window(start: opens, end: opens.addingTimeInterval(3600))
        }

        /// Flat UV index 8 from local midnight through the two days after it.
        static func storedCurve(for key: DayKey) -> StoredCurve {
            let opens = key.start()
            let samples = (0 ... 72).map { HourlyUVI(time: opens.addingTimeInterval(Double($0) * 3600), uvi: 8) }
            return StoredCurve(
                hourly: samples,
                solarNoon: opens.addingTimeInterval(43200),
                timeZoneID: zone.identifier,
                location: place,
                fetchedAt: opens
            )
        }

        /// One planned session, up and about, nothing covered.
        static func record(on key: DayKey = day) -> SessionRecord {
            let window = morning(of: key)
            return SessionRecord(
                day: key,
                createdAt: window.start.addingTimeInterval(-600),
                plannedWindow: window,
                plannedIntervals: [ExposureInterval(exposure: .upAndAbout, window: window)],
                firstSide: .faceUp,
                posture: .upAndAbout,
                coverHeadAndShoulders: false,
                intent: .bestMinutes,
                ceilingAtPlan: .standard,
                state: .planned,
                dosePerRegion: [:],
                factorsShown: [.front: 1.0, .back: 1.0, .headAndShoulders: 1.0],
                targetsShown: [.front: 2.7, .back: 2.7, .headAndShoulders: 2.7],
                curveUsed: storedCurve(for: key),
                forecastFetchedAt: window.start.addingTimeInterval(-600),
                forecastPlace: place
            )
        }

        /// The bare dose the day's own curve gives those intervals.
        static func doses(over intervals: [ExposureInterval], on key: DayKey = day) throws -> [Region: SED] {
            let curve = try storedCurve(for: key).curve()
            var bare = [Region: SED]()
            for interval in intervals {
                let part = ExposureModel.dose(
                    interval.exposure,
                    coverHeadAndShoulders: false,
                    over: interval.window,
                    curve: curve,
                    tunables: Tunables.current
                )
                for (region, dose) in part {
                    bare[region, default: 0] += dose
                }
            }
            return ExposureModel.attenuated(bare, sunscreen: nil, coverHeadAndShoulders: false)
        }

        /// The skin check as it was answered: every field filled in, so a test can
        /// show the colour answer leaves all of them alone.
        static func report(on key: DayKey = day, at reported: Date = reportedAt) -> SkinReport {
            SkinReport(
                day: key,
                reportedAt: reported,
                answer: .clearlyPink,
                timing: .nextMorning,
                region: .back,
                confounders: [.alcohol, .altitude],
                channel: .notification
            )
        }
    }

    /// A composed environment with the fakes kept to hand, so a test can read the
    /// stored report and what is still due in-app.
    @MainActor
    private struct ColourHarness {
        let environment: AppEnvironment
        let port: FakeNotificationPort

        static func make() -> ColourHarness {
            let tunables = Tunables.current
            let port = FakeNotificationPort(authorization: .granted)
            let environment = AppEnvironment(
                forecast: ForecastService(
                    provider: SilentProvider(), cache: MemoryForecastCache(), tunables: tunables
                ),
                location: LocationService(
                    source: FakeLocationSource(reading: .denied), resolver: FakePlaceResolver(table: [:])
                ),
                history: HistoryStore.inMemory(tunables: tunables, profile: ColourFixture.profile),
                profile: MemoryProfileStore(profile: ColourFixture.profile),
                prompts: PromptScheduler(port: port, tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { ColourFixture.answeredAt }
            )
            return ColourHarness(environment: environment, port: port)
        }

        /// A logged session and the skin report about it — the state the app is in
        /// when the lasting-colour question comes round.
        @discardableResult
        func reportedDay(
            _ key: DayKey = ColourFixture.day,
            at reported: Date = ColourFixture.reportedAt
        ) async throws -> SkinReport {
            let record = ColourFixture.record(on: key)
            try await environment.history.upsertPlanned(record, replacing: nil)
            try await environment.history.log(
                record.id,
                actual: record.plannedIntervals,
                sunscreen: nil,
                doses: ColourFixture.doses(over: record.plannedIntervals, on: key),
                factors: record.factorsShown,
                targets: record.targetsShown
            )
            let report = ColourFixture.report(on: key, at: reported)
            _ = try await environment.history.addReport(report)
            await environment.prompts.reportAdded(on: key, at: reported)
            return report
        }

        func model(for key: DayKey = ColourFixture.day, channel: Channel = .notification) -> LastingColourModel {
            LastingColourModel(env: environment, day: key, channel: channel)
        }

        func reports() async throws -> [SkinReport] {
            try await environment.history.history().reports
        }

        func report(for key: DayKey) async throws -> SkinReport {
            let all = try await reports()
            return try XCTUnwrap(all.first { $0.day == key }, "no report for \(key.id)")
        }

        func dueInApp(now: Date) async throws -> [DuePrompt] {
            try await environment.prompts.dueInApp(history: environment.history.history(), now: now)
        }
    }

    // MARK: - Attaching the answer to the day's report (R20, R24)

    /// The question is asked about one day, and its answer lands on that day's
    /// report carrying the instant it was actually given — never the instant the
    /// skin check was answered, which is days earlier.
    @MainActor
    final class LastingColourSubmitTests: XCTestCase {
        func testAnsweringAttachesTheColourAndTheInstantItWasGiven() async throws {
            let harness = ColourHarness.make()
            try await harness.reportedDay()
            let model = harness.model()

            try await model.submit(.aLittle, now: ColourFixture.answeredAt)

            let stored = try await harness.report(for: ColourFixture.day)
            XCTAssertEqual(stored.lastingColour, .aLittle)
            XCTAssertEqual(stored.lastingColourAt, ColourFixture.answeredAt)
            XCTAssertEqual(
                stored.reportedAt, ColourFixture.reportedAt, "the skin check's own timestamp is untouched"
            )
            XCTAssertNotEqual(
                stored.lastingColourAt, stored.reportedAt, "the colour is answered days after the report"
            )
        }

        /// All three answers R20 offers are recorded as given, and none of them is
        /// treated as "nothing said".
        func testEachOfTheThreeAnswersIsRecordedAsGiven() async throws {
            for colour in [LastingColour.yes, .aLittle, .no] {
                let harness = ColourHarness.make()
                try await harness.reportedDay()
                let model = harness.model()

                try await model.submit(colour, now: ColourFixture.answeredAt)

                let stored = try await harness.report(for: ColourFixture.day)
                XCTAssertEqual(stored.lastingColour, colour, "\(colour)")
                XCTAssertNotNil(stored.lastingColourAt, "\(colour) is an answer, not a silence")
            }
        }

        /// The colour answer adds to the report and revises nothing in it: the
        /// skin check's answers are the evidence the replay already used.
        func testTheAnswerLeavesEverythingElseInTheReportAlone() async throws {
            let harness = ColourHarness.make()
            let before = try await harness.reportedDay()
            let model = harness.model(channel: .inApp)

            try await model.submit(.yes, now: ColourFixture.answeredAt)

            let stored = try await harness.report(for: ColourFixture.day)
            XCTAssertEqual(stored.id, before.id, "the same report, not a second one")
            XCTAssertEqual(stored.day, before.day)
            XCTAssertEqual(stored.answer, before.answer)
            XCTAssertEqual(stored.timing, before.timing)
            XCTAssertEqual(stored.region, before.region)
            XCTAssertEqual(stored.confounders, before.confounders)
            XCTAssertEqual(stored.channel, before.channel)
            let all = try await harness.reports()
            XCTAssertEqual(all.count, 1)
        }

        /// The model is about one day. Another day's report is not touched, even
        /// when it is waiting for the same question.
        func testOnlyTheDayTheModelIsAboutIsAnswered() async throws {
            let harness = ColourHarness.make()
            try await harness.reportedDay(ColourFixture.day)
            try await harness.reportedDay(
                ColourFixture.nextDay, at: ColourFixture.reportedAt.addingTimeInterval(ColourFixture.oneDay)
            )
            let model = harness.model(for: ColourFixture.day)

            try await model.submit(.no, now: ColourFixture.answeredAt)

            let answered = try await harness.report(for: ColourFixture.day)
            let untouched = try await harness.report(for: ColourFixture.nextDay)
            XCTAssertEqual(answered.lastingColour, .no)
            XCTAssertNil(untouched.lastingColour, "the next day's question has not been asked yet")
            XCTAssertNil(untouched.lastingColourAt)
        }

        /// The question only exists because a report does. A day with no report
        /// has nothing to attach an answer to, and nothing is invented for it.
        func testAnsweringForADayWithNoReportIsRefusedAndRecordsNothing() async throws {
            let harness = ColourHarness.make()
            let model = harness.model()

            do {
                try await model.submit(.yes, now: ColourFixture.answeredAt)
                XCTFail("a lasting colour needs a report to belong to")
            } catch let error as HistoryError {
                XCTAssertEqual(error, .noReport(ColourFixture.day))
            }

            let all = try await harness.reports()
            XCTAssertTrue(all.isEmpty, "a refused answer writes no report of its own")
        }
    }

    // MARK: - Answering removes the in-app card (R20)

    /// The in-app card is the fallback for a question the notification never got
    /// answered. Answering it is what takes the day off the card.
    @MainActor
    final class LastingColourInAppCardTests: XCTestCase {
        /// Three days after the report the day is on the card; once answered it
        /// is not, at the same instant.
        func testAnsweringTakesTheDayOffTheInAppCard() async throws {
            let harness = ColourHarness.make()
            try await harness.reportedDay()
            let model = harness.model(channel: .inApp)

            let before = try await harness.dueInApp(now: ColourFixture.answeredAt)
            try await model.submit(.aLittle, now: ColourFixture.answeredAt)
            let after = try await harness.dueInApp(now: ColourFixture.answeredAt)

            XCTAssertEqual(before, [.lastingColour(ColourFixture.day)])
            XCTAssertEqual(after, [], "the question has been answered")
        }

        /// Answering one day's question leaves another day's on the card.
        func testAnsweringOneDayLeavesAnotherDayOnTheCard() async throws {
            let harness = ColourHarness.make()
            try await harness.reportedDay(ColourFixture.day)
            try await harness.reportedDay(
                ColourFixture.nextDay, at: ColourFixture.reportedAt.addingTimeInterval(ColourFixture.oneDay)
            )
            let model = harness.model(for: ColourFixture.day, channel: .inApp)

            try await model.submit(.yes, now: ColourFixture.answeredAt)

            let due = try await harness.dueInApp(now: ColourFixture.answeredAt.addingTimeInterval(ColourFixture.oneDay))
            XCTAssertEqual(due, [.lastingColour(ColourFixture.nextDay)])
        }
    }

    // MARK: - The screen declares its slots (R39, S15)

    @MainActor
    final class LastingColourFlowManifestTests: XCTestCase {
        /// One question and no numbers, so no banner and no figure.
        func testTheLastingColourFlowCarriesNoBannerAndShowsNoFigure() throws {
            XCTAssertFalse(LastingColourFlow.hasBannerSlot)
            XCTAssertFalse(LastingColourFlow.showsFigures)

            let row = try XCTUnwrap(ScreenTable.row("LastingColourFlow"))
            XCTAssertEqual(row.hasBanner, LastingColourFlow.hasBannerSlot)
            XCTAssertEqual(row.showsFigures, LastingColourFlow.showsFigures)
        }
    }
#endif
