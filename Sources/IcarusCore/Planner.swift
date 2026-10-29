// The planner is one file by the plan's file list: composing the four models
// into a single typed result, with the provenance bookkeeping that makes the
// figures honest, is one contract.

import Foundation

/// Everything one recommendation is computed from: the forecast (or why there
/// isn't one), where the device is, the clock, the window and how it will be
/// spent, the user, and the state replayed from their history.
///
/// The engine reads no clock, no forecast and no location of its own; all three
/// arrive here.
public struct PlanRequest: Sendable {
    public let curve: ForecastCurve?
    /// Why the curve is missing. Only meaningful when `curve` is nil.
    public let forecastFailure: ForecastFailureKind?
    /// Where the device is now, if it knows — compared against the place the
    /// forecast is for (R3).
    public let deviceLocation: Coordinate?
    public let now: Date
    public let window: Window
    public let posture: Posture
    public let firstSide: Side
    public let coverHeadAndShoulders: Bool
    public let intent: Intent
    public let profile: Profile
    public let state: DerivedState
    /// What the user is trying to get out of the sun. Tanning today; the seam
    /// is here so the vitamin D goal slots in without reorganising anything.
    public let goal: any TargetGoal

    public init(
        curve: ForecastCurve?,
        forecastFailure: ForecastFailureKind? = nil,
        deviceLocation: Coordinate? = nil,
        now: Date,
        window: Window,
        posture: Posture,
        firstSide: Side = .faceUp,
        coverHeadAndShoulders: Bool = false,
        intent: Intent,
        profile: Profile,
        state: DerivedState,
        goal: any TargetGoal = TanningGoal()
    ) {
        self.curve = curve
        self.forecastFailure = forecastFailure
        self.deviceLocation = deviceLocation
        self.now = now
        self.window = window
        self.posture = posture
        self.firstSide = firstSide
        self.coverHeadAndShoulders = coverHeadAndShoulders
        self.intent = intent
        self.profile = profile
        self.state = state
        self.goal = goal
    }
}

/// The one entry point of the engine: a request in, a `DoseResult` out.
///
/// Everything it needs it composes from the models below it — the dose
/// arithmetic, the targets, the exposure solve, the sunscreen answer and the
/// adaptation notices — and it never renders a word. Every constant it uses is
/// read through the `Tunables` it was given, so a recording copy observes
/// exactly the keys the result's figures declare.
public enum Planner {
    /// The recommendation for one window.
    ///
    /// The order is fixed and it matters: staleness and the plateau are settled
    /// first because both move the targets, the targets are solved on before
    /// anything looks at the window, and the sunscreen is judged against what
    /// is left of the budget after any maintenance scaling.
    public static func plan(_ request: PlanRequest, tunables: Tunables) -> DoseResult {
        guard let curve = request.curve else { return noForecast(request) }
        var context = Context(request: request, curve: curve, tunables: tunables)
        context.prepare()
        if context.everyBudgetSpent {
            return context.finish(.budgetSpent(context.mostSpentRegion))
        }
        guard let window = DoseCalculator.clip(request.window, toStartNoEarlierThan: request.now) else {
            return context.finish(.windowPassed)
        }
        context.observe(window)
        if let weak = context.weakWindowOutcome() {
            return context.finish(weak)
        }
        guard let solved = context.solve() else {
            return context.finish(.budgetSpent(context.mostSpentRegion))
        }
        let sunscreen = context.sunscreenOutcome(for: solved)
        let headline = context.headline(solved, sunscreen: sunscreen)
        return context.finish(.plan(solved, sunscreen: sunscreen, headline: headline), plan: solved)
    }

