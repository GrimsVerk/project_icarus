---
slug: calculator-ui
status: draft
created: 2026-09-02
design: M3 — App copy, Calculator, Result, Flip Timer, Onboarding
covers: [R11, R28, R29, R31, R35, R36, R40, R42, R43]
format: pseudocode
---

# Calculator, Result, Flip Timer, Onboarding — Plan

## Summary

The first screens a person sees: onboarding with Module 1 and the app's own
skin-type table and quiz, the inputs-only calculator, the result that shows
every figure with its provenance, the flip timer as the session clock driven
by the Planner, and Settings. All copy comes from `docs/APP_COPY.md` through
IcarusContent; views hold no literal text; every screen declares its slots.
The environment lives in IcarusUI so package models can take it. Depends on
`learn-tab` Slice 1 (content, deep links) and Slice 2 (`ModuleView`).
Revision 3 lands the second tactical pass.

Non-goals:
- We do NOT ship real ads or the consent flow (M7); the protocol and the no-op live here, the AdMob provider in M7.
- We do NOT build History screens (M6) or the prompts (M5).
- We do NOT write copy in views; a copy-bearing call site with a literal fails S11.

Owner costs:
- S17: approve every line of `docs/APP_COPY.md` before this milestone starts.
- S9 on a device, with the fake provider.

Rulings: D-2026-09-03-F7, F8, T3 (docs/DECISIONS.md); design revision 3 for sunscreen, warnings and location entry

## The slices

## Slice 1 — App copy as data, the ad protocol and no-op, the profile store, the screen manifest, and the environment

- **Delivers:** `docs/APP_COPY.md` exists with a keyed table for every `CopyKey`; `AppCopy.text(_:skinType:)` resolves them; the `AdBannerProvider` protocol and `NoAdsProvider` exist in IcarusAds; `ProfileStore` exists in IcarusData; every screen declares `hasBannerSlot` and `showsFigures`; `AppEnvironment` lives in IcarusUI and composes the packages, refreshes the forecast on foreground (the R1 trigger), discards stale planned sessions, and routes deep links; the app target only instantiates it.
- **Files:** `docs/APP_COPY.md`, `scripts/build-app-copy.sh`, `Sources/IcarusContent/Resources/app-copy.json`, `Sources/IcarusContent/AppCopy.swift`, `Sources/IcarusContent/SkinTypeTable.swift`, `Sources/IcarusAds/AdBannerProvider.swift`, `Sources/IcarusAds/NoAdsProvider.swift`, `Sources/IcarusData/ProfileStore.swift`, `Sources/IcarusUI/ScreenManifest.swift`, `Sources/IcarusUI/AppEnvironment.swift`, `App/ProjectIcarusApp.swift`, `App/RootTabs.swift`, `Tests/IcarusContentTests/AppCopyTests.swift`, `Tests/IcarusUITests/ScreenManifestTests.swift`, `Tests/IcarusUITests/AppEnvironmentTests.swift`, `acceptance/S11-static.sh`, `acceptance/S15-screens.sh`
- **Estimate:** ~520 lines

### Signatures

