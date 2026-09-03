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
every figure with its provenance, the flip timer as the session clock, and
Settings. All copy comes from `docs/APP_COPY.md` through IcarusContent; views
hold no literal text; every screen declares its slots. Depends on
`learn-tab` Slice 1 (content) landing first. Revision 2 lands the tactical review.

Non-goals:
- We do NOT ship real ads or the consent flow (M7); the slot takes an `AnyView?`.
- We do NOT build History screens (M6) or the prompts (M5).
- We do NOT write copy in views; a copy-bearing call site with a literal fails S11.

Owner costs:
- S17: approve every line of `docs/APP_COPY.md` before this milestone starts.
- S9 on a device, with the fake provider.

Rulings: D-2026-09-03-F7, F8, T3 (docs/DECISIONS.md); design revision 3 for sunscreen, warnings and location entry

## The slices

## Slice 1 — App copy as data, the screen manifest, and the app shell

- **Delivers:** `docs/APP_COPY.md` exists with a keyed table for every `CopyKey`, skin-type variants where R43 needs them, onboarding text, the skin-type table and quiz, prompts and notifications; `AppCopy.text(_:skinType:)` resolves them from a generated resource; every screen declares `hasBannerSlot` and `showsFigures` statically; the app target composes the packages behind `AppEnvironment`, refreshes the forecast on foreground (the R1 trigger), and routes deep links.
- **Files:** `docs/APP_COPY.md`, `scripts/build-app-copy.sh`, `Sources/IcarusContent/Resources/app-copy.json`, `Sources/IcarusContent/AppCopy.swift`, `Sources/IcarusContent/SkinTypeTable.swift`, `Sources/IcarusUI/ScreenManifest.swift`, `App/ProjectIcarusApp.swift`, `App/AppEnvironment.swift`, `App/RootTabs.swift`, `Tests/IcarusContentTests/AppCopyTests.swift`, `Tests/IcarusUITests/ScreenManifestTests.swift`, `acceptance/S11-static.sh`
- **Estimate:** ~460 lines

### Signatures

```text
public enum AppCopy {
    public static func text(_ key: CopyKey, skinType: SkinType? = nil, args: [String: String] = [:]) -> String   // base variant fallback; a missing key is caught by S11, never an empty string
    public static var allKeys: Set<CopyKey>
}
public struct SkinTypeRow: Sendable, Equatable { public let type: SkinType; public let name: String; public let description: String; public let citation: Citation }
public enum SkinTypeTable { public static let rows: [SkinTypeRow] }
public struct QuizQuestion: Sendable, Equatable { public let id: Int; public let text: String; public let options: [QuizOption] }
public struct QuizOption: Sendable, Equatable { public let text: String; public let points: Int }
public enum FitzpatrickQuiz { public static let questions: [QuizQuestion]; public static func skinType(forScore: Int) -> SkinType }
public protocol ScreenManifest { static var hasBannerSlot: Bool { get }; static var showsFigures: Bool { get } }   // every screen View conforms
public enum ScreenTable { public static let all: [(String, hasBanner: Bool, showsFigures: Bool)] }   // S15 reads this
@MainActor public final class AppEnvironment: ObservableObject {
    public let forecast: ForecastService; public let location: LocationService; public let history: HistoryStore; public let profile: any ProfileStore
    public let prompts: PromptScheduler; public let ads: any AdBannerProvider; public let tunables: Tunables; public let clock: () -> Date
    public static func live() throws -> AppEnvironment
    public static func preview() -> AppEnvironment     // fake provider fixture, MemoryPersistence, NoAdsProvider, fixed clock
    public func didBecomeActive() async                // forecast.current(for: last coordinate, now) — the foreground fetch trigger (R1); housekeeping: history.discardPlanned(before: now)
}
// Promises (S11, S15, S17): every CopyKey.allCases resolves; every key in app-copy.json is a CopyKey; S11 finds no literal at a copy-bearing call site in IcarusUI;
//  ScreenTable: CalculatorEntryView (true, false), LearnListView (true, false), every other screen (false, _); didBecomeActive invokes the provider when the cache is older than an hour
```

### Internals

