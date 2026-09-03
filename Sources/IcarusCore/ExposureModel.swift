// The exposure model is one file by the plan's file list: the request, the
// plan, the posture geometry and the solver are one contract, and splitting
// them would put half of it in a file no slice declares.
// swiftlint:disable file_length

import Foundation

/// Everything the solver needs for one session: the window the user entered,
/// the clock, how they will lie or stand, whether the head and shoulders are
/// covered, whether they mean to stay out, each region's budget, what each
/// region already took today, and the forecast to integrate.
public struct ExposureRequest: Sendable {
    public let window: Window
    public let now: Date
    public let posture: Posture
    public let firstSide: Side
    public let coverHeadAndShoulders: Bool
    public let intent: Intent
    public let targets: [Region: RegionTarget]
    public let doseToday: [Region: SED]
    public let curve: ForecastCurve

    public init(
        window: Window,
        now: Date,
        posture: Posture,
        firstSide: Side,
        coverHeadAndShoulders: Bool,
        intent: Intent,
        targets: [Region: RegionTarget],
        doseToday: [Region: SED],
        curve: ForecastCurve
    ) {
        self.window = window
        self.now = now
        self.posture = posture
        self.firstSide = firstSide
        self.coverHeadAndShoulders = coverHeadAndShoulders
        self.intent = intent
        self.targets = targets
        self.doseToday = doseToday
        self.curve = curve
    }
}

/// One stretch of the session: what the body is doing, when, and what every
/// region gets out of it.
public struct SideAllocation: Sendable, Equatable {
    public let exposure: Exposure
    public let window: Window
    public let doses: [Region: SED]

    public init(exposure: Exposure, window: Window, doses: [Region: SED]) {
        self.exposure = exposure
        self.window = window
        self.doses = doses
    }
}

/// The solved session.
public struct ExposurePlan: Sendable, Equatable {
    public let sides: [SideAllocation]
    public let perRegionDose: [Region: SED]
    /// The region whose budget ran out first — what the copy explains.
    public let limitingRegion: Region
    public let span: Window
    public let totalMinutes: Double
    /// True when the two sides differ by more than the tunable fraction, so
    /// the result says "front X, back Y" rather than "X per side" (R9).
    public let showTwoFigures: Bool
    /// How much longer each stretch could run with the head and shoulders
    /// covered (R10). Empty when they already are.
    public let extraMinutesIfCovered: [Exposure: Double]
    /// True when the window could not reach the budget, so the plan is the
    /// whole window rather than a block inside it.
    public let fillsWindow: Bool
    public let warnings: [Warning]

    public init(
        sides: [SideAllocation],
        perRegionDose: [Region: SED],
        limitingRegion: Region,
        span: Window,
        totalMinutes: Double,
        showTwoFigures: Bool,
        extraMinutesIfCovered: [Exposure: Double],
        fillsWindow: Bool,
        warnings: [Warning]
    ) {
        self.sides = sides
        self.perRegionDose = perRegionDose
        self.limitingRegion = limitingRegion
        self.span = span
        self.totalMinutes = totalMinutes
        self.showTwoFigures = showTwoFigures
        self.extraMinutesIfCovered = extraMinutesIfCovered
        self.fillsWindow = fillsWindow
        self.warnings = warnings
    }

    /// The stretches that actually last a minute, in order — what the timer
    /// runs and what a session record stores. A side whose budget is already
    /// spent is not one of them.
    public var intervals: [ExposureInterval] {
        sides.filter { $0.window.minutes > 0 }
            .map { ExposureInterval(exposure: $0.exposure, window: $0.window) }
    }
}

/// What the whole entered window would do to a region, when the user means to
/// stay out for it (R19). `dayTotal` is today's dose including this window.
public enum Warning: Sendable, Equatable {
    case pastTarget(Region, dayTotal: SED)
    case reachesThreshold(Region, dayTotal: SED)
}

/// The posture geometry and the solver: who gets what dose, what one region's
/// budget allows, and the coupled two-side solve for lying down.
public enum ExposureModel {
    // MARK: - Geometry

    /// What each region receives over a stretch, before sunscreen.
    public static func dose(
        _ exposure: Exposure,
        coverHeadAndShoulders: Bool,
        over window: Window,
        curve: ForecastCurve,
        tunables: Tunables
    ) -> [Region: SED] {
        let bare = curve.sed(from: window.start, to: window.end)
        return factors(exposure, coverHeadAndShoulders: coverHeadAndShoulders, tunables: tunables)
            .mapValues { $0 * bare }
    }

