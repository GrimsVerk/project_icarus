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
services; builds and tests on Linux and macOS alike.

Non-goals:
- We do NOT fetch weather, read location, persist anything, or schedule prompts (M2, M5).
- We do NOT render copy: outcomes carry `CopyKey`s, never strings (M3, M4).
- We do NOT build the vitamin D goal; we leave the `TargetGoal` seam it needs.

Owner costs:
- CI change (owner override merge): Core tests run on a Linux runner; the
  macOS `test` job keeps the app build; `project.yml` gains the package.

Rulings: D-2026-09-02 (revision 2 and 3 entries in docs/DECISIONS.md); pass-4 batch pending

## The slices

FORK F1 (structural, batch): package layout. TRUNK — one root `Package.swift`
with five library targets (`IcarusCore`, `IcarusData`, `IcarusContent`,
`IcarusAds`, `IcarusUI`) under `Sources/<Target>/` and `Tests/<Target>Tests/`,
and the app shell in `App/` referenced by `project.yml` as a local package at
`.`. Alternative — five separate packages under `Packages/`, each with its own
manifest; needs `TEST_THE_TESTS_IMPL_DIR`/`TEST_DIR` overrides per package and
five `swift test` invocations. The trunk keeps `Sources/` and `Tests/` as the
template's checks expect and makes `swift test --filter IcarusCoreTests` the
Linux command. Dependency enforcement is identical: target dependencies are
explicit in the manifest either way.

## Slice 1 — Dose from a curve: integrate, sub-window, viability, clock

- **Delivers:** Given a forecast curve, a window and the clock, the engine returns the SED over any interval by trapezoid on a one-minute interpolation, the best contiguous sub-window for a target dose starting no earlier than now, viability, the next viable window within the horizon, the UVA-heavy flag, and the "window has passed" outcome. The build prompt's 14:00–17:00 counter-example and the type II at UVI 7 ≈ 21 min check pass.
- **Files:** `Package.swift`, `Sources/IcarusCore/Tunables.swift`, `Sources/IcarusCore/Models/ForecastCurve.swift`, `Sources/IcarusCore/Models/Window.swift`, `Sources/IcarusCore/Models/SkinType.swift`, `Sources/IcarusCore/Models/Region.swift`, `Sources/IcarusCore/DoseCalculator.swift`, `Tests/IcarusCoreTests/DoseCalculatorTests.swift`, `Tests/IcarusCoreTests/Fixtures/Curves.swift`, `.github/workflows/ci.yml`, `project.yml`
- **Estimate:** ~520 lines

### Signatures

