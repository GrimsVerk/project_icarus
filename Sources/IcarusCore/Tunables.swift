import Foundation

/// Where a number came from. A `citation` points at a source the project can
/// show; an `assumption` is a number the project chose, and any figure computed
/// from one is labelled an estimate in the UI (R30).
public enum Basis: Sendable, Equatable {
    case citation(String)
    case assumption(String)
}

/// Every constant the engine uses, in one place, each one readable only through
/// an accessor that reports its key. Give a `Tunables` a sink with
/// `recording(_:)` and it behaves identically while telling you exactly which
/// constants an outcome read — that recording is what per-figure provenance is
/// built from.
///
/// Keys are the accessor name, or `"<table>.<band|case>"` for the tables that
/// vary by skin type, band, ceiling or answer.
public struct Tunables: Sendable {
    /// The shipped set of constants.
    public static let current = Tunables(version: "2026-09-03.1", storage: Storage(), sink: nil)

    /// Identifies the constant set a replayed state was derived under.
    public let version: String

    private let storage: Storage
    private let sink: (@Sendable (String) -> Void)?

    /// The same constants, with every read reported to `sink`.
    public func recording(_ sink: @escaping @Sendable (String) -> Void) -> Tunables {
        Tunables(version: version, storage: storage, sink: sink)
    }

    fileprivate func read<T>(_ key: String, _ value: T) -> T {
        sink?(key)
        return value
    }

    /// The stored numbers. One basis per number in `provenance`, under the same
    /// key the accessor reports.
    fileprivate struct Storage: Sendable {
        /// dose
        let uviMinutesPerSED = 66.7
        // target
        let calibrationReports = 3
        let aggressiveUnlockReports = 5
        let uncertaintyBandAtZero = 0.30
        // posture
        let frontBackFraction = 0.5
        let shoulderFraction = 0.5
        let sideDifferenceForTwoFigures = 0.15
        // adaptation
        let riseTimeConstantDays = 7.2
        let decayHalfLifeDays = 21.0
        let plateauTanState = 0.75
        let tolerantCredit = 0.5
        let escalationNoticeFraction = 0.5
        let gapDays = 14.0
        let ceilingNoColourCount = 3
        let maintenanceFraction = 0.7
        let lastingColourRegionFraction = 0.5
        // calibration
        let reporterBandEdges = [0.95, 1.15, 2.0, 4.0]
        let k = 2.5
        let nCap = 20
        let burnWeight = 2.0
        let multiplierClamp = 0.5 ... 1.8
        let confoundedDiscount = 0.25
        let blisterProtectiveFactor = 0.8
        let blisterPauseDays = 4
        // sunscreen
        let densityDefault = 1.0
        let spfLadder = [15, 20, 30, 50]
        let realisticMaxSPF = 50
        let reapplicationIntervalHours = 2.0
        // staleness, fetch and horizon
        let staleHeadsUpHours = 3.0
        let staleWarnHours = 6.0
        let staleRangeWiden = 1.5
        let staleReduction = 0.05
        let staleDistanceKm = 25.0
        let fetchMinIntervalHours = 1.0
        let fetchMoveKm = 10.0
        let forecastHorizonDays = 10
        let viabilityFraction = 0.5
        let uvaHeavyHoursFromNoon = 3.0
        // prompts
        let skinCheckDelayHours = 20.0
        let lastingColourDelayDays = 4.0
        let inAppSkinCheckWindowHours = 12.0 ... 72.0
        let inAppLastingColourWindowDays = 3.0 ... 10.0

        func medBaselineSED(_ type: SkinType) -> SED {
            switch type {
            case .i: 2.0
            case .ii: 2.5
            case .iii: 3.0
            case .iv: 4.5
            case .v: 6.0
            case .vi: 10.0
            }
        }

        func melanogenicFraction(_ band: SkinBand) -> Double {
            switch band {
            case .fair: 1.0
            case .medium: 0.95
            case .dark: 0.75
            }
        }

        func ceilingScale(_ ceiling: Ceiling) -> Double {
            switch ceiling {
            case .conservative: 0.75
            case .standard: 0.90
            case .aggressive: 1.0
            }
        }

        func riseMultiplier(_ band: SkinBand) -> Double {
            switch band {
            case .fair, .medium: 1.0
            case .dark: 1.5
            }
        }

        func adaptationGain(_ band: SkinBand) -> Double {
            switch band {
            case .fair, .medium: 1.25
            case .dark: 2.0
            }
        }

        func impliedRatio(_ answer: SkinAnswer) -> Double {
            switch answer {
            case .normal: 1.0
            case .faintPink: 1.0
            case .clearlyPink: 1.5
            case .redSore: 2.5
            case .blistered: 4.0
            }
        }
    }
}

