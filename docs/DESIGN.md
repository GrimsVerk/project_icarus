---
title: project_icarus
status: draft            # draft | in-review | approved
created: 2026-09-02
related:
  - docs/BUILD_PROMPT.md      # the owner's build prompt; this doc is derived from it
  - docs/LEARN_CONTENT.md     # the Learn tab copy, verbatim input, never rewritten
---

# project_icarus — Design Doc

"Icarus" is the code name. The build prompt says "Acuras"; that is a typo, the
name is Icarus. It is a placeholder for the App Store name and must not be baked
into user-facing copy or bundle identifiers in a way that is painful to change.

## 1. Summary

Icarus is a free, native iOS app for people who want to build a real, lasting tan
and stay clear of redness the next day. The user enters the time slot they
actually have, how they will be in the sun (lying down and turning over, or up
and about), and the app answers with specifics: how many minutes, per side,
which minutes are best, and which sunscreen applied how, so that the dose lands
at about 90% of their personal burn threshold. A day-after skin check teaches the
app their real sensitivity. As their tan builds, the recommended dose grows with
their rising threshold; after a break, it shrinks again, so the classic
after-holiday burn does not happen. A Learn tab, with every claim cited, says
plainly that any tan has a cost.

## 2. Problem & motivation

Most people cannot be outside at solar noon. Their free slot sits on the shoulder
of the UV curve, and working out what that slot is worth means integrating a
changing UV index over time, knowing one's own burn threshold, and knowing how
much a given sunscreen, applied the way people really apply it, attenuates the
dose. Nobody does that arithmetic by hand, so people guess, and guessing produces
two failures: burns, and the plateau where a dose that worked in week one stops
producing colour in week three because the threshold has moved. The second
failure is the more common one for deliberate tanners and no consumer app
handles it. A third, dangerous failure is the return from a break at a dose that
felt easy before the break.

Existing UV apps show an index and a generic "time to burn". They do not take a
window, do not solve for sunscreen, do not learn the user, and do not model
adaptation or its decay.

## 3. Goals and non-goals

**Goals**
- Turn a real time slot into specific, honest numbers: minutes per side, best
  sub-window, sunscreen product and application, and the day's remaining budget.
- Stay under the user's personal burn threshold, and learn that threshold from
  day-after reports rather than from the skin-type prior alone.
- Model adaptation explicitly: escalate the dose as the tan builds, decay it
  during gaps, and say when the biological ceiling is reached.
- Make the body-side reality explicit: which sides get the sun, for how long,
  and what that means for head and shoulders when walking around.
- Teach, with citations, what is actually happening to the skin, including that
  there is no safe threshold and that a tan has a cost.
- Keep the engine, the Learn copy, and the UI independently changeable.
- Be releasable on the App Store: attribution, disclaimer, and health-app
  scrutiny designed in from the start.

**Non-goals**
- No paid APIs, subscriptions, accounts, analytics, or any cost that scales
  with users. The only recurring cost is the Apple Developer Program.
- No Apple Watch app, no widgets, no iPad layout, in this version. These are
  "later, not never": no design decision may block any of them.
- English only.
- No HealthKit integration. No sharing or social features.
- No sunbed mode. Sunbeds are actively discouraged where they come up.
- No per-limb or per-patch modelling beyond the three regions in §7.
- No measurement of pigment. The history is a record of dose, never a claim
  about colour.
- No medical advice. The app does not diagnose or treat anything.

## 4. Users & core use cases

The user is an adult who has already decided to tan outdoors and wants to do it
deliberately. They know their rough skin type or can find it from a table. They
are not a dermatology reader; they want a number they can act on and an honest
account of what it costs.

1. **The lunch-hour slot.** A type II office worker has 12:30 to 13:15 free
   and will sit in a park. They enter the slot, choose "up and about", and get:
   the best 22 minutes inside that slot, that head and shoulders reach the dose
   in those 22 minutes while the front and back get about half, and the option
   to cover head and shoulders to run longer. They also get told sunscreen is
   not needed for the tanning goal at that dose, and that the day's remaining
   budget is now small.

2. **The evening sunbather.** A type III user has 17:00 to 19:00 by a pool and
   will lie down. The app says the slot delivers a strong UVA-heavy dose with
   little tanning value late on, recommends the earliest 30 minutes per side, 60
   total, starts a flip timer that alerts at the turn-over point, and notes the
   UVA ratio with a link to Learn Module 3.

3. **The long weekend.** A user has three hours on a beach. The raw dose would
   far exceed their target. The app solves for "SPF 30, applied normally" for the
   three hours, explains that application thickness matters more than the label
   number, and offers the alternative: 40 minutes per side, no sunscreen.