    /// How much the forecast's age and place should be held against it (R3):
    /// nothing under the heads-up hours, the age alone under the warning hours,
    /// and a warning past them — or at any age when the device is further from
    /// the forecast's place than the tunable distance, or does not know where
    /// it is.
    ///
    /// With no forecast at all there is nothing to age, and the answer is the
    /// warning level with no hours: the caller is about to say so outright.
    public static func staleLevel(
        curve: ForecastCurve?,
        now: Date,
        deviceLocation: Coordinate?,
        tunables: Tunables
    ) -> StaleLevel {
        guard let curve else { return .warn(hours: 0, farFromCache: false) }
        let headsUp = tunables.staleHeadsUpHours
        let warn = tunables.staleWarnHours
        let limit = tunables.staleDistanceKm
        let hours = max(0, now.timeIntervalSince(curve.fetchedAt) / 3600)
        let far = deviceLocation.map { curve.location.distanceKm(to: $0) > limit } ?? false
        if hours + tolerance >= warn || far || deviceLocation == nil {
            return .warn(hours: hours, farFromCache: far)
        }
        if hours + tolerance >= headsUp {
            return .headsUp(hours: hours)
        }
        return .fresh
    }

    /// A number this small is a rounding artefact, never a real difference.
    fileprivate static let tolerance = 1e-9

    /// The result for a request with no forecast: the one outcome that shows no
    /// number at all (R3). Nothing is computed, so no constant is read and no
    /// figure claims one — the only notice is the one that follows from the
    /// skin type alone.
    private static func noForecast(_ request: PlanRequest) -> DoseResult {
        let thin = request.profile.skinType.band == .fair
        let kind = request.forecastFailure
        return DoseResult(
            outcome: .missingForecast(kind),
            notices: Notices(stale: .warn(hours: 0, farFromCache: false), thinMargin: thin),
            copyKeys: [kind == .noLocation ? .missingForecastNoLocation : .missingForecast]
                + (thin ? [CopyKey.thinMargin] : [])
        )
    }
}

// MARK: - Recording what was read

/// A set of keys collected from a recording `Tunables`. The sink is
/// `@Sendable`, so the collector is a reference type with a lock; the planner
/// itself is single-threaded.
private final class KeyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var keys = Set<String>()

    func add(_ key: String) {
        lock.lock()
        keys.insert(key)
        lock.unlock()
    }

    var recorded: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return keys
    }
}

private extension Planner {
    /// Runs `body` once through a copy of `tunables` that reports every read
    /// both to the caller's own sink and to a local one, so the keys a figure
    /// depended on are known without computing anything twice (S14).
    static func tracked<T>(_ tunables: Tunables, _ body: (Tunables) -> T) -> (value: T, reads: Set<String>) {
        let box = KeyBox()
        let value = body(tunables.alsoRecording { box.add($0) })
        return (value, box.recorded)
    }
}

/// The constants read while computing each part of the result, kept apart so
/// every figure can declare exactly what its own number depended on (R30).
private struct Reads {
    /// Staleness, the plateau, the targets and the scale — everything the
    /// budgets are made of.
    var target = Set<String>()
    /// The exposure solve: the posture geometry and the two-figure threshold.
    var solve = Set<String>()
    /// The viability bar, the next-viable search and the horizon.
    var viability = Set<String>()
    /// The sunscreen ladder and its reapplication interval.
    var sunscreen = Set<String>()
    /// The UVA-heavy threshold.
    var uva = Set<String>()
    /// The escalation and gap notices, whose figure is the cycle dose (R13).
    var escalation = Set<String>()

    var all: Set<String> {
        target.union(solve).union(viability).union(sunscreen).union(uva).union(escalation)
    }
}

/// The range around the number, as the minutes at each of its edges (R7).
private struct RangeMinutes {
    let lower: Double
    let upper: Double
    /// True when the upper edge is the minutes to `MED_personal`.
    let clipped: Bool
}

// MARK: - One plan in progress

/// The planner's working state for one request. It is a value, built up in the
/// order the Internals fix, and every step records what it read.
private struct Context {
    let request: PlanRequest
    let curve: ForecastCurve
    let tunables: Tunables

    var reads = Reads()
    var stale = StaleLevel.fresh
    var plateau = [Region: PlateauOutcome]()
    var targets = [Region: RegionTarget]()
    var conservativeForced = false
    var aggressiveRefused = false
    var fairSkinPreCalibration = false
    /// The part of the window still ahead, once there is one.
    var window: Window?
    /// What that window would deliver to each region if the user stayed for all
    /// of it.
    var wholeWindowRaw = [Region: SED]()
    var attenuationRegion: Region?
    var uvaHeavy = false

