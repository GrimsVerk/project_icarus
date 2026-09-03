import Foundation
import IcarusCore

/// Cumulative dose per region over the two spans History shows (R24).
public struct Totals: Sendable, Equatable {
    /// The last seven days of logged sessions.
    public let week: [Region: SED]
    /// Everything since each region's tan cycle opened.
    public let cycle: [Region: SED]

    public init(week: [Region: SED], cycle: [Region: SED]) {
        self.week = week
        self.cycle = cycle
    }
}

/// The one way in and out of the history (R25, R44).
///
/// The history is the record and nothing derived from it is stored: `state` is
/// a replay of the whole record under the current constants and the current
/// profile, memoised only so a screen can ask for it repeatedly. Every write
/// drops the memo, and so does a change of profile or of `Tunables`, because
/// the memo is keyed by all four things the answer depends on.
public actor HistoryStore {
    private let persistence: any HistoryPersistence
    private let tunables: Tunables
    private let profileProvider: @Sendable () -> Profile
    private var memo: (key: MemoKey, state: DerivedState)?

    public init(
        persistence: any HistoryPersistence,
        tunables: Tunables,
        profileProvider: @escaping @Sendable () -> Profile
    ) {
        self.persistence = persistence
        self.tunables = tunables
        self.profileProvider = profileProvider
    }

    /// A store over `MemoryPersistence` with a fixed profile — what tests, and
    /// platforms without SwiftData, run against.
    public static func inMemory(tunables: Tunables, profile: Profile) -> HistoryStore {
        HistoryStore(persistence: MemoryPersistence(), tunables: tunables, profileProvider: { profile })
    }

    /// The constant set this store replays under; the export records it.
    public var tunablesVersion: String {
        tunables.version
    }

    // MARK: - Reading

    public func history() throws -> History {
        try persistence.load()
    }

    /// The replayed state as it stands at `now`. Never a stored number.
    public func state(now: Date) throws -> DerivedState {
        let history = try persistence.load()
        let profile = profileProvider()
        let key = MemoKey(
            history: history,
            tunablesVersion: tunables.version,
            dayID: dayID(at: now, in: history),
            profile: profile
        )
        if let memo, memo.key == key {
            return memo.state
        }
        let replayed = Replay.replay(history, skinType: profile.skinType, now: now, tunables: tunables)
        memo = (key, replayed.state)
        return replayed.state
    }

    /// Forget the memoised state. Every write does this; a caller does it when
    /// something outside the store — the profile — has changed.
    public func invalidate() {
        memo = nil
    }

    /// The day's planned sessions, earliest window first.
    public func plannedSessions(on day: DayKey) throws -> [SessionRecord] {
        try sessions(on: day).filter { $0.state == .planned }
    }

    /// Every session of the day, whatever became of it, earliest window first.
    public func sessions(on day: DayKey) throws -> [SessionRecord] {
        try persistence.load().sessions
            .filter { $0.day == day }
            .sorted { ($0.plannedWindow.start, $0.createdAt) < ($1.plannedWindow.start, $1.createdAt) }
    }

    /// Weekly and cycle-to-date dose per region, from the logged record alone.
    public func totals(now: Date) throws -> Totals {
        let history = try persistence.load()
        let logged = history.sessions.filter { $0.state == .logged && $0.actualWindow != nil }
        let weekOpens = now.addingTimeInterval(-7 * 24 * 3600)

        var week = [Region: SED]()
        for session in logged {
            guard let end = session.actualWindow?.end, end > weekOpens, end <= now else { continue }
            for (region, dose) in session.dosePerRegion {
                week[region, default: 0] += dose
            }
        }

        var cycle = [Region: SED]()
        let regions = try state(now: now).regions
        for (region, regionState) in regions {
            guard let cycleStart = regionState.cycleStart else { continue }
            let opens = cycleStart.start()
            cycle[region] = logged
                .filter { ($0.actualWindow?.start ?? .distantPast) >= opens }
                .reduce(0) { $0 + ($1.dosePerRegion[region] ?? 0) }
        }
        return Totals(week: week, cycle: cycle)
    }

    // MARK: - Writing

    /// Store a planned session, replacing the one it supersedes (R45). The
    /// stored record's id is returned, which is what `log` is addressed by.
    @discardableResult
    public func upsertPlanned(_ new: SessionRecord, replacing id: UUID?) throws -> UUID {
        var history = try persistence.load()
        if let id {
            guard let superseded = history.sessions.firstIndex(where: { $0.id == id }) else {
                throw HistoryError.unknownSession(id)
            }
            history.sessions.remove(at: superseded)
        }
        var planned = new
        planned.state = .planned
        history.sessions.removeAll { $0.id == planned.id }
        history.sessions.append(planned)
        try persistence.replaceAll(history)
        invalidate()
        return planned.id
    }

    // Six arguments: the plan's contract fixes this signature.
    // swiftlint:disable function_parameter_count
    /// Log a session from the intervals actually faced (R22, R45).
    ///
    /// A planned session becomes logged; a logged one is updated in place,
    /// which is what the timer's stop does when it shortens the record; a
    /// discarded one is refused.
    public func log(
        _ id: UUID,
        actual: [ExposureInterval],
        sunscreen: SunscreenChoice?,
        doses: [Region: SED],
        factors: [Region: Double],
        targets: [Region: SED]
    ) throws {
        var session = try session(id)
        guard session.state != .discarded else { throw HistoryError.discarded(id) }
        session.actualIntervals = actual
        session.sunscreen = sunscreen
        session.dosePerRegion = doses
        session.factorsShown = factors
        session.targetsShown = targets
        session.state = .logged
        try persistence.upsertSession(session)
        invalidate()
    }

    // swiftlint:enable function_parameter_count

    /// Drop one session. A discarded session is never replayed and never
    /// counts towards any total.
    public func discard(_ id: UUID) throws {
        var session = try session(id)
        session.state = .discarded
        try persistence.upsertSession(session)
        invalidate()
    }

    /// Discard every planned session whose in-app skin-check window has closed
    /// unanswered by `cutoff`, and say how many that was (R45).
    @discardableResult
    public func discardPlanned(before cutoff: Date) throws -> Int {
        let history = try persistence.load()
        let windowCloses = tunables.inAppSkinCheckWindowHours.upperBound * 3600
        var discarded = 0
        for session in history.sessions where session.state == .planned {
            guard session.plannedWindow.end.addingTimeInterval(windowCloses) < cutoff else { continue }
            var stale = session
            stale.state = .discarded
            try persistence.upsertSession(stale)
            discarded += 1
        }
        if discarded > 0 {
            invalidate()
        }
        return discarded
    }

    /// Record one skin report and say what it did to the calibration (R21).
    /// One report per day: a second is refused rather than merged.
    @discardableResult
    public func addReport(_ report: SkinReport) throws -> CalibrationEffect {
        let history = try persistence.load()
        if history.reports.contains(where: { $0.day == report.day && $0.id != report.id }) {
            throw HistoryError.alreadyReported(report.day)
        }
        try persistence.upsertReport(report)
        invalidate()
        let replayed = try Replay.replay(
            persistence.load(),
            skinType: profileProvider().skinType,
            now: report.reportedAt,
            tunables: tunables
        )
        return replayed.effects[report.id] ?? .none
    }

    /// Record the lasting-colour answer against the day's report, at the
    /// instant it was given — never at the report's (R14).
    public func setLastingColour(day: DayKey, _ colour: LastingColour, at time: Date) throws {
        let history = try persistence.load()
        guard var answered = history.reports.first(where: { $0.day == day }) else {
            throw HistoryError.noReport(day)
        }
        answered.lastingColour = colour
        answered.lastingColourAt = time
        try persistence.upsertReport(answered)
        invalidate()
    }

    /// Start over: the history is the record, so deleting it deletes the
    /// calibration, the tan state and every total with it (R44).
    public func deleteAll() throws {
        try persistence.replaceAll(History())
        invalidate()
    }

    /// Replace the whole history at once. The import's landing, and atomic.
    public func replaceAll(_ history: History) throws {
        try persistence.replaceAll(history)
        invalidate()
    }

    // MARK: - Inside

    private func session(_ id: UUID) throws -> SessionRecord {
        guard let session = try persistence.load().sessions.first(where: { $0.id == id }) else {
            throw HistoryError.unknownSession(id)
        }
        return session
    }

    /// The day `now` falls in, in the zone the history was recorded in — the
    /// same instant is two different days in two different places, and the
    /// memo has to notice when the day turns over.
    private func dayID(at now: Date, in history: History) -> String {
        let latest = history.sessions.max { $0.createdAt < $1.createdAt }
        let zone = latest.flatMap { TimeZone(identifier: $0.day.timeZoneID) } ?? TimeZone.current
        return DayKey(now, timeZone: zone).id
    }

    /// Everything the replayed state depends on. A change to any of the four
    /// is a different answer, so the memo is keyed by all four.
    private struct MemoKey: Equatable {
        let history: History
        let tunablesVersion: String
        let dayID: String
        let profile: Profile
    }
}