4. **Two sessions in a day.** The same user goes out again in the afternoon.
   The app carries forward the morning's dose per region, shows the front is
   already at 85% of its budget, and warns when the planned session would pass
   90%. Past 100% the warning uses the burn language from Learn Module 7.

5. **The return after a break.** A user who tanned regularly through June takes
   three weeks off. On resuming, the app says their tolerance has dropped since
   the last session and recommends a session materially shorter than the last
   one they did, with a link to Learn Module 6.

6. **The plateau.** After five weeks of regular sessions, the recommended
   session has grown from 20 to 38 minutes per side. The app explains that the
   threshold has risen and a fixed dose would no longer trigger new pigment.
   When the "lasting colour" prompt returns "no" repeatedly near the modelled
   ceiling, the app stops escalating and says the user has likely reached their
   biological maximum.

7. **The day after.** About 20 hours after a session, a notification asks how
   the skin looks today, on which side, and whether anything unusual applied
   (medication, illness, water or snow, altitude, alcohol). Four days later, a
   lightweight prompt asks about lasting colour. The answers update the user's
   sensitivity estimate, which is visible read-only in Settings.

8. **The type I user.** A very fair user runs the calculator. The app gives
   the number, says plainly that their margin is thin, and that deciding it is
   not worth it is a reasonable conclusion. It does not push either way.

9. **Offline at the beach.** With no signal, the app uses the cached forecast,
   shows its age prominently, and refuses to give a confident recommendation
   once the data is older than six hours.

## 5. Requirements

**Functional**

Weather and location

- **R1** — Fetch the hourly UV index forecast for the user's location from Apple
  WeatherKit, including the day's solar noon, and cache the last successful
  fetch on device with its fetch time. — *Evidenced by:* S8
- **R2** — Obtain location via CoreLocation with when-in-use permission at
  kilometre accuracy; on denial, offer manual location entry backed by Apple's
  geocoder. — *Evidenced by:* S8
- **R3** — Show the age of the forecast prominently whenever it is not fresh,
  and block confident recommendations on data older than six hours (tunable).
  — *Evidenced by:* S6

Dose engine

- **R4** — Compute dose by linearly interpolating the hourly UVI series to
  one-minute resolution, integrating over the window by the trapezoidal rule,
  and dividing UVI·minutes by 66.7 to obtain SED. Never average the window's
  endpoints. Cache the interpolated curve; recompute only on new forecast or
  window change. — *Evidenced by:* S1
- **R5** — Personal threshold is `MED_baseline(skinType) × userMultiplier ×
  adaptationFactor(region)`. The three terms are stored and updated separately
  and never collapsed. Baselines: I 2.0, II 2.5, III 3.0, IV 4.5, V 6.0, VI 10.0
  SED. — *Evidenced by:* S4
- **R6** — The target dose is a tunable fraction of the personal threshold,
  selectable in Settings as conservative / standard / aggressive, mapping to
  0.75 / 0.90 / 0.95, default standard. — *Evidenced by:* S1
- **R7** — Every recommendation shows a specific number at the target fraction
  and a range that reflects the current uncertainty: about ±30% (tunable) before
  any logs, narrowing as logs accumulate. — *Evidenced by:* S6

Body sides and posture

- **R8** — The engine models three skin regions: front, back, and
  head-and-shoulders. Each region carries its own dose today, its own tan state,
  and its own adaptation factor. The sensitivity multiplier is one number shared
  by all regions. — *Evidenced by:* S5
- **R9** — The user chooses a posture per session. In "lying down, turning
  over", front and back each receive the full per-side time and the session
  total is twice the per-side time; the result is shown as "X min per side, Y
  min total". In "up and about", head-and-shoulders receive the full session
  dose while front and back each receive about half (tunable fraction), so the
  session length is limited by head-and-shoulders. — *Evidenced by:* S5
- **R10** — In "up and about", a single toggle "head and shoulders covered"
  (hat, shirt, or SPF 30+) removes that region from the limit and lets the
  session run to the torso's full time, with the doubled head-and-shoulders
  exposure explained. — *Evidenced by:* S5
- **R11** — For lying-down sessions, a flip timer runs for the session, alerts
  at the turn-over point and at the end, and works with the screen locked via a
  scheduled local notification. — *Evidenced by:* S9

Adaptation

