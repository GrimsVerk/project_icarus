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
services; builds and tests on Linux and macOS alike. Revision 3 lands the
second tactical pass (`tactical-2.md`, `implementation-check-2.md`).

Non-goals:
- We do NOT fetch weather, read location, persist anything, or schedule prompts (M2, M5).
- We do NOT render copy: outcomes carry `CopyKey`s, never strings (M3, M4).
- We do NOT build the vitamin D goal; we leave the `TargetGoal` seam it needs.

Owner costs:
- CI change (owner override merge): Core tests run on a Linux runner; the
  macOS `test` job keeps the app build; `project.yml` gains the package.

Rulings: D-2026-09-03-F1..F8, T1, T3, T4, T5, T6 (docs/DECISIONS.md); T2 superseded by T6

## The slices

Layout (ruled D-2026-09-03-F1): one root `Package.swift` with five library
targets under `Sources/<Target>/` and `Tests/<Target>Tests/`, and the app shell
in `App/`. On Linux the manifest declares only `IcarusCore`, `IcarusContent`
and `IcarusData` (and their tests); `IcarusUI`, `IcarusAds` and their
dependencies exist only under `#if !os(Linux)` in the manifest. Tests are XCTest
(F5). Engine, content and data tests run on a Linux CI job, `core-tests` (F6).
Every type any later plan names is declared in Slice 1, so no slice stubs
another's types. Every payload-free enum in a record type has a `String` raw
value so the export format is a JSON object, never an array of alternating
keys and values.

## Slice 1 — Models, Tunables, and dose from a curve: integrate, sub-window, viability, clock

