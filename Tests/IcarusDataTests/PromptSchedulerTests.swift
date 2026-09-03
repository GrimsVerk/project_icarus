// Slice 4's prompts, asserted one promise per test against the fake port. The
// scheduler itself is never mocked: the only boundary here is the notification
// port, which is the protocol the slice declares for exactly that purpose.
// swiftlint:disable file_length

@testable import IcarusCore
@testable import IcarusData
import XCTest

/// Fixed instants, days and records for the prompt tests. Nothing here is
/// derived from `Date()`, and every day carries the zone it was decided in.
///
/// The pieces are copied from the Core fixtures (`Curves`, `SessionFixture`)
/// rather than imported: test targets cannot import each other's code.
private enum Prompts {
    static let oslo = TimeZone(identifier: "Europe/Oslo")!
    static let oneHour: TimeInterval = 3600
    static let oneDay: TimeInterval = 86400
    static let place = Coordinate(latitude: 59.9, longitude: 10.75)

    /// A fixed instant in a named zone.
    static func instant(
        _ year: Int,
        _ month: Int,
        _ dayOfMonth: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        zone: TimeZone = oslo
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = dayOfMonth
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }

    /// The calendar day of `year-month-dayOfMonth` in `zone`.
    static func dayKey(_ year: Int, _ month: Int, _ dayOfMonth: Int, zone: TimeZone = oslo) -> DayKey {
        DayKey(instant(year, month, dayOfMonth, 12, zone: zone), timeZone: zone)
    }

    /// A scheduler over a fake port, and the port to read `pending()` from.
    static func scheduler(
        _ authorization: NotificationAuthorization = .granted
    ) -> (PromptScheduler, FakeNotificationPort) {
        let port = FakeNotificationPort(authorization: authorization)
        return (PromptScheduler(port: port, tunables: Tunables.current), port)
    }

    /// A flat curve covering `day`, stored the way a session record stores one.
    static func curve(on day: DayKey) -> StoredCurve {
        let midnight = day.start()
        let samples = (0 ... 30).map {
            HourlyUVI(time: midnight.addingTimeInterval(Double($0) * oneHour), uvi: 4)
        }
        return StoredCurve(
            hourly: samples,
            solarNoon: midnight.addingTimeInterval(13 * oneHour),
            timeZoneID: day.timeZoneID,
            location: place,
            fetchedAt: midnight
        )
    }

    /// One session on `day`. A logged session faced exactly what it planned, so
    /// its planned and actual windows end at the same instant.
    static func session(
        on day: DayKey,
        from start: Date,
        to end: Date,
        state: SessionState = .logged
    ) -> SessionRecord {
        let interval = ExposureInterval(exposure: .lying(.faceUp), window: Window(start: start, end: end))
        return SessionRecord(
            day: day,
            createdAt: start.addingTimeInterval(-oneHour),
            plannedWindow: Window(start: start, end: end),
            plannedIntervals: [interval],
            firstSide: .faceUp,
            actualIntervals: state == .logged ? [interval] : nil,
            posture: .lyingTurning,
            coverHeadAndShoulders: false,
            intent: .stayWholeWindow,
            ceilingAtPlan: .standard,
            state: state,
            dosePerRegion: [.front: 1.2, .back: 1.2, .headAndShoulders: 0.6],
            curveUsed: curve(on: day),
            forecastFetchedAt: start.addingTimeInterval(-oneHour),
            forecastPlace: place
        )
    }

    /// The skin report for `day`, optionally already carrying its lasting colour.
    static func report(
        on day: DayKey,
        at reportedAt: Date,
        lastingColour: LastingColour? = nil,
        lastingColourAt: Date? = nil
    ) -> SkinReport {
        SkinReport(
            day: day,
            reportedAt: reportedAt,
            answer: .faintPink,
            region: .front,
            channel: .notification,
            lastingColour: lastingColour,
            lastingColourAt: lastingColourAt
        )
    }
}

private extension PendingNotification {
    /// The index of a reapplication alert, or nil for any other kind.
    var reapplyIndex: Int? {
        if case let .timerReapply(index) = kind {
            return index
        }
        return nil
    }
}

