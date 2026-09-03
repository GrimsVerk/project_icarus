import Foundation

/// The sunscreen the engine prescribes for the whole window, the honesty that
/// goes with it, and the re-solve for a user who does not have that SPF (R15).
public struct SunscreenAdvice: Sendable, Equatable {
    /// The label and application the user should wear. Never thick: a
    /// prescription the user cannot realistically apply is not a prescription.
    public let prescribed: SunscreenChoice
    /// How many times longer the covered window is than the bare sub-window,
    /// and so roughly how many times the UVA load.
    public let uvaMultiple: Double
    /// When to put more on, inside the window.
    public let reapplyAt: [Date]
    /// Why a moderate label applied properly beats a high label applied thinly.
    public let whyModerateSPF: CopyKey

    public init(prescribed: SunscreenChoice, uvaMultiple: Double, reapplyAt: [Date], whyModerateSPF: CopyKey) {
        self.prescribed = prescribed
        self.uvaMultiple = uvaMultiple
        self.reapplyAt = reapplyAt
        self.whyModerateSPF = whyModerateSPF
    }
}

/// What the sunscreen question answers: nothing to do, a pair to wear, or an
/// honest "no realistic product covers this — shorten the window instead".
public enum SunscreenOutcome: Sendable, Equatable {
    case notNeeded(uvaHeavy: Bool)
    case prescribe(SunscreenAdvice)
    case nothingRealistic(requiredAttenuation: Double)

    /// The pair to wear, when there is one.
    public var prescribedChoice: SunscreenChoice? {
        switch self {
        case let .prescribe(advice): advice.prescribed
        case .notNeeded, .nothingRealistic: nil
        }
    }
}

/// The re-solve for "I don't have that SPF": what the product the user actually
/// has covers, and what they do for the rest of the window. Never more frequent
/// application in place of a higher label.
public struct AlternativePlan: Sendable, Equatable {
    /// Exactly what the user said they can manage — label and application both.
    public let with: SunscreenChoice
    /// The part of the window this product covers.
    public let coveredWindow: Window
    /// The rest of the window, to be spent in the shade.
    public let shadeMinutes: Double
    /// Head and shoulders are covered whenever the window is cut short.
    public let coverHeadAndShoulders: Bool
    /// Reapplication times, inside the covered part only.
    public let reapplyAt: [Date]
    public let copy: CopyKey

    public init(
        with: SunscreenChoice,
        coveredWindow: Window,
        shadeMinutes: Double,
        coverHeadAndShoulders: Bool,
        reapplyAt: [Date],
        copy: CopyKey
    ) {
        self.with = with
        self.coveredWindow = coveredWindow
        self.shadeMinutes = shadeMinutes
        self.coverHeadAndShoulders = coverHeadAndShoulders
        self.reapplyAt = reapplyAt
        self.copy = copy
    }
}

/// Prescribes sunscreen for the whole window, names the UVA multiple and the
/// reapplication times, and re-solves with whatever the user actually has
/// (R15, D-2026-09-03 sunscreen ruling).
///
/// Pure: no state, and every constant comes from the `Tunables` passed in, so a
/// recording copy sees exactly what an outcome read.
public enum SunscreenSolver {
    /// The sunscreen answer for a whole window whose raw dose is `rawSED`
    /// against a remaining budget of `budgetSED`.
    ///
    /// The attenuation needed is raw over budget. At or below 1 nothing is
    /// needed. Otherwise the answer is the lowest label on the ladder, applied
    /// normally, whose effective SPF covers that attenuation — thick
    /// application is never solved for, so a label above the realistic maximum
    /// is not an answer either. When no label on the ladder is enough, the
    /// honest answer is to shorten the window.
    ///
    /// The parameter list is the plan's declared signature, which the blind
    /// test author writes against; it is not ours to shorten.
    public static func outcome( // swiftlint:disable:this function_parameter_count
        rawSED: SED,
        budgetSED: SED,
        window: Window,
        bareMinutes: Double,
        uvaHeavy: Bool,
        tunables: Tunables
    ) -> SunscreenOutcome {
        let needed = attenuation(rawSED: rawSED, budgetSED: budgetSED)
        guard needed > 1 else { return .notNeeded(uvaHeavy: uvaHeavy) }

        let density = tunables.densityDefault
        let maximum = tunables.realisticMaxSPF
        let label = tunables.spfLadder.sorted().first { candidate in
            candidate <= maximum && effectiveSPF(label: candidate, density: density) >= needed
        }
        guard let label else { return .nothingRealistic(requiredAttenuation: needed) }

        return .prescribe(SunscreenAdvice(
            prescribed: SunscreenChoice(spfLabel: label, application: .normal),
            uvaMultiple: uvaMultiple(window: window, bareMinutes: bareMinutes),
            reapplyAt: reapplicationTimes(window: window, tunables: tunables),
            whyModerateSPF: .sunscreenApplicationBeatsLabel
        ))
    }