- **Delivers:** Every shared value type exists with its full declaration, including the record types and the export-facing `StoredCurve`; `Tunables` exposes every constant through a read that reports its key, so a test can record exactly what an outcome read, and carries one basis per stored number, band by band; given a forecast curve (with its location's time zone), a window and the clock, the engine returns the SED over any interval by trapezoid on a one-minute prefix integral, the shortest block for a target dose ending on an interpolated minute, viability, the next viable window within the horizon, the UVA-heavy flag, and the "window has passed" clip. `swift build` succeeds on Linux with placeholder files for the other targets.
- **Files:** `Package.swift`, `Sources/IcarusCore/Tunables.swift`, `Sources/IcarusCore/Models/Units.swift`, `Sources/IcarusCore/Models/DayKey.swift`, `Sources/IcarusCore/Models/ForecastCurve.swift`, `Sources/IcarusCore/Models/StoredCurve.swift`, `Sources/IcarusCore/Models/Window.swift`, `Sources/IcarusCore/Models/SkinType.swift`, `Sources/IcarusCore/Models/Region.swift`, `Sources/IcarusCore/Models/Sunscreen.swift`, `Sources/IcarusCore/Models/Reports.swift`, `Sources/IcarusCore/Models/CopyKey.swift`, `Sources/IcarusCore/Models/Figure.swift`, `Sources/IcarusCore/DoseCalculator.swift`, `Sources/IcarusData/IcarusData.swift`, `Sources/IcarusContent/IcarusContent.swift`, `Sources/IcarusAds/IcarusAds.swift`, `Sources/IcarusUI/IcarusUI.swift`, `Tests/IcarusDataTests/PlaceholderTests.swift`, `Tests/IcarusContentTests/PlaceholderTests.swift`, `Tests/IcarusAdsTests/PlaceholderTests.swift`, `Tests/IcarusUITests/PlaceholderTests.swift`, `Tests/IcarusCoreTests/DoseCalculatorTests.swift`, `Tests/IcarusCoreTests/TunablesTests.swift`, `Tests/IcarusCoreTests/DayKeyTests.swift`, `Tests/IcarusCoreTests/Fixtures/Curves.swift`, `.github/workflows/ci.yml`, `project.yml`
- **Estimate:** ~760 lines

### Signatures

```text
// Package.swift: swift-tools-version 6.0; platforms [.iOS(.v18), .macOS(.v14)]
// always: IcarusCore (deps none), IcarusContent (none; resources: [.copy("Resources")]), IcarusData (IcarusCore; test resources copied) + their test targets
// #if !os(Linux): IcarusAds (none until M7), IcarusUI (IcarusCore, IcarusData, IcarusContent, IcarusAds) + their test targets, and later MarkdownUI / Google Mobile Ads
// promise: `swift build` and `swift test` on Linux succeed with exactly Core, Content, Data (+tests) in `swift package describe`

public typealias SED = Double            // 1 SED = 100 J/m² erythemal
public typealias UVI = Double

public struct DayKey: Codable, Sendable, Hashable, Comparable {
    public let year: Int; public let month: Int; public let day: Int; public let timeZoneID: String
    public init(_ date: Date, timeZone: TimeZone)
    public var id: String                       // "2026-09-03@Europe/Oslo" — THE string form, used in notification ids and the export
    public init?(id: String)                    // DayKey(id: d.id) == d for every d; nil for a malformed string
    public func start() -> Date; public func end() -> Date; public func adding(days: Int) -> DayKey
}
public enum SkinType: Int, CaseIterable, Codable, Sendable { case i = 1, ii, iii, iv, v, vi; public var band: SkinBand }
public enum SkinBand: String, Codable, Sendable, CaseIterable { case fair /*I–II*/, medium /*III*/, dark /*IV–VI*/ }
public enum Region: String, CaseIterable, Codable, Sendable { case front, back, headAndShoulders }
public enum Side: String, Codable, Sendable { case faceUp, faceDown }
public enum Exposure: Codable, Sendable, Hashable { case lying(Side), upAndAbout }   // Codable as {"lying":"faceUp"} / "upAndAbout"
public enum Posture: String, Codable, Sendable { case lyingTurning, upAndAbout }
public enum Intent: String, Codable, Sendable { case bestMinutes, stayWholeWindow }
public enum Ceiling: String, Codable, Sendable, CaseIterable { case conservative, standard, aggressive }
public struct Window: Codable, Sendable, Equatable { public let start: Date; public let end: Date; public var minutes: Double }
public struct ExposureInterval: Codable, Sendable, Equatable { public let exposure: Exposure; public let window: Window }
public struct Coordinate: Codable, Sendable, Equatable { public let latitude: Double; public let longitude: Double
    public func distanceKm(to: Coordinate) -> Double }
public struct HourlyUVI: Codable, Sendable, Equatable { public let time: Date; public let uvi: UVI }
public enum Application: String, Codable, Sendable, CaseIterable { case thin /*0.5*/, normal /*1.0*/, thick /*2.0 mg/cm²*/; public var density: Double }
public struct SunscreenChoice: Codable, Sendable, Equatable, Hashable { public let spfLabel: Int; public let application: Application
    public var effectiveSPF: Double }    // pow(Double(spfLabel), application.density / 2)
public enum SunscreenConfirmation: Codable, Sendable, Equatable { case asPrescribed, alternative(SunscreenChoice), none }
public enum SkinAnswer: String, Codable, Sendable, CaseIterable { case normal, faintPink, clearlyPink, redSore, blistered }
public enum RednessTiming: String, Codable, Sendable { case withinHourGoneByEvening, thatEvening, nextMorning, notSure }
public enum ReportRegion: String, Codable, Sendable { case front, back, headAndShoulders, allExposed }
public enum Confounder: String, Codable, Sendable, CaseIterable { case photosensitisingMedication, illness, waterOrSnow, altitude, alcohol }
public enum LastingColour: String, Codable, Sendable { case yes, aLittle, no }
public enum Channel: String, Codable, Sendable { case notification, inApp }
public enum SessionState: String, Codable, Sendable { case planned, logged, discarded }
public enum FigureKey: String, Codable, Sendable, CaseIterable { case headlineMinutes, sideMinutes, regionDose, remainingBudget, cycleDose, rangeLower, rangeUpper, uvaMultiple, shortfall, extraIfCovered }
public enum FigureUnit: Sendable, Equatable { case minutes, sed, multiple }     // not `Unit`: Foundation exports one
public struct Figure: Sendable, Equatable { public let key: FigureKey; public let region: Region?; public let exposure: Exposure?; public let value: Double; public let unit: FigureUnit
    public let reads: Set<String>; public var isEstimate: Bool; public var assumptionKeys: [String] }   // isEstimate == reads ∩ Tunables.assumptionKeys ≠ ∅
public enum CopyKey: String, Codable, Sendable, CaseIterable {
    // outcomes: planBareSubWindow, planStayWearThis, planStayWholeWindowFits, tooWeak, noViableWindow, windowPassed, budgetSpent, missingForecast, missingForecastNoLocation
    // notices: staleHeadsUp, staleWarn, staleFarFromCache, escalationRisen, toleranceDropped, ceilingReached, underDosed, maintenance,
    //          thinMargin, fairSkinPreCalibration, conservativeUntilCalibrated, aggressiveLocked, uvaHeavy, cloudCaveat, coverToRunLonger,
    //          boundByMelanogenic, boundByBurnLine, whichSideFirst, timerStoppedAtPlannedEnd, timerNeedsNotifications, timerCannotStart, oneSideSpent
    // warnings: warnPastTarget, warnReachesThreshold
    // sunscreen: sunscreenNotNeeded, sunscreenPrescribed, sunscreenApplicationBeatsLabel, uvaMultiple, reapply, nothingRealistic,
    //            alternativeWholeWindow, alternativeThickEnough, alternativeShadeForRest, didYouWearIt
    // prompts: didYouDoThisSession, noSessionToReport, immediateDarkeningExplained, revisitSkinType, pauseSuggested, reportRecorded, alreadyReported
    // settings/history: sensitivitySentence, deleteHistoryWarning, trajectoryTitle, unreportedDays, privacyOptions, importApplied, importFailed
    // onboarding: onboardingWhyLocation, onboardingWhyNotifications, disclaimer
    // THIS LIST IS COMPLETE FOR EVERY PLAN. A later plan that needs a key adds it HERE and to docs/APP_COPY.md and lists both files.
}
public enum Basis: Sendable, Equatable { case citation(String), assumption(String) }
public struct Tunables: Sendable {
    // Every constant is a computed accessor over private storage; each read reports its key (plain name, or "<table>.<band|case>") to the sink.
    // Values, bases and the band split as listed; the Tunables file carries them as one table, one basis per stored number.
    public static let current: Tunables; public let version: String
    public func recording(_ sink: @escaping @Sendable (String) -> Void) -> Tunables   // same values, every read reported; the S1 spy
    public static let provenance: [String: Basis]      // one entry per stored number; keys are the read keys
    public static var assumptionKeys: Set<String>
    // dose
    public var uviMinutesPerSED: Double { get }                   // 66.7   citation Module 4
    public func medBaselineSED(_ t: SkinType) -> SED               // I 2.0 II 2.5 III 3.0 IV 4.5 V 6.0 VI 10.0  citation BUILD_PROMPT §4.3 (authoritative; addendum's 3.5/5.0 NOT used)
    // target
    public func melanogenicFraction(_ b: SkinBand) -> Double       // fair 1.0 (citation Pathak & Fanselow 1983, solar; Wulf 2010 1.5–1.9 NOT used), medium 0.95 (assumption), dark 0.75 (assumption)
    public func ceilingScale(_ c: Ceiling) -> Double               // 0.75 / 0.90 / 1.0
    public var calibrationReports: Int { get }                    // 3
    public var aggressiveUnlockReports: Int { get }               // 5
    public var uncertaintyBandAtZero: Double { get }              // 0.30   citation Module 4
    // posture
    public var frontBackFraction: Double { get }                  // 0.5  assumption (geometry)
    public var shoulderFraction: Double { get }                   // 0.5  assumption
    public var sideDifferenceForTwoFigures: Double { get }        // 0.15
    // adaptation
    public var riseTimeConstantDays: Double { get }               // 7.2  assumption: solved WITH the F3 decay (21 daily sessions at doseFraction 1.0 → 0.80, fair)
    public func riseMultiplier(_ b: SkinBand) -> Double            // fair 1.0, medium 1.0 (citation Module 6), dark 1.5 (assumption)
    public var decayHalfLifeDays: Double { get }                  // 21.0  assumption — Module 6 gives a 4–8 week fade; fast end so post-gap doses err shorter (V2)
    public func adaptationGain(_ b: SkinBand) -> Double            // fair 1.25, medium 1.25 (citation Module 5/6, SPF 2–3), dark 2.0 (assumption)
    public var plateauTanState: Double { get }                    // 0.75  assumption: below the 5/wk weekday peak (≈0.78) and daily saturation (≈0.82) under F3
    public var tolerantCredit: Double { get }                     // 0.5   assumption
    public var escalationNoticeFraction: Double { get }           // 0.5 — of the maximum rise for .risen, of the rise achieved for .dropped (T1, T5)
    public var gapDays: Double { get }                            // 14
    public var ceilingNoColourCount: Int { get }                  // 3
    public var maintenanceFraction: Double { get }                // 0.7
    public var lastingColourRegionFraction: Double { get }        // 0.5
    // calibration
    public func impliedRatio(_ a: SkinAnswer) -> Double            // faintPink 1.0 clearlyPink 1.5 redSore 2.5 blistered 4.0   assumption (build prompt §5.3 shape)
    public var reporterBandEdges: [Double] { get }                // [0.95, 1.15, 2.0, 4.0]   (S3 fixture; inverse of impliedRatio)
    public func reporterAnswer(ratio: Double) -> SkinAnswer        // first edge > ratio → normal / faintPink / clearlyPink / redSore; ≥ 4.0 → blistered
    public var k: Double { get }                                  // 2.5
    public var nCap: Int { get }                                  // 20
    public var burnWeight: Double { get }                         // 2.0
    public var multiplierClamp: ClosedRange<Double> { get }       // 0.5...1.8
    public var confoundedDiscount: Double { get }                 // 0.25
    public var blisterProtectiveFactor: Double { get }            // 0.8
    public var blisterPauseDays: Int { get }                      // 4
    // sunscreen
    public var densityDefault: Double { get }                     // 1.0 mg/cm²   citation Module 8
    public var spfLadder: [Int] { get }                           // [15, 20, 30, 50]
    public var realisticMaxSPF: Int { get }                       // 50 (applied normally)
    public var reapplicationIntervalHours: Double { get }         // 2
    // staleness / fetch / horizon
    public var staleHeadsUpHours: Double { get }                  // 3
    public var staleWarnHours: Double { get }                     // 6
    public var staleRangeWiden: Double { get }                    // 1.5
    public var staleReduction: Double { get }                     // 0.05
    public var staleDistanceKm: Double { get }                    // 25
    public var fetchMinIntervalHours: Double { get }              // 1
    public var fetchMoveKm: Double { get }                        // 10
    public var forecastHorizonDays: Int { get }                   // 10
    public var viabilityFraction: Double { get }                  // 0.5
    public var uvaHeavyHoursFromNoon: Double { get }              // 3   assumption
    // prompts
    public var skinCheckDelayHours: Double { get }                // 20
    public var lastingColourDelayDays: Double { get }             // 4
    public var inAppSkinCheckWindowHours: ClosedRange<Double> { get }    // 12...72
    public var inAppLastingColourWindowDays: ClosedRange<Double> { get } // 3...10
}
public enum ForecastCurveError: Error, Equatable { case tooFewSamples, unsorted }
public struct ForecastCurve: Codable, Sendable {
    public let location: Coordinate; public let timeZone: TimeZone; public let fetchedAt: Date; public let horizonEnd: Date
    public let hourly: [HourlyUVI]
    public init(location:, timeZone:, fetchedAt:, hourly:, solarNoon: [DayKey: Date]) throws
    public func uvi(at: Date) -> UVI
    public func sed(from: Date, to: Date) -> SED                          // prefix-integral difference at 1-minute resolution; from ≥ to → 0
    public func solarNoon(on: DayKey) -> Date                             // stored, else the NOAA formula from location and day
    public func day(_ date: Date) -> DayKey                               // DayKey(date, timeZone)
    public func stored(for day: DayKey) -> StoredCurve
}
public struct StoredCurve: Codable, Sendable, Equatable {               // EXTERNAL format (export v1); changes bump formatVersion
    public let hourly: [HourlyUVI]          // every sample from day.start() to day.end() + 6 h
    public let solarNoon: Date; public let timeZoneID: String; public let location: Coordinate; public let fetchedAt: Date
    public func curve() throws -> ForecastCurve
}
public enum DoseCalculator {
    public static func durationFrom(_ start: Date, targetSED: SED, curve:, notAfter: Date) -> Double?
        // smallest d (minutes, interpolated within the last minute) with sed(start, start+d) ≥ target and start+d ≤ notAfter (the INTERPOLATED end is compared); nil otherwise
    public static func bestSubWindow(curve:, within: Window, now: Date, targetSED: SED, tunables:) -> Window?
    public static func isViable(curve:, window: Window, now: Date, targetSED: SED, tunables:) -> Bool
    public static func nextViableWindow(curve:, after: Date, targetSED: SED, tunables:) -> Window?
    public static func isUVAHeavy(window: Window, solarNoon: Date, tunables:) -> Bool
    public static func clip(_ window: Window, toStartNoEarlierThan now: Date) -> Window?
}

// Promises the tests hold (S1, S6):
//  Tunables: every read key has a provenance entry; assumptionKeys == keys whose basis is .assumption; "adaptationGain.dark" ∈ assumptionKeys, "adaptationGain.fair" ∉;
//  Tunables.current.recording(sink): reading three accessors reports exactly their three keys; reporterAnswer(0.95) == .faintPink, (0.9499) == .normal, (4.0) == .blistered
//  sed(analytic ramp) within 0.5% of the closed form; steep-then-flat 14–17 window ≠ endpoint mean and equals the trapezoid;
//  type II, m=1.0, standard, UVI 7 steady → bestSubWindow.minutes within ±0.5 of 21.44 (interpolated end);
//  on morningRising 09:00–12:00 bestSubWindow ends at 12:00 within 1 second; on eveningFalling it starts at `now`;
//  clip returns nil for a passed window, shortened for a partial one; nextViableWindow never returns a start beyond horizonEnd;
//  DayKey(23:30Z, UTC) != DayKey(23:30Z, America/Los_Angeles); DayKey(id: d.id) == d; DayKey(id: "garbage") == nil;
//  solarNoon(on:) for an unsupplied day returns the NOAA value within 5 minutes of a reference; StoredCurve.curve() round-trips sed(a, b) within 1e-9;
//  JSONEncoder(SessionRecord) produces an object whose "dosePerRegion" is a JSON object keyed "front"/"back"/"headAndShoulders"
```

### Internals

```text
Package.swift: `#if os(Linux)` guards the IcarusUI/IcarusAds targets, products, test targets and their dependencies; placeholder `public enum <Target> {}` files keep every declared directory non-empty
project.yml: deploymentTarget iOS "18.0"; packages: { Icarus: { path: "." } }; ProjectIcarus sources [App] (move the two scaffold files to App/); dependencies: package Icarus product IcarusUI;
  ProjectIcarusTests sources [Tests/AppTests]; schemes.ProjectIcarus.test.targets: [ProjectIcarusTests, {package: Icarus/IcarusCoreTests}, {package: Icarus/IcarusDataTests}, {package: Icarus/IcarusContentTests}, {package: Icarus/IcarusUITests}, {package: Icarus/IcarusAdsTests}]
ci.yml: job core-tests (ubuntu-latest, swift-actions/setup-swift@v2 Swift 6.0): `swift test` (Linux builds only Core/Content/Data by the manifest guard); gated by swift-changed; macOS `test` and test-the-tests unchanged
Tunables: private storage struct + accessors; recording() returns a copy with a sink; `read(key)` reports then returns
DayKey.id: "\(year)-\(month, 2)-\(day, 2)@\(timeZoneID)"; init?(id:) parses and validates the zone identifier
ForecastCurve.init: validate sorted, ≥ 2; prefixSED computed in init at minute resolution (excluded from CodingKeys)
sed(a, b): b ≤ a → 0; interp(prefix, b) − interp(prefix, a)
solarNoon(on day): stored[day] ?? noaaSolarNoon(location, day)
durationFrom(start, target, notAfter): k = first prefix index with prefix[k] − prefix(start) ≥ target; nil if none
  d = (k − 1) + (target − (prefix[k−1] − p0)) / (prefix[k] − prefix[k−1]); if start + d > notAfter → nil else d
bestSubWindow: w = clip(within, now) ?? nil; argmin over start minutes s of durationFrom(s, target, notAfter: w.end); ties by |mid − solarNoon(day(s))|
Tests/Fixtures/Curves.swift: steadyUVI(7), ramp, steepThenFlat14to17, eveningFalling, morningRising, winterLow, tenDayLow, beachFlatUVI8, shoulderHourUVI2
```

## Slice 2 — Target and exposure: per-region budgets, attenuation, the coupled per-side solve

- **Delivers:** For a profile, replayed state, posture, cover toggle, intent flag and today's dose, the engine returns per-region targets (R6 formula, scale, aggressive unlock, conservative-until-calibrated, stale reduction, maintenance scaling, the adaptation factor the UI must log), a range centred on the target that widens when stale and whose upper edge can unclip, the one attenuation function every logging path calls, the whole-window raw dose for either posture (lying: two equal consecutive halves in side order), and an exposure plan where every region limits: the best start minute is searched, lying-down sides are consecutive from that start and each may be zero when its own budget is spent, sides are shortened until the head-and-shoulders credit fits; a window that cannot reach the budget is planned in full, never as zero minutes; warnings compare today's total and only when the user means to stay.
- **Files:** `Sources/IcarusCore/Models/Profile.swift`, `Sources/IcarusCore/Models/DerivedState.swift`, `Sources/IcarusCore/TargetModel.swift`, `Sources/IcarusCore/ExposureModel.swift`, `Tests/IcarusCoreTests/TargetModelTests.swift`, `Tests/IcarusCoreTests/ExposureModelTests.swift`
- **Estimate:** ~660 lines

### Signatures

```text
public struct Profile: Codable, Sendable, Equatable { public let skinType: SkinType; public var ceiling: Ceiling; public var manualMultiplier: Double? }
public struct RegionState: Codable, Sendable, Equatable {
    public var tanState: Double; public var lastExposure: Date?; public var cycleStart: DayKey?; public var rednessBoundInCycle: Bool
    public var noColourNearCeiling: Int; public var doseToday: SED; public var doseInCycle: SED; public var factorAtLastSession: Double; public var tanStateAtLastSession: Double
}
public struct DerivedState: Codable, Sendable, Equatable {
    public var multiplier: Double; public var reportCount: Int; public var totalReports: Int; public var rednessReportCount: Int
    public var regions: [Region: RegionState]; public var today: DayKey?; public var cycleStarts: [Date]; public var tunablesVersion: String
    public static func initial(tunables:) -> DerivedState
}
public enum BoundBy: String, Codable, Sendable { case melanogenic, burnLine }
public struct RegionTarget: Sendable, Equatable {
    public let region: Region; public let medPersonal: SED; public let melanogenic: SED; public let adaptationFactor: Double
    public let target: SED; public let boundBy: BoundBy; public let scaleUsed: Double; public let remaining: SED
    public let range: ClosedRange<SED>; public let rangeClipped: Bool
    public func scaled(by f: Double) -> RegionTarget      // target × f, remaining = max(0, target × f − doseToday); everything else unchanged
}
public protocol TargetGoal: Sendable {   // the seam for M8; TanningGoal is the only conformer now
    func target(for region: Region, profile: Profile, state: DerivedState, now: Date, stale: Bool, tunables: Tunables) -> RegionTarget
    var copyKey: CopyKey { get }
}
public struct TanningGoal: TargetGoal {
    public static func effectiveScale(profile:, state:, tunables:) -> (scale: Double, conservativeForced: Bool, aggressiveRefused: Bool)
    public static func adaptationFactor(_ region: RegionState, skinType:, tunables:) -> Double   // 1 + gain(band) × tanState
}
public struct ExposureRequest: Sendable {
    public let window: Window; public let now: Date; public let posture: Posture; public let firstSide: Side; public let coverHeadAndShoulders: Bool
    public let intent: Intent; public let targets: [Region: RegionTarget]; public let doseToday: [Region: SED]; public let curve: ForecastCurve
}
public struct SideAllocation: Sendable, Equatable { public let exposure: Exposure; public let window: Window; public let doses: [Region: SED] }
public struct ExposurePlan: Sendable, Equatable {
    public let sides: [SideAllocation]; public let perRegionDose: [Region: SED]; public let limitingRegion: Region
    public let span: Window; public let totalMinutes: Double; public let showTwoFigures: Bool
    public let extraMinutesIfCovered: [Exposure: Double]; public let fillsWindow: Bool     // true when the window could not reach the budget
    public let warnings: [Warning]
    public var intervals: [ExposureInterval]     // sides with non-empty windows, in order
}
public enum Warning: Sendable, Equatable { case pastTarget(Region, dayTotal: SED), reachesThreshold(Region, dayTotal: SED) }
public enum ExposureModel {
    public static func dose(_ exposure: Exposure, coverHeadAndShoulders: Bool, over w: Window, curve:, tunables:) -> [Region: SED]
    public static func wholeWindowRaw(_ w: Window, posture: Posture, firstSide: Side, coverHeadAndShoulders: Bool, curve:, tunables:) -> [Region: SED]
        // upAndAbout: dose(.upAndAbout, over w); lyingTurning: two equal consecutive halves in side order — the "stay" model, also what didThis logs
    public static func attenuated(_ bare: [Region: SED], sunscreen: SunscreenChoice?, coverHeadAndShoulders: Bool) -> [Region: SED]
    public static func attenuationRegion(raw: [Region: SED], targets: [Region: RegionTarget]) -> Region?   // argmax over regions with raw > 0 of raw/remaining (remaining 0 → ∞); nil if none exposed
    public static func solve(_ r: ExposureRequest, tunables:) -> ExposurePlan?
        // nil only when head-and-shoulders (uncovered) has remaining ≤ 0, or in lying both torso sides' regions have remaining ≤ 0, or upAndAbout with every exposed region at ≤ 0
    public static func warnings(entered: Window, r: ExposureRequest, tunables:) -> [Warning]
}

// Promises (S1, S5, S6):
//  type IV m=1 UVI 7 standard: target/med < type II's; boundBy .melanogenic for IV, .burnLine for II; type III standard binds .melanogenic (0.95 × 0.9)
//  every (type, ceiling): target ≤ medPersonal; the selector changes target for every type; RegionTarget.adaptationFactor == 1 + gain × tanState
//  range contains target; at standard and zero reports the upper edge is clipped; once rednessReportCount ≥ 5 at standard it is unclipped (0.9 × 1.1 < 1); stale widens both edges ×1.5 with the upper still ≤ medPersonal
//  attenuated(x, 50 normal, cover: false) == x / 7.07 per region within 1e-9; attenuated(x, nil, cover: true)[.headAndShoulders] == 0
//  wholeWindowRaw(lying, 3 h, flat): front == back == 1.5 h dose; headAndShoulders == 1.5 h + 0.5 × 1.5 h; attenuationRegion is the torso when remaining are equal
//  upAndAbout on morningRising 09:00–12:00: span ends at 12:00 within 1 s; lying on morningRising: sides consecutive, both inside the window
//  a clipped window whose full dose is below every exposed region's remaining → fillsWindow true, span == the window (never 0 minutes); lying same case: both sides non-empty, sum == window, dose/remaining equal per side within 1e-6
//  lying, flat UVI, equal regions, no H&S limit: total == 2 × side, one figure; sloping: two figures beyond 15%
//  lying: headAndShoulders dose == faceUp + 0.5 × faceDown and ≤ its remaining; when it limited, sides shorter than their optima and extraMinutesIfCovered[.lying(.faceUp)] > 0
//  front remaining 0, back and H&S > 0, lying → faceUp side 0 minutes, faceDown solved (not nil); upAndAbout: limiting == .headAndShoulders unless covered
//  warnings: intent .bestMinutes → []; .stayWholeWindow with doseToday 2.0 and window 2.0 on target 2.25 / MED 2.5 → .reachesThreshold(front, 4.0)
```

### Internals

```text
TanningGoal.target(region): rs = state.regions[region]; af = adaptationFactor(rs); m = profile.manualMultiplier ?? state.multiplier
  med = baseline(skinType) × m × af; mel = med × melanogenicFraction(band); (scale, forced, refused) = effectiveScale
  target = min(mel, med) × scale × (stale ? 1 − staleReduction : 1); boundBy = mel < med ? .melanogenic : .burnLine
  widen = stale ? staleRangeWiden : 1; h0 = uncertaintyBandAtZero
  lowerH = widen × h0 / (1 + totalReports/k); upperH = widen × h0 / (1 + rednessReportCount/k)
  rawUpper = target × (1 + upperH); range = target × (1 − lowerH) ... min(rawUpper, med); rangeClipped = rawUpper > med
  remaining = max(0, target − rs.doseToday)

ratio(region, dose) = remaining > 0 ? dose/remaining : (dose > 0 ? .infinity : 0)
The coupled lying-down solve (ruled D-2026-09-03-F2): scalar shrink by bisection on s ∈ (0, 1] of both sides' durations until every region's dose ≤ remaining.

solve(r):
  w = clip(window, now) ?? return nil
  hsUncovered = !cover; if hsUncovered && remaining[hs] ≤ 0 → nil
  upAndAbout:
    if every exposed region remaining ≤ 0 → nil
    full = dose(.upAndAbout, cover, over: w)
    if maxOverExposed(ratio(full)) ≤ 1 → sides = [SideAllocation(.upAndAbout, w, full)], fillsWindow = true
    else for s in grid: d(s) = smallest d with maxOverExposed(ratio(dose over Window(s, s+d))) ≥ 1 (bisection), nil when none before w.end
         pick s minimising d(s) over non-nil (ties → |mid − solarNoon|)
  lyingTurning:
    order = firstSide == .faceUp ? [.faceUp, .faceDown] : [.faceDown, .faceUp]; region(side) = faceUp ? .front : .back
    spent(i) = remaining[region(order[i])] ≤ 0; if spent(0) && spent(1) → nil
    for s in grid: d1 = spent(0) ? 0 : durationFrom(s, remaining[r1], notAfter: w.end); d2 = spent(1) ? 0 : d1.map { durationFrom(s + $0, remaining[r2], notAfter: w.end) }
    candidates = s with both defined (0 counts as defined); pick min d1 + d2 (ties → |mid − solarNoon|)
    if no candidate (window cannot reach the budget): t = bisection on the flip time in w so that dose(order[0] side over (w.start, t))/remaining[r1] == dose(order[1] over (t, w.end))/remaining[r2]
       (a spent side gets 0 minutes and the other the whole window); sides = [(w.start,t), (t,w.end)]; fillsWindow = true
    if H&S credit (faceUp dose + shoulderFraction × faceDown dose, 0 if covered) > remaining[hs] → F2 shrink on (d1, d2)
    extraMinutesIfCovered = re-solve with cover on, per-exposure difference
  perRegionDose = Σ sides; limitingRegion = argmax ratio; span = first.start…last.end; intervals = sides with window.minutes > 0
  showTwoFigures = lying && |d1 − d2| / max(d1, d2) > sideDifferenceForTwoFigures
  warnings = warnings(entered: w, r)
warnings(entered, r): if intent != .stayWholeWindow → []; raw = wholeWindowRaw(entered, posture, firstSide, cover)
  for region: total = doseToday[region] + raw[region]; total ≥ medPersonal → .reachesThreshold(region, total) else total > target → .pastTarget(region, total)
```

## Slice 3 — Adaptation and calibration, replayed from the history

- **Delivers:** `Replay` folds an ordered history into `DerivedState` under the current Tunables and returns every report's effect: tan state rises as a leaky integrator of dose-over-target (the target of the time, under the ceiling and override the session was planned with) and decays by elapsed time; today's dose is reset per day, never carried; tolerant surprises credit tan state first (discounted when confounded) and the learned multiplier second, always moving from itself; redness reports update the multiplier against the pre-session factor with the confidence-weighted, asymmetric, capped, two-cycle-windowed rule; "all exposed" redness takes the lowest-dose region; a report with no logged dose is recorded, never calibrated; Q2 reclassifies; blistering corrects; clamps prompt; the tan cycle starts and ends as defined and the two most recent cycle starts are kept for the report window; lasting-colour answers are placed by their own timestamp; the plateau outcome is sticky (it depends on the count, not on the decayed tan state at plan time); escalation fires at half the maximum rise and the gap notice at half the rise actually achieved, inclusive at the half-life boundary. S3 and S4 pass with the fixed reporter under the corrected constants.
- **Files:** `Sources/IcarusCore/Models/History.swift`, `Sources/IcarusCore/AdaptationModel.swift`, `Sources/IcarusCore/CalibrationEngine.swift`, `Sources/IcarusCore/Replay.swift`, `Tests/IcarusCoreTests/AdaptationModelTests.swift`, `Tests/IcarusCoreTests/CalibrationEngineTests.swift`, `Tests/IcarusCoreTests/ReplayTests.swift`, `Tests/IcarusCoreTests/Fixtures/SimulatedUser.swift`
- **Estimate:** ~740 lines

### Signatures

```text
public struct SessionRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID; public let day: DayKey; public let createdAt: Date
    public var plannedWindow: Window; public var plannedIntervals: [ExposureInterval]; public var firstSide: Side
    public var actualIntervals: [ExposureInterval]?       // the sub-intervals actually faced, in order — the source of truth once logged
    public var actualWindow: Window? { get }               // span of actualIntervals
    public var posture: Posture; public var coverHeadAndShoulders: Bool; public var intent: Intent
    public let ceilingAtPlan: Ceiling; public let manualMultiplierAtPlan: Double?
    public var prescribedSunscreen: SunscreenChoice?       // the R15 pair the result showed; nil when the second answer was not a prescription
    public var sunscreen: SunscreenChoice?                 // confirmed at logging (nil = none)
    public var state: SessionState
    public var dosePerRegion: [Region: SED]                // after sunscreen and cover; stored, never recomputed
    public var factorsShown: [Region: Double]; public var targetsShown: [Region: SED]   // display records only (R22)
    public var curveUsed: StoredCurve; public var forecastFetchedAt: Date; public var forecastPlace: Coordinate
}
public struct SkinReport: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID; public let day: DayKey; public let reportedAt: Date
    public let answer: SkinAnswer; public let timing: RednessTiming?; public let region: ReportRegion
    public let confounders: Set<Confounder>; public let channel: Channel
    public var lastingColour: LastingColour?; public var lastingColourAt: Date?
}
public struct History: Codable, Sendable, Equatable { public var sessions: [SessionRecord]; public var reports: [SkinReport]
    public func ordered() -> [HistoryEvent] }   // logged sessions by actualWindow.end; reports by reportedAt; lastingColour by lastingColourAt (absent → not emitted)
