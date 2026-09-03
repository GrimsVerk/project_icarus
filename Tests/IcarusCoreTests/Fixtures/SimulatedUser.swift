import Foundation
@testable import IcarusCore

/// A user the engine cannot see: they have a real sensitivity multiplier and a
/// real adaptation gain, they do exactly what the app recommends, and they
/// answer the skin check truthfully from the ratio of the dose they received to
/// the threshold they actually have.
///
/// The response model is the engine's, not the test author's (S3): the bands
/// come from `Tunables.reporterAnswer(ratio:)`, and the user's own tan state
/// follows the same rise-and-decay rule the engine models. Only the gain in
/// their threshold — `trueGainScale` — is allowed to differ from the model, so
/// that the separation runs measure exactly one mismatch.
///
/// Every session is three hours, lying down and turning over, on
/// `Curves.beachFlatUVI8`, and every region is dosed at its own target for the
/// day, so the dose fraction that drives the tan state is exactly 1.0.
struct SimulatedUser {
    var trueMultiplier: Double = 1
    var trueGainScale: Double = 1
    var skinType: SkinType = .ii
    var ceiling: Ceiling = .standard
    var zone: TimeZone = Curves.zone
    var tunables: Tunables = .current

    /// Local noon, and three hours out.
    static let sessionHour = 12.0
    static let sessionHours = 3.0

    /// One session day: an offset in whole days from the run's first day, an
    /// optional answer that replaces the truthful one (S3's outliers), and an
    /// optional lasting-colour answer given an hour after the session.
    struct Day {
        var offset: Int
        var answer: SkinAnswer?
        var lastingColour: LastingColour?

        init(_ offset: Int, answer: SkinAnswer? = nil, lastingColour: LastingColour? = nil) {
            self.offset = offset
            self.answer = answer
            self.lastingColour = lastingColour
        }
    }

    /// What one run produced: the history the app would hold, and — for the
    /// assertions — what the user was actually given and what they actually
    /// answered, day by day.
    struct Run {
        var history = History()
        var answers: [SkinAnswer] = []
        /// The front region's dose, which is that region's target for the day.
        var doses: [SED] = []
        /// The user's real threshold before each session.
        var thresholds: [SED] = []
        var sessionEnds: [Date] = []
        /// The user's real tan state before each session, and after the last one.
        var trueTans: [Double] = []
        var trueTanAfterLast: Double = 0
        var skinType: SkinType = .ii
        var tunables: Tunables = .current

        /// The state the app would hold at `moment`, replayed from the history.
        func replayed(at moment: Date) -> DerivedState {
            Replay.replay(history, skinType: skinType, now: moment, tunables: tunables).state
        }

        func effects(at moment: Date) -> [UUID: CalibrationEffect] {
            Replay.replay(history, skinType: skinType, now: moment, tunables: tunables).effects
        }

        /// The end of the last session. Nothing in the history is later than
        /// `finish`, which is an hour past the last answer.
        var lastSessionEnd: Date {
            sessionEnds.last ?? Curves.start
        }

        var finish: Date {
            lastSessionEnd.addingTimeInterval(21 * 3600)
        }

        var state: DerivedState {
            replayed(at: finish)
        }

        var multiplier: Double {
            state.multiplier
        }

        /// The front region as it stood when the last session ended — before
        /// any gap that follows it has been decayed away.
        var lastFront: RegionState {
            state.regions[.front] ?? RegionState()
        }
    }

    // MARK: - Running a schedule