```text
// Package.swift: swift-tools-version 6.0; platforms [.iOS(.v18), .macOS(.v14)];
// products: five libraries; targets: IcarusCore (deps: none),
// IcarusContent (none), IcarusAds (none in Core sense; the SDK dep is added in M7),
// IcarusData (IcarusCore), IcarusUI (IcarusCore, IcarusData, IcarusContent, IcarusAds);
// test targets: IcarusCoreTests, IcarusDataTests, IcarusContentTests, IcarusUITests.

public typealias SED = Double            // 1 SED = 100 J/m² erythemal
public typealias UVI = Double

public struct Tunables: Sendable, Codable {
    public static let current: Tunables   // the one configuration; version bumps on any change
    public let version: String            // "1.0.0"
    // every field below has a `Basis` in `Tunables.provenance[key]`
    public let uviMinutesPerSED: Double               // 66.7   citation Module 4
    public let medBaselineSED: [SkinType: SED]        // I 2.0 II 2.5 III 3.0 IV 4.5 V 6.0 VI 10.0  citation BUILD_PROMPT §4.3 (authoritative; addendum's 3.5/5.0 NOT used)
    public let melanogenicFraction: [SkinBand: Double] // I–II 1.0, III 0.95, IV–VI 0.75  assumption (addendum §5; Pathak used, Wulf 1.5–1.9 not used)
    public let ceilingScale: [Ceiling: Double]        // conservative 0.75 standard 0.90 aggressive 1.0
    public let calibrationReports: Int                // 3
    public let aggressiveUnlockReports: Int           // 5
    public let uncertaintyBandAtZero: Double          // 0.30
    public let posture: PostureFractions              // upAndAbout front/back 0.5; lying shoulderFraction 0.5  assumption
    public let sideDifferenceForTwoFigures: Double    // 0.15
    public let riseTimeConstantDays: Double           // set so 5/wk at standard reaches 0.8 in ~21 d for I–III  assumption
    public let riseMultiplier: [SkinBand: Double]     // I–III 1.0, IV–VI 1.5
    public let decayHalfLifeDays: Double              // 21.0  citation Module 6 (fast end)
    public let adaptationGain: [SkinBand: Double]     // I–III 1.25 (cap 2.25×), IV–VI 2.0 (cap 3×)
    public let tolerantCredit: Double                 // 0.5  assumption
    public let escalationNoticeFraction: Double       // 0.10
    public let gapDays: Double                        // 14
    public let ceilingNoColourCount: Int              // 3
    public let maintenanceFraction: Double            // 0.7
    public let lastingColourRegionFraction: Double    // 0.5
    public let impliedRatio: [SkinAnswer: Double]     // faintPink 1.0 clearlyPink 1.5 redSore 2.5 blistered 4.0
    public let reporterBands: [SkinAnswer: ClosedRange<Double>] // normal <0.95 …  (S3 fixture; inverse of impliedRatio)
    public let k: Double                              // 2.5
    public let nCap: Int                              // 20
    public let burnWeight: Double                     // 2.0
    public let multiplierClamp: ClosedRange<Double>   // 0.5...1.8
    public let densityDefault: Double                 // 1.0 mg/cm²
    public let realisticMaxSPF: Int                   // 50 (applied normally)
    public let reapplicationIntervalHours: Double     // 2
    public let staleHeadsUpHours: Double              // 3
    public let staleWarnHours: Double                 // 6
    public let staleRangeWiden: Double                // 1.5
    public let staleReduction: Double                 // 0.05
    public let staleDistanceKm: Double                // 25
    public let fetchMinIntervalHours: Double          // 1
    public let fetchMoveKm: Double                    // 10
    public let forecastHorizonDays: Int               // 10
    public let viabilityFraction: Double              // 0.5
    public let uvaHeavyHoursFromNoon: Double          // 3  assumption
    public let warnPastTargetFraction: Double         // 1.0 (any excess over target warns)
    public let skinCheckDelayHours: Double            // 20
    public let lastingColourDelayDays: Double         // 4
    public let inAppSkinCheckWindowHours: ClosedRange<Double>   // 12...72
    public let inAppLastingColourWindowDays: ClosedRange<Double> // 3...10
    public static let provenance: [String: Basis]     // key = property name; every key present (S1)
}
public enum Basis: Sendable, Equatable { case citation(String), assumption(String) }
public enum SkinType: Int, CaseIterable, Codable, Sendable { case i = 1, ii, iii, iv, v, vi; public var band: SkinBand }
public enum SkinBand: Codable, Sendable { case fair /*I–II*/, medium /*III*/, dark /*IV–VI*/ }
public enum Region: CaseIterable, Codable, Sendable { case front, back, headAndShoulders }
public enum Side: Codable, Sendable { case faceUp, faceDown }
public struct Window: Codable, Sendable, Equatable { public let start: Date; public let end: Date; public var minutes: Double }

public struct ForecastCurve: Codable, Sendable {
    public let location: Coordinate
    public let fetchedAt: Date
    public let horizonEnd: Date
    public let hourly: [HourlyUVI]               // sorted, ≥ 2 samples, as received
    public let solarNoon: [DayKey: Date]
    public init(location:, fetchedAt:, hourly:, solarNoon:) throws   // throws .tooFewSamples, .unsorted
    public func uvi(at: Date) -> UVI              // linear interpolation; 0 outside the samples
    public func sed(from: Date, to: Date) -> SED  // trapezoid at 1-minute steps; from ≥ to → 0
    public func solarNoon(on: DayKey) -> Date?
}
public struct Coordinate: Codable, Sendable, Equatable { public let latitude: Double; public let longitude: Double
    public func distanceKm(to: Coordinate) -> Double }
public struct DayKey: Codable, Sendable, Hashable { public init(_ date: Date, calendar: Calendar) }

public enum DoseCalculator {
    public static func bestSubWindow(curve:, within: Window, now: Date, targetSED: SED) -> Window?
        // the shortest contiguous block ≥ now that delivers targetSED, ties → nearest solar noon; nil if the whole window from now delivers < targetSED
    public static func isViable(curve:, window: Window, now: Date, targetSED: SED, tunables:) -> Bool
        // sed(max(start, now) → end) ≥ viabilityFraction × targetSED
    public static func nextViableWindow(curve:, after: Date, targetSED: SED, tunables:) -> Window?
        // searches whole days within curve.horizonEnd for the first hour-aligned 3 h block that is viable; nil if none
    public static func isUVAHeavy(window: Window, solarNoon: Date, tunables:) -> Bool
        // |midpoint − solarNoon| > uvaHeavyHoursFromNoon
    public static func clip(_ window: Window, toStartNoEarlierThan now: Date) -> Window?   // nil if window.end ≤ now
}

// Promises the tests hold (S1, S6):
//  sed(analytic ramp) within 0.5% of the closed form; steep-then-flat 14–17 window ≠ endpoint mean and equals the trapezoid;
//  type II, m=1.0, standard, UVI 7 steady → bestSubWindow.minutes ≈ 21.4 (target 2.25 SED → 150 UVI·min → 21.4 min; tolerance ±0.5);
//  clip returns nil for a passed window, shortened for a partial one; nextViableWindow never returns a start beyond horizonEnd.
```

### Internals

