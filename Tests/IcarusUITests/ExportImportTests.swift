#if canImport(SwiftUI)
    import Foundation
    import IcarusAds
    import IcarusContent
    import IcarusCore
    import IcarusData
    @testable import IcarusUI
    import XCTest

    // Slice 3 of `history`, asserted against `ExportImportModel` and never against
    // a rendered view: a share sheet and a file importer both need a host
    // application, and every promise the slice makes — a file the M2 import
    // accepts, an import that applies the file's profile and replays the record it
    // landed, and a refused file that changes nothing — is reachable without one.
    //
    // The boundaries are faked and nothing else is: the forecast provider (the
    // network), the location source (the device), the notification port (the
    // system centre) and the clock. The history store, the profile store, the
    // export service and the replay all run for real, because the promise here is
    // about what actually reaches the record.
    //
    // Every fixture here is file-private: a fixture in a test target is shared
    // with every other file in it, and these names are ours.

    // MARK: - Fixtures

    /// The network, which never answers. Neither exporting nor importing a record
    /// of days that are over may reach for a forecast.
    private struct OfflineProvider: UVForecastProvider {
        let name = "export-import-test"

        func forecast(at _: Coordinate, days _: Int) async throws(ProviderError) -> ProviderForecast {
            throw ProviderError.network("the test provider is offline")
        }
    }

    /// Fixed instants only, read in UTC. Nothing here reads the wall clock, and no
    /// assertion below turns on today's date or on a computed dose — the doses are
    /// handed to the store, so what a file carries is known exactly.
    private enum ExportFixture {
        static let zone = TimeZone(identifier: "UTC")!
        static let place = Coordinate(latitude: 59.91, longitude: 10.75)

        /// The profile the app is running under before any import.
        static let profile = Profile(skinType: .iii, ceiling: .standard)

        /// A deliberately different profile for the file to carry, so "the file's
        /// profile was applied" cannot pass by accident.
        static let carriedProfile = Profile(skinType: .v, ceiling: .conservative, manualMultiplier: 1.3)

        static func at(day: Int, hour: Int) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour))!
        }

        static func day(_ dayOfMonth: Int) -> DayKey {
            DayKey(at(day: dayOfMonth, hour: 12), timeZone: zone)
        }

        /// Well after every session below, and what the environment's clock reads.
        static let now = at(day: 16, hour: 9)

        static func hour(_ dayOfMonth: Int, from startHour: Int) -> Window {
            Window(start: at(day: dayOfMonth, hour: startHour), end: at(day: dayOfMonth, hour: startHour + 1))
        }

        /// Flat UV index 8 across the day and the one after. Nothing in this slice
        /// recomputes a dose; the curve only has to be well formed, because the
        /// export carries it and the import validates it.
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

        /// Ids that read as numbers, so a failure names the record it is about.
        static func uuid(_ index: Int) -> UUID {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!
        }

        static func record(id: UUID, on dayOfMonth: Int, from startHour: Int = 10) -> SessionRecord {
            let span = hour(dayOfMonth, from: startHour)
            return SessionRecord(
                id: id,
                day: day(dayOfMonth),
                createdAt: span.start.addingTimeInterval(-600),
                plannedWindow: span,
                plannedIntervals: [ExposureInterval(exposure: .upAndAbout, window: span)],
                firstSide: .faceUp,
                posture: .upAndAbout,
                coverHeadAndShoulders: false,
                intent: .bestMinutes,
                ceilingAtPlan: .standard,
                prescribedSunscreen: nil,
                state: .planned,
                dosePerRegion: [:],
                factorsShown: [.front: 1.1, .back: 1.1, .headAndShoulders: 1.2],
                targetsShown: [.front: 2.7, .back: 2.7, .headAndShoulders: 2.4],
                curveUsed: storedCurve(dayOfMonth),
                forecastFetchedAt: at(day: dayOfMonth, hour: 9),
                forecastPlace: place
            )
        }

        static func dose(_ amount: SED) -> [Region: SED] {
            [.front: amount, .back: amount, .headAndShoulders: amount * 2]
        }

        /// Records in a fixed order, so a comparison never turns on storage order.
        static func ordered(_ history: History) -> History {
            History(
                sessions: history.sessions.sorted { $0.id.uuidString < $1.id.uuidString },
                reports: history.reports.sorted { $0.id.uuidString < $1.id.uuidString }
            )
        }

        static func encoder() -> JSONEncoder {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return encoder
        }

        static func decoder() -> JSONDecoder {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }
    }

    /// A composed environment whose profile store and history store are wired the
    /// way the app wires them: the store replays under whatever profile the
    /// profile store currently holds, so applying an imported profile is visible
    /// in the state the store answers with.
    @MainActor
    private struct ExportHarness {
        let environment: AppEnvironment
        let profiles: MemoryProfileStore

        static func make(profile: Profile = ExportFixture.profile) -> ExportHarness {
            let tunables = Tunables.current
            let profiles = MemoryProfileStore(profile: profile)
            let history = HistoryStore(
                persistence: MemoryPersistence(),
                tunables: tunables,
                profileProvider: { profiles.load() ?? profile }
            )
            let environment = AppEnvironment(
                forecast: ForecastService(
                    provider: OfflineProvider(), cache: MemoryForecastCache(), tunables: tunables
                ),
                location: LocationService(
                    source: FakeLocationSource(reading: .denied), resolver: FakePlaceResolver(table: [:])
                ),
                history: history,
                profile: profiles,
                prompts: PromptScheduler(port: FakeNotificationPort(authorization: .granted), tunables: tunables),
                ads: NoAdsProvider(),
                tunables: tunables,
                clock: { ExportFixture.now }
            )
            return ExportHarness(environment: environment, profiles: profiles)
        }

        var model: ExportImportModel {
            ExportImportModel(env: environment)
        }

        /// Plan a session and log it — the only way a session reaches the store.
        func seed(_ record: SessionRecord, dose: [Region: SED]) async throws {
            try await environment.history.upsertPlanned(record, replacing: nil)
            try await environment.history.log(
                record.id,
                actual: record.plannedIntervals,
                sunscreen: nil,
                doses: dose,
                factors: record.factorsShown,
                targets: record.targetsShown
            )
        }

        /// Two logged days and one skin report — a record worth carrying.
        func seedTwoDaysAndAReport() async throws {
            try await seed(ExportFixture.record(id: ExportFixture.uuid(1), on: 14), dose: ExportFixture.dose(1))
            try await seed(ExportFixture.record(id: ExportFixture.uuid(2), on: 15), dose: ExportFixture.dose(1.5))
            _ = try await environment.history.addReport(SkinReport(
                id: ExportFixture.uuid(20),
                day: ExportFixture.day(15),
                reportedAt: ExportFixture.at(day: 16, hour: 8),
                answer: .faintPink,
                timing: .nextMorning,
                region: .allExposed,
                channel: .inApp
            ))
        }

        func storedHistory() async throws -> History {
            try await environment.history.history()
        }
    }

    /// A history written out as a file on disk, which is the only thing the file
    /// importer ever hands the model.
    private func writeTemporaryFile(_ data: Data, extension ext: String = "json") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("icarus-import-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try data.write(to: url)
        return url
    }

    /// The bytes of a well-formed export file carrying the history and profile
    /// given, at whatever format version is asked for.
    private func exportFileData(
        history: History,
        profile: Profile = ExportFixture.carriedProfile,
        formatVersion: Int = ExportService.formatVersion
    ) throws -> Data {
        try ExportFixture.encoder().encode(ExportFile(
            formatVersion: formatVersion,
            tunablesVersion: Tunables.current.version,
            profile: profile,
            history: history,
            exportedAt: ExportFixture.at(day: 16, hour: 8)
        ))
    }

    /// A logged history of one day, built without a store — what an incoming file
    /// carries.
    private func fileHistory() -> History {
        var session = ExportFixture.record(id: ExportFixture.uuid(7), on: 13)
        session.state = .logged
        session.actualIntervals = session.plannedIntervals
        session.dosePerRegion = ExportFixture.dose(2)
        let report = SkinReport(
            id: ExportFixture.uuid(21),
            day: ExportFixture.day(13),
            reportedAt: ExportFixture.at(day: 14, hour: 8),
            answer: .normal,
            region: .allExposed,
            channel: .inApp
        )
        return History(sessions: [session], reports: [report])
    }

    // MARK: - The export is a file the import accepts (R25, S10)

    @MainActor
    final class ExportImportExportTests: XCTestCase {
        /// The whole promise of the export, end to end: what the share sheet hands
        /// out is a file the app's own import reads back into an empty store,
        /// record for record.
        func testTheExportedFileImportsBackAsTheSameRecord() async throws {
            let harness = ExportHarness.make()
            try await harness.seedTwoDaysAndAReport()
            let exported = try await harness.storedHistory()

            let url = try await harness.model.exportURL()

            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "nothing was written at \(url.path)")
            let data = try Data(contentsOf: url)
            let target = HistoryStore.inMemory(tunables: Tunables.current, profile: ExportFixture.profile)
            let summary = try await ExportService.import(data, into: target)

            XCTAssertEqual(summary.sessions, 2)
            XCTAssertEqual(summary.reports, 1)
            let restored = try await target.history()
            XCTAssertEqual(ExportFixture.ordered(restored), ExportFixture.ordered(exported))
        }

        /// The file carries the profile the app is running under — that is what
        /// makes an import able to reproduce the figures (R25).
        func testTheExportCarriesTheProfileTheAppIsRunningUnder() async throws {
            let harness = ExportHarness.make(profile: ExportFixture.carriedProfile)
            try await harness.seedTwoDaysAndAReport()

            let url = try await harness.model.exportURL()
            let file = try ExportFixture.decoder().decode(ExportFile.self, from: Data(contentsOf: url))

            XCTAssertEqual(file.profile, ExportFixture.carriedProfile)
            XCTAssertEqual(file.formatVersion, ExportService.formatVersion)
            XCTAssertEqual(file.tunablesVersion, Tunables.current.version)
        }

        /// Exported at the environment's clock, never at the wall clock: two
        /// exports of the same record on a held clock are the same file.
        func testTheExportIsStampedAtTheEnvironmentsClock() async throws {
            let harness = ExportHarness.make()
            try await harness.seedTwoDaysAndAReport()

            let url = try await harness.model.exportURL()
            let file = try ExportFixture.decoder().decode(ExportFile.self, from: Data(contentsOf: url))

            XCTAssertEqual(file.exportedAt, ExportFixture.now)
        }

        /// The file picker only offers JSON, so what the share sheet hands out has
        /// to be named as JSON or it cannot come back in.
        func testTheExportedFileIsNamedAsJSON() async throws {
            let harness = ExportHarness.make()
            try await harness.seedTwoDaysAndAReport()

            let url = try await harness.model.exportURL()

            XCTAssertEqual(url.pathExtension, "json")
            XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        }

        /// A user who has logged nothing can still export: an empty record is a
        /// record, not an error.
        func testAnEmptyHistoryExportsAFileTheImportAccepts() async throws {
            let harness = ExportHarness.make()

            let url = try await harness.model.exportURL()

            let target = HistoryStore.inMemory(tunables: Tunables.current, profile: ExportFixture.profile)
            let summary = try await ExportService.import(Data(contentsOf: url), into: target)
            XCTAssertEqual(summary.sessions, 0)
            XCTAssertEqual(summary.reports, 0)
        }
    }

    // MARK: - What an import lands (R25, S10)

    @MainActor
    final class ExportImportImportTests: XCTestCase {
        /// Picking a file changes nothing until the warning is accepted
        /// (HIST-4, HIST-5): an import replaces everything on the phone, so
        /// silent data loss on the tap that picked the file is never intended.
        func testPickingAFileReplacesNothingUntilTheWarningIsAccepted() async throws {
            let harness = ExportHarness.make()
            try await harness.seedTwoDaysAndAReport()
            let before = try await harness.storedHistory()
            let url = try writeTemporaryFile(exportFileData(history: fileHistory()))
            let model = harness.model

            model.choose(url)
            XCTAssertEqual(model.pendingImport, url)
            let afterPicking = try await harness.storedHistory()
            XCTAssertEqual(ExportFixture.ordered(afterPicking), ExportFixture.ordered(before))

            model.cancelImport()
            let nothing = try await model.confirmImport()
            XCTAssertNil(nothing)
            let afterCancelling = try await harness.storedHistory()
            XCTAssertEqual(ExportFixture.ordered(afterCancelling), ExportFixture.ordered(before))

            model.choose(url)
            let summary = try await model.confirmImport()
            XCTAssertEqual(summary?.sessions, 1)
            XCTAssertNil(model.pendingImport)
            let landed = try await harness.storedHistory()
            XCTAssertEqual(ExportFixture.ordered(landed), ExportFixture.ordered(fileHistory()))
        }

        /// The import replaces the record whole and says what it landed.
        func testImportingAFileReplacesTheRecordAndReportsWhatItLanded() async throws {
            let harness = ExportHarness.make()
            try await harness.seedTwoDaysAndAReport()
            let url = try writeTemporaryFile(exportFileData(history: fileHistory()))

            let summary = try await harness.model.importFile(url)

            XCTAssertEqual(summary.sessions, 1)
            XCTAssertEqual(summary.reports, 1)
            let landed = try await harness.storedHistory()
            XCTAssertEqual(ExportFixture.ordered(landed), ExportFixture.ordered(fileHistory()))
            XCTAssertFalse(
                landed.sessions.contains { $0.id == ExportFixture.uuid(1) },
                "the record the import replaced is still there"
            )
        }

        /// The profile the file carried becomes the profile the app runs under.
        func testImportAppliesTheProfileTheFileCarried() async throws {
            let harness = ExportHarness.make(profile: ExportFixture.profile)
            let url = try writeTemporaryFile(
                exportFileData(history: fileHistory(), profile: ExportFixture.carriedProfile)
            )

            let summary = try await harness.model.importFile(url)

            XCTAssertEqual(summary.profile, ExportFixture.carriedProfile)
            XCTAssertEqual(harness.profiles.load(), ExportFixture.carriedProfile, "the file's profile was not applied")
        }

        /// Nothing derived survives an import: the state the screens read is a
        /// replay of the landed record under the landed profile, not the answer
        /// that was memoised before the file arrived.
        func testTheStateIsReplayedFromTheImportedRecord() async throws {
            let harness = ExportHarness.make()
            let before = try await harness.environment.history.state(now: ExportFixture.now)
            XCTAssertTrue(before.cycleStarts.isEmpty, "nothing has been logged yet")
            let url = try writeTemporaryFile(
                exportFileData(history: fileHistory(), profile: ExportFixture.carriedProfile)
            )

            _ = try await harness.model.importFile(url)

            let after = try await harness.environment.history.state(now: ExportFixture.now)
            let reference = HistoryStore.inMemory(
                tunables: Tunables.current, profile: ExportFixture.carriedProfile
            )
            try await reference.replaceAll(fileHistory())
            let expected = try await reference.state(now: ExportFixture.now)
            XCTAssertEqual(after, expected)
            XCTAssertFalse(after.cycleStarts.isEmpty, "the imported session opened a cycle")
            XCTAssertNotEqual(after, before, "the screens would still be reading the record the import replaced")
        }

        /// Two imports in a row are the second file, not both of them.
        func testASecondImportReplacesTheFirst() async throws {
            let harness = ExportHarness.make()
            let first = try writeTemporaryFile(exportFileData(history: fileHistory()))
            _ = try await harness.model.importFile(first)

            var other = ExportFixture.record(id: ExportFixture.uuid(8), on: 12)
            other.state = .logged
            other.actualIntervals = other.plannedIntervals
            other.dosePerRegion = ExportFixture.dose(1)
            let second = try writeTemporaryFile(exportFileData(history: History(sessions: [other])))

            let summary = try await harness.model.importFile(second)

            XCTAssertEqual(summary.sessions, 1)
            let landed = try await harness.storedHistory()
            XCTAssertEqual(landed.sessions.map(\.id), [ExportFixture.uuid(8)])
            XCTAssertTrue(landed.reports.isEmpty, "the first file's report is not the second file's record")
        }
    }

    // MARK: - A file that cannot be read changes nothing (R25, S10)

    @MainActor
    final class ExportImportFailureTests: XCTestCase {
        /// Import the file and expect a refusal, then prove the record and the
        /// profile are exactly what they were.
        private func assertRefused(
            _ url: URL,
            _ what: String,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws {
            let harness = ExportHarness.make()
            try await harness.seedTwoDaysAndAReport()
            let before = try await harness.storedHistory()

            do {
                _ = try await harness.model.importFile(url)
                XCTFail("importing \(what) should have been refused", file: file, line: line)
            } catch {}

            let after = try await harness.storedHistory()
            XCTAssertEqual(
                ExportFixture.ordered(after), ExportFixture.ordered(before),
                "the history was changed by \(what)", file: file, line: line
            )
            XCTAssertEqual(
                harness.profiles.load(), ExportFixture.profile,
                "the profile was changed by \(what)", file: file, line: line
            )
        }

        func testBytesThatAreNotAnExportFileAreRefusedAndTheHistoryIsUntouched() async throws {
            let url = try writeTemporaryFile(Data("{\"formatVersion\":1,\"nonsense\":true}".utf8))
            try await assertRefused(url, "a truncated file")
        }

        func testAFileThatIsNotJSONAtAllIsRefusedAndTheHistoryIsUntouched() async throws {
            let url = try writeTemporaryFile(Data("this is not a record of anything".utf8))
            try await assertRefused(url, "bytes that are not JSON")
        }

        func testAFileFromAFormatThisBuildCannotReadIsRefused() async throws {
            let url = try writeTemporaryFile(
                exportFileData(history: fileHistory(), formatVersion: ExportService.formatVersion + 1)
            )
            try await assertRefused(url, "a later format version")
        }

        /// A file this app could not have written — a negative dose — is refused
        /// whole rather than landed in part.
        func testAFileHoldingARecordThisAppCouldNotHaveWrittenIsRefused() async throws {
            var broken = ExportFixture.record(id: ExportFixture.uuid(9), on: 13)
            broken.state = .logged
            broken.actualIntervals = broken.plannedIntervals
            broken.dosePerRegion = [.front: -0.5]
            let url = try writeTemporaryFile(exportFileData(history: History(sessions: [broken])))
            try await assertRefused(url, "a negative dose")
        }

        /// The file picker can hand back a URL there is nothing at.
        func testAFileThatIsNotThereIsRefusedAndTheHistoryIsUntouched() async throws {
            let missing = FileManager.default.temporaryDirectory
                .appendingPathComponent("icarus-missing-\(UUID().uuidString).json")
            try await assertRefused(missing, "a file that does not exist")
        }
    }

    // MARK: - What the screen has to show (S10)

    @MainActor
    final class ExportImportErrorReportingTests: XCTestCase {
        /// A model that has done nothing has nothing to complain about, so the
        /// screen shows no alert on arrival.
        func testANewModelHoldsNoError() {
            let harness = ExportHarness.make()

            XCTAssertNil(harness.model.lastError)
        }

        /// The refusal is recorded, because the screen has to be able to say the
        /// file could not be read.
        func testAFailedImportIsRecordedForTheScreenToShow() async throws {
            let harness = ExportHarness.make()
            let model = harness.model
            let url = try writeTemporaryFile(Data("not a record".utf8))

            _ = try? await model.importFile(url)

            XCTAssertNotNil(model.lastError, "nothing was recorded for the screen to show")
        }

        /// And it is forgotten once a file does land, so an old failure cannot
        /// alert over a successful import.
        func testASuccessfulImportClearsTheEarlierFailure() async throws {
            let harness = ExportHarness.make()
            let model = harness.model
            _ = try? await model.importFile(try writeTemporaryFile(Data("not a record".utf8)))
            XCTAssertNotNil(model.lastError)

            _ = try await model.importFile(writeTemporaryFile(exportFileData(history: fileHistory())))

            XCTAssertNil(model.lastError)
        }
    }

    // MARK: - The screen itself

    @MainActor
    final class ExportImportViewTests: XCTestCase {
        /// Building the screen is not doing anything: the export happens when the
        /// user asks for it, and the record is untouched until a file is picked.
        func testBuildingTheScreenChangesNoRecord() async throws {
            let harness = ExportHarness.make()
            try await harness.seedTwoDaysAndAReport()
            let before = try await harness.storedHistory()

            _ = ExportImportView(env: harness.environment)

            let after = try await harness.storedHistory()
            XCTAssertEqual(ExportFixture.ordered(after), ExportFixture.ordered(before))
            XCTAssertEqual(harness.profiles.load(), ExportFixture.profile)
        }
    }
#endif