```text
docs/APP_COPY.md: one "### <CopyKey>" heading per key; "- base:" / "- fair:" variants; {args}; skin-type table; quiz list
scripts/build-app-copy.sh → app-copy.json; S11 regenerates and diffs
acceptance/S11-static.sh (tactical #25): match ONLY copy-bearing call sites with a string literal first argument —
  Text(" Label(" Button(" .navigationTitle(" .alert(" .confirmationDialog(" Section(" accessibilityLabel(" accessibilityHint(" — no allowlist;
  plus `swift package describe` asserting IcarusCore deps == [] and import greps for URLSession/WeatherKit/GoogleMobileAds outside their packages;
  plus `grep -c "FigureView(" Sources/IcarusUI/Calculator/CalculatorEntryView.swift Sources/IcarusUI/Prompts/*` must be 0
AppEnvironment.live: WeatherKitProvider, FileForecastCache, CoreLocationSource + AppleGeocoder, SwiftDataPersistence, UserDefaultsProfileStore, UserNotificationAdapter, NoAdsProvider (M7 swaps), Tunables.current
RootTabs: TabView { Calculator, Learn }; History and Settings via toolbar; icarus:// → DeepLink; .onChange(scenePhase == .active) → env.didBecomeActive()
```

## Slice 2 — Onboarding: Module 1, disclaimer, skin type, permissions

- **Delivers:** First launch shows Module 1 unsoftened (from `ModuleIndex`, landed by `learn-tab` Slice 1), the medical disclaimer to acknowledge, the skin-type table with the optional Fitzpatrick quiz, and asks for location and notification permission with the reason for each; the profile is saved; the flow's completion rule lives in a testable model.
- **Files:** `Sources/IcarusUI/Onboarding/OnboardingFlow.swift`, `Sources/IcarusUI/Onboarding/OnboardingModel.swift`, `Sources/IcarusUI/Onboarding/SkinTypePicker.swift`, `Sources/IcarusUI/Onboarding/QuizView.swift`, `Sources/IcarusUI/Onboarding/DisclaimerView.swift`, `Sources/IcarusData/ProfileStore.swift`, `Tests/IcarusUITests/OnboardingModelTests.swift`
- **Estimate:** ~380 lines

### Signatures

```text
public protocol ProfileStore: Sendable { func load() -> Profile?; func save(_: Profile); func flags() -> ProfileFlags; func setFlags(_: ProfileFlags) }
public struct ProfileFlags: Codable, Sendable, Equatable { public var onboardingComplete: Bool; public var disclaimerAcknowledged: Bool; public var adConsentDone: Bool }
public struct UserDefaultsProfileStore: ProfileStore { public init(defaults: UserDefaults = .standard) }
@MainActor public final class OnboardingModel: ObservableObject {
    public init(store: any ProfileStore)
    @Published public var disclaimerAcknowledged: Bool; @Published public var skinType: SkinType?; @Published public var quizScore: Int?
    public var canComplete: Bool { get }                         // disclaimerAcknowledged && skinType != nil
    public func applyQuiz() ; public func complete() -> Profile  // saves; precondition canComplete
}
public struct OnboardingFlow: View, ScreenManifest { public init(model: OnboardingModel, onComplete: @escaping (Profile) -> Void) }   // (false, false)
public struct SkinTypePicker: View { public init(model: OnboardingModel) }
public struct QuizView: View { public init(model: OnboardingModel) }
// Promises: canComplete false until both set; applyQuiz maps the score through FitzpatrickQuiz; Module 1 page text == ModuleIndex.module(1).markdown
```

### Internals

```text
OnboardingFlow pages: ModuleView(module 1) → DisclaimerView (explicit toggle) → SkinTypePicker (rows from SkinTypeTable; "Not sure?" → QuizView) → permissions (copy keys .onboardingWhyLocation / .onboardingWhyNotifications; requests both; tolerates denial)
```

## Slice 3 — Calculator entry and the Result screen

- **Delivers:** The entry screen asks only window, posture, cover toggle and "staying the whole window", with the banner slot at the bottom and no figure; computing never fetches the forecast (it reads the cache; fetching is the foreground trigger and the explicit refresh); the Result shows the outcome per R15, per-side or per-region times, the clipped range, remaining budget per region, warnings when they apply, the escalation or gap notice with the cycle total, the UVA note, forecast age and place with a "change place" entry to manual location, the thin-margin and pre-calibration lines, estimate labels on the figures that carry them, links into Learn, "I don't have that SPF" with the re-solve, and "I did this" which logs the session with the attenuated dose over the window the headline implies. Computing keeps exactly one planned session and schedules its skin check.
- **Files:** `Sources/IcarusUI/Calculator/CalculatorEntryView.swift`, `Sources/IcarusUI/Calculator/ResultView.swift`, `Sources/IcarusUI/Calculator/FigureView.swift`, `Sources/IcarusUI/Calculator/SunscreenAlternativeSheet.swift`, `Sources/IcarusUI/Calculator/ManualLocationSheet.swift`, `Sources/IcarusUI/Calculator/CalculatorModel.swift`, `Tests/IcarusUITests/CalculatorModelTests.swift`
- **Estimate:** ~640 lines

### Signatures

```text
@MainActor public final class CalculatorModel: ObservableObject {
    public init(env: AppEnvironment)
    @Published public var window: Window; @Published public var posture: Posture; @Published public var cover: Bool; @Published public var stay: Bool
    @Published public var confirmedSunscreen: SunscreenConfirmation      // defaults to .asPrescribed iff headline == .sunscreenForWholeWindow, else .none
    @Published public private(set) var result: DoseResult?; @Published public private(set) var forecastStatus: ForecastResult?
    public private(set) var plannedSessionID: UUID?
    public func compute() async                     // cache → history.state → Planner.plan → upsertPlanned(replacing: plannedSessionID) → prompts.sessionsChanged
    public func refreshForecast() async             // the explicit refresh: forecast.current(force: true) then compute()
    public func didThis() async throws              // logs: actual = span or entered window per headline; doses = attenuated(dose over that window, confirmedSunscreen, cover)
    public func alternative(have: SunscreenChoice) -> AlternativePlan?
    public func useManualPlace(_: Place) async
}
public struct CalculatorEntryView: View, ScreenManifest { public init(model: CalculatorModel, adBanner: AnyView?) }   // (true, false)
public struct ResultView: View, ScreenManifest { public init(model: CalculatorModel) }                                // (false, true)
public struct FigureView: View { public init(figure: Figure, label: String) }   // "estimate" badge iff figure.isEstimate; accessibilityLabel names figure.assumptionKeys via AppCopy
// Promises (S6 via model tests, S15, S10):
//  compute() twice in one model → exactly one planned session; after compute() returns .plan the port holds exactly one pending skinCheck(day) at lastEnd + 20 h
//  changing window or posture between two compute() calls never invokes the provider; refreshForecast() does
//  didThis with headline .bareSubWindow logs actual == plan.span and doses == plan.perRegionDose; with .sunscreenForWholeWindow logs actual == entered window and doses == attenuated(raw over entered, prescribed pair)
//  .alternative(choice) confirmation logs attenuated(raw over entered, choice)
//  warnings shown only when stay; estimate badge iff isEstimate; "change place" reachable from the forecast line
```

### Internals

```text
compute(): loc = await env.location.location(now); coord = loc.coordinate
  fr = await env.forecast.cached(); if fr.curve == nil → fr = await env.forecast.current(for: coord, now)   // a missing cache is the only fetch here (tactical #18)
  state = try env.history.state(now); req = PlanRequest(fr.curve, fr.failure?.kind, coord, now, window, posture, .faceUp, cover, stay ? .stayWholeWindow : .bestMinutes, profile, state, TanningGoal())
  result = Planner.plan(req)
  if case .plan(let plan, _, let headline) = result.outcome:
     confirmedSunscreen = headline == .sunscreenForWholeWindow ? .asPrescribed : .none
     rec = SessionRecord(planned: window, day: curve.day(window.start), ceilingAtPlan: profile.ceiling, manualMultiplierAtPlan: profile.manualMultiplier, curveUsed: curve.stored(for: day), …)
     plannedSessionID = try env.history.upsertPlanned(rec, replacing: plannedSessionID)
     lastEnd = max(window.end, sessions(on: day).map(end).max()); await env.prompts.sessionsChanged(on: day, lastSessionEnd: lastEnd)
didThis(): (actual, doses) per Signatures; choice = confirmedSunscreen → prescribed pair / alternative / nil
  env.history.log(id, actual, sunscreen: choice, doses, factors, targets)
ResultView: outcome card (headline figure + copy) → second answer card (with "I don't have that SPF") → per-region budget rows → warnings → notices (escalation with cycleDose figure) → UVA → forecast line (age, place, "change place", "refresh") → thin margin → Learn links → actions ("Start timer" if lying, "I did this")
SunscreenAlternativeSheet: pickers label from tunables.spfLadder × application → model.alternative → AlternativePlan copy → confirms .alternative(choice)
```

## Slice 4 — The flip timer and Settings

- **Delivers:** The flip timer asks which side is up first, starts the session at the real clock time with the sunscreen confirmation from the calculator, re-solves the sides on the real curve, alerts at the first side's end, the reapplication times and the session end with the screen locked, stops on demand and shortens the record on the actual sub-intervals with attenuation, warns before starting when notifications are denied, and stops itself at the planned end if left past midnight. Settings shows the ceiling selector with the aggressive unlock state, the sensitivity sentence counting reports, override and reset (invalidating the store), unreported logged days, attribution, disclaimer, privacy policy link, export, import (applying the file's profile), and delete history with the R44 warning.
- **Files:** `Sources/IcarusUI/Timer/FlipTimerView.swift`, `Sources/IcarusUI/Timer/FlipTimerModel.swift`, `Sources/IcarusUI/Settings/SettingsView.swift`, `Sources/IcarusUI/Settings/SettingsModel.swift`, `Sources/IcarusUI/Settings/AttributionView.swift`, `Tests/IcarusUITests/FlipTimerModelTests.swift`, `Tests/IcarusUITests/SettingsModelTests.swift`
- **Estimate:** ~540 lines

### Signatures

```text
@MainActor public final class FlipTimerModel: ObservableObject {
    public init(env: AppEnvironment, calculator: CalculatorModel)
    @Published public var firstSide: Side; @Published public private(set) var phase: TimerPhase
    public var notificationsDenied: Bool { get }
    public func start(now: Date) async throws       // re-solves from now with firstSide; logs at start with attenuated doses (calculator.confirmedSunscreen); schedules alerts
    public func stop(now: Date) async throws        // actual end = now; doses re-credited on actual sub-intervals, attenuated; cancels alerts
    public func tick(now: Date)                     // side 1 → side 2 at its end; at sessionEnd → finished (implicit stop at planned end)
    public func foregrounded(now: Date) async       // running past sessionEnd → stop at sessionEnd; sets stoppedAtPlannedEnd (copy .timerStoppedAtPlannedEnd)
}
public enum TimerPhase: Sendable, Equatable { case idle, running(exposure: Exposure, endsAt: Date, sessionEnd: Date), finished(stoppedAtPlannedEnd: Bool) }
public struct FlipTimerView: View, ScreenManifest { public init(model: FlipTimerModel) }   // (false, true)
@MainActor public final class SettingsModel: ObservableObject {
    public init(env: AppEnvironment)
    @Published public var ceiling: Ceiling; public var aggressiveUnlocked: Bool
    public var sensitivitySentence: String           // .sensitivitySentence with percent and report count
    public func overrideMultiplier(_: Double?) async ; public func resetSensitivity() async   // save profile, then env.history.invalidate()
    public var unreportedDays: Int                   // days with a LOGGED session and no report
    public func exportFile() async throws -> URL; public func importFile(_: URL) async throws -> ImportSummary   // applies summary.profile, invalidates
    public func deleteHistory() async throws        // the view shows the R44 warning first
}
public struct SettingsView: View, ScreenManifest { public init(model: SettingsModel) }   // (false, true)
// Promises: start re-solves from now and logs with attenuated doses; stop at half time on a flat curve halves the front dose; alerts: side end, reapply (if any), session end;
//  aggressiveUnlocked iff reports ≥ 5 and a bound in cycle; override then state(now) changes without a write; import applies the file's profile; sentence counts reports; unreportedDays counts logged days
```

### Internals

```text
FlipTimerModel.start: req = calculator's request with window Window(now, entered.end), firstSide; plan = ExposureModel.solve; doses = attenuated(plan.perRegionDose, choice, cover)
  history.log(id, actual: plan.span, sunscreen: choice, doses, …); prompts.scheduleTimer(sideEnd: sides.first.end (lying), reapply: advice?.reapplyAt ∩ span, sessionEnd: span.end)
stop(now): actual = Window(span.start, now); doses = attenuated(Σ sides dose(exposure, cover, over min(side window, now)), choice, cover); history.log(update); prompts.cancelTimer()
SettingsView sections: Target (segmented; aggressive disabled with .aggressiveLocked), Sensitivity (sentence, override, reset), Reports (.unreportedDays), About (AttributionView, disclaimer, privacy policy — the link's URL comes in M7), Data (ShareLink export, fileImporter import, delete with confirmationDialog .deleteHistoryWarning)
```