```text
public enum AppCopy { public static func text(_ key: CopyKey, skinType: SkinType? = nil, args: [String: String] = [:]) -> String; public static var allKeys: Set<CopyKey> }
public struct SkinTypeRow: Sendable, Equatable { public let type: SkinType; public let name: String; public let description: String; public let citation: Citation }
public enum SkinTypeTable { public static let rows: [SkinTypeRow] }
public struct QuizQuestion: Sendable, Equatable { public let id: Int; public let text: String; public let options: [QuizOption] }
public struct QuizOption: Sendable, Equatable { public let text: String; public let points: Int }
public enum FitzpatrickQuiz { public static let questions: [QuizQuestion]; public static func skinType(forScore: Int) -> SkinType }
// IcarusAds (protocol only here; the SDK provider is M7)
public protocol AdBannerProvider: Sendable {
    func prepare(region: ConsentRegion) async -> AdReadiness
    @MainActor func banner(width: CGFloat) -> AnyView?
    var requestConfiguration: AdRequestConfiguration { get }
}
public enum ConsentRegion: Sendable, Equatable { case requiresConsent, none }
public enum AdReadiness: Sendable, Equatable { case ready, limited, unavailable }
public struct AdRequestConfiguration: Sendable, Equatable { public let nonPersonalised: Bool; public let consentShown: Bool }
public struct NoAdsProvider: AdBannerProvider { public init() }       // banner nil; nonPersonalised true
// IcarusData
public protocol ProfileStore: Sendable { func load() -> Profile?; func save(_: Profile); func flags() -> ProfileFlags; func setFlags(_: ProfileFlags) }
public struct ProfileFlags: Codable, Sendable, Equatable { public var onboardingComplete: Bool; public var disclaimerAcknowledged: Bool; public var adConsentDone: Bool }
public struct UserDefaultsProfileStore: ProfileStore { public init(defaults: UserDefaults = .standard) }
public struct MemoryProfileStore: ProfileStore { public init(profile: Profile?) }
// IcarusUI
public protocol ScreenManifest { static var hasBannerSlot: Bool { get }; static var showsFigures: Bool { get } }
public enum ScreenTable { public static let all: [(name: String, hasBanner: Bool, showsFigures: Bool)] }
@MainActor public final class AppEnvironment: ObservableObject {
    public let forecast: ForecastService; public let location: LocationService; public let history: HistoryStore; public let profile: any ProfileStore
    public let prompts: PromptScheduler; public let ads: any AdBannerProvider; public let tunables: Tunables; public let clock: () -> Date
    public init(forecast:, location:, history:, profile:, prompts:, ads:, tunables:, clock:)
    public static func preview() -> AppEnvironment         // fake provider fixture, MemoryPersistence, MemoryProfileStore, NoAdsProvider, fixed clock
    public var lastCoordinate: Coordinate? { get }
    public func didBecomeActive() async                    // forecast.current(for: lastCoordinate, now) when the cache is older than an hour; history.discardPlanned(before: now)
    public func handle(_ url: URL) -> DeepLink?
}
// App/ProjectIcarusApp: builds the live AppEnvironment (WeatherKitProvider, FileForecastCache, CoreLocationSource + AppleGeocoder, SwiftDataPersistence, UserDefaultsProfileStore, UserNotificationAdapter, NoAdsProvider until M7)
// Promises (S11, S15, S17): every CopyKey.allCases resolves; every key in app-copy.json is a CopyKey; S11 finds no literal at a copy-bearing call site;
//  ScreenTable: CalculatorEntryView (true, false), LearnListView (true, false), every other screen (false, _); didBecomeActive invokes the provider when the cache is older than an hour and not otherwise; NoAdsProvider.banner == nil
```

### Internals

```text
docs/APP_COPY.md and scripts/build-app-copy.sh as revision 2
acceptance/S11-static.sh: copy-bearing call sites only (Text(" Label(" Button(" .navigationTitle(" .alert(" .confirmationDialog(" Section(" accessibilityLabel(" accessibilityHint(") — no allowlist; package describe; import greps; FigureView( must not appear in CalculatorEntryView.swift or Prompts/
acceptance/S15-screens.sh: `swift test --filter ScreenManifestTests` asserting the ScreenTable rows, plus the FigureView grep
RootTabs: TabView { Calculator, Learn }; History and Settings via toolbar; .onOpenURL → env.handle(url); .onChange(scenePhase == .active) → env.didBecomeActive()
```

## Slice 2 — Onboarding: Module 1, disclaimer, skin type, permissions