    /// The re-solve with exactly what the user said they have — the label they
    /// picked and the way they said they will apply it.
    ///
    /// If that is enough for the attenuation the window needs, they wear it for
    /// the whole window. If it is not, the answer is less time, not more
    /// frequent application: the covered part is the longest prefix of the
    /// window whose attenuated dose still fits the budget, the rest is shade,
    /// and head and shoulders are covered.
    ///
    /// The parameter list is the plan's declared signature, as above.
    public static func alternative( // swiftlint:disable:this function_parameter_count
        have: SunscreenChoice,
        rawSED: SED,
        budgetSED: SED,
        window: Window,
        curve: ForecastCurve,
        tunables: Tunables
    ) -> AlternativePlan {
        let needed = attenuation(rawSED: rawSED, budgetSED: budgetSED)
        let protection = have.effectiveSPF

        if protection >= needed {
            return AlternativePlan(
                with: have,
                coveredWindow: window,
                shadeMinutes: 0,
                coverHeadAndShoulders: false,
                reapplyAt: reapplicationTimes(window: window, tunables: tunables),
                copy: have.application == .thick ? .alternativeThickEnough : .alternativeWholeWindow
            )
        }

        // R15 and S2: "thick application of what they have if it is enough".
        // The label is what the user has; how much they put on is the one
        // thing they can still change, so a thicker layer of the same bottle
        // is offered before any minute is taken away.
        let thick = SunscreenChoice(spfLabel: have.spfLabel, application: .thick)
        if have.application != .thick, thick.effectiveSPF >= needed {
            return AlternativePlan(
                with: thick,
                coveredWindow: window,
                shadeMinutes: 0,
                coverHeadAndShoulders: false,
                reapplyAt: reapplicationTimes(window: window, tunables: tunables),
                copy: .alternativeThickEnough
            )
        }

        let covered = coveredPrefix(window: window, curve: curve, budgetSED: budgetSED, protection: protection)
        return AlternativePlan(
            with: have,
            coveredWindow: covered,
            shadeMinutes: max(0, window.minutes - covered.minutes),
            coverHeadAndShoulders: true,
            reapplyAt: reapplicationTimes(window: covered, tunables: tunables),
            copy: .alternativeShadeForRest
        )
    }

    /// Every reapplication time inside a window: one interval after the start,
    /// then every interval after that, up to but not including the end. Empty
    /// for a window no longer than one interval.
    public static func reapplicationTimes(window: Window, tunables: Tunables) -> [Date] {
        let interval = tunables.reapplicationIntervalHours * 3600
        guard interval > 0 else { return [] }
        var times: [Date] = []
        var time = window.start.addingTimeInterval(interval)
        while time < window.end {
            times.append(time)
            time = time.addingTimeInterval(interval)
        }
        return times
    }

    /// How many times the whole window's raw dose must be cut down to fit the
    /// budget. Nothing exposed needs nothing; no budget left can never be met.
    private static func attenuation(rawSED: SED, budgetSED: SED) -> Double {
        guard rawSED > 0 else { return 0 }
        guard budgetSED > 0 else { return .infinity }
        return rawSED / budgetSED
    }

    /// The protection a label really gives at an applied density: the label is
    /// measured at 2 mg/cm², and the protection falls off exponentially below
    /// that (Module 8).
    private static func effectiveSPF(label: Int, density: Double) -> Double {
        pow(Double(label), density / 2)
    }

    /// The same tanning dose spread over N times the minutes carries roughly N
    /// times the UVA. Without a bare sub-window to compare against there is no
    /// multiple to name, so the answer is 1.
    private static func uvaMultiple(window: Window, bareMinutes: Double) -> Double {
        guard bareMinutes > 0 else { return 1 }
        return window.minutes / bareMinutes
    }

    /// The longest prefix of the window whose attenuated dose still fits the
    /// budget, found by bisection on the curve's prefix integral — the dose
    /// from the start only ever grows, so the fit has a single crossing.
    private static func coveredPrefix(
        window: Window,
        curve: ForecastCurve,
        budgetSED: SED,
        protection: Double
    ) -> Window {
        guard budgetSED > 0, protection > 0 else { return Window(start: window.start, end: window.start) }
        let allowed = budgetSED * protection
        guard curve.sed(from: window.start, to: window.end) > allowed else { return window }

        var low = 0.0
        var high = window.end.timeIntervalSince(window.start)
        for _ in 0 ..< bisectionSteps {
            let middle = (low + high) / 2
            let dose = curve.sed(from: window.start, to: window.start.addingTimeInterval(middle))
            if dose <= allowed {
                low = middle
            } else {
                high = middle
            }
        }
        return Window(start: window.start, end: window.start.addingTimeInterval(low))
    }

    /// Enough halvings to place the crossing to well under a second over any
    /// window a session can span.
    private static let bisectionSteps = 60
}
