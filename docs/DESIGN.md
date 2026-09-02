---
title: project_icarus
status: in-review        # draft | in-review | approved
created: 2026-09-02
related:
  - docs/BUILD_PROMPT.md               # the owner's build prompt; this doc is derived from it
  - docs/LEARN_CONTENT.md              # the Learn tab copy, verbatim input, never rewritten
  - docs/MELANOGENIC_THRESHOLDS.md     # the owner's addendum on per-skin-type tanning thresholds
  - docs/reviews/design/conceptual-reconciled.md   # stage 2 findings this revision lands
---

# project_icarus — Design Doc

"Icarus" is the code name. The build prompt says "Acuras"; that is a typo, the
name is Icarus. It is a placeholder for the App Store name and must not be baked
into user-facing copy or bundle identifiers in a way that is painful to change.

Revision 2 (2026-09-02): lands the accepted findings of the two conceptual
reviews and the owner's rulings on them. Requirement and criterion ids are
never renumbered; changed ones keep their id, new ones are appended.

## 1. Summary

Icarus is a native iOS app for people who want to build a real, lasting tan
and stay clear of redness the next day. The user enters the time slot they
actually have, how they will be in the sun (lying down and turning over, or up
and about), and the app answers with specifics: how many minutes, per side,
which minutes are best, and which sunscreen applied how, so that the dose lands
at their personal tanning target and never above their personal burn threshold.
A day-after skin check teaches the app their real sensitivity. As their tan
builds, the recommended dose grows with their rising threshold; after a break,
it shrinks again, so the classic after-holiday burn does not happen. A Learn
tab, with every claim cited, says plainly that any tan has a cost. One small
non-personalised ad banner on two entry screens pays for it.

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
- Give each skin type the dose its own biology needs: fair skin rides the line
  it cannot avoid; darker skin tans well below its burn line and is never
  pushed toward it.
- Model adaptation explicitly: escalate the dose as the tan builds, decay it
  during gaps, and say when the biological ceiling is reached.
- Make the body-side reality explicit: which sides get the sun, for how long,
  and what that means for head and shoulders in either posture.
- Teach, with citations, what is actually happening to the skin, including that
  there is no safe threshold and that a tan has a cost.
- Keep the engine, the Learn copy, the app copy, and the UI independently
  changeable.
- Be releasable on the App Store: attribution, disclaimer, and health-app
  scrutiny designed in from the start.
- Earn revenue through one small, non-personalised ad banner that never sits
  on the numbers the user acts on.

**Non-goals**
- No paid APIs, subscriptions, accounts, analytics, or any cost that scales
  with users. The only recurring cost is the Apple Developer Program.
- No personalised advertising, no tracking identifier, no "Allow tracking"
  prompt. The banner runs in non-personalised mode only.
- No Apple Watch app, no widgets, no iPad layout, in this version. These are
  "later, not never": no design decision may block any of them.
- English only.
- No HealthKit integration. No sharing or social features.
- No sunbed mode. Sunbeds are actively discouraged where they come up.
- No per-limb or per-patch modelling beyond the three regions in §7.
- No measurement of pigment. The history is a record of dose, never a claim
  about colour, and the app never asserts a pigment ceiling it cannot see.
- No claim about the weather beyond the forecast's own horizon. The app never
  says "this season".
- No medical advice. The app does not diagnose or treat anything.

## 4. Users & core use cases

The user is an adult who has already decided to tan outdoors and wants to do it
deliberately. They know their rough skin type or can find it from a table. They
are not a dermatology reader; they want a number they can act on and an honest
account of what it costs.

Every use case below is also an acceptance fixture (S18): the numbers in it
are the ones the engine must reproduce from the fixture's forecast and profile.

1. **The lunch-hour slot.** A type II office worker, uncalibrated, has 12:30
   to 13:15 free and will sit in a park. They enter the slot, choose "up and
   about", and get: the best 18 minutes inside that slot at the conservative
   target because the app has no logs yet, with the copy "shorter until the app
   has learned your skin"; that head and shoulders reach the dose in those
   minutes while the front and back get about half; and the option to cover
   head and shoulders with a hat or shirt to run longer. The result says
   sunscreen is not needed for the tanning goal at that dose, shows the day's
   remaining budget per region, and carries the thin-margin line for types I
   and II.

2. **The evening sunbather.** A calibrated type III user has 17:00 to 19:00 by
   a pool and will lie down. The app says the slot is far from solar noon and
   therefore UVA-heavy with little tanning value late on, recommends the
   earliest minutes per side, solved per side on the falling curve so the
   second side gets a few minutes more than the first, starts a flip timer that
   alerts at the first side's end and at the session's end, credits head and
   shoulders with the face-up dose, and notes the UVA ratio with a link to
   Learn Module 3.

3. **The long weekend.** A calibrated type II user has three hours on a beach.
   The raw dose would far exceed their target. The headline is the best
   bare-skin sub-window per side. The second answer is "SPF 30, applied
   normally" for the three hours, with the line that the same tanning dose over
   about four times the minutes carries about four times the UVA, the
   reapplication times, and links to Modules 3 and 8. The two are never shown
   as equivalent.

4. **Two sessions in a day.** The same user goes out again in the afternoon.
   The recommendation is solved against what is left of each region's budget:
   the front has 15% left, so the number is small. If the user enters a longer
   window than that, the result warns; if the window would reach the region's
   burn threshold, it warns strongly in Module 7's burn language. That evening
   there is one skin check, about the whole day.

5. **The return after a break.** A user who tanned regularly through June takes
   three weeks off. On resuming, the app says their tolerance has dropped since
   the last session and recommends a session materially shorter than the last
   one they did, with a link to Learn Module 6.

6. **The plateau.** After five weeks of regular sessions, the recommended
   session has grown from 20 to 36 minutes per side. The result explains that
   the threshold has risen and a fixed dose would no longer trigger new
   pigment, and shows the region's season-to-date dose beside it. When the
   "lasting colour" prompt returns "no" repeatedly near modelled saturation and
   a redness report in this cycle has shown where the line is, the app drops to
   a maintenance dose and says the user has likely reached their maximum. With
   no redness report in the cycle it says instead that it has not yet seen the
   skin react and cannot tell whether the dose is too low or the skin is done.

7. **The day after.** About 20 hours after the day's last session, one
   notification asks how the skin looks today, when any redness showed up,
   on which side, and whether anything unusual applied (medication, illness,
   water or snow, altitude, alcohol). Four days later, a lightweight prompt asks
   about lasting colour. If notifications are off, the same questions wait on
   the next launch. The answers update the user's sensitivity estimate, which
   is visible read-only in Settings.

8. **The type II user who wants to push.** After five logs, one of them pink,
   the aggressive setting unlocks. The target moves to the burn line, never
   past it, and the result says so plainly, with the thin-margin line and the
   note that deciding it is not worth it is a reasonable conclusion.

9. **Offline at the beach.** The forecast was fetched at breakfast at home.
   At the beach, 30 km away with no signal, the result names the place the
   forecast is for and treats it as stale; at three hours it shows the age;
   past six hours it warns that the data may be outdated, widens the range,
   trims the recommendation by the stale reduction, and still gives a number.

## 5. Requirements

**Functional**

Weather and location

- **R1** — Fetch the hourly UV index forecast for the user's location from Apple
  WeatherKit for the provider's full horizon (`forecastHorizonDays`, default
  10, tunable to match what WeatherKit actually returns), including solar noon
  per day, and cache the last successful fetch on device with its fetch time
  and location. Fetch at most once per hour per location (tunable): on
  foreground, on a location change of more than 10 km (tunable), and on
  explicit refresh; never on window or posture change. — *Evidenced by:* S8