public enum HistoryEvent: Sendable { case session(SessionRecord), report(SkinReport), lastingColour(SkinReport) }

public enum AdaptationModel {
    public static func decayed(_ s: RegionState, to now: Date, tunables:) -> RegionState   // tanState × 0.5^(Δdays / halfLife); gap > gapDays → cycle ends (cycleStart nil, bound cleared, doseInCycle 0, noColour 0)
    public static func advanced(_ s: RegionState, doseFraction: Double, skinType:, at: Date, tunables:) -> RegionState
        // tanState += (1 − tanState) × (1 − exp(−doseFraction × riseMultiplier(band) / riseTimeConstantDays))
    public static func creditTolerant(_ s: RegionState, excess: Double, tunables:) -> (RegionState, unabsorbed: Double)
    public static func escalationNotice(_ s: RegionState, now: Date, skinType:, tunables:) -> EscalationNotice?
        // .risen(factor) when factor(now) − 1 ≥ escalationNoticeFraction × gain(band)
        // .dropped(fraction) when now − lastExposure > gapDays and the decay since the last exposure has undone ≥ escalationNoticeFraction of the rise the factor had achieved BY that session (T5):
        //   tanAfterLast = tanState(now) / 0.5^(days/halfLife) (the state Replay hands out is decayed to now, R44), fraction = 1 − tanState(now)/tanAfterLast — inclusive at the half-life boundary.
        //   factorAtLastSession / tanStateAtLastSession stay the PRE-session values calibration divides by
    public static func plateauOutcome(_ s: RegionState, tunables:) -> PlateauOutcome?
        // noColourNearCeiling ≥ ceilingNoColourCount → rednessBoundInCycle ? .ceiling : .underDosed; nil otherwise
        // (the count only ever increments while tanState ≥ plateauTanState at the answer; resets on yes / aLittle and when the cycle ends) — sticky across a weekend's decay
}
public enum EscalationNotice: Sendable, Equatable { case risen(factor: Double), dropped(fraction: Double) }
public enum PlateauOutcome: Sendable, Equatable { case ceiling, underDosed }