- **R12** — Track `tanState ∈ [0, 1]` per region, rising with cumulative recent
  effective dose with diminishing returns so it saturates, and decaying toward
  zero with a half-life of about 3.5 weeks (tunable) without exposure.
  `adaptationFactor = 1 + adaptationGain(skinType) × tanState`, with gain capped
  so the total increase is at most about 2.25× for types I–III and about 3× for
  types IV–VI (tunable). — *Evidenced by:* S4
- **R13** — When the recommended session is longer than the user's first
  because of adaptation, say so and link to Learn Module 6. On resuming after a
  gap of more than two weeks (tunable), say explicitly that tolerance has
  dropped and that today's recommendation is shorter than what they were doing.
  — *Evidenced by:* S4
- **R14** — When `tanState` is near saturation and the lasting-colour prompt
  returns "no" repeatedly (tunable count), stop escalating and say the user has
  likely reached their biological maximum and further dose buys damage without
  colour. Cumulative dose tracking continues regardless. — *Evidenced by:* S4

Sunscreen

- **R15** — When the window's raw dose exceeds the target, solve for a product
  and application pair using `SPF_effective = SPF_label ^ (density / 2)`, with
  reference points 2.0 mg/cm² = full label, 1.0 = square root, 0.5 = fourth
  root, default assumption 1.0 mg/cm². Phrase the answer as people think:
  "SPF 30, applied normally". Prefer a moderate SPF applied properly over a high
  SPF applied thinly and say why. When no realistic combination is enough, say
  so and recommend shortening the window instead. — *Evidenced by:* S2
- **R16** — When no sunscreen is needed for the tanning goal, still surface the
  option, and still say so when the UVA load is high. — *Evidenced by:* S6

Edge cases and notes

- **R17** — Each of these produces a specific, useful answer with copy, never a
  crash, a nil, or a fabricated number: window too weak to matter (with the
  shortfall and the next viable window); window massively overshoots (with the
  optimal sub-window); optimal sub-window inside a longer slot (the highest-UVB
  slice, explained); no viable day this season; stale or missing forecast;
  dose already logged today; cloud cover caveat. — *Evidenced by:* S6
- **R18** — When the window sits well off solar noon (tunable threshold on
  hours from solar noon as supplied by the forecast), show a note that the dose
  is comparatively UVA-heavy and link to Learn Module 3. — *Evidenced by:* S6

Sessions and daily budget

- **R19** — A user may log any number of sessions per day. Dose per region
  accumulates through the day and is subtracted from the remaining budget. When
  a planned or logged session would take a region past 90% (tunable) of its
  target, warn; past 100%, warn strongly using the burn language of Learn
  Module 7. — *Evidenced by:* S5

Logging and calibration

- **R20** — About 20 hours after a session (tunable), a local notification asks
  Q1 "How does your skin look today?" with five options from "normal" to "very
  red, painful, or blistered", Q2 (if any redness) "When did it show up?", which
  region (front, back, head and shoulders, or all exposed; default all
  exposed), and a quick "anything unusual?" with photosensitising medication,
  illness or fever, water or snow reflection, altitude, and alcohol. About four
  days later (tunable) a separate prompt asks "Did you notice lasting colour?"
  with yes / a little / no. MED and SED never appear in the logging flow.
  — *Evidenced by:* S10
- **R21** — Each Q1 answer maps to an implied dose-to-threshold ratio (tunable
  table; defaults normal 0.7, faint pink 1.0, clearly pink 1.5, red and sore
  2.5, blistered 4.0). The implied threshold is divided by the adaptation
  factor in force for that region at the session before it updates the
  multiplier. Update: `weight = k / (n + k)` with k ≈ 2.5, `multiplier +=
  weight × (implied − multiplier)`. Burn observations carry twice the weight of
  no-reaction observations. Confounded logs are heavily discounted. The
  multiplier is clamped to [0.5, 1.8] and hitting a clamp prompts the user to
  revisit their skin type. A blistering report applies an immediate protective
  correction regardless of n, suggests a pause of several days, and points to
  Learn Module 7. The multiplier never decays for seasonal change.
  — *Evidenced by:* S3
- **R22** — Every session record stores the adaptation factor per region in
  force at the time, so the normalisation in R21 is possible retrospectively.
  — *Evidenced by:* S3