    /// Runs the schedule: on every session day the user asks the app, does
    /// exactly what it says, and answers the skin check twenty hours later.
    func run(_ days: [Day], from start: Date) throws -> Run {
        let stored = try Curves.beachFlatUVI8().stored(for: DayKey(Curves.start, timeZone: Curves.zone))
        var run = Run(skinType: skinType, tunables: tunables)
        var trueTan = 0.0
        var previous: Int?
        for day in days {
            let opens = Self.noon(start, day.offset)
            let closes = opens.addingTimeInterval(Self.sessionHours * 3600)
            if let previous {
                trueTan = decayedTrueTan(trueTan, days: Double(day.offset - previous))
            }
            let state = Replay.replay(run.history, skinType: skinType, now: opens, tunables: tunables).state
            let dose = doses(state: state, at: opens)
            let threshold = trueThreshold(tanState: trueTan)
            let front = dose[.front] ?? 0
            let answer = day.answer ?? tunables.reporterAnswer(ratio: front / threshold)
            run.history.sessions.append(session(opens: opens, closes: closes, dose: dose, curve: stored))
            run.history.reports.append(report(day: day, opens: opens, closes: closes, answer: answer))
            run.answers.append(answer)
            run.doses.append(front)
            run.thresholds.append(threshold)
            run.sessionEnds.append(closes)
            run.trueTans.append(trueTan)
            trueTan = risenTrueTan(trueTan)
            previous = day.offset
        }
        run.trueTanAfterLast = trueTan
        return run
    }

    /// The user's real threshold `days` after their last session, once the tan
    /// they built has faded by that much.
    func trueThreshold(_ run: Run, daysAfterLastSession days: Double) -> SED {
        trueThreshold(tanState: decayedTrueTan(run.trueTanAfterLast, days: days))
    }

    /// The dose the app recommends for each region: that region's whole target
    /// for the day, which is what "the user does exactly what it says" means.
    func doses(state: DerivedState, at moment: Date) -> [Region: SED] {
        var doses = [Region: SED]()
        for (region, target) in targets(state: state, at: moment) {
            doses[region] = target.target
        }
        return doses
    }

    func targets(state: DerivedState, at moment: Date) -> [Region: RegionTarget] {
        let profile = Profile(skinType: skinType, ceiling: ceiling)
        var targets = [Region: RegionTarget]()
        for region in Region.allCases {
            targets[region] = TanningGoal().target(for: region, profile: profile, state: state,
                                                   now: moment, stale: false, tunables: tunables)
        }
        return targets
    }

    /// `MED_baseline × trueMultiplier × (1 + trueGainScale × gain × tanState)`.
    func trueThreshold(tanState: Double) -> SED {
        tunables.medBaselineSED(skinType) * trueMultiplier
            * (1 + trueGainScale * tunables.adaptationGain(skinType.band) * tanState)
    }

    // MARK: - Building the records

    private func session(opens: Date, closes: Date, dose: [Region: SED], curve: StoredCurve) -> SessionRecord {
        let middle = opens.addingTimeInterval(closes.timeIntervalSince(opens) / 2)
        let intervals = [
            ExposureInterval(exposure: .lying(.faceUp), window: Window(start: opens, end: middle)),
            ExposureInterval(exposure: .lying(.faceDown), window: Window(start: middle, end: closes)),
        ]
        return SessionRecord(
            day: DayKey(opens, timeZone: zone),
            createdAt: opens,
            plannedWindow: Window(start: opens, end: closes),
            plannedIntervals: intervals,
            firstSide: .faceUp,
            actualIntervals: intervals,
            posture: .lyingTurning,
            coverHeadAndShoulders: false,
            intent: .stayWholeWindow,
            ceilingAtPlan: ceiling,
            state: .logged,
            dosePerRegion: dose,
            curveUsed: curve,
            forecastFetchedAt: Curves.start,
            forecastPlace: Curves.location
        )
    }

    private func report(day: Day, opens: Date, closes: Date, answer: SkinAnswer) -> SkinReport {
        SkinReport(
            day: DayKey(opens, timeZone: zone),
            reportedAt: closes.addingTimeInterval(tunables.skinCheckDelayHours * 3600),
            answer: answer,
            timing: answer == .normal ? nil : .thatEvening,
            region: .front,
            channel: .notification,
            lastingColour: day.lastingColour,
            lastingColourAt: day.lastingColour == nil ? nil : closes.addingTimeInterval(3600)
        )
    }

    // MARK: - The user's own skin