- **Delivers:** First launch shows Module 1 unsoftened (`ModuleView`, landed by `learn-tab` Slice 2), the medical disclaimer to acknowledge, the skin-type table with the optional Fitzpatrick quiz, and asks for location and notification permission with the reason for each; the profile is saved; the flow's completion rule lives in a testable model.
- **Files:** `Sources/IcarusUI/Onboarding/OnboardingFlow.swift`, `Sources/IcarusUI/Onboarding/OnboardingModel.swift`, `Sources/IcarusUI/Onboarding/SkinTypePicker.swift`, `Sources/IcarusUI/Onboarding/QuizView.swift`, `Sources/IcarusUI/Onboarding/DisclaimerView.swift`, `Tests/IcarusUITests/OnboardingModelTests.swift`
- **Estimate:** ~340 lines

### Signatures

```text
@MainActor public final class OnboardingModel: ObservableObject {
    public init(store: any ProfileStore)
    @Published public var disclaimerAcknowledged: Bool; @Published public var skinType: SkinType?; @Published public var quizScore: Int?
    public var canComplete: Bool { get }; public func applyQuiz(); public func complete() -> Profile
}
public struct OnboardingFlow: View, ScreenManifest { public init(model: OnboardingModel, onComplete: @escaping (Profile) -> Void) }   // (false, false)
public struct SkinTypePicker: View { public init(model: OnboardingModel) }
public struct QuizView: View { public init(model: OnboardingModel) }
// Promises: canComplete false until both set; applyQuiz maps the score through FitzpatrickQuiz; Module 1 page text == ModuleIndex.module(1).markdown
```

### Internals

```text
pages: ModuleView(module 1) → DisclaimerView → SkinTypePicker ("Not sure?" → QuizView) → permissions (.onboardingWhyLocation / .onboardingWhyNotifications; tolerates denial)
```

## Slice 3 — Calculator entry and the Result screen

- **Delivers:** The entry screen asks only window, posture, cover toggle and "staying the whole window", with the banner slot and no figure; computing reads the cache and never fetches on a window change; a denied location with no cache yields a result that still offers "change place"; the Result shows the outcome per R15 with the forecast line on every outcome, per-side or per-region times, the clipped range, remaining budget per region, warnings when they apply, the escalation or gap notice with the cycle total, the UVA note, the thin-margin and pre-calibration lines, estimate labels on the figures that carry them, links into Learn, "I don't have that SPF" with the re-solve against the same region, and "I did this" which logs the session's intervals with the attenuated dose the headline implies and never an unattenuated whole window. Computing keeps exactly one planned session with its prescribed pair and schedules its skin check.
- **Files:** `Sources/IcarusUI/Calculator/CalculatorEntryView.swift`, `Sources/IcarusUI/Calculator/ResultView.swift`, `Sources/IcarusUI/Calculator/FigureView.swift`, `Sources/IcarusUI/Calculator/SunscreenAlternativeSheet.swift`, `Sources/IcarusUI/Calculator/ManualLocationSheet.swift`, `Sources/IcarusUI/Calculator/CalculatorModel.swift`, `Tests/IcarusUITests/CalculatorModelTests.swift`
- **Estimate:** ~680 lines

### Signatures

