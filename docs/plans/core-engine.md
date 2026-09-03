---
slug: core-engine
status: draft
created: 2026-09-02
design: M1 — Core engine
covers: [R4, R5, R6, R7, R8, R9, R10, R12, R13, R14, R15, R16, R17, R18, R19, R21, R30, R38, R43, R44]
format: pseudocode
---

# Core engine — Plan

## Summary

The pure-Swift engine: a function from forecast curve, clock, profile, replayed
state, and today's dose to a typed `DoseResult`, plus the calibration and
adaptation loops that replay from the history. No UI, no network, no system
services; builds and tests on Linux and macOS alike. Revision 2 lands the
tactical review (`docs/reviews/design/tactical-1.md`).

Non-goals:
- We do NOT fetch weather, read location, persist anything, or schedule prompts (M2, M5).
- We do NOT render copy: outcomes carry `CopyKey`s, never strings (M3, M4).
- We do NOT build the vitamin D goal; we leave the `TargetGoal` seam it needs.

Owner costs:
- CI change (owner override merge): Core tests run on a Linux runner; the
  macOS `test` job keeps the app build; `project.yml` gains the package.

Rulings: D-2026-09-03-F1, F2, F3, F5, F6, F7, F8 and T1–T4 (docs/DECISIONS.md)

## The slices