- **R2** — Obtain location via CoreLocation with when-in-use permission at
  kilometre accuracy; on denial, offer manual location entry backed by Apple's
  geocoder. — *Evidenced by:* S8
- **R3** — Staleness is a matter of age and place. Show the fetch age whenever
  the forecast is not fresh. At three hours (tunable) the result carries a
  heads-up naming the age. At six hours (tunable), or whenever the device is
  more than 25 km (tunable) from the cache's location or the location is
  unknown, the result warns that the data may be outdated, names the place the
  forecast is for, widens the range by a tunable factor (default 1.5×), and
  reduces the recommendation by `staleReduction` (default 5%, tunable). A
  number is always shown; only a missing forecast shows none.
  — *Evidenced by:* S6

Dose engine

- **R4** — Compute dose by linearly interpolating the hourly UVI series to
  one-minute resolution, integrating over the window by the trapezoidal rule,
  and dividing UVI·minutes by 66.7 to obtain SED. Never average the window's
  endpoints. Cache the interpolated curve; recompute only on new forecast or
  window change. — *Evidenced by:* S1
- **R5** — Personal threshold is `MED_personal = MED_baseline(skinType) ×
  userMultiplier × adaptationFactor(region)`. The three terms are stored and
  updated separately and never collapsed. Baselines, in SED: I 2.0, II 2.5,
  III 3.0, IV 4.5, V 6.0, VI 10.0. **These are the build prompt's baselines
  and they are authoritative.** `docs/MELANOGENIC_THRESHOLDS.md` computed its
  reference table from a different set (III 3.5, IV 5.0); that set is not
  used anywhere in this project, and no agent may substitute it. The build
  prompt's set is the more conservative and it is the owner's ruling.
  — *Evidenced by:* S4
- **R6** — The target dose derives from two thresholds, not from one fixed
  fraction:

  ```
  melanogenicDose = MED_personal × melanogenicFraction(skinType)
  targetDose      = min(melanogenicDose, MED_personal × ceiling)
  ```

  `melanogenicFraction` is static per skin-type band in Tunables, labelled
  `assumption` with its basis in `docs/MELANOGENIC_THRESHOLDS.md`: types I–II
  1.0 (Pathak & Fanselow 1983, solar spectrum), type III 0.95, types IV–VI
  0.75. It never changes with exposure history; all exposure-history dynamics
  live in `adaptationFactor` so the two never compound. `ceiling` is set by
  the Settings selector: conservative 0.75, standard 0.90, aggressive 1.0
  (tunable). For types I–II the ceiling binds, so they ride the line Module 5
  describes; for types III–VI the melanogenic dose binds, so they get a
  genuine no-redness protocol. `targetDose` never exceeds `MED_personal` for
  any type or setting: aggressive means at the line, never past it. The result
  screen says which threshold bound and why, with a link to Module 5.
  — *Evidenced by:* S1
- **R7** — Every recommendation shows a specific number and a range. Until the
  calibration count is reached (`calibrationLogs`, default 3) the number is
  computed at the conservative ceiling whatever the selector says, and the copy
  says "shorter until the app has learned your skin"; after that the number
  sits at the selected ceiling. The range is ±30% (tunable) at n = 0. Its lower
  edge narrows with any report; its upper edge narrows only with redness
  reports, so a user who has never gone pink keeps a wide upper edge. The
  aggressive ceiling unlocks only after `aggressiveUnlockLogs` (default 5)
  logs of which at least one reported redness in the current tan cycle.
  — *Evidenced by:* S6

Body sides and posture

- **R8** — The engine models three skin regions: front, back, and
  head-and-shoulders. Each region carries its own dose today, its own tan state,
  its own adaptation factor, its own remaining budget, and its own solved time.
  The sensitivity multiplier is one number shared by all regions.
  — *Evidenced by:* S5
- **R9** — The user chooses a posture per session. In "lying down, turning
  over", the front side and the back side are each solved per region against
  that region's threshold and remaining budget over the actual sub-interval
  that side will face the sun, so each side receives its target dose rather
  than an equal time; head-and-shoulders is credited with the face-up dose in
  full plus a tunable fraction (default 0.5) of the back-side dose for the
  shoulders. The result shows one "X min per side" figure when the two sides
  differ by less than a tunable fraction (default 15%) and "front X min, back Y
  min" otherwise; the total is the sum. In "up and about", head-and-shoulders
  receive the full session dose while front and back each receive a tunable
  fraction (default 0.5), so the session length is limited by
  head-and-shoulders. — *Evidenced by:* S5
- **R10** — In either posture, a single toggle "head and shoulders covered"
  means opaque cover, a hat or a shirt: that region is logged at zero dose and
  removed from the limit, and in "up and about" the session may run to the
  torso's full time with the doubled exposure explained. Sunscreen is never a
  cover; sunscreen on the face is the session's sunscreen choice applied to
  that region through the R15 model. — *Evidenced by:* S5
- **R11** — For lying-down sessions, a flip timer runs for the session, alerts
  at the first side's end and at the session's end, and works with the screen
  locked via a scheduled local notification. Starting it starts the session at
  the actual clock time and recomputes the per-side times from that start on
  the cached curve. If notification permission is denied it says, before
  starting, that it cannot alert with the screen locked. — *Evidenced by:* S9

Adaptation

- **R12** — Track `tanState ∈ [0, 1]` per region. It rises as a leaky
  integrator of each region's effective dose, where effective dose is the
  region's dose after sunscreen expressed as a fraction of that region's
  personal threshold at the time, so a session at the target advances tanState
  equally for every skin type. The rise time constant is in Tunables, set so
  that daily sessions at the standard target reach tanState 0.8 in about three
  weeks for types I–III and never faster than the two-to-three-week course in
  Module 6, with a type-dependent rise multiplier (default 1.5× for IV–VI). It
  decays toward zero with a half-life of 3.0 weeks (tunable), the fast end of
  the cited 3–4 week range, because the thickening component decays faster than
  pigment (Module 6). `adaptationFactor = 1 + adaptationGain(skinType) ×
  tanState`, with gain capped so the total increase is at most about 2.25× for
  types I–III and about 3× for types IV–VI (tunable). — *Evidenced by:* S4
- **R13** — When the recommended session is longer than the user's first
  because of adaptation, the result card says so, shows the limiting region's
  season-to-date cumulative dose in SED beside the message in the same type
  size as the recommendation, and links to Learn Module 6. On resuming after a
  gap of more than two weeks (tunable), say explicitly that tolerance has
  dropped and that today's recommendation is shorter than what they were doing.
  — *Evidenced by:* S4, S6
- **R14** — The ceiling outcome requires that at least one redness report in
  the current tan cycle has bounded the region's threshold from above. With
  that bound, when `tanState` is near saturation and the lasting-colour prompt
  returns "no" repeatedly (tunable count), stop escalating, drop the
  recommendation to a maintenance dose (`maintenanceFraction`, default 0.7 of
  the current target, tunable), and say the user has likely reached their
  biological maximum and that more buys damage without colour; escalation
  resumes after a later "yes" or "a little". Without that bound the same
  signals produce the under-dosed outcome: the app has not yet seen the skin
  react, so it cannot tell whether the dose is too low or the skin is done,
  and the copy never asserts a pigment ceiling. The lasting-colour answer
  applies to every region that received at least a tunable fraction (default
  0.5) of its target that day. Cumulative dose tracking continues regardless.
  — *Evidenced by:* S4

