import Foundation

/// The R44 fold: the ordered history in, the current derived state out, under
/// today's `Tunables`.
///
/// Nothing here is stored. Region states and the multiplier are recomputed from
/// the record every time, so a change to the constants takes effect for every
/// existing user and for every historical normalisation at once. Per-region
/// doses are the exception in the other direction: they are what the session
/// stored, never recomputed, because the forecast is not part of the replay.
public enum Replay {
    /// Fold a whole history into state, and keep what every report did.
    public static func replay(
        _ history: History,
        skinType: SkinType,
        now: Date,
        tunables: Tunables
    ) -> (state: DerivedState, effects: [UUID: CalibrationEffect]) {
        var fold = Fold(skinType: skinType, tunables: tunables, history: history)
        for event in history.ordered() {
            switch event {
            case let .session(session): fold.fold(session)
            case let .report(report): fold.fold(report)
            case let .lastingColour(report): fold.foldLastingColour(report)
            }
        }
        fold.finish(at: now)
        return (fold.state, fold.effects)
    }
}

// MARK: - The fold

/// The running state of one replay. It exists so each event kind is one short
/// method over the same few pieces of bookkeeping.
private struct Fold {
    /// What one region took on one day, and the target it was measured against
    /// — the pair the lasting-colour answer needs days later.
    struct DayEntry {
        var dose: SED
        var target: SED
    }

    let skinType: SkinType
    let tunables: Tunables
    let goal = TanningGoal()
    let sessionsByDay: [DayKey: [SessionRecord]]
    var state: DerivedState
    var effects: [UUID: CalibrationEffect] = [:]
    var dayDose: [DayKey: [Region: DayEntry]] = [:]
    /// The reports folded in so far, which is what the report window counts.
    var reportTimes: [Date] = []

    init(skinType: SkinType, tunables: Tunables, history: History) {
        self.skinType = skinType
        self.tunables = tunables
        sessionsByDay = history.loggedSessionsByDay()
        state = DerivedState.initial(tunables: tunables)
    }

    /// One logged session: every region decays to the moment the session ended,
    /// a new tan cycle opens if the last one has lapsed, and each region rises
    /// by the share of its target the session delivered.
    mutating func fold(_ session: SessionRecord) {
        guard let window = session.actualWindow else { return }
        let profileThen = Profile(
            skinType: skinType,
            ceiling: session.ceilingAtPlan,
            manualMultiplier: session.manualMultiplierAtPlan
        )
        let sameDay = session.day == state.today
        for region in Region.allCases {
            state.regions[region] = AdaptationModel.decayed(
                state.regions[region] ?? RegionState(), to: window.end, tunables: tunables
            )
        }
        if Region.allCases.allSatisfy({ state.regions[$0]?.cycleStart == nil }) {
            state.cycleStarts.append(window.start)
            state.cycleStarts = Array(state.cycleStarts.suffix(2))
        }
        for region in Region.allCases {
            advance(region, session: session, window: window, profile: profileThen, sameDay: sameDay)
        }
        state.today = session.day
    }

    /// One region's share of one session.
    private mutating func advance(
        _ region: Region,
        session: SessionRecord,
        window: Window,
        profile: Profile,
        sameDay: Bool
    ) {
        var regionState = state.regions[region] ?? RegionState()
        if regionState.cycleStart == nil {
            regionState.cycleStart = session.day
            regionState.rednessBoundInCycle = false
            regionState.doseInCycle = 0
            regionState.noColourNearCeiling = 0
        }
        // What a report about this session will be judged against: the factor
        // and the tan state as they stood before the session advanced them.
        regionState.factorAtLastSession = TanningGoal.adaptationFactor(
            regionState, skinType: skinType, tunables: tunables
        )
        regionState.tanStateAtLastSession = regionState.tanState
        state.regions[region] = regionState

        // The target of the time: under the ceiling and the override this
        // session was planned with, and the state as it was at that moment.
        let target = goal.target(
            for: region, profile: profile, state: state,
            now: window.start, stale: false, tunables: tunables
        )
        let dose = session.dosePerRegion[region] ?? 0
        let fraction = target.target > 0 ? dose / target.target : 0
        regionState = AdaptationModel.advanced(
            regionState, doseFraction: fraction, skinType: skinType, at: window.end, tunables: tunables
        )
        regionState.doseInCycle += dose
        regionState.doseToday = sameDay ? regionState.doseToday + dose : dose
        state.regions[region] = regionState
        record(day: session.day, region: region, dose: dose, target: target.target)
    }

    /// One skin report, and the report window it lands in.
    mutating func fold(_ report: SkinReport) {
        let (next, effect) = CalibrationEngine.apply(
            report,
            daySessions: sessionsByDay[report.day] ?? [],
            state: state,
            skinType: skinType,
            tunables: tunables
        )
        state = next
        effects[report.id] = effect
        reportTimes.append(report.reportedAt)
        // `n` is the reports of the current and the previous tan cycle (R21),
        // so the window opens at the second-most-recent cycle start.
        let opened = state.cycleStarts.suffix(2).first ?? Date.distantPast
        state.reportCount = reportTimes.filter { $0 >= opened }.count
    }

    /// One lasting-colour answer, days after the report it belongs to. It counts
    /// for every region that took at least its share of its target that day, and
    /// only builds the plateau count while that region is near saturation.
    mutating func foldLastingColour(_ report: SkinReport) {
        guard let answer = report.lastingColour else { return }
        let share = tunables.lastingColourRegionFraction
        let plateau = tunables.plateauTanState
        for region in Region.allCases {
            guard let entry = dayDose[report.day]?[region], entry.target > 0,
                  entry.dose / entry.target >= share else { continue }
            var regionState = state.regions[region] ?? RegionState()
            switch answer {
            case .no:
                if regionState.tanState >= plateau {
                    regionState.noColourNearCeiling += 1
                }
            case .yes, .aLittle:
                regionState.noColourNearCeiling = 0
            }
            state.regions[region] = regionState
        }
    }

    /// Bring the state to now: the tan has faded since the last session, and
    /// today's dose belongs to today only.
    mutating func finish(at now: Date) {
        for region in Region.allCases {
            state.regions[region] = AdaptationModel.decayed(
                state.regions[region] ?? RegionState(), to: now, tunables: tunables
            )
        }
        if let today = state.today, now >= today.end() {
            for region in Region.allCases {
                state.regions[region]?.doseToday = 0
            }
        }
        state.tunablesVersion = tunables.version
    }

    private mutating func record(day: DayKey, region: Region, dose: SED, target: SED) {
        var entry = dayDose[day]?[region] ?? DayEntry(dose: 0, target: target)
        entry.dose += dose
        entry.target = target
        dayDose[day, default: [:]][region] = entry
    }
}