    var thinMargin: Bool {
        request.profile.skinType.band == .fair
    }

    /// The region the window pushes hardest, or — when nothing is exposed or
    /// the window has not been looked at yet — the front, which is exposed in
    /// every posture.
    var focusRegion: Region {
        attenuationRegion ?? .front
    }

    /// True when today is over for every region.
    var everyBudgetSpent: Bool {
        Region.allCases.allSatisfy { (targets[$0]?.remaining ?? 0) <= 0 }
    }

    /// The region that took the most of today's dose — the one the
    /// budget-spent copy names.
    var mostSpentRegion: Region {
        Region.allCases.max { left, right in
            (request.state.regions[left]?.doseToday ?? 0) < (request.state.regions[right]?.doseToday ?? 0)
        } ?? .front
    }
}

// MARK: - Building the budgets

private extension Context {
    /// Staleness, the plateau outcomes, the targets they scale, and the flags
    /// the result screen needs about the scale actually used. The maintenance
    /// scaling happens here, before anything is solved, so the session and the
    /// sunscreen are both judged against the maintained budget (R14).
    mutating func prepare() {
        let request = request
        let curve = curve
        let (level, staleReads) = Planner.tracked(tunables) {
            Planner.staleLevel(curve: curve, now: request.now, deviceLocation: request.deviceLocation, tunables: $0)
        }
        stale = level
        reads.target.formUnion(staleReads)

        let (outcomes, plateauReads) = Planner.tracked(tunables) { tunables in
            Region.allCases.reduce(into: [Region: PlateauOutcome]()) { found, region in
                let state = request.state.regions[region] ?? RegionState()
                found[region] = AdaptationModel.plateauOutcome(state, tunables: tunables)
            }
        }
        plateau = outcomes
        reads.target.formUnion(plateauReads)

        let reduced = level.reducesTarget
        let (budgets, targetReads) = Planner.tracked(tunables) { tunables in
            Region.allCases.reduce(into: [Region: RegionTarget]()) { found, region in
                let target = request.goal.target(
                    for: region, profile: request.profile, state: request.state,
                    now: request.now, stale: reduced, tunables: tunables
                )
                found[region] = outcomes[region] == nil ? target : target.scaled(by: tunables.maintenanceFraction)
            }
        }
        targets = budgets
        reads.target.formUnion(targetReads)
        prepareScale()
    }

    /// The scale actually applied and why it is not the selected one, plus the
    /// fair-skin note that goes with the same report count.
    mutating func prepareScale() {
        let request = request
        let (scale, scaleReads) = Planner.tracked(tunables) {
            TanningGoal.effectiveScale(profile: request.profile, state: request.state, tunables: $0)
        }
        conservativeForced = scale.conservativeForced
        aggressiveRefused = scale.aggressiveRefused
        reads.target.formUnion(scaleReads)

        let (calibrating, calibrationReads) = Planner.tracked(tunables) {
            request.state.totalReports < $0.calibrationReports
        }
        fairSkinPreCalibration = thinMargin && calibrating
        reads.target.formUnion(calibrationReads)
    }