Sunscreen

- **R15** — When the window's raw dose exceeds the target, the headline is the
  bare-skin sub-window per region ("the best 40 minutes per side, no
  sunscreen"). The second answer solves the full window for a product and
  application pair using `SPF_effective = SPF_label ^ (density / 2)`, with
  reference points 2.0 mg/cm² = full label, 1.0 = square root, 0.5 = fourth
  root, default assumption 1.0 mg/cm². "Realistic" means at most SPF 50
  applied normally (about 7×); thick application is never solved for and is
  offered only as a choice the user can select, and when they do the result
  repeats Module 8's line that almost nobody achieves it. The answer is
  phrased as people think: "SPF 30, applied normally"; a moderate SPF applied
  properly is preferred over a high SPF applied thinly, and the result says
  why. The sunscreen answer always states that the same tanning dose over N
  times the minutes carries roughly N times the UVA, names N, notes that the
  product filters UVB more than UVA unless it carries a UVA rating, names the
  reapplication times when the plan exceeds the reapplication interval (2 h,
  tunable), and links to Modules 3 and 8; the two answers are never presented
  as equivalent. The order is reversed only when the user has marked that they
  will stay out for the whole window. When no realistic combination is enough,
  say so and recommend shortening the window instead. — *Evidenced by:* S2, S6
- **R16** — When no sunscreen is needed for the tanning goal, still surface the
  option, and still say so when the UVA load is high. — *Evidenced by:* S6

Edge cases and notes

- **R17** — Each of these produces a specific, useful answer with copy, never a
  crash, a nil, or a fabricated number: window too weak to matter (with the
  shortfall from the melanogenic dose and the next viable window); window
  massively overshoots (with the optimal sub-window); optimal sub-window inside
  a longer slot (the highest-UVB slice, explained); no viable window in the
  horizon; stale or missing forecast; dose already logged today; cloud cover
  caveat. A window is viable when it can deliver at least a tunable fraction
  (default 0.5) of the target. "Next viable window" is searched across the
  cached horizon only. "No viable window" is the outcome when no hour in the
  horizon reaches viability; its copy says "not in the next N days", names the
  horizon's peak UVI, and never claims a season. — *Evidenced by:* S6
- **R18** — When the window sits well off solar noon (tunable threshold on
  hours from solar noon as supplied by the forecast), show a note that the dose
  is comparatively UVA-heavy and link to Learn Module 3. — *Evidenced by:* S6

Sessions and daily budget

- **R19** — A user may log any number of sessions per day. The recommendation
  is always solved against each region's remaining budget (target minus today's
  logged dose), so the headline number already accounts for earlier sessions.
  When the user's entered window exceeds that recommendation the result warns;
  when it would reach the region's personal threshold (target ÷ ceiling) it
  warns strongly in Module 7's burn language. Both lines are measured against
  the threshold, not the target, so the strong warning means redness is
  expected. — *Evidenced by:* S5

Logging and calibration

- **R20** — One skin-check prompt per day that had sessions, about 20 hours
  (tunable) after the day's last logged session. It asks Q1 "How does your skin
  look today?" with five options from "normal" to "very red, painful, or
  blistered"; Q2 (if any redness) "When did it show up?" with "within an hour
  and gone by evening", "that evening", "the next morning", "not sure"; which
  region (front, back, head and shoulders, or all exposed; default all
  exposed); and a quick "anything unusual?" with photosensitising medication,
  illness or fever, water or snow reflection, altitude, and alcohol. Its
  evidence is the day's summed dose per region and the adaptation factors in
  force that day, and it counts as one log. About four days later (tunable) a
  separate prompt asks "Did you notice lasting colour?" with yes / a little /
  no, likewise per day. If notification permission is denied, or a prompt goes
  unanswered, the skin check is asked in-app on the next launch between 12 and
  72 hours after the day's sessions and the lasting-colour question between 3
  and 10 days after; Settings shows how many session days have no report. MED
  and SED never appear in the logging flow. — *Evidenced by:* S10
- **R21** — A "normal" report is one-sided evidence: it asserts only that the
  threshold lies above the delivered dose. It moves the multiplier upward only
  when the delivered dose was at or above the current estimated threshold for
  that region (dose ratio ≥ 1.0), and then to an implied threshold equal to
  the delivered dose, never higher; at or below the target it is a confirmation
  and changes nothing. Redness reports map to an implied dose-to-threshold ratio
  (tunable table; defaults faint pink 1.0, clearly pink 1.5, red and sore 2.5,
  blistered 4.0) and move it in either direction. Q2 reclassifies: redness that
  appeared within about an hour and had faded by evening is immediate pigment
  darkening, not erythema; the report is calibrated as "normal" and the
  confirmation says so with a link to Module 2. Evidence that the skin
  tolerated more than the model predicted is attributed to the region's
  tanState, which decays; evidence that the skin reacted at a lower dose than
  predicted is attributed to the multiplier, which persists; disagreement in
  the tolerant direction therefore cannot survive a gap. The implied threshold
  is divided by the adaptation factor in force for that region before it
  updates the multiplier. Update: `weight = k / (n + k)` with k ≈ 2.5,
  `multiplier += weight × (implied − multiplier)`; burn observations carry
  twice the weight of no-reaction observations; the effective weight of any
  single update is capped at 1.0. Confounded logs are heavily discounted. The
  multiplier is clamped to [0.5, 1.8] and hitting a clamp prompts the user to
  revisit their skin type. A blistering report applies an immediate protective
  correction regardless of n, suggests a pause of several days, and points to
  Learn Module 7. The multiplier never decays for seasonal change.
  — *Evidenced by:* S3
- **R22** — Every session record stores the adaptation factor per region and
  the target per region in force at the time, so the normalisation in R21 and
  the replay in R44 are possible retrospectively. — *Evidenced by:* S3
