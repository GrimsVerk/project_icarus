import Foundation
import IcarusCore
@testable import IcarusData
import XCTest

/// Planning, replacing and discarding: what the store holds before anything has
/// actually been faced (R45).
final class HistoryStorePlanningTests: XCTestCase {
    private let opens = StoreFixtures.date(2026, 6, 29, 12)

    private func makeStore() -> HistoryStore {
        HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
    }

    func testUpsertPlannedStoresThePrescribedPairAndThePlannedIntervals() async throws {
        let store = makeStore()
        let choice = SunscreenChoice(spfLabel: 30, application: .normal)
        let record = try StoreFixtures.planned(1, opens: opens, prescribed: choice)

        let id = try await store.upsertPlanned(record, replacing: nil)
        let planned = try await store.plannedSessions(on: StoreFixtures.day(opens))
        XCTAssertEqual(planned.count, 1)
        let stored = try XCTUnwrap(planned.first)
        XCTAssertEqual(stored.id, id)
        XCTAssertEqual(stored.state, .planned)
        XCTAssertEqual(stored.prescribedSunscreen, choice)
        XCTAssertEqual(stored.plannedIntervals, record.plannedIntervals)
    }

    func testUpsertPlannedReplacingLeavesOnePlannedSessionForTheDay() async throws {
        let store = makeStore()
        let first = try StoreFixtures.planned(1, opens: opens)
        let firstID = try await store.upsertPlanned(first, replacing: nil)
        let second = try StoreFixtures.planned(2, opens: opens.addingTimeInterval(3600))

        let secondID = try await store.upsertPlanned(second, replacing: firstID)
        let planned = try await store.plannedSessions(on: StoreFixtures.day(opens))
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.id, secondID)
        XCTAssertEqual(planned.first?.plannedWindow, second.plannedWindow)
    }

    func testADiscardedSessionIsNoLongerPlanned() async throws {
        let store = makeStore()
        let record = try StoreFixtures.planned(1, opens: opens)
        _ = try await store.upsertPlanned(record, replacing: nil)

        try await store.discard(record.id)
        let planned = try await store.plannedSessions(on: StoreFixtures.day(opens))
        XCTAssertTrue(planned.isEmpty)
        let history = try await store.history()
        XCTAssertTrue(history.sessions.allSatisfy { $0.state == .discarded })
    }

    func testDiscardPlannedBeforeACutoffDiscardsOnlyTheStalePlannedOnes() async throws {
        let store = makeStore()
        let staleDay = StoreFixtures.date(2026, 6, 20, 10)
        let freshDay = StoreFixtures.date(2026, 6, 25, 10)
        _ = try await store.upsertPlanned(
            StoreFixtures.planned(1, opens: staleDay, createdAt: StoreFixtures.date(2026, 6, 20, 9)), replacing: nil
        )
        _ = try await store.upsertPlanned(
            StoreFixtures.planned(2, opens: freshDay, createdAt: StoreFixtures.date(2026, 6, 25, 9)), replacing: nil
        )
        try await StoreFixtures.seed(store, index: 3, opens: StoreFixtures.date(2026, 6, 20, 12),
                                     dose: [.front: 1.0])

        // R45: a planned session is discarded only once its in-app skin-check
        // window (72 h after the session) has closed unanswered, never before.
        // The stale session's window closes on the 23rd; the cutoff is the 24th.
        let discarded = try await store.discardPlanned(before: StoreFixtures.date(2026, 6, 24))
        XCTAssertEqual(discarded, 1)
        let stale = try await store.plannedSessions(on: StoreFixtures.day(staleDay))
        XCTAssertTrue(stale.isEmpty)
        let fresh = try await store.plannedSessions(on: StoreFixtures.day(freshDay))
        XCTAssertEqual(fresh.count, 1)
        let sameDay = try await store.sessions(on: StoreFixtures.day(staleDay))
        XCTAssertEqual(sameDay.filter { $0.state == .logged }.count, 1)
    }

    func testEveryWriteReachesThePersistenceSoASecondStoreSeesIt() async throws {
        let persistence = MemoryPersistence()
        let writer = HistoryStore(persistence: persistence, tunables: StoreFixtures.tunables,
                                  profileProvider: { StoreFixtures.profile })
        try await StoreFixtures.seed(writer, index: 1, opens: opens, dose: [.front: 1.1])

        let reader = HistoryStore(persistence: persistence, tunables: StoreFixtures.tunables,
                                  profileProvider: { StoreFixtures.profile })
        let history = try await reader.history()
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(history.sessions.first?.dosePerRegion[.front], 1.1)
    }
}