// MARK: - The day's skin check

final class PromptSchedulerSkinCheckTests: XCTestCase {
    private let day = Prompts.dayKey(2026, 6, 15)

    /// One planned and one logged session on a day: one skin check, twenty
    /// hours after the last of them.
    func testOneDayOfSessionsSchedulesOneSkinCheckTwentyHoursAfterTheLast() async throws {
        let (scheduler, port) = Prompts.scheduler()
        let lastEnd = Prompts.instant(2026, 6, 15, 16)

        await scheduler.sessionsChanged(on: day, lastSessionEnd: lastEnd)

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 1)
        let notification = try XCTUnwrap(pending.first)
        XCTAssertEqual(notification.kind, .skinCheck(day))
        XCTAssertEqual(notification.fireAt, lastEnd.addingTimeInterval(20 * Prompts.oneHour))
    }

    /// The pending identifier is "skin-" plus the day's zone-carrying id.
    func testSkinCheckIdentifierIsSkinPlusTheDayIdentifier() async throws {
        let (scheduler, port) = Prompts.scheduler()

        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 16))

        let notification = try await XCTUnwrap(port.pending().first)
        XCTAssertEqual(notification.id, "skin-" + day.id)
        XCTAssertEqual(notification.id, "skin-2026-06-15@Europe/Oslo")
    }

    /// Adding a later session moves the skin check; it never leaves two.
    func testAddingALaterSessionMovesTheSkinCheck() async {
        let (scheduler, port) = Prompts.scheduler()
        let later = Prompts.instant(2026, 6, 15, 16)

        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 14))
        await scheduler.sessionsChanged(on: day, lastSessionEnd: later)

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.fireAt, later.addingTimeInterval(20 * Prompts.oneHour))
    }

    /// The day's last session was discarded: its skin check goes with it.
    func testDiscardingTheDaysLastSessionCancelsTheSkinCheck() async {
        let (scheduler, port) = Prompts.scheduler()

        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 16))
        await scheduler.sessionsChanged(on: day, lastSessionEnd: nil)

        let pending = await port.pending()
        XCTAssertEqual(pending.filter { $0.kind == .skinCheck(day) }.count, 0)
    }

    /// Cancelling one day never cancels another day's.
    func testCancellingOneDayLeavesAnotherDaysSkinCheckPending() async throws {
        let (scheduler, port) = Prompts.scheduler()
        let other = Prompts.dayKey(2026, 6, 16)
        let otherEnd = Prompts.instant(2026, 6, 16, 15)

        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 16))
        await scheduler.sessionsChanged(on: other, lastSessionEnd: otherEnd)
        await scheduler.sessionsChanged(on: day, lastSessionEnd: nil)

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 1)
        let survivor = try XCTUnwrap(pending.first)
        XCTAssertEqual(survivor.kind, .skinCheck(other))
        XCTAssertEqual(survivor.fireAt, otherEnd.addingTimeInterval(20 * Prompts.oneHour))
    }
}

// MARK: - The lasting-colour prompt

final class PromptSchedulerLastingColourTests: XCTestCase {
    private let day = Prompts.dayKey(2026, 6, 15)