    // Six arguments: the plan's contract fixes this signature.
    // swiftlint:disable function_parameter_count
    /// The dose of the whole window in either posture — the "I am staying out"
    /// model, and what a session logged after the fact is credited with. Lying
    /// down is two equal consecutive halves in side order.
    public static func wholeWindowRaw(
        _ window: Window,
        posture: Posture,
        firstSide: Side,
        coverHeadAndShoulders: Bool,
        curve: ForecastCurve,
        tunables: Tunables
    ) -> [Region: SED] {
        switch posture {
        case .upAndAbout:
            return dose(
                .upAndAbout, coverHeadAndShoulders: coverHeadAndShoulders,
                over: window, curve: curve, tunables: tunables
            )
        case .lyingTurning:
            let middle = window.start.addingTimeInterval(window.minutes * 30)
            let halves = [Window(start: window.start, end: middle), Window(start: middle, end: window.end)]
            var total = zeroDose
            for (side, half) in zip(sideOrder(firstSide), halves) {
                add(
                    dose(
                        .lying(side), coverHeadAndShoulders: coverHeadAndShoulders,
                        over: half, curve: curve, tunables: tunables
                    ),
                    to: &total
                )
            }
            return total
        }
    }

    // swiftlint:enable function_parameter_count

    /// The one attenuation function every logging path calls. Sunscreen divides
    /// every region by the pair's effective SPF; an opaque cover takes the head
    /// and shoulders to zero, and sunscreen is never a cover (R10, R15).
    public static func attenuated(
        _ bare: [Region: SED],
        sunscreen: SunscreenChoice?,
        coverHeadAndShoulders: Bool
    ) -> [Region: SED] {
        let protection = sunscreen?.effectiveSPF ?? 1
        var out = bare.mapValues { protection > 0 ? $0 / protection : $0 }
        if coverHeadAndShoulders { out[.headAndShoulders] = 0 }
        return out
    }

    /// The region a sunscreen has to be solved for: the one the raw dose pushes
    /// hardest against what is left of its budget. A spent region is pushed
    /// infinitely hard. Nil when nothing is exposed.
    public static func attenuationRegion(raw: [Region: SED], targets: [Region: RegionTarget]) -> Region? {
        var best: (region: Region, ratio: Double)?
        for region in Region.allCases {
            let received = raw[region] ?? 0
            guard received > 0, let target = targets[region] else { continue }
            let ratio = target.remaining > 0 ? received / target.remaining : Double.infinity
            // A tie — two sides of a turning body on a flat curve — keeps the
            // earlier region, so the answer never turns on a rounding bit.
            if let current = best, ratio <= current.ratio * (1 + 1e-9) { continue }
            best = (region, ratio)
        }
        return best?.region
    }

    // MARK: - The solve

    /// The largest session the window allows that keeps every region at or
    /// under its budget. Nil only when there is no session to plan: the head
    /// and shoulders are uncovered and spent, both torso sides are spent, or
    /// every region exposed while up and about is spent.
    public static func solve(_ request: ExposureRequest, tunables: Tunables) -> ExposurePlan? {
        guard let window = DoseCalculator.clip(request.window, toStartNoEarlierThan: request.now) else { return nil }
        if !request.coverHeadAndShoulders, remaining(request, .headAndShoulders) <= 0 { return nil }
        let solved: Shape? = switch request.posture {
        case .upAndAbout:
            uprightShape(request, in: window, tunables: tunables)
        case .lyingTurning:
            lyingShape(request, in: window, tunables: tunables)
        }
        guard let shape = solved else { return nil }
        return plan(fitted(shape, request, tunables: tunables), request, window: window, tunables: tunables)
    }

    /// What the whole entered window would do, compared against the target and
    /// the burn line — and only when the user has said they mean to stay (R19).
    public static func warnings(entered: Window, r request: ExposureRequest, tunables: Tunables) -> [Warning] {
        guard request.intent == .stayWholeWindow else { return [] }
        let raw = wholeWindowRaw(
            entered, posture: request.posture, firstSide: request.firstSide,
            coverHeadAndShoulders: request.coverHeadAndShoulders, curve: request.curve, tunables: tunables
        )
        var out = [Warning]()
        for region in Region.allCases {
            guard let target = request.targets[region] else { continue }
            let total = (request.doseToday[region] ?? 0) + (raw[region] ?? 0)
            if total >= target.medPersonal {
                out.append(.reachesThreshold(region, dayTotal: total))
            } else if total > target.target {
                out.append(.pastTarget(region, dayTotal: total))
            }
        }
        return out
    }
}