public enum CalibrationEngine {
    public static func apply(_ report: SkinReport, daySessions: [SessionRecord], state: DerivedState, skinType: SkinType, tunables:) -> (DerivedState, CalibrationEffect)
    public static func evidenceRegion(_ report: SkinReport, daySessions:) -> Region?
        // named region; .allExposed: .normal → highest-dose region; any redness → lowest-dose region with dose > 0; nil when no dose that day
    public static func weight(n: Int, isBurn: Bool, tunables:) -> Double                 // min(1, (isBurn ? burnWeight : 1) × k / (min(n, nCap) + k))
}
public enum CalibrationEffect: Sendable, Equatable { case none, tanStateCredited(Region, Double), multiplierMoved(from: Double, to: Double), clampHit(revisitSkinType: Bool), blisterCorrection(from: Double, to: Double, pauseDays: Int), reclassifiedAsNormal, discounted, noDoseThatDay }

public enum Replay {
    public static func replay(_ h: History, skinType: SkinType, now: Date, tunables:) -> (state: DerivedState, effects: [UUID: CalibrationEffect])
}

// Promises (S3, S4, S10):
//  weight(0,·) == 1.0; weight(15, burn) ≈ 0.286; weight(100, burn) ≥ 0.11; non-burn floor at nCap ≈ 0.111
//  true m=0.75 with the reporter: |m̂ − 0.75| ≤ 0.05 within 8 reports; normal outlier at 15 moves ≤ 0.05; redSore at 15 moves −0.10…−0.20
//  true m=1.0 truthful at standard for 20 reports: |m̂ − 1| ≤ 0.05; normal at ratio 1.2 with tanState < 1 → tanStateCredited, multiplier unchanged; at tanState 1 → multiplier rises ≤ excess
//  normal at ratio 1.4 with .alcohol → tanState rise == 0.25 × 0.5 × 0.4 and effect .discounted
//  override 0.8, learned 1.0, faintPink at ratio 1.0 (implied 0.8): learned moves from 1.0 toward 0.8 by weight (to 0.8 at n = 0, 0.956 at n = 20), never jumps to the override
//  a report whose day has no logged dose → .noDoseThatDay, state unchanged; est uses factorAtLastSession (pre-session)
//  two logged lying sessions on consecutive days: after replay every region's doseToday equals day 2's dose alone
//  12 reports, a 20-day gap, 12 more, another gap, 3 more → reportCount == 15 (previous + current cycle), never 3
//  evidenceRegion(.allExposed, redness) == the lowest-dose region with dose > 0; (.allExposed, .normal) == the highest
//  separation at true gain 0.7× and 1.3×: |m̂ − 1| ≤ 0.10 after 6 weeks; first post-gap recommendation ≤ true threshold
//  F3 with decay: 21 daily sessions at doseFraction 1.0 (fair) → tanState 0.80 ± 0.02; daily saturation 0.82 ± 0.02
//  6 weeks × 5/wk at standard (type II): factor rises, < cap; escalation notice absent after week 1 and present by week 2; 1-week factor rise < 50% of the cap rise (T6: 0.47 at τ = 7.2)
//  then a 28-day gap → dose ≥ 25% smaller and .dropped(fraction ≈ 0.60); a 21-day gap → .dropped (inclusive); a 13-day gap → nil
//  8 weeks × 5/wk reaches tanState ≥ plateauTanState at a Friday; 3 × lastingColour .no there → plateauOutcome non-nil, and STILL non-nil after three days of decay (0.71);
//   .ceiling iff rednessBoundInCycle else .underDosed; a bound from a previous cycle does not count
//  changing profile.ceiling after N sessions leaves every region's tanState unchanged (targets replay under ceilingAtPlan)
//  Q2 .withinHourGoneByEvening + faintPink → .reclassifiedAsNormal; blistered → blisterCorrection at any n; m̂ < 0.5 → clampHit(revisitSkinType: true)
//  Replay under tunables A then B differs; effects[r.id] present for every report; identical under TZ=UTC and TZ=Europe/Oslo
```

### Internals

```text
Discrete form (D-2026-09-03-F3, constant per T1): decay by elapsed time, then the closed-form rise; τ = 7.2 solved WITH one day of decay at
  half-life 21 between daily events so that 21 daily sessions at doseFraction 1.0 land at 0.80 (fair); daily saturation ≈ 0.82;
  five-a-week steady state 0.73–0.78 across the week. plateauTanState 0.75 is inside that band and the plateau count is what persists.