```text
Package.swift
  tools 6.0; strict concurrency complete; platforms iOS 18, macOS 14 (Linux implicit)
  targets as in Signatures; IcarusCore has NO dependencies; test targets depend on their target only
project.yml
  deploymentTarget iOS "18.0"; packages: { Icarus: { path: "." } };
  ProjectIcarus target sources [App] (rename: move Sources/ContentView.swift & ProjectIcarusApp.swift to App/);
  dependencies: package Icarus product IcarusUI …; ProjectIcarusTests sources [Tests/AppTests] (placeholder moves there)
.github/workflows/ci.yml
  new job `core-tests` on ubuntu-latest: uses swift-actions/setup-swift@v2 (Swift 6.0); `swift test --filter 'IcarusCoreTests|IcarusContentTests'`
  gated by swift-changed like the macOS jobs; added to the ruleset later by the owner (owner cost)
  macOS `test` keeps xcodebuild test (app + UI/Data tests); `test-the-tests` unchanged (Sources/ and Tests/ still the dirs)

ForecastCurve.init: validate sorted, ≥2; horizonEnd = hourly.last.time
uvi(at t): binary search bracket; linear interpolate; clamp 0 outside
sed(from a, to b):
  if b ≤ a return 0
  step = 60 s; walk t from a to b at minute boundaries plus the exact endpoints
  sum trapezoids of uvi(t) over minutes → UVI·minutes; return / tunables.uviMinutesPerSED
  // cache: memoize prefix integral at minute resolution on first call (prefix[i] = sed(start, start+i min)); sed(a,b) = prefix(b) − prefix(a) with linear tails
bestSubWindow(curve, within, now, target):
  w = clip(within, now) ?? return nil
  if curve.sed(w.start, w.end) < target return nil
  // two-pointer on the minute grid: for each start minute, advance end until sed ≥ target; keep minimal length; tie-break by |mid − solarNoon(day)|
  return best
isViable: sed(clip(window,now)) ≥ viabilityFraction × target
nextViableWindow(after, target):
  for each day from DayKey(after) while dayStart < horizonEnd:
    for hour blocks [h, h+3h] with h ≥ after: if isViable → return block  // 3 h is the search granule; the Result copy uses the block's best sub-window
  return nil
isUVAHeavy: abs(mid − solarNoon) > uvaHeavyHoursFromNoon h
Tests/Fixtures/Curves.swift: steadyUVI(7), ramp (analytic ∫), steepThenFlat14to17 (build prompt), eveningFalling, winterLow, tenDayLow
```

## Slice 2 — Target and exposure: per-region budgets, the coupled per-side solve

- **Delivers:** For a profile, replayed state, posture, cover toggle, intent flag and today's dose, the engine returns per-region targets (R6 formula, scale, aggressive unlock, conservative-until-calibrated, stale reduction), the clipped range, and an exposure plan where every region limits: lying-down sides solved on their own sub-intervals and shortened until the head-and-shoulders credit fits; up-and-about limited by head-and-shoulders; warnings only when the user means to stay; the R43 thin-margin key for I–II.
- **Files:** `Sources/IcarusCore/Models/Profile.swift`, `Sources/IcarusCore/Models/DerivedState.swift`, `Sources/IcarusCore/TargetModel.swift`, `Sources/IcarusCore/ExposureModel.swift`, `Sources/IcarusCore/Models/Figure.swift`, `Tests/IcarusCoreTests/TargetModelTests.swift`, `Tests/IcarusCoreTests/ExposureModelTests.swift`
- **Estimate:** ~560 lines

### Signatures

```text
public enum Ceiling: Codable, Sendable { case conservative, standard, aggressive }
public struct Profile: Codable, Sendable { public let skinType: SkinType; public var ceiling: Ceiling; public var manualMultiplier: Double? }
public struct RegionState: Codable, Sendable, Equatable {
    public var tanState: Double            // 0...1
    public var lastExposure: Date?
    public var cycleStart: Date?
    public var rednessBoundInCycle: Bool
    public var noColourNearCeiling: Int
    public var doseToday: SED
    public var doseInCycle: SED
    public var factorAtLastSession: Double
}
public struct DerivedState: Codable, Sendable, Equatable {
    public var multiplier: Double          // starts 1.0
    public var reportCount: Int            // reports in current + previous cycle, uncapped here; nCap applied in weight
    public var totalReports: Int
    public var regions: [Region: RegionState]
    public var tunablesVersion: String
    public static func initial(now: Date, tunables:) -> DerivedState
}
public enum BoundBy: Codable, Sendable { case melanogenic, burnLine }
public struct RegionTarget: Sendable, Equatable {
    public let region: Region
    public let medPersonal: SED            // MED_baseline × multiplier × adaptationFactor
    public let melanogenic: SED
    public let target: SED                 // min(melanogenic, medPersonal) × scale × (stale ? 1−staleReduction : 1)
    public let boundBy: BoundBy
    public let scaleUsed: Double
    public let remaining: SED              // max(0, target − doseToday)
    public let range: ClosedRange<SED>     // uncertainty in medPersonal, upper clipped at medPersonal
    public let rangeClipped: Bool
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
public enum Intent: Codable, Sendable { case bestMinutes, stayWholeWindow }
public struct ExposureRequest: Sendable {
    public let window: Window; public let now: Date; public let posture: Posture; public let coverHeadAndShoulders: Bool
    public let intent: Intent; public let targets: [Region: RegionTarget]; public let curve: ForecastCurve; public let firstSide: Side
}
public enum Posture: Codable, Sendable { case lyingTurning, upAndAbout }
public struct SideAllocation: Sendable, Equatable { public let side: Side; public let window: Window; public let doses: [Region: SED] }
public struct ExposurePlan: Sendable, Equatable {
    public let sides: [SideAllocation]               // 1 for upAndAbout, 2 for lyingTurning
    public let perRegionDose: [Region: SED]
    public let limitingRegion: Region
    public let totalMinutes: Double
    public let showTwoFigures: Bool                  // lying: sides differ by > sideDifferenceForTwoFigures
    public let extraMinutesIfCovered: [Side: Double] // lying: how much longer each side could run with cover
    public let warnings: [Warning]                   // empty unless intent == .stayWholeWindow (or timer overrun, M3)
}
public enum Warning: Sendable, Equatable { case pastTarget(Region, SED), reachesThreshold(Region, SED) }
public enum ExposureModel {
    public static func solve(_ r: ExposureRequest, tunables:) -> ExposurePlan?
        // nil when no region has remaining budget > 0 (→ Planner returns .budgetSpent)
    public static func dose(of side: Side, over w: Window, curve:, tunables:) -> [Region: SED]
        // faceUp: front = full, headAndShoulders = full, back = 0; faceDown: back = full, headAndShoulders = shoulderFraction × full, front = 0
        // upAndAbout (single "side"): headAndShoulders = full; front = back = frontBackFraction × full
        // coverHeadAndShoulders → headAndShoulders = 0 in every case
    public static func warnings(for entered: Window, plan:, targets:, curve:, intent:, tunables:) -> [Warning]
}
public struct Figure: Sendable, Equatable { public let key: FigureKey; public let value: Double; public let unit: Unit; public let reads: Set<String>; public var isEstimate: Bool }
    // isEstimate == reads ∩ assumptionKeys ≠ ∅ ; every outcome declares `static let reads` (S1)

// Promises (S1, S5, S6):
//  type IV m=1 UVI 7 standard: target/med < type II's; boundBy == .melanogenic for IV, .burnLine for II
//  every (type, ceiling): target ≤ medPersonal; selector changes target for every type
//  lying, flat UVI, equal regions: total == 2 × side, one figure; sloping: two figures beyond 15%
//  lying: headAndShoulders dose == faceUp dose + 0.5 × faceDown dose, and ≤ its remaining budget; extraMinutesIfCovered > 0 when it limited
//  upAndAbout: limitingRegion == .headAndShoulders unless covered
//  second session: remaining = target − doseToday drives the solve
//  intent .bestMinutes → warnings == []; .stayWholeWindow with entered window past target → .pastTarget; reaching medPersonal → .reachesThreshold
//  range.upperBound ≤ medPersonal; rangeClipped when the raw band exceeds it
//  thin-margin: FigureKey/CopyKey .thinMargin present iff skinType ∈ {I, II}  (assembled by Planner, slice 4)
```