- **R23** — Settings shows the sensitivity read-only in plain words ("15% more
  sensitive than typical for your skin type, based on 11 sessions"), with a
  manual override and a reset. — *Evidenced by:* S10

History

- **R24** — A session log (date, window, posture, computed dose per region,
  sunscreen used, outcome), weekly and seasonal cumulative dose per region, and
  a dose-trajectory chart that is labelled as a record of dose, not pigment.
  Weekly and seasonal totals per region ship with M5; the chart with M6.
  — *Evidenced by:* S10
- **R25** — All records persist locally via SwiftData and export to a single
  JSON file through the share sheet. The export is the full session and report
  history plus the Tunables version, and importing it reproduces the state.
  — *Evidenced by:* S10

Learn

- **R26** — The Learn tab renders the twelve modules of `docs/LEARN_CONTENT.md`
  verbatim. Each module is its own content file, editable without touching any
  other module or any view code. Markdown renders including tables and links.
  Every citation renders with authors, title, and a tappable link where the
  source carries a DOI; a citation without a DOI renders the identifier it
  carries (PMID, tappable via PubMed; ISO number; URL) or its text as given,
  and is never assigned an identifier the source does not carry and never
  omitted for lack of a link. `[VERIFY]` markers and the document's preamble
  above Module 1 are build annotations and are never rendered; S7's
  normalisation strips exactly those and whitespace. No citation is
  paraphrased, summarised, or dropped. — *Evidenced by:* S7, S13
- **R27** — Every Learn module is deep-linkable from the calculator, so a
  result screen can point at the relevant explanation. — *Evidenced by:* S7
- **R28** — Onboarding shows Module 1 (or its equivalent) and the "there is no
  safe tan" framing unsoftened, then asks for skin type. The onboarding table
  is the app's own copy in IcarusContent, written to V13 and citing Fitzpatrick
  1988; Module 4's table is Learn copy and stays verbatim under V5. The
  optional quiz is the Fitzpatrick skin-type questionnaire with its published
  scoring bands; questions, bands and citation live in IcarusContent.
  — *Evidenced by:* S9

Compliance and tone

- **R29** — WeatherKit attribution (logo and legal link) is implemented per
  Apple's requirements. A medical disclaimer is persistent and findable from
  every tab. Sunbeds are actively discouraged where they come up.
  — *Evidenced by:* S9
- **R30** — All tunable constants (ceilings, melanogenic fractions, MED
  baselines, k, clamps, decay half-life, rise time constant and multipliers,
  gains and caps, density assumptions, warning thresholds, prompt delays and
  windows, staleness limits and reduction, distance limits, forecast horizon,
  posture fractions, uncertainty band, calibration and unlock counts,
  maintenance fraction, viability fraction, reapplication interval) live in one
  configuration file in the engine. Every entry carries, beside it, either a
  citation into the Learn modules or the addendum, or the word `assumption`
  with a one-line rationale; a result that depends on an `assumption` constant
  is labelled an estimate on screen. — *Evidenced by:* S1

Advertising

- **R39** — One small adaptive banner from Google AdMob, requested in
  non-personalised mode only, shown at the bottom of the Calculator entry
  screen and the Learn module list. The Calculator entry screen holds inputs
  only: no UVI, forecast age, budget, warning, or any figure the user could act
  on; every figure lives on the Result screen. Never on the result screen, the
  flip timer, onboarding, the skin-check or lasting-colour prompts, History, or
  Settings. — *Evidenced by:* S15, S16
- **R40** — The ad SDK lives in its own package behind an `AdBannerProvider`
  protocol with a no-op implementation used by previews, tests, and CI. No ad
  code or import appears in Core, Data, Content, or the rest of UI.
  — *Evidenced by:* S15
- **R41** — Settings links to a privacy policy that states what the ad SDK
  receives; the App Store privacy labels reflect AdMob's non-personalised
  data use; the SDK's non-personalised flag is set before any request.
  — *Evidenced by:* S15, S16

Copy, state, and sessions (added in revision 2)

- **R42** — All non-Learn user-facing copy — outcome keys, warnings, the
  escalation and gap messages, onboarding, the skin-type table and quiz, the
  disclaimer, notification texts, the sensitivity sentence, the thin-margin
  line, the stale-data lines, the delete-data warning — is authored in
  `docs/APP_COPY.md` before M3 begins, rendered by IcarusContent exactly as the
  Learn modules are, and never appears as a literal in a view. The agent
  drafts it; the owner approves every line. — *Evidenced by:* S11, S17
- **R43** — For skin types I and II every result states, in the same copy for
  both, that the margin between a tanning dose and a burn is thin and that
  deciding it is not worth it is a reasonable conclusion; the copy does not
  push either way. The copy key is present for types I and II and absent for
  III–VI. — *Evidenced by:* S6
- **R44** — Region states and the multiplier are derived, never authoritative.
  The ordered session and report history is the record. On launch and after
  every logged session or report, `AdaptationModel` and `CalibrationEngine`
  replay that history under the current Tunables to produce the current state,
  which is cached for display only. A Tunables change therefore takes effect
  for every existing user on next launch. Deleting the history is offered in
  Settings behind a warning that says plainly the app will start over from the
  skin-type prior: calibration, tan state, budgets, and History are all lost,
  and the export is the only way to keep them. — *Evidenced by:* S10
- **R45** — A `Session` is created as *planned* when a result is shown and
  becomes *logged* only by a user action: starting the flip timer, tapping
  "I did this" on the result, or answering "yes" to the skin-check prompt's
  opening question "Did you do this session?". Actual start and end are
  editable at logging. Only logged sessions count toward today's dose,
  tanState, and History; a planned session never logged is discarded at local
  midnight. A skin report adjusts the multiplier; logging is what advances
  tanState. — *Evidenced by:* S5, S10

**Non-functional**

- **R31** — Platform / targets: *(non-functional)* iOS 18 and later, iPhone,
  Swift and SwiftUI. Engine and data layers contain no UI framework imports, and
  UI uses adaptive layouts and observable state, so that an iPad layout, a Watch
  app, and widgets can be added later without restructuring.
- **R32** — Privacy / security / data handling: *(non-functional)* no accounts,
  no analytics, all logs on device. The only network calls are the weather
  fetch, the location lookup that feeds it, and the ad banner's requests in
  non-personalised mode. No tracking identifier is ever sent.
- **R33** — Cost / resource limits: *(non-functional)* zero cost per user. The
  only cost is the Apple Developer Program membership, which the App Store
  release needs anyway. At R1's fetch cadence the included WeatherKit tier
  covers on the order of ten thousand daily users; that is the point at which
  V6 needs revisiting.
- **R34** — Modularity: *(non-functional)* five local Swift packages: Core (pure
  Swift, fully unit-testable with no mocking of network or system services),
  Data, Content, UI, Ads. Changing Learn copy, app copy, tuning the engine,
  adjusting UI, and swapping the ad provider are independent operations.
  Content is data, never string literals in views.
- **R35** — Accessibility: *(non-functional)* Dynamic Type throughout; VoiceOver
  labels on every result figure, warning, and the flip timer.
- **R36** — Tone: *(non-functional)* frank, not preachy, not promotional. Never
  implies tanning is safe. Never moralises at a user who has decided to tan.
  Never presents an estimate as a measurement. Designed for App Store
  health-app review from the start.
- **R37** — Offline / connectivity: *(non-functional)* the calculator works from
  the cached forecast with no network, degrading per R3 rather than failing.
- **R38** — Performance: *(non-functional)* recomputing a result after a window
  or posture change completes within 100 ms on the interpolated curve cache,
  and the R44 replay of a season's history completes within 200 ms.

## 6. Constraints & assumptions

Constraints
- Free to run. WeatherKit's included tier (500,000 calls/month with the
  developer membership) is the data source at R1's cadence; Open-Meteo is the
  named fallback and switching to it requires the owner's explicit decision,
  never a silent swap.
- The forecast horizon is whatever WeatherKit actually forecasts. Nothing in
  the app reasons past it: no clear-sky model, no seasonal table, no claim
  about a season.
- Native Swift and SwiftUI; iOS 18 floor; SwiftData for persistence.
- The Learn copy is an input. It is rendered, never rewritten. The app copy
  (R42) is an owner-approved input too.
- The MED baselines are the build prompt's (R5). The addendum's alternative
  set is reference material only.
- CI builds and tests on macOS runners. The development container has no
  Swift toolchain today; the Core package is designed to also build and test on
  Linux, so that it can be tested where the agent works once a toolchain is
  available, and so that CI can run the engine tests on Linux runners.
- The App Store release needs the Apple Developer Program; nothing before a
  real-device WeatherKit test does.

Assumptions (if wrong, the design changes)
- The UV Index from WeatherKit is erythemally weighted and measured on a
  horizontal surface, and it already accounts for forecast cloud. The
  horizontal-surface assumption is what makes "lying down" the closest match
  to the index; the "up and about" fractions and the shoulder fraction are
  coarse geometric approximations, not measurements, and are labelled
  `assumption`.