Replay.replay(h, skinType, now):
  state = DerivedState.initial; dayDose: [DayKey: [Region: (dose, target)]] = [:]
  for ev in h.ordered():
    .session(s) where s.state == .logged:
      profileThen = Profile(skinType, ceiling: s.ceilingAtPlan, manualMultiplier: s.manualMultiplierAtPlan)
      sameDay = (s.day == state.today)
      if every region's cycleStart == nil after decay → state.cycleStarts.append(s.actualWindow!.start)   // a new cycle begins for the user
      for region: rs = decayed(rs, to: s.actualWindow!.end)
        if rs.cycleStart == nil: cycleStart = s.day; rednessBound = false; doseInCycle = 0; noColour = 0
        rs.factorAtLastSession = adaptationFactor(rs); rs.tanStateAtLastSession = rs.tanState     // BEFORE advancing
        target = TanningGoal.target(region, profileThen, state, now: s.actualWindow!.start, stale: false)
        dose = s.dosePerRegion[region]; rs = advanced(rs, doseFraction: dose / target.target)
        dayDose[s.day][region] = (dose, target.target); doseInCycle += dose; lastExposure = end
        rs.doseToday = sameDay ? rs.doseToday + dose : dose
      state.today = s.day                                   // AFTER the region loop
    .report(r):
      sessions = logged sessions with day == r.day
      (state, effect) = CalibrationEngine.apply(r, daySessions: sessions, state, skinType); effects[r.id] = effect
      state.reportCount = count of reports with reportedAt ≥ (state.cycleStarts.suffix(2).first ?? .distantPast)
    .lastingColour(r):
      for region where dayDose[r.day][region].dose / .target ≥ lastingColourRegionFraction:
        if r.lastingColour == .no && tanState ≥ plateauTanState → noColourNearCeiling += 1 else if yes/aLittle → 0
  final: every region decayed to now; if state.today != nil && now ≥ state.today.end() → every doseToday = 0
  state.tunablesVersion = tunables.version

