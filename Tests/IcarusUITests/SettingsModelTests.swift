#if canImport(SwiftUI)
    import Foundation
    import IcarusAds
    import IcarusContent
    import IcarusCore
    import IcarusData
    @testable import IcarusUI
    import XCTest

    // Slice 4 of `calculator-ui`, asserted against the model and never against a
    // rendered view: a view test would need a host application, and every promise
    // the slice makes about Settings is reachable without one.
    //
    // The boundaries are faked and nothing else is — the notification port, the
    // location source, the forecast provider and the clock. `SettingsModel`
    // itself runs for real against the real history store, the real replay, the
    // real export service and the real copy document.
    //
    // Every type here is file-private on purpose: a fixture in a test target is
    // shared with every other file in it, and these names are ours alone.

    // MARK: - Fixtures

    /// The network, offline. Nothing in Settings asks for a forecast, and a
    /// provider that answered would hide it if something did.
    private struct OfflineProvider: UVForecastProvider {
        let name = "settings-test"

        func forecast(at _: Coordinate, days _: Int) async throws(ProviderError) -> ProviderForecast {
            throw ProviderError.network("the test provider is offline")
        }
    }

    /// Fixed values only: a run of days each carrying one logged session, and a
    /// report on as many of them as the test asks for. Nothing reads the wall
    /// clock, and every session stores the curve it was planned on so an export
    /// of this history is a file the importer accepts.
    private enum Fixed {
        static let zone = TimeZone(identifier: "UTC")!
        static let place = Coordinate(latitude: 59.91, longitude: 10.75)
        static let profile = Profile(skinType: .iii, ceiling: .standard)

        static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }

        /// Noon on the day after the last session below.
        static let now = date(2026, 6, 15, 12)

        static func day(_ moment: Date) -> DayKey {
            DayKey(moment, timeZone: zone)
        }

        /// Ids that read as numbers, so a failure names the record it is about.
        static func uuid(_ index: Int) -> UUID {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
        }

        /// Flat UV index 8 across two whole days from `moment`'s local midnight.
        static func curve(on moment: Date) throws -> ForecastCurve {
            let opens = day(moment).start()
            let hourly = (0 ... 48).map { HourlyUVI(time: opens.addingTimeInterval(Double($0) * 3600), uvi: 8) }
            return try ForecastCurve(
                location: place, timeZone: zone, fetchedAt: opens, hourly: hourly,
                solarNoon: [day(moment): opens.addingTimeInterval(12 * 3600)]
            )
        }

        /// One logged lying session: half an hour a side, from ten o'clock.
        static func session(_ index: Int, on opens: Date) throws -> SessionRecord {
            let middle = opens.addingTimeInterval(1800)
            let closes = opens.addingTimeInterval(3600)
            let intervals = [
                ExposureInterval(exposure: .lying(.faceUp), window: Window(start: opens, end: middle)),
                ExposureInterval(exposure: .lying(.faceDown), window: Window(start: middle, end: closes)),
            ]
            return try SessionRecord(
                id: uuid(index), day: day(opens), createdAt: opens,
                plannedWindow: Window(start: opens, end: closes), plannedIntervals: intervals,
                firstSide: .faceUp, actualIntervals: intervals, posture: .lyingTurning,
                coverHeadAndShoulders: false, intent: .bestMinutes, ceilingAtPlan: .standard,
                state: .logged, dosePerRegion: [.front: 1, .back: 1, .headAndShoulders: 1.5],
                curveUsed: curve(on: opens).stored(for: day(opens)),
                forecastFetchedAt: day(opens).start(), forecastPlace: place
            )
        }

        /// The morning after the session, which is when the app asks (R20).
        static func report(_ index: Int, on opens: Date, answer: SkinAnswer) -> SkinReport {
            SkinReport(
                id: uuid(100 + index), day: day(opens), reportedAt: opens.addingTimeInterval(22 * 3600),
                answer: answer, timing: answer == .normal ? nil : .nextMorning, region: .front,
                channel: .inApp
            )
        }

        /// `loggedDays` consecutive days ending the day before `now`, the first
        /// `reports` of them answered. The last answer is the reddening one when
        /// the test asks for a bound in the cycle.
        static func history(loggedDays: Int, reports: Int, redness: Bool = false) throws -> History {
            var sessions = [SessionRecord]()
            var answers = [SkinReport]()
            for index in 0 ..< loggedDays {
                let opens = date(2026, 6, 15 - loggedDays + index, 10)
                try sessions.append(session(index, on: opens))
                guard index < reports else { continue }
                let reddens = redness && index == reports - 1
                answers.append(report(index, on: opens, answer: reddens ? .clearlyPink : .normal))
            }
            return History(sessions: sessions, reports: answers)
        }
    }

    /// A composed environment with the profile store kept to hand, wired the way
    /// the app wires it: the history replays under whatever profile is stored, so
    /// a change made in Settings is a change the next replay sees.
    @MainActor
    private struct Harness {
        let environment: AppEnvironment
        let profiles: MemoryProfileStore

        static func make(profile: Profile = Fixed.profile, history: History = History()) async throws -> Harness {
            let tunables = Tunables.current
            let profiles = MemoryProfileStore(profile: profile)
            let store = HistoryStore(
                persistence: MemoryPersistence(),
                tunables: tunables,
                profileProvider: { profiles.load() ?? profile }
            )
            try await store.replaceAll(history)
            let environment = AppEnvironment(
                forecast: ForecastService(
                    provider: OfflineProvider(), cache: MemoryForecastCache(), tunables: tunables
                ),
                location: LocationService(
                    source: FakeLocationSource(reading: .denied), resolver: FakePlaceResolver(table: [:])
                ),
                history: store,
                profile: profiles,
                prompts: PromptScheduler(port: FakeNotificationPort(authorization: .granted), tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { Fixed.now }
            )
            return Harness(environment: environment, profiles: profiles)
        }
    }

    /// The three read-only properties answer from state replayed behind an actor,
    /// so the model has to load them in a task of its own. Give that task the
    /// main actor until the day count it depends on has landed; every fixture
    /// below leaves at least one day unreported, so the value waited for is never
    /// the one an unloaded model would already be showing.
    @MainActor
    private func settled(_ model: SettingsModel, unreportedDays: Int) async {
        var turns = 0
        while model.unreportedDays != unreportedDays, turns < 2000 {
            await Task.yield()
            turns += 1
        }
    }

    /// What the engine would plan for the front today, under whatever profile is
    /// stored now. The override is only worth anything if it reaches this.
    @MainActor
    private func plannedTarget(
        _ harness: Harness,
        state: DerivedState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> RegionTarget {
        let profile = try XCTUnwrap(harness.profiles.load(), file: file, line: line)
        return TanningGoal().target(
            for: .front, profile: profile, state: state, now: Fixed.now, stale: false, tunables: Tunables.current
        )
    }

    // MARK: - The ceiling selector (R7)

    @MainActor
    final class SettingsCeilingTests: XCTestCase {
        func testTheModelOpensAtTheStoredCeilingAndSavesTheOneTheUserPicks() async throws {
            let harness = try await Harness.make(profile: Profile(skinType: .iii, ceiling: .conservative))
            let model = SettingsModel(env: harness.environment)
            XCTAssertEqual(model.ceiling, .conservative)

            model.ceiling = .standard

            XCTAssertEqual(harness.profiles.load()?.ceiling, .standard)
            XCTAssertEqual(harness.profiles.load()?.skinType, .iii, "changing the ceiling is not starting over")
        }

        /// Aggressive is the one setting the app holds back: it needs enough
        /// reports and at least one redness report in the current tan cycle,
        /// because until then nobody knows where the line is.
        func testAggressiveUnlocksWithFiveReportsAndARednessBoundInTheCycle() async throws {
            let history = try Fixed.history(loggedDays: 6, reports: 5, redness: true)
            let harness = try await Harness.make(history: history)
            let model = SettingsModel(env: harness.environment)

            await settled(model, unreportedDays: 1)

            XCTAssertTrue(model.aggressiveUnlocked)
        }

        func testAggressiveStaysLockedWithoutTheReportsOrWithoutARednessBound() async throws {
            let few = try await Harness.make(history: Fixed.history(loggedDays: 6, reports: 4, redness: true))
            let calm = try await Harness.make(history: Fixed.history(loggedDays: 6, reports: 5))
            let onFew = SettingsModel(env: few.environment)
            let onCalm = SettingsModel(env: calm.environment)

            await settled(onFew, unreportedDays: 2)
            await settled(onCalm, unreportedDays: 1)

            XCTAssertFalse(onFew.aggressiveUnlocked, "four reports is not five")
            XCTAssertFalse(onCalm.aggressiveUnlocked, "five reports that never reddened bound nothing")
        }
    }

    // MARK: - The sensitivity sentence (R21, S10)

    /// The sentence is rendered from the replayed state and from the copy
    /// document, never written in the view.
    @MainActor
    final class SettingsSensitivityTests: XCTestCase {
        func testTheSentenceCountsTheReportsBehindIt() async throws {
            let many = try await Harness.make(history: Fixed.history(loggedDays: 6, reports: 5))
            let few = try await Harness.make(history: Fixed.history(loggedDays: 6, reports: 2))
            let onMany = SettingsModel(env: many.environment)
            let onFew = SettingsModel(env: few.environment)

            await settled(onMany, unreportedDays: 1)
            await settled(onFew, unreportedDays: 4)

            XCTAssertTrue(onMany.sensitivitySentence.contains("5"), onMany.sensitivitySentence)
            XCTAssertTrue(onFew.sensitivitySentence.contains("2"), onFew.sensitivitySentence)
            XCTAssertNotEqual(onMany.sensitivitySentence, onFew.sensitivitySentence)
            XCTAssertNotEqual(
                onMany.sensitivitySentence, AppCopy.text(.sensitivitySentence),
                "the sentence is the owner's line with this user's numbers in it, not the template"
            )
            XCTAssertFalse(
                onMany.sensitivitySentence.contains("{"),
                "an argument the sentence names was never filled in: \(onMany.sensitivitySentence)"
            )
        }

        /// A multiplier under one means the skin reacted sooner than typical, so
        /// the sentence says "more sensitive" — the two words are data the copy
        /// takes as an argument, and the direction is not the view's to guess.
        func testTheSentenceSaysMoreSensitiveWhenTheReportsMovedTheMultiplierDown() async throws {
            let harness = try await Harness.make(history: Fixed.history(loggedDays: 6, reports: 5, redness: true))
            let model = SettingsModel(env: harness.environment)
            await settled(model, unreportedDays: 1)

            let state = try await harness.environment.history.state(now: Fixed.now)
            XCTAssertLessThan(state.multiplier, 1)
            let percent = Int((abs(1 - state.multiplier) * 100).rounded())
            XCTAssertTrue(model.sensitivitySentence.contains("more"), model.sensitivitySentence)
            XCTAssertFalse(model.sensitivitySentence.contains("less"), model.sensitivitySentence)
            XCTAssertTrue(model.sensitivitySentence.contains("\(percent)"), model.sensitivitySentence)
        }
    }

    // MARK: - The override (R21)

    /// The override replaces the learned multiplier wherever the engine would
    /// have read it, and the learned value keeps moving underneath it.
    @MainActor
    final class SettingsOverrideTests: XCTestCase {
        func testOverridingIsSavedAndChangesWhatIsPlannedWithoutWritingHistory() async throws {
            let harness = try await Harness.make(history: Fixed.history(loggedDays: 6, reports: 5))
            let model = SettingsModel(env: harness.environment)
            let before = try await harness.environment.history.history()
            let learned = try await harness.environment.history.state(now: Fixed.now)
            let plannedBefore = try plannedTarget(harness, state: learned)

            await model.overrideMultiplier(1.5)

            XCTAssertEqual(harness.profiles.load()?.manualMultiplier, 1.5)
            let after = try await harness.environment.history.history()
            XCTAssertEqual(after, before, "an override is not something that happened to the skin")
            let state = try await harness.environment.history.state(now: Fixed.now)
            XCTAssertEqual(state.multiplier, learned.multiplier, accuracy: 1e-9, "the learned value keeps moving")
            XCTAssertGreaterThan(try plannedTarget(harness, state: state).target, plannedBefore.target)
        }

        func testResettingClearsTheOverrideAndPutsThePlanBack() async throws {
            let stored = Profile(skinType: .iii, ceiling: .standard, manualMultiplier: 1.5)
            let harness = try await Harness.make(profile: stored, history: Fixed.history(loggedDays: 3, reports: 2))
            let model = SettingsModel(env: harness.environment)
            let state = try await harness.environment.history.state(now: Fixed.now)
            let overridden = try plannedTarget(harness, state: state)

            await model.resetSensitivity()

            XCTAssertNil(harness.profiles.load()?.manualMultiplier)
            XCTAssertLessThan(try plannedTarget(harness, state: state).target, overridden.target)
        }
    }

    // MARK: - The record itself (R20, R44)

    @MainActor
    final class SettingsHistoryTests: XCTestCase {
        /// The count the screen offers to catch up on: days the user did a
        /// session and never said what their skin did.
        func testUnreportedDaysCountsTheLoggedDaysWithNoReport() async throws {
            let harness = try await Harness.make(history: Fixed.history(loggedDays: 6, reports: 4))
            let model = SettingsModel(env: harness.environment)

            await settled(model, unreportedDays: 2)

            XCTAssertEqual(model.unreportedDays, 2)
        }

        /// A day that was only ever planned is not a day the user did anything
        /// on, so there is nothing to report about it.
        func testADayThatWasOnlyPlannedIsNotAnUnreportedDay() async throws {
            var history = try Fixed.history(loggedDays: 3, reports: 1)
            var planned = try Fixed.session(9, on: Fixed.date(2026, 6, 15, 10))
            planned.actualIntervals = nil
            planned.state = .planned
            planned.dosePerRegion = [:]
            history.sessions.append(planned)
            let harness = try await Harness.make(history: history)
            let model = SettingsModel(env: harness.environment)

            await settled(model, unreportedDays: 2)

            XCTAssertEqual(model.unreportedDays, 2)
        }

        /// R44's warning is about this: the history is the record, so deleting it
        /// deletes the calibration and the tan state with it.
        func testDeletingTheHistoryStartsOverFromTheSkinTypePrior() async throws {
            let harness = try await Harness.make(history: Fixed.history(loggedDays: 6, reports: 5, redness: true))
            let model = SettingsModel(env: harness.environment)
            let before = try await harness.environment.history.state(now: Fixed.now)
            XCTAssertEqual(before.totalReports, 5)
            XCTAssertNotEqual(before.multiplier, 1, "the fixture has actually taught the app something")

            try await model.deleteHistory()

            let history = try await harness.environment.history.history()
            XCTAssertTrue(history.sessions.isEmpty)
            XCTAssertTrue(history.reports.isEmpty)
            let after = try await harness.environment.history.state(now: Fixed.now)
            XCTAssertEqual(after.totalReports, 0)
            XCTAssertEqual(after.multiplier, 1, accuracy: 1e-9)
        }
    }

    // MARK: - Export and import (R25, S10)

    @MainActor
    final class SettingsTransferTests: XCTestCase {
        func testExportingWritesAFileCarryingTheWholeRecordAndTheProfile() async throws {
            let harness = try await Harness.make(history: Fixed.history(loggedDays: 3, reports: 2))
            let model = SettingsModel(env: harness.environment)

            let url = try await model.exportFile()

            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let file = try decoder.decode(ExportFile.self, from: Data(contentsOf: url))
            XCTAssertEqual(file.formatVersion, ExportService.formatVersion)
            XCTAssertEqual(file.profile, Fixed.profile)
            XCTAssertEqual(file.tunablesVersion, Tunables.current.version)
            XCTAssertEqual(file.history.sessions.count, 3)
            XCTAssertEqual(file.history.reports.count, 2)
            try? FileManager.default.removeItem(at: url)
        }

        /// A file carries the profile it was written under, and importing it
        /// applies that profile rather than keeping the one on this phone.
        func testImportingAppliesTheFilesProfileAndItsWholeRecord() async throws {
            let harness = try await Harness.make(history: Fixed.history(loggedDays: 2, reports: 1))
            let model = SettingsModel(env: harness.environment)
            let incoming = Profile(skinType: .v, ceiling: .aggressive, manualMultiplier: 1.2)
            let url = try await Self.file(holding: Fixed.history(loggedDays: 4, reports: 3), profile: incoming)

            let summary = try await model.importFile(url)

            XCTAssertEqual(summary.profile, incoming)
            XCTAssertEqual(summary.sessions, 4)
            XCTAssertEqual(summary.reports, 3)
            XCTAssertEqual(harness.profiles.load(), incoming, "the file's profile is what the app runs on now")
            let landed = try await harness.environment.history.history()
            XCTAssertEqual(landed.sessions.count, 4)
            XCTAssertEqual(landed.reports.count, 3)
            try? FileManager.default.removeItem(at: url)
        }

        /// An export file written by the real service, on disk, for the model to
        /// read back — the file boundary is real, everything else is not.
        private static func file(holding history: History, profile: Profile) async throws -> URL {
            let store = HistoryStore.inMemory(tunables: Tunables.current, profile: profile)
            try await store.replaceAll(history)
            let data = try await ExportService.export(store: store, profile: profile, now: Fixed.now)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("icarus-settings-\(UUID().uuidString).json")
            try data.write(to: url)
            return url
        }
    }

    // MARK: - The screen declares its slots (R39, S15)

    @MainActor
    final class SettingsScreenManifestTests: XCTestCase {
        /// Settings shows the sensitivity figures, so no banner may sit under it.
        func testSettingsCarriesNoBannerAndShowsFigures() throws {
            XCTAssertFalse(SettingsView.hasBannerSlot)
            XCTAssertTrue(SettingsView.showsFigures)
            let row = try XCTUnwrap(ScreenTable.row("SettingsView"))
            XCTAssertEqual(row.hasBanner, SettingsView.hasBannerSlot)
            XCTAssertEqual(row.showsFigures, SettingsView.showsFigures)
        }
    }
#endif