// MARK: - Dose and target

public extension Tunables {
    /// UVI·minutes per SED. 1 SED = 100 J/m²; 1 UVI = 25 mW/m².
    var uviMinutesPerSED: Double {
        read("uviMinutesPerSED", storage.uviMinutesPerSED)
    }

    /// The unadapted minimal erythemal dose for a skin type, in SED.
    func medBaselineSED(_ type: SkinType) -> SED {
        read("medBaselineSED.\(type.keyName)", storage.medBaselineSED(type))
    }

    /// The fraction of MED at which useful melanogenesis is reached.
    func melanogenicFraction(_ band: SkinBand) -> Double {
        read("melanogenicFraction.\(band.rawValue)", storage.melanogenicFraction(band))
    }

    /// How close to the binding threshold the selector plans.
    func ceilingScale(_ ceiling: Ceiling) -> Double {
        read("ceilingScale.\(ceiling.rawValue)", storage.ceilingScale(ceiling))
    }

    /// Skin reports needed before the selected ceiling is honoured, and before
    /// the aggressive ceiling unlocks.
    var calibrationReports: Int {
        read("calibrationReports", storage.calibrationReports)
    }

    var aggressiveUnlockReports: Int {
        read("aggressiveUnlockReports", storage.aggressiveUnlockReports)
    }

    /// Half-width of the uncertainty band before any report.
    var uncertaintyBandAtZero: Double {
        read("uncertaintyBandAtZero", storage.uncertaintyBandAtZero)
    }
}

// MARK: - Posture and adaptation

public extension Tunables {
    /// Share of a lying session's time each torso side gets, and the share of
    /// the face-down dose that head and shoulders are credited with.
    var frontBackFraction: Double {
        read("frontBackFraction", storage.frontBackFraction)
    }

    var shoulderFraction: Double {
        read("shoulderFraction", storage.shoulderFraction)
    }

    /// Relative difference between the two sides above which both are shown.
    var sideDifferenceForTwoFigures: Double {
        read("sideDifferenceForTwoFigures", storage.sideDifferenceForTwoFigures)
    }

    /// Leaky-integrator time constant of the tan-state rise, in days.
    var riseTimeConstantDays: Double {
        read("riseTimeConstantDays", storage.riseTimeConstantDays)
    }

    /// Band multiplier on the rise.
    func riseMultiplier(_ band: SkinBand) -> Double {
        read("riseMultiplier.\(band.rawValue)", storage.riseMultiplier(band))
    }

    /// Half-life of the tan-state decay, in days.
    var decayHalfLifeDays: Double {
        read("decayHalfLifeDays", storage.decayHalfLifeDays)
    }

    /// Maximum rise of the adaptation factor at full tan state.
    func adaptationGain(_ band: SkinBand) -> Double {
        read("adaptationGain.\(band.rawValue)", storage.adaptationGain(band))
    }

    /// Tan state at or above which the plateau outcomes can be reached.
    var plateauTanState: Double {
        read("plateauTanState", storage.plateauTanState)
    }

    /// Share of a tolerant surprise credited to tan state before the multiplier.
    var tolerantCredit: Double {
        read("tolerantCredit", storage.tolerantCredit)
    }

    /// Fraction of the available rise at which the escalation notices fire.
    var escalationNoticeFraction: Double {
        read("escalationNoticeFraction", storage.escalationNoticeFraction)
    }

    /// A gap longer than this many days ends the tan cycle (R14).
    var gapDays: Double {
        read("gapDays", storage.gapDays)
    }

    /// Consecutive "no lasting colour" answers near the ceiling before the
    /// plateau outcome is reported, and what the target drops to when it is.
    var ceilingNoColourCount: Int {
        read("ceilingNoColourCount", storage.ceilingNoColourCount)
    }

    var maintenanceFraction: Double {
        read("maintenanceFraction", storage.maintenanceFraction)
    }

    /// Share of a region's target a session must have delivered for a
    /// lasting-colour answer to count for that region.
    var lastingColourRegionFraction: Double {
        read("lastingColourRegionFraction", storage.lastingColourRegionFraction)
    }
}

// MARK: - Calibration

public extension Tunables {
    /// The dose-over-estimate ratio a redness answer implies.
    func impliedRatio(_ answer: SkinAnswer) -> Double {
        read("impliedRatio.\(answer.rawValue)", storage.impliedRatio(answer))
    }

    /// Band edges of the inverse mapping, used by the simulated reporter.
    var reporterBandEdges: [Double] {
        read("reporterBandEdges", storage.reporterBandEdges)
    }