CalibrationEngine.apply(r, daySessions, state, skinType):
  region = evidenceRegion(r, daySessions) ?? return (state, .noDoseThatDay)
  dose = Σ daySessions dosePerRegion[region]; guard dose > 0 else (state, .noDoseThatDay)
  overrideThen = last session of the day .manualMultiplierAtPlan; mUsed = overrideThen ?? state.multiplier
  af = rs.factorAtLastSession; est = baseline(skinType) × mUsed × af; ratio = dose / est
  discount = r.confounders.isEmpty ? 1 : confoundedDiscount
  answer = (r.answer == .faintPink && r.timing == .withinHourGoneByEvening) ? .normal (effect .reclassifiedAsNormal) : r.answer
  if answer == .normal:
    if ratio ≤ 1.0 → .none (or .discounted if discount < 1)
    excess = discount × (ratio − 1); (rs, unabsorbed) = creditTolerant(rs, excess)
    if unabsorbed > 0: implied = min(mUsed × (1 + unabsorbed), mUsed × ratio); state.multiplier += weight(n, burn: false) × (implied − state.multiplier) → .multiplierMoved
    else → .tanStateCredited(region, rise)
  else:
    implied = dose / (baseline × af × impliedRatio(answer))            // absolute; mUsed cancels
    state.multiplier += discount × weight(n, burn: true) × (implied − state.multiplier)     // the learned value moves from itself
    mark rednessBoundInCycle on region (allExposed → every region with dose that day); state.rednessReportCount += 1
    if answer == .blistered: state.multiplier = min(state.multiplier, implied × blisterProtectiveFactor) → .blisterCorrection(pauseDays: blisterPauseDays)
  clamp; clamp hit → .clampHit(revisitSkinType: true)
  state.totalReports += 1
