import Foundation

/// Which of the two thresholds set the target: the dose that tans, or the dose
/// that burns. For types I–II they are the same number, so the burn line binds
/// and the user rides it (R6).
public enum BoundBy: String, Codable, Sendable {
    case melanogenic
    case burnLine
}

/// One region's budget for today, with everything the result screen has to be
/// able to say about it: the two thresholds, the adaptation factor that moved
/// them, the number itself, what bound it, what is left after today's earlier
/// sessions, and the uncertainty range around it (R6, R7, R19).
public struct RegionTarget: Sendable, Equatable {
    public let region: Region
    /// `MED_baseline × multiplier × adaptationFactor` — the burn line (R5).
    public let medPersonal: SED
    /// `medPersonal × melanogenicFraction(band)` — the dose that tans.
    public let melanogenic: SED
    /// `1 + gain(band) × tanState`. The UI must be able to show this (R22).
    public let adaptationFactor: Double
    public let target: SED
    public let boundBy: BoundBy
    /// The ceiling scale actually used, which is not always the selected one.
    public let scaleUsed: Double
    /// `target − doseToday`, never negative.
    public let remaining: SED
    /// The uncertainty in the threshold, centred on the target. Its upper edge
    /// is clipped at `medPersonal`: the app never draws a range past the line.
    public let range: ClosedRange<SED>
    public let rangeClipped: Bool

    public init(
        region: Region,
        medPersonal: SED,
        melanogenic: SED,
        adaptationFactor: Double,
        target: SED,
        boundBy: BoundBy,
        scaleUsed: Double,
        remaining: SED,
        range: ClosedRange<SED>,
        rangeClipped: Bool
    ) {
        self.region = region
        self.medPersonal = medPersonal
        self.melanogenic = melanogenic
        self.adaptationFactor = adaptationFactor
        self.target = target
        self.boundBy = boundBy
        self.scaleUsed = scaleUsed
        self.remaining = remaining
        self.range = range
        self.rangeClipped = rangeClipped
    }

    /// The same target scaled — the maintenance dose (R14). Today's dose is
    /// recovered from `target − remaining`, so what is left shrinks with the
    /// target rather than staying where it was.
    public func scaled(by factor: Double) -> RegionTarget {
        let spentToday = max(0, target - remaining)
        let scaledTarget = target * factor
        return RegionTarget(
            region: region,
            medPersonal: medPersonal,
            melanogenic: melanogenic,
            adaptationFactor: adaptationFactor,
            target: scaledTarget,
            boundBy: boundBy,
            scaleUsed: scaleUsed,
            remaining: max(0, scaledTarget - spentToday),
            range: range,
            rangeClipped: rangeClipped
        )
    }
}

/// What the user is trying to get out of the sun. Tanning is the only goal
/// today; the vitamin D goal for darker skin slots in here without
/// reorganising anything (M8, design decision 26).
public protocol TargetGoal: Sendable {
    // The goal seam takes six arguments because the plan's contract says so.
    // swiftlint:disable function_parameter_count
    func target(
        for region: Region,
        profile: Profile,
        state: DerivedState,
        now: Date,
        stale: Bool,
        tunables: Tunables
    ) -> RegionTarget
    // swiftlint:enable function_parameter_count

    /// The line that explains, on the result, what this goal is aiming at.
    var copyKey: CopyKey { get }
}

/// The tanning goal: plan at a scale of whichever threshold binds, never past
/// the burn line, shorter until the app has learned the skin, and shorter
/// again when the forecast is old.
public struct TanningGoal: TargetGoal {
    public init() {}

    public var copyKey: CopyKey {
        .boundByMelanogenic
    }

    // swiftlint:disable function_parameter_count
    public func target(
        for region: Region,
        profile: Profile,
        state: DerivedState,
        now _: Date,
        stale: Bool,
        tunables: Tunables
    ) -> RegionTarget {
        let regionState = state.regions[region] ?? RegionState()
        let factor = Self.adaptationFactor(regionState, skinType: profile.skinType, tunables: tunables)
        let multiplier = profile.manualMultiplier ?? state.multiplier
        let medPersonal = tunables.medBaselineSED(profile.skinType) * multiplier * factor
        let melanogenic = medPersonal * tunables.melanogenicFraction(profile.skinType.band)
        let scale = Self.effectiveScale(profile: profile, state: state, tunables: tunables)
        let reduction = stale ? 1 - tunables.staleReduction : 1
        let target = min(melanogenic, medPersonal) * scale.scale * reduction
        let (lower, upper) = Self.halfWidths(state: state, stale: stale, tunables: tunables)
        let rawUpper = target * (1 + upper)
        return RegionTarget(
            region: region,
            medPersonal: medPersonal,
            melanogenic: melanogenic,
            adaptationFactor: factor,
            target: target,
            boundBy: melanogenic < medPersonal ? .melanogenic : .burnLine,
            scaleUsed: scale.scale,
            remaining: max(0, target - regionState.doseToday),
            range: target * (1 - lower) ... min(rawUpper, medPersonal),
            rangeClipped: rawUpper > medPersonal
        )
    }

    // swiftlint:enable function_parameter_count

    // swiftlint:disable large_tuple
    /// The scale actually applied, and why it is not the selected one: the
    /// number sits at the conservative scale until the app has seen
    /// `calibrationReports` reports (R7), and the aggressive scale unlocks only
    /// after `aggressiveUnlockReports` reports with at least one redness report
    /// in the current cycle. A refused aggressive falls back to standard, not
    /// to conservative — refusing is not punishing.
    public static func effectiveScale(
        profile: Profile,
        state: DerivedState,
        tunables: Tunables
    ) -> (scale: Double, conservativeForced: Bool, aggressiveRefused: Bool) {
        let forced = state.totalReports < tunables.calibrationReports
        let unlocked = state.totalReports >= tunables.aggressiveUnlockReports
            && state.regions.values.contains { $0.rednessBoundInCycle }
        let refused = profile.ceiling == .aggressive && !unlocked
        let applied: Ceiling = forced ? .conservative : (refused ? .standard : profile.ceiling)
        return (tunables.ceilingScale(applied), forced, refused)
    }

    // swiftlint:enable large_tuple

    /// `1 + gain(band) × tanState` (R12). All of the exposure history's effect
    /// on the threshold lives here, so it never compounds with the melanogenic
    /// fraction.
    public static func adaptationFactor(
        _ region: RegionState,
        skinType: SkinType,
        tunables: Tunables
    ) -> Double {
        1 + tunables.adaptationGain(skinType.band) * region.tanState
    }

    /// The half-widths of the range, below and above the target. The lower edge
    /// narrows with any report; the upper edge narrows only with redness
    /// reports, because only redness bounds the threshold from above (R7). A
    /// stale forecast widens both.
    private static func halfWidths(
        state: DerivedState,
        stale: Bool,
        tunables: Tunables
    ) -> (lower: Double, upper: Double) {
        let widen = stale ? tunables.staleRangeWiden : 1
        let atZero = tunables.uncertaintyBandAtZero
        let confidence = tunables.k
        return (
            widen * atZero / (1 + Double(state.totalReports) / confidence),
            widen * atZero / (1 + Double(state.rednessReportCount) / confidence)
        )
    }
}