// MARK: - Shapes

private extension ExposureModel {
    /// One stretch of a candidate session: what the body is doing and for how
    /// long. Stretches run consecutively from the shape's start.
    struct Leg {
        let exposure: Exposure
        var minutes: Double
    }

    /// A candidate session before it is turned into a plan.
    struct Shape {
        var start: Date
        var legs: [Leg]
        var fillsWindow: Bool

        var totalMinutes: Double { legs.reduce(0) { $0 + $1.minutes } }

        func scaled(by factor: Double) -> Shape {
            Shape(start: start, legs: legs.map { Leg(exposure: $0.exposure, minutes: $0.minutes * factor) },
                  fillsWindow: fillsWindow)
        }

        /// The stretches as clock windows, consecutive from the start.
        func windows() -> [Window] {
            var opens = start
            return legs.map { leg in
                let closes = opens.addingTimeInterval(leg.minutes * 60)
                defer { opens = closes }
                return Window(start: opens, end: closes)
            }
        }
    }

    /// Up and about, every region is exposed at once, so the session is one
    /// block and the shortest block that spends the tightest budget is the
    /// answer. A window that cannot reach it is planned whole.
    static func uprightShape(_ request: ExposureRequest, in window: Window, tunables: Tunables) -> Shape? {
        let shares = factors(.upAndAbout, coverHeadAndShoulders: request.coverHeadAndShoulders, tunables: tunables)
        guard let required = requiredSED(shares, request) else { return nil }
        guard required > 0 else {
            return Shape(start: window.start, legs: [Leg(exposure: .upAndAbout, minutes: 0)], fillsWindow: false)
        }
        if let best = DoseCalculator.bestSubWindow(
            curve: request.curve, within: window, now: request.now, targetSED: required, tunables: tunables
        ) {
            return Shape(
                start: best.start, legs: [Leg(exposure: .upAndAbout, minutes: best.minutes)], fillsWindow: false
            )
        }
        return Shape(start: window.start, legs: [Leg(exposure: .upAndAbout, minutes: window.minutes)],
                     fillsWindow: true)
    }

    /// Lying down, the two sides are consecutive and each is solved against its
    /// own torso region: the side runs exactly as long as that region's budget
    /// allows, and a side whose budget is already spent runs not at all.
    static func lyingShape(_ request: ExposureRequest, in window: Window, tunables _: Tunables) -> Shape? {
        let order = sideOrder(request.firstSide)
        let budgets = order.map { remaining(request, torso($0)) }
        if budgets[0] <= 0, budgets[1] <= 0 { return nil }
        return bestLyingStart(request, in: window, budgets: budgets, order: order)
            ?? fillingShape(request, in: window, budgets: budgets, order: order)
    }

    /// One candidate start: the session it produces, how long that session
    /// runs, and how far its middle sits from solar noon — the tie-breaker.
    struct Candidate {
        let shape: Shape
        let total: Double
        let offNoon: Double

        func beats(_ other: Candidate) -> Bool {
            total < other.total - 1e-6 || (total < other.total + 1e-6 && offNoon < other.offNoon)
        }
    }

    /// The start minute whose two sides finish soonest. Ties — a flat curve
    /// makes every start equal — go to the session centred nearest solar noon.
    static func bestLyingStart(
        _ request: ExposureRequest,
        in window: Window,
        budgets: [Double],
        order: [Side]
    ) -> Shape? {
        var best: Candidate?
        var start = window.start
        while start <= window.end {
            if let legs = sideDurations(request, from: start, until: window.end, budgets: budgets, order: order) {
                let total = legs[0] + legs[1]
                let middle = start.addingTimeInterval(total * 30)
                let noon = request.curve.solarNoon(on: request.curve.day(start))
                let candidate = Candidate(
                    shape: Shape(
                        start: start,
                        legs: zip(order, legs).map { Leg(exposure: .lying($0.0), minutes: $0.1) },
                        fillsWindow: false
                    ),
                    total: total,
                    offNoon: abs(middle.timeIntervalSince(noon))
                )
                if best.map({ candidate.beats($0) }) ?? true { best = candidate }
            }
            start = start.addingTimeInterval(60)
        }
        return best?.shape
    }