    /// Only a report schedules it, four days after the report itself.
    func testReportAddedSchedulesTheLastingColourFourDaysLater() async throws {
        let (scheduler, port) = Prompts.scheduler()
        let reportedAt = Prompts.instant(2026, 6, 16, 9)

        await scheduler.reportAdded(on: day, at: reportedAt)

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 1)
        let notification = try XCTUnwrap(pending.first)
        XCTAssertEqual(notification.kind, .lastingColour(day))
        XCTAssertEqual(notification.fireAt, reportedAt.addingTimeInterval(4 * Prompts.oneDay))
        XCTAssertEqual(notification.id, "colour-" + day.id)
    }

    /// Sessions alone never schedule it — the report is what starts the clock.
    func testSessionsAloneScheduleNoLastingColour() async {
        let (scheduler, port) = Prompts.scheduler()

        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 16))

        let pending = await port.pending()
        XCTAssertEqual(pending.filter { $0.kind == .lastingColour(day) }.count, 0)
    }

    /// Discarding the day's last session cancels the lasting colour too.
    func testDiscardingTheDaysLastSessionCancelsTheLastingColour() async {
        let (scheduler, port) = Prompts.scheduler()

        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 16))
        await scheduler.reportAdded(on: day, at: Prompts.instant(2026, 6, 16, 9))
        await scheduler.sessionsChanged(on: day, lastSessionEnd: nil)

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 0)
    }

    /// A later session moves the skin check and leaves the lasting colour where
    /// the report put it.
    func testALaterSessionLeavesTheLastingColourAtItsReportTime() async {
        let (scheduler, port) = Prompts.scheduler()
        let reportedAt = Prompts.instant(2026, 6, 16, 9)

        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 14))
        await scheduler.reportAdded(on: day, at: reportedAt)
        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 16))

        let pending = await port.pending()
        let colours = pending.filter { $0.kind == .lastingColour(day) }
        XCTAssertEqual(colours.count, 1)
        XCTAssertEqual(colours.first?.fireAt, reportedAt.addingTimeInterval(4 * Prompts.oneDay))
    }
}

// MARK: - Authorization

final class PromptSchedulerAuthorizationTests: XCTestCase {
    private let day = Prompts.dayKey(2026, 6, 15)

    /// Denied: nothing is scheduled at all.
    func testDeniedAuthorizationSchedulesNothing() async {
        let (scheduler, port) = Prompts.scheduler(.denied)
        let start = Prompts.instant(2026, 6, 15, 12)

        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 16))
        await scheduler.reportAdded(on: day, at: Prompts.instant(2026, 6, 16, 9))
        await scheduler.scheduleTimer(
            sideEnd: start.addingTimeInterval(45 * 60),
            reapply: [start.addingTimeInterval(2 * Prompts.oneHour)],
            sessionEnd: start.addingTimeInterval(3 * Prompts.oneHour)
        )

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 0)
    }

    /// Not yet asked: also nothing.
    func testNotDeterminedAuthorizationSchedulesNothing() async {
        let (scheduler, port) = Prompts.scheduler(.notDetermined)

        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 16))
        await scheduler.reportAdded(on: day, at: Prompts.instant(2026, 6, 16, 9))

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 0)
    }

    /// With notifications denied the in-app window is what surfaces the day.
    func testDeniedAuthorizationStillListsTheDayInApp() async {
        let (scheduler, port) = Prompts.scheduler(.denied)
        let lastEnd = Prompts.instant(2026, 6, 15, 16)
        let history = History(sessions: [
            Prompts.session(on: day, from: Prompts.instant(2026, 6, 15, 13), to: lastEnd),
        ])

        await scheduler.sessionsChanged(on: day, lastSessionEnd: lastEnd)

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 0)
        let due = await scheduler.dueInApp(history: history, now: lastEnd.addingTimeInterval(20 * Prompts.oneHour))
        XCTAssertEqual(due, [.skinCheck(day)])
    }
}

// MARK: - The in-app fallback windows

final class PromptSchedulerInAppWindowTests: XCTestCase {
    private let day = Prompts.dayKey(2026, 6, 15)
    private let lastEnd = Prompts.instant(2026, 6, 15, 16)

    private func oneSessionDay() -> History {
        History(sessions: [
            Prompts.session(on: day, from: Prompts.instant(2026, 6, 15, 13), to: lastEnd),
        ])
    }

    /// The skin-check window opens twelve hours after the day's last session.
    func testSkinCheckIsDueFromTwelveHoursAfterTheLastSession() async {
        let (scheduler, _) = Prompts.scheduler()
        let history = oneSessionDay()
        let opens = lastEnd.addingTimeInterval(12 * Prompts.oneHour)

        let before = await scheduler.dueInApp(history: history, now: opens.addingTimeInterval(-1))
        let atOpening = await scheduler.dueInApp(history: history, now: opens)

        XCTAssertEqual(before, [])
        XCTAssertEqual(atOpening, [.skinCheck(day)])
    }