```text
@MainActor public final class CalculatorModel: ObservableObject {
    public init(env: AppEnvironment)
    @Published public var window: Window; @Published public var posture: Posture; @Published public var cover: Bool; @Published public var stay: Bool
    @Published public var confirmedSunscreen: SunscreenConfirmation      // .asPrescribed only when the result's sunscreen is .prescribe and the headline is .sunscreenForWholeWindow; else .none
    @Published public private(set) var result: DoseResult?; @Published public private(set) var forecastStatus: ForecastResult?
    public private(set) var plannedSessionID: UUID?
    public func request(window: Window, firstSide: Side, now: Date) async throws -> PlanRequest   // shared with the timer: same profile, state, stale level, intent, cover
    public func compute() async
    public func refreshForecast() async
    public func didThis() async throws
    public func alternative(have: SunscreenChoice) -> AlternativePlan?    // solved against result.attenuationRegion's raw and remaining
    public func useManualPlace(_: Place) async
}
public struct CalculatorEntryView: View, ScreenManifest { public init(model: CalculatorModel, adBanner: AnyView?) }   // (true, false)
public struct ResultView: View, ScreenManifest { public init(model: CalculatorModel) }                                // (false, true); the forecast line (place, "change place", "refresh") renders for EVERY outcome
public struct FigureView: View { public init(figure: Figure, label: String) }
// Promises (S6 via model tests, S15, S10):
//  compute() twice in one model → exactly one planned session, with prescribedSunscreen == the result's prescribed pair or nil; after .plan the port holds exactly one pending skinCheck(day) at lastEnd + 20 h
//  changing window or posture between two compute() calls never invokes the provider; refreshForecast() does
//  FakeLocationSource(.denied) with an empty cache → result.outcome == .missingForecast(.noLocation) and the model exposes the manual-place path
//  didThis with headline .bareSubWindow or .wholeWindowFits logs actual == plan.intervals and doses == plan.perRegionDose;
//  with .sunscreenForWholeWindow logs actual == the half/half (or single) intervals over the entered window and doses == attenuated(result.wholeWindowRaw, prescribed pair, cover);
//  .alternative(choice) logs attenuated(wholeWindowRaw, choice, cover); .nothingRealistic never logs an unattenuated whole window (confirmedSunscreen is .none and the span is logged)
//  warnings shown only when stay; estimate badge iff isEstimate
```

### Internals

```text
compute(): loc = await env.location.location(now); coord = loc.coordinate
  fr = await env.forecast.cached(); if fr.curve == nil, let coord → fr = await env.forecast.current(for: coord, now)
  guard let coord else { result = Planner.plan(PlanRequest(curve: fr.curve, forecastFailure: fr.curve == nil ? .noLocation : nil, deviceLocation: nil, …)); return }
  req = try await request(window, firstSide: .faceUp, now); result = Planner.plan(req)
  if case .plan(let plan, let sunscreen, let headline) = result.outcome:
     confirmedSunscreen = (headline == .sunscreenForWholeWindow) ? .asPrescribed : .none
     rec = SessionRecord(planned: window, plannedIntervals: plan.intervals, prescribedSunscreen: sunscreen.prescribedChoice, ceilingAtPlan, manualMultiplierAtPlan, curveUsed: curve.stored(for: curve.day(window.start)), …)
     plannedSessionID = try env.history.upsertPlanned(rec, replacing: plannedSessionID)
     lastEnd = max(window.end, sessions(on: day).map(end).max()); await env.prompts.sessionsChanged(on: day, lastSessionEnd: lastEnd)
didThis(): switch headline:
   .bareSubWindow, .wholeWindowFits → actual = plan.intervals; doses = plan.perRegionDose
   .sunscreenForWholeWindow → guard case .asPrescribed, let pair = sunscreen.prescribedChoice else fall back to the span case; actual = halves of the entered window in side order (or one upAndAbout interval); doses = attenuated(result.wholeWindowRaw, pair, cover)
   .alternative(choice) → actual as above; doses = attenuated(result.wholeWindowRaw, choice, cover)
  env.history.log(id, actual, sunscreen: choice, doses, factors: targets.map(\.adaptationFactor), targets: targets.map(\.target))
ResultView layout as revision 2; the forecast line is outside the outcome switch
SunscreenAlternativeSheet: pickers from tunables.spfLadder × application → model.alternative
```

## Slice 4 — The flip timer and Settings

