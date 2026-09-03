import Foundation

/// Everything the engine knows about one region, as replayed from the history.
/// Never stored: the history is the record, and this is derived from it under
/// the current `Tunables` (design revision 2).
public struct RegionState: Codable, Sendable, Equatable {
    /// How tanned this region is, 0 (untanned) to 1 (saturated).
    public var tanState: Double
    /// When this region last received dose, used for the decay and the gap.
    public var lastExposure: Date?
    /// The day the current tan cycle began for this region; nil between cycles.
    public var cycleStart: DayKey?
    /// Whether a redness report has bounded this region in the current cycle.
    public var rednessBoundInCycle: Bool
    /// Consecutive "no lasting colour" answers given near saturation (R14).
    public var noColourNearCeiling: Int
    /// Dose delivered to this region today, and since the cycle began.
    public var doseToday: SED
    public var doseInCycle: SED
    /// The adaptation factor and tan state as they stood *before* the last
    /// session advanced them — what a report about that session is judged
    /// against, and what the gap notice measures the drop from.
    public var factorAtLastSession: Double
    public var tanStateAtLastSession: Double

    public init(
        tanState: Double = 0,
        lastExposure: Date? = nil,
        cycleStart: DayKey? = nil,
        rednessBoundInCycle: Bool = false,
        noColourNearCeiling: Int = 0,
        doseToday: SED = 0,
        doseInCycle: SED = 0,
        factorAtLastSession: Double = 1,
        tanStateAtLastSession: Double = 0
    ) {
        self.tanState = tanState
        self.lastExposure = lastExposure
        self.cycleStart = cycleStart
        self.rednessBoundInCycle = rednessBoundInCycle
        self.noColourNearCeiling = noColourNearCeiling
        self.doseToday = doseToday
        self.doseInCycle = doseInCycle
        self.factorAtLastSession = factorAtLastSession
        self.tanStateAtLastSession = tanStateAtLastSession
    }
}

/// The whole replayed state: one sensitivity multiplier shared by every region
/// (R8), the report counts the confidence weighting and the unlocks are made
/// of, per-region state, and the tan-cycle starts the report window needs.
///
/// `tunablesVersion` records which constant set produced it, so a state
/// replayed under different constants is recognisable as such.
public struct DerivedState: Codable, Sendable, Equatable {
    /// The learned sensitivity multiplier (R21). One number for the person.
    public var multiplier: Double
    /// Reports in the current and previous tan cycle — the `n` of the weight.
    public var reportCount: Int
    /// Every report ever, which is what the calibration and unlock counts use.
    public var totalReports: Int
    /// How many of those reported redness.
    public var rednessReportCount: Int
    public var regions: [Region: RegionState]
    /// The day the replayed `doseToday` values belong to.
    public var today: DayKey?
    /// The start of every tan cycle, oldest first; the last two are the report
    /// window.
    public var cycleStarts: [Date]
    public var tunablesVersion: String

    public init(
        multiplier: Double = 1,
        reportCount: Int = 0,
        totalReports: Int = 0,
        rednessReportCount: Int = 0,
        regions: [Region: RegionState] = [:],
        today: DayKey? = nil,
        cycleStarts: [Date] = [],
        tunablesVersion: String = ""
    ) {
        self.multiplier = multiplier
        self.reportCount = reportCount
        self.totalReports = totalReports
        self.rednessReportCount = rednessReportCount
        self.regions = regions
        self.today = today
        self.cycleStarts = cycleStarts
        self.tunablesVersion = tunablesVersion
    }

    /// A user the engine knows nothing about: multiplier 1, no reports, every
    /// region untanned and outside a cycle.
    public static func initial(tunables: Tunables) -> DerivedState {
        var regions = [Region: RegionState]()
        for region in Region.allCases {
            regions[region] = RegionState()
        }
        return DerivedState(regions: regions, tunablesVersion: tunables.version)
    }
}
