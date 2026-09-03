import Foundation
import IcarusCore

/// Whether the system will let us alert the user at all.
public enum NotificationAuthorization: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}

/// What a scheduled alert is about. The payload is the day the question is
/// about, which always carries its time zone (`DayKey`), or the timer step.
public enum NotificationKind: Sendable, Equatable {
    case skinCheck(DayKey)
    case lastingColour(DayKey)
    case timerSideEnd
    case timerReapply(Int)
    case timerSessionEnd
}

/// One alert waiting to fire.
public struct PendingNotification: Sendable, Equatable {
    public let id: String
    public let fireAt: Date
    public let kind: NotificationKind

    public init(id: String, fireAt: Date, kind: NotificationKind) {
        self.id = id
        self.fireAt = fireAt
        self.kind = kind
    }
}

/// The system notification centre, as the only thing this layer needs from it.
/// Every identifier is derived from the thing it is about, so cancelling is a
/// prefix match and never bookkeeping we could get out of step with.
public protocol NotificationPort: Sendable {
    func authorization() async -> NotificationAuthorization
    func schedule(_ n: PendingNotification) async
    func cancel(idPrefix: String) async
    func pending() async -> [PendingNotification]
}

/// A question the app must ask on the next launch, because a notification was
/// never allowed or was never answered.
public enum DuePrompt: Sendable, Equatable {
    case skinCheck(DayKey)
    case lastingColour(DayKey)
}

// MARK: - Identifiers

/// The one place identifiers are built and read back. `DayKey.id` is the day's
/// only string form, so `"skin-" + day.id` round-trips through
/// `PromptScheduler.day(fromNotificationID:)` in any zone.
enum NotificationID {
    static let skinPrefix = "skin-"
    static let colourPrefix = "colour-"
    static let timerPrefix = "timer-"
    static let timerSide = "timer-side"
    static let timerEnd = "timer-end"
    static let timerReapplyPrefix = "timer-reapply-"

    static func skinCheck(_ day: DayKey) -> String {
        skinPrefix + day.id
    }

    static func lastingColour(_ day: DayKey) -> String {
        colourPrefix + day.id
    }

    static func timerReapply(_ index: Int) -> String {
        timerReapplyPrefix + String(index)
    }

    /// The kind an identifier stands for, or nil when it is not ours.
    static func kind(of identifier: String) -> NotificationKind? {
        if let rest = identifier.after(skinPrefix) {
            return DayKey(id: rest).map(NotificationKind.skinCheck)
        }
        if let rest = identifier.after(colourPrefix) {
            return DayKey(id: rest).map(NotificationKind.lastingColour)
        }
        if identifier == timerSide {
            return .timerSideEnd
        }
        if identifier == timerEnd {
            return .timerSessionEnd
        }
        if let rest = identifier.after(timerReapplyPrefix), let index = Int(rest) {
            return .timerReapply(index)
        }
        return nil
    }
}