- **Delivers:** The flip timer asks which side is up first, plans through the Planner from the real clock with the same stale level and maintenance the result used (with sunscreen confirmed, it plans the sunscreened span), refuses to start on a non-plan outcome, logs the session at start from the plan's intervals, alerts at the first side's end, the reapplication times and the session end with the screen locked, stops on demand writing the intervals it actually ran, warns before starting when notifications are denied, and stops itself at the planned end if left past midnight. Settings shows the ceiling selector with the aggressive unlock state, the sensitivity sentence counting reports, override and reset (invalidating the store), unreported logged days, attribution, disclaimer, privacy policy link, export, import (applying the file's profile), and delete history with the R44 warning.
- **Files:** `Sources/IcarusUI/Timer/FlipTimerView.swift`, `Sources/IcarusUI/Timer/FlipTimerModel.swift`, `Sources/IcarusUI/Settings/SettingsView.swift`, `Sources/IcarusUI/Settings/SettingsModel.swift`, `Sources/IcarusUI/Settings/AttributionView.swift`, `Tests/IcarusUITests/FlipTimerModelTests.swift`, `Tests/IcarusUITests/SettingsModelTests.swift`
- **Estimate:** ~560 lines

### Signatures

```text
public enum TimerError: Error, Equatable { case cannotStart(Outcome), notificationsDenied }
@MainActor public final class FlipTimerModel: ObservableObject {
    public init(env: AppEnvironment, calculator: CalculatorModel)
    @Published public var firstSide: Side; @Published public private(set) var phase: TimerPhase
    public var notificationsDenied: Bool { get }
    public func start(now: Date) async throws       // Planner.plan(calculator.request(window: Window(now, entered.end), firstSide, now)); with sunscreen confirmed the targets' remaining are scaled by effectiveSPF so the plan spans the covered window; guard .plan else .cannotStart; logs intervals at start; schedules alerts
    public func stop(now: Date) async throws        // writes the intervals actually run (side windows clipped at now), doses attenuated; cancels alerts
    public func tick(now: Date); public func foregrounded(now: Date) async
}
public enum TimerPhase: Sendable, Equatable { case idle, running(exposure: Exposure, endsAt: Date, sessionEnd: Date), finished(stoppedAtPlannedEnd: Bool) }
public struct FlipTimerView: View, ScreenManifest { public init(model: FlipTimerModel) }   // (false, true)
@MainActor public final class SettingsModel: ObservableObject {
    public init(env: AppEnvironment)
    @Published public var ceiling: Ceiling; public var aggressiveUnlocked: Bool; public var sensitivitySentence: String
    public func overrideMultiplier(_: Double?) async; public func resetSensitivity() async
    public var unreportedDays: Int
    public func exportFile() async throws -> URL; public func importFile(_: URL) async throws -> ImportSummary
    public func deleteHistory() async throws
}
public struct SettingsView: View, ScreenManifest { public init(model: SettingsModel) }   // (false, true)
public struct AttributionView: View { public init(legalURL: URL?) }                        // Apple's asset and link; the URL is wired in M7
// Promises: start on a .tooWeak result → .cannotStart; start with .asPrescribed SPF 30 spans ≈ 5.5× the bare minutes on a flat curve and logs doses ≈ the target; stop at half time on a flat bare session halves the front dose and writes one interval;
//  stop after the flip writes two intervals; alerts: side end, reapply (if any), session end; aggressiveUnlocked iff reports ≥ 5 and a bound in cycle; override then state(now) changes without a write; import applies the file's profile; sentence counts reports; unreportedDays counts logged days
```

### Internals

```text
start: req = calculator.request(Window(now, entered.end), firstSide, now); if choice != nil: req.targets = targets.map { $0.scaled(by: choice.effectiveSPF) } (remaining grows ×SPF); result = Planner.plan(req)
  guard case .plan(plan, sunscreen, _) else throw .cannotStart(outcome); doses = attenuated(plan.perRegionDose, choice, cover)
  history.log(id, actual: plan.intervals, sunscreen: choice, doses, …); prompts.scheduleTimer(sideEnd: first side end if two, reapply: advice?.reapplyAt ∩ span, sessionEnd: span.end)
tick / foregrounded as revision 2 (midnight rule → finished(stoppedAtPlannedEnd: true))
stop(now): intervals = plan.intervals clipped at now (drop empty); doses = attenuated(Σ dose(i.exposure, cover, over i.window), choice, cover); history.log(id, actual: intervals, …); prompts.cancelTimer()
SettingsView sections as revision 2; importFile: summary = try await ExportService.import(data, into: env.history); env.profile.save(summary.profile); env.history.invalidate()
```