    /// The answer a truthful reporter gives for a dose-over-threshold ratio:
    /// the first edge strictly greater than the ratio names the answer, and a
    /// ratio at or past the last edge blisters.
    func reporterAnswer(ratio: Double) -> SkinAnswer {
        let answers: [SkinAnswer] = [.normal, .faintPink, .clearlyPink, .redSore]
        for (index, edge) in reporterBandEdges.enumerated() where edge > ratio {
            return answers[min(index, answers.count - 1)]
        }
        return .blistered
    }

    /// How fast the learned multiplier moves, how far it may go, and how much a
    /// burn, a confounded report or a blister count for.
    /// Confidence half-life of the learned multiplier, in reports.
    var k: Double {
        read("k", storage.k)
    }

    var nCap: Int {
        read("nCap", storage.nCap)
    }

    var burnWeight: Double {
        read("burnWeight", storage.burnWeight)
    }

    var multiplierClamp: ClosedRange<Double> {
        read("multiplierClamp", storage.multiplierClamp)
    }

    var confoundedDiscount: Double {
        read("confoundedDiscount", storage.confoundedDiscount)
    }

    var blisterProtectiveFactor: Double {
        read("blisterProtectiveFactor", storage.blisterProtectiveFactor)
    }

    var blisterPauseDays: Int {
        read("blisterPauseDays", storage.blisterPauseDays)
    }
}

// MARK: - Sunscreen, staleness and prompts

public extension Tunables {
    /// Applied density assumed of a real user, in mg/cm² — what people put on,
    /// not what the label was measured at.
    var densityDefault: Double {
        read("densityDefault", storage.densityDefault)
    }

    /// Labels the engine is willing to prescribe, lowest first.
    var spfLadder: [Int] {
        read("spfLadder", storage.spfLadder)
    }

    /// The highest label a user can realistically apply as directed.
    var realisticMaxSPF: Int {
        read("realisticMaxSPF", storage.realisticMaxSPF)
    }

    var reapplicationIntervalHours: Double {
        read("reapplicationIntervalHours", storage.reapplicationIntervalHours)
    }

    // Staleness: a forecast this old degrades the recommendation, never refuses it.
    var staleHeadsUpHours: Double {
        read("staleHeadsUpHours", storage.staleHeadsUpHours)
    }

    var staleWarnHours: Double {
        read("staleWarnHours", storage.staleWarnHours)
    }

    var staleRangeWiden: Double {
        read("staleRangeWiden", storage.staleRangeWiden)
    }

    var staleReduction: Double {
        read("staleReduction", storage.staleReduction)
    }

    var staleDistanceKm: Double {
        read("staleDistanceKm", storage.staleDistanceKm)
    }

    /// Fetching and how far ahead the engine may look.
    var fetchMinIntervalHours: Double {
        read("fetchMinIntervalHours", storage.fetchMinIntervalHours)
    }

    var fetchMoveKm: Double {
        read("fetchMoveKm", storage.fetchMoveKm)
    }

    var forecastHorizonDays: Int {
        read("forecastHorizonDays", storage.forecastHorizonDays)
    }

    /// Share of the target a window must be able to deliver to be worth going out for.
    var viabilityFraction: Double {
        read("viabilityFraction", storage.viabilityFraction)
    }

    /// Hours from solar noon past which the dose is called UVA-heavy.
    var uvaHeavyHoursFromNoon: Double {
        read("uvaHeavyHoursFromNoon", storage.uvaHeavyHoursFromNoon)
    }

    /// When the app asks about the skin, and how long each answer stays offered.
    var skinCheckDelayHours: Double {
        read("skinCheckDelayHours", storage.skinCheckDelayHours)
    }

    var lastingColourDelayDays: Double {
        read("lastingColourDelayDays", storage.lastingColourDelayDays)
    }

    var inAppSkinCheckWindowHours: ClosedRange<Double> {
        read("inAppSkinCheckWindowHours", storage.inAppSkinCheckWindowHours)
    }

    var inAppLastingColourWindowDays: ClosedRange<Double> {
        read("inAppLastingColourWindowDays", storage.inAppLastingColourWindowDays)
    }
}

// MARK: - Provenance

public extension Tunables {
    /// One entry per stored number, under exactly the key its accessor reports.
    static let provenance: [String: Basis] = makeProvenance()

    /// The keys whose basis is an assumption. A figure that read one of these
    /// is an estimate.
    static var assumptionKeys: Set<String> {
        Set(provenance.compactMap { pair -> String? in
            if case .assumption = pair.value {
                return pair.key
            }
            return nil
        })
    }
}

