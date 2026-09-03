import Foundation

/// What one skin report did to the state. Every report has exactly one of
/// these, so the app can always say what an answer changed — including when the
/// answer changed nothing.
public enum CalibrationEffect: Sendable, Equatable {
    /// Evidence the state already agreed with.
    case none
    /// A tolerant surprise the region's tan state absorbed, and by how much it
    /// rose.
    case tanStateCredited(Region, Double)
    case multiplierMoved(from: Double, to: Double)
    /// The learned multiplier ran into its clamp, which is the app's cue to ask
    /// the user to revisit their skin type.
    case clampHit(revisitSkinType: Bool)
    case blisterCorrection(from: Double, to: Double, pauseDays: Int)
    /// Redness within an hour that had faded by evening: immediate pigment
    /// darkening, not erythema, so the report was calibrated as "normal".
    case reclassifiedAsNormal
    /// The report named a confounder, so it counted for a fraction of itself.
    case discounted
    /// Nothing was logged that day, so the report is recorded and never
    /// calibrated (D-2026-09-03-T4).
    case noDoseThatDay
}

/// The learning half of the engine (R21): one skin report against one day's
/// logged dose, moving the region's tan state and the person's one sensitivity
/// multiplier.
///
/// It is a pure function of the report, the day's sessions and the state as it
/// stood — `Replay` is what walks the history through it.
public enum CalibrationEngine {
    /// Fold one report into the state, and say what it did.
    public static func apply(
        _ report: SkinReport,
        daySessions: [SessionRecord],
        state: DerivedState,
        skinType: SkinType,
        tunables: Tunables
    ) -> (DerivedState, CalibrationEffect) {
        guard let region = evidenceRegion(report, daySessions: daySessions) else {
            return (state, .noDoseThatDay)
        }
        let doses = doseByRegion(daySessions)
        let dose = doses[region] ?? 0
        guard dose > 0 else { return (state, .noDoseThatDay) }

        let evidence = Evidence(report: report, region: region, doses: doses, dose: dose,
                                daySessions: daySessions, state: state, skinType: skinType,
                                tunables: tunables)
        var next = state
        var effect = evidence.answer == .normal
            ? tolerant(evidence, into: &next)
            : redness(evidence, into: &next)
        if evidence.reclassified { effect = .reclassifiedAsNormal }
        if let clamped = clamp(&next, tunables: tunables) {
            // A blistering report's correction is the more urgent message (the
            // pause and Module 7), so it survives the clamp; the value it
            // reports is the held one.
            if case let .blisterCorrection(from, _, pauseDays) = effect {
                effect = .blisterCorrection(from: from, to: next.multiplier, pauseDays: pauseDays)
            } else {
                effect = clamped
            }
        }
        next.totalReports += 1
        return (next, effect)
    }

    /// Which region a report is evidence about. A named region is itself; "all
    /// exposed" takes the strongest bound the answer supports — the highest-dose
    /// region when the skin stayed normal, the lowest-dose one that received any
    /// dose when it reddened (D-2026-09-03-T4). A day with no logged dose is
    /// evidence about nothing.
    public static func evidenceRegion(_ report: SkinReport, daySessions: [SessionRecord]) -> Region? {
        let doses = doseByRegion(daySessions)
        let exposed = Region.allCases.filter { (doses[$0] ?? 0) > 0 }
        guard !exposed.isEmpty else { return nil }
        switch report.region {
        case .front: return .front
        case .back: return .back
        case .headAndShoulders: return .headAndShoulders
        case .allExposed:
            let ordered = exposed.sorted { lhs, rhs in
                let left = doses[lhs] ?? 0, right = doses[rhs] ?? 0
                if left != right { return left < right }
                return index(of: lhs) < index(of: rhs)
            }
            return report.answer == .normal ? ordered.last : ordered.first
        }
    }

    /// How much one report is allowed to move the multiplier. It falls with the
    /// number of reports already folded in, never below the floor `nCap` sets,
    /// and a burn observation counts double — but no single update may ever be
    /// worth more than the whole distance (R21).
    public static func weight(n: Int, isBurn: Bool, tunables: Tunables) -> Double {
        let confidence = tunables.k
        let counted = Double(min(max(0, n), tunables.nCap))
        let burn = isBurn ? tunables.burnWeight : 1
        return min(1, burn * confidence / (counted + confidence))
    }
}

// MARK: - The evidence one report carries

private extension CalibrationEngine {
    /// Everything the update rule needs, read once so the branches below stay
    /// about the arithmetic.
    struct Evidence {
        let report: SkinReport
        let region: Region
        let doses: [Region: SED]
        let dose: SED
        let regionState: RegionState
        /// The adaptation factor in force *before* the day's session advanced
        /// it — what the report is actually evidence about.
        let factor: Double
        let baseline: SED
        /// The multiplier the session was planned with: a manual override when
        /// the user had one, the learned value otherwise.
        let multiplierUsed: Double
        let ratio: Double
        let discount: Double
        let reclassified: Bool
        let answer: SkinAnswer
        let reportCount: Int
        let tunables: Tunables