- **R23** — Settings shows the sensitivity read-only in plain words ("15% more
  sensitive than typical for your skin type, based on 11 sessions"), with a
  manual override and a reset. — *Evidenced by:* S10

History

- **R24** — A session log (date, window, posture, computed dose per region,
  sunscreen used, outcome), weekly and seasonal cumulative dose per region, and
  a dose-trajectory chart that is labelled as a record of dose, not pigment.
  — *Evidenced by:* S10
- **R25** — All records persist locally via SwiftData and export to a single
  JSON file through the share sheet. — *Evidenced by:* S10

Learn

- **R26** — The Learn tab renders the twelve modules of `docs/LEARN_CONTENT.md`
  verbatim. Each module is its own content file, editable without touching any
  other module or any view code. Markdown renders including tables and links.
  Every citation renders with authors, title, and a tappable DOI link. No
  citation is paraphrased, summarised, or dropped. — *Evidenced by:* S7, S13
- **R27** — Every Learn module is deep-linkable from the calculator, so a
  result screen can point at the relevant explanation. — *Evidenced by:* S7
- **R28** — Onboarding shows Module 1 (or its equivalent) and the "there is no
  safe tan" framing unsoftened, then asks for skin type via the six-row table
  with plain factual descriptions and an optional short quiz for those unsure.
  — *Evidenced by:* S9

Compliance and tone

- **R29** — WeatherKit attribution (logo and legal link) is implemented per
  Apple's requirements. A medical disclaimer is persistent and findable from
  every tab. Sunbeds are actively discouraged where they come up.
  — *Evidenced by:* S9
- **R30** — All tunable constants (target fractions, MED baselines, k, clamps,
  decay half-life, gains and caps, density assumptions, warning thresholds,
  prompt delays, staleness limit, posture fractions, uncertainty band) live in
  one configuration file in the engine. — *Evidenced by:* S1

**Non-functional**

- **R31** — Platform / targets: *(non-functional)* iOS 18 and later, iPhone,
  Swift and SwiftUI. Engine and data layers contain no UI framework imports, and
  UI uses adaptive layouts and observable state, so that an iPad layout, a Watch
  app, and widgets can be added later without restructuring.
- **R32** — Privacy / security / data handling: *(non-functional)* no accounts,
  no analytics, all logs on device. The only network calls are the weather fetch
  and the location lookup that feeds it.
- **R33** — Cost / resource limits: *(non-functional)* zero cost per user. The
  only cost is the Apple Developer Program membership, which the App Store
  release needs anyway.
- **R34** — Modularity: *(non-functional)* four local Swift packages: Core (pure
  Swift, fully unit-testable with no mocking of network or system services),
  Data, Content, UI. Changing Learn copy, tuning the engine, and adjusting UI
  are three independent operations. Content is data, never string literals in
  views.
- **R35** — Accessibility: *(non-functional)* Dynamic Type throughout; VoiceOver
  labels on every result figure, warning, and the flip timer.
- **R36** — Tone: *(non-functional)* frank, not preachy, not promotional. Never
  implies tanning is safe. Never moralises at a user who has decided to tan.
  Never presents an estimate as a measurement. Designed for App Store
  health-app review from the start.
- **R37** — Offline / connectivity: *(non-functional)* the calculator works from
  the cached forecast with no network, degrading with an age indicator rather
  than failing.
- **R38** — Performance: *(non-functional)* recomputing a result after a window
  or posture change completes within 100 ms on the interpolated curve cache.

## 6. Constraints & assumptions

Constraints
- Free to run. WeatherKit's included tier (500,000 calls/month with the
  developer membership) is the data source; Open-Meteo is the named fallback
  and switching to it requires the owner's explicit decision, never a silent
  swap.
- Native Swift and SwiftUI; iOS 18 floor; SwiftData for persistence.
- The Learn copy is an input. It is rendered, never rewritten.
- CI builds and tests on macOS runners. The development container has no
  Swift toolchain today; the Core package is designed to also build and test on
  Linux, so that it can be tested where the agent works once a toolchain is
  available.
- The App Store release needs the Apple Developer Program; nothing before a
  real-device WeatherKit test does.

Assumptions (if wrong, the design changes)
- The UV Index from WeatherKit is erythemally weighted and measured on a
  horizontal surface, and it already accounts for forecast cloud. The
  horizontal-surface assumption is what makes "lying down" the closest match
  to the index; the "up and about" fractions are a coarse geometric
  approximation, not a measurement.
- The 66.7 UVI·minute per SED conversion and the MED baselines in R5 are
  accepted priors; calibration exists because they are only priors.
- The adaptation constants (half-life, gains, caps) are supported for types
  I–III by the cited literature and are extrapolated for IV–VI.
- The exponential SPF density model is adequate over 0.5–2.0 mg/cm².
- WeatherKit provides solar noon per day. If it does not, the Data layer
  computes it from date and location by formula; the engine's input does not
  change.
- Apple's geocoder is free within the same developer membership.

## 7. Proposed approach (high level)

Four local Swift packages inside the repository, plus the thin app target that
wires them together. Dependencies point one way: UI → Data → Core, UI →
Content, App → all.