private extension Tunables {
    static let scalarKeys = [
        "uviMinutesPerSED", "calibrationReports", "aggressiveUnlockReports", "uncertaintyBandAtZero",
        "frontBackFraction", "shoulderFraction", "sideDifferenceForTwoFigures",
        "riseTimeConstantDays", "decayHalfLifeDays", "plateauTanState", "tolerantCredit",
        "escalationNoticeFraction", "gapDays", "ceilingNoColourCount", "maintenanceFraction",
        "lastingColourRegionFraction", "reporterBandEdges", "k", "nCap", "burnWeight",
        "multiplierClamp", "confoundedDiscount", "blisterProtectiveFactor", "blisterPauseDays",
        "densityDefault", "spfLadder", "realisticMaxSPF", "reapplicationIntervalHours",
        "staleHeadsUpHours", "staleWarnHours", "staleRangeWiden", "staleReduction", "staleDistanceKm",
        "fetchMinIntervalHours", "fetchMoveKm", "forecastHorizonDays", "viabilityFraction",
        "uvaHeavyHoursFromNoon", "skinCheckDelayHours", "lastingColourDelayDays",
        "inAppSkinCheckWindowHours", "inAppLastingColourWindowDays",
    ]

    static var allKeys: [String] {
        scalarKeys
            + SkinType.allCases.map { "medBaselineSED.\($0.keyName)" }
            + SkinBand.allCases.flatMap {
                ["melanogenicFraction.\($0.rawValue)", "riseMultiplier.\($0.rawValue)",
                 "adaptationGain.\($0.rawValue)"]
            }
            + Ceiling.allCases.map { "ceilingScale.\($0.rawValue)" }
            + SkinAnswer.allCases.map { "impliedRatio.\($0.rawValue)" }
    }

    static func makeProvenance() -> [String: Basis] {
        var basis = [String: Basis]()
        // Everything the design or the build prompt fixed outright.
        for key in allKeys {
            basis[key] = .citation("docs/DESIGN.md §5 (owner ruling)")
        }
        let module4 = Basis.citation("Learn Module 4 — UV dose, SED and the erythemal weighting")
        basis["uviMinutesPerSED"] = module4
        basis["uncertaintyBandAtZero"] = module4
        basis["densityDefault"] = .citation("Learn Module 8 — sunscreen is measured at 2 mg/cm²")
        for type in SkinType.allCases {
            basis["medBaselineSED.\(type.keyName)"] =
                .citation("BUILD_PROMPT §4.3; the addendum's 3.5 / 5.0 are NOT used")
        }
        basis["melanogenicFraction.fair"] =
            .citation("Pathak & Fanselow 1983 (solar spectrum); Wulf et al. 2010 "
                + "(solar simulator, 1.5–1.9) NOT used — outdoor app")
        for band in [SkinBand.medium, .dark] {
            basis["melanogenicFraction.\(band.rawValue)"] =
                .assumption("docs/MELANOGENIC_THRESHOLDS.md — no outdoor solar figure for this band")
        }
        for band in [SkinBand.fair, .medium] {
            basis["riseMultiplier.\(band.rawValue)"] = .citation("Learn Module 6 — how a tan builds")
            basis["adaptationGain.\(band.rawValue)"] =
                .citation("Learn Modules 5 and 6 — a full tan is worth about SPF 2–3")
        }
        basis["riseMultiplier.dark"] = .assumption("darker skin tans faster; no measured figure")
        basis["adaptationGain.dark"] = .assumption("darker skin gains more protection; no measured figure")
        basis["frontBackFraction"] = .assumption("geometry: a turning body faces the sun half the time")
        basis["shoulderFraction"] = .assumption("geometry: shoulders take about half the face-down dose")
        basis["riseTimeConstantDays"] =
            .assumption("D-2026-09-03-T1 — solved with the decay so 21 daily sessions reach 0.80 (fair)")
        basis["decayHalfLifeDays"] =
            .assumption("D-2026-09-03-T1 — Module 6 gives a 4–8 week fade; the fast end errs shorter")
        basis["plateauTanState"] =
            .assumption("D-2026-09-03-T1 — below the five-a-week peak and the daily saturation")
        basis["tolerantCredit"] = .assumption("how much of a tolerant surprise is adaptation, not sensitivity")
        basis["uvaHeavyHoursFromNoon"] = .assumption("no threshold in the sources; three hours is the shape")
        for answer in SkinAnswer.allCases {
            basis["impliedRatio.\(answer.rawValue)"] =
                .assumption("BUILD_PROMPT §5.3 shape — the ladder is judgement, not measurement")
        }
        return basis
    }
}

private extension SkinType {
    /// The case name, which is the roman numeral: "i", "ii", … "vi".
    var keyName: String {
        String(describing: self)
    }
}