    /// It closes seventy-two hours after that same session.
    func testSkinCheckStopsBeingDueSeventyTwoHoursAfterTheLastSession() async {
        let (scheduler, _) = Prompts.scheduler()
        let history = oneSessionDay()
        let closes = lastEnd.addingTimeInterval(72 * Prompts.oneHour)

        let atClosing = await scheduler.dueInApp(history: history, now: closes)
        let after = await scheduler.dueInApp(history: history, now: closes.addingTimeInterval(1))

        XCTAssertEqual(atClosing, [.skinCheck(day)])
        XCTAssertEqual(after, [])
    }

    /// The window hangs off the day's LAST session, planned or logged, not its
    /// first.
    func testTheWindowIsMeasuredFromTheDaysLastSession() async {
        let (scheduler, _) = Prompts.scheduler()
        let earlyEnd = Prompts.instant(2026, 6, 15, 14)
        let history = History(sessions: [
            Prompts.session(on: day, from: Prompts.instant(2026, 6, 15, 11), to: earlyEnd, state: .planned),
            Prompts.session(on: day, from: Prompts.instant(2026, 6, 15, 15), to: lastEnd),
        ])

        let afterTheEarlyOne = await scheduler.dueInApp(
            history: history, now: earlyEnd.addingTimeInterval(12 * Prompts.oneHour)
        )
        let afterTheLastOne = await scheduler.dueInApp(
            history: history, now: lastEnd.addingTimeInterval(12 * Prompts.oneHour)
        )

        XCTAssertEqual(afterTheEarlyOne, [])
        XCTAssertEqual(afterTheLastOne, [.skinCheck(day)])
    }

    /// A day that has been reported is no longer asked about.
    func testADayWithAReportIsNotDueForASkinCheck() async {
        let (scheduler, _) = Prompts.scheduler()
        var history = oneSessionDay()
        history.reports = [Prompts.report(on: day, at: lastEnd.addingTimeInterval(20 * Prompts.oneHour))]

        let due = await scheduler.dueInApp(history: history, now: lastEnd.addingTimeInterval(24 * Prompts.oneHour))

        XCTAssertEqual(due, [])
    }

    /// A day whose only session was discarded is never asked about.
    func testADayWithOnlyADiscardedSessionIsNotDue() async {
        let (scheduler, _) = Prompts.scheduler()
        let history = History(sessions: [
            Prompts.session(on: day, from: Prompts.instant(2026, 6, 15, 13), to: lastEnd, state: .discarded),
        ])

        let due = await scheduler.dueInApp(history: history, now: lastEnd.addingTimeInterval(20 * Prompts.oneHour))

        XCTAssertEqual(due, [])
    }

    /// The lasting-colour window runs from three to ten days after the report.
    func testLastingColourIsDueFromThreeToTenDaysAfterTheReport() async {
        let (scheduler, _) = Prompts.scheduler()
        let reportedAt = Prompts.instant(2026, 6, 16, 9)
        var history = oneSessionDay()
        history.reports = [Prompts.report(on: day, at: reportedAt)]

        let opens = reportedAt.addingTimeInterval(3 * Prompts.oneDay)
        let closes = reportedAt.addingTimeInterval(10 * Prompts.oneDay)
        let before = await scheduler.dueInApp(history: history, now: opens.addingTimeInterval(-1))
        let atOpening = await scheduler.dueInApp(history: history, now: opens)
        let atClosing = await scheduler.dueInApp(history: history, now: closes)
        let after = await scheduler.dueInApp(history: history, now: closes.addingTimeInterval(1))

        XCTAssertEqual(before, [])
        XCTAssertEqual(atOpening, [.lastingColour(day)])
        XCTAssertEqual(atClosing, [.lastingColour(day)])
        XCTAssertEqual(after, [])
    }