Layout (ruled D-2026-09-03-F1): one root `Package.swift` with five library
targets (`IcarusCore`, `IcarusData`, `IcarusContent`, `IcarusAds`, `IcarusUI`)
under `Sources/<Target>/` and `Tests/<Target>Tests/`, and the app shell in
`App/` referenced by `project.yml` as a local package at `.`. Tests are XCTest
(F5). Engine and content tests run on a Linux CI job, `core-tests` (F6).
Every type any later plan names is declared in Slice 1 (tactical #20), so no
slice stubs another's types.

## Slice 1 — Models, Tunables, and dose from a curve: integrate, sub-window, viability, clock

- **Delivers:** Every shared value type exists with its full declaration; `Tunables` carries every constant with its basis; given a forecast curve (with its location's time zone), a window and the clock, the engine returns the SED over any interval by trapezoid on a one-minute prefix integral, the shortest block for a target dose ending on an interpolated minute, viability, the next viable window within the horizon, the UVA-heavy flag, and the "window has passed" clip. The build prompt's 14:00–17:00 counter-example and the type II at UVI 7 ≈ 21.4 min check pass.
- **Files:** `Package.swift`, `Sources/IcarusCore/Tunables.swift`, `Sources/IcarusCore/Models/Units.swift`, `Sources/IcarusCore/Models/DayKey.swift`, `Sources/IcarusCore/Models/ForecastCurve.swift`, `Sources/IcarusCore/Models/StoredCurve.swift`, `Sources/IcarusCore/Models/Window.swift`, `Sources/IcarusCore/Models/SkinType.swift`, `Sources/IcarusCore/Models/Region.swift`, `Sources/IcarusCore/Models/Sunscreen.swift`, `Sources/IcarusCore/Models/CopyKey.swift`, `Sources/IcarusCore/Models/Figure.swift`, `Sources/IcarusCore/DoseCalculator.swift`, `Tests/IcarusCoreTests/DoseCalculatorTests.swift`, `Tests/IcarusCoreTests/TunablesTests.swift`, `Tests/IcarusCoreTests/Fixtures/Curves.swift`, `.github/workflows/ci.yml`, `project.yml`
- **Estimate:** ~640 lines

### Signatures

```text
// Package.swift: swift-tools-version 6.0; platforms [.iOS(.v18), .macOS(.v14)];
// products: five libraries; targets: IcarusCore (deps: none), IcarusContent (none; resources: [.copy("Resources")]),
// IcarusAds (none until M7), IcarusData (IcarusCore; test resources copied), IcarusUI (IcarusCore, IcarusData, IcarusContent, IcarusAds);
// test targets: IcarusCoreTests, IcarusDataTests, IcarusContentTests, IcarusUITests, IcarusAdsTests.

public typealias SED = Double            // 1 SED = 100 J/m² erythemal
public typealias UVI = Double

public struct DayKey: Codable, Sendable, Hashable, Comparable {
    public let year: Int; public let month: Int; public let day: Int; public let timeZoneID: String
    public init(_ date: Date, timeZone: TimeZone)
    public func start() -> Date; public func end() -> Date        // in its own time zone; end = next day's start
    public func adding(days: Int) -> DayKey
}
public enum SkinType: Int, CaseIterable, Codable, Sendable { case i = 1, ii, iii, iv, v, vi; public var band: SkinBand }
public enum SkinBand: Codable, Sendable, CaseIterable { case fair /*I–II*/, medium /*III*/, dark /*IV–VI*/ }
public enum Region: CaseIterable, Codable, Sendable { case front, back, headAndShoulders }
public enum Side: Codable, Sendable { case faceUp, faceDown }
public enum Exposure: Codable, Sendable, Equatable { case lying(Side), upAndAbout }
public enum Posture: Codable, Sendable { case lyingTurning, upAndAbout }
public enum Intent: Codable, Sendable { case bestMinutes, stayWholeWindow }
public enum Ceiling: Codable, Sendable, CaseIterable { case conservative, standard, aggressive }
public struct Window: Codable, Sendable, Equatable { public let start: Date; public let end: Date; public var minutes: Double }
public struct Coordinate: Codable, Sendable, Equatable { public let latitude: Double; public let longitude: Double
    public func distanceKm(to: Coordinate) -> Double }
public struct HourlyUVI: Codable, Sendable, Equatable { public let time: Date; public let uvi: UVI }
public struct PostureFractions: Codable, Sendable { public let frontBackFraction: Double; public let shoulderFraction: Double }
public enum Application: Codable, Sendable, CaseIterable { case thin /*0.5*/, normal /*1.0*/, thick /*2.0 mg/cm²*/; public var density: Double }
public struct SunscreenChoice: Codable, Sendable, Equatable { public let spfLabel: Int; public let application: Application
    public var effectiveSPF: Double }    // pow(Double(spfLabel), application.density / 2)
public enum SunscreenConfirmation: Codable, Sendable, Equatable { case asPrescribed, alternative(SunscreenChoice), none }
public enum FigureKey: String, Codable, Sendable, CaseIterable { case headlineMinutes, sideMinutes, regionDose, remainingBudget, cycleDose, rangeLower, rangeUpper, uvaMultiple, shortfall, extraIfCovered }
public enum Unit: Sendable, Equatable { case minutes, sed, multiple }
public struct Figure: Sendable, Equatable { public let key: FigureKey; public let region: Region?; public let value: Double; public let unit: Unit; public let reads: Set<String>; public var isEstimate: Bool
    public var assumptionKeys: [String] }     // isEstimate == !assumptionKeys.isEmpty == reads ∩ Tunables.assumptionKeys ≠ ∅
public enum CopyKey: String, Codable, Sendable, CaseIterable {
    // outcomes: planBareSubWindow, planStayWearThis, tooWeak, noViableWindow, windowPassed, budgetSpent, missingForecast
    // notices: staleHeadsUp, staleWarn, staleFarFromCache, escalationRisen, toleranceDropped, ceilingReached, underDosed, maintenance,
    //          thinMargin, fairSkinPreCalibration, conservativeUntilCalibrated, aggressiveLocked, uvaHeavy, cloudCaveat, coverToRunLonger,
    //          boundByMelanogenic, boundByBurnLine, whichSideFirst, timerStoppedAtPlannedEnd, timerNeedsNotifications
    // warnings: warnPastTarget, warnReachesThreshold
    // sunscreen: sunscreenNotNeeded, sunscreenPrescribed, sunscreenApplicationBeatsLabel, uvaMultiple, reapply, nothingRealistic,
    //            alternativeWholeWindow, alternativeThickEnough, alternativeShadeForRest, didYouWearIt
    // prompts: didYouDoThisSession, noSessionToReport, immediateDarkeningExplained, revisitSkinType, pauseSuggested, reportRecorded
    // settings/history: sensitivitySentence, deleteHistoryWarning, trajectoryTitle, unreportedDays, privacyOptions
    // onboarding: onboardingWhyLocation, onboardingWhyNotifications, disclaimer
    // THIS LIST IS COMPLETE FOR EVERY PLAN. A later plan that needs a key adds it HERE and to docs/APP_COPY.md and lists both files.
}
public enum Basis: Sendable, Equatable { case citation(String), assumption(String) }
public struct Tunables: Sendable, Codable {
    public static let current: Tunables; public let version: String
    // dose
    public let uviMinutesPerSED: Double               // 66.7                     citation Module 4
    public let medBaselineSED: [SkinType: SED]        // I 2.0 II 2.5 III 3.0 IV 4.5 V 6.0 VI 10.0   citation BUILD_PROMPT §4.3 (authoritative; addendum's 3.5/5.0 NOT used)
    // target
    public let melanogenicFraction: [SkinBand: Double] // fair 1.0, medium 0.95, dark 0.75   assumption (addendum §5; Pathak & Fanselow 1983 solar ≈1.0 USED; Wulf 2010 solar-simulator 1.5–1.9 NOT used: outdoor app)
    public let ceilingScale: [Ceiling: Double]        // 0.75 / 0.90 / 1.0
    public let calibrationReports: Int                // 3
    public let aggressiveUnlockReports: Int           // 5
    public let uncertaintyBandAtZero: Double          // 0.30   citation Module 4 ("differ by 30% or more")
    // posture
    public let posture: PostureFractions              // frontBackFraction 0.5, shoulderFraction 0.5   assumption (geometry)
    public let sideDifferenceForTwoFigures: Double    // 0.15
    // adaptation
    public let riseTimeConstantDays: Double           // 7.2  assumption: solved WITH the F3 decay so 21 daily sessions at doseFraction 1.0 reach 0.8 (fair)
    public let riseMultiplier: [SkinBand: Double]     // fair 1.0, medium 1.0, dark 1.5
    public let decayHalfLifeDays: Double              // 21.0  assumption — Module 6 gives a 4–8 week fade; a 3-week half-life sits at the fast end so post-gap doses err shorter (V2)
    public let adaptationGain: [SkinBand: Double]     // fair 1.25, medium 1.25 (cap 2.25×), dark 2.0 (cap 3×)   citation Module 5/6 (SPF 2–3) for fair; assumption for dark
    public let plateauTanState: Double                // 0.75  assumption: "near saturation" = above the 5/wk fixed point, below daily saturation under F3
    public let tolerantCredit: Double                 // 0.5   assumption
    public let escalationNoticeFraction: Double       // 0.5 of the cap rise (T1)
    public let gapDays: Double                        // 14
    public let ceilingNoColourCount: Int              // 3
    public let maintenanceFraction: Double            // 0.7
    public let lastingColourRegionFraction: Double    // 0.5
    // calibration
    public let impliedRatio: [SkinAnswer: Double]     // faintPink 1.0 clearlyPink 1.5 redSore 2.5 blistered 4.0   assumption (build prompt §5.3 shape)
    public let reporterBands: [SkinAnswer: ClosedRange<Double>] // normal 0..<0.95, faintPink 0.95..<1.15, clearlyPink 1.15..<2.0, redSore 2.0..<4.0, blistered 4.0...   (S3 fixture; inverse of impliedRatio)
    public let k: Double                              // 2.5
    public let nCap: Int                              // 20
    public let burnWeight: Double                     // 2.0
    public let multiplierClamp: ClosedRange<Double>   // 0.5...1.8
    public let confoundedDiscount: Double             // 0.25
    public let blisterProtectiveFactor: Double        // 0.8
    public let blisterPauseDays: Int                  // 4
    // sunscreen
    public let densityDefault: Double                 // 1.0 mg/cm²   citation Module 8
    public let spfLadder: [Int]                       // [15, 20, 30, 50]
    public let realisticMaxSPF: Int                   // 50 (applied normally)
    public let reapplicationIntervalHours: Double     // 2
    // staleness / fetch / horizon
    public let staleHeadsUpHours: Double              // 3
    public let staleWarnHours: Double                 // 6
    public let staleRangeWiden: Double                // 1.5
    public let staleReduction: Double                 // 0.05
    public let staleDistanceKm: Double                // 25
    public let fetchMinIntervalHours: Double          // 1
    public let fetchMoveKm: Double                    // 10
    public let forecastHorizonDays: Int               // 10
    public let viabilityFraction: Double              // 0.5
    public let uvaHeavyHoursFromNoon: Double          // 3   assumption
    // prompts
    public let skinCheckDelayHours: Double            // 20
    public let lastingColourDelayDays: Double         // 4
    public let inAppSkinCheckWindowHours: ClosedRange<Double>    // 12...72
    public let inAppLastingColourWindowDays: ClosedRange<Double> // 3...10
    public static let provenance: [String: Basis]     // key = property name; every stored property present (S1)
    public static var assumptionKeys: Set<String>
}
public enum ForecastCurveError: Error, Equatable { case tooFewSamples, unsorted }
public struct ForecastCurve: Codable, Sendable {
    public let location: Coordinate; public let timeZone: TimeZone        // the location's zone, from the provider
    public let fetchedAt: Date; public let horizonEnd: Date
    public let hourly: [HourlyUVI]                                        // sorted, ≥ 2 samples, as received
    public init(location:, timeZone:, fetchedAt:, hourly:, solarNoon: [DayKey: Date]) throws
    public func uvi(at: Date) -> UVI                                      // linear interpolation; 0 outside the samples
    public func sed(from: Date, to: Date) -> SED                          // prefix-integral difference at 1-minute resolution; from ≥ to → 0
    public func solarNoon(on: DayKey) -> Date                             // stored, else computed by the NOAA formula from location and day
    public func day(_ date: Date) -> DayKey                               // DayKey(date, timeZone)
    public func stored(for day: DayKey) -> StoredCurve
}
public struct StoredCurve: Codable, Sendable, Equatable {               // an EXTERNAL format (export v1); changes bump formatVersion
    public let hourly: [HourlyUVI]          // every sample from day.start() to day.end() + 6 h
    public let solarNoon: Date; public let timeZoneID: String; public let location: Coordinate; public let fetchedAt: Date
    public func curve() throws -> ForecastCurve
}
public enum DoseCalculator {
    public static func durationFrom(_ start: Date, targetSED: SED, curve:, notAfter: Date) -> Double?
        // smallest d (minutes, interpolated within the last minute) with sed(start, start+d) ≥ target; nil if none before notAfter
    public static func bestSubWindow(curve:, within: Window, now: Date, targetSED: SED, tunables:) -> Window?
        // durationFrom minimised over start minutes ≥ now; ties → nearest solar noon; nil if the window from now cannot deliver the target
    public static func isViable(curve:, window: Window, now: Date, targetSED: SED, tunables:) -> Bool
        // sed(max(start, now) → end) ≥ viabilityFraction × targetSED
    public static func nextViableWindow(curve:, after: Date, targetSED: SED, tunables:) -> Window?
        // first hour-aligned 3 h block ≥ after within horizonEnd whose sed ≥ viabilityFraction × target; nil if none
    public static func isUVAHeavy(window: Window, solarNoon: Date, tunables:) -> Bool
    public static func clip(_ window: Window, toStartNoEarlierThan now: Date) -> Window?   // nil if window.end ≤ now
}

// Promises the tests hold (S1, S6):
//  Tunables: every stored property has a provenance entry; assumptionKeys == the keys whose basis is .assumption
//  sed(analytic ramp) within 0.5% of the closed form; steep-then-flat 14–17 window ≠ endpoint mean and equals the trapezoid;
//  type II, m=1.0, standard, UVI 7 steady → bestSubWindow.minutes within ±0.5 of 21.44 (interpolated end, not a whole-minute grid);
//  on a rising 09:00–12:00 curve bestSubWindow ends at 12:00; on eveningFalling it starts at `now`;
//  clip returns nil for a passed window, shortened for a partial one; nextViableWindow never returns a start beyond horizonEnd;
//  DayKey(23:30Z, UTC) != DayKey(23:30Z, America/Los_Angeles); replay results are identical on any host time zone (S3 runs the suite under TZ=UTC and TZ=Pacific);
//  solarNoon(on:) for a day the provider did not supply returns the NOAA value within 5 minutes of a known reference;
//  StoredCurve.curve() round-trips sed(a, b) for any a, b inside its span within 1e-9.
```

### Internals

```text
Package.swift / project.yml / ci.yml as in the layout note; project.yml:
  deploymentTarget iOS "18.0"; packages: { Icarus: { path: "." } };
  ProjectIcarus sources [App] (move Sources/ContentView.swift & ProjectIcarusApp.swift to App/); dependencies: package Icarus product IcarusUI
  ProjectIcarusTests sources [Tests/AppTests]
  schemes.ProjectIcarus.test.targets: [ProjectIcarusTests, {package: Icarus/IcarusCoreTests}, {package: Icarus/IcarusDataTests},
                                       {package: Icarus/IcarusContentTests}, {package: Icarus/IcarusUITests}, {package: Icarus/IcarusAdsTests}]   // tactical #31
ci.yml: job core-tests (ubuntu-latest, swift-actions/setup-swift@v2 Swift 6.0): `swift test --filter 'IcarusCoreTests|IcarusContentTests|IcarusDataTests'`
  gated by swift-changed; macOS `test` unchanged; test-the-tests unchanged (Sources/ and Tests/ remain the dirs)

ForecastCurve.init: validate sorted, ≥ 2; horizonEnd = hourly.last.time
  prefixSED: [Double] computed in init at minute resolution from hourly.first.time (excluded from CodingKeys; tactical #27)
uvi(at t): binary-search bracket; linear interpolate; 0 outside
sed(a, b): b ≤ a → 0; interp(prefix, b) − interp(prefix, a) with linear tails inside a minute
solarNoon(on day): stored[day] ?? noaaSolarNoon(location, day)   // NOAA equation-of-time formula, ±5 min
durationFrom(start, target, notAfter): k = first prefix index with prefix[k] − prefix(start) ≥ target; if none or start+k > notAfter → nil
  d = (k − 1) + (target − (prefix[k−1] − p0)) / (prefix[k] − prefix[k−1]) minutes    // tactical #29
bestSubWindow(curve, within, now, target): w = clip(within, now) ?? nil; best = argmin over start minutes s in w of durationFrom(s, target, notAfter: w.end); ties by |mid − solarNoon(day(s))|
isViable / nextViableWindow / isUVAHeavy / clip as in Signatures
Tests/Fixtures/Curves.swift: steadyUVI(7), ramp (analytic ∫), steepThenFlat14to17, eveningFalling, morningRising, winterLow, tenDayLow, beachFlatUVI8
```

## Slice 2 — Target and exposure: per-region budgets, attenuation, the coupled per-side solve

- **Delivers:** For a profile, replayed state, posture, cover toggle, intent flag and today's dose, the engine returns per-region targets (R6 formula, scale, aggressive unlock, conservative-until-calibrated, stale reduction), the clipped range, the one attenuation function every logging path calls, and an exposure plan where every region limits: the best start minute is searched, lying-down sides are consecutive from that start, solved on their own sub-intervals and shortened until the head-and-shoulders credit fits; up-and-about limited by head-and-shoulders; warnings compare today's total and only when the user means to stay; nil only when an exposed region has no budget.
- **Files:** `Sources/IcarusCore/Models/Profile.swift`, `Sources/IcarusCore/Models/DerivedState.swift`, `Sources/IcarusCore/TargetModel.swift`, `Sources/IcarusCore/ExposureModel.swift`, `Tests/IcarusCoreTests/TargetModelTests.swift`, `Tests/IcarusCoreTests/ExposureModelTests.swift`
- **Estimate:** ~600 lines

### Signatures

```text
public struct Profile: Codable, Sendable, Equatable { public let skinType: SkinType; public var ceiling: Ceiling; public var manualMultiplier: Double? }
public struct RegionState: Codable, Sendable, Equatable {
    public var tanState: Double; public var lastExposure: Date?; public var cycleStart: DayKey?; public var rednessBoundInCycle: Bool
    public var noColourNearCeiling: Int; public var doseToday: SED; public var doseInCycle: SED; public var factorAtLastSession: Double
}
public struct DerivedState: Codable, Sendable, Equatable {
    public var multiplier: Double; public var reportCount: Int; public var totalReports: Int; public var rednessReportCount: Int
    public var regions: [Region: RegionState]; public var today: DayKey?; public var tunablesVersion: String
    public static func initial(tunables:) -> DerivedState
}
public enum BoundBy: Codable, Sendable { case melanogenic, burnLine }
public struct RegionTarget: Sendable, Equatable {
    public let region: Region; public let medPersonal: SED; public let melanogenic: SED
    public let target: SED                 // min(melanogenic, medPersonal) × scale × (stale ? 1−staleReduction : 1)
    public let boundBy: BoundBy; public let scaleUsed: Double
    public let remaining: SED              // max(0, target − doseToday)
    public let range: ClosedRange<SED>; public let rangeClipped: Bool
}
public protocol TargetGoal: Sendable {   // the seam for M8; TanningGoal is the only conformer now
    func target(for region: Region, profile: Profile, state: DerivedState, now: Date, stale: Bool, tunables: Tunables) -> RegionTarget
    var copyKey: CopyKey { get }
}
public struct TanningGoal: TargetGoal {
    public static func effectiveScale(profile:, state:, tunables:) -> (scale: Double, conservativeForced: Bool, aggressiveRefused: Bool)
        // conservative until state.totalReports ≥ calibrationReports; aggressive refused unless totalReports ≥ aggressiveUnlockReports AND any region.rednessBoundInCycle
    public static func adaptationFactor(_ region: RegionState, skinType:, tunables:) -> Double   // 1 + gain(band) × tanState
}
public struct ExposureRequest: Sendable {
    public let window: Window; public let now: Date; public let posture: Posture; public let firstSide: Side; public let coverHeadAndShoulders: Bool
    public let intent: Intent; public let targets: [Region: RegionTarget]; public let doseToday: [Region: SED]; public let curve: ForecastCurve
}
public struct SideAllocation: Sendable, Equatable { public let exposure: Exposure; public let window: Window; public let doses: [Region: SED] }
public struct ExposurePlan: Sendable, Equatable {
    public let sides: [SideAllocation]; public let perRegionDose: [Region: SED]; public let limitingRegion: Region
    public let span: Window                          // sides.first.start … sides.last.end
    public let totalMinutes: Double; public let showTwoFigures: Bool; public let extraMinutesIfCovered: [Side: Double]
    public let warnings: [Warning]
}
public enum Warning: Sendable, Equatable { case pastTarget(Region, dayTotal: SED), reachesThreshold(Region, dayTotal: SED) }
public enum ExposureModel {
    public static func dose(_ exposure: Exposure, coverHeadAndShoulders: Bool, over w: Window, curve:, tunables:) -> [Region: SED]
        // lying(.faceUp): front = full, headAndShoulders = full, back = 0; lying(.faceDown): back = full, headAndShoulders = shoulderFraction × full, front = 0
        // upAndAbout: headAndShoulders = full; front = back = frontBackFraction × full; cover → headAndShoulders = 0 in every case
    public static func attenuated(_ bare: [Region: SED], sunscreen: SunscreenChoice?, coverHeadAndShoulders: Bool) -> [Region: SED]
        // every region ÷ sunscreen.effectiveSPF (nil → ÷ 1); headAndShoulders = 0 when covered. THE function every logging path calls.
    public static func solve(_ r: ExposureRequest, tunables:) -> ExposurePlan?
        // nil when any region that receives dose in this posture (cover applied) has remaining ≤ 0
    public static func warnings(entered: Window, r: ExposureRequest, tunables:) -> [Warning]
        // only when intent == .stayWholeWindow; per region total = doseToday + dose over `entered`; total ≥ medPersonal → .reachesThreshold else total > target → .pastTarget
}

// Promises (S1, S5, S6):
//  type IV m=1 UVI 7 standard: target/med < type II's; boundBy == .melanogenic for IV, .burnLine for II; type III standard binds .melanogenic (0.95 × 0.9)
//  every (type, ceiling): target ≤ medPersonal; the selector changes target for every type
//  attenuated(x, 50 normal, cover: false) == x / 7.07 per region within 1e-9; attenuated(x, nil, cover: true)[.headAndShoulders] == 0
//  upAndAbout on morningRising 09:00–12:00: plan.span ends at 12:00 (best minutes, not first minutes)
//  lying on morningRising: sides consecutive, side 2 starts at side 1's end, both inside the window
//  lying, flat UVI, equal regions, no H&S limit: total == 2 × side, one figure; sloping: two figures beyond 15%
//  lying: headAndShoulders dose == faceUp dose + 0.5 × faceDown dose and ≤ its remaining; when it limited, sides are shorter than their independent optima and extraMinutesIfCovered > 0
//  upAndAbout: limitingRegion == .headAndShoulders unless covered
//  second session: remaining = target − doseToday drives the solve; front remaining 0 and H&S remaining > 0 in lying → nil (not a crash)
//  warnings: intent .bestMinutes → []; .stayWholeWindow with doseToday 2.0 and window 2.0 on target 2.25 / MED 2.5 → .reachesThreshold(front, 4.0)
//  range.upperBound ≤ medPersonal; rangeClipped when the raw band exceeds it; upper narrows only as rednessReportCount grows
```

### Internals

```text
TanningGoal.target(region): rs = state.regions[region]; af = adaptationFactor(rs); m = profile.manualMultiplier ?? state.multiplier
  med = baseline[skinType] × m × af; mel = med × melanogenicFraction[band]; (scale, forced, refused) = effectiveScale
  target = min(mel, med) × scale × (stale ? 1 − staleReduction : 1); boundBy = mel < med ? .melanogenic : .burnLine
  h0 = uncertaintyBandAtZero; lowerH = h0 / (1 + totalReports/k); upperH = h0 / (1 + rednessReportCount/k)
  range = med×(1−lowerH) ... min(med×(1+upperH), med); rangeClipped = med×(1+upperH) > med; remaining = max(0, target − rs.doseToday)

The coupled lying-down solve (ruled D-2026-09-03-F2): scalar shrink by bisection on s ∈ (0, 1] of both sides' durations
  from their independent optima until every region's dose ≤ remaining (headAndShoulders credit included); 40 iterations; monotone so exact to a second.

ratio(region, dose) = remaining > 0 ? dose/remaining : (dose > 0 ? .infinity : 0)     // covered / zero-dose regions never limit (tactical #13)
solve(r):
  w = clip(window, now) ?? return nil
  exposedRegions = regions with dose > 0 in this posture after cover; if any exposed remaining ≤ 0 → return nil
  upAndAbout:
    for s in minute grid of w: d(s) = bisection over [0, w.end − s] on maxOverExposed(ratio) ≤ 1
    pick s minimising d(s) (ties → |mid − solarNoon|); sides = [SideAllocation(.upAndAbout, Window(s, s+d), doses)]
  lyingTurning (tactical #3):
    order = firstSide == .faceUp ? [.faceUp, .faceDown] : [.faceDown, .faceUp]; region(side) = faceUp ? .front : .back
    for s in minute grid of w:
      d1 = durationFrom(s, remaining[region(order[0])]) ?? (w.end − s); d2 = durationFrom(s + d1, remaining[region(order[1])]) ?? (w.end − s − d1)
    pick s minimising d1 + d2 subject to s + d1 + d2 ≤ w.end; sides consecutive from s
    if H&S credit (faceUp dose + shoulderFraction × faceDown dose, 0 if covered) > remaining[hs] → F2 shrink on (d1, d2)
    extraMinutesIfCovered = re-solve with cover on, per-side difference
  perRegionDose = Σ sides; limitingRegion = argmax ratio; span = first.start…last.end
  showTwoFigures = lying && |d1 − d2| / max(d1, d2) > sideDifferenceForTwoFigures
  warnings = warnings(entered: w, r) (empty unless stay)
warnings(entered, r): if intent != .stayWholeWindow → []; for region: total = doseToday[region] + dose over the region's share of `entered` (per posture, cover applied)
  total ≥ medPersonal → .reachesThreshold(region, total); else total > target → .pastTarget(region, total)     // tactical #5
```

## Slice 3 — Adaptation and calibration, replayed from the history

- **Delivers:** `Replay` folds an ordered history of sessions and reports into `DerivedState` under the current Tunables and returns the calibration effect of every report: tan state rises as a leaky integrator of dose-over-target (the target of the time, under the ceiling and override the session was planned with) and decays by elapsed time; tolerant surprises credit tan state first and the multiplier second; redness reports update the multiplier with the confidence-weighted, asymmetric, capped, `nCap`-windowed rule against the factor the day's plan used; "all exposed" redness takes the lowest-dose region; a report with no logged dose is recorded, never calibrated; Q2 reclassifies; confounders discount; blistering corrects; clamps prompt; the tan cycle starts and ends as defined; lasting-colour answers are placed by their own timestamp; plateau outcomes are reachable at the tunable plateau line; escalation and gap triggers are fractions of the cap rise. S3 and S4 simulations pass with the fixed reporter under the corrected constants.
- **Files:** `Sources/IcarusCore/Models/History.swift`, `Sources/IcarusCore/Models/SkinReport.swift`, `Sources/IcarusCore/AdaptationModel.swift`, `Sources/IcarusCore/CalibrationEngine.swift`, `Sources/IcarusCore/Replay.swift`, `Tests/IcarusCoreTests/AdaptationModelTests.swift`, `Tests/IcarusCoreTests/CalibrationEngineTests.swift`, `Tests/IcarusCoreTests/ReplayTests.swift`, `Tests/IcarusCoreTests/Fixtures/SimulatedUser.swift`
- **Estimate:** ~700 lines

### Signatures

```text
public enum SessionState: Codable, Sendable { case planned, logged, discarded }
public struct SessionRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID; public let day: DayKey; public let createdAt: Date
    public var plannedWindow: Window; public var actualWindow: Window?; public var firstSide: Side
    public var posture: Posture; public var coverHeadAndShoulders: Bool; public var intent: Intent
    public let ceilingAtPlan: Ceiling; public let manualMultiplierAtPlan: Double?   // replay INPUTS: the user's choices at the time (tactical #6)
    public var sunscreen: SunscreenChoice?            // confirmed at logging (nil = none)
    public var state: SessionState
    public var dosePerRegion: [Region: SED]           // after sunscreen and cover; stored, never recomputed
    public var factorsShown: [Region: Double]; public var targetsShown: [Region: SED]   // display records only (R22)
    public var curveUsed: StoredCurve; public var forecastFetchedAt: Date; public var forecastPlace: Coordinate
}
public enum SkinAnswer: Codable, Sendable, CaseIterable { case normal, faintPink, clearlyPink, redSore, blistered }
public enum RednessTiming: Codable, Sendable { case withinHourGoneByEvening, thatEvening, nextMorning, notSure }
public enum ReportRegion: Codable, Sendable { case front, back, headAndShoulders, allExposed }
public enum Confounder: Codable, Sendable, CaseIterable { case photosensitisingMedication, illness, waterOrSnow, altitude, alcohol }
public enum LastingColour: Codable, Sendable { case yes, aLittle, no }
public enum Channel: Codable, Sendable { case notification, inApp }
public struct SkinReport: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID; public let day: DayKey; public let reportedAt: Date
    public let answer: SkinAnswer; public let timing: RednessTiming?; public let region: ReportRegion
    public let confounders: Set<Confounder>; public let channel: Channel
    public var lastingColour: LastingColour?; public var lastingColourAt: Date?        // tactical #10
}
public struct History: Codable, Sendable, Equatable { public var sessions: [SessionRecord]; public var reports: [SkinReport]
    public func ordered() -> [HistoryEvent] }   // logged sessions by actualWindow.end; reports by reportedAt; lastingColour by lastingColourAt (absent → not emitted)
public enum HistoryEvent: Sendable { case session(SessionRecord), report(SkinReport), lastingColour(SkinReport) }

public enum AdaptationModel {
    public static func decayed(_ s: RegionState, to now: Date, tunables:) -> RegionState   // tanState × 0.5^(Δdays / halfLife); gap > gapDays → cycle ends (cycleStart nil, bound cleared, doseInCycle 0, noColour 0)
    public static func advanced(_ s: RegionState, doseFraction: Double /* dose ÷ target of the time */, skinType:, at: Date, tunables:) -> RegionState
        // tanState += (1 − tanState) × (1 − exp(−doseFraction × riseMultiplier[band] / riseTimeConstantDays))
    public static func creditTolerant(_ s: RegionState, excess: Double, tunables:) -> (RegionState, unabsorbed: Double)
    public static func escalationNotice(_ s: RegionState, skinType:, tunables:) -> EscalationNotice?
        // .risen when factor − 1 ≥ escalationNoticeFraction × gain(band) ; .dropped when a gap > gapDays cut the factor by ≥ that same amount from factorAtLastSession
    public static func plateauOutcome(_ s: RegionState, tunables:) -> PlateauOutcome?   // noColourNearCeiling ≥ ceilingNoColourCount && tanState ≥ plateauTanState → rednessBoundInCycle ? .ceiling : .underDosed
}
public enum EscalationNotice: Sendable, Equatable { case risen(factor: Double), dropped(fraction: Double) }
public enum PlateauOutcome: Sendable, Equatable { case ceiling, underDosed }

public enum CalibrationEngine {
    public static func apply(_ report: SkinReport, daySessions: [SessionRecord], state: DerivedState, skinType: SkinType, tunables:) -> (DerivedState, CalibrationEffect)
    public static func evidenceRegion(_ report: SkinReport, daySessions:) -> Region?
        // named region; .allExposed: answer == .normal → highest-dose region (strongest one-sided evidence); any redness → lowest-dose region with dose > 0 (tightest bound); nil when no dose that day
    public static func weight(n: Int, isBurn: Bool, tunables:) -> Double                 // min(1, (isBurn ? burnWeight : 1) × k / (min(n, nCap) + k))
}
public enum CalibrationEffect: Sendable, Equatable { case none, tanStateCredited(Region, Double), multiplierMoved(from: Double, to: Double), clampHit(revisitSkinType: Bool), blisterCorrection(from: Double, to: Double, pauseDays: Int), reclassifiedAsNormal, discounted, noDoseThatDay }

public enum Replay {
    public static func replay(_ h: History, skinType: SkinType, now: Date, tunables:) -> (state: DerivedState, effects: [UUID: CalibrationEffect])
        // pure function of its arguments; recomputes every factor and target from the history under each session's ceilingAtPlan / manualMultiplierAtPlan; ignores factorsShown/targetsShown; identical on any host time zone
}

// Promises (S3, S4, S10):
//  weight(0,·) == 1.0; weight(15, burn) == 2×2.5/17.5 ≈ 0.286; weight(100, burn) ≥ 0.11; non-burn floor at nCap ≈ 0.111
//  simulated true m=0.75 with the reporterBands: |m̂ − 0.75| ≤ 0.05 within 8 reports; normal outlier at 15 moves ≤ 0.05; redSore at 15 moves −0.10…−0.20
//  true m=1.0 truthful at standard for 20 reports: |m̂ − 1| ≤ 0.05; normal at ratio 1.2 with tanState < 1 → tanStateCredited, multiplier unchanged; at tanState 1 → multiplier rises ≤ excess
//  a report whose day has no logged dose → .noDoseThatDay, state unchanged; est uses factorAtLastSession (the pre-session factor), not the post-session one
//  evidenceRegion(.allExposed, redness) == the lowest-dose region with dose > 0; (.allExposed, .normal) == the highest
//  separation at true gain 0.7× and 1.3×: |m̂ − 1| ≤ 0.10 after 6 weeks; first post-gap recommendation ≤ true threshold
//  F3 with decay: 21 daily sessions at doseFraction 1.0 (fair) reach tanState 0.80 ± 0.02 under `decayed` then `advanced` with τ = riseTimeConstantDays
//  6 weeks × 5/wk at standard (type II): factor rises, < cap; escalation notice absent after week 1 and present by week 6; 1-week factor rise < 40% of the cap rise (T2); 4-week gap → dose ≥ 25% smaller and .dropped
//  8 weeks × 5/wk reaches tanState ≥ plateauTanState; then 3 × lastingColour .no (with lastingColourAt set) → .ceiling iff rednessBoundInCycle else .underDosed; a bound from a previous cycle does not count
//  changing profile.ceiling after N sessions leaves every region's tanState unchanged (targets replay under ceilingAtPlan)
//  Q2 .withinHourGoneByEvening + faintPink → .reclassifiedAsNormal; blistered → blisterCorrection at any n; m̂ < 0.5 → clampHit(revisitSkinType: true)
//  Replay under tunables A then B differs; effects[r.id] is present for every report
```

### Internals

```text
Discrete form of the leaky integrator (ruled D-2026-09-03-F3, constant corrected per T1): per-event update — decay by elapsed time,
  then the closed-form rise. riseTimeConstantDays = 7.2 is solved WITH one day of decay at half-life 21 between daily events so
  that 21 daily sessions at doseFraction 1.0 land at 0.80 (fair). Daily saturation ≈ 0.82, 5/wk fixed point ≈ 0.78 (computed by the
  test, asserted ±0.02); plateauTanState 0.75 sits below both, so R14's outcomes are reachable at 5/wk.

Replay.replay(h, skinType, now):
  state = DerivedState.initial; dayDose: [DayKey: [Region: (dose, target)]] = [:]
  for ev in h.ordered():
    .session(s) where s.state == .logged:
      profileThen = Profile(skinType, ceiling: s.ceilingAtPlan, manualMultiplier: s.manualMultiplierAtPlan)
      for region: rs = decayed(rs, to: s.actualWindow!.end)
        if rs.cycleStart == nil: cycleStart = s.day; rednessBound = false; doseInCycle = 0; noColour = 0
        rs.factorAtLastSession = adaptationFactor(rs)                       // BEFORE advancing (tactical #8b)
        target = TanningGoal.target(region, profileThen, state, now: s.actualWindow!.start, stale: false)
        dose = s.dosePerRegion[region]; rs = advanced(rs, doseFraction: dose / target.target)
        dayDose[s.day][region] = (dose, target.target); doseInCycle += dose; lastExposure = end
        rs.doseToday = (s.day == state.today) ? rs.doseToday + dose : dose ; state.today = s.day
    .report(r):
      sessions = logged sessions with day == r.day
      (state, effect) = CalibrationEngine.apply(r, daySessions: sessions, state, skinType); effects[r.id] = effect
    .lastingColour(r):
      for region where dayDose[r.day][region].dose / .target ≥ lastingColourRegionFraction:
        if r.lastingColour == .no && tanState ≥ plateauTanState → noColourNearCeiling += 1 else if yes/aLittle → 0
  final: every region decayed to now; if state.today != DayKey(now, that region's last session zone) → doseToday = 0
  state.tunablesVersion = tunables.version

CalibrationEngine.apply(r, daySessions, state, skinType):
  region = evidenceRegion(r, daySessions) ?? return (state, .noDoseThatDay)
  dose = Σ daySessions dosePerRegion[region]; guard dose > 0 else (state, .noDoseThatDay)
  ceilingThen / overrideThen = last session of the day; m = overrideThen ?? state.multiplier
  af = rs.factorAtLastSession; est = baseline[skinType] × m × af
  ratio = dose / est
  discount = r.confounders.isEmpty ? 1 : confoundedDiscount
  answer = (r.answer == .faintPink && r.timing == .withinHourGoneByEvening) ? .normal (effect .reclassifiedAsNormal) : r.answer
  if answer == .normal:
    if ratio ≤ 1.0 → .none
    excess = ratio − 1; (rs, unabsorbed) = creditTolerant(rs, excess)
    if unabsorbed > 0: implied = min(m × (1 + unabsorbed), m × ratio); m += discount × weight(n, burn: false) × (implied − m) → .multiplierMoved
    else → .tanStateCredited(region, rise)
  else:
    implied = m × ratio / impliedRatio[answer]; m += discount × weight(n, burn: true) × (implied − m)
    mark rednessBoundInCycle on region (allExposed → every region with dose that day); state.rednessReportCount += 1
    if answer == .blistered: m = min(m, implied × blisterProtectiveFactor) → .blisterCorrection(pauseDays: blisterPauseDays)
  clamp; clamp hit → .clampHit(revisitSkinType: true); if discount < 1 and effect == .none → .discounted
  state.totalReports += 1; state.reportCount = reports in current + previous cycle (by cycleStart of the limiting region)
escalationNotice / plateauOutcome as in Signatures
Fixtures/SimulatedUser.swift: trueMultiplier, trueGainScale; answers Q1 from true ratio via tunables.reporterBands; runs weeks through Replay under TZ variations
```

## Slice 4 — Sunscreen: prescribe, the UVA multiple, reapplication, and the honest alternative

- **Delivers:** `SunscreenSolver` prescribes the lowest ladder label whose normal-application effective SPF covers the required attenuation against the region's remaining budget, never thick; names the UVA multiple and reapplication times; the "I don't have that SPF" re-solve uses exactly what the user said they can manage and never suggests reapplying more often as a fix; the S2 numbers pass.
- **Files:** `Sources/IcarusCore/SunscreenSolver.swift`, `Tests/IcarusCoreTests/SunscreenSolverTests.swift`
- **Estimate:** ~260 lines

### Signatures

```text
public struct SunscreenAdvice: Sendable, Equatable {
    public let prescribed: SunscreenChoice          // label ∈ spfLadder, application .normal, ≤ realisticMaxSPF
    public let uvaMultiple: Double                  // wholeWindowMinutes / bareMinutes
    public let reapplyAt: [Date]; public let whyModerateSPF: CopyKey   // .sunscreenApplicationBeatsLabel
}
public enum SunscreenOutcome: Sendable, Equatable { case notNeeded(uvaHeavy: Bool), prescribe(SunscreenAdvice), nothingRealistic(requiredAttenuation: Double) }
public struct AlternativePlan: Sendable, Equatable {
    public let with: SunscreenChoice; public let coveredWindow: Window; public let shadeMinutes: Double
    public let coverHeadAndShoulders: Bool; public let reapplyAt: [Date]; public let copy: CopyKey   // .alternativeWholeWindow | .alternativeThickEnough | .alternativeShadeForRest
}
public enum SunscreenSolver {
    public static func outcome(rawSED: SED, budgetSED: SED, window: Window, bareMinutes: Double, uvaHeavy: Bool, tunables:) -> SunscreenOutcome
        // attenuation = raw/budget; ≤ 1 → .notNeeded; lowest label with pow(label, densityDefault/2) ≥ attenuation; none → .nothingRealistic
    public static func alternative(have: SunscreenChoice, rawSED:, budgetSED:, window:, curve:, tunables:) -> AlternativePlan
        // have.effectiveSPF ≥ attenuation → whole window with `have` (.alternativeThickEnough iff have.application == .thick, else .alternativeWholeWindow)
        // else coveredWindow = longest prefix with sed(start, t)/have.effectiveSPF ≤ budget; shade for the rest; cover H&S; reapply inside the covered window
    public static func reapplicationTimes(window:, tunables:) -> [Date]
}
// Promises (S2): effectiveSPF(50,.thick)=50, (50,.normal)≈7.07, (50,.thin)≈2.66; attenuation 8 → .nothingRealistic; attenuation 5 → SPF 30 (5.48 ≥ 5 > 4.47);
//  densityDefault is read (changing it to 2.0 makes attenuation 8 → SPF 15); uvaMultiple == whole/bare; reapplyAt non-empty iff window > 2 h;
//  alternative(have: 15 normal) for 3 h at UVI 8 → shadeMinutes > 0, coverHeadAndShoulders true, copy .alternativeShadeForRest, reapplyAt inside coveredWindow; no key ever says "reapply more often"
```

### Internals

```text
outcome: effective(label) = pow(Double(label), densityDefault / 2); first label in spfLadder with effective ≥ attenuation and label ≤ realisticMaxSPF
reapplicationTimes: start + k × reapplicationIntervalHours while < end
alternative as in Signatures; coveredWindow found by bisection on t over the prefix integral
```

## Slice 5 — The Planner: one typed result, the fixtures, and the performance bound

- **Delivers:** `Planner.plan` composes everything into one `DoseResult`: outcome type with copy key, headline and second answer per R15 (bare sub-window unless the user stays; the prescribed pair otherwise), the R17 edge cases against the remaining budget with the `noViableWindow` outcome actually produced, the R3 stale levels, the R13 notices with the cycle total, the plateau outcomes with maintenance, the R43 thin-margin key, per-figure provenance, and the use-case fixtures 1–6, 8, 9 (S18) pass. The S14 performance test passes.
- **Files:** `Sources/IcarusCore/Planner.swift`, `Sources/IcarusCore/Models/DoseResult.swift`, `Tests/IcarusCoreTests/PlannerTests.swift`, `Tests/IcarusCoreTests/PerformanceTests.swift`, `Tests/IcarusCoreTests/Fixtures/UseCases.swift`, `acceptance/S18-usecases.sh`, `acceptance/S1-core.sh`
- **Estimate:** ~560 lines

### Signatures

```text
public enum Outcome: Sendable, Equatable {
    case plan(ExposurePlan, sunscreen: SunscreenOutcome, headline: Headline)
    case tooWeak(shortfallSED: SED, nextViable: Window?)
    case noViableWindow(days: Int, peakUVI: UVI)
    case windowPassed
    case budgetSpent(Region)
    case missingForecast(ForecastFailureKind?)
}
public enum ForecastFailureKind: Sendable, Equatable { case provider, malformed, cacheUnreadable }
public enum Headline: Sendable, Equatable { case bareSubWindow, sunscreenForWholeWindow }
public enum StaleLevel: Sendable, Equatable { case fresh, headsUp(hours: Double), warn(hours: Double, farFromCache: Bool) }
public struct Notices: Sendable, Equatable { public let escalation: EscalationNotice?; public let plateau: PlateauOutcome?; public let maintenanceApplied: Bool
    public let uvaHeavy: Bool; public let stale: StaleLevel; public let thinMargin: Bool; public let conservativeForced: Bool; public let fairSkinPreCalibration: Bool; public let aggressiveRefused: Bool; public let cloudCaveat: Bool }
public struct DoseResult: Sendable, Equatable {
    public let outcome: Outcome; public let targets: [Region: RegionTarget]; public let notices: Notices
    public let figures: [Figure]; public let copyKeys: [CopyKey]; public let cycleDose: [Region: SED]
    public static let reads: Set<String>      // the union of every figure's reads for this outcome family (S1 provenance check)
}
public struct PlanRequest: Sendable {
    public let curve: ForecastCurve?; public let forecastFailure: ForecastFailureKind?; public let deviceLocation: Coordinate?; public let now: Date
    public let window: Window; public let posture: Posture; public let firstSide: Side; public let coverHeadAndShoulders: Bool
    public let intent: Intent; public let profile: Profile; public let state: DerivedState; public let goal: any TargetGoal
}
public enum Planner {
    public static func plan(_ req: PlanRequest, tunables:) -> DoseResult
    public static func staleLevel(curve:, now:, deviceLocation:, tunables:) -> StaleLevel
}
// Promises (S6, S14, S18):
//  windowPassed when window.end ≤ now; a partial window is solved from now (span.start ≥ now)
//  viability uses min(remaining, target): a second session with 0.3 SED remaining and a 0.5 SED window is a .plan, not .tooWeak
//  tooWeak carries shortfall from the melanogenic dose and nextViable (searched with the full target) within the horizon; when nextViable == nil the outcome is .noViableWindow(days: forecastHorizonDays, peakUVI: horizon max) — never a season claim
//  overshoot is judged against `remaining`; sunscreen budget is `remaining`
//  stale: 3 h → .headsUp; 6 h or 30 km or unknown location → .warn, targets reduced by staleReduction and range widened ×1.5; curve nil → .missingForecast(kind)
//  headline == .bareSubWindow iff intent == .bestMinutes when overshooting; .sunscreenForWholeWindow when staying
//  notices.thinMargin iff type I/II; fairSkinPreCalibration iff type I/II and totalReports < calibrationReports; escalation only when the factor passes the notice line
//  plateau non-nil → maintenanceApplied and targets × maintenanceFraction
//  figures: isEstimate iff reads ∩ assumptionKeys ≠ ∅; the range figure reads uncertaintyBandAtZero (a citation) and is not an estimate; DoseResult.reads equals the set the tests observe (a Tunables spy records every key read)
//  S18: each fixture's outcome type, headline minutes ±10%, per-region doses, and copy keys match; fixtures run under TZ=UTC and TZ=Europe/Oslo with identical results
//  S14: 100 plans on a cached curve < 100 ms each; replay of 200 records < 200 ms
```

### Internals

```text
Planner.plan(req):
  guard curve else return .missingForecast(req.forecastFailure)
  stale = staleLevel: age = now − fetchedAt; far = deviceLocation == nil || distanceKm > staleDistanceKm; age ≥ warn || far → .warn; age ≥ headsUp → .headsUp; else .fresh
  isStale = stale is .warn; targets = for region: goal.target(…, stale: isStale)
  if every region's remaining == 0 → .budgetSpent(limiting by doseToday)
  w = clip(window, now) ?? return .windowPassed
  exposureReq = ExposureRequest(w, now, posture, firstSide, cover, intent, targets, doseToday, curve)
  rawPerRegion = dose over the whole w per posture (stay-whole-window doses)
  plan = ExposureModel.solve(exposureReq) ?? return .budgetSpent(the exposed region with remaining 0)
  limiting = plan.limitingRegion; t = targets[limiting]
  viableBar = viabilityFraction × min(t.remaining, t.target)
  if rawPerRegion[limiting] < viableBar:
     nv = nextViableWindow(after: w.end, targetSED: t.target); if nv == nil → .noViableWindow(days: forecastHorizonDays, peakUVI: max uvi in horizon)
     else → .tooWeak(shortfall: t.melanogenic − rawPerRegion[limiting], nextViable: nv)
  overshoot = rawPerRegion[limiting] > t.remaining
  sunscreen = overshoot ? SunscreenSolver.outcome(rawSED: raw, budgetSED: t.remaining, w, bareMinutes: plan.totalMinutes, uvaHeavy) : .notNeeded(uvaHeavy)
  headline = overshoot && intent == .stayWholeWindow ? .sunscreenForWholeWindow : .bareSubWindow
  notices: escalation = escalationNotice(regions[limiting]); plateau = plateauOutcome(regions[limiting]); if plateau != nil → targets × maintenanceFraction, re-solve; maintenanceApplied
    thinMargin = skinType ∈ {i, ii}; fairSkinPreCalibration = thinMargin && totalReports < calibrationReports; conservativeForced / aggressiveRefused; cloudCaveat = true; uvaHeavy = isUVAHeavy(w, curve.solarNoon(on: curve.day(w.start)))
  figures: headline minutes; per-side minutes; per-region dose; remaining; cycleDose; range lower/upper; uvaMultiple; extraIfCovered — each built by a static builder that declares `reads`; Tunables access goes through a `TunablesReader` that records keys in tests
  copyKeys in display order: outcome, headline, warnings, notices, sunscreen keys, .cloudCaveat
acceptance/S1-core.sh: `swift test --filter 'IcarusCoreTests.(DoseCalculator|Tunables|TargetModel)'` and prints the provenance table
acceptance/S18-usecases.sh: `TZ=UTC swift test --filter UseCaseTests && TZ=Europe/Oslo swift test --filter UseCaseTests`
PerformanceTests: measure 100 × Planner.plan on a fixed curve; 200-record Replay
```