        init(
            report: SkinReport,
            region: Region,
            doses: [Region: SED],
            dose: SED,
            daySessions: [SessionRecord],
            state: DerivedState,
            skinType: SkinType,
            tunables: Tunables
        ) {
            self.report = report
            self.region = region
            self.doses = doses
            self.dose = dose
            self.tunables = tunables
            regionState = state.regions[region] ?? RegionState()
            factor = regionState.factorAtLastSession
            baseline = tunables.medBaselineSED(skinType)
            let lastOfDay = daySessions
                .sorted { ($0.actualWindow?.end ?? $0.createdAt) < ($1.actualWindow?.end ?? $1.createdAt) }
                .last
            multiplierUsed = lastOfDay?.manualMultiplierAtPlan ?? state.multiplier
            let estimate = baseline * multiplierUsed * factor
            ratio = estimate > 0 ? dose / estimate : 0
            discount = report.confounders.isEmpty ? 1 : tunables.confoundedDiscount
            reclassified = report.answer == .faintPink && report.timing == .withinHourGoneByEvening
            answer = reclassified ? .normal : report.answer
            reportCount = state.reportCount
        }
    }
}

// MARK: - The two branches

private extension CalibrationEngine {
    /// A "normal" answer is one-sided evidence: it says only that the threshold
    /// lies above what was delivered. At or below the estimate it confirms and
    /// changes nothing; above it, the excess goes to tan state first and only
    /// what saturation cannot absorb reaches the multiplier (R21).
    static func tolerant(_ evidence: Evidence, into next: inout DerivedState) -> CalibrationEffect {
        let discounted = evidence.discount < 1
        guard evidence.ratio > 1 else { return discounted ? .discounted : .none }
        let excess = evidence.discount * (evidence.ratio - 1)
        let (credited, unabsorbed) = AdaptationModel.creditTolerant(
            evidence.regionState, excess: excess, tunables: evidence.tunables
        )
        let rise = credited.tanState - evidence.regionState.tanState
        next.regions[evidence.region] = credited
        guard unabsorbed > 0 else {
            return discounted ? .discounted : .tanStateCredited(evidence.region, rise)
        }
        let used = evidence.multiplierUsed
        let implied = min(used * (1 + unabsorbed), used * evidence.ratio)
        let from = next.multiplier
        next.multiplier += weight(n: evidence.reportCount, isBurn: false, tunables: evidence.tunables)
            * (implied - from)
        return discounted ? .discounted : .multiplierMoved(from: from, to: next.multiplier)
    }

    /// A redness answer maps to an implied dose-to-threshold ratio, and the
    /// threshold it implies is divided by the adaptation factor in force before
    /// it touches the multiplier. The learned value always moves from itself,
    /// never from a manual override, so an override never becomes the thing the
    /// app has learned.
    static func redness(_ evidence: Evidence, into next: inout DerivedState) -> CalibrationEffect {
        let tunables = evidence.tunables
        let implied = evidence.dose
            / (evidence.baseline * evidence.factor * tunables.impliedRatio(evidence.answer))
        let from = next.multiplier
        let move = weight(n: evidence.reportCount, isBurn: true, tunables: tunables)
        next.multiplier += evidence.discount * move * (implied - from)
        bound(evidence, into: &next)
        next.rednessReportCount += 1
        guard evidence.answer == .blistered else {
            return .multiplierMoved(from: from, to: next.multiplier)
        }
        next.multiplier = min(next.multiplier, implied * tunables.blisterProtectiveFactor)
        return .blisterCorrection(from: from, to: next.multiplier, pauseDays: tunables.blisterPauseDays)
    }

    /// The redness bound is per region; a report on "all exposed" bounds every
    /// region that received dose that day (R14).
    static func bound(_ evidence: Evidence, into next: inout DerivedState) {
        let bounded: [Region] = evidence.report.region == .allExposed
            ? Region.allCases.filter { (evidence.doses[$0] ?? 0) > 0 }
            : [evidence.region]
        for region in bounded {
            var regionState = next.regions[region] ?? RegionState()
            regionState.rednessBoundInCycle = true
            next.regions[region] = regionState
        }
    }

    /// Hold the multiplier inside its clamp, and say so when it had to.
    static func clamp(_ next: inout DerivedState, tunables: Tunables) -> CalibrationEffect? {
        let range = tunables.multiplierClamp
        let held = min(max(next.multiplier, range.lowerBound), range.upperBound)
        guard held != next.multiplier else { return nil }
        next.multiplier = held
        return .clampHit(revisitSkinType: true)
    }
}

// MARK: - The day's dose

extension CalibrationEngine {
    /// One day's summed dose per region, after sunscreen and cover, as stored.
    /// Doses are never recomputed: the forecast is not part of the replay (R44).
    static func doseByRegion(_ daySessions: [SessionRecord]) -> [Region: SED] {
        var doses = [Region: SED]()
        for session in daySessions {
            for (region, dose) in session.dosePerRegion {
                doses[region, default: 0] += dose
            }
        }
        return doses
    }

    private static func index(of region: Region) -> Int {
        Region.allCases.firstIndex(of: region) ?? 0
    }
}