    /// Once the lasting colour is answered the day drops out.
    func testADayWhoseLastingColourIsAnsweredIsNotDue() async {
        let (scheduler, _) = Prompts.scheduler()
        let reportedAt = Prompts.instant(2026, 6, 16, 9)
        var history = oneSessionDay()
        history.reports = [Prompts.report(
            on: day,
            at: reportedAt,
            lastingColour: .aLittle,
            lastingColourAt: reportedAt.addingTimeInterval(4 * Prompts.oneDay)
        )]

        let due = await scheduler.dueInApp(
            history: history, now: reportedAt.addingTimeInterval(5 * Prompts.oneDay)
        )

        XCTAssertEqual(due, [])
    }

    /// Several due days come back in day order.
    func testDuePromptsAreSortedByDay() async {
        let (scheduler, _) = Prompts.scheduler()
        let earlier = Prompts.dayKey(2026, 6, 15)
        let later = Prompts.dayKey(2026, 6, 18)
        let laterEnd = Prompts.instant(2026, 6, 18, 16)
        let history = History(
            sessions: [Prompts.session(on: later, from: Prompts.instant(2026, 6, 18, 13), to: laterEnd)],
            reports: [Prompts.report(on: earlier, at: Prompts.instant(2026, 6, 16, 12))]
        )

        let due = await scheduler.dueInApp(history: history, now: Prompts.instant(2026, 6, 19, 13))

        XCTAssertEqual(due, [.lastingColour(earlier), .skinCheck(later)])
    }
}

// MARK: - The flip timer's alerts

final class PromptSchedulerTimerTests: XCTestCase {
    private let start = Prompts.instant(2026, 6, 15, 12)

    /// Side end, every reapplication, and the session's end are all pending.
    func testScheduleTimerSchedulesSideEndEveryReapplicationAndTheSessionEnd() async throws {
        let (scheduler, port) = Prompts.scheduler()
        let sideEnd = start.addingTimeInterval(45 * 60)
        let reapply = [start.addingTimeInterval(Prompts.oneHour), start.addingTimeInterval(3 * Prompts.oneHour)]
        let sessionEnd = start.addingTimeInterval(3.5 * Prompts.oneHour)

        await scheduler.scheduleTimer(sideEnd: sideEnd, reapply: reapply, sessionEnd: sessionEnd)

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 4)
        let side = try XCTUnwrap(pending.first { $0.kind == .timerSideEnd })
        XCTAssertEqual(side.id, "timer-side")
        XCTAssertEqual(side.fireAt, sideEnd)
        let end = try XCTUnwrap(pending.first { $0.kind == .timerSessionEnd })
        XCTAssertEqual(end.id, "timer-end")
        XCTAssertEqual(end.fireAt, sessionEnd)
        let reapplications = pending.filter { $0.reapplyIndex != nil }.sorted { $0.fireAt < $1.fireAt }
        XCTAssertEqual(reapplications.map(\.fireAt), reapply)
        XCTAssertEqual(Set(reapplications.map(\.id)).count, 2)
        for notification in reapplications {
            XCTAssertEqual(notification.id, "timer-reapply-\(notification.reapplyIndex ?? -1)")
        }
    }

    /// No side to end — up and about — so no side alert.
    func testScheduleTimerWithoutASideEndSchedulesNoSideAlert() async {
        let (scheduler, port) = Prompts.scheduler()
        let sessionEnd = start.addingTimeInterval(2 * Prompts.oneHour)

        await scheduler.scheduleTimer(
            sideEnd: nil, reapply: [start.addingTimeInterval(Prompts.oneHour)], sessionEnd: sessionEnd
        )

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(pending.filter { $0.kind == .timerSideEnd }.count, 0)
        XCTAssertEqual(pending.first { $0.kind == .timerSessionEnd }?.fireAt, sessionEnd)
    }

    /// Scheduling again replaces the previous run's alerts rather than adding to
    /// them.
    func testSchedulingTheTimerAgainReplacesThePreviousAlerts() async {
        let (scheduler, port) = Prompts.scheduler()
        let secondEnd = start.addingTimeInterval(5 * Prompts.oneHour)

        await scheduler.scheduleTimer(
            sideEnd: start.addingTimeInterval(45 * 60),
            reapply: [start.addingTimeInterval(Prompts.oneHour)],
            sessionEnd: start.addingTimeInterval(2 * Prompts.oneHour)
        )
        await scheduler.scheduleTimer(
            sideEnd: nil,
            reapply: [start.addingTimeInterval(3 * Prompts.oneHour), start.addingTimeInterval(4 * Prompts.oneHour)],
            sessionEnd: secondEnd
        )

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 3)
        XCTAssertEqual(pending.filter { $0.kind == .timerSideEnd }.count, 0)
        XCTAssertEqual(pending.filter { $0.reapplyIndex != nil }.count, 2)
        XCTAssertEqual(pending.first { $0.kind == .timerSessionEnd }?.fireAt, secondEnd)
    }

    /// Cancelling the timer takes its alerts and nothing else.
    func testCancelTimerRemovesTheTimerAlertsAndLeavesTheSkinCheck() async throws {
        let (scheduler, port) = Prompts.scheduler()
        let day = Prompts.dayKey(2026, 6, 15)

        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 16))
        await scheduler.scheduleTimer(
            sideEnd: start.addingTimeInterval(45 * 60),
            reapply: [start.addingTimeInterval(Prompts.oneHour)],
            sessionEnd: start.addingTimeInterval(2 * Prompts.oneHour)
        )
        await scheduler.cancelTimer()

        let pending = await port.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(try XCTUnwrap(pending.first).kind, .skinCheck(day))
    }
}

