# Tactical review 2 — the settled pseudocode plans (blind)

Reviewed as they stand on `docs/tactical-pass-2`: `core-engine.md`,
`data-layer.md`, `calculator-ui.md`, `learn-tab.md`,
`logging-calibration.md`, `history.md`, `release-readiness.md`, read against
`docs/DESIGN.md` (revision 3), `docs/VISION.md`, `docs/DECISIONS.md`, the
build prompt, the melanogenic addendum, `docs/LEARN_CONTENT.md`, and the
scripts that consume plans (`plan-parse.sh`, `plan-contracts.sh`,
`test-the-tests.sh`, `plan-format.sh`). No earlier review and no git history
were read. Every number below was recomputed from the formulas in the plans;
the simulation used the plan's own update rule (decay by elapsed time at a
21-day half-life, then the closed-form rise with τ = 7.2, five sessions a
week, the S3 reporter bands, the tolerant credit, and the `k / (n + k)`
weights).

## Overall build risk

The engine plan is unusually complete for a pseudocode pass, and most of the
numbers a test will assert do come out of the stated formulas: 21.44 minutes,
the SPF ladder values, the weights, τ = 7.2 landing 21 daily sessions at
0.799, daily saturation 0.82 and the five-a-week fixed point 0.78. The risk
is concentrated in the seams between the sub-window plan and the
whole-window answer, and in state that is recomputed at plan time from a
decayed quantity. Three flaws would pass every promised test and reach a
user: the sunscreen prescription and the overshoot test are judged on the
region that limited the *sub-window* plan rather than on the region the
*whole window* pushes hardest (and the lying-down whole-window split is never
defined), so a "stay the whole window" user can be handed an SPF that leaves
their torso past target; the exposure solver's fallback makes a viable but
under-delivering window collapse to a zero-minute plan at the window's end,
which is the shoulder-hour slot the app exists for; and the replay's
`doseToday` bookkeeping carries yesterday's back and head-and-shoulders dose
into today for every day after the first. Behind those, the plateau
maintenance re-checks a decayed tan state at plan time and so flickers on and
off across the week at the very cadence the S4 script defines as "regular";
the gap notice's threshold is the absolute one and never fires for the
three-to-four-week gaps in use cases 5 and S4; and the one-week rise bound
(T2's 40%) is arithmetically 47% under the τ the same ruling set. The slice
seams are loud rather than silent — a Package.swift that references nine
directories that do not exist, a Linux job that must compile SwiftUI, an
`AppEnvironment` in the app target that every package model takes as an
argument — but each will be "fixed" by a coder under time pressure in a way
the plan did not choose, which is the drift the plan format exists to
prevent.

## Findings, by silence rank

---

### 1. Sunscreen and overshoot are judged on the sub-window's limiting region; the lying whole-window split is undefined

POSTURE: 3 (contract vs internals) with a 1 (wrong shape) underneath
SILENCE RANK: 1
WHERE: `core-engine.md`, Slice 5 Internals:
```
rawPerRegion = dose over the whole w per posture (stay-whole-window doses)
plan = ExposureModel.solve(exposureReq) ?? return .budgetSpent(…)
limiting = plan.limitingRegion; t = targets[limiting]
…
overshoot = rawPerRegion[limiting] > t.remaining
sunscreen = overshoot ? SunscreenSolver.outcome(rawSED: raw, budgetSED: t.remaining, w, bareMinutes: plan.totalMinutes, uvaHeavy) : .notNeeded(uvaHeavy)
```
and the promise "overshoot is judged against `remaining`; sunscreen budget is `remaining`" (Slice 5 Signatures); `ExposureModel.dose(_ exposure: Exposure, …, over w: Window, …)` takes one exposure (Slice 2).
THE FLAW: `plan.limitingRegion` is the argmax of dose/remaining *inside the
best sub-window plan*. Over the whole window the ratios differ: lying down,
the sub-window plan is typically limited by head-and-shoulders (the credit of
faceUp + 0.5 × faceDown on the shortened sides), while over a three-hour stay
the torso sides each get half the window and their raw/remaining ratio can
exceed head-and-shoulders'. Sunscreen divides every region by the same
`effectiveSPF`, so the attenuation the solver must cover is
`max over exposed r of raw[r] / remaining[r]`, not the ratio of one region.
Worse, `rawPerRegion … per posture` cannot be computed for `lyingTurning` at
all from the declared `dose(_ exposure:)`: nothing says how the whole window
is split between faceUp and faceDown. A coder will pick (faceUp for the whole
window — then `back` is 0 and the back never limits — or half/half); the
fixture author for use case 3 will pick independently.
CONSEQUENCE: A type II who marks "staying the whole window" lying down gets
"SPF 20, applied normally" solved against head-and-shoulders while the front
and back need SPF 30. At standard scale that is a torso at up to
0.9 × (5.48/4.47) ≈ 1.1 MED — a planned burn (V15). No promise names a
multi-region attenuation; the S18 use case 3 fixture asserts the ladder
answer for "its curve", so whichever split and region the coder chose is the
one the fixture is tuned to. `warnings()` is per region and correct, which
hides the asymmetry: the warning fires while the sunscreen does not cover it.
THE FIX (Planner Internals; the `dose(_:)` signature is unchanged):
```
wholeWindowRaw(w, posture, cover): [Region: SED]
  upAndAbout   → ExposureModel.dose(.upAndAbout, cover, over: w)
  lyingTurning → mid = w.start + w.minutes/2; sides in `order` (firstSide first):
                 dose(.lying(order[0]), cover, over: Window(w.start, mid)) + dose(.lying(order[1]), cover, over: Window(mid, w.end))
                 // the "stay" model: the user turns over at half time; the SAME split is what didThis logs for .sunscreenForWholeWindow
exposed = regions with rawPerRegion[r] > 0
attenuationRegion = argmax over exposed of rawPerRegion[r] / targets[r].remaining   // remaining 0 → ∞
overshoot = rawPerRegion[attenuationRegion] > targets[attenuationRegion].remaining
sunscreen = overshoot ? SunscreenSolver.outcome(rawSED: rawPerRegion[attenuationRegion], budgetSED: targets[attenuationRegion].remaining, w, bareMinutes: plan.totalMinutes, uvaHeavy) : .notNeeded(uvaHeavy)
alternative(have:) in CalculatorModel passes the SAME region's raw and remaining
```
Add to Slice 5 Signatures promises:
```
//  the prescribed pair covers every exposed region: attenuation == max over exposed r of raw[r]/remaining[r]; a lying stay-whole-window
//  request splits the window into two equal consecutive halves in side order for raw, sunscreen, warnings and the logged dose
//  fixture: lying, standard, equal remaining, flat UVI, 3 h: front/back ratio > headAndShoulders ratio and the label is the torso's
```
Contract-only addition; not structural.

---

### 2. The exposure solver returns a zero-minute plan when the window cannot deliver the target

POSTURE: 2 (silent failure)
SILENCE RANK: 2
WHERE: `core-engine.md`, Slice 2 Internals:
```
upAndAbout:
    for s in minute grid of w: d(s) = bisection over [0, w.end − s] on maxOverExposed(ratio) ≤ 1
    pick s minimising d(s) (ties → |mid − solarNoon|)
lyingTurning (tactical #3):
    d1 = durationFrom(s, remaining[region(order[0])]) ?? (w.end − s); d2 = durationFrom(s + d1, remaining[region(order[1])]) ?? (w.end − s − d1)
    pick s minimising d1 + d2 subject to s + d1 + d2 ≤ w.end
```
THE FLAW: When no start can reach the budget, the fallback duration is "the
rest of the window", which is minimised at `s = w.end` with `d = 0`. Both
branches collapse to a zero-minute session at the window's end. The Planner
only discards the plan when `raw < viableBar` (50% of the target); every
window that delivers between 50% and 100% of the limiting region's remaining
passes viability and ships the zero-minute plan as `.plan`. `bestSubWindow`
in Slice 1 returns nil in this case, but the Planner never calls it.
CONSEQUENCE: "Best 0 minutes, 18:59–19:00" for the shoulder-of-the-curve
slot that §2 of the design names as the problem being solved. No promise
covers a viable-but-short window: "a second session with 0.3 SED remaining
and a 0.5 SED window is a .plan" has the target deliverable, "eveningFalling
starts at now" has it deliverable, and use cases 1–3 all overshoot. S18 and
S6 pass. The owner sees it the first evening the sun is low.
THE FIX (Slice 2 Internals):
```
upAndAbout:
    full = dose(.upAndAbout, cover, over: w)
    if maxOverExposed(ratio(full)) ≤ 1 → sides = [SideAllocation(.upAndAbout, w, full)]      // the window cannot reach the budget: stay all of it
    else for s in grid: d(s) = smallest d with maxOverExposed(ratio(dose over Window(s, s+d))) ≥ 1, nil when none before w.end
         pick s minimising d(s) over non-nil (ties → |mid − solarNoon|)
lyingTurning:
    for s in grid: d1 = durationFrom(s, remaining[r1], notAfter: w.end); d2 = d1.map { durationFrom(s + $0, remaining[r2], notAfter: w.end) }
    candidates = s with both non-nil; pick min d1 + d2
    if no candidate: t = bisection on the flip time in w so that dose(lying(order[0]), cover, over: Window(w.start, t))/remaining[r1]
                     == dose(lying(order[1]), cover, over: Window(t, w.end))/remaining[r2]; sides = [(w.start,t), (t,w.end)]   // equal fraction of budget per side
    then the F2 shrink on (d1, d2) if the H&S credit exceeds remaining[hs]
```
Add to Slice 2 Signatures promises:
```
//  a clipped window whose full dose is below every exposed region's remaining returns a plan with span == the clipped window (never 0 minutes);
//  lying, same case: both sides non-empty, sum == the window, ratio dose/remaining equal per side within 1e-6
```
Not structural.

---

### 3. `Replay` carries yesterday's back and head-and-shoulders dose into today

POSTURE: 2 (silent failure)
SILENCE RANK: 3
WHERE: `core-engine.md`, Slice 3 Internals:
```
      for region: rs = decayed(rs, to: s.actualWindow!.end)
        …
        rs.doseToday = (s.day == state.today) ? rs.doseToday + dose : dose ; state.today = s.day
```
THE FLAW: `state.today = s.day` is executed inside the per-region loop. For
the first region of a new day `s.day != state.today` and its `doseToday`
resets; `state.today` is then updated, so the second and third regions see
`s.day == state.today` and *add* to the `doseToday` they carried from the
previous session day. The final step (`if state.today != DayKey(now, …) →
doseToday = 0`) masks it whenever the plan is computed on a day with no
session yet, so the single-day fixtures and every "next morning" fixture pass.
CONSEQUENCE: On any day after the first day of use, the second session of the
day is solved with `remaining[back]` and `remaining[headAndShoulders]` reduced
by every previous day's dose. Within a week `back` reads spent every
afternoon; lying returns `.budgetSpent(back)` or a nil solve while the front
is fine. Use case 4 ("the front has 15% left") only fails if its fixture
history contains an earlier day, which a fixture author has no reason to
add. Replay purity, S3 and S4 (multipliers and tan state) are untouched.
THE FIX:
```
    .session(s) where s.state == .logged:
      sameDay = (s.day == state.today)
      for region: …
        rs.doseToday = sameDay ? rs.doseToday + dose : dose
      state.today = s.day                       // AFTER the region loop
```
Add to Slice 3 promises:
```
//  two logged lying sessions on consecutive days: after replay, every region's doseToday equals day 2's dose alone (day 1 is not carried)
```
Not structural.

---

### 4. Maintenance is not sticky: the plateau is re-tested against a decayed tan state at plan time, and the sunscreen is solved before maintenance is applied

POSTURE: 1 (wrong shape) and 3 (the "stays there" promise is not delivered)
SILENCE RANK: 4
WHERE: `core-engine.md`, Slice 3 Signatures:
```
public static func plateauOutcome(_ s: RegionState, tunables:) -> PlateauOutcome?   // noColourNearCeiling ≥ ceilingNoColourCount && tanState ≥ plateauTanState → …
```
Slice 3 Internals: "Daily saturation ≈ 0.82, 5/wk fixed point ≈ 0.78 …
plateauTanState 0.75 sits below both, so R14's outcomes are reachable at
5/wk." Slice 5 Internals:
```
  sunscreen = overshoot ? SunscreenSolver.outcome(…) : .notNeeded(uvaHeavy)
  headline = …
  notices: … plateau = plateauOutcome(regions[limiting]); if plateau != nil → targets × maintenanceFraction, re-solve; maintenanceApplied
```
THE FLAW: The 0.78 fixed point is the value *right after Friday's session*.
`Replay` decays every region to `now` before the Planner runs, so at plan
time in a five-a-week rhythm the tan state is 0.710 on Monday (three days'
decay), 0.723 Tuesday, 0.734 Wednesday, 0.744 Thursday and 0.752 Friday.
`plateauOutcome` is therefore nil four days out of five: the maintenance dose
appears on Fridays. R14 says the recommendation "drops to a maintenance dose
… and stays there until a later yes or a little". The count
`noColourNearCeiling` already encodes "near saturation at the time of the
answer" (it only increments when `tanState ≥ plateauTanState` at the
lasting-colour event); re-testing the line at plan time is what makes it
flicker. Separately, the Planner computes overshoot, sunscreen and headline
against the unmaintained targets and only then rescales and "re-solves" —
which of those is redone is unstated, and `RegionTarget` has `let` fields,
so "targets × maintenanceFraction" has no expression.
CONSEQUENCE: The S4 promise ("8 weeks × 5/wk reaches tanState ≥
plateauTanState; then 3 × lastingColour .no → .ceiling") is asserted at the
Friday peak and passes. In use the number oscillates between the full target
and 0.7 of it across the week with the copy appearing and vanishing, and on
the days it applies the sunscreen prescription covers a target 43% larger
than the one shown. The T1 premise "reachable at 5/wk" is true only at the
instant of the last session.
THE FIX. Slice 3 Signatures:
```
    public static func plateauOutcome(_ s: RegionState, tunables:) -> PlateauOutcome?
        // noColourNearCeiling ≥ ceilingNoColourCount → rednessBoundInCycle ? .ceiling : .underDosed; nil otherwise
        // (the count only ever increments while tanState ≥ plateauTanState at the answer; it resets on yes / aLittle and when the cycle ends)
```
Slice 2 Signatures, `RegionTarget` gains:
```
    public func scaled(by f: Double) -> RegionTarget   // target × f, remaining = max(0, target × f − doseToday); range, boundBy, scaleUsed unchanged
```
Slice 5 Internals, reordered so everything is solved once:
```
  plateau = { r: AdaptationModel.plateauOutcome(state.regions[r]) }
  targets = for region: t = goal.target(…, stale: isStale); plateau[region] != nil ? t.scaled(by: maintenanceFraction) : t
  maintenanceApplied = plateau.values.contains { $0 != nil }
  … budgetSpent / clip / solve / raw / overshoot / sunscreen / headline on these targets, once …
  notices.plateau = plateau[limiting] ?? plateau.values.first { $0 != nil }
```
Add promise: "plateau non-nil → the sunscreen prescription is solved
against the maintained remaining; plateauOutcome is unchanged by a weekend's
decay (tanState 0.71 after three days from 0.78 still returns the outcome)".
FLAGGED STRUCTURAL: adds `scaled(by:)` to a Signatures block and changes a
Signatures comment line.

---

### 5. `.nothingRealistic` with "staying the whole window" logs the whole window bare

POSTURE: 2 (silent failure)
SILENCE RANK: 5
WHERE: `core-engine.md`, Slice 5 Internals:
```
  headline = overshoot && intent == .stayWholeWindow ? .sunscreenForWholeWindow : .bareSubWindow
```
`calculator-ui.md`, Slice 3:
```
@Published public var confirmedSunscreen: SunscreenConfirmation      // defaults to .asPrescribed iff headline == .sunscreenForWholeWindow, else .none
public func didThis() async throws              // logs: actual = span or entered window per headline; doses = attenuated(dose over that window, confirmedSunscreen, cover)
didThis(): (actual, doses) per Signatures; choice = confirmedSunscreen → prescribed pair / alternative / nil
```
THE FLAW: When `SunscreenSolver.outcome` returns `.nothingRealistic` (any
attenuation above 7.07: three hours at UVI 8 for an uncalibrated type I at the
conservative scale needs about 14×), the headline is still
`.sunscreenForWholeWindow`, `confirmedSunscreen` defaults to `.asPrescribed`,
and there is no prescribed pair. `didThis` resolves the choice to `nil` and
logs `attenuated(raw over entered window, nil)` — the full raw dose over the
whole window, unattenuated, with `actual = entered window`.
CONSEQUENCE: A fair-skinned user who read "nothing realistic covers three
hours — shorten the window", stayed twenty minutes and tapped "I did this",
is recorded as having taken 14 targets of dose. The next day's "normal"
report credits tan state to 1.0 and moves the multiplier up by the whole
unabsorbed excess (capped only by the clamp at 1.8). Every promised test
about `.nothingRealistic` stops at the outcome; the logging promise names
only `.bareSubWindow` and a prescribed pair.
THE FIX (Slice 5 Internals and Signatures):
```
  headline = (overshoot && intent == .stayWholeWindow && case .prescribe = sunscreen) ? .sunscreenForWholeWindow : .bareSubWindow
//  promise: .nothingRealistic never pairs with headline .sunscreenForWholeWindow; the headline is the bare sub-window and .nothingRealistic is the second answer
```
`calculator-ui.md` Slice 3 Internals:
```
  confirmedSunscreen = (headline == .sunscreenForWholeWindow) ? .asPrescribed : .none     // .asPrescribed only exists when sunscreen is .prescribe
  didThis(): guard case .asPrescribed, case .prescribe(let advice) = sunscreen else use span/.none — never log an unattenuated entered window
```
FLAGGED STRUCTURAL: changes a Signatures promise line (headline rule); no
type changes.

---

### 6. `SessionRecord` cannot say when the user turned over, so lying sessions are not reproducible from the record

POSTURE: 1 (wrong shape)
SILENCE RANK: 6
WHERE: `core-engine.md`, Slice 3 Signatures:
```
public struct SessionRecord … { … public var plannedWindow: Window; public var actualWindow: Window?; public var firstSide: Side
    … public var dosePerRegion: [Region: SED]           // after sunscreen and cover; stored, never recomputed
```
`data-layer.md`, Slice 3: `reproduce(_ s: SessionRecord, …) throws -> [Region: SED]   // re-plans from s.curveUsed with s's posture, cover, sides, actual window…`; `logging-calibration.md` Slice 1: `didDo(_ id, actual: Window, wore:)  // doses = attenuated(dose over actual sub-intervals …)`; `calculator-ui.md` Slice 4: `stop(now): … doses = attenuated(Σ sides dose(exposure, cover, over min(side window, now)), …)`.
THE FLAW: The record holds one `actualWindow` and a `firstSide`. The flip
time — the boundary between the faceUp and faceDown sub-intervals — exists
only inside the running `FlipTimerModel`. `reproduce` must "re-plan" to
recover it, which needs the remaining budgets of that moment (a replay up to
that session, which `stateBefore` supplies only approximately), and a timer
stopped before the flip has no second side at all. `didDo`'s "editable
times" edits one window; its "actual sub-intervals" are undefined.
CONSEQUENCE: R22 ("reproducible from the record alone") and V12 ("every
figure on the result screen is reproducible from the JSON export") are false
for every lying-down session. The S10 promise names "a session logged with
SPF 30 normal" without a posture; a tester writing it up-and-about passes. It
surfaces only when someone audits an export.
THE FIX (Slice 3 Signatures; export format v1 is not yet frozen):
```
public struct ExposureInterval: Codable, Sendable, Equatable { public let exposure: Exposure; public let window: Window }
public struct SessionRecord … {
    public var actualIntervals: [ExposureInterval]?   // the sub-intervals actually faced, in order; replaces actualWindow as the source of truth
    public var actualWindow: Window? { actualIntervals.map { Window($0.first!.window.start, $0.last!.window.end) } }
```
`HistoryStore.log(_ id, actual: [ExposureInterval], …)`; `reproduce` = `attenuated(Σ dose(i.exposure, cover, over: i.window), s.sunscreen, cover)`; `didDo(_ id, actual: [ExposureInterval], wore:)` with the editor defaulting to the planned sides; the timer's `stop` writes the intervals it actually ran. Promise: "reproduce(lying session stopped before the flip) == its stored doses within 1e-6".
FLAGGED STRUCTURAL: changes a Signatures block, the `log`/`didDo` signatures, and the export schema.

---

### 7. The Tunables "spy" cannot exist against a `let` struct, and one `Basis` per key cannot carry a per-band basis

POSTURE: 4 (untestable promise) and 1 (wrong shape)
SILENCE RANK: 7
WHERE: `core-engine.md`, Slice 1 Signatures:
```
public struct Tunables: Sendable, Codable {
    public static let current: Tunables; public let version: String
    …
    public let adaptationGain: [SkinBand: Double]     // fair 1.25, medium 1.25 (cap 2.25×), dark 2.0 (cap 3×)   citation Module 5/6 (SPF 2–3) for fair; assumption for dark
    public let riseMultiplier: [SkinBand: Double]     // fair 1.0, medium 1.0, dark 1.5
    public static let provenance: [String: Basis]     // key = property name; every stored property present (S1)
```
Slice 5: "DoseResult.reads equals the set the tests observe (a Tunables spy records every key read)"; Internals: "Tunables access goes through a `TunablesReader` that records keys in tests".
THE FLAW: Every engine signature takes `tunables: Tunables`, a struct of
stored `let`s. Reading a stored property is not observable; the blind
test-writer, who sees only the Signatures, has no `TunablesReader` to spy
with, so the S1 clause "the declared constant set of every outcome equals the
constants its tests observe being read" has no test that can hold it. It
degrades to a hand-maintained `reads` set per figure builder — exactly the
list decision 24 wanted checked. Separately, `provenance` is one `Basis` per
property name, but `adaptationGain` is a citation for fair skin and an
assumption for dark, and `riseMultiplier`'s 1.5 is the assumption; there is
no way to record that, so either every headline for every type carries the
estimate badge or a type V's headline lacks the badge V12 requires.
CONSEQUENCE: The estimate label — the only on-screen expression of V12 — is
driven by a list nobody can test against what the code reads. A builder that
forgets `posture` (up-and-about fractions) ships a figure without its badge
and passes S1, S6 and S18. Not visible to anyone until a reviewer diffs the
list against the code by hand.
THE FIX (Slice 1 Signatures; the property names and types are unchanged):
```
public struct Tunables: Sendable, Codable {
    // every constant is a computed property over private storage; each read reports its key to `onRead`
    public var uviMinutesPerSED: Double { read("uviMinutesPerSED") }
    public func adaptationGain(_ band: SkinBand) -> Double { read("adaptationGain.\(band)") }     // band-keyed tables become functions so the read carries the band
    … (riseMultiplier, melanogenicFraction, medBaselineSED(_ type:), ceilingScale(_:), impliedRatio(_:) likewise)
    public static let current: Tunables
    public func recording(_ sink: @escaping @Sendable (String) -> Void) -> Tunables   // same values, every read reported; the S1 spy
    public static let provenance: [String: Basis]   // keys: plain names and "<table>.<band>" / "<table>.<case>" — one basis per stored number
    public static var assumptionKeys: Set<String>
}
// promise: Planner.plan(req, tunables: Tunables.current.recording(sink)) → the recorded set == the union of result.figures.map(\.reads); adaptationGain.dark ∈ assumptionKeys, adaptationGain.fair ∉
```
FLAGGED STRUCTURAL: reshapes the `Tunables` Signatures block (accessors
become functions for band-keyed tables) and the provenance key space.

---

### 8. The notification id loses the day's time zone, so a report can match no session

POSTURE: 5 (slice seam) with a 2 (silent failure) outcome
SILENCE RANK: 8
WHERE: `data-layer.md`, Slice 4 Internals: `ids: "skin-<day>", "colour-<day>", …`;
`logging-calibration.md`, Slice 1: `// App/NotificationRouting: "skin-<day>" → SkinCheckFlow(day, .notification)`;
`core-engine.md`, Slice 1: `public struct DayKey: Codable, Sendable, Hashable, Comparable { public let year: Int; public let month: Int; public let day: Int; public let timeZoneID: String … }` and the promise `DayKey(23:30Z, UTC) != DayKey(23:30Z, America/Los_Angeles)`; Slice 3 Internals: `.report(r): sessions = logged sessions with day == r.day`.
THE FLAW: `DayKey` equality includes `timeZoneID` (the promise requires it:
23:30Z is 3 September in both zones, so only the zone distinguishes them).
Sessions are keyed by `curve.day(window.start)` — the *forecast location's*
zone. The notification id is an unspecified string form of the day; nothing
declares a round-trip. A coder writes `"skin-2026-09-03"` and the router
rebuilds `DayKey` with `.current`. Whenever the provider's placemark zone
identifier differs from the device's, `sessions with day == r.day` is empty,
`evidenceRegion` returns nil, and `apply` returns `.noDoseThatDay`.
CONSEQUENCE: The user logs a session, answers the skin check the next day,
and is told "no session to report". Every report on that trip records and
never calibrates. The fake port carries the full `DayKey` inside
`NotificationKind.skinCheck(DayKey)`, so every promised test passes; the
string path only exists on a device.
THE FIX (Slice 1 Signatures):
```
public struct DayKey … {
    public var id: String                      // "2026-09-03@Europe/Oslo" — the only string form; used in notification ids and export
    public init?(id: String)                   // promise: DayKey(id: d.id) == d for every d; nil for a malformed string
}
```
`data-layer.md` Slice 4: `ids: "skin-\(day.id)", "colour-\(day.id)"`; `logging-calibration.md`: `NotificationRouting: DayKey(id:) from the id suffix; unparseable → open DuePromptsCard instead`.
FLAGGED STRUCTURAL: adds two members to a Signatures block.

---

### 9. The range is centred on MED: its upper edge is always clipped and never narrows, the number can sit outside it, and stale never widens it

POSTURE: 3 (contract vs internals) and 1 (wrong shape)
SILENCE RANK: 9
WHERE: `core-engine.md`, Slice 2 Internals:
```
  h0 = uncertaintyBandAtZero; lowerH = h0 / (1 + totalReports/k); upperH = h0 / (1 + rednessReportCount/k)
  range = med×(1−lowerH) ... min(med×(1+upperH), med); rangeClipped = med×(1+upperH) > med; remaining = max(0, target − rs.doseToday)
```
Promises: "range.upperBound ≤ medPersonal; rangeClipped when the raw band exceeds it; upper narrows only as rednessReportCount grows" (Slice 2) and "stale: … targets reduced by staleReduction and range widened ×1.5" (Slice 5).
THE FLAW: `upperH > 0` for every finite report count, so `med × (1 + upperH)
> med` always: the upper edge is `med` forever, `rangeClipped` is true on
every result forever, and "narrows only with redness reports" is
unobservable — the displayed upper never moves. The lower edge is `0.7 med`
at zero reports while the number is `0.75 med` (conservative) or, for a type
IV at standard, `0.675 med`: the number is outside its own range. And
`staleRangeWiden` is read nowhere: the target takes `stale`, the range does
not.
CONSEQUENCE: A tester asserting "redness reports narrow the upper edge" fails
loudly and the coder discovers the formula makes R7's narrowing impossible;
a tester asserting "does not narrow without redness" passes vacuously and
the permanent "redness likely beyond" clip label ships on every result. The
stale widening (R3, use case 9) is promised in Slice 5 and delivered by
nothing.
THE FIX (Slice 2 Internals; R7's "uncertainty in the threshold" is applied
to the number that the threshold scales):
```
  widen = stale ? staleRangeWiden : 1
  lowerH = widen × h0 / (1 + totalReports/k); upperH = widen × h0 / (1 + rednessReportCount/k)
  rawUpper = target × (1 + upperH)
  range = target × (1 − lowerH) ... min(rawUpper, med); rangeClipped = rawUpper > med
```
Promise additions: "range contains target; at standard scale the upper edge
is clipped at zero reports and unclipped once rednessReportCount ≥ 5 (0.9 ×
1.1 < 1); stale: true widens both edges ×1.5 with the upper still ≤
medPersonal". Not structural.

---

### 10. The gap notice's threshold is absolute and never fires for the gaps the design and fixtures describe

POSTURE: 3 (a promise the internals cannot deliver); arithmetic
SILENCE RANK: 10
WHERE: `core-engine.md`, Slice 3 Signatures:
```
    public static func escalationNotice(_ s: RegionState, skinType:, tunables:) -> EscalationNotice?
        // .risen when factor − 1 ≥ escalationNoticeFraction × gain(band) ; .dropped when a gap > gapDays cut the factor by ≥ that same amount from factorAtLastSession
```
and the promise "4-week gap → dose ≥ 25% smaller and .dropped".
THE FLAW: "That same amount" is 0.5 × gain = 0.625 for fair skin. From the
five-a-week fixed point (tanState 0.784) a 28-day gap decays to 0.311; the
factor falls by 1.25 × 0.473 = 0.59 < 0.625. No `.dropped`. Use case 5 (four
weeks in June, three weeks off): 0.765 → 0.383, a factor drop of 0.478.
No `.dropped`. The notice only fires from this state after ≥ 31 days. Read
relatively — a drop of `escalationNoticeFraction` of the factor's *own* rise —
the 28-day case fires (0.59 ≥ 0.488); but the 21-day case sits exactly on
the line, because a 21-day gap at a 21-day half-life halves the tan state
exactly, so floating point decides use case 5.
CONSEQUENCE: The S4 blind test fails loudly. The danger is the fix: the
coder moves `escalationNoticeFraction` or `decayHalfLifeDays` to make the
test green (both are `assumption`), and V2's "shrinks it after a break" copy
becomes a function of a constant tuned to a test. The dose reduction itself
(30%) is correct and unaffected.
THE FIX (Slice 3 Signatures comment):
```
        // .dropped(fraction:) when now − lastExposure > gapDays and (factorAtLastSession − factor(now)) ≥ escalationNoticeFraction × (factorAtLastSession − 1) − 1e-9,
        //   fraction = 1 − tanState(now)/tanStateAtLastSession   (relative to the factor's own rise, not to the cap rise)
```
Promises: "6 weeks × 5/wk then a 28-day gap → .dropped(fraction ≈ 0.60);
a 21-day gap → .dropped (the half-life boundary is inclusive); a 13-day gap →
nil". S18 use case 5's fixture should use a 22-day gap or rely on the
inclusive comparison, stated in the fixture.
FLAGGED STRUCTURAL: changes a Signatures comment that defines behaviour;
touches R13's wording, which the owner should confirm reads "of its rise".

---

### 11. The flip timer bypasses the Planner, and `stop` logs a session that is no longer `.planned`

POSTURE: 5 (slice seam) and 3
SILENCE RANK: 11
WHERE: `calculator-ui.md`, Slice 4 Internals:
```
FlipTimerModel.start: req = calculator's request with window Window(now, entered.end), firstSide; plan = ExposureModel.solve; doses = attenuated(plan.perRegionDose, choice, cover)
  history.log(id, actual: plan.span, …)
stop(now): actual = Window(span.start, now); … history.log(update); prompts.cancelTimer()
```
`data-layer.md`, Slice 3 Internals: `log(id, …): entity = fetch; guard .planned; set actual, …, state .logged`.
THE FLAW: `ExposureModel.solve` takes targets; the timer must rebuild them,
and the plan does not say with which stale level or maintenance scale. The
result the user just read may have been reduced 5% for staleness or 30% for
maintenance; the timer re-solves at full target. And `log` refuses a session
that is already `.logged`, so the second `log` in `stop` throws
`.notPlanned` — a loud failure at assembly that the UI coder will route
around with whatever the store offers.
CONSEQUENCE: The timer runs longer than the result said on stale or
maintenance days; the "re-credits on the actual sub-intervals" promise is
implemented against an API that forbids it, so the re-credit is the part that
gets dropped.
THE FIX. `data-layer.md` Slice 3 Signatures:
```
    public func log(_ id: UUID, actual: [ExposureInterval], sunscreen:, doses:, factors:, targets:) throws   // .planned → .logged; .logged → updated in place (the timer's stop); .discarded → throws .notPlanned
```
`calculator-ui.md` Slice 4 Internals:
```
FlipTimerModel.start: result = Planner.plan(calculator.request(window: Window(now, entered.end), firstSide)); guard case .plan(let plan, let sunscreen, _) else throw TimerError.cannotStart(result.outcome)
  intervals = plan.sides.map { ExposureInterval($0.exposure, $0.window) }; doses = attenuated(plan.perRegionDose, choice, cover); history.log(id, actual: intervals, …)
```
FLAGGED STRUCTURAL: changes the `log` signature (also required by finding 6).

---

### 12. Denied location with no cache leaves no route to a manual place

POSTURE: 2 (silent failure) and 5
SILENCE RANK: 12
WHERE: `calculator-ui.md`, Slice 3 Internals:
```
compute(): loc = await env.location.location(now); coord = loc.coordinate
  fr = await env.forecast.cached(); if fr.curve == nil → fr = await env.forecast.current(for: coord, now)
```
`data-layer.md`: `public func current(for location: Coordinate, now: Date, force: Bool = false)`; `core-engine.md` Slice 5: `case missingForecast(ForecastFailureKind?)`, `public enum ForecastFailureKind … { case provider, malformed, cacheUnreadable }`.
THE FLAW: `coord` is optional; `current(for:)` is not. With permission denied
and nothing cached (first launch after denial), the pseudocode has no branch:
either it cannot compile as written or the coder returns early with no
result. The Result screen is where "change place" lives ("forecast line (age,
place, 'change place', 'refresh')"), and the plan does not say that line is
rendered for `.missingForecast`. V7: manual entry is "reached from the
result's place line" and "never a control on the entry screen".
CONSEQUENCE: A user who denies location on first run computes and sees
nothing they can act on, with no way to enter a place. The promise "'change
place' reachable from the forecast line" is tested on a result that has a
forecast.
THE FIX. Slice 5 Signatures: `public enum ForecastFailureKind … { case provider, malformed, cacheUnreadable, noLocation }`. `calculator-ui.md` Slice 3:
```
compute(): … guard let coord else { result = Planner.plan(PlanRequest(curve: fr.curve, forecastFailure: fr.curve == nil ? .noLocation : nil, deviceLocation: nil, …)); return }
ResultView: the forecast line (place, "change place", "refresh") renders for EVERY outcome including .missingForecast
// promise: with FakeLocationSource(.denied) and an empty cache, compute() yields .missingForecast(.noLocation) and the view exposes "change place"
```
FLAGGED STRUCTURAL: one enum case added to a Signatures block.

---

### 13. The DOI regex swallows the `[VERIFY]` marker, and McKinlay's kind contradicts the parser

POSTURE: 3 (contract vs internals) and 2
SILENCE RANK: 13
WHERE: `learn-tab.md`, Slice 1 Internals:
```
LearnModule loader: … citations parsed from the file text BEFORE stripping so needsVerification = line contained [VERIFY]
Citation parser: … identifier by regex: https://doi.org/(.+) | PMID (\d+) | ISO \d+ | https?://…
```
Promise: "Routaboul → .pmid("10066941"); McKinlay → .none; WHO → .url". Source line 68: `> - McKinlay AF, Diffey BL. *A reference action spectrum …* CIE Journal, 1987. (Standardised as ISO 17166:1999 / CIE S 007) `[VERIFY]``.
THE FLAW: Parsing before stripping with `(.+)` captures
`10.1111/j.1600-0749.2006.00358.x `[VERIFY]`` as the DOI for every marked
citation — the ones the owner must check. The promised test checks
*kinds*, and a value only for the PMID. And the source's McKinlay line
carries "ISO 17166:1999", so `ISO \d+` classifies it `.iso` while the promise
says `.none`; R26 says a citation "renders the identifier it carries (… ISO
number …)".
CONSEQUENCE: Tapping a `[VERIFY]` citation opens a broken doi.org URL; S7
passes. McKinlay: a loud test/impl disagreement resolved by whichever side
is edited.
THE FIX:
```
identifier regex, applied to the text after the year's ". ": https://doi\.org/(\S+) | PMID (\d+) | ISO (\d+(?::\d+)?) | (https?://\S+)   — the DOI/URL capture stops at whitespace
// promise: Miyamura → .doi("10.1111/j.1600-0749.2006.00358.x") with needsVerification true; McKinlay → .iso("17166:1999"); ISO 17166 (module 4 sources) → .iso("17166:1999")
```
FLAGGED STRUCTURAL: changes a promise line (McKinlay's kind).

---

### 14. A report made under a manual override moves the learned multiplier from the override, not from itself

POSTURE: 2 (silent failure)
SILENCE RANK: 14
WHERE: `core-engine.md`, Slice 3 Internals:
```
  ceilingThen / overrideThen = last session of the day; m = overrideThen ?? state.multiplier
  …
    implied = m × ratio / impliedRatio[answer]; m += discount × weight(n, burn: true) × (implied − m)
```
THE FLAW: `implied` is an absolute estimate (`m` cancels: `m × dose/(base ×
m × af) / r = dose/(base × af × r)`), but the update `m += w × (implied − m)`
starts from the override value and is written back to `state.multiplier`.
Learned 1.0, override 0.8, one faint-pink report at ratio 1.0 → learned
becomes 0.8 in one step. The reset in Settings then reveals a "learned"
number that was the override.
CONSEQUENCE: No promise covers reports under an override. Silent until a
user resets.
THE FIX:
```
  mUsed = overrideThen ?? state.multiplier            // what the day's plan used → ratio and implied
  …
  state.multiplier += discount × weight(…) × (implied − state.multiplier)    // the learned value moves from itself
  // promise: override 0.8, learned 1.0, faintPink at ratio 1.0 (implied = 0.8): learned moves from 1.0 toward 0.8 by weight — to 0.8 at n = 0, to 0.956 at n = 20 — never jumps to the override
```
Not structural.

---

### 15. A confounded "normal" report credits tan state at full weight

POSTURE: 3 (the discount promise is only half delivered)
SILENCE RANK: 15
WHERE: `core-engine.md`, Slice 3 Internals:
```
  discount = r.confounders.isEmpty ? 1 : confoundedDiscount
  …
    excess = ratio − 1; (rs, unabsorbed) = creditTolerant(rs, excess)
    if unabsorbed > 0: … m += discount × weight(n, burn: false) × (implied − m)
```
THE FLAW: Only the multiplier move is discounted; `creditTolerant` receives
the undiscounted excess. A "normal" after alcohol at ratio 1.4 raises tan
state by 0.2 as if the tolerance were real, and that credit is what
lengthens tomorrow's session.
CONSEQUENCE: R21 "confounded logs are heavily discounted" holds for the
persistent term and not for the one that changes tomorrow's number. The
promise tests `.discounted` on the effect enum.
THE FIX: `excess = discount × (ratio − 1)` before `creditTolerant`; promise
"normal at ratio 1.4 with .alcohol → tanState rise == 0.25 × 0.5 × 0.4".
Not structural.

---

### 16. "Reports in the current and previous cycle" needs a cycle history the fold discards

POSTURE: 1 (wrong shape)
SILENCE RANK: 16
WHERE: `core-engine.md`, Slice 3 Internals: `state.reportCount = reports in current + previous cycle (by cycleStart of the limiting region)`; Signatures: `decayed(…) // gap > gapDays → cycle ends (cycleStart nil, …)`; `DerivedState { … regions: [Region: RegionState]; today: DayKey? … }`.
THE FLAW: `decayed` erases `cycleStart` at a gap; the next session writes a
new one. Nothing retains the previous cycle's start, and "the limiting
region" is undefined inside a replay that has no plan. `reportCount` is
therefore computable only for the current cycle, or from an ad-hoc local the
coder invents.
CONSEQUENCE: For a user beyond 20 reports the window is what keeps the
weight above 0.11 across seasons (decision 6). With one cycle counted the
weight resets to 1.0 at every gap: the first post-gap report moves the
multiplier the whole way. No promise reaches this (nCap caps everything the
promises test).
THE FIX (Replay Internals):
```
  cycleStarts: [Date] = []      // local to the fold; appended when the earliest-starting region begins a cycle
  on a session where every region had cycleStart == nil: cycleStarts.append(s.actualWindow!.start)
  after each report: state.reportCount = count of reports with reportedAt ≥ (cycleStarts.suffix(2).first ?? .distantPast)
// promise: 12 reports, a 20-day gap, 12 more, another gap, 3 more → reportCount == 15 (previous + current), never 3
```
Not structural.

---

### 17. T2's 40% one-week bound is 47% under the τ that T1 set

POSTURE: 3 (a promise the internals contradict); arithmetic
SILENCE RANK: 17 (loud: the blind test fails)
WHERE: `core-engine.md`, Slice 3 promise: "1-week factor rise < 40% of the cap rise (T2)"; Internals: "riseTimeConstantDays = 7.2 is solved WITH one day of decay at half-life 21 between daily events so that 21 daily sessions at doseFraction 1.0 land at 0.80"; `docs/DECISIONS.md` D-2026-09-03-T2: "a single-exponential rise that reaches 0.8 in three weeks is at about 32% after five sessions".
THE FLAW: 32% is the no-decay exponential (τ = 21/ln 5 ≈ 13). Solving τ
with the decay the engine applies gives 7.2, and the rise is front-loaded:
after five daily sessions tanState = 0.473 (47% of the cap rise), 0.43 if
measured after the weekend. The ruling's stated premise is false under the
constants its sibling ruling fixed. 21 daily → 0.799 and 5/wk → 0.784 both
hold, so τ is right; the bound is what is wrong.
CONSEQUENCE: The S4 test fails; the loud path leads to "fix" the constant
rather than the bound, which moves the three-week course R12 pins.
THE FIX: the promise becomes "1-week factor rise < 50% of the cap rise
(0.47 at τ = 7.2)", with the T2 entry superseded to say the decay-solved
rise reaches 0.47 after five sessions. FLAGGED STRUCTURAL: touches a `D-…`
ruling and S4's text; the ruling's own premise is the false statement.

---

### 18. `durationFrom` rejects a fit by up to a minute at `notAfter`

POSTURE: 2
SILENCE RANK: 18
WHERE: `core-engine.md`, Slice 1 Internals: `durationFrom(start, target, notAfter): k = first prefix index with prefix[k] − prefix(start) ≥ target; if none or start+k > notAfter → nil; d = (k − 1) + …`
THE FLAW: The test uses the whole minute `k`, the answer is the interpolated
`d < k`. A start whose `d` ends 0.4 min before `notAfter` is rejected. On a
rising curve the last admissible start is dropped and the plan ends up to a
minute before the window's end; "bestSubWindow ends at 12:00" holds only
within a minute's tolerance the promise does not state.
THE FIX: `d = …; if start + d > notAfter → nil` (compare the interpolated
duration). Promise: "on morningRising 09:00–12:00 the returned window ends at
12:00 within 1 second". Not structural.

---

### 19. A lying session with one side's budget spent returns nil instead of the other side

POSTURE: 1 (wrong shape)
SILENCE RANK: 19
WHERE: `core-engine.md`, Slice 2 promise: "front remaining 0 and H&S remaining > 0 in lying → nil (not a crash)"; Internals: `exposedRegions = regions with dose > 0 in this posture after cover; if any exposed remaining ≤ 0 → return nil`.
THE FLAW: In lying, the front is exposed only on the faceUp side. A spent
front means faceUp = 0 minutes, not "no session": the back and
head-and-shoulders still have budget and the honest answer is "back only, N
minutes". The Planner then reports `.budgetSpent(front)` for a user with a
fresh back.
THE FIX (Signatures promise change): "front remaining 0, back and H&S > 0,
lying → a plan whose faceUp side is 0 minutes and whose faceDown side is
solved; nil only when H&S (uncovered) or both torso sides have remaining ≤
0". Internals: `if remaining[region(order[i])] ≤ 0 → d_i = 0` before the
search. FLAGGED STRUCTURAL: replaces a promise line.

---

### 20. Export v1 freezes enums that have no raw values

POSTURE: 1 (wrong shape for an external format)
SILENCE RANK: 20
WHERE: `core-engine.md`, Slice 1: `public enum Region: CaseIterable, Codable, Sendable { case front, back, headAndShoulders }`, `Side`, `Posture`, `Intent`, `Ceiling`, `Application`; Slice 3: `SkinAnswer`, `RednessTiming`, `ReportRegion`, `Confounder`, `LastingColour`, `Channel`, `SessionState`; `StoredCurve … // an EXTERNAL format (export v1)`; `SessionRecord.dosePerRegion: [Region: SED]`.
THE FLAW: A payload-free enum without a raw type encodes as `{"front":{}}`,
and a `[Region: SED]` dictionary with such keys encodes as an unkeyed array
of alternating keys and values. Export v1 will carry
`[{"front":{}},1.2,{"back":{}},0.4,…]` and must decode it forever.
THE FIX: give every payload-free enum in the record types `: String` (e.g.
`public enum Region: String, CaseIterable, Codable, Sendable`), which makes
dictionaries keyed by them encode as JSON objects. FLAGGED STRUCTURAL: the
external schema, cheap now and expensive after the first export.

---

### 21. Two small shapes: `RegionTarget` lacks the factor the UI must log, and `extraMinutesIfCovered` cannot express up-and-about

POSTURE: 1
SILENCE RANK: 21
WHERE: `core-engine.md` Slice 2: `RegionTarget { region; medPersonal; melanogenic; target; boundBy; scaleUsed; remaining; range; rangeClipped }`; `ExposurePlan.extraMinutesIfCovered: [Side: Double]`; `data-layer.md` Slice 3: `log(…, factors: [Region: Double], targets: [Region: SED])`.
THE FLAW: `factorsShown` (R22) must be logged by the UI, which has no
factor in `DoseResult` and would call `TanningGoal.adaptationFactor` itself
— calculation in UI. Use case 1 (up-and-about) promises "the option to cover
head and shoulders to run longer"; a `[Side: Double]` has no key for it.
THE FIX: `RegionTarget` gains `public let adaptationFactor: Double`;
`extraMinutesIfCovered: [Exposure: Double]`. FLAGGED STRUCTURAL: Signatures.

---

### 22. `reporterBands` is typed as closed ranges but defined as half-open ones

POSTURE: 1
SILENCE RANK: 22
WHERE: `core-engine.md` Slice 1: `public let reporterBands: [SkinAnswer: ClosedRange<Double>] // normal 0..<0.95, faintPink 0.95..<1.15, clearlyPink 1.15..<2.0, redSore 2.0..<4.0, blistered 4.0...`
THE FLAW: `0..<0.95` is a `Range`, `4.0...` a `PartialRangeFrom`; neither
fits the type. A coder invents upper bounds (0.9499?) and the S3 reporter at
exactly 0.95 becomes coder-dependent.
THE FIX: `public let reporterBandEdges: [Double] // [0.95, 1.15, 2.0, 4.0]` and
`public func reporterAnswer(ratio: Double) -> SkinAnswer // first edge > ratio; ≥ 4.0 → .blistered`. FLAGGED STRUCTURAL: Signatures.

---

### 23. Cross-plan types: `AppEnvironment` in the app target, the ad protocol in M7, `ProfileStore` in Slice 2, `DeepLink`/`ModuleView` in M4 Slice 2

POSTURE: 5 (slice seams)
SILENCE RANK: 23 (loud at build; silent in what the coder does about it)
WHERE: `calculator-ui.md` Slice 1 Files: `App/AppEnvironment.swift`; Signatures `@MainActor public final class AppEnvironment … public let ads: any AdBannerProvider … profile: any ProfileStore`; Slice 3 `CalculatorModel { public init(env: AppEnvironment) }` in `Sources/IcarusUI/…`; `release-readiness.md` Slice 1 Files: `Sources/IcarusAds/AdBannerProvider.swift`, `Sources/IcarusAds/NoAdsProvider.swift`; `calculator-ui.md` Slice 2 Files: `Sources/IcarusData/ProfileStore.swift`; Slice 1 Internals `RootTabs: … icarus:// → DeepLink`; Slice 2 Internals `OnboardingFlow pages: ModuleView(module 1)`; `learn-tab.md` Slice 2 Files: `DeepLink.swift`, `ModuleView.swift`; Slice 1 Internals: `swift run split-learn-content … (a tiny executable target …)` with `Package.swift` absent from Slice 1's Files.
THE FLAW: A package cannot import the app target: every `init(env:
AppEnvironment)` in IcarusUI is uncompilable with `AppEnvironment` in
`App/`. `AdBannerProvider`/`NoAdsProvider` and `ProfileStore` are used two
plans and one slice, respectively, before they are declared. `RootTabs`
(M3 S1) routes through `DeepLink` (M4 S2, "can follow M3"); onboarding (M3 S2)
renders `ModuleView` (M4 S2) though the declared dependency is M4 S1. The
split executable needs a Package.swift edit outside its slice's file list.
CONSEQUENCE: The M3 S1 coder creates the four missing types to compile; M7
S1's file list then "adds" files that exist; `plan-metrics` reports scope
drift on both sides; and `test-the-tests` never reverts `App/` (its
implementation dir is `Sources/`), so wiring in `App/` is unchecked by it.
THE FIX: move `AppEnvironment.swift` to `Sources/IcarusUI/AppEnvironment.swift`
(IcarusUI already depends on Data, Content and Ads); move
`Sources/IcarusAds/AdBannerProvider.swift` and `NoAdsProvider.swift` into
`calculator-ui` Slice 1's Files (M7 keeps `AdMobBannerProvider.swift` and
`ConsentFlow.swift`); move `Sources/IcarusData/ProfileStore.swift` into
`calculator-ui` Slice 1; move `Sources/IcarusUI/Navigation/DeepLink.swift`
(pure) into `learn-tab` Slice 1 and add `Package.swift` to that slice's Files
for the executable target; state in `calculator-ui` Slice 2 "depends on
`learn-tab` Slice 2 (ModuleView)". FLAGGED STRUCTURAL: slice file lists and
one cross-plan dependency line.

---

### 24. The Linux `core-tests` job must compile SwiftUI, and Slice 1's manifest names nine directories that do not exist

POSTURE: 5
SILENCE RANK: 24 (loud)
WHERE: `core-engine.md` Slice 1 Signatures: "targets: IcarusCore …, IcarusContent …, IcarusAds …, IcarusData …, IcarusUI …; test targets: IcarusCoreTests, IcarusDataTests, IcarusContentTests, IcarusUITests, IcarusAdsTests"; Files list only `Sources/IcarusCore/…` and `Tests/IcarusCoreTests/…`; Internals: "ci.yml: job core-tests (ubuntu-latest …): `swift test --filter 'IcarusCoreTests|IcarusContentTests|IcarusDataTests'`".
THE FLAW: SwiftPM refuses a manifest whose target directories are absent, so
Slice 1 cannot build without placeholder files it does not list. `swift test
--filter` filters which tests *run*; it builds every test target and its
dependencies, and `IcarusUI` (SwiftUI, later MarkdownUI) and `IcarusAds`
(later a binary Google SDK) do not build on Linux. F6's Linux job fails at
the first PR that adds IcarusUI, and the coder's obvious fix — wrapping every
UI file in `#if canImport(SwiftUI)` — is the wrong one.
THE FIX (Slice 1 Signatures, Package.swift):
```
// Package.swift: let applePlatformsOnly = !os(Linux) evaluated in the manifest (#if os(Linux)); IcarusUI, IcarusAds and their test targets
//   (and the MarkdownUI / GoogleMobileAds dependencies) are declared only when it is true; IcarusCore, IcarusContent, IcarusData (SwiftData under #if canImport) always
// Slice 1 Files add: Sources/IcarusData/IcarusData.swift, Sources/IcarusContent/IcarusContent.swift, Sources/IcarusAds/IcarusAds.swift, Sources/IcarusUI/IcarusUI.swift (each `public enum <Target> {}`)
//   and Tests/<Target>Tests/PlaceholderTests.swift for the four other test targets
// promise: `swift build` on Linux succeeds with only Core/Content/Data targets present in `swift package describe`
```
FLAGGED STRUCTURAL: Package.swift shape and Slice 1's file list.

---

### 25. `Unit` collides with `Foundation.Unit`

POSTURE: 5 (a build collision that forces a rename the blind tests will not share)
SILENCE RANK: 25 (loud)
WHERE: `core-engine.md` Slice 1: `public enum Unit: Sendable, Equatable { case minutes, sed, multiple }`.
THE FLAW: Foundation exports `class Unit`. Every file importing both
Foundation (all of them) and IcarusCore sees an ambiguous `Unit`; the coder
renames, the blind tests use the Signatures name, assembly disagrees.
THE FIX: `public enum FigureUnit: Sendable, Equatable { case minutes, sed, multiple }` and `Figure.unit: FigureUnit`. FLAGGED STRUCTURAL: a Signatures rename.

---

### 26. Two dependencies have no approval artifact the merge rule accepts

POSTURE: 5
SILENCE RANK: 26 (loud at review)
WHERE: `learn-tab.md` Slice 2: "Package.swift: IcarusUI adds dependency .product("MarkdownUI", package: "swift-markdown-ui") pinned exact 2.4.1"; `release-readiness.md` Slice 1: "IcarusAds adds the Google Mobile Ads SPM dependency pinned exact".
THE FLAW: AGENTS.md: "land the approval as a repository artifact before the
dependency merges: a `docs/DECISIONS.md` entry, or a `docs/BACKLOG.md` item
the pull request cites … Record what it is for, why the standard library …
will not do, and its licence." `docs/DESIGN.md` §10 names both, but the rule
names the two ledgers, and `plan-metrics.sh` will flag the manifest change
for a reviewer who then looks for the entry.
THE FIX: two `docs/DECISIONS.md` entries, landed before those slices'
branches: swift-markdown-ui 2.4.1 (MIT; Apple's markdown lacks tables), and
the Google Mobile Ads SDK (Google's licence; the only network with fill in
non-personalised mode). Not structural.

---

## CLOSED ANGLES

Attacks the pseudocode survives, one line each:

- Type II, m = 1, standard, UVI 7: 2.25 SED × 66.7 / 7 = 21.44 min; the interpolated-end rule gives 21 + (2.25 − 2.204)/0.105 = 21.44, inside ±0.5.
- SPF 50 at 2.0 / 1.0 / 0.5 mg/cm² = 50 / 7.07 / 2.66; attenuation 5 → SPF 30 (5.48 ≥ 5 > 4.47); attenuation 8 → nothingRealistic (7.07 < 8); densityDefault 2.0 → SPF 15 covers 8.
- weight(0) = 1; weight(15, burn) = 5/17.5 = 0.286; weight(100, burn) = 5/22.5 = 0.222; non-burn floor 2.5/22.5 = 0.111.
- τ = 7.2 with a 21-day half-life between daily events: 21 sessions → 0.799 (±0.02 holds; the exact solution is 7.16); daily saturation 0.821; five-a-week fixed point 0.784; eight weeks × 5/wk = 0.784 ≥ 0.75.
- Escalation notice at tanState ≥ 0.5: absent after week one (0.473 at the peak, 0.43 after the weekend), present from week two (0.66); use case 6 at five weeks is 0.777, "well past" the line.
- Four-week gap from the 5/wk fixed point: factor 1.976 → 1.389, dose 30% smaller ≥ 25%.
- S3 convergence: true 0.75 → faintPink at ratio 1.0 on report 1 → weight 1 → m̂ = 0.75 in one report; normal outlier at 15 moves 0 (ratio 0.9 ≤ 1); redSore at 15 moves −0.137 (in −0.10…−0.20); redSore after nCap moves −0.107 ≥ 0.10.
- Separation: true gain 0.7× settles m̂ at 0.882 (within 0.10 of 1.0, margin 0.018 — thin but holds); 1.0× and 1.3× stay at 1.000; the first post-gap recommendation is below the true threshold in all three.
- Type III standard: 0.95 × 0.9 = 0.855 MED, bound melanogenic; type IV standard 0.675 < type II's 0.9; every (type, ceiling) target ≤ MED.
- `alternative(have:)`'s reading — the user names label *and* application, thick only if they picked thick — matches design revision 3 and use case 3 (SPF 15 normal → shade), and S2's "thick when that suffices" is the thick pick.
- Reapplication times `start + k × 2 h while < end`: empty at exactly 2 h, one at 2 h 01.
- Forecast cadence: 30 min → one provider call; 10.1 km → a second; force → a call; provider failure with a cache → `.cached(_, .providerFailed)`; one-sample response → `.malformed`, never `.provider`.
- `import` decodes and validates fully before `replaceAll`; a corrupt file leaves the history untouched.
- `discardPlanned(before:)` at `plannedWindow.end + 72 h` matches R45's "when the prompt's in-app window closes"; `dueInApp` windows 12–72 h and 3–10 d match R20.
- `History.ordered()` emits lasting colour by its own timestamp and only when set; a report without one is folded once.
- `ForecastCurve` excludes the prefix integral from Codable and rebuilds it; `StoredCurve` keeps every sample to day end + 6 h, so `sed(a, b)` round-trips exactly.
- `DayKey` carries the zone, so replay is host-zone independent; S18's UTC/Oslo double run is the right harness.
- The twelve `## Module N — ` headings and thirty-five `> - ` citation lines in `docs/LEARN_CONTENT.md` match `LearnSource.split` and the parser's line selector; Module 1 has no table.
- S11's literal grep on copy-bearing call sites forces even `Text("\(n) min")` through `AppCopy` with args, which is the intent.
- Aggressive re-locks after a gap ends the cycle (the redness bound is per cycle) — V15-consistent, and `aggressiveRefused` carries the copy.
- Warnings are gated on `.stayWholeWindow` independently of the overshoot test, so use case 1 carries none and use case 4 carries `.reachesThreshold(front, 4.0)` (2.0 + 2.0 ≥ 2.5).
- `HistoryStore.state(now)` memo keyed on history hash, tunables version, today's key and the profile; `invalidate()` after a profile change is the only path that needs it.
- The 14:00–17:00 steep-then-flat fixture and the analytic ramp are shape-defined and the trapezoid on a one-minute prefix integral is exact for piecewise-linear input.
- Performance: a 10-day prefix integral is 14,400 doubles; the up-and-about search is ~180 starts × 40 bisection steps × 3 regions of O(1) reads; the lying search is ~180 × 180; both well inside 100 ms.