    /// What the window ahead would deliver, which region it pushes hardest, and
    /// whether it sits far enough from solar noon to be UVA-heavy (R18).
    mutating func observe(_ ahead: Window) {
        window = ahead
        let request = request
        let curve = curve
        let (raw, geometryReads) = Planner.tracked(tunables) {
            ExposureModel.wholeWindowRaw(
                ahead, posture: request.posture, firstSide: request.firstSide,
                coverHeadAndShoulders: request.coverHeadAndShoulders, curve: curve, tunables: $0
            )
        }
        wholeWindowRaw = raw
        reads.solve.formUnion(geometryReads)
        // Every minute figure rests on the UVI-minutes-per-SED conversion
        // (R4), which the curve applied when it integrated the forecast —
        // before this planner was asked, so no solve above could observe the
        // read. It is declared here and read through the request's Tunables,
        // so a recording copy sees exactly what the figures claim (R30, S1).
        _ = tunables.uviMinutesPerSED
        reads.solve.insert("uviMinutesPerSED")
        attenuationRegion = ExposureModel.attenuationRegion(raw: raw, targets: targets)

        let noon = curve.solarNoon(on: curve.day(ahead.start))
        let (heavy, uvaReads) = Planner.tracked(tunables) {
            DoseCalculator.isUVAHeavy(window: ahead, solarNoon: noon, tunables: $0)
        }
        uvaHeavy = heavy
        reads.uva.formUnion(uvaReads)
    }
}

// MARK: - The outcomes

private extension Context {
    /// The outcome for a window that cannot deliver a viable share of what is
    /// left of the budget: the shortfall from the melanogenic dose and the next
    /// window that could, or — when the horizon holds none — how many days were
    /// searched and how strong the sun got in them (R17).
    mutating func weakWindowOutcome() -> Outcome? {
        guard let window, let target = targets[focusRegion] else { return nil }
        let received = wholeWindowRaw[focusRegion] ?? 0
        let curve = curve
        let (fraction, barReads) = Planner.tracked(tunables) { $0.viabilityFraction }
        reads.viability.formUnion(barReads)
        guard received < fraction * min(target.remaining, target.target) else { return nil }

        let (next, searchReads) = Planner.tracked(tunables) {
            DoseCalculator.nextViableWindow(
                curve: curve, after: window.end, targetSED: target.target, tunables: $0
            )
        }
        reads.viability.formUnion(searchReads)
        if let next {
            return .tooWeak(shortfallSED: max(0, target.melanogenic - received), nextViable: next)
        }
        let (days, horizonReads) = Planner.tracked(tunables) { $0.forecastHorizonDays }
        reads.viability.formUnion(horizonReads)
        return .noViableWindow(days: days, peakUVI: curve.hourly.map(\.uvi).max() ?? 0)
    }

    /// The session itself, solved against the maintained budgets. Nil when
    /// there is no session to plan, which is the budget-spent outcome.
    mutating func solve() -> ExposurePlan? {
        solve(against: targets)
    }

    /// The session solved against the given budgets, recording what it read.
    mutating func solve(against budgets: [Region: RegionTarget]) -> ExposurePlan? {
        let request = request
        let exposure = ExposureRequest(
            window: request.window,
            now: request.now,
            posture: request.posture,
            firstSide: request.firstSide,
            coverHeadAndShoulders: request.coverHeadAndShoulders,
            intent: request.intent,
            targets: budgets,
            doseToday: request.state.regions.mapValues(\.doseToday),
            curve: curve
        )
        let (plan, solveReads) = Planner.tracked(tunables) { ExposureModel.solve(exposure, tunables: $0) }
        reads.solve.formUnion(solveReads)
        return plan
    }

    /// The range around the number, in minutes on the recommendation (R7):
    /// the same session solved again with every region's budget at each edge
    /// of its threshold range. The upper edge is where the range was clipped
    /// at `MED_personal` when it was, and its key says so (FIG-10). The number
    /// always sits inside its range.
    mutating func rangeMinutes(_ plan: ExposurePlan) -> RangeMinutes {
        let atLower = budgets(at: { $0.range.lowerBound })
        let atUpper = budgets(at: { $0.range.upperBound })
        let lower = solve(against: atLower)?.totalMinutes ?? 0
        let upper = solve(against: atUpper)?.totalMinutes ?? plan.totalMinutes
        return RangeMinutes(
            lower: min(lower, plan.totalMinutes),
            upper: max(upper, plan.totalMinutes),
            clipped: targets[plan.limitingRegion]?.rangeClipped ?? false
        )
    }

    /// Every region's budget moved to one edge of its own range.
    func budgets(at edge: (RegionTarget) -> SED) -> [Region: RegionTarget] {
        targets.mapValues { target in
            target.target > 0 ? target.scaled(by: edge(target) / target.target) : target
        }
    }

