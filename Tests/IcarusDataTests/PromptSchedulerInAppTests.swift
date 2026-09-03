import Foundation
import IcarusCore
@testable import IcarusData
import XCTest

// Slice 2 of `logging-calibration`, on the data side: the in-app fallback asked
// of the REAL history store rather than of a hand-built `History`. The window
// arithmetic alone is asserted by `PromptSchedulerTests`; what is asserted here
// is the pair working together — a session logged through the store makes the
// day due, a report through the store takes it off the card and puts the colour
// question on it, an answer takes that off too, and the foreground sweep and the
// card agree about when a planned session has run out of time (R20, R45).
//
// The only fake is the notification port, which is the system centre and the
// boundary the slice declares for exactly that purpose. Notifications are denied
// in most of these tests because that is the case the fallback exists for.
//
// Not covered here, and deliberately: "Settings counts unreported logged days".
// The plan promises the count but declares no interface for it in either slice —
// there is a `CopyKey.unreportedDays` and no API that produces its `{count}` —
// so a test would have had to invent one. Reported as a plan gap instead.

// MARK: - Fixtures

/// One session day in UTC and the instants around it. Nothing here is derived
/// from `Date()`. The record fixtures are `StoreFixtures`, shared with the rest
/// of this target.
private enum InApp {
    static let hour: TimeInterval = 3600
    static let oneDay: TimeInterval = 86400

    /// The session starts at noon; `StoreFixtures.seed` logs three hours faced,
    /// so the day's last session ends at 15:00.
    static let opens = StoreFixtures.date(2026, 6, 15, 12)
    static let lastEnd = opens.addingTimeInterval(3 * hour)
    /// A planned session that was never logged ends where it was planned to.
    static let plannedEnd = opens.addingTimeInterval(2 * hour)

    static var day: DayKey {
        StoreFixtures.day(opens)
    }

    static func store() -> HistoryStore {
        HistoryStore.inMemory(tunables: StoreFixtures.tunables, profile: StoreFixtures.profile)
    }

    /// A scheduler over a fake port. Denied is the default because the in-app
    /// fallback is what a denial leaves the app with.
    static func scheduler(
        _ authorization: NotificationAuthorization = .denied
    ) -> (PromptScheduler, FakeNotificationPort) {
        let port = FakeNotificationPort(authorization: authorization)
        return (PromptScheduler(port: port, tunables: StoreFixtures.tunables), port)
    }

    /// The skin check for the day, answered at `reportedAt`.
    static func report(_ index: Int, at reportedAt: Date) -> SkinReport {
        SkinReport(
            id: StoreFixtures.uuid(index),
            day: day,
            reportedAt: reportedAt,
            answer: .normal,
            region: .allExposed,
            channel: .inApp
        )
    }
}

// MARK: - With notifications denied (R20)

/// Nothing is pending, and the day is asked about in the app instead, inside the
/// twelve-to-seventy-two-hour window R20 fixes.
final class PromptSchedulerDeniedInAppTests: XCTestCase {
    func testADeniedDaySchedulesNothingAndIsDueInAppFromTwelveHoursAfterTheSession() async throws {
        let store = InApp.store()
        try await StoreFixtures.seed(store, index: 1, opens: InApp.opens, dose: [.front: 1.4])
        let (scheduler, port) = InApp.scheduler()
        await scheduler.sessionsChanged(on: InApp.day, lastSessionEnd: InApp.lastEnd)
        let history = try await store.history()

        let pending = await port.pending()
        let opens = InApp.lastEnd.addingTimeInterval(12 * InApp.hour)
        let before = await scheduler.dueInApp(history: history, now: opens.addingTimeInterval(-1))
        let atOpening = await scheduler.dueInApp(history: history, now: opens)

        XCTAssertEqual(pending.count, 0, "a denied app schedules nothing at all")
        XCTAssertEqual(before, [], "the question is not asked the same evening")
        XCTAssertEqual(atOpening, [.skinCheck(InApp.day)])
    }

    func testTheInAppSkinCheckStopsBeingDueSeventyTwoHoursAfterTheSession() async throws {
        let store = InApp.store()
        try await StoreFixtures.seed(store, index: 1, opens: InApp.opens, dose: [.front: 1.4])
        let (scheduler, _) = InApp.scheduler()
        let history = try await store.history()
        let closes = InApp.lastEnd.addingTimeInterval(72 * InApp.hour)

        let atClosing = await scheduler.dueInApp(history: history, now: closes)
        let after = await scheduler.dueInApp(history: history, now: closes.addingTimeInterval(1))

        XCTAssertEqual(atClosing, [.skinCheck(InApp.day)])
        XCTAssertEqual(after, [], "three days on, the question is not worth asking")
    }
}

// MARK: - Answering takes the day off the card (R20)

/// The card is the list of questions still outstanding, so each answer written
/// through the store removes exactly what it answered — and the skin report is
/// what puts the colour question on the card in the first place.
final class PromptSchedulerInAppAnsweringTests: XCTestCase {
    private let reportedAt = InApp.lastEnd.addingTimeInterval(13 * InApp.hour)

    private func reportedDay() async throws -> HistoryStore {
        let store = InApp.store()
        try await StoreFixtures.seed(store, index: 1, opens: InApp.opens, dose: [.front: 1.4])
        _ = try await store.addReport(InApp.report(2, at: reportedAt))
        return store
    }

    func testReportingTheDayTakesItOffTheSkinCheckCard() async throws {
        let store = InApp.store()
        try await StoreFixtures.seed(store, index: 1, opens: InApp.opens, dose: [.front: 1.4])
        let (scheduler, _) = InApp.scheduler()
        let now = reportedAt.addingTimeInterval(InApp.hour)

        let before = try await scheduler.dueInApp(history: store.history(), now: now)
        _ = try await store.addReport(InApp.report(2, at: reportedAt))
        let after = try await scheduler.dueInApp(history: store.history(), now: now)

        XCTAssertEqual(before, [.skinCheck(InApp.day)])
        XCTAssertEqual(after, [], "the day has been reported")
    }

