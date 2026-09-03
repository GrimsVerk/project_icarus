import Foundation

/// What the engine has to say about one window. Every path out of the planner
/// is one of these — never a nil, never a crash, never a fabricated number
/// (R17).
public enum Outcome: Sendable, Equatable {
    /// A session to do: the solved plan, the sunscreen answer beside it, and
    /// which of the two is the headline (R15).
    case plan(ExposurePlan, sunscreen: SunscreenOutcome, headline: Headline)
    /// The window cannot deliver enough to be worth going out for. The
    /// shortfall is measured from the melanogenic dose, and the next viable
    /// window is a day and an hour, never a planned session.
    case tooWeak(shortfallSED: SED, nextViable: Window?)
    /// Nothing in the cached horizon reaches viability.
    case noViableWindow(days: Int, peakUVI: UVI)
    /// The window is wholly in the past.
    case windowPassed
    /// Every region's budget for today is already spent; the region named is
    /// the one that took the most.
    case budgetSpent(Region)
    /// No forecast to plan from — the one outcome that shows no number.
    case missingForecast(ForecastFailureKind?)
}

/// Why there is no forecast. The engine never fetches; the data layer says
/// which of these happened.
public enum ForecastFailureKind: String, Sendable, Equatable {
    case provider
    case malformed
    case cacheUnreadable
    case noLocation
}

/// Which answer leads the result screen (R15). The bare sub-window leads unless
/// the user has said they will stay out for the whole window and a realistic
/// sunscreen covers it; a window that cannot reach the budget is itself the
/// answer.
public enum Headline: Sendable, Equatable {
    case bareSubWindow
    case sunscreenForWholeWindow
    case wholeWindowFits
}

/// How much the forecast's age and place should be held against it (R3).
public enum StaleLevel: Sendable, Equatable {
    case fresh
    /// Old enough to name the age, not old enough to change the number.
    case headsUp(hours: Double)
    /// Old, far away, or for an unknown place: the range widens and the
    /// recommendation is trimmed, and a number is still given.
    case warn(hours: Double, farFromCache: Bool)

    /// True for the level that degrades the recommendation.
    public var reducesTarget: Bool {
        if case .warn = self {
            return true
        }
        return false
    }
}

/// Everything the result says beside the number. Each flag is a fact about this
/// recommendation; the copy keys that render them are in `DoseResult.copyKeys`.
public struct Notices: Sendable, Equatable {
    /// The limiting region's tolerance news (R13).
    public let escalation: EscalationNotice?
    /// The limiting region's plateau outcome, or the first region that has one
    /// (R14).
    public let plateau: PlateauOutcome?
    /// True when a plateau outcome scaled the targets down to the maintenance
    /// dose before the session was solved.
    public let maintenanceApplied: Bool
    public let uvaHeavy: Bool
    public let stale: StaleLevel
    /// Types I and II only: the margin between a tanning dose and a burn is
    /// thin (R43).
    public let thinMargin: Bool
    /// The number is at the conservative scale whatever the selector says (R7).
    public let conservativeForced: Bool
    /// Types I and II before the calibration count: the first sessions are
    /// deliberately below the dose that reliably tans fair skin.
    public let fairSkinPreCalibration: Bool
    /// The aggressive scale was selected and not yet unlocked.
    public let aggressiveRefused: Bool
    public let cloudCaveat: Bool

    public init(
        escalation: EscalationNotice? = nil,
        plateau: PlateauOutcome? = nil,
        maintenanceApplied: Bool = false,
        uvaHeavy: Bool = false,
        stale: StaleLevel = .fresh,
        thinMargin: Bool = false,
        conservativeForced: Bool = false,
        fairSkinPreCalibration: Bool = false,
        aggressiveRefused: Bool = false,
        cloudCaveat: Bool = false
    ) {
        self.escalation = escalation
        self.plateau = plateau
        self.maintenanceApplied = maintenanceApplied
        self.uvaHeavy = uvaHeavy
        self.stale = stale
        self.thinMargin = thinMargin
        self.conservativeForced = conservativeForced
        self.fairSkinPreCalibration = fairSkinPreCalibration
        self.aggressiveRefused = aggressiveRefused
        self.cloudCaveat = cloudCaveat
    }
}

/// One recommendation, whole: what to do, the budgets it was solved against,
/// what the screen says beside it, every number with its provenance, and the
/// copy keys in display order. The engine renders no words (D-2026-09-03-F7).
public struct DoseResult: Sendable, Equatable {
    public let outcome: Outcome
    /// The per-region budgets the outcome was solved against, after any
    /// maintenance scaling. Empty when there was no forecast to solve from.
    public let targets: [Region: RegionTarget]
    public let notices: Notices
    /// Every number the screen shows, each carrying the constants it read
    /// (R30). Their union is exactly what a recording `Tunables` observes.
    public let figures: [Figure]
    /// Every line the outcome and the notices imply, in display order.
    public let copyKeys: [CopyKey]
    /// Dose since each region's tan cycle began — what the escalation message
    /// shows beside itself (R13).
    public let cycleDose: [Region: SED]
    /// The region the whole window pushes hardest against its remaining budget:
    /// the region overshoot and the sunscreen are judged on.
    public let attenuationRegion: Region?
    /// What the whole window would deliver, per region — what a
    /// stay-whole-window log is credited with.
    public let wholeWindowRaw: [Region: SED]

    public init(
        outcome: Outcome,
        targets: [Region: RegionTarget] = [:],
        notices: Notices = Notices(),
        figures: [Figure] = [],
        copyKeys: [CopyKey] = [],
        cycleDose: [Region: SED] = [:],
        attenuationRegion: Region? = nil,
        wholeWindowRaw: [Region: SED] = [:]
    ) {
        self.outcome = outcome
        self.targets = targets
        self.notices = notices
        self.figures = figures
        self.copyKeys = copyKeys
        self.cycleDose = cycleDose
        self.attenuationRegion = attenuationRegion
        self.wholeWindowRaw = wholeWindowRaw
    }
}