    /// The sunscreen answer, judged on the region the whole window pushes
    /// hardest and against what is left of that region's budget. Nothing to
    /// wear unless the window would overshoot it (R15, R16).
    mutating func sunscreenOutcome(for plan: ExposurePlan) -> SunscreenOutcome {
        guard let window, let target = targets[focusRegion] else { return .notNeeded(uvaHeavy: uvaHeavy) }
        let received = wholeWindowRaw[focusRegion] ?? 0
        guard received > target.remaining else { return .notNeeded(uvaHeavy: uvaHeavy) }
        let heavy = uvaHeavy
        let (outcome, solverReads) = Planner.tracked(tunables) {
            SunscreenSolver.outcome(
                rawSED: received, budgetSED: target.remaining, window: window,
                bareMinutes: plan.totalMinutes, uvaHeavy: heavy, tunables: $0
            )
        }
        reads.sunscreen.formUnion(solverReads)
        return outcome
    }

    /// Which answer leads (R15). A window that could not reach the budget is
    /// its own headline; otherwise the sunscreen leads only when the user has
    /// said they will stay out and there is a realistic product to name.
    func headline(_ plan: ExposurePlan, sunscreen: SunscreenOutcome) -> Headline {
        if plan.fillsWindow {
            return .wholeWindowFits
        }
        let overshoot = (wholeWindowRaw[focusRegion] ?? 0) > (targets[focusRegion]?.remaining ?? 0)
        guard overshoot, request.intent == .stayWholeWindow, case .prescribe = sunscreen else {
            return .bareSubWindow
        }
        return .sunscreenForWholeWindow
    }
}

// MARK: - Assembling the result

private extension Context {
    /// The finished result: the outcome, the budgets it was solved against, the
    /// notices, every figure with its provenance, and the copy keys in display
    /// order.
    mutating func finish(_ outcome: Outcome, plan: ExposurePlan? = nil) -> DoseResult {
        let focus = plan?.limitingRegion ?? focusRegion
        let range = plan.map { rangeMinutes($0) }
        let region = request.state.regions[focus] ?? RegionState()
        let skinType = request.profile.skinType
        let now = request.now
        let (escalation, escalationReads) = Planner.tracked(tunables) {
            AdaptationModel.escalationNotice(region, now: now, skinType: skinType, tunables: $0)
        }
        reads.escalation.formUnion(escalationReads)

        let notices = Notices(
            escalation: escalation,
            plateau: plateau[focus] ?? Region.allCases.compactMap { plateau[$0] }.first,
            maintenanceApplied: !plateau.isEmpty,
            uvaHeavy: uvaHeavy,
            stale: stale,
            thinMargin: thinMargin,
            conservativeForced: conservativeForced,
            fairSkinPreCalibration: fairSkinPreCalibration,
            aggressiveRefused: aggressiveRefused,
            // No forecast the engine sees carries cloud cover; the data layer
            // supplies the caveat when it can (M2).
            cloudCaveat: false
        )
        return DoseResult(
            outcome: outcome,
            targets: targets,
            notices: notices,
            figures: figures(outcome: outcome, plan: plan, range: range),
            copyKeys: copyKeys(outcome: outcome, plan: plan, notices: notices, focus: focus),
            cycleDose: request.state.regions.mapValues(\.doseInCycle),
            attenuationRegion: attenuationRegion,
            wholeWindowRaw: wholeWindowRaw
        )
    }

    /// Every number the result shows, each declaring the constants its own
    /// value depended on (R30).
    func figures(
        outcome: Outcome,
        plan: ExposurePlan?,
        range: RangeMinutes?
    ) -> [Figure] {
        var out = [Figure]()
        if let plan {
            out += planFigures(plan, range: range)
        }
        if case let .tooWeak(shortfall, _) = outcome {
            out.append(Figure(
                key: .shortfall, region: attenuationRegion, value: shortfall, unit: .sed,
                reads: reads.target.union(reads.viability)
            ))
        }
        out += budgetFigures()
        if case let .plan(_, sunscreen, _) = outcome, case let .prescribe(advice) = sunscreen {
            out.append(Figure(
                key: .uvaMultiple, value: advice.uvaMultiple, unit: .multiple,
                reads: reads.sunscreen.union(reads.uva)
            ))
        }
        return sweep(out)
    }