private extension String {
    /// What follows `prefix`, or nil when the string does not start with it.
    func after(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

// MARK: - The fake port

/// Records everything, decides nothing. Scheduling with an identifier that is
/// already pending replaces it, as the system centre does.
public actor FakeNotificationPort: NotificationPort {
    private let status: NotificationAuthorization
    private var scheduled: [PendingNotification] = []

    public init(authorization: NotificationAuthorization) {
        status = authorization
    }

    public func authorization() async -> NotificationAuthorization {
        status
    }

    public func schedule(_ n: PendingNotification) async {
        if let existing = scheduled.firstIndex(where: { $0.id == n.id }) {
            scheduled[existing] = n
        } else {
            scheduled.append(n)
        }
    }

    public func cancel(idPrefix: String) async {
        scheduled.removeAll { $0.id.hasPrefix(idPrefix) }
    }

    public func pending() async -> [PendingNotification] {
        scheduled
    }
}

// MARK: - The scheduler

/// Owns every prompt the app makes: the skin check about a day's sessions, the
/// lasting-colour question about a report, the flip timer's alerts, and the
/// in-app fallback for anything the system never delivered.
///
/// Nothing here decides *what* a session or a report is — the store does that
/// and tells us. We only keep the pending set in step with it.
public actor PromptScheduler {
    private let port: any NotificationPort
    private let tunables: Tunables

    public init(port: any NotificationPort, tunables: Tunables) {
        self.port = port
        self.tunables = tunables
    }

    /// The day's planned-or-logged sessions changed. `lastSessionEnd` is the end
    /// of the last of them, or nil when the last one was discarded and the day
    /// has no session left — which cancels the day's questions, both of them.
    ///
    /// One skin check per day, always keyed by the day, so a later session
    /// simply moves it.
    public func sessionsChanged(on day: DayKey, lastSessionEnd: Date?) async {
        guard let lastSessionEnd else {
            await port.cancel(idPrefix: NotificationID.skinCheck(day))
            await port.cancel(idPrefix: NotificationID.lastingColour(day))
            return
        }
        await port.cancel(idPrefix: NotificationID.skinCheck(day))
        let fireAt = lastSessionEnd.addingTimeInterval(tunables.skinCheckDelayHours * 3600)
        await scheduleIfAllowed(
            PendingNotification(id: NotificationID.skinCheck(day), fireAt: fireAt, kind: .skinCheck(day))
        )
    }

    /// A report about `day` was answered. The lasting-colour question is asked
    /// days after that answer, never after the session, so it is scheduled here
    /// and nowhere else.
    public func reportAdded(on day: DayKey, at answeredAt: Date) async {
        await port.cancel(idPrefix: NotificationID.lastingColour(day))
        let fireAt = answeredAt.addingTimeInterval(tunables.lastingColourDelayDays * 86400)
        await scheduleIfAllowed(
            PendingNotification(id: NotificationID.lastingColour(day), fireAt: fireAt, kind: .lastingColour(day))
        )
    }

    /// The flip timer's alerts, as one set: the first side's end (nil when the
    /// session is not a lying one), each reapplication time, and the end of the
    /// session. Rescheduling replaces the whole set.
    public func scheduleTimer(sideEnd: Date?, reapply: [Date], sessionEnd: Date) async {
        await port.cancel(idPrefix: NotificationID.timerPrefix)
        if let sideEnd {
            await scheduleIfAllowed(
                PendingNotification(id: NotificationID.timerSide, fireAt: sideEnd, kind: .timerSideEnd)
            )
        }
        for (index, time) in reapply.enumerated() {
            await scheduleIfAllowed(
                PendingNotification(
                    id: NotificationID.timerReapply(index), fireAt: time, kind: .timerReapply(index)
                )
            )
        }
        await scheduleIfAllowed(
            PendingNotification(id: NotificationID.timerEnd, fireAt: sessionEnd, kind: .timerSessionEnd)
        )
    }

    /// The timer stopped. Nothing about it is asked any more.
    public func cancelTimer() async {
        await port.cancel(idPrefix: NotificationID.timerPrefix)
    }

    /// What to ask in the app right now, because notifications were denied or a
    /// prompt went unanswered (R20). A day with a planned or logged session and
    /// no report is due for the skin check inside its window after the day's
    /// last session; a report with no lasting-colour answer is due for that
    /// question inside its own window after the answer. Ordered by day.
    public func dueInApp(history: History, now: Date) -> [DuePrompt] {
        var byDay: [DayKey: DuePrompt] = [:]

        let reportedDays = Set(history.reports.map(\.day))
        let skinWindow = tunables.inAppSkinCheckWindowHours
        for (day, lastEnd) in lastSessionEnds(in: history) where !reportedDays.contains(day) {
            let opens = lastEnd.addingTimeInterval(skinWindow.lowerBound * 3600)
            let closes = lastEnd.addingTimeInterval(skinWindow.upperBound * 3600)
            if now >= opens, now <= closes {
                byDay[day] = .skinCheck(day)
            }
        }

        let colourWindow = tunables.inAppLastingColourWindowDays
        for report in history.reports where report.lastingColour == nil {
            let opens = report.reportedAt.addingTimeInterval(colourWindow.lowerBound * 86400)
            let closes = report.reportedAt.addingTimeInterval(colourWindow.upperBound * 86400)
            if now >= opens, now <= closes {
                byDay[report.day] = .lastingColour(report.day)
            }
        }

        return byDay.keys.sorted().compactMap { byDay[$0] }
    }

    /// The day a notification we scheduled is about. Both question identifiers
    /// carry `DayKey.id` whole, so this is the exact inverse of building one.
    public static func day(fromNotificationID identifier: String) -> DayKey? {
        switch NotificationID.kind(of: identifier) {
        case let .skinCheck(day), let .lastingColour(day): day
        default: nil
        }
    }

    /// Scheduling is the one thing permission gates. Without it the in-app
    /// fallback is what surfaces the question, so we drop the request rather
    /// than pretending it is pending.
    private func scheduleIfAllowed(_ notification: PendingNotification) async {
        guard await port.authorization() == .granted else { return }
        await port.schedule(notification)
    }

    /// The end of each day's last planned-or-logged session. A logged session
    /// ends where it actually ended; a planned one where it is planned to.
    private func lastSessionEnds(in history: History) -> [DayKey: Date] {
        var ends: [DayKey: Date] = [:]
        for session in history.sessions where session.state == .planned || session.state == .logged {
            let end = session.actualWindow?.end ?? session.plannedWindow.end
            if let known = ends[session.day], known >= end {
                continue
            }
            ends[session.day] = end
        }
        return ends
    }
}