    /// How long each side runs from a start, or nil when one of them cannot
    /// reach its budget before the window closes.
    static func sideDurations(
        _ request: ExposureRequest,
        from start: Date,
        until end: Date,
        budgets: [Double],
        order _: [Side]
    ) -> [Double]? {
        guard let first = budgets[0] <= 0 ? 0 : DoseCalculator.durationFrom(
            start, targetSED: budgets[0], curve: request.curve, notAfter: end
        ) else { return nil }
        let secondStart = start.addingTimeInterval(first * 60)
        guard let second = budgets[1] <= 0 ? 0 : DoseCalculator.durationFrom(
            secondStart, targetSED: budgets[1], curve: request.curve, notAfter: end
        ) else { return nil }
        return [first, second]
    }

    /// The window cannot reach either budget, so it is planned in full and the
    /// only question is where to flip: at the time that leaves both sides the
    /// same fraction of their budgets. A spent side gets nothing and the other
    /// gets everything.
    static func fillingShape(
        _ request: ExposureRequest,
        in window: Window,
        budgets: [Double],
        order: [Side]
    ) -> Shape {
        var flip = window.start
        if budgets[0] <= 0 {
            flip = window.start
        } else if budgets[1] <= 0 {
            flip = window.end
        } else {
            var low = window.start
            var high = window.end
            for _ in 0 ..< 60 {
                let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                let ahead = request.curve.sed(from: window.start, to: middle) / budgets[0]
                let behind = request.curve.sed(from: middle, to: window.end) / budgets[1]
                if ahead > behind { high = middle } else { low = middle }
            }
            flip = low
        }
        let first = max(0, flip.timeIntervalSince(window.start) / 60)
        let second = max(0, window.end.timeIntervalSince(flip) / 60)
        return Shape(
            start: window.start,
            legs: [Leg(exposure: .lying(order[0]), minutes: first),
                   Leg(exposure: .lying(order[1]), minutes: second)],
            fillsWindow: true
        )
    }

    /// The head-and-shoulders credit is the face-up dose in full plus a share
    /// of the face-down dose, so it can overrun its budget when both torso
    /// sides are within theirs. Both sides then shrink by one scalar, found by
    /// bisection, until the credit fits (D-2026-09-03-F2).
    static func fitted(_ shape: Shape, _ request: ExposureRequest, tunables: Tunables) -> Shape {
        guard !request.coverHeadAndShoulders else { return shape }
        let budget = remaining(request, .headAndShoulders)
        guard budget.isFinite, shape.totalMinutes > 0 else { return shape }
        guard credit(shape, request, tunables: tunables) > budget + 1e-9 else { return shape }
        var low = 0.0
        var high = 1.0
        for _ in 0 ..< 50 {
            let middle = (low + high) / 2
            if credit(shape.scaled(by: middle), request, tunables: tunables) > budget { high = middle } else {
                low = middle
            }
        }
        var fitted = shape.scaled(by: low)
        fitted.fillsWindow = false
        return fitted
    }

    /// What the head and shoulders take over a whole shape.
    static func credit(_ shape: Shape, _ request: ExposureRequest, tunables: Tunables) -> SED {
        zip(shape.legs, shape.windows()).reduce(0) { total, pair in
            total + (dose(
                pair.0.exposure, coverHeadAndShoulders: request.coverHeadAndShoulders,
                over: pair.1, curve: request.curve, tunables: tunables
            )[.headAndShoulders] ?? 0)
        }
    }
}

// MARK: - Building the plan

private extension ExposureModel {
    static func plan(
        _ shape: Shape,
        _ request: ExposureRequest,
        window: Window,
        tunables: Tunables
    ) -> ExposurePlan {
        let sides = zip(shape.legs, shape.windows()).map { leg, span in
            SideAllocation(
                exposure: leg.exposure,
                window: span,
                doses: dose(
                    leg.exposure, coverHeadAndShoulders: request.coverHeadAndShoulders,
                    over: span, curve: request.curve, tunables: tunables
                )
            )
        }
        var perRegion = zeroDose
        for side in sides {
            add(side.doses, to: &perRegion)
        }
        let total = shape.totalMinutes
        return ExposurePlan(
            sides: sides,
            perRegionDose: perRegion,
            limitingRegion: attenuationRegion(raw: perRegion, targets: request.targets) ?? .front,
            span: Window(start: shape.start, end: shape.start.addingTimeInterval(total * 60)),
            totalMinutes: total,
            showTwoFigures: twoFigures(shape, tunables: tunables),
            extraMinutesIfCovered: extraIfCovered(shape, request, tunables: tunables),
            fillsWindow: shape.fillsWindow,
            warnings: warnings(entered: window, r: request, tunables: tunables)
        )
    }