    /// The session's own numbers: how long it runs and the range around that,
    /// how long each side runs, what each region takes, and how much longer it
    /// could run covered.
    func planFigures(_ plan: ExposurePlan, range: RangeMinutes?) -> [Figure] {
        let derived = reads.target.union(reads.solve)
        var out = [Figure(
            key: .headlineMinutes, value: plan.totalMinutes, unit: .minutes,
            reads: derived.union(reads.viability)
        )]
        if let range {
            out.append(Figure(key: .rangeLower, value: range.lower, unit: .minutes, reads: derived))
            out.append(Figure(
                key: range.clipped ? .rangeUpperClipped : .rangeUpper, value: range.upper, unit: .minutes,
                reads: derived
            ))
        }
        if plan.sides.count > 1 {
            out += plan.sides.map {
                Figure(
                    key: .sideMinutes, exposure: $0.exposure, value: $0.window.minutes,
                    unit: .minutes, reads: derived
                )
            }
        }
        for region in Region.allCases {
            let dose = plan.perRegionDose[region] ?? 0
            guard dose > 0 else { continue }
            out.append(Figure(key: .regionDose, region: region, value: dose, unit: .sed, reads: derived))
        }
        for side in plan.sides {
            guard let extra = plan.extraMinutesIfCovered[side.exposure], extra > 0 else { continue }
            out.append(Figure(
                key: .extraIfCovered, exposure: side.exposure, value: extra, unit: .minutes, reads: derived
            ))
        }
        return out
    }

    /// What is left of each region's budget and the dose it has taken since
    /// its cycle began — the second is the figure the escalation message shows
    /// beside itself (R13).
    func budgetFigures() -> [Figure] {
        var out = [Figure]()
        for region in Region.allCases {
            guard let target = targets[region] else { continue }
            out.append(Figure(
                key: .remainingBudget, region: region, value: target.remaining, unit: .sed, reads: reads.target
            ))
            out.append(Figure(
                key: .cycleDose, region: region, value: request.state.regions[region]?.doseInCycle ?? 0,
                unit: .sed, reads: reads.escalation
            ))
        }
        return out
    }

    /// The promise the tests hold: what a recording `Tunables` saw is exactly
    /// the union of the figures' declared reads. A constant read for a notice
    /// rather than for a number of its own — the UVA threshold, or the ladder
    /// behind a "nothing realistic covers this" — belongs to the headline it
    /// shaped, so it is folded into the first figure rather than dropped.
    func sweep(_ figures: [Figure]) -> [Figure] {
        let claimed = figures.reduce(into: Set<String>()) { $0.formUnion($1.reads) }
        let missing = reads.all.subtracting(claimed)
        guard !missing.isEmpty, let first = figures.first else { return figures }
        var out = figures
        out[0] = Figure(
            key: first.key, region: first.region, exposure: first.exposure,
            value: first.value, unit: first.unit, reads: first.reads.union(missing)
        )
        return out
    }
}

// MARK: - The copy keys, in display order

private extension Context {
    /// Every line the outcome and the notices imply, outcome first, then the
    /// notices, the warnings, and the sunscreen.
    func copyKeys(outcome: Outcome, plan: ExposurePlan?, notices: Notices, focus: Region) -> [CopyKey] {
        var keys = [CopyKey]()
        func add(_ key: CopyKey) {
            guard !keys.contains(key) else { return }
            keys.append(key)
        }
        add(outcomeKey(outcome))
        if plan != nil, let target = targets[focus] {
            add(target.boundBy == .melanogenic ? .boundByMelanogenic : .boundByBurnLine)
        }
        noticeKeys(notices).forEach(add)
        if let plan {
            planKeys(plan).forEach(add)
        }
        if case let .plan(_, sunscreen, _) = outcome {
            sunscreenKeys(sunscreen).forEach(add)
        }
        return keys
    }