- **IcarusCore** (pure Swift, no UI, no networking, no system services) —
  - `Tunables`: the single configuration file of every constant in R30.
  - `Models`: `SkinType`, `Region`, `Posture`, `Window`, `ForecastCurve`,
    `SessionPlan`, `DoseResult`, `SunscreenAdvice`, `SkinReport`.
  - `DoseCalculator`: interpolation, trapezoidal integration, SED conversion,
    best sub-window search, UVA note decision from solar noon.
  - `ExposureModel`: posture → per-region dose fractions; per-side timing;
    cover toggle; daily budget and the 90% / 100% warnings.
  - `AdaptationModel`: per-region `tanState`, growth, decay, gain and cap,
    the gap message, the ceiling detection.
  - `SunscreenSolver`: required attenuation → product and application pair;
    preference for proper application; "nothing realistic works" outcome.
  - `CalibrationEngine`: report → implied ratio → adaptation-normalised,
    confidence-weighted, asymmetric multiplier update; clamps; confounders;
    blistering correction.
  - `Planner`: composes the above into one `DoseResult` for a window, posture,
    profile, region states, and today's logged dose, including every §R17
    edge case as a typed outcome with a copy key.
- **IcarusData** — `UVForecastProvider` protocol with `WeatherKitProvider`
  and `FakeForecastProvider` (used in development, previews, and tests);
  `LocationService` (CoreLocation plus geocoder-backed manual entry);
  `ForecastCache` (last forecast, solar noon, fetch time, location, on disk);
  SwiftData store for profile, sessions, reports, and region states; JSON
  export; `PromptScheduler` for the local notifications in R20 and the flip
  timer alerts in R11.
- **IcarusContent** — the twelve Learn modules as markdown resource files, one
  per module, in the wording of `docs/LEARN_CONTENT.md`; a `ModuleIndex`
  mapping module ids to files and titles for deep links; a `Citation` parser
  that surfaces every citation with its DOI; the copy table for engine outcome
  keys (edge-case copy, warnings, explanations) so that no UI view holds
  literal copy.
- **IcarusUI** — SwiftUI views only, no calculation: onboarding (Module 1,
  skin type table and quiz, disclaimer, permissions), Calculator (window,
  posture, cover toggle, sunscreen choice), Result (specific number, range,
  per-side times, sub-window, sunscreen advice, warnings, UVA note, forecast
  age, links into Learn), Flip Timer, Skin Check and Lasting Colour prompts,
  History and charts, Learn (module list, markdown rendering, tappable
  citations), Settings (target selector, sensitivity read-only with override
  and reset, attribution, disclaimer, export).
- **App target** — composes the packages, owns the tab bar (Calculator, Learn,
  with History and Settings reachable from them), and injects the real
  providers.

Data flow: location → forecast fetch → cache → `ForecastCurve` (interpolated
once, reused) → `Planner` with profile, region states, today's dose → `DoseResult`
→ Result view. A logged session writes a `Session` with per-region dose and the
adaptation factors in force; the day-after `SkinReport` runs through
`CalibrationEngine` to update the shared multiplier and through
`AdaptationModel` to update per-region states.

## 8. Key design decisions & alternatives

1. **Four local Swift packages, not folders in one target.**
   Options: folders and naming discipline; local packages; a single package
   with several targets. Choice: local packages. The compiler enforces the
   "Core imports no UI, no network" rule instead of a code review; Core can be
   built and tested on Linux, which is where the agent works; the app target
   stays a thin shell, which is also what keeps Watch and widget targets
   possible later. Cost: the template's CI scripts assume `Sources/` and
   `Tests/`; the plan for milestone 1 includes adjusting them.

2. **Apple WeatherKit, with Open-Meteo as a named fallback.**
   Options: WeatherKit; Open-Meteo; both. Choice: WeatherKit behind a
   `UVForecastProvider` protocol. It is the source the built-in Weather app
   uses, so the user's mental model matches; it needs no key in the app; it
   supplies solar noon. Open-Meteo is free and keyless but is a different
   number from the one the user sees in Weather. Switching is an owner
   decision, never silent. The protocol makes the switch a one-file change.

3. **Three regions with separate tan state; one shared sensitivity.**
   Options: one body-wide state with posture only changing the time shown;
   three regions; finer patches. Choice: three regions. Front and back do tan
   independently in real life, and head-and-shoulders is the region that limits
   walking sessions. Sensitivity is intrinsic to the person, so one number.
   Finer patches would need input nobody would give.