/// Logging is what the timer's stop and the "I did this" tap do: the record
/// takes the intervals actually faced, and may take them again (R45).
final class HistoryStoreLoggingTests: XCTestCase {
    private let opens = StoreFixtures.date(2026, 6, 29, 12)

    private func makeStore() -> HistoryStore {
        HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
    }

    private func interval(minutes: Double) -> ExposureInterval {
        ExposureInterval(exposure: .lying(.faceUp),
                         window: Window(start: opens, end: opens.addingTimeInterval(minutes * 60)))
    }

    func testLoggingAPlannedSessionRecordsWhatWasActuallyFaced() async throws {
        let store = makeStore()
        let record = try StoreFixtures.planned(1, opens: opens)
        _ = try await store.upsertPlanned(record, replacing: nil)
        let choice = SunscreenChoice(spfLabel: 15, application: .thin)

        try await store.log(record.id, actual: [interval(minutes: 40)], sunscreen: choice,
                            doses: [.front: 0.9, .back: 0, .headAndShoulders: 0.9],
                            factors: [.front: 1.1], targets: [.front: 2.4])

        let sessions = try await store.sessions(on: StoreFixtures.day(opens))
        let logged = try XCTUnwrap(sessions.first { $0.id == record.id })
        XCTAssertEqual(logged.state, .logged)
        XCTAssertEqual(logged.actualIntervals, [interval(minutes: 40)])
        XCTAssertEqual(logged.sunscreen, choice)
        XCTAssertEqual(logged.dosePerRegion[.front], 0.9)
        XCTAssertEqual(logged.factorsShown[.front], 1.1)
        XCTAssertEqual(logged.targetsShown[.front], 2.4)
        let planned = try await store.plannedSessions(on: StoreFixtures.day(opens))
        XCTAssertTrue(planned.isEmpty)
    }

    func testLoggingALoggedSessionUpdatesItInPlaceAndTheStateFollows() async throws {
        let store = makeStore()
        let record = try StoreFixtures.planned(1, opens: opens)
        _ = try await store.upsertPlanned(record, replacing: nil)
        try await store.log(record.id, actual: [interval(minutes: 60)], sunscreen: nil,
                            doses: [.front: 1.2], factors: [.front: 1.1], targets: [.front: 2.4])

        try await store.log(record.id, actual: [interval(minutes: 20)], sunscreen: nil,
                            doses: [.front: 0.4], factors: [.front: 1.1], targets: [.front: 2.4])

        let history = try await store.history()
        XCTAssertEqual(history.sessions.count, 1, "the stop replaced the log, it did not add one")
        XCTAssertEqual(history.sessions.first?.actualIntervals, [interval(minutes: 20)])
        XCTAssertEqual(history.sessions.first?.dosePerRegion[.front], 0.4)
        let state = try await store.state(now: StoreFixtures.date(2026, 6, 29, 18))
        XCTAssertEqual(state.regions[.front]?.doseToday ?? -1, 0.4, accuracy: 1e-9)
    }

    func testLoggingADiscardedSessionIsRefused() async throws {
        let store = makeStore()
        let record = try StoreFixtures.planned(1, opens: opens)
        _ = try await store.upsertPlanned(record, replacing: nil)
        try await store.discard(record.id)

        do {
            try await store.log(record.id, actual: [interval(minutes: 20)], sunscreen: nil,
                                doses: [.front: 0.4], factors: [:], targets: [:])
            XCTFail("logging a discarded session should have been refused")
        } catch {
            XCTAssertEqual(error as? HistoryError, .discarded(record.id))
        }
    }

    func testLoggingAnUnknownSessionIsRefused() async throws {
        let store = makeStore()
        let unknown = StoreFixtures.uuid(77)

        do {
            try await store.log(unknown, actual: [interval(minutes: 20)], sunscreen: nil,
                                doses: [.front: 0.4], factors: [:], targets: [:])
            XCTFail("logging an unknown session should have been refused")
        } catch {
            XCTAssertEqual(error as? HistoryError, .unknownSession(unknown))
        }
    }
}