    func testAReportedDayIsDueForColourFromThreeDaysAfterTheReport() async throws {
        let store = try await reportedDay()
        let (scheduler, _) = InApp.scheduler()
        let history = try await store.history()
        let opens = reportedAt.addingTimeInterval(3 * InApp.oneDay)

        let before = await scheduler.dueInApp(history: history, now: opens.addingTimeInterval(-1))
        let atOpening = await scheduler.dueInApp(history: history, now: opens)

        XCTAssertEqual(before, [], "two days on, the colour question is not asked yet")
        XCTAssertEqual(atOpening, [.lastingColour(InApp.day)])
    }

    func testTheInAppColourQuestionStopsBeingDueTenDaysAfterTheReport() async throws {
        let store = try await reportedDay()
        let (scheduler, _) = InApp.scheduler()
        let history = try await store.history()
        let closes = reportedAt.addingTimeInterval(10 * InApp.oneDay)

        let atClosing = await scheduler.dueInApp(history: history, now: closes)
        let after = await scheduler.dueInApp(history: history, now: closes.addingTimeInterval(1))

        XCTAssertEqual(atClosing, [.lastingColour(InApp.day)])
        XCTAssertEqual(after, [], "ten days on, lasting colour is no longer a fair question")
    }

    func testAnsweringTheColourQuestionTakesTheDayOffTheCard() async throws {
        let store = try await reportedDay()
        let (scheduler, _) = InApp.scheduler()
        let answeredAt = reportedAt.addingTimeInterval(4 * InApp.oneDay)

        let before = try await scheduler.dueInApp(history: store.history(), now: answeredAt)
        try await store.setLastingColour(day: InApp.day, .aLittle, at: answeredAt)
        let after = try await scheduler.dueInApp(history: store.history(), now: answeredAt)

        XCTAssertEqual(before, [.lastingColour(InApp.day)])
        XCTAssertEqual(after, [])
        let reports = try await store.history().reports
        let stored = try XCTUnwrap(reports.first)
        XCTAssertEqual(stored.lastingColour, .aLittle)
        XCTAssertEqual(stored.lastingColourAt, answeredAt, "answered days after the report, and stamped so")
    }
}

// MARK: - The foreground sweep and the card agree (R45)

/// A planned session nobody ever answered for is discarded when its window
/// closes, never before — the same window the card asks inside.
final class PromptSchedulerInAppHousekeepingTests: XCTestCase {
    private func plannedDay() async throws -> HistoryStore {
        let store = InApp.store()
        let record = try StoreFixtures.planned(1, opens: InApp.opens)
        _ = try await store.upsertPlanned(record, replacing: nil)
        return store
    }

    func testAPlannedSessionInsideItsWindowIsStillAskedAboutAndSurvivesTheSweep() async throws {
        let store = try await plannedDay()
        let (scheduler, _) = InApp.scheduler()
        let now = InApp.plannedEnd.addingTimeInterval(24 * InApp.hour)

        let due = try await scheduler.dueInApp(history: store.history(), now: now)
        let discarded = try await store.discardPlanned(before: now)

        XCTAssertEqual(due, [.skinCheck(InApp.day)], "a planned session is a question, not yet an answer")
        XCTAssertEqual(discarded, 0, "its window is still open")
        let planned = try await store.plannedSessions(on: InApp.day)
        XCTAssertEqual(planned.count, 1)
    }

    func testOnceTheWindowHasClosedTheDayLeavesTheCardAndTheSweepDiscardsTheSession() async throws {
        let store = try await plannedDay()
        let (scheduler, _) = InApp.scheduler()
        let now = InApp.plannedEnd.addingTimeInterval(73 * InApp.hour)

        let due = try await scheduler.dueInApp(history: store.history(), now: now)
        let discarded = try await store.discardPlanned(before: now)
        let afterTheSweep = try await scheduler.dueInApp(history: store.history(), now: now)

        XCTAssertEqual(due, [], "the window closed unanswered")
        XCTAssertEqual(discarded, 1)
        XCTAssertEqual(afterTheSweep, [])
        let sessions = try await store.sessions(on: InApp.day)
        XCTAssertEqual(sessions.map(\.state), [.discarded], "a session never faced counts towards nothing")
    }

    /// The sweep takes the stale day and leaves a day still inside its window,
    /// so the card keeps asking about the one that can still be answered.
    func testTheSweepLeavesADayThatIsStillInsideItsWindow() async throws {
        let store = InApp.store()
        let staleOpens = StoreFixtures.date(2026, 6, 10, 10)
        _ = try await store.upsertPlanned(
            StoreFixtures.planned(1, opens: staleOpens, createdAt: staleOpens), replacing: nil
        )
        _ = try await store.upsertPlanned(
            StoreFixtures.planned(2, opens: InApp.opens, createdAt: InApp.opens), replacing: nil
        )
        let (scheduler, _) = InApp.scheduler()
        let now = InApp.plannedEnd.addingTimeInterval(24 * InApp.hour)

        let discarded = try await store.discardPlanned(before: now)
        let due = try await scheduler.dueInApp(history: store.history(), now: now)

        XCTAssertEqual(discarded, 1, "only the stale day's session")
        XCTAssertEqual(due, [.skinCheck(InApp.day)])
        let stale = try await store.plannedSessions(on: StoreFixtures.day(staleOpens))
        XCTAssertTrue(stale.isEmpty)
    }
}