4. **Posture as an explicit input with a cover toggle.**
   Options: ignore posture; ask posture; infer from motion. Choice: ask, with
   two modes and one toggle. Inference is unreliable and privacy-noisy;
   ignoring posture double-doses head and shoulders on every walk.

5. **Sensitivity and adaptation kept separate; adaptation normalised out of
   every log before the multiplier updates.**
   Options: one learned number; two terms. Choice: two terms, as the build
   prompt requires. One number attributes tan-driven tolerance to intrinsic
   sensitivity, never decays, and produces the winter-return burn.

6. **Confidence-weighted, asymmetric multiplier update.**
   `k / (n + k)` with burns weighted 2×. Options: running average; Bayesian
   update with censoring; this. Choice: this, as specified: first logs move
   the estimate far, later logs nudge; "nothing happened" is censored data
   and is weighted accordingly.

7. **Exponential SPF density model, default square root of label.**
   Options: label SPF; linear scaling; exponential. Choice: exponential,
   as cited in Learn Module 8. Output phrased as product and application, and
   the solver prefers proper application of a moderate SPF.

8. **A specific number plus a range.**
   Options: a range only; a number only; both. Choice: both. A range alone
   leaves the user to decide, which is the complexity the app exists to remove;
   a number alone hides uncertainty. The number sits at the target fraction;
   the range narrows as logs arrive.

9. **Unlimited sessions per day with budget warnings at 90% and 100%.**
   Options: one session per day; unlimited with warnings; hard block. Choice:
   unlimited with warnings. Blocking a log discards evidence; the warning uses
   the honest burn language.

10. **Flip timer in the MVP.** Options: display per-side numbers only; timer
    later; timer now. Choice: now, per the owner. A per-side number without a
    timer is a number the user has to remember while lying in the sun.

11. **Learn modules as markdown files rendered by MarkdownUI.**
    Options: hand-built SwiftUI views per module; Apple's `AttributedString`
    markdown; a markdown renderer package. Choice: markdown files plus the
    MarkdownUI package. Apple's built-in markdown does not render tables and
    two modules have them; hand-built views put copy in code, which R34
    forbids. MarkdownUI is the project's single third-party dependency and is
    isolated inside IcarusUI so it can be replaced.

12. **Solar noon from the forecast, not computed.**
    Options: compute sun position by formula; take solar noon from WeatherKit.
    Choice: WeatherKit's value, cached with the forecast, passed into the
    engine as an input. Less code, no second source of truth; the formula
    remains the fallback if the field is absent.

13. **Apple's geocoder for manual location.** Options: raw coordinates;
    geocoder. Choice: geocoder. It is free within the same membership; the
    vision names it explicitly as part of the weather fetch so it does not
    violate the "no other network calls" tenet.

14. **SwiftData for persistence, JSON for export.** Options: Core Data;
    SwiftData; files. Choice: SwiftData on iOS 18; one JSON export through the
    share sheet. Export is the user's escape hatch and the debugging aid.

15. **Local notifications for the day-after and four-day prompts.** Prompting
    the same evening collects near-worthless data because erythema peaks at
    12–24 hours. Delays are tunables.

16. **iOS 18 floor.** "Current minus one" as of writing; SwiftData and Swift
    Charts are available; more devices can install than iOS 26.

17. **Nothing that blocks iPad, Watch, or widgets.** Core and Data have no UI
    imports; UI is SwiftUI with adaptive layouts and no fixed sizes; app state
    lives in observable models the app target owns, not in views.

## 9. Data model / key entities

- **UserProfile** — skin type (I–VI); sensitivity multiplier (start 1.0); log
  count n; target preference (conservative / standard / aggressive); manual
  override flag and value; onboarding complete; disclaimer acknowledged.
- **RegionState** ×3 (front, back, headAndShoulders) — `tanState`; last
  exposure date; consecutive "no lasting colour" count near ceiling.
- **Forecast** (cached) — location; fetched-at; hourly UVI series for the day
  and the next; solar noon per day; provider name.
- **Session** — start, end; location; posture; cover toggle; sunscreen choice
  (label SPF and application level, or none); forecast fetch time used;
  computed dose per region (SED); adaptation factor per region in force;
  target dose per region in force; whether planned, logged, or both.
- **SkinReport** — session reference; report time; Q1 answer; Q2 answer;
  region; confounders; four-day lasting-colour answer when it arrives;
  the multiplier before and after the update (for the Settings sentence and
  the export).
- **Tunables** — the configuration file, versioned, exported with the JSON so
  a report can be reproduced.
- **LearnModule** — id, title, file name; **Citation** — authors, title,
  venue, year, DOI or note, verify flag.

