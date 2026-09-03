#if canImport(SwiftUI)
    import Foundation
    import IcarusAds
    import IcarusContent
    import IcarusCore
    import IcarusData
    @testable import IcarusUI
    import XCTest

    // Slice 1 of `logging-calibration`, asserted against the model and the router
    // and never against a rendered view: a view test would need a host
    // application, and every promise the slice makes is reachable without one.
    //
    // The boundaries are faked and nothing else is — the forecast provider (the
    // network), the location source (the device), the notification port (the
    // system centre) and the clock. `SkinCheckModel` and `NotificationRouting`,
    // which are what this slice delivers, run for real against the real history
    // store, the real calibration replay and the real prompt scheduler.
    //
    // Every fixture type here is file-private on purpose: a fixture in a test
    // target is shared with every other file in it, and these names are ours.

    // MARK: - Fixtures

    /// The network, which never answers. Nothing in the skin-check flow may reach
    /// for a forecast: the day it is about is over, and the record already holds
    /// the curve it was solved from.
    private struct OfflineProvider: UVForecastProvider {
        let name = "skin-check-test"

        func forecast(at _: Coordinate, days _: Int) async throws(ProviderError) -> ProviderForecast {
            throw ProviderError.network("the test provider is offline")
        }
    }

    /// Fixed values only: one flat day at one place, read in UTC, and the morning
    /// after it. Nothing here reads the wall clock.
    ///
    /// A flat UV index of 8 is 7.196 SED an hour to bare skin, so an hour up and
    /// about gives the head and shoulders 7.196 SED and each torso side half of
    /// it — about 1.2 times a type III user's estimated threshold of 3.0 SED.
    private enum Fixture {
        static let zone = TimeZone(identifier: "UTC")!
        static let place = Coordinate(latitude: 59.91, longitude: 10.75)
        static let profile = Profile(skinType: .iii, ceiling: .standard)
        static let prescribed = SunscreenChoice(spfLabel: 30, application: .normal)

        static func at(_ hour: Int, _ minute: Int = 0) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: hour, minute: minute))!
        }

        /// 09:00 the day after the session — when the skin check is answered.
        static let answeredAt = at(9).addingTimeInterval(86400)

        static var day: DayKey {
            DayKey(at(10), timeZone: zone)
        }

        /// The planned hour, and an afternoon session for the days that have two.
        static var morning: Window {
            Window(start: at(10), end: at(11))
        }

        static var afternoon: Window {
            Window(start: at(14), end: at(15))
        }

        /// Flat UV index 8 from local midnight through the following day.
        static var hourly: [HourlyUVI] {
            let opens = day.start()
            return (0 ... 48).map { HourlyUVI(time: opens.addingTimeInterval(Double($0) * 3600), uvi: 8) }
        }

        static var storedCurve: StoredCurve {
            StoredCurve(
                hourly: hourly,
                solarNoon: day.start().addingTimeInterval(43200),
                timeZoneID: zone.identifier,
                location: place,
                fetchedAt: at(9)
            )
        }

        /// One planned session, up and about, nothing covered. `prescribed` is
        /// the pair the result recommended, or nil when it recommended none.
        static func record(
            id: UUID = UUID(),
            window: Window = morning,
            prescribed pair: SunscreenChoice? = prescribed
        ) -> SessionRecord {
            SessionRecord(
                id: id,
                day: day,
                createdAt: window.start.addingTimeInterval(-600),
                plannedWindow: window,
                plannedIntervals: [ExposureInterval(exposure: .upAndAbout, window: window)],
                firstSide: .faceUp,
                posture: .upAndAbout,
                coverHeadAndShoulders: false,
                intent: .bestMinutes,
                ceilingAtPlan: .standard,
                prescribedSunscreen: pair,
                state: .planned,
                dosePerRegion: [:],
                factorsShown: [.front: 1.0, .back: 1.0, .headAndShoulders: 1.0],
                targetsShown: [.front: 2.7, .back: 2.7, .headAndShoulders: 2.7],
                curveUsed: storedCurve,
                forecastFetchedAt: at(9),
                forecastPlace: place
            )
        }

        /// What the slice promises a logged session is credited with: the day's
        /// own stored curve integrated over the intervals actually faced, then
        /// attenuated by what the user says they wore.
        static func doses(
            over intervals: [ExposureInterval],
            wearing sunscreen: SunscreenChoice?,
            cover: Bool = false
        ) throws -> [Region: SED] {
            let curve = try storedCurve.curve()
            var bare = [Region: SED]()
            for interval in intervals {
                let part = ExposureModel.dose(
                    interval.exposure,
                    coverHeadAndShoulders: cover,
                    over: interval.window,
                    curve: curve,
                    tunables: Tunables.current
                )
                for (region, dose) in part {
                    bare[region, default: 0] += dose
                }
            }
            return ExposureModel.attenuated(bare, sunscreen: sunscreen, coverHeadAndShoulders: cover)
        }
    }

    /// A composed environment with the fakes kept to hand, so a test can read the
    /// pending alerts and the stored record.
    @MainActor
    private struct SkinCheckHarness {
        let environment: AppEnvironment
        let port: FakeNotificationPort

        static func make() -> SkinCheckHarness {
            let tunables = Tunables.current
            let port = FakeNotificationPort(authorization: .granted)
            let environment = AppEnvironment(
                forecast: ForecastService(
                    provider: OfflineProvider(), cache: MemoryForecastCache(), tunables: tunables
                ),
                location: LocationService(
                    source: FakeLocationSource(reading: .denied), resolver: FakePlaceResolver(table: [:])
                ),
                history: HistoryStore.inMemory(tunables: tunables, profile: Fixture.profile),
                profile: MemoryProfileStore(profile: Fixture.profile),
                prompts: PromptScheduler(port: port, tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { Fixture.answeredAt }
            )
            return SkinCheckHarness(environment: environment, port: port)
        }

        func plan(_ record: SessionRecord) async throws {
            try await environment.history.upsertPlanned(record, replacing: nil)
        }

        /// A session already logged before the flow opens — the one the day-after
        /// prompt has nothing left to ask about.
        func log(_ record: SessionRecord) async throws {
            try await plan(record)
            try await environment.history.log(
                record.id,
                actual: record.plannedIntervals,
                sunscreen: nil,
                doses: Fixture.doses(over: record.plannedIntervals, wearing: nil),
                factors: record.factorsShown,
                targets: record.targetsShown
            )
        }

        /// The model as the notification opens it, with its planned sessions read.
        func model(channel: Channel = .notification) async -> SkinCheckModel {
            let model = SkinCheckModel(env: environment, day: Fixture.day, channel: channel)
            await model.load()
            return model
        }

        func session(_ id: UUID) async throws -> SessionRecord {
            let sessions = try await environment.history.history().sessions
            return try XCTUnwrap(sessions.first { $0.id == id }, "no session \(id)")
        }

        func reports() async throws -> [SkinReport] {
            try await environment.history.history().reports
        }
    }

    /// Doses are floating point: compare region by region, to the last place a
    /// difference could mean anything.
    private func assertSameDoses(
        _ actual: [Region: SED],
        _ expected: [Region: SED],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(actual.keys), Set(expected.keys), file: file, line: line)
        for (region, value) in expected {
            XCTAssertEqual(actual[region] ?? .nan, value, accuracy: 1e-9, "\(region)", file: file, line: line)
        }
    }

    // MARK: - What the flow opens with (R20, R45)

    /// The prompt is about one day, and it asks "did you do this session?" only
    /// about the sessions that day still has planned.
    @MainActor
    final class SkinCheckPlannedSessionsTests: XCTestCase {
        func testTheFlowOpensWithTheDaysStillPlannedSessionsAndNoOthers() async throws {
            let harness = SkinCheckHarness.make()
            let stillPlanned = Fixture.record(window: Fixture.morning)
            let alreadyLogged = Fixture.record(window: Fixture.afternoon)
            try await harness.plan(stillPlanned)
            try await harness.log(alreadyLogged)

            let model = await harness.model()

            XCTAssertEqual(model.planned.map(\.id), [stillPlanned.id])
            XCTAssertTrue(model.hasLoggedSession, "the day already has a logged session")
        }

        /// A discarded session is not asked about again, and it is not a logged
        /// session either.
        func testADiscardedSessionIsNeitherAskedAboutNorCountedAsLogged() async throws {
            let harness = SkinCheckHarness.make()
            let record = Fixture.record()
            try await harness.plan(record)
            try await harness.environment.history.discard(record.id)

            let model = await harness.model()

            XCTAssertTrue(model.planned.isEmpty)
            XCTAssertFalse(model.hasLoggedSession)
        }

        /// The three answers the user has not given yet: the region starts at
        /// "all exposed" (R20's default) and nothing else is chosen for them.
        func testTheRegionStartsAtAllExposedAndNothingElseIsAnswered() async throws {
            let harness = SkinCheckHarness.make()
            try await harness.plan(Fixture.record())

            let model = await harness.model()

            XCTAssertEqual(model.region, .allExposed)
            XCTAssertNil(model.answer)
            XCTAssertNil(model.timing)
            XCTAssertTrue(model.confounders.isEmpty)
        }
    }

    // MARK: - "Did you do this session?" (R20, R22, R45)

    /// "No" discards the session; "yes" logs it from the intervals on the screen,
    /// with the dose the day's own curve gives them through what was worn.
    @MainActor
    final class SkinCheckDidYouDoThisTests: XCTestCase {
        func testSayingNoDiscardsTheSessionAndLogsNothing() async throws {
            let harness = SkinCheckHarness.make()
            let record = Fixture.record()
            try await harness.plan(record)
            let model = await harness.model()

            try await model.didNotDo(record.id)

            XCTAssertTrue(model.planned.isEmpty, "a session answered for is no longer asked about")
            XCTAssertFalse(model.hasLoggedSession)
            let stored = try await harness.session(record.id)
            XCTAssertEqual(stored.state, .discarded)
            XCTAssertNil(stored.actualIntervals)
        }

        func testSayingYesAsPrescribedLogsThatPairAndItsAttenuatedDose() async throws {
            let harness = SkinCheckHarness.make()
            let record = Fixture.record()
            try await harness.plan(record)
            let model = await harness.model()

            try await model.didDo(record.id, actual: record.plannedIntervals, wore: .asPrescribed)

            let stored = try await harness.session(record.id)
            XCTAssertEqual(stored.state, .logged)
            XCTAssertEqual(stored.sunscreen, Fixture.prescribed, "as prescribed is the record's own pair")
            XCTAssertEqual(stored.actualIntervals, record.plannedIntervals)
            try assertSameDoses(
                stored.dosePerRegion,
                Fixture.doses(over: record.plannedIntervals, wearing: Fixture.prescribed)
            )
            XCTAssertTrue(model.planned.isEmpty)
            XCTAssertTrue(model.hasLoggedSession)
        }

        /// The factors and targets the user was shown are the record's own and
        /// survive the log unchanged (R22) — they are display history, and a log
        /// must never invent them.
        func testLoggingKeepsTheFactorsAndTargetsTheUserWasShown() async throws {
            let harness = SkinCheckHarness.make()
            let record = Fixture.record()
            try await harness.plan(record)
            let model = await harness.model()

            try await model.didDo(record.id, actual: record.plannedIntervals, wore: SunscreenConfirmation.none)

            let stored = try await harness.session(record.id)
            XCTAssertEqual(stored.factorsShown, record.factorsShown)
            XCTAssertEqual(stored.targetsShown, record.targetsShown)
        }

        /// "As prescribed" against a result that prescribed nothing has no pair to
        /// resolve to, so it is refused rather than logged as bare.
        func testAsPrescribedOnASessionThatPrescribedNothingIsRefused() async throws {
            let harness = SkinCheckHarness.make()
            let record = Fixture.record(prescribed: nil)
            try await harness.plan(record)
            let model = await harness.model()

            do {
                try await model.didDo(record.id, actual: record.plannedIntervals, wore: .asPrescribed)
                XCTFail("a session with no prescription has nothing to confirm")
            } catch let error as SkinCheckError {
                XCTAssertEqual(error, .noPrescription(record.id))
            }

            let stored = try await harness.session(record.id)
            XCTAssertEqual(stored.state, .planned, "a refused answer records nothing")
            XCTAssertEqual(model.planned.map(\.id), [record.id], "the question is still open")
        }

        /// "I wore my own": the log is credited against the product the user names,
        /// never against the one that was prescribed.
        func testWearingAnotherProductIsCreditedAgainstThatProduct() async throws {
            let harness = SkinCheckHarness.make()
            let record = Fixture.record()
            try await harness.plan(record)
            let model = await harness.model()
            let own = SunscreenChoice(spfLabel: 20, application: .thin)

            try await model.didDo(record.id, actual: record.plannedIntervals, wore: .alternative(own))

            let stored = try await harness.session(record.id)
            XCTAssertEqual(stored.sunscreen, own)
            try assertSameDoses(stored.dosePerRegion, Fixture.doses(over: record.plannedIntervals, wearing: own))
        }

        /// "None": nothing is recorded as worn, and the dose is the bare one.
        func testWearingNothingLogsNoSunscreenAndTheBareDose() async throws {
            let harness = SkinCheckHarness.make()
            let record = Fixture.record()
            try await harness.plan(record)
            let model = await harness.model()

            try await model.didDo(record.id, actual: record.plannedIntervals, wore: SunscreenConfirmation.none)

            let stored = try await harness.session(record.id)
            XCTAssertNil(stored.sunscreen)
            try assertSameDoses(stored.dosePerRegion, Fixture.doses(over: record.plannedIntervals, wearing: nil))
        }

        /// The intervals are editable, and the dose follows what was edited. The
        /// curve is flat, so half the planned hour is exactly half the dose —
        /// which is checked here without asking the exposure model anything.
        func testTheDoseFollowsTheEditedIntervalsRatherThanThePlannedOnes() async throws {
            let harness = SkinCheckHarness.make()
            let record = Fixture.record()
            try await harness.plan(record)
            let model = await harness.model()
            let halfAsLong = [ExposureInterval(
                exposure: .upAndAbout, window: Window(start: Fixture.at(10), end: Fixture.at(10, 30))
            )]

            try await model.didDo(record.id, actual: halfAsLong, wore: SunscreenConfirmation.none)

            let stored = try await harness.session(record.id)
            XCTAssertEqual(stored.actualIntervals, halfAsLong)
            try assertSameDoses(stored.dosePerRegion, Fixture.doses(over: halfAsLong, wearing: nil))
            let wholeHour = try Fixture.doses(over: record.plannedIntervals, wearing: nil)
            for region in Region.allCases {
                XCTAssertEqual(
                    stored.dosePerRegion[region] ?? .nan,
                    (wholeHour[region] ?? .nan) / 2,
                    accuracy: 1e-9,
                    "\(region): half the flat hour is half the dose"
                )
            }
        }
    }

    // MARK: - What may be submitted (R20, S10)

    /// Three things gate the submission: a logged session that day, an answer to
    /// Q1, and — only when Q1 reported redness — an answer to Q2.
    @MainActor
    final class SkinCheckSubmissionGateTests: XCTestCase {
        func testADayWithNothingLoggedCannotBeReportedAndRecordsNothing() async throws {
            let harness = SkinCheckHarness.make()
            try await harness.plan(Fixture.record())
            let model = await harness.model()

            model.answer = .normal

            XCTAssertFalse(model.hasLoggedSession)
            XCTAssertFalse(model.canSubmit, "there is nothing for a report to be evidence about")
            let reports = try await harness.reports()
            XCTAssertTrue(reports.isEmpty)
        }

        func testALoggedDayStillNeedsAnAnswerToQ1() async throws {
            let harness = SkinCheckHarness.make()
            try await harness.log(Fixture.record())
            let model = await harness.model()

            XCTAssertTrue(model.hasLoggedSession)
            XCTAssertFalse(model.canSubmit)
        }

        /// Q2 is asked if and only if Q1 reported redness, so every reddened
        /// answer waits for it and "normal" never does.
        func testEveryRednessAnswerWaitsForTheTimingAndNormalDoesNot() async throws {
            let harness = SkinCheckHarness.make()
            try await harness.log(Fixture.record())
            let model = await harness.model()

            model.answer = .normal
            XCTAssertTrue(model.canSubmit, "normal skin has no timing to report")

            for reddened in [SkinAnswer.faintPink, .clearlyPink, .redSore, .blistered] {
                model.answer = reddened
                model.timing = nil
                XCTAssertFalse(model.canSubmit, "\(reddened) needs Q2")
                model.timing = .thatEvening
                XCTAssertTrue(model.canSubmit, "\(reddened) with a timing is complete")
            }
        }
    }

    // MARK: - Submitting (R20, R21, S10)

    /// One report per day, carrying every answer, and the effect the replay
    /// applied comes back to the screen that has to explain it.
    @MainActor
    final class SkinCheckSubmitTests: XCTestCase {
        func testSubmittingWritesOneReportCarryingEveryAnswerAndTheChannel() async throws {
            let harness = SkinCheckHarness.make()
            try await harness.log(Fixture.record())
            let model = await harness.model(channel: .inApp)
            model.answer = .clearlyPink
            model.timing = .nextMorning
            model.region = .back
            model.confounders = [.alcohol, .altitude]

            _ = try await model.submit(now: Fixture.answeredAt)

            let reports = try await harness.reports()
            XCTAssertEqual(reports.count, 1)
            let report = try XCTUnwrap(reports.first)
            XCTAssertEqual(report.day, Fixture.day)
            XCTAssertEqual(report.reportedAt, Fixture.answeredAt)
            XCTAssertEqual(report.answer, .clearlyPink)
            XCTAssertEqual(report.timing, .nextMorning)
            XCTAssertEqual(report.region, .back)
            XCTAssertEqual(report.confounders, [.alcohol, .altitude])
            XCTAssertEqual(report.channel, .inApp)
            XCTAssertNil(report.lastingColour, "the lasting-colour answer is days away")
            XCTAssertNil(report.lastingColourAt)
        }

        /// The effect handed back is the store's own: a faint-pink report on a
        /// bare hour implies a threshold above the type III estimate, so the
        /// multiplier moves, and it moves to exactly what the replay now holds.
        func testTheEffectReturnedIsTheOneTheStoresReplayApplied() async throws {
            let harness = SkinCheckHarness.make()
            let record = Fixture.record()
            try await harness.plan(record)
            let model = await harness.model()
            try await model.didDo(record.id, actual: record.plannedIntervals, wore: SunscreenConfirmation.none)
            model.answer = .faintPink
            model.timing = .nextMorning

            let effect = try await model.submit(now: Fixture.answeredAt)

            guard case let .multiplierMoved(from, to) = effect else {
                return XCTFail("a faint pink report on a bare hour moves the multiplier, got \(effect)")
            }
            XCTAssertEqual(from, 1, accuracy: 1e-9, "the app had learned nothing before this report")
            XCTAssertGreaterThan(to, from, "the hour was past the estimate, so the estimate was too low")
            let state = try await harness.environment.history.state(now: Fixture.answeredAt)
            XCTAssertEqual(state.multiplier, to, accuracy: 1e-9)
            XCTAssertEqual(state.totalReports, 1)
        }

        /// The same day's evidence with no redness is a one-sided confirmation, so
        /// the effect it reports is not a multiplier move.
        func testANormalReportOnTheSameDayReportsADifferentEffect() async throws {
            let harness = SkinCheckHarness.make()
            let record = Fixture.record()
            try await harness.plan(record)
            let model = await harness.model()
            try await model.didDo(record.id, actual: record.plannedIntervals, wore: SunscreenConfirmation.none)
            model.answer = .normal

            let effect = try await model.submit(now: Fixture.answeredAt)

            if case .multiplierMoved = effect {
                XCTFail("a normal report is one-sided evidence, not a redness correction")
            }
            XCTAssertNotEqual(effect, .noDoseThatDay, "the day had a logged dose")
            let state = try await harness.environment.history.state(now: Fixture.answeredAt)
            XCTAssertEqual(state.totalReports, 1)
        }

        /// One report per day is all the app uses, so a second submission is
        /// refused and the first one stands (R20).
        func testASecondReportForTheSameDayIsRefused() async throws {
            let harness = SkinCheckHarness.make()
            try await harness.log(Fixture.record())
            let model = await harness.model()
            model.answer = .normal
            _ = try await model.submit(now: Fixture.answeredAt)

            do {
                _ = try await model.submit(now: Fixture.answeredAt.addingTimeInterval(600))
                XCTFail("a day may carry only one skin report")
            } catch let error as HistoryError {
                XCTAssertEqual(error, .alreadyReported(Fixture.day))
            }

            let reports = try await harness.reports()
            XCTAssertEqual(reports.count, 1)
            XCTAssertEqual(try XCTUnwrap(reports.first).reportedAt, Fixture.answeredAt)
        }

        /// Answering is what starts the lasting-colour clock: four days after the
        /// answer, never four days after the session (R20).
        func testSubmittingAsksTheLastingColourQuestionFourDaysLater() async throws {
            let harness = SkinCheckHarness.make()
            try await harness.log(Fixture.record())
            let model = await harness.model()
            model.answer = .normal

            _ = try await model.submit(now: Fixture.answeredAt)

            let pending = await harness.port.pending()
            let colour = try XCTUnwrap(
                pending.first { $0.kind == .lastingColour(Fixture.day) }, "no lasting-colour question was scheduled"
            )
            XCTAssertEqual(colour.id, "colour-\(Fixture.day.id)")
            XCTAssertEqual(colour.fireAt, Fixture.answeredAt.addingTimeInterval(4 * 86400))
        }
    }

    // MARK: - The confirmation the user is shown (R20, R21)

    /// Every effect the replay can apply has one line of approved copy, and the
    /// mapping is the model's, so it can be asserted without a view.
    @MainActor
    final class SkinCheckConfirmationCopyTests: XCTestCase {
        func testAnEffectThatOnlyRecordsTheReportSaysSoAndNothingMore() {
            for effect in [
                CalibrationEffect.none,
                .discounted,
                .tanStateCredited(.front, 0.2),
                .multiplierMoved(from: 1, to: 1.2),
            ] {
                XCTAssertEqual(SkinCheckModel.confirmationKey(for: effect), .reportRecorded, "\(effect)")
            }
        }

        func testTheThreeEffectsThatHaveSomethingElseToSayEachGetTheirOwnLine() {
            XCTAssertEqual(
                SkinCheckModel.confirmationKey(for: .clampHit(revisitSkinType: true)), .revisitSkinType
            )
            XCTAssertEqual(
                SkinCheckModel.confirmationKey(for: .blisterCorrection(from: 1.4, to: 0.9, pauseDays: 4)),
                .pauseSuggested
            )
            XCTAssertEqual(
                SkinCheckModel.confirmationKey(for: .reclassifiedAsNormal), .immediateDarkeningExplained
            )
        }

        /// A report about a day with no logged dose is recorded and never
        /// calibrated, and the confirmation says exactly that (D-2026-09-03-T4).
        func testADayWithNoLoggedDoseIsToldThereWasNothingToReport() {
            XCTAssertEqual(SkinCheckModel.confirmationKey(for: .noDoseThatDay), .noSessionToReport)
        }
    }

    // MARK: - Opening the flow from a notification (R20)

    /// The identifier the scheduler wrote is the only thing a tapped notification
    /// carries, so routing is the exact inverse of building one — and anything
    /// that is not one of ours routes nowhere, which is what sends the user to the
    /// due-prompts card instead.
    final class SkinCheckNotificationRoutingTests: XCTestCase {
        func testASkinCheckIdentifierOpensThatDaysSkinCheck() throws {
            let day = try XCTUnwrap(DayKey(id: "2026-09-03@Europe/Oslo"))

            XCTAssertEqual(NotificationRouting.route("skin-2026-09-03@Europe/Oslo"), .skinCheck(day))
        }

        func testALastingColourIdentifierOpensThatDaysColourQuestion() throws {
            let day = try XCTUnwrap(DayKey(id: "2026-09-03@Europe/Oslo"))

            XCTAssertEqual(NotificationRouting.route("colour-2026-09-03@Europe/Oslo"), .lastingColour(day))
        }

        /// The day carries its zone, so an identifier written in one zone comes
        /// back as the same day and never as the device's.
        func testEveryDayIdentifierRoundTripsInWhicheverZoneItWasWrittenIn() {
            for identifier in ["UTC", "Europe/Oslo", "Pacific/Kiritimati", "America/Los_Angeles"] {
                guard let zone = TimeZone(identifier: identifier) else {
                    return XCTFail("\(identifier) is not a zone")
                }
                let day = DayKey(Fixture.at(10), timeZone: zone)
                XCTAssertEqual(NotificationRouting.route("skin-\(day.id)"), .skinCheck(day), identifier)
                XCTAssertEqual(NotificationRouting.route("colour-\(day.id)"), .lastingColour(day), identifier)
            }
        }

        /// Anything that is not a day question of ours: a malformed day, an
        /// impossible one, a timer alert, and a bare day with no prefix at all.
        func testAnythingElseRoutesNowhere() {
            let strangers = [
                "skin-garbage", "skin-", "skin-2026-13-40@Europe/Oslo", "skin-2026-09-03@Nowhere/AtAll",
                "colour-garbage", "timer-side", "timer-end", "timer-reapply-0", "2026-09-03@Europe/Oslo", "",
            ]
            for identifier in strangers {
                XCTAssertNil(NotificationRouting.route(identifier), "\"\(identifier)\" is not ours")
            }
        }
    }

    // MARK: - The screen declares its slots (R39, S15)

    @MainActor
    final class SkinCheckFlowManifestTests: XCTestCase {
        /// The flow is a question, not a figure, and no banner sits under it.
        func testTheSkinCheckFlowCarriesNoBannerAndShowsNoFigure() throws {
            XCTAssertFalse(SkinCheckFlow.hasBannerSlot)
            XCTAssertFalse(SkinCheckFlow.showsFigures)

            let row = try XCTUnwrap(ScreenTable.row("SkinCheckFlow"))
            XCTAssertEqual(row.hasBanner, SkinCheckFlow.hasBannerSlot)
            XCTAssertEqual(row.showsFigures, SkinCheckFlow.showsFigures)
        }
    }
#endif