### Internals

```text
TanningGoal.target(region):
  rs = state.regions[region]; af = adaptationFactor(rs)
  m = profile.manualMultiplier ?? state.multiplier
  med = baseline[skinType] × m × af
  mel = med × melanogenicFraction[band]
  (scale, forced, refused) = effectiveScale
  target = min(mel, med) × scale × (stale ? (1 − staleReduction) : 1)
  boundBy = mel < med ? .melanogenic : .burnLine
  // uncertainty: half-width h = uncertaintyBandAtZero × shrink(state): lower shrinks with any report, upper with redness reports:
  //   lowerH = h0 / (1 + totalReports/k); upperH = h0 / (1 + rednessReports/k)   (rednessReports tracked in DerivedState via regions' bound count → add `rednessReportCount`)
  range = (med×(1−lowerH)) ... min(med×(1+upperH), med); clipped = raw upper > med
  remaining = max(0, target − rs.doseToday)

FORK F2 (structural, batch): the coupled lying-down solve. TRUNK — scalar shrink by bisection:
  let s ∈ (0, 1] scale both sides' durations from their independent optima; find the largest s such that every region's
  dose ≤ remaining (headAndShoulders credit included); 40 iterations of bisection on s; sides keep their own sub-intervals.
  Alternative — solve the two side durations as an LP under three linear constraints (exact, more code, no library on Linux).
  The trunk is monotone (dose grows with s) so bisection is exact to a second; picked for size and testability.

ExposureModel.solve(r):
  w = clip(window, now) ?? return nil
  switch posture:
   upAndAbout:
     // single interval starting at w.start; find the longest duration d such that for all regions dose(d) ≤ remaining
     d = bisection over [0, w.minutes] on maxOverRegions(dose/remaining) ≤ 1; if d == 0 → nil
     limiting = argmax(dose/remaining)
     sides = [SideAllocation(.faceUp /*label only*/, Window(w.start, w.start+d), doses)]
   lyingTurning:
     order = firstSide == .faceUp ? [.faceUp, .faceDown] : [.faceDown, .faceUp]
     // independent optima: for each side, the longest duration reaching its own regions' remaining (front for faceUp, back for faceDown), consecutive intervals
     d1*, d2* from bestSubWindow on the region's remaining target within w (side 1 from w.start; side 2 from side 1 end)
     if headAndShoulders credit (faceUp full + shoulderFraction × faceDown) ≤ remaining[hs] → s = 1 else bisection on s as F2
     sides = consecutive windows with d1 = s·d1*, d2 = s·d2*
     extraMinutesIfCovered = re-solve with cover on, difference per side
  perRegionDose = sum over sides; limitingRegion = argmax(dose/remaining)
  showTwoFigures = lying && |d1 − d2| / max(d1, d2) > sideDifferenceForTwoFigures
  warnings = intent == .stayWholeWindow ? warnings(entered: w, …) : []
warnings(entered): doses if the user stays the whole entered window (dose(of side over its share of w));
  for each region: if dose > target → .pastTarget; if dose ≥ medPersonal → .reachesThreshold (only the stronger one per region)
Figure.reads: each static outcome/figure builder lists its tunables keys; Tunables.assumptionKeys = provenance.filter(.assumption).keys
```

## Slice 3 — Adaptation and calibration, replayed from the history