- The 66.7 UVI·minute per SED conversion and the MED baselines in R5 are
  accepted priors; calibration exists because they are only priors.
- The melanogenic fractions rest on Pathak & Fanselow for types I–II and on
  the addendum's extrapolation for III–VI; the direction of the effect is
  published, the exact values are not.
- The adaptation constants (half-life, rise, gains, caps) are supported for
  types I–III by the cited literature and are extrapolated for IV–VI.
- The exponential SPF density model is adequate over 0.5–2.0 mg/cm².
- WeatherKit provides solar noon per day. If it does not, the Data layer
  computes it from date and location by formula; the engine's input does not
  change.
- Apple's geocoder is free within the same developer membership.

## 7. Proposed approach (high level)

Five local Swift packages inside the repository, plus the thin app target that
wires them together. Dependencies point one way: UI → Data → Core, UI →
Content, UI → Ads (protocol only), App → all.

- **IcarusCore** (pure Swift, no UI, no networking, no system services) —
  - `Tunables`: the single configuration file of every constant in R30, each
    with its citation or `assumption` note.
  - `Models`: `SkinType`, `Region`, `Posture`, `Window`, `ForecastCurve`,
    `SessionPlan`, `Session` (planned / logged, actual times), `DoseResult`,
    `SunscreenAdvice`, `SkinReport`.
  - `DoseCalculator`: interpolation, trapezoidal integration, SED conversion,
    per-region sub-window search over the cached horizon, UVA note decision
    from solar noon, viability.
  - `ExposureModel`: posture → per-region dose fractions and sub-intervals;
    per-region solved times; cover toggle; remaining budget; the target and
    threshold warning lines.
  - `TargetModel`: the R6 formula — melanogenic dose, ceiling, aggressive
    unlock, conservative-until-calibrated, stale reduction.
  - `AdaptationModel`: per-region `tanState` rise and decay, gain and cap, the
    gap message, the ceiling and under-dosed outcomes, maintenance.
  - `SunscreenSolver`: bare sub-window headline; required attenuation →
    realistic product and application pair; UVA multiple; reapplication
    times; "nothing realistic works".
  - `CalibrationEngine`: report → one-sided or point evidence → Q2
    reclassification → attribution to tanState or multiplier →
    adaptation-normalised, confidence-weighted, asymmetric, capped update;
    clamps; confounders; blistering correction.
  - `Replay`: the R44 fold of the ordered history under the current Tunables
    into current state.
  - `Planner`: composes the above into one `DoseResult` for a window, posture,
    profile, replayed state, and today's logged dose, including every R17 edge
    case as a typed outcome with a copy key.