escalationNotice / plateauOutcome as in Signatures
Fixtures/SimulatedUser.swift: trueMultiplier, trueGainScale; answers Q1 via tunables.reporterAnswer(ratio:); weeks through Replay under TZ variations
```

## Slice 4 — Sunscreen: prescribe, the UVA multiple, reapplication, and the honest alternative

- **Delivers:** `SunscreenSolver` prescribes the lowest ladder label whose normal-application effective SPF covers the attenuation the whole window needs for the region it pushes hardest, never thick; names the UVA multiple and reapplication times; the "I don't have that SPF" re-solve uses exactly what the user said they can manage and never suggests reapplying more often as a fix; the S2 numbers pass.
- **Files:** `Sources/IcarusCore/SunscreenSolver.swift`, `Tests/IcarusCoreTests/SunscreenSolverTests.swift`
- **Estimate:** ~260 lines

### Signatures

```text
public struct SunscreenAdvice: Sendable, Equatable {
    public let prescribed: SunscreenChoice; public let uvaMultiple: Double; public let reapplyAt: [Date]; public let whyModerateSPF: CopyKey
}
public enum SunscreenOutcome: Sendable, Equatable { case notNeeded(uvaHeavy: Bool), prescribe(SunscreenAdvice), nothingRealistic(requiredAttenuation: Double)
    public var prescribedChoice: SunscreenChoice? }
public struct AlternativePlan: Sendable, Equatable {
    public let with: SunscreenChoice; public let coveredWindow: Window; public let shadeMinutes: Double
    public let coverHeadAndShoulders: Bool; public let reapplyAt: [Date]; public let copy: CopyKey
}
public enum SunscreenSolver {
    public static func outcome(rawSED: SED, budgetSED: SED, window: Window, bareMinutes: Double, uvaHeavy: Bool, tunables:) -> SunscreenOutcome
        // attenuation = raw/budget; ≤ 1 → .notNeeded; lowest label in spfLadder ≤ realisticMaxSPF with pow(label, densityDefault/2) ≥ attenuation; none → .nothingRealistic
    public static func alternative(have: SunscreenChoice, rawSED:, budgetSED:, window:, curve:, tunables:) -> AlternativePlan
    public static func reapplicationTimes(window:, tunables:) -> [Date]
}
// Promises (S2): effectiveSPF(50,.thick)=50, (50,.normal)≈7.07, (50,.thin)≈2.66; attenuation 8 → .nothingRealistic; attenuation 4 → SPF 20; attenuation 5 → SPF 30;
//  densityDefault is read (recording sink sees "densityDefault"; 2.0 makes attenuation 8 → SPF 15); uvaMultiple == whole/bare; reapplyAt non-empty iff window > 2 h;
//  alternative(have: 15 normal) for 3 h at UVI 8 → shadeMinutes > 0, coverHeadAndShoulders true, copy .alternativeShadeForRest; no key ever says "reapply more often"
```

### Internals

```text
outcome: effective(label) = pow(Double(label), densityDefault / 2); first label in spfLadder with effective ≥ attenuation and label ≤ realisticMaxSPF
reapplicationTimes: start + k × reapplicationIntervalHours while < end
alternative(have): have.effectiveSPF ≥ attenuation → whole window (.alternativeThickEnough iff have.application == .thick else .alternativeWholeWindow); else if have is not thick and SunscreenChoice(have.spfLabel, .thick).effectiveSPF ≥ attenuation → whole window with the thick pair, .alternativeThickEnough (R15, S2: "thicker application of what they have if it is enough")
  else coveredWindow = longest prefix with sed(start, t)/have.effectiveSPF ≤ budget (bisection on the prefix integral); shade for the rest; cover H&S; reapply inside the covered window