- **Delivers:** `Replay` folds an ordered history of sessions and reports into `DerivedState` under the current Tunables: tan state rises as a leaky integrator of dose-over-target and decays by elapsed time, tolerant surprises credit tan state first and the multiplier second, redness reports update the multiplier with the confidence-weighted, asymmetric, capped, `nCap`-windowed rule, Q2 reclassifies, confounders discount, blistering corrects, clamps prompt; the tan cycle starts and ends as defined; escalation and gap triggers, ceiling and under-dosed outcomes, and maintenance are computed. S3 and S4 simulations pass with the fixed reporter.
- **Files:** `Sources/IcarusCore/Models/History.swift`, `Sources/IcarusCore/Models/SkinReport.swift`, `Sources/IcarusCore/AdaptationModel.swift`, `Sources/IcarusCore/CalibrationEngine.swift`, `Sources/IcarusCore/Replay.swift`, `Tests/IcarusCoreTests/AdaptationModelTests.swift`, `Tests/IcarusCoreTests/CalibrationEngineTests.swift`, `Tests/IcarusCoreTests/ReplayTests.swift`, `Tests/IcarusCoreTests/Fixtures/SimulatedUser.swift`
- **Estimate:** ~640 lines

### Signatures

```text
public struct SessionRecord: Codable, Sendable, Identifiable {
    public let id: UUID; public let day: DayKey
    public var plannedWindow: Window; public var actualWindow: Window?; public var firstSide: Side
    public var posture: Posture; public var coverHeadAndShoulders: Bool; public var intent: Intent
    public var sunscreen: SunscreenChoice?            // confirmed at logging
    public var state: SessionState                    // planned | logged | discarded
    public var dosePerRegion: [Region: SED]           // after sunscreen; stored, never recomputed
    public var factorsShown: [Region: Double]         // display record (R22)
    public var targetsShown: [Region: SED]            // display record
    public var curveUsed: StoredCurve                 // hourly UVI + solar noon for the day (R22)
    public var forecastFetchedAt: Date; public var forecastPlace: Coordinate
}
public enum SessionState: Codable, Sendable { case planned, logged, discarded }
public enum SkinAnswer: Codable, Sendable, CaseIterable { case normal, faintPink, clearlyPink, redSore, blistered }
public enum RednessTiming: Codable, Sendable { case withinHourGoneByEvening, thatEvening, nextMorning, notSure }
public enum ReportRegion: Codable, Sendable { case front, back, headAndShoulders, allExposed }
public enum Confounder: Codable, Sendable, CaseIterable { case photosensitisingMedication, illness, waterOrSnow, altitude, alcohol }
public struct SkinReport: Codable, Sendable, Identifiable {
    public let id: UUID; public let day: DayKey; public let reportedAt: Date
    public let answer: SkinAnswer; public let timing: RednessTiming?; public let region: ReportRegion
    public let confounders: Set<Confounder>; public var lastingColour: LastingColour?; public let channel: Channel
}
public enum LastingColour: Codable, Sendable { case yes, aLittle, no }
public enum Channel: Codable, Sendable { case notification, inApp }
public struct History: Codable, Sendable { public var sessions: [SessionRecord]; public var reports: [SkinReport]
    public func ordered() -> [HistoryEvent] }   // by time: logged sessions (actual end), reports (reportedAt)
public enum HistoryEvent: Sendable { case session(SessionRecord), report(SkinReport), lastingColour(SkinReport) }

public enum AdaptationModel {
    public static func decayed(_ s: RegionState, to now: Date, tunables:) -> RegionState   // tanState × 0.5^(Δdays / halfLife); cycle handling (gap > gapDays → cycle ends, bound flag cleared)
    public static func advanced(_ s: RegionState, doseFraction: Double /* dose ÷ target */, skinType:, at: Date, tunables:) -> RegionState
        // tanState += (1 − tanState) × (1 − exp(−doseFraction × riseMultiplier[band] / riseTimeConstantDays))
    public static func creditTolerant(_ s: RegionState, excess: Double, tunables:) -> (RegionState, unabsorbed: Double)
        // rise = min(1 − tanState, tolerantCredit × excess); unabsorbed = excess − rise/tolerantCredit
    public static func escalationNotice(_ s: RegionState, skinType:, tunables:) -> EscalationNotice?    // .risen(factor, cycleDose) | .dropped(byFraction) | nil
    public static func plateauOutcome(_ s: RegionState, tunables:) -> PlateauOutcome?                    // .ceiling | .underDosed | nil ; both imply maintenance
}
public enum EscalationNotice: Sendable, Equatable { case risen(factor: Double), dropped(fraction: Double) }
public enum PlateauOutcome: Sendable, Equatable { case ceiling, underDosed }

public enum CalibrationEngine {
    public static func apply(_ report: SkinReport, daySessions: [SessionRecord], state: DerivedState, profile:, tunables:) -> (DerivedState, CalibrationEffect)
    public static func evidenceRegion(_ report: SkinReport, daySessions:) -> Region        // named region, or the highest-dose region for .allExposed
    public static func weight(n: Int, isBurn: Bool, tunables:) -> Double                 // min(1, (isBurn ? burnWeight : 1) × k / (min(n, nCap) + k))
}
public enum CalibrationEffect: Sendable, Equatable { case none, tanStateCredited(Region, Double), multiplierMoved(from: Double, to: Double), clampHit(revisitSkinType: Bool), blisterCorrection(from: Double, to: Double, pauseDays: Int), reclassifiedAsNormal, discounted }

public enum Replay {
    public static func replay(_ h: History, profile:, now: Date, tunables:) -> DerivedState
        // deterministic; recomputes every factor and target from the history; ignores stored factorsShown/targetsShown
}

// Promises (S3, S4, S10):
//  weight(n:0, burn:false) == 1.0; weight(n:0, burn:true) == 1.0 (capped); weight(n:15, burn:true) == 2×2.5/17.5 ≈ 0.286; weight(n:100, burn:true) ≥ 0.11
//  simulated true m=0.75 with the S3 reporter bands: |m̂ − 0.75| ≤ 0.05 within 8 reports; normal outlier at 15 moves ≤ 0.05; redSore at 15 moves −0.10…−0.20
//  true m=1.0 truthful at standard for 20 reports: |m̂ − 1| ≤ 0.05; normal at ratio 1.2 with tanState < 1 → tanStateCredited, multiplier unchanged; at tanState 1 → multiplier rises ≤ excess
//  separation at true gain 0.7× and 1.3×: |m̂ − 1| ≤ 0.10 after 6 weeks; first post-gap recommendation ≤ true threshold
//  6 weeks × 5/wk at standard (type II): factor rises, < cap, escalation notice appears only after factor ≥ 1.10, 1-week factor rise < 25% of cap rise; 4-week gap → dose ≥ 25% smaller and .dropped notice
//  plateau: 3 × lastingColour .no near saturation → .ceiling iff rednessBoundInCycle else .underDosed; a bound from a previous cycle does not count
//  Q2 .withinHourGoneByEvening + faintPink → treated as .normal (.reclassifiedAsNormal)
//  blistered → blisterCorrection at any n; m̂ < 0.5 → clampHit(revisitSkinType: true)
//  Replay under tunables A then B differs; replay is a pure function of (history, profile, now, tunables)
```