## 10. External dependencies & integrations

- Apple WeatherKit (hourly UV index, solar noon). Requires the WeatherKit
  capability and Apple's attribution.
- CoreLocation and CLGeocoder (location and manual entry).
- UserNotifications (day-after prompt, four-day prompt, flip timer alerts).
- SwiftData (persistence), Swift Charts (history), SwiftUI.
- MarkdownUI (Swift package) for Learn rendering. The only third-party
  dependency.
- Apple Developer Program (for WeatherKit on device, TestFlight, App Store).
- Named fallback only: Open-Meteo hourly `uv_index`, keyless.

## 11. Risks & open questions

- **Citations marked `[VERIFY]`.** Nine citations in the Learn copy must be
  confirmed to resolve to the stated paper before shipping. Any that do not are
  reported back, never silently dropped (S13).
- **"Up and about" fractions.** The half-dose for front and back and the full
  dose for head-and-shoulders are geometric approximations. They are tunables
  and are labelled as estimates in the result; the conceptual review should
  challenge them.
- **Adaptation constants for types IV–VI** are extrapolated. The ceiling
  detection is qualitative.
- **Per-region reports.** A user who reports "red and sore" on "all exposed"
  after a walking session gives one data point for three regions with
  different doses. The calibration uses the region with the highest dose as
  the evidence; this is a choice to review.
- **WeatherKit in development.** Real WeatherKit calls need signing and the
  developer membership. Until then, all development and CI use the fake
  provider; the first live test is an owner criterion (S8, S9).
- **App Store health-app review.** The disclaimer and the "no safe threshold"
  framing are both required; review may still ask for changes to wording.
- **MarkdownUI maintenance.** A third-party renderer can lag an iOS release.
  It is isolated in IcarusUI; the fallback is a small in-house renderer for
  the subset the modules use (headings, paragraphs, bold, lists, tables,
  links, blockquotes).
- **Toolchain in the agent's container.** No Swift on Linux today, so Core
  tests run only in CI until the network policy allows a toolchain download.
  This slows the engine milestone; it does not change the design.
- **Cloud and reflection.** Forecast UVI accounts for forecast cloud; actual
  conditions, reflection, and altitude are outside the model and are covered
  by copy and confounders, not by the engine.
- **UVA note is qualitative.** The UV Index is nearly blind to UVA; the note is
  triggered by distance from solar noon, not by a UVA measurement.

## 12. Milestones / phasing

Milestones are coarse phases; slicing happens in plans.

**MVP** (M1–M5)
- **M1 — Core engine.** IcarusCore package with Tunables, Models,
  DoseCalculator, ExposureModel, AdaptationModel, SunscreenSolver,
  CalibrationEngine, Planner, and the full test suite of §7 of the build
  prompt plus the posture and daily-budget tests. CI scripts adjusted for the
  package layout. *Done when* S1–S6 pass in CI.
- **M2 — Data.** WeatherKit provider behind the protocol, fake provider,
  location and geocoder entry, forecast cache with age, SwiftData store,
  JSON export, prompt scheduler. *Done when* S8 (agent part) passes and the
  fake provider drives the engine end to end.
- **M3 — Calculator, Result, Flip Timer, Onboarding.** Onboarding with
  Module 1, skin type table and quiz, disclaimer; calculator with window,
  posture, cover toggle, sunscreen choice; result with number, range, per-side
  times, sub-window, sunscreen advice, warnings, UVA note, forecast age, Learn
  links; flip timer; attribution. *Done when* S9 can be run by the owner on a
  device with the fake provider and S14 passes.
- **M4 — Learn.** IcarusContent with the twelve module files and citation
  index; Learn tab with markdown rendering, tables, tappable DOIs, deep links.
  *Done when* S7 passes and the S13 verification report exists.
- **M5 — Logging and calibration.** Day-after and four-day prompts, skin
  check flow with region and confounders, calibration update, Settings
  sensitivity sentence with override and reset, daily budget carry-forward.
  *Done when* S10 passes and S3 holds against real report flows.

**Later**
- **M6 — History.** Session log, weekly and seasonal totals per region,
  dose-trajectory chart, export UI.
- **M7 — Release readiness.** Accessibility pass (S9), edge-case copy pass,
  live WeatherKit on device, TestFlight, App Store listing with the health
  disclaimer.

## 13. Success criteria

Unmarked criteria become scripts under `acceptance/`; `(owner)` criteria are
the owner's to judge.