/// Derived state is replayed from the record every time, never stored (R44).
final class HistoryStoreStateTests: XCTestCase {
    private let opens = StoreFixtures.date(2026, 6, 29, 12)
    private let now = StoreFixtures.date(2026, 7, 1, 12)

    private func filled(_ store: HistoryStore) async throws {
        try await StoreFixtures.seed(store, index: 1, opens: opens,
                                     dose: [.front: 2.0, .back: 2.0, .headAndShoulders: 1.0])
        _ = try await store.addReport(StoreFixtures.report(20, .clearlyPink, on: opens))
    }

    func testStateAfterALogAndAReportEqualsAReplayOverTheHistory() async throws {
        let store = HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
        try await filled(store)

        let history = try await store.history()
        let expected = Replay.replay(history, skinType: StoreFixtures.profile.skinType,
                                     now: now, tunables: StoreFixtures.tunables).state
        let state = try await store.state(now: now)
        XCTAssertEqual(state, expected)
        XCTAssertNotEqual(state, DerivedState.initial(tunables: StoreFixtures.tunables))
    }

    func testTheStateIsFoldedUnderTheTunablesTheStoreHoldsAndInvalidateFoldsItAgain() async throws {
        let recorder = ConstantRecorder()
        let spy = StoreFixtures.tunables.recording { recorder.record($0) }
        let store = HistoryStore(persistence: MemoryPersistence(), tunables: spy,
                                 profileProvider: { StoreFixtures.profile })
        try await filled(store)

        _ = try await store.state(now: now)
        XCTAssertTrue(recorder.keys.contains("decayHalfLifeDays"))
        recorder.reset()
        _ = try await store.state(now: now)
        XCTAssertFalse(recorder.keys.contains("decayHalfLifeDays"), "the second call should be memoised")
        await store.invalidate()
        _ = try await store.state(now: now)
        XCTAssertTrue(recorder.keys.contains("decayHalfLifeDays"), "invalidate should drop the memo")
    }

    func testAProfileChangeChangesTheStateForTheSameHistory() async throws {
        let box = ProfileBox(Profile(skinType: .ii, ceiling: .standard))
        let store = HistoryStore(persistence: MemoryPersistence(), tunables: StoreFixtures.tunables,
                                 profileProvider: { box.profile })
        try await filled(store)
        let before = try await store.state(now: now)

        box.set(Profile(skinType: .v, ceiling: .standard))
        let after = try await store.state(now: now)
        XCTAssertNotEqual(after, before)
        XCTAssertNotEqual(after.regions[.front]?.tanState, before.regions[.front]?.tanState)
    }

    func testADifferentNowOnAnotherDayRecomputesTheState() async throws {
        let store = HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
        try await StoreFixtures.seed(store, index: 1, opens: opens, dose: [.front: 1.2])

        let sameDay = try await store.state(now: StoreFixtures.date(2026, 6, 29, 18))
        XCTAssertEqual(sameDay.regions[.front]?.doseToday ?? -1, 1.2, accuracy: 1e-9)
        let later = try await store.state(now: now)
        XCTAssertEqual(later.regions[.front]?.doseToday ?? -1, 0, accuracy: 1e-9)
        XCTAssertLessThan(later.regions[.front]?.tanState ?? 0, sameDay.regions[.front]?.tanState ?? 0)
    }

    func testDeleteAllEmptiesTheHistoryAndResetsTheState() async throws {
        let store = HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
        try await filled(store)

        try await store.deleteAll()
        let history = try await store.history()
        XCTAssertTrue(history.sessions.isEmpty)
        XCTAssertTrue(history.reports.isEmpty)
        let state = try await store.state(now: now)
        XCTAssertEqual(state, DerivedState.initial(tunables: StoreFixtures.tunables))
    }
}

/// Reports and the lasting-colour answer that follows one days later (R20, R21).
final class HistoryStoreReportTests: XCTestCase {
    private let opens = StoreFixtures.date(2026, 6, 29, 12)
    private let now = StoreFixtures.date(2026, 7, 1, 12)

    private func makeStore() -> HistoryStore {
        HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
    }

    func testAddReportReturnsTheCalibrationEffectTheReplayGivesIt() async throws {
        let store = makeStore()
        try await StoreFixtures.seed(store, index: 1, opens: opens,
                                     dose: [.front: 2.0, .back: 2.0, .headAndShoulders: 1.0])
        let report = StoreFixtures.report(20, .clearlyPink, on: opens)

        let effect = try await store.addReport(report)
        let history = try await store.history()
        let replayed = Replay.replay(history, skinType: StoreFixtures.profile.skinType,
                                     now: now, tunables: StoreFixtures.tunables).effects[report.id]
        XCTAssertEqual(effect, replayed)
        XCTAssertNotEqual(effect, .noDoseThatDay)
    }