### Internals

```text
FORK F3 (structural, batch): discrete form of the leaky integrator. TRUNK — per-event update with decay applied
  by elapsed time before each event (`decayed` then `advanced`), closed-form as in Signatures; riseTimeConstantDays is
  solved offline so that 21 daily sessions at doseFraction 1.0 land at tanState 0.8 for band .fair (τ ≈ 13.0 d, see test).
  Alternative — a daily-step simulation (integrate day by day). The trunk is exact for sparse events and O(events).

Replay.replay(h, profile, now):
  state = DerivedState.initial
  for ev in h.ordered():
    switch ev:
     .session(s) where s.state == .logged:
       for region: rs = decayed(rs, to: s.actualWindow.end)
         if cycle ended (gap > gapDays or nil cycleStart): cycleStart = s.day; rednessBound = false; doseInCycle = 0; noColourNearCeiling = 0
         target = TanningGoal.target(region, …, now: s.actualWindow.start, stale: false)  // recomputed from replayed state, NOT s.targetsShown
         rs = advanced(rs, doseFraction: s.dosePerRegion[region] / target.target)
         doseToday(day) += dose; doseInCycle += dose; lastExposure = end; factorAtLastSession = af
     .report(r):
       sessions = h.sessions.filter(day == r.day && logged)
       (state, effect) = CalibrationEngine.apply(r, daySessions: sessions, state, profile)
     .lastingColour(r):
       for region with doseFraction that day ≥ lastingColourRegionFraction: if r.lastingColour == .no && tanState ≥ 0.9 → noColourNearCeiling += 1 else if yes/aLittle → noColourNearCeiling = 0
  final decay of every region to `now`; doseToday recomputed for DayKey(now)
  state.tunablesVersion = tunables.version

CalibrationEngine.apply(r, daySessions, state):
  if r.confounders non-empty → weight × 0.25 (discount) and flag .discounted   // "heavily discounted"
  region = evidenceRegion(r, daySessions)
  dose = Σ daySessions dosePerRegion[region]; af = factor in force that day (replayed); est = medPersonal(region) at that day (replayed)
  ratio = dose / est
  answer = (r.answer == .faintPink && r.timing == .withinHourGoneByEvening) ? .normal (effect .reclassifiedAsNormal) : r.answer
  if answer == .normal:
     if ratio < 1.0 → .none
     excess = ratio − 1
     (rs, unabsorbed) = creditTolerant(rs, excess)
     if unabsorbed > 0: implied = m × (1 + unabsorbed) capped at m × ratio; m += weight(n, burn:false) × (implied − m)  → .multiplierMoved
     else → .tanStateCredited(region, rise)
     rednessBound unchanged
  else:
     implied = m × (ratio / impliedRatio[answer]) / 1   // threshold = dose / impliedRatio, normalised by af already inside est
     m += weight(n, burn: answer != .faintPink ? true : true /* all redness = burn evidence */) × (implied − m)
     regions[region].rednessBoundInCycle = true   (allExposed → every region with dose that day)
     if answer == .blistered: m = min(m, implied × 0.8); effect .blisterCorrection(pauseDays: 4)
  clamp m to multiplierClamp; if hit → .clampHit(revisitSkinType: true)
  state.reportCount = count of reports in current + previous cycle; totalReports += 1; rednessReportCount += (answer != .normal)
AdaptationModel.escalationNotice: factor − 1 ≥ escalationNoticeFraction → .risen; lastExposure gap > gapDays && factorAtLastSession − factor ≥ escalationNoticeFraction × factorAtLastSession → .dropped
plateauOutcome: noColourNearCeiling ≥ ceilingNoColourCount && tanState ≥ 0.9 → rednessBoundInCycle ? .ceiling : .underDosed
Fixtures/SimulatedUser.swift: trueMultiplier, trueGainScale; answers Q1 from true ratio via tunables.reporterBands; runs weeks of sessions through Replay
```