```

## Slice 5 — The Planner: one typed result, the fixtures, and the performance bound

- **Delivers:** `Planner.plan` composes everything into one `DoseResult`, solving once on maintained targets: outcome type with copy key, headline and second answer per R15 with the headline reverting to the bare sub-window when nothing realistic covers the window, overshoot and the sunscreen budget judged on the region the whole window pushes hardest, the R17 edge cases against the remaining budget with `noViableWindow` actually produced, a `noLocation` forecast failure, the R3 stale levels, the R13 notices with the cycle total, the plateau outcomes with maintenance applied before the solve, the R43 thin-margin key, per-figure provenance recorded through the Tunables spy, and the use-case fixtures 1–6, 8, 9 (S18) pass. The S14 performance test passes.
- **Files:** `Sources/IcarusCore/Planner.swift`, `Sources/IcarusCore/Models/DoseResult.swift`, `Tests/IcarusCoreTests/PlannerTests.swift`, `Tests/IcarusCoreTests/PerformanceTests.swift`, `Tests/IcarusCoreTests/Fixtures/UseCases.swift`, `acceptance/S18.sh`, `acceptance/S1.sh`
- **Estimate:** ~600 lines

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
public enum ForecastFailureKind: String, Sendable, Equatable { case provider, malformed, cacheUnreadable, noLocation }
public enum Headline: Sendable, Equatable { case bareSubWindow, sunscreenForWholeWindow, wholeWindowFits }
public enum StaleLevel: Sendable, Equatable { case fresh, headsUp(hours: Double), warn(hours: Double, farFromCache: Bool) }
public struct Notices: Sendable, Equatable { public let escalation: EscalationNotice?; public let plateau: PlateauOutcome?; public let maintenanceApplied: Bool
    public let uvaHeavy: Bool; public let stale: StaleLevel; public let thinMargin: Bool; public let conservativeForced: Bool; public let fairSkinPreCalibration: Bool; public let aggressiveRefused: Bool; public let cloudCaveat: Bool }
public struct DoseResult: Sendable, Equatable {
    public let outcome: Outcome; public let targets: [Region: RegionTarget]; public let notices: Notices
    public let figures: [Figure]; public let copyKeys: [CopyKey]; public let cycleDose: [Region: SED]
    public let attenuationRegion: Region?; public let wholeWindowRaw: [Region: SED]     // what a stay-whole-window log uses
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
//  windowPassed when window.end ≤ now; a partial window is solved from now; curve nil with forecastFailure .noLocation → .missingForecast(.noLocation)
//  viability uses min(remaining, target); a second session with 0.3 SED remaining and a 0.5 SED window is a .plan
//  a viable window that cannot reach the budget → .plan with headline .wholeWindowFits and span == the window (never 0 minutes)
//  tooWeak carries the shortfall from the melanogenic dose and nextViable (full target) within the horizon; nextViable nil → .noViableWindow(days: forecastHorizonDays, peakUVI: horizon max)
//  overshoot and the sunscreen budget are judged on attenuationRegion (max raw/remaining over the whole window, lying split half/half in side order); the prescribed pair covers every exposed region
//  fixture: lying, standard, equal remaining, flat UVI, 3 h: attenuationRegion is a torso side and the label is the torso's
//  headline == .sunscreenForWholeWindow iff intent == .stayWholeWindow && overshoot && sunscreen is .prescribe; .nothingRealistic never pairs with it
//  plateau non-nil → targets scaled by maintenanceFraction BEFORE the solve; the sunscreen is solved against the maintained remaining; plateau reported after a weekend's decay
//  stale: 3 h → .headsUp; 6 h or 30 km or unknown location → .warn, targets reduced and range widened; curve nil → .missingForecast(kind)
//  notices.thinMargin iff type I/II; fairSkinPreCalibration iff type I/II and totalReports < calibrationReports; escalation only past the notice line
//  figures: isEstimate iff reads ∩ assumptionKeys ≠ ∅; Planner.plan(req, tunables: .current.recording(sink)) → recorded keys == union of figures' reads
//  S18: each fixture's outcome type, headline minutes ±10%, per-region doses, and copy keys match; identical under TZ=UTC and TZ=Europe/Oslo
//  S14: 100 plans on a cached curve < 100 ms each; replay of 200 records < 200 ms
```

### Internals

```text
Planner.plan(req):
  guard curve else return .missingForecast(req.forecastFailure)
  stale = staleLevel(…); isStale = stale is .warn
  plateau = { r: AdaptationModel.plateauOutcome(state.regions[r]) }
  targets = for region: t = goal.target(…, stale: isStale); plateau[region] != nil ? t.scaled(by: maintenanceFraction) : t
  maintenanceApplied = plateau.values.contains(non-nil)
  if every region's remaining == 0 → .budgetSpent(argmax doseToday)
  w = clip(window, now) ?? return .windowPassed
  raw = ExposureModel.wholeWindowRaw(w, posture, firstSide, cover, curve)
  aRegion = attenuationRegion(raw, targets); t = targets[aRegion]
  viableBar = viabilityFraction × min(t.remaining, t.target)
  if raw[aRegion] < viableBar:
     nv = nextViableWindow(after: w.end, targetSED: t.target); nv == nil → .noViableWindow(days: forecastHorizonDays, peakUVI: horizon max)
     else → .tooWeak(shortfall: t.melanogenic − raw[aRegion], nextViable: nv)
  plan = ExposureModel.solve(request with targets) ?? return .budgetSpent(the region that made it nil)
  overshoot = raw[aRegion] > t.remaining
  sunscreen = overshoot ? SunscreenSolver.outcome(rawSED: raw[aRegion], budgetSED: t.remaining, w, bareMinutes: plan.totalMinutes, uvaHeavy) : .notNeeded(uvaHeavy)
  headline = plan.fillsWindow ? .wholeWindowFits : (overshoot && intent == .stayWholeWindow && case .prescribe = sunscreen) ? .sunscreenForWholeWindow : .bareSubWindow
  notices: escalation = escalationNotice(regions[plan.limitingRegion], now); plateau = plateau[limiting] ?? first non-nil; thinMargin / fairSkinPreCalibration / conservativeForced / aggressiveRefused / cloudCaveat / uvaHeavy as before
  figures via builders that declare `reads`; every Tunables access goes through the request's tunables (recording in tests)
  copyKeys in display order
acceptance/S1.sh (the check runs only `S<n>.sh`): `swift test --filter 'IcarusCoreTests.(DoseCalculator|Tunables|DayKey|TargetModel)'` and prints the provenance table
acceptance/S18.sh: `TZ=UTC swift test --filter UseCaseTests && TZ=Europe/Oslo swift test --filter UseCaseTests`
PerformanceTests: 100 × Planner.plan; 200-record Replay
```