    private func decayedTrueTan(_ tanState: Double, days: Double) -> Double {
        tanState * pow(0.5, days / tunables.decayHalfLifeDays)
    }

    private func risenTrueTan(_ tanState: Double) -> Double {
        let step = tunables.riseMultiplier(skinType.band) / tunables.riseTimeConstantDays
        return tanState + (1 - tanState) * (1 - exp(-step))
    }

    static func noon(_ start: Date, _ offset: Int) -> Date {
        start.addingTimeInterval(Double(offset) * 86400 + sessionHour * 3600)
    }
}

// MARK: - Schedules

extension SimulatedUser {
    /// Consecutive days, one session each.
    static func daily(_ count: Int) -> [Day] {
        (0 ..< count).map { Day($0) }
    }

    /// "Regular sessions" as S4 defines them: five a week, Monday to Friday.
    /// The fixtures' first day, 2026-06-15, is a Monday, so offset 4 of every
    /// week is a Friday and the weekend is offsets 5 and 6.
    static func weekdays(weeks: Int) -> [Day] {
        (0 ..< weeks).flatMap { week in (0 ..< 5).map { Day(week * 7 + $0) } }
    }

    /// The Friday of every week in a five-a-week schedule: the day the tan
    /// state peaks before the weekend fades it.
    static func fridays(weeks: Int) -> [Int] {
        (0 ..< weeks).map { $0 * 7 + 4 }
    }

    /// Five a week, with a "no lasting colour" answer on the given days — the
    /// answers that reach the plateau outcome (R14).
    static func weekdays(weeks: Int, noLastingColourOn days: Set<Int>) -> [Day] {
        weekdays(weeks: weeks).map { day in
            days.contains(day.offset) ? Day(day.offset, lastingColour: .no) : day
        }
    }

    /// One session a day for `days`, then a gap, then `after` more — the shape
    /// the tan-cycle tests need.
    static func cycles(_ blocks: [Int], gapDays: Int) -> [Day] {
        var days: [Day] = []
        var offset = 0
        for block in blocks {
            days += (0 ..< block).map { Day(offset + $0) }
            offset += block + gapDays
        }
        return days
    }
}

// MARK: - Single records

/// One logged session and one skin report, built exactly as the tests need
/// them, for the unit tests that call `CalibrationEngine` directly.
enum SessionFixture {
    /// A three-hour lying session on `opens`' day, dosed as given.
    static func logged(
        at opens: Date,
        dose: [Region: SED],
        ceiling: Ceiling = .standard,
        manualMultiplier: Double? = nil
    ) throws -> SessionRecord {
        let closes = opens.addingTimeInterval(3 * 3600)
        let stored = try Curves.beachFlatUVI8().stored(for: DayKey(Curves.start, timeZone: Curves.zone))
        let interval = ExposureInterval(exposure: .lying(.faceUp), window: Window(start: opens, end: closes))
        return SessionRecord(
            day: DayKey(opens, timeZone: Curves.zone),
            createdAt: opens,
            plannedWindow: Window(start: opens, end: closes),
            plannedIntervals: [interval],
            firstSide: .faceUp,
            actualIntervals: [interval],
            posture: .lyingTurning,
            coverHeadAndShoulders: false,
            intent: .stayWholeWindow,
            ceilingAtPlan: ceiling,
            manualMultiplierAtPlan: manualMultiplier,
            state: .logged,
            dosePerRegion: dose,
            curveUsed: stored,
            forecastFetchedAt: Curves.start,
            forecastPlace: Curves.location
        )
    }

    /// The skin check for `opens`' day, answered twenty hours later.
    static func report(
        _ answer: SkinAnswer,
        on opens: Date,
        region: ReportRegion = .front,
        timing: RednessTiming? = nil,
        confounders: Set<Confounder> = []
    ) -> SkinReport {
        SkinReport(
            day: DayKey(opens, timeZone: Curves.zone),
            reportedAt: opens.addingTimeInterval(23 * 3600),
            answer: answer,
            timing: timing,
            region: region,
            confounders: confounders,
            channel: .notification
        )
    }
}