## Slice 4 — Sunscreen prescription and the Planner: one typed result

- **Delivers:** `Planner.plan` composes everything into one `DoseResult`: outcome type with copy key, headline and second answer per R15 (bare sub-window unless the user stays; the prescribed SPF and application otherwise), the "I don't have that SPF" re-solve, the UVA multiple and reapplication times, the R17 edge cases, the R3 stale outcomes, the R13 notices with the cycle total, the plateau outcomes with maintenance, the R43 thin-margin key, per-figure estimate labels, and the use-case fixtures 1–6, 8, 9 (S18) pass. The S14 performance test passes.
- **Files:** `Sources/IcarusCore/SunscreenSolver.swift`, `Sources/IcarusCore/Planner.swift`, `Sources/IcarusCore/Models/DoseResult.swift`, `Sources/IcarusCore/Models/CopyKey.swift`, `Tests/IcarusCoreTests/SunscreenSolverTests.swift`, `Tests/IcarusCoreTests/PlannerTests.swift`, `Tests/IcarusCoreTests/PerformanceTests.swift`, `acceptance/S18-usecases.sh`, `Tests/IcarusCoreTests/Fixtures/UseCases.swift`
- **Estimate:** ~700 lines

### Signatures

```text
public enum Application: Codable, Sendable, CaseIterable { case thin /*0.5*/, normal /*1.0*/, thick /*2.0 mg/cm²*/ ; public var density: Double }
public struct SunscreenChoice: Codable, Sendable, Equatable { public let spfLabel: Int; public let application: Application
    public var effectiveSPF: Double }    // pow(spfLabel, density/2)
public struct SunscreenAdvice: Sendable, Equatable {
    public let prescribed: SunscreenChoice          // ≤ realisticMaxSPF applied .normal; never .thick
    public let uvaMultiple: Double                  // wholeWindowMinutes / bareSubWindowMinutes
    public let reapplyAt: [Date]
    public let whyModerateSPF: CopyKey              // .sunscreenApplicationBeatsLabel
}
public enum SunscreenOutcome: Sendable, Equatable { case notNeeded(uvaHeavy: Bool), prescribe(SunscreenAdvice), nothingRealistic(requiredAttenuation: Double) }
public struct AlternativePlan: Sendable, Equatable {   // "I don't have that SPF"
    public let with: SunscreenChoice; public let coveredMinutes: Double; public let shadeMinutes: Double
    public let coverHeadAndShoulders: Bool; public let reapplyAt: [Date]; public let copy: CopyKey   // .alternativeThickEnough | .alternativeShadeForRest
}
public enum SunscreenSolver {
    public static func outcome(rawSED: SED, targetSED: SED, window: Window, bareMinutes: Double, uvaHeavy: Bool, tunables:) -> SunscreenOutcome
        // attenuation = raw/target; ≤ 1 → .notNeeded; choose the lowest label in [15, 20, 30, 50] whose effective (normal) ≥ attenuation; none → .nothingRealistic
    public static func alternative(have: SunscreenChoice, rawSED:, targetSED:, window:, curve:, tunables:) -> AlternativePlan
        // if have at .thick suffices → thick; else covered minutes = longest prefix whose attenuated dose ≤ target, rest is shade
    public static func reapplicationTimes(window:, tunables:) -> [Date]
}
public enum Outcome: Sendable, Equatable {
    case plan(ExposurePlan, sunscreen: SunscreenOutcome, headline: Headline)
    case tooWeak(shortfallSED: SED, nextViable: Window?)
    case noViableWindow(days: Int, peakUVI: UVI)
    case windowPassed
    case budgetSpent
    case missingForecast
}
public enum Headline: Sendable, Equatable { case bareSubWindow, sunscreenForWholeWindow }
public struct Notices: Sendable, Equatable { public let escalation: EscalationNotice?; public let plateau: PlateauOutcome?; public let maintenanceApplied: Bool
    public let uvaHeavy: Bool; public let stale: StaleLevel; public let thinMargin: Bool; public let conservativeForced: Bool; public let fairSkinPreCalibration: Bool; public let aggressiveRefused: Bool; public let cloudCaveat: Bool }
public enum StaleLevel: Sendable, Equatable { case fresh, headsUp(hours: Double), warn(hours: Double, farFromCache: Bool) }
public struct DoseResult: Sendable, Equatable {
    public let outcome: Outcome; public let targets: [Region: RegionTarget]; public let notices: Notices
    public let figures: [Figure]; public let copyKeys: [CopyKey]; public let cycleDose: [Region: SED]
}
public struct PlanRequest: Sendable {
    public let curve: ForecastCurve?; public let deviceLocation: Coordinate?; public let now: Date
    public let window: Window; public let posture: Posture; public let firstSide: Side; public let coverHeadAndShoulders: Bool
    public let intent: Intent; public let profile: Profile; public let state: DerivedState; public let goal: any TargetGoal
}
public enum Planner {
    public static func plan(_ req: PlanRequest, tunables:) -> DoseResult
    public static func staleLevel(curve:, now:, deviceLocation:, tunables:) -> StaleLevel
}
public enum CopyKey: String, Codable, Sendable, CaseIterable { /* one case per outcome, notice, warning, headline, alternative; e.g. .planBareSubWindow, .planStayWearThis, .tooWeak, .noViableWindow, .windowPassed, .budgetSpent, .staleHeadsUp, .staleWarn, .escalationRisen, .toleranceDropped, .ceilingReached, .underDosed, .maintenance, .thinMargin, .fairSkinPreCalibration, .conservativeUntilCalibrated, .aggressiveLocked, .warnPastTarget, .warnReachesThreshold, .uvaHeavy, .uvaMultiple, .reapply, .sunscreenNotNeeded, .nothingRealistic, .alternativeThickEnough, .alternativeShadeForRest, .cloudCaveat, .coverToRunLonger, .boundByMelanogenic, .boundByBurnLine */ }

// Promises (S2, S6, S14, S18):
//  effectiveSPF(50,.thick)=50, (50,.normal)≈7.07, (50,.thin)≈2.66; attenuation 8 → .nothingRealistic; both suffice → prescribes 30 normal over 50 thin
//  uvaMultiple == whole/bare; reapplyAt non-empty iff window > 2 h
//  alternative(have: 15 thick) for 3 h at UVI 8: thick insufficient → shadeMinutes > 0 and coverHeadAndShoulders == true; never suggests "reapply more" as a fix
//  windowPassed when window.end ≤ now; partial window solved from now
//  tooWeak carries shortfall from melanogenic dose and nextViable within horizon; noViableWindow.days == forecastHorizonDays and never claims a season (no such key)
//  stale: 3 h → .headsUp; 6 h or 30 km → .warn, targets reduced by staleReduction and range widened ×1.5; curve nil → .missingForecast
//  headline == .bareSubWindow iff intent == .bestMinutes when overshooting; .sunscreenForWholeWindow when staying
//  notices.thinMargin iff type I/II; fairSkinPreCalibration iff type I/II and totalReports < 3
//  figures: isEstimate true iff reads ∩ assumptionKeys ≠ ∅; a plain SED figure that reads only cited keys is not an estimate
//  S18: each fixture's outcome type, headline minutes ±10%, per-region doses, and copy keys match
//  S14: 100 plans on a cached curve < 100 ms each; replay of 200 records < 200 ms
```

