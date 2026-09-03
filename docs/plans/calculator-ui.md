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
hold no literal text. The banner slot exists and is wired to the no-op.

Non-goals:
- We do NOT ship real ads or the consent flow (M7); the slot takes an `AnyView?`.
- We do NOT build History screens (M6) or the prompts (M5); the "I did this" action writes a logged session and stops.
- We do NOT write copy in views; a view with a literal user-visible string fails S11.

Owner costs:
- S17: approve every line of `docs/APP_COPY.md` before this milestone starts.
- S9 on a device, with the fake provider.

Rulings: D-2026-09-03-F7, F8 (docs/DECISIONS.md); design revision 3 for sunscreen, warnings and location entry

## The slices

## Slice 1 — App copy as data, and the app shell that composes the packages

- **Delivers:** `docs/APP_COPY.md` exists with a keyed table for every `CopyKey`, skin-type variants where R43 needs them, onboarding text, the skin-type table and quiz, prompts and notifications; `AppCopy.text(_:skinType:)` resolves them from a generated resource; the app target composes the packages behind `AppEnvironment` with the fake provider in previews and tests; the URL scheme routes deep links.
- **Files:** `docs/APP_COPY.md`, `scripts/build-app-copy.sh`, `Sources/IcarusContent/Resources/app-copy.json`, `Sources/IcarusContent/AppCopy.swift`, `Sources/IcarusContent/SkinTypeTable.swift`, `App/ProjectIcarusApp.swift`, `App/AppEnvironment.swift`, `App/RootTabs.swift`, `Tests/IcarusContentTests/AppCopyTests.swift`, `acceptance/S11-static.sh`
- **Estimate:** ~420 lines

### Signatures

```text
public enum AppCopy {
    public static func text(_ key: CopyKey, skinType: SkinType? = nil, args: [String: String] = [:]) -> String
        // falls back to the base variant; missing key is a programmer error surfaced in S11, never an empty string at runtime
    public static var allKeys: Set<CopyKey>
}
public struct SkinTypeRow: Sendable, Equatable { public let type: SkinType; public let name: String; public let description: String; public let citation: Citation }
public enum SkinTypeTable { public static let rows: [SkinTypeRow] /* app copy, Fitzpatrick 1988 */ }
public struct QuizQuestion: Sendable, Equatable { public let id: Int; public let text: String; public let options: [QuizOption] }
public struct QuizOption: Sendable, Equatable { public let text: String; public let points: Int }
public enum FitzpatrickQuiz { public static let questions: [QuizQuestion]; public static func skinType(forScore: Int) -> SkinType }   // published bands
@MainActor public final class AppEnvironment: ObservableObject {
    public let forecast: ForecastService; public let location: LocationService; public let history: HistoryStore
    public let prompts: PromptScheduler; public let ads: any AdBannerProvider; public let tunables: Tunables; public let clock: () -> Date
    public static func live() throws -> AppEnvironment
    public static func preview() -> AppEnvironment     // FakeForecastProvider fixture, in-memory store, NoAdsProvider, fixed clock
}
// App/RootTabs: TabView { Calculator, Learn }; History and Settings via toolbar; handles icarus:// URLs
// Promises (S11, S17): every CopyKey.allCases resolves; every key in app-copy.json is a CopyKey; no string literal in IcarusUI views (S11 grep); docs/APP_COPY.md and app-copy.json agree (script regenerates and diffs)
```

### Internals

