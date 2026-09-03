import Foundation

/// What the app tells the user about how their tolerance has moved (R13).
/// Both cases speak of tolerance, never of minutes, so they stay true when
/// today's window differs from the last one.
public enum EscalationNotice: Sendable, Equatable {
    /// The threshold has risen, and by how much: the factor as it stands now.
    case risen(factor: Double)
    /// A gap has undone part of the rise, and what share of it is gone.
    case dropped(fraction: Double)
}

/// What repeated "no lasting colour" near saturation means (R14). Which of the
/// two it is depends on whether the app has ever seen this region react.
public enum PlateauOutcome: Sendable, Equatable {
    case ceiling
    case underDosed
}

/// How a region's tan state moves: up with dose, down with time, and what the
/// two of them together are worth saying about.
///
/// The update is the closed form ruled in D-2026-09-03-F3 with T1's constants:
/// decay by the elapsed time, then a leaky-integrator rise. Never a day-by-day
/// loop — an event is one decay and one rise, whatever the gap before it.
public enum AdaptationModel {
    private static let secondsPerDay = 86400.0

    /// The region as it stands at `now`: the tan state faded by the elapsed
    /// time, and — when the elapsed time is longer than the gap that ends a tan
    /// cycle (R14) — the cycle closed, with its bound, its cumulative dose and
    /// its plateau count cleared.
    ///
    /// The last exposure is kept, because the gap notice measures from it.
    public static func decayed(_ state: RegionState, to now: Date, tunables: Tunables) -> RegionState {
        guard let last = state.lastExposure else { return state }
        let days = now.timeIntervalSince(last) / secondsPerDay
        guard days > 0 else { return state }
        var faded = state
        faded.tanState = state.tanState * pow(0.5, days / tunables.decayHalfLifeDays)
        if days > tunables.gapDays {
            faded.cycleStart = nil
            faded.rednessBoundInCycle = false
            faded.doseInCycle = 0
            faded.noColourNearCeiling = 0
        }
        return faded
    }

    /// The region after a session that delivered `doseFraction` of its target:
    /// a leaky-integrator step toward saturation, scaled by the band's rise
    /// multiplier. A session at the target advances every skin type and every
    /// ceiling setting equally, which is what makes the fraction the input
    /// rather than the dose (R12).
    public static func advanced(
        _ state: RegionState,
        doseFraction: Double,
        skinType: SkinType,
        at time: Date,
        tunables: Tunables
    ) -> RegionState {
        var risen = state
        // Record where the skin stood before this session: calibration divides
        // a report's evidence by the factor in force when the dose was taken.
        risen.tanStateAtLastSession = state.tanState
        risen.factorAtLastSession = 1 + tunables.adaptationGain(skinType.band) * state.tanState
        risen.lastExposure = time
        guard doseFraction.isFinite, doseFraction > 0 else { return risen }
        let multiplier = tunables.riseMultiplier(skinType.band)
        let step = 1 - exp(-doseFraction * multiplier / tunables.riseTimeConstantDays)
        risen.tanState = min(1, state.tanState + (1 - state.tanState) * step)
        return risen
    }

    /// A tolerant surprise, credited to tan state first (R21). The excess is
    /// worth `tolerantCredit` of itself as extra rise; what saturation cannot
    /// absorb comes back as `unabsorbed`, and only that raises the multiplier.
    public static func creditTolerant(
        _ state: RegionState,
        excess: Double,
        tunables: Tunables
    ) -> (RegionState, unabsorbed: Double) {
        let credit = tunables.tolerantCredit
        guard excess > 0, credit > 0 else { return (state, max(0, excess)) }
        let headroom = max(0, 1 - state.tanState)
        let wanted = credit * excess
        var risen = state
        risen.tanState = min(1, state.tanState + wanted)
        guard wanted > headroom else { return (risen, 0) }
        return (risen, excess - headroom / credit)
    }

    /// The notice this region has earned, if any. A gap long enough to matter
    /// is judged first: news that tolerance has dropped is what the user needs
    /// before they plan, and the rise is still true underneath it.
    ///
    /// The region is taken as it stands at `now` — decayed to the clock, which
    /// is what `Replay` hands out (R44). The gap is measured against the rise
    /// the factor had achieved BY the last logged session (T5): that
    /// post-session tan state is recovered by undoing the decay since the last
    /// exposure, so the share undone is `1 − 0.5^(days / halfLife)` and the
    /// notice is inclusive at exactly one half-life.
    public static func escalationNotice(
        _ state: RegionState,
        now: Date,
        skinType: SkinType,
        tunables: Tunables
    ) -> EscalationNotice? {
        let gain = tunables.adaptationGain(skinType.band)
        let fraction = tunables.escalationNoticeFraction
        let tanNow = state.tanState
        let factorNow = 1 + gain * tanNow
        let idleDays = state.lastExposure.map { now.timeIntervalSince($0) / secondsPerDay } ?? 0
        if idleDays > tunables.gapDays {
            let decay = pow(0.5, idleDays / tunables.decayHalfLifeDays)
            let tanAfterLast = decay > 0 ? min(1, tanNow / decay) : tanNow
            let achieved = gain * tanAfterLast
            let undone = gain * (tanAfterLast - tanNow)
            if achieved > 0, undone >= fraction * achieved - 1e-9 {
                return .dropped(fraction: tanAfterLast > 0 ? 1 - tanNow / tanAfterLast : 0)
            }
        }
        if factorNow - 1 >= fraction * gain - 1e-12 { return .risen(factor: factorNow) }
        return nil
    }

    /// What repeated "no lasting colour" near saturation means for this region,
    /// or nothing while the answers have not piled up. The outcome hangs on the
    /// count, never on the tan state re-read at plan time, so it does not
    /// flicker with a weekend's decay (R14).
    public static func plateauOutcome(_ state: RegionState, tunables: Tunables) -> PlateauOutcome? {
        guard state.noColourNearCeiling >= tunables.ceilingNoColourCount else { return nil }
        return state.rednessBoundInCycle ? .ceiling : .underDosed
    }
}