### Internals

```text
Planner.plan(req):
  guard curve else return DoseResult(.missingForecast …)
  stale = staleLevel(curve, now, deviceLocation): age = now − fetchedAt; far = deviceLocation?.distanceKm(curve.location) > staleDistanceKm || deviceLocation == nil
    age ≥ warn || far → .warn; age ≥ headsUp → .headsUp; else .fresh
  isStale = stale is .warn
  targets = for region: goal.target(region, profile, state, now, stale: isStale)
  if all remaining == 0 → .budgetSpent
  w = clip(window, now) ?? .windowPassed
  rawPerRegion = ExposureModel.dose over the whole w for the posture (stay-whole-window doses)
  plan = ExposureModel.solve(request with targets) — with widened range if stale
  melShortfall check: if for the limiting region rawPerRegion < viabilityFraction × melanogenic → .tooWeak(shortfall: melanogenic − raw, nextViable: nextViableWindow(after: w.end))
  overshoot = rawPerRegion[limiting] > target[limiting].target
  sunscreen = overshoot ? SunscreenSolver.outcome(raw, target, w, bare: plan.totalMinutes, uvaHeavy) : .notNeeded(uvaHeavy)
  headline = overshoot && intent == .stayWholeWindow ? .sunscreenForWholeWindow : .bareSubWindow
  notices: escalation = AdaptationModel.escalationNotice(limiting region state); plateau = plateauOutcome(limiting)
    if plateau != nil → targets scaled by maintenanceFraction and plan re-solved; maintenanceApplied = true
    thinMargin = skinType ∈ {i, ii}; fairSkinPreCalibration = thinMargin && totalReports < calibrationReports
    conservativeForced / aggressiveRefused from TanningGoal.effectiveScale
    cloudCaveat = true always (copy); uvaHeavy = isUVAHeavy(w, solarNoon)
  figures: headline minutes (reads: uviMinutesPerSED, medBaselineSED, melanogenicFraction, ceilingScale, posture.* …) → isEstimate computed;
           per-region dose figures; cycleDose figures; range figure (reads uncertaintyBandAtZero → assumption? NO: cite Module 11 → citation)
  copyKeys assembled in display order: outcome key, headline key, warnings, notices, sunscreen keys, .cloudCaveat
SunscreenSolver.outcome: labels = [15, 20, 30, 50]; attenuation = raw/target; pick first label with pow(label, 0.5) ≥ attenuation; reapplyAt = every reapplicationIntervalHours from w.start while < w.end
SunscreenSolver.alternative(have): eff = have.effectiveSPF; if pow(label, 1.0) [thick] ≥ attenuation → .alternativeThickEnough with .thick
   else: coveredMinutes = longest prefix t with curve.sed(w.start, t)/eff ≤ target; shadeMinutes = w.minutes − covered; coverHeadAndShoulders = true; reapply within covered
acceptance/S18-usecases.sh: `swift test --filter IcarusCoreTests.UseCaseTests` and prints the fixture table (exit 0 iff all pass)
PerformanceTests: measure 100 × Planner.plan on a fixed curve; 200-record Replay
```