- **IcarusData** — `UVForecastProvider` protocol with `WeatherKitProvider`
  and `FakeForecastProvider` (used in development, previews, and tests);
  `LocationService` (CoreLocation plus geocoder-backed manual entry, distance
  from the cache); `ForecastCache` (full horizon, solar noon per day, fetch
  time, location, on disk; R1's cadence); the SwiftData store for the profile
  and the ordered session and report history (state is cached, never
  authoritative); JSON export and import; `PromptScheduler` for the one-per-day
  prompts of R20, the in-app fallbacks, and the flip timer alerts of R11.
- **IcarusContent** — the twelve Learn modules as markdown resource files, one
  per module, in the wording of `docs/LEARN_CONTENT.md`; a `ModuleIndex`
  mapping module ids to files and titles for deep links; a `Citation` parser
  that surfaces every citation with its identifier; the app copy of
  `docs/APP_COPY.md` as a keyed table for every engine outcome, warning,
  explanation, prompt, and onboarding text, so that no UI view holds literal
  copy; the onboarding skin-type table and the Fitzpatrick quiz.
- **IcarusAds** — the `AdBannerProvider` protocol, a `NoAdsProvider` no-op,
  and the `AdMobBannerProvider` that wraps the Google Mobile Ads SDK with the
  non-personalised flag set. The only package that imports the SDK.
- **IcarusUI** — SwiftUI views only, no calculation: onboarding (Module 1,
  skin type table and quiz, disclaimer, permissions), Calculator entry (window,
  posture, cover toggle, sunscreen choice, "staying the whole window"; inputs
  only), Result (specific number, range, per-side or per-region times,
  sub-window headline, sunscreen second answer with UVA multiple, remaining
  budget per region, warnings, escalation message with season total, UVA
  note, forecast age and place, links into Learn, "I did this"), Flip Timer,
  Skin Check and Lasting Colour prompts (notification and in-app), History and
  charts, Learn (module list, markdown rendering, tappable citations), Settings
  (ceiling selector with the aggressive unlock state, sensitivity read-only
  with override and reset, unreported session days, attribution, disclaimer,
  privacy policy, export, import, delete history with its warning).
- **App target** — composes the packages, owns the tab bar (Calculator, Learn,
  with History and Settings reachable from them), and injects the real
  providers, including the AdMob provider in release builds and the no-op in
  previews and tests.

Data flow: location → forecast fetch on R1's cadence → cache → `ForecastCurve`
(interpolated once, reused) → `Replay` of the history into current state →
`Planner` with profile, state, today's logged dose → `DoseResult` → Result
view. Showing a result creates a planned `Session`; a user action logs it with
actual times and per-region dose after sunscreen, with the adaptation factors
and targets in force; the day's skin report attaches to the day; the next
replay folds both in. Nothing writes state directly.

## 8. Key design decisions & alternatives

1. **Five local Swift packages, not folders in one target.**
   Options: folders and naming discipline; local packages; a single package
   with several targets. Choice: local packages. The compiler enforces the
   "Core imports no UI, no network" rule instead of a code review; Core can be
   built and tested on Linux, which is where the agent works and the cheap CI
   runner is; the app target stays a thin shell, which is also what keeps Watch
   and widget targets possible later. Cost: the template's CI scripts assume
   `Sources/` and `Tests/`; the plan for milestone 1 includes adjusting them.

2. **Apple WeatherKit, with Open-Meteo as a named fallback.**
   Options: WeatherKit; Open-Meteo; both. Choice: WeatherKit behind a
   `UVForecastProvider` protocol. It is the source the built-in Weather app
   uses, so the user's mental model matches; it needs no key in the app; it
   supplies solar noon and a multi-day horizon. Open-Meteo is free and keyless
   but is a different number from the one the user sees in Weather. Switching
   is an owner decision, never silent. The protocol makes the switch a
   one-file change.

3. **Three regions with separate tan state; one shared sensitivity.**
   Options: one body-wide state with posture only changing the time shown;
   three regions; finer patches. Choice: three regions, each with its own
   solved time. Front and back do tan independently in real life, and
   head-and-shoulders is the region that limits walking sessions and is
   exposed face-up while lying. Sensitivity is intrinsic to the person, so one
   number. Finer patches would need input nobody would give.

4. **Posture as an explicit input with an opaque-cover toggle.**
   Options: ignore posture; ask posture; infer from motion. Choice: ask, with
   two modes and one toggle that means a hat or a shirt. Inference is
   unreliable and privacy-noisy; ignoring posture double-doses head and
   shoulders on every walk; treating sunscreen as cover contradicts the app's
   own sunscreen model.

5. **Sensitivity and adaptation kept separate, and the separation is learned,
   not asserted.** Options: one learned number; two terms with adaptation
   divided out; two terms with directional attribution. Choice: directional
   attribution. Evidence the skin tolerated more than predicted goes to the
   decaying tan state; evidence it reacted sooner goes to the persistent
   multiplier. Dividing out the modelled adaptation alone would book every
   model error in the tolerant direction to a number that never decays, which
   is the winter-return burn.

6. **One-sided "normal" evidence; confidence-weighted, asymmetric, capped
   update.** `k / (n + k)` with burns weighted 2× and a per-update cap of 1.0.
   Options: point estimate for every answer; running average; Bayesian update
   with censoring; this. Choice: this. A "normal" report as a point estimate
   walks a correctly typed user up to their burn line; as a lower bound it
   only confirms or raises when the dose already exceeded the estimate.

7. **Exponential SPF density model, default square root of label, realistic
   ceiling at SPF 50 applied normally.** Options: label SPF; linear scaling;
   exponential with no ceiling; exponential with a ceiling. Choice: the last.
   Without a ceiling almost any window is solvable and the "shorten the
   window" outcome never fires.

8. **A specific number plus a range, conservative until calibrated.**
   Options: a range only; a number only; a number at the selected ceiling from
   day one; a number at the conservative ceiling until three logs. Choice: the
   last. V2 says err shorter when unsure, and before three logs the model is
   at its most unsure; after that the number sits at the selected ceiling and
   the range says the rest. The range's upper edge narrows only with redness
   reports, because only those bound the threshold from above.

9. **Unlimited sessions per day, solved against what is left, with warnings at
   the target and the threshold.** Options: one session per day; unlimited with
   warnings against the target; unlimited with warnings against the threshold;
   hard block. Choice: solve against the remaining budget so the headline is
   right, warn past the target, warn strongly only at the threshold, so the
   burn language means redness is expected and is never learned to be ignored.

10. **Flip timer in the MVP, and it is the session clock.** Options: display
    per-side numbers only; timer later; timer now. Choice: now, per the owner.
    Starting it starts the session at the real clock time and re-solves the
    sides on the real curve.

11. **Learn modules as markdown files rendered by MarkdownUI.**
    Options: hand-built SwiftUI views per module; Apple's `AttributedString`
    markdown; a markdown renderer package. Choice: markdown files plus the
    MarkdownUI package. Apple's built-in markdown does not render tables and
    two modules have them; hand-built views put copy in code, which R34
    forbids. MarkdownUI is isolated inside IcarusUI so it can be replaced.

12. **Solar noon and the horizon from the forecast, not computed.**
    Options: compute sun position by formula; take solar noon from WeatherKit;
    add a clear-sky UVI model for "next viable window" and "season". Choice:
    WeatherKit's values, the whole horizon cached, passed into the engine as
    inputs. Nothing reasons past the forecast. The formula remains the fallback
    for solar noon only.

13. **Apple's geocoder for manual location.** Options: raw coordinates;
    geocoder. Choice: geocoder. It is free within the same membership; the
    vision names it explicitly as part of the weather fetch so it does not
    violate the network tenet.

14. **SwiftData for the history, derived state, JSON for export and import.**
    Options: stored mutable state nudged per event; derived state replayed
    from the history. Choice: derived. The history is the record; the numbers
    are recomputed from it under the current Tunables, so a tuned constant
    applies to everyone at once and a fixed bug heals every user's state.
    Cost: a replay per event, bounded by R38; deleting the history means
    starting over, and the app says so (R44).

15. **Local notifications for the day-after and four-day prompts, one per day,
    with in-app fallbacks.** Prompting the same evening collects near-worthless
    data because erythema peaks at 12–24 hours; the skin reports the whole day,
    not one session; a user without notifications must still be able to
    calibrate. Delays and windows are tunables.

16. **iOS 18 floor.** "Current minus one" as of writing; SwiftData and Swift
    Charts are available; more devices can install than iOS 26.

17. **Nothing that blocks iPad, Watch, or widgets.** Core and Data have no UI
    imports; UI is SwiftUI with adaptive layouts and no fixed sizes; app state
    lives in observable models the app target owns, not in views.

18. **One AdMob banner, non-personalised only, on input-only screens.**
    Options: no ads and a paid app; AdMob personalised; AdMob
    non-personalised; a smaller privacy-first network. Choice: AdMob in
    non-personalised mode. It is the network with the fill to actually pay,
    and non-personalised mode sends no tracking identifier, so the app needs
    no "Allow tracking" prompt and keeps a clean privacy label for a
    health-adjacent review. The banner is confined to two entry screens that
    carry no figure, so an ad can never sit beside a dose. A "remove ads"
    one-time purchase is a later option that stacks on this.

19. **The target derives from two thresholds.** Options: one fixed fraction of
    MED for everyone; per-type fractions; the min of a melanogenic dose and a
    ceiling. Choice: the min. Fair skin's tanning dose sits at its burn dose,
    so the ceiling binds and it rides the line; darker skin's tanning dose sits
    well below, so the melanogenic dose binds and it never approaches a burn,
    which is what the app's own Module 5 teaches. The melanogenic fraction is
    static per band; exposure history lives only in the adaptation factor, so
    the two never compound. The MED baselines are the build prompt's, by
    ruling, because they are the more conservative set.

20. **Aggressive means at the line, unlocked by evidence.** Options: always
    available; never; unlocked after calibration. Choice: unlocked after five
    logs of which at least one was redness in the current cycle. The
    aggressive ceiling is 1.0 × MED and never above, because the app has then
    seen where the user's line is; before that it has not.

21. **A session is real when the user says so.** Options: every shown result
    counts; only reported sessions count; only user-logged sessions count.
    Choice: user-logged, by timer start, "I did this", or the skin check's
    opening question. Counting shown results escalates users who stayed
    indoors; counting only reports never escalates users who ignore
    notifications.

22. **The bare-skin sub-window is the headline when the window overshoots.**
    Options: sunscreen first; sub-window first. Choice: sub-window first, with
    the sunscreen answer second and its UVA multiple named. The sunscreen
    route is the higher-photoaging route for the same pigment and the app's
    own Modules 3 and 8 say so; the differentiator is offered, never sold as
    equivalent.

23. **Stale data degrades the number, it never withholds it.** Options: refuse
    past six hours (the build prompt's wording); show a shorter, wider number
    with the age in the headline. Choice: the second, by the owner's ruling. A
    calculation on old data at the beach is more useful than none; the
    reduction is a tunable so it can move.

## 9. Data model / key entities

- **UserProfile** — skin type (I–VI); ceiling preference (conservative /
  standard / aggressive); manual sensitivity override flag and value;
  onboarding complete; disclaimer acknowledged; notification permission state.
- **Session** (the record) — created-at; planned start and end; actual start
  and end; location; forecast fetch time and place used; posture; cover
  toggle; sunscreen choice (label SPF and application level, or none);
  "staying the whole window"; state (planned / logged); per-region dose after
  sunscreen (SED); per-region adaptation factor and target in force; day key.
- **SkinReport** (the record) — day key; report time; Q1; Q2; region;
  confounders; four-day lasting-colour answer when it arrives; whether it came
  by notification or in-app.
- **DerivedState** (cache, never authoritative) — sensitivity multiplier; log
  count n; redness-in-cycle flag; per-region `tanState`, last exposure, "no
  lasting colour" count near ceiling; today's per-region dose; season-to-date
  per-region dose; the Tunables version it was computed under.
- **Forecast** (cached) — location; fetched-at; hourly UVI series for the full
  horizon; solar noon per day; provider name; horizon days.
- **Tunables** — the configuration file, versioned, each entry annotated,
  exported with the JSON so a report can be reproduced.
- **LearnModule** — id, title, file name; **Citation** — authors, title,
  venue, year, identifier kind and value, verify flag; **AppCopy** — key,
  text, skin-type applicability.

## 10. External dependencies & integrations

- Apple WeatherKit (hourly UV index for its full horizon, solar noon). Requires
  the WeatherKit capability and Apple's attribution.
- CoreLocation and CLGeocoder (location and manual entry).
- UserNotifications (day-after prompt, four-day prompt, flip timer alerts).
- SwiftData (persistence), Swift Charts (history), SwiftUI.
- MarkdownUI (Swift package) for Learn rendering.
- Google Mobile Ads SDK (AdMob) for the banner, isolated in IcarusAds and used
  in non-personalised mode. Needs an AdMob account, an app id, and a privacy
  policy URL. These two are the only third-party dependencies.
- Apple Developer Program (for WeatherKit on device, TestFlight, App Store).
- Named fallback only: Open-Meteo hourly `uv_index`, keyless.

## 11. Risks & open questions

- **Citations marked `[VERIFY]`**, and the addendum's own flagged sources (the
  1.16 ratio from a patent's secondary table; the Wulf year conflation), must
  be confirmed before shipping. Any that do not resolve are reported in
  `docs/reviews/citations.md`, never silently dropped (S13).
- **The melanogenic fractions for III–VI** are the addendum's extrapolations
  and are labelled so. If a literature pass moves them, only Tunables changes.
- **"Up and about" and shoulder fractions** are geometric approximations,
  labelled `assumption`, and every result that depends on them is labelled an
  estimate.
- **Per-region reports.** A user who reports "red and sore" on "all exposed"
  gives one data point for three regions with different doses. The
  calibration uses the region with the highest dose as the evidence; this is a
  choice to review at the tactical stage.
- **WeatherKit in development.** Real WeatherKit calls need signing and the
  developer membership. Until then, all development and CI use the fake
  provider; the first live test is an owner criterion (S8, S9). The actual
  horizon WeatherKit returns is confirmed then and `forecastHorizonDays` set
  to match.
- **App Store health-app review.** The disclaimer and the "no safe threshold"
  framing are both required; review may still ask for changes to wording.
- **MarkdownUI maintenance.** A third-party renderer can lag an iOS release.
  It is isolated in IcarusUI; the fallback is a small in-house renderer for
  the subset the modules use.
- **The ad SDK.** It is large, it makes network calls of its own, and its
  privacy disclosures must be mirrored in the App Store labels. Non-personalised
  fill and revenue are lower than personalised. Isolating it in one package
  behind a protocol keeps it swappable; the no-op provider keeps it out of
  tests and CI entirely.
- **Toolchain in the agent's container.** No Swift on Linux today, so Core
  tests run only in CI until the network policy allows a toolchain download.
- **Cloud and reflection.** Forecast UVI accounts for forecast cloud; actual
  conditions, reflection, and altitude are outside the model and are covered
  by copy and confounders, not by the engine.
- **UVA note is qualitative.** The UV Index is nearly blind to UVA; the note is
  triggered by distance from solar noon and the UVA multiple by session
  length, not by a UVA measurement.
- **Replay cost.** Derived state is a fold over the history on every event;
  R38 bounds it, and a season is a few hundred records.

## 12. Milestones / phasing

Milestones are coarse phases; slicing happens in plans.

**MVP** (M1–M5)
- **M1 — Core engine.** IcarusCore package with Tunables, Models,
  DoseCalculator, ExposureModel, TargetModel, AdaptationModel,
  SunscreenSolver, CalibrationEngine, Replay, Planner, and the full test suite:
  the build prompt's §7 tests, the posture, region, budget and stale tests,
  the calibration and separation simulations with their fixed response model,
  and the use-case fixtures. CI scripts adjusted for the package layout, with
  Core tests on a Linux runner. *Done when* S1–S6 and S18 (use cases 1–6, 8,
  9) pass in CI.
- **M2 — Data.** WeatherKit provider behind the protocol, fake provider,
  location and geocoder entry with distance from the cache, forecast cache for
  the full horizon at R1's cadence, SwiftData history store with replayed
  state, JSON export and import, prompt scheduler with in-app fallbacks.
  *Done when* S8 (agent part) passes and the fake provider drives the engine
  end to end.
- **M3 — App copy, Calculator, Result, Flip Timer, Onboarding.**
  `docs/APP_COPY.md` approved (S17); onboarding with Module 1, the app's
  skin-type table and the Fitzpatrick quiz, disclaimer; calculator entry with
  inputs only; result with number, range, per-side or per-region times,
  sub-window headline, sunscreen second answer with UVA multiple, remaining
  budget, warnings, escalation message with season total, UVA note, forecast
  age and place, thin-margin line, Learn links, "I did this"; flip timer as
  the session clock; attribution; the banner slot wired to the no-op ad
  provider. *Done when* S9 can be run by the owner on a device with the fake
  provider and S14 passes.
- **M4 — Learn.** IcarusContent with the twelve module files and citation
  index; Learn tab with markdown rendering, tables, tappable identifiers,
  deep links, markers stripped. *Done when* S7 passes and the S13 verification
  report exists.
- **M5 — Logging and calibration.** One-per-day prompts with in-app fallbacks,
  skin check flow with Q2, region and confounders, calibration update through
  replay, Settings with the ceiling selector and aggressive unlock, sensitivity
  sentence with override and reset, unreported days, delete-history warning,
  weekly and seasonal totals per region. *Done when* S10 passes, S3 holds
  against real report flows, and S18 adds use case 7.

**Later**
- **M6 — History.** Session log view, dose-trajectory chart, export and import
  UI.
- **M7 — Release readiness.** Accessibility pass (S9), edge-case copy pass,
  live WeatherKit on device with the horizon confirmed, the AdMob provider
  wired in with the non-personalised flag and the privacy policy link (S15,
  S16), TestFlight, App Store listing with the health disclaimer and privacy
  labels.

## 13. Success criteria

Unmarked criteria become scripts under `acceptance/`; `(owner)` criteria are
the owner's to judge.

- **S1** — *(covers R4, R6, R30)* — The Core test suite passes: trapezoidal
  integration matches a known analytic curve within 0.5%; the 14:00–17:00
  steep-then-flat window differs materially from the naive endpoint average and
  the trapezoidal result is the correct one; a calibrated type II at multiplier
  1.0, standard ceiling and steady UVI 7 yields about 21 minutes; a type IV at
  multiplier 1.0 is planned materially shorter, as a fraction of MED, than a
  type II, and the melanogenic dose is what bound it; no setting produces a
  target above MED for any type; every constant used by the engine is read
  from the single Tunables file and every entry carries a citation or an
  `assumption` note.
- **S2** — *(covers R15)* — SPF density tests: label 50 at 2.0, 1.0, and 0.5
  mg/cm² yields effective 50, about 7.07, and about 2.66; the solver prefers
  "SPF 30 applied normally" over "SPF 50 applied thinly" when both suffice; a
  required attenuation of 8 returns the shorten-the-window outcome; the
  sunscreen answer carries the UVA multiple with N computed and the
  reapplication times when the plan exceeds the interval.
- **S3** — *(covers R21, R22)* — Calibration simulation with a fixed response
  model in the acceptance script, not the test author's choice: the simulated
  reporter answers Q1 from the true dose-to-threshold ratio with bands normal
  < 0.95, faint pink 0.95–1.15, clearly pink 1.15–2.0, red and sore 2.0–4.0,
  blistered ≥ 4.0, and the bands live in Tunables beside the implied-ratio
  table. A user whose true multiplier is 0.75 converges to within 0.05 within 8
  logs; one "normal" outlier at log 15 moves the multiplier by at most 0.05 and
  one "red and sore" report at log 15 moves it down by at least 0.10 and at
  most 0.20; a user at true multiplier 1.0 reporting truthfully at the standard
  ceiling for 20 logs moves by no more than 0.05. The separation simulation
  runs with the simulated user's true adaptation gain at 0.7× and at 1.3× the
  modelled gain; in both cases the multiplier stays within 0.10 of 1.0 after
  six weeks and the first post-gap recommendation is at or below the simulated
  user's true threshold. A blistering report applies the protective correction
  at any n; the clamp triggers the revisit-skin-type outcome; a "faint pink"
  report with the immediate-darkening Q2 answer moves the multiplier as
  "normal" does.
- **S4** — *(covers R5, R12, R13, R14)* — Adaptation simulation where
  "regular sessions" means five sessions per week at the standard ceiling,
  stated in the acceptance script: six weeks raises the adaptation factor,
  saturates below the cap for the skin type, lengthens the recommended session,
  and escalation after one week is below 25% of the eventual cap; a four-week
  gap after that makes the next recommendation materially shorter (at least
  25%) than the pre-gap one and produces the tolerance-dropped message. **A
  regression here is a release blocker.** Repeated "no lasting colour" near
  saturation with a redness bound in the cycle drops to the maintenance dose
  with the ceiling message; without the bound it produces the under-dosed
  outcome and never the ceiling copy.
- **S5** — *(covers R8, R9, R10, R19, R45)* — Posture and budget tests:
  lying-down credits each region with its own target dose over its own
  sub-interval, and the total equals twice the per-side time only when the
  regions are equal and the UVI is flat; on a sloping curve the two sides get
  different times and the result shows two figures past the 15% difference;
  a lying-down session credits head-and-shoulders with the face-up dose and a
  following up-and-about session the same day is limited by that credit;
  up-and-about is limited by head-and-shoulders with front and back at the
  tunable fraction; the cover toggle logs head-and-shoulders at zero and lifts
  the limit; a second session is solved against the remaining budget per
  region; an entered window past the target warns and one reaching the
  threshold warns strongly; a planned session never logged contributes
  nothing after midnight.
- **S6** — *(covers R3, R7, R13, R15, R16, R17, R18, R43)* — Every R17 edge
  case, given its fixture forecast, returns a typed outcome with a copy key and
  the expected figures (shortfall from the melanogenic dose, sub-window, next
  viable window within the horizon, "not in the next N days"), never nil or a
  crash; a forecast at three hours carries the heads-up, at six hours the
  warning, the widened range and the stale reduction, and a cache 30 km away is
  stale at any age; a window far from solar noon carries the UVA flag; every
  result carries a specific number and a range, the number is at the
  conservative ceiling before three logs, the upper edge narrows only with
  redness reports, the aggressive ceiling is refused before five logs with a
  redness report; an escalated result carries the cumulative-dose figure; the
  thin-margin copy key is present for types I and II and absent for III–VI.
- **S7** — *(covers R26, R27)* — Content tests: twelve module files load; the
  module text equals the corresponding section of `docs/LEARN_CONTENT.md`
  after stripping exactly the `[VERIFY]` markers, the preamble, and
  whitespace; every citation in the source appears in the rendered module
  model with its identifier intact and no citation is missing; every module
  id resolves for deep links.
- **S8** — *(covers R1, R2, R37)* — Data tests with the fake provider: a
  forecast round-trips through the cache with location, horizon, solar noon,
  and fetch time; age is computed correctly across a day boundary; the fetch
  cadence holds (no fetch on window change, one within an hour, one after a
  10 km move); the WeatherKit mapping converts a recorded response fixture
  into the curve the engine expects; the manual location path resolves a
  fixture place name. **(owner)** the live WeatherKit fetch on a signed device
  returns the same UV figures as the built-in Weather app for the same hour,
  and the horizon it returns is recorded in Tunables.
- **S9** — **(owner)** *(covers R11, R28, R29, R31, R35, R36)* — On a device:
  onboarding shows Module 1 unsoftened and the disclaimer; the flip timer alerts
  at the first side's end and at the session's end with the screen locked;
  WeatherKit attribution and the disclaimer are findable from every tab;
  VoiceOver reads every figure and warning on the result screen; the copy reads
  frank and not preachy.
- **S10** — *(covers R20, R23, R24, R25, R44, R45)* — Logging and state tests:
  a day with two logged sessions schedules one skin-check prompt after the last
  and one lasting-colour prompt at four days; the prompt's evidence is the
  day's summed dose; with notifications denied the questions are asked in-app
  within their windows; each Q1 answer produces the expected multiplier
  movement via replay; the Settings sentence renders from derived state; a
  Tunables change followed by a replay changes derived state for an existing
  history; the JSON export round-trips every record and the tunables version
  and importing it reproduces the derived state; deleting the history shows
  the warning and resets to the prior; weekly and seasonal totals per region
  are computed from the history.
- **S11** — *(covers R32, R34, R42)* — Static checks: IcarusCore imports
  nothing but Foundation; no `URLSession` or `WeatherKit` import outside
  IcarusData; no `GoogleMobileAds` import outside IcarusAds; no Learn copy or
  app copy string literal appears in IcarusUI; every user-visible string in
  IcarusUI resolves through IcarusContent; every key in
  `docs/APP_COPY.md` is referenced and every referenced key exists.
- **S12** — **(owner)** *(covers R33)* — No cost beyond the Apple Developer
  Program appears in any dependency, service, or plan.
- **S13** — **(owner)** *(covers R26)* — Every `[VERIFY]` citation and every
  source the addendum flags has been checked against doi.org or PubMed,
  corrected only in identifier, year or venue where wrong, and any that does
  not resolve is reported in `docs/reviews/citations.md` rather than dropped.
- **S14** — *(covers R38)* — A performance test recomputes a result after a
  window change 100 times on the cached curve in under 100 ms each on the CI
  runner, and replays a 200-record history in under 200 ms.
- **S15** — *(covers R39, R40, R41)* — Ad tests and static checks: the AdMob
  provider sets the non-personalised flag before its first request (asserted
  on a recorded request configuration); the result, flip timer, onboarding,
  prompt, History, and Settings views contain no banner slot; the Calculator
  entry and Learn list views contain exactly one and the entry view contains
  no figure; the no-op provider is what tests and previews receive.
- **S16** — **(owner)** *(covers R39, R41)* — On a device with a live AdMob
  app id: a banner loads on the Calculator entry screen and the Learn list,
  appears nowhere else, and the privacy policy link in Settings opens.
- **S17** — **(owner)** *(covers R42)* — Every string in `docs/APP_COPY.md`
  was written or approved by the owner, and the file exists before M3 begins.
- **S18** — *(covers R6, R9, R13, R15, R19, R21, R45)* — Each §4 use case is
  a fixture under `acceptance/`: a forecast series, profile, history, window,
  posture, and the expected outcome type, headline minutes within ±10%,
  per-region doses, and the copy keys named in the use case. M1 is not done
  until use cases 1–6, 8 and 9 pass; M5 adds 7.