    func testAReportOnADayWithNothingLoggedIsRecordedAndNeverCalibrated() async throws {
        let store = makeStore()
        let report = StoreFixtures.report(21, .redSore, on: opens)

        let effect = try await store.addReport(report)
        XCTAssertEqual(effect, .noDoseThatDay)
        let history = try await store.history()
        XCTAssertEqual(history.reports.count, 1)
    }

    func testASecondReportForTheSameDayIsRefused() async throws {
        let store = makeStore()
        _ = try await store.addReport(StoreFixtures.report(20, .normal, on: opens))

        do {
            _ = try await store.addReport(StoreFixtures.report(21, .faintPink, on: opens))
            XCTFail("a second report for the same day should have been refused")
        } catch {
            XCTAssertEqual(error as? HistoryError, .alreadyReported(StoreFixtures.day(opens)))
        }
    }

    func testSetLastingColourStoresTheAnswerWithItsOwnTimestamp() async throws {
        let store = makeStore()
        try await StoreFixtures.seed(store, index: 1, opens: opens, dose: [.front: 2.0])
        _ = try await store.addReport(StoreFixtures.report(20, .normal, on: opens))
        let answered = StoreFixtures.date(2026, 7, 3, 9)

        try await store.setLastingColour(day: StoreFixtures.day(opens), .aLittle, at: answered)

        let history = try await store.history()
        let stored = try XCTUnwrap(history.reports.first)
        XCTAssertEqual(stored.lastingColour, .aLittle)
        XCTAssertEqual(stored.lastingColourAt, answered)
    }

    func testLastingColourForADayWithNoReportIsRefused() async throws {
        let store = makeStore()
        let day = StoreFixtures.day(opens)

        do {
            try await store.setLastingColour(day: day, .no, at: StoreFixtures.date(2026, 7, 3, 9))
            XCTFail("a lasting-colour answer needs the report it belongs to")
        } catch {
            XCTAssertEqual(error as? HistoryError, .noReport(day))
        }
    }
}

/// Weekly and cycle-to-date dose per region, both read off the history (R24).
final class HistoryStoreTotalsTests: XCTestCase {
    private let now = StoreFixtures.date(2026, 7, 1, 12)

    /// One session ten days before `now` and one two days before it — far
    /// enough apart to tell the week from the cycle, close enough that the
    /// fourteen-day gap has not ended the cycle.
    private func makeStore() async throws -> HistoryStore {
        let store = HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
        try await StoreFixtures.seed(store, index: 1, opens: StoreFixtures.date(2026, 6, 21, 12),
                                     dose: [.front: 1.0, .back: 1.0, .headAndShoulders: 0.5])
        try await StoreFixtures.seed(store, index: 2, opens: StoreFixtures.date(2026, 6, 29, 12),
                                     dose: [.front: 1.2, .back: 0.8, .headAndShoulders: 0.4])
        return store
    }

    func testWeekTotalsSumTheLastSevenDaysOfLoggedDosePerRegion() async throws {
        let totals = try await makeStore().totals(now: now)

        XCTAssertEqual(totals.week[.front] ?? -1, 1.2, accuracy: 1e-9)
        XCTAssertEqual(totals.week[.back] ?? -1, 0.8, accuracy: 1e-9)
        XCTAssertEqual(totals.week[.headAndShoulders] ?? -1, 0.4, accuracy: 1e-9)
    }

    func testCycleTotalsSumEveryLoggedDoseSinceTheCycleStarted() async throws {
        let store = try await makeStore()
        let state = try await store.state(now: now)
        XCTAssertEqual(state.regions[.front]?.cycleStart, StoreFixtures.day(StoreFixtures.date(2026, 6, 21, 12)))

        let totals = try await store.totals(now: now)
        XCTAssertEqual(totals.cycle[.front] ?? -1, 2.2, accuracy: 1e-9)
        XCTAssertEqual(totals.cycle[.back] ?? -1, 1.8, accuracy: 1e-9)
        XCTAssertEqual(totals.cycle[.headAndShoulders] ?? -1, 0.9, accuracy: 1e-9)
    }
}