- **S1** — *(covers R4, R6, R30)* — The Core test suite passes: trapezoidal
  integration matches a known analytic curve within 0.5%; the 14:00–17:00
  steep-then-flat window differs materially from the naive endpoint average and
  the trapezoidal result is the correct one; type II at multiplier 1.0 and
  steady UVI 7 yields about 21 minutes to 0.9 MED; every constant used by the
  engine is read from the single Tunables file.
- **S2** — *(covers R15)* — SPF density tests: label 50 at 2.0, 1.0, and 0.5
  mg/cm² yields effective 50, about 7.07, and about 2.66; the solver prefers
  "SPF 30 applied normally" over "SPF 50 applied thinly" when both suffice; an
  attenuation no realistic pair delivers returns the "shorten the window"
  outcome.
- **S3** — *(covers R21, R22)* — Calibration simulation: a user whose true
  multiplier is 0.75 converges to within 0.05 within 8 logs and is not moved by
  more than 0.03 by one outlier at log 15; a user with true multiplier 1.0 who
  tans normally for six weeks stays within 0.05 of 1.0 while adaptation
  accumulates; a blistering report applies the protective correction at any n;
  the clamp triggers the revisit-skin-type outcome.
- **S4** — *(covers R5, R12, R13, R14)* — Adaptation simulation: six weeks of
  regular sessions raises the adaptation factor, saturates below the cap for
  the skin type, and lengthens the recommended session; a four-week gap after
  that makes the next recommendation materially shorter (at least 25%) than the
  pre-gap one and produces the tolerance-dropped message. **A regression here
  is a release blocker.** Repeated "no lasting colour" near saturation stops
  escalation and produces the ceiling message.
- **S5** — *(covers R8, R9, R10, R19)* — Posture and budget tests: lying-down
  total equals twice the per-side time and both regions receive the full
  per-side dose; up-and-about is limited by head-and-shoulders with front and
  back at the tunable fraction; the cover toggle lifts the limit and reports the
  head-and-shoulders exposure; two sessions in one day accumulate per region and
  trigger the 90% warning and the 100% strong warning at the right doses.
- **S6** — *(covers R3, R7, R16, R17, R18)* — Every §R17 edge case, given its
  fixture forecast, returns a typed outcome with a copy key and the expected
  figures (shortfall, sub-window, next viable window), never nil or a crash;
  forecast data older than six hours returns the stale outcome; a window far
  from solar noon carries the UVA flag; every result carries a specific number
  and a range whose width shrinks as n grows.
- **S7** — *(covers R26, R27)* — Content tests: twelve module files load; the
  module text equals the corresponding section of `docs/LEARN_CONTENT.md`
  after normalisation; every citation in the source appears in the rendered
  module model with its DOI link intact; every module id resolves for deep
  links.
- **S8** — *(covers R1, R2, R37)* — Data tests with the fake provider: a
  forecast round-trips through the cache with location, solar noon, and fetch
  time; age is computed correctly across a day boundary; the WeatherKit mapping
  converts a recorded response fixture into the curve the engine expects; the
  manual location path resolves a fixture place name. **(owner)** the live
  WeatherKit fetch on a signed device returns the same UV figures as the
  built-in Weather app for the same hour.
- **S9** — **(owner)** *(covers R11, R28, R29, R31, R35, R36)* — On a device:
  onboarding shows Module 1 unsoftened and the disclaimer; the flip timer alerts
  at the turn-over point with the screen locked; WeatherKit attribution and the
  disclaimer are findable from every tab; VoiceOver reads every figure and
  warning on the result screen; the copy reads frank and not preachy.
- **S10** — *(covers R20, R23, R24, R25)* — Logging tests: a logged session
  schedules the skin-check prompt at the tunable delay and the lasting-colour
  prompt at four days; each Q1 answer produces the expected multiplier movement
  via the engine; the Settings sentence renders from profile state; the JSON
  export round-trips every entity and the tunables version.
- **S11** — *(covers R32, R34)* — Static checks: IcarusCore imports nothing
  but Foundation; no `URLSession` or `WeatherKit` import outside IcarusData; no
  Learn copy string literal appears in IcarusUI; every user-visible string in
  IcarusUI resolves through IcarusContent.
- **S12** — **(owner)** *(covers R33)* — No cost beyond the Apple Developer
  Program appears in any dependency, service, or plan.
- **S13** — **(owner)** *(covers R26)* — Every `[VERIFY]` citation has been
  checked against doi.org, corrected where wrong, and any that does not resolve
  is reported in `docs/reviews/citations.md` rather than dropped.
- **S14** — *(covers R38)* — A performance test recomputes a result after a
  window change 100 times on the cached curve in under 100 ms each on the CI
  runner.