    func outcomeKey(_ outcome: Outcome) -> CopyKey {
        switch outcome {
        case let .plan(_, _, headline):
            switch headline {
            case .bareSubWindow: .planBareSubWindow
            case .sunscreenForWholeWindow: .planStayWearThis
            case .wholeWindowFits: .planStayWholeWindowFits
            }
        case .tooWeak: .tooWeak
        case .noViableWindow: .noViableWindow
        case .windowPassed: .windowPassed
        case .budgetSpent: .budgetSpent
        case let .missingForecast(kind): kind == .noLocation ? .missingForecastNoLocation : .missingForecast
        }
    }

    func noticeKeys(_ notices: Notices) -> [CopyKey] {
        skinKeys(notices) + historyKeys(notices)
    }

    /// What follows from the skin type and from how much the app has learned.
    func skinKeys(_ notices: Notices) -> [CopyKey] {
        var keys = [CopyKey]()
        if notices.thinMargin {
            keys.append(.thinMargin)
        }
        if notices.fairSkinPreCalibration {
            keys.append(.fairSkinPreCalibration)
        }
        if notices.conservativeForced {
            keys.append(.conservativeUntilCalibrated)
        }
        if notices.aggressiveRefused {
            keys.append(.aggressiveLocked)
        }
        return keys
    }

    /// What follows from the history and from the forecast behind the number.
    func historyKeys(_ notices: Notices) -> [CopyKey] {
        var keys = [CopyKey]()
        switch notices.escalation {
        case .risen: keys.append(.escalationRisen)
        case .dropped: keys.append(.toleranceDropped)
        case nil: break
        }
        switch notices.plateau {
        case .ceiling: keys.append(.ceilingReached)
        case .underDosed: keys.append(.underDosed)
        case nil: break
        }
        if notices.maintenanceApplied {
            keys.append(.maintenance)
        }
        keys += staleKeys(notices.stale)
        if notices.uvaHeavy {
            keys.append(.uvaHeavy)
        }
        if notices.cloudCaveat {
            keys.append(.cloudCaveat)
        }
        return keys
    }

    func staleKeys(_ level: StaleLevel) -> [CopyKey] {
        switch level {
        case .fresh: []
        case .headsUp: [.staleHeadsUp]
        case let .warn(_, far): far ? [.staleWarn, .staleFarFromCache] : [.staleWarn]
        }
    }

    /// What the session itself implies: the option to cover up and run longer,
    /// a side whose budget is already spent, and the warnings the solve
    /// produced. Which side goes first is the flip timer's question, asked
    /// where it can be answered (R11, screen review F2).
    func planKeys(_ plan: ExposurePlan) -> [CopyKey] {
        var keys = [CopyKey]()
        if plan.extraMinutesIfCovered.values.contains(where: { $0 > 0 }) {
            keys.append(.coverToRunLonger)
        }
        if request.posture == .lyingTurning, plan.sides.contains(where: { $0.window.minutes <= 0 }) {
            keys.append(.oneSideSpent)
        }
        for warning in plan.warnings {
            switch warning {
            case .pastTarget: keys.append(.warnPastTarget)
            case .reachesThreshold: keys.append(.warnReachesThreshold)
            }
        }
        return keys
    }

    func sunscreenKeys(_ sunscreen: SunscreenOutcome) -> [CopyKey] {
        switch sunscreen {
        case let .notNeeded(uvaHeavy):
            uvaHeavy ? [.sunscreenNotNeeded, .uvaHeavy] : [.sunscreenNotNeeded]
        case let .prescribe(advice):
            [.sunscreenPrescribed, advice.whyModerateSPF, .uvaMultiple]
                + (advice.reapplyAt.isEmpty ? [] : [CopyKey.reapply])
        case .nothingRealistic:
            [.nothingRealistic]
        }
    }
}