    static func twoFigures(_ shape: Shape, tunables: Tunables) -> Bool {
        guard shape.legs.count == 2 else { return false }
        let longest = max(shape.legs[0].minutes, shape.legs[1].minutes)
        guard longest > 0 else { return false }
        return abs(shape.legs[0].minutes - shape.legs[1].minutes) / longest > tunables.sideDifferenceForTwoFigures
    }

    /// How much longer each stretch could run with the head and shoulders
    /// covered: the same solve again with the cover on, minus what was solved
    /// here. Empty when the cover is already on, which also stops the
    /// recursion.
    static func extraIfCovered(
        _ shape: Shape,
        _ request: ExposureRequest,
        tunables: Tunables
    ) -> [Exposure: Double] {
        guard !request.coverHeadAndShoulders else { return [:] }
        let covered = ExposureRequest(
            window: request.window, now: request.now, posture: request.posture, firstSide: request.firstSide,
            coverHeadAndShoulders: true, intent: request.intent, targets: request.targets,
            doseToday: request.doseToday, curve: request.curve
        )
        guard let plan = solve(covered, tunables: tunables) else { return [:] }
        var extra = [Exposure: Double]()
        for (leg, side) in zip(shape.legs, plan.sides) where side.exposure == leg.exposure {
            extra[leg.exposure] = max(0, side.window.minutes - leg.minutes)
        }
        return extra
    }
}

// MARK: - Small arithmetic

private extension ExposureModel {
    static var zeroDose: [Region: SED] {
        Region.allCases.reduce(into: [Region: SED]()) { $0[$1] = 0 }
    }

    static func add(_ doses: [Region: SED], to total: inout [Region: SED]) {
        for (region, value) in doses {
            total[region, default: 0] += value
        }
    }

    static func sideOrder(_ first: Side) -> [Side] {
        first == .faceUp ? [.faceUp, .faceDown] : [.faceDown, .faceUp]
    }

    /// The torso region a side presents to the sun.
    static func torso(_ side: Side) -> Region {
        side == .faceUp ? .front : .back
    }

    /// What is left of a region's budget. A region the caller did not give a
    /// target for cannot limit anything.
    static func remaining(_ request: ExposureRequest, _ region: Region) -> Double {
        request.targets[region]?.remaining ?? .infinity
    }

    /// Each region's share of the bare dose in one exposure (R9, R10).
    static func factors(
        _ exposure: Exposure,
        coverHeadAndShoulders: Bool,
        tunables: Tunables
    ) -> [Region: Double] {
        var shares: [Region: Double]
        switch exposure {
        case .upAndAbout:
            let torso = tunables.frontBackFraction
            shares = [.front: torso, .back: torso, .headAndShoulders: 1]
        case .lying(.faceUp):
            shares = [.front: 1, .back: 0, .headAndShoulders: 1]
        case .lying(.faceDown):
            shares = [.front: 0, .back: 1, .headAndShoulders: tunables.shoulderFraction]
        }
        if coverHeadAndShoulders { shares[.headAndShoulders] = 0 }
        return shares
    }

    /// The bare dose at which the first exposed region runs out of budget. Zero
    /// when one of them is already spent, and nil when every one of them is —
    /// there is no session to plan then.
    static func requiredSED(_ shares: [Region: Double], _ request: ExposureRequest) -> Double? {
        var exposed = [Region]()
        for region in Region.allCases where (shares[region] ?? 0) > 0 {
            exposed.append(region)
        }
        guard !exposed.isEmpty else { return nil }
        let budgets = exposed.map { remaining(request, $0) }
        guard budgets.contains(where: { $0 > 0 }) else { return nil }
        guard !budgets.contains(where: { $0 <= 0 }) else { return 0 }
        let worst = zip(exposed, budgets).reduce(0.0) { max($0, (shares[$1.0] ?? 0) / $1.1) }
        return worst > 0 ? 1 / worst : .infinity
    }
}