```text
docs/APP_COPY.md format: one "### <CopyKey>" heading per key; optional "- fair:" / "- base:" variants; args in {braces}; a table for skin types; a list for quiz questions
scripts/build-app-copy.sh → app-copy.json (key → {base, fair?}); S11 runs it and diffs
acceptance/S11-static.sh: grep for `Text("` / `"..."` literals in Sources/IcarusUI (allowlist: system image names, accessibility ids); `swift package describe` to assert IcarusCore deps == []; grep imports for URLSession/WeatherKit/GoogleMobileAds outside their packages
AppEnvironment.live: WeatherKitProvider, FileForecastCache(Application Support), CoreLocationSource + AppleGeocoder, ModelContainer(SessionEntity, ReportEntity), UserNotificationAdapter, NoAdsProvider (M7 swaps), Tunables.current, Date.init
```

## Slice 2 — Onboarding: Module 1, disclaimer, skin type, permissions

- **Delivers:** First launch shows Module 1 unsoftened, the medical disclaimer to acknowledge, the skin-type table with the optional Fitzpatrick quiz, and asks for location and notification permission with the reason for each; the profile is saved; re-running is possible from Settings.
- **Files:** `Sources/IcarusUI/Onboarding/OnboardingFlow.swift`, `Sources/IcarusUI/Onboarding/SkinTypePicker.swift`, `Sources/IcarusUI/Onboarding/QuizView.swift`, `Sources/IcarusUI/Onboarding/DisclaimerView.swift`, `Sources/IcarusData/ProfileStore.swift`, `Tests/IcarusUITests/OnboardingTests.swift`
- **Estimate:** ~360 lines

### Signatures

```text
public protocol ProfileStore: Sendable { func load() -> Profile?; func save(_: Profile); func flags() -> ProfileFlags; func setFlags(_: ProfileFlags) }
public struct ProfileFlags: Codable, Sendable, Equatable { public var onboardingComplete: Bool; public var disclaimerAcknowledged: Bool; public var adConsentDone: Bool }
public struct UserDefaultsProfileStore: ProfileStore { public init(defaults: UserDefaults = .standard) }
public struct OnboardingFlow: View { public init(onComplete: @escaping (Profile) -> Void) }   // pages: module1 → disclaimer → skinType → permissions
public struct SkinTypePicker: View { public init(selection: Binding<SkinType?>, showQuiz: Binding<Bool>) }
public struct QuizView: View { public init(result: @escaping (SkinType) -> Void) }
// Promises (S9 owner; UI tests): flow cannot complete without disclaimer acknowledged and a skin type; quiz score → type via FitzpatrickQuiz; Module 1 text equals ModuleIndex.module(1).markdown
```

### Internals

```text
OnboardingFlow: @State page; ModuleView(module 1) page with a single continue; DisclaimerView with an explicit acknowledge toggle; SkinTypePicker lists SkinTypeTable.rows, "Not sure?" opens QuizView; permissions page explains location (weather) and notifications (day-after check) via AppCopy keys, requests both, tolerates denial
ProfileStore: JSON in UserDefaults; Profile.ceiling defaults .standard
```

## Slice 3 — Calculator entry and the Result screen

- **Delivers:** The entry screen asks only window, posture, cover toggle and "staying the whole window", with the banner slot at the bottom and no figure; the Result screen shows the outcome per R15 (headline and second answer), per-side or per-region times, the clipped range, remaining budget per region, warnings when they apply, escalation or gap notice with the cycle total, UVA note, forecast age and place with a "change place" entry to manual location, thin-margin and pre-calibration lines, estimate labels on the figures that carry them with VoiceOver text, links into Learn, "I don't have that SPF" with the re-solve, and "I did this" which logs the session.
- **Files:** `Sources/IcarusUI/Calculator/CalculatorEntryView.swift`, `Sources/IcarusUI/Calculator/ResultView.swift`, `Sources/IcarusUI/Calculator/FigureView.swift`, `Sources/IcarusUI/Calculator/SunscreenAlternativeSheet.swift`, `Sources/IcarusUI/Calculator/ManualLocationSheet.swift`, `Sources/IcarusUI/Calculator/CalculatorModel.swift`, `Tests/IcarusUITests/CalculatorModelTests.swift`, `Tests/IcarusUITests/ResultViewTests.swift`
- **Estimate:** ~620 lines

### Signatures

```text
@MainActor public final class CalculatorModel: ObservableObject {
    public init(env: AppEnvironment)
    @Published public var window: Window; @Published public var posture: Posture; @Published public var cover: Bool; @Published public var stay: Bool
    @Published public private(set) var result: DoseResult?
    @Published public private(set) var forecastStatus: ForecastStatus    // fresh | cached(age, place) | none
    public func compute() async                 // location → forecast → history.state → Planner.plan
    public func didThis() async throws          // logs the planned session with the planned window and the confirmed sunscreen
    public func alternative(have: SunscreenChoice) -> AlternativePlan?
    public func useManualPlace(_: Place) async
    public var plannedSessionID: UUID?
}
public struct CalculatorEntryView: View { public init(model: CalculatorModel, adBanner: AnyView?) }   // inputs only — asserted by S15
public struct ResultView: View { public init(model: CalculatorModel) }
public struct FigureView: View { public init(figure: Figure, label: String) }   // shows "estimate" badge iff figure.isEstimate; accessibilityLabel names the assumption
// Promises (S6 via model tests, S15): entry view has no Figure; result for a fixture shows headline per intent; warnings only when stay; estimate badge iff isEstimate; "change place" reachable from the result's place line; didThis writes a logged SessionRecord with curveUsed
```

### Internals

```text
compute(): loc = await env.location.location(now); coord = device/manual coordinate or nil
  fr = await env.forecast.current(for: coord, now); curve = fr.curve?; forecastStatus from fr
  state = try env.history.state(now); req = PlanRequest(curve, deviceLocation: coord, now, window, posture, firstSide: .faceUp, cover, intent: stay ? .stayWholeWindow : .bestMinutes, profile, state, goal: TanningGoal())
  result = Planner.plan(req); if case .plan → env.history.addPlanned(SessionRecord(planned from req and result, curveUsed: curve.dayCurve(window.day))); plannedSessionID = id
didThis(): env.history.log(id, actual: plannedWindow, sunscreen: confirmed, doses: plan.perRegionDose, factors, targets); env.prompts.sessionsChanged(day, lastEnd)
ResultView layout: outcome card (headline figure + copy) → second answer card → per-region budget rows → warnings → notices (escalation with cycleDose figure) → UVA note → forecast line (age, place, "change place") → thin margin → Learn links → actions ("Start timer" if lying, "I did this", "I don't have that SPF")
SunscreenAlternativeSheet: pickers label [15,20,30,50] × application → model.alternative → shows AlternativePlan copy
```

## Slice 4 — The flip timer and Settings

- **Delivers:** The flip timer asks which side is up first, starts the session at the real clock time, re-solves the sides on the real curve, shows the countdown, alerts at the first side's end, reapplication times and the session end with the screen locked, stops on demand and shortens the record, warns before starting when notifications are denied, and stops itself at the planned end if left running past midnight. Settings shows the ceiling selector with the aggressive unlock state, the sensitivity sentence read-only with override and reset, unreported session days, attribution, disclaimer, privacy policy link, export, import, and delete history with the R44 warning.
- **Files:** `Sources/IcarusUI/Timer/FlipTimerView.swift`, `Sources/IcarusUI/Timer/FlipTimerModel.swift`, `Sources/IcarusUI/Settings/SettingsView.swift`, `Sources/IcarusUI/Settings/SettingsModel.swift`, `Sources/IcarusUI/Settings/AttributionView.swift`, `Tests/IcarusUITests/FlipTimerModelTests.swift`, `Tests/IcarusUITests/SettingsModelTests.swift`
- **Estimate:** ~520 lines

### Signatures

```text
@MainActor public final class FlipTimerModel: ObservableObject {
    public init(env: AppEnvironment, model: CalculatorModel)
    @Published public var firstSide: Side
    @Published public private(set) var phase: TimerPhase     // idle | running(side, endsAt) | finished
    public var notificationsDenied: Bool { get }
    public func start(now: Date) async throws                 // logs the session at `now` with re-solved sides; schedules alerts
    public func stop(now: Date) async throws                  // sets actual end, re-credits doses on actual sub-intervals, cancels alerts
    public func tick(now: Date)                               // advances phase; at planned end → finished
}
public enum TimerPhase: Sendable, Equatable { case idle, running(side: Side, endsAt: Date, sessionEnd: Date), finished }
@MainActor public final class SettingsModel: ObservableObject {
    public init(env: AppEnvironment)
    @Published public var ceiling: Ceiling; public var aggressiveUnlocked: Bool
    public var sensitivitySentence: String                    // AppCopy .sensitivitySentence with args percent, count (reports)
    public func overrideMultiplier(_: Double?) ; public func resetSensitivity()
    public var unreportedDays: Int
    public func exportFile() async throws -> URL; public func importFile(_: URL) async throws -> ImportSummary
    public func deleteHistory() async throws                  // the view shows the R44 warning first
}
// Promises (S9 owner; model tests): start re-solves from `now` and logs; stop at half time halves the front dose (flat curve); alerts scheduled: side end, reapply (if any), session end; aggressiveUnlocked iff reports ≥ 5 and a bound in cycle; deleteHistory only after confirmation flag; sentence counts reports not sessions
```

### Internals

```text
FlipTimerModel.start: plan = ExposureModel.solve(request with window from now, firstSide) ; history.log(id, actual: Window(now, now+total), …) ; prompts.scheduleTimer(sideEnd, reapply, sessionEnd)
tick: if now ≥ endsAt of side 1 → running(side 2); if now ≥ sessionEnd → finished (stop implicitly with actual end = sessionEnd)
stop(now): actual = Window(start, now); doses = Σ sides ExposureModel.dose over min(side window, now) ; history.log(update) ; prompts.cancelTimer()
midnight rule: on app foreground, if a running timer's sessionEnd < now → stop at sessionEnd and set a "stoppedAtPlannedEnd" flag the Result shows
SettingsView sections: Target (segmented picker; aggressive disabled with AppCopy .aggressiveLocked), Sensitivity (sentence, override stepper, reset), Reports (unreported days), About (attribution logo + legal link, disclaimer, privacy policy), Data (export via ShareLink, import via fileImporter, delete with confirmationDialog showing .deleteHistoryWarning)
```