// MARK: - Notification identifiers

final class PromptSchedulerNotificationIDTests: XCTestCase {
    /// The identifier the port holds parses back to the day it was keyed by,
    /// zone and all, on a host whose own zone is UTC.
    func testSkinCheckIdentifierRoundTripsForAnOsloDay() async throws {
        let (scheduler, port) = Prompts.scheduler()
        let day = Prompts.dayKey(2026, 6, 15)

        await scheduler.sessionsChanged(on: day, lastSessionEnd: Prompts.instant(2026, 6, 15, 16))

        let identifier = try await XCTUnwrap(port.pending().first).id
        XCTAssertEqual(PromptScheduler.day(fromNotificationID: identifier), day)
        XCTAssertEqual(day.timeZoneID, "Europe/Oslo")
    }

    /// The lasting colour's identifier parses back the same way.
    func testLastingColourIdentifierRoundTrips() async throws {
        let (scheduler, port) = Prompts.scheduler()
        let day = Prompts.dayKey(2026, 6, 15)

        await scheduler.reportAdded(on: day, at: Prompts.instant(2026, 6, 16, 9))

        let identifier = try await XCTUnwrap(port.pending().first).id
        XCTAssertEqual(PromptScheduler.day(fromNotificationID: identifier), day)
    }

    /// A day in another zone is a different day, and its identifier says so.
    func testTwoZonesGiveTwoDifferentDays() throws {
        let oslo = Prompts.dayKey(2026, 6, 15)
        let utc = try Prompts.dayKey(2026, 6, 15, zone: XCTUnwrap(TimeZone(identifier: "UTC")))

        XCTAssertNotEqual(oslo, utc)
        XCTAssertEqual(PromptScheduler.day(fromNotificationID: "skin-" + utc.id), utc)
        XCTAssertNotEqual(PromptScheduler.day(fromNotificationID: "skin-" + utc.id), oslo)
    }

    /// Anything that is not one of the two prefixes over a real day is nil.
    func testMalformedNotificationIdentifiersReturnNil() {
        XCTAssertNil(PromptScheduler.day(fromNotificationID: ""))
        XCTAssertNil(PromptScheduler.day(fromNotificationID: "skin-"))
        XCTAssertNil(PromptScheduler.day(fromNotificationID: "colour-"))
        XCTAssertNil(PromptScheduler.day(fromNotificationID: "skin-not-a-day"))
        XCTAssertNil(PromptScheduler.day(fromNotificationID: "skin-2026-06-15@Nowhere/AtAll"))
        XCTAssertNil(PromptScheduler.day(fromNotificationID: "timer-end"))
        XCTAssertNil(PromptScheduler.day(fromNotificationID: "2026-06-15@Europe/Oslo"))
    }
}
