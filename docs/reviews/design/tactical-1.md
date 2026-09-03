# Tactical adversarial review 1 — the settled pseudocode plans

Reviewed: `docs/plans/core-engine.md`, `data-layer.md`, `calculator-ui.md`,
`learn-tab.md`, `logging-calibration.md`, `history.md`, `release-readiness.md`
(all `format: pseudocode`, at commit 30d2389), against `docs/DESIGN.md`
revision 3, `docs/VISION.md`, and the rulings in `docs/DECISIONS.md`. The
reviewer is fresh: it read no earlier review under `docs/reviews/design/`.
Arithmetic was checked by re-deriving every asserted number from the
formulas in the plans (a small simulation of the F3 recurrence, the minute
grid, the S3 weights, the SPF ladder).

## Overall build risk

The engine plans are unusually explicit and most of the numeric core is right:
the S3 weights, the SPF density points, the S3 outlier moves and the S4 gap
drop all reproduce from the pseudocode. The risk is not in the arithmetic the
tests will assert; it is in the seams the contracts never mention, and they
cluster in one place — **the moment a session becomes real**. Nothing in Core
takes a `SunscreenChoice` and returns an attenuated dose; none of the three
logging entry points (the result's "I did this", the flip timer, the
day-after "yes") carries a sunscreen confirmation; and the calculator never
schedules the skin check for a session it only planned. Each of those passes
every blind test written from the contracts, because the contracts are silent
about them, and each one corrupts the calibration loop the whole product is
built around: a user who follows the sunscreen headline and says "yes" the
next day is logged at three to five times the dose they received and is
walked to the multiplier clamp in one report. Second cluster: the tan-state
constant was solved without the decay the same pseudocode applies before
every event, so the plateau outcomes (tan state ≥ 0.9) are unreachable in use
and the S4 week-one bound is unreachable for any τ — the blind tests will
either catch this loudly at assembly or, more likely, be loosened. Third:
several shapes were picked by default — a calendar-less `DayKey`, replay
under today's profile, a lasting-colour answer with no timestamp, a planned
session created on every recompute and never discarded — and each fights an
extension the design already names. The build is doable as planned, but the
first field use of the logging loop will produce wrong calibration unless
findings 1–3 and 6–11 are landed first; ten findings below are flagged
structural and should trigger the second tactical pass the flow allows.

---

## Findings, ordered by silence

### 1. A session is logged at its bare dose whatever sunscreen the user wore

POSTURE: 3 (contract vs internals drift), 5 (slice seam)
SILENCE RANK: 1
WHERE:
- `core-engine.md` Slice 2 Signatures: `public static func dose(of side: Side, over w: Window, curve:, tunables:) -> [Region: SED]` — no sunscreen parameter anywhere in Core. Slice 3 Signatures: `public var dosePerRegion: [Region: SED] // after sunscreen; stored, never recomputed`.
- `calculator-ui.md` Slice 3 Internals: `didThis(): env.history.log(id, actual: plannedWindow, sunscreen: confirmed, doses: plan.perRegionDose, factors, targets)`; Signatures: `public func didThis() async throws // logs the planned session with the planned window and the confirmed sunscreen` — no parameter or published property carries the confirmation.
- `calculator-ui.md` Slice 4 Internals: `FlipTimerModel.start: plan = ExposureModel.solve(request with window from now, firstSide) ; history.log(id, actual: Window(now, now+total), …)` and `stop(now): … doses = Σ sides ExposureModel.dose over min(side window, now)` — bare doses, no attenuation, no cover.
- `logging-calibration.md` Slice 1 Internals: `didDo(id, actual): doses = ExposureModel doses over actual sub-intervals with the stored curve and the confirmed sunscreen` — the flow pages are `DidYouDoThis (repeat per planned) → Q1 → …`; no page confirms sunscreen.
THE FLAW: R15 says "the logged dose uses whatever the user confirms at logging: the recommended pair, the alternative they picked, or none", and `SessionRecord.dosePerRegion` is documented as "after sunscreen". But no Core signature attenuates a dose by a `SunscreenChoice`, so three UI coders will each invent the division (whole-body? head-and-shoulders only when not covered? on the raw whole-window dose or the sub-window?), and two of the three entry points have nowhere to put the confirmation at all. Take use case 3: the headline is "SPF 30, applied normally, stay the three hours". The user does exactly that, and next day answers "yes". `didDo` re-derives "planned doses" from the stored curve with sunscreen `nil` (the record's `sunscreen` is only ever set by `log`, which is what `didDo` is calling): three hours of bare dose ≈ 5 × target. The report is "normal" → `ratio ≈ 5` → `creditTolerant` saturates tan state in one step and `implied = m × (1 + unabsorbed)` capped at `m × ratio` → `m += 1.0 × (≈4m − m)` → clamp at 1.8 → `.clampHit(revisitSkinType: true)` after the user's very first honest report. The timer has the same hole in the other direction: a lying session with the prescribed sunscreen and reapplication alerts is logged at the bare per-side doses.
CONSEQUENCE: Every blind test passes — "didThis writes a logged SessionRecord with curveUsed", "submit after didDo logs the planned session first", "stop at half time halves the front dose (flat curve)" are all true of the bare path. `reproduce(session) == session.dosePerRegion within 1e-6` passes because the test-writer, lacking any attenuation function, builds sessions without sunscreen. The owner notices in use, on the first sunscreen session, as a multiplier that jumps to the clamp and a "revisit your skin type" prompt.
THE FIX (structural — adds to two Signatures blocks and one flow):
```text
// core-engine.md Slice 4 Signatures (SunscreenChoice already lives here)
public enum ExposureModel {
    public static func dose(of side: Side, over w: Window, curve:, tunables:) -> [Region: SED]   // bare
    public static func attenuated(_ bare: [Region: SED], sunscreen: SunscreenChoice?, coverHeadAndShoulders: Bool) -> [Region: SED]
        // every region ÷ sunscreen.effectiveSPF (nil → ÷1); headAndShoulders = 0 when covered; this is THE function every logging path calls
}
// Promise: attenuated(x, 50 normal) == x / 7.07 per region within 1e-9; attenuated(x, nil, cover: true)[.headAndShoulders] == 0

// calculator-ui.md Slice 3 Signatures
@Published public var confirmedSunscreen: SunscreenConfirmation   // .asPrescribed | .alternative(SunscreenChoice) | .none ; defaults to .asPrescribed iff headline == .sunscreenForWholeWindow else .none
public func didThis() async throws   // doses = attenuated(dose over the window the confirmation implies, confirmedSunscreen)

// calculator-ui.md Slice 4: FlipTimerModel.start/stop take the same confirmation from CalculatorModel; stop() re-attenuates.
// logging-calibration.md Slice 1: DidYouDoThis page gains "Did you wear <prescribed>?" (yes / I used … / no) and didDo(id, actual:, sunscreen:) passes it.
```

### 2. A session that was only planned never gets its skin check

POSTURE: 2 (silent failure), 5 (slice seam between calculator-ui and data-layer)
SILENCE RANK: 2
WHERE: `calculator-ui.md` Slice 3 Internals: `result = Planner.plan(req); if case .plan → env.history.addPlanned(SessionRecord(...)); plannedSessionID = id` and, only in `didThis(): … env.prompts.sessionsChanged(day, lastEnd)`. `data-layer.md` Slice 4: `sessionsChanged(on day: DayKey, lastSessionEnd: Date) async // (re)schedule skinCheck day+20h`.
THE FLAW: Design decision 21 and R20 exist for the user "who read the number and went": the prompt is scheduled from *planned or logged* sessions and opens with "Did you do this session?". In the pseudocode `sessionsChanged` is called from `didThis()` and nowhere else. `compute()` writes the planned record and stops. The user who reads the number, goes, and never taps "I did this" gets no notification; `dueInApp` would list the day on the next launch, but the design's stated reason for planned-session prompts is precisely that this user does not come back to the app.
CONSEQUENCE: `PromptSchedulerTests` test the scheduler given calls; `CalculatorModelTests` test that `didThis` logs. Neither can see that `compute` fails to call the scheduler, because the contract never promises it. In use: the majority of sessions produce no prompt, the app never learns most users, and the escalation loop never advances for them — quietly, forever.
THE FIX (not structural):
```text
compute(): … if case .plan → id = env.history.upsertPlanned(...)   // see finding 9 for upsert
            let lastEnd = max(window.end, (try env.history.sessionsOn(day)).map(\.end).max())
            await env.prompts.sessionsChanged(on: day, lastSessionEnd: lastEnd)
// Contract line to add to CalculatorModel: "after compute() returns .plan, the port holds exactly one pending skinCheck(day) at lastEnd + 20 h"
```

### 3. The solver returns the first minutes of the slot, not the best ones; the lying solve breaks on a rising curve

POSTURE: 3 (drift), 2 (silent failure)
SILENCE RANK: 3
WHERE: `core-engine.md` Slice 2 Internals: `upAndAbout: // single interval starting at w.start; find the longest duration d such that for all regions dose(d) ≤ remaining` and `lyingTurning: … d1*, d2* from bestSubWindow on the region's remaining target within w (side 1 from w.start; side 2 from side 1 end)`. Slice 1 Signatures: `bestSubWindow … the shortest contiguous block ≥ now that delivers targetSED, ties → nearest solar noon`.
THE FLAW: Two different quantities are conflated. `bestSubWindow` finds the shortest block *anywhere* in the window (on a 09:00–12:00 rising curve that block ends at 12:00). The up-and-about solve then ignores it and takes `d` minutes *from `w.start`*, so use case 1's "the best 18 minutes inside that slot" and R17's "optimal sub-window inside a longer slot (the highest-UVB slice)" are never produced — the plan's window always starts at the slot start. For lying, `d1*` comes from `bestSubWindow` (a block near the end on a rising curve) while side 2 starts "from side 1 end" — on a morning session side 2 starts at or after `w.end`, is clipped to nothing, and the coupled solve then scales two windows that are not consecutive.
CONSEQUENCE: Every fixture the design names is evening-falling or flat (use case 2, `eveningFalling`, `steadyUVI`), where "first minutes" and "best minutes" coincide. S18 asserts headline minutes ±10%, not which minutes. A morning lying session — the second most common real session — produces a nonsensical side 2 in production, and every up-and-about result in a long slot names the wrong minutes.
THE FIX (internals only):
```text
durationFrom(start, targetSED, curve) -> Double?   // smallest d with sed(start, start+d) ≥ target; nil if none within w
upAndAbout:
  for s in minute grid of w: d(s) = bisection over [0, w.end − s] on maxOverExposedRegions(dose(s, d)/remaining) ≤ 1
  pick s minimising d(s); ties → |mid − solarNoon| smallest; sides = [Window(s, s + d)]
lyingTurning:
  for s in minute grid of w: d1 = durationFrom(s, rem(side1 region)) ?? (w.end − s); d2 = durationFrom(s + d1, rem(side2 region)) ?? (w.end − s − d1)
  pick s minimising d1 + d2 subject to s + d1 + d2 ≤ w.end; then apply the F2 scalar shrink to (d1, d2) from that s
// bestSubWindow keeps its contract; it is durationFrom minimised over s for a single region.
```

### 4. The tan-state constant was solved without the decay the pseudocode applies, so the plateau can never be reached

POSTURE: 2 (silent failure) — arithmetic
SILENCE RANK: 4
WHERE: `core-engine.md` Slice 3 Internals: `Discrete form of the leaky integrator (ruled D-2026-09-03-F3): per-event update with decay applied by elapsed time before each event (decayed then advanced) … riseTimeConstantDays is solved offline so that 21 daily sessions at doseFraction 1.0 land at tanState 0.8 for band .fair (τ ≈ 13.0 d, see test)`; Signatures: `decayed … tanState × 0.5^(Δdays / halfLife)`, `advanced … tanState += (1 − tanState) × (1 − exp(−doseFraction × riseMultiplier[band] / riseTimeConstantDays))`; Internals `plateauOutcome: noColourNearCeiling ≥ ceilingNoColourCount && tanState ≥ 0.9` and `.lastingColour(r): … tanState ≥ 0.9 → noColourNearCeiling += 1`.
THE FLAW: τ = 13.05 is exactly the solution of `1 − (1 − a)^21 = 0.8` with **no decay**. Apply the plan's own recurrence (decay by one day at half-life 21 d, then advance) and 21 daily sessions land at **0.641**; the fixed point for daily sessions is **0.711**, for five per week **0.654**. Tan state ≥ 0.9 is unreachable at any cadence, so `noColourNearCeiling` never increments, `plateauOutcome` never fires, and R14's maintenance dose, ceiling copy and under-dosed copy are dead in production. (Solving for 0.8 at 21 days *with* decay gives τ ≈ 7.2 d, whose daily saturation is 0.82 — still below 0.9.) The threshold 0.9 is also a literal in two places and not in `Tunables`, so it cannot be moved without a code change, against R30. Same recurrence: the escalation notice `factor − 1 ≥ 0.10` needs tanState 0.08, which the first or second session delivers, so every user sees "your threshold has risen" on day two — not the "after five weeks" of use case 6.
CONSEQUENCE: The blind plateau test constructs `RegionState(tanState: 0.95, …)` directly and passes; the F3 τ test asserts 0.8 at 21 sessions and fails loudly — but the likely repair is to change τ, which does not make 0.9 reachable. This is D-F3's own stated premise ("τ solved offline so 21 daily standard sessions reach 0.8") being false in the pseudocode, which is the one ground on which a ruled item is in scope.
THE FIX (structural — Tunables Signatures gain a field; the τ derivation and the plateau threshold change together):
```text
public let plateauTanState: Double       // 0.75  assumption: "near saturation" = above the 5/wk fixed point, below daily saturation, under the F3 recurrence with halfLife 21
public let riseTimeConstantDays: Double  // solved WITH the F3 decay: 21 daily sessions at doseFraction 1.0 → 0.8 ⇒ τ ≈ 7.2 d; the test asserts the recurrence, not a closed form without decay
// plateauOutcome / .lastingColour use tunables.plateauTanState, never a literal
// Promise to add (S4): "five sessions per week for eight weeks reaches tanState ≥ plateauTanState; a 'no' then increments noColourNearCeiling"
// Owner note, not a fix: with gain 1.25 the notice line 0.10 fires on session two; either escalationNoticeFraction rises (≈0.5) or the notice is defined as factor ≥ 1 + fraction × (cap − 1).
```

### 5. Warnings and the sunscreen prescription ignore what was already logged today

POSTURE: 2 (silent failure)
SILENCE RANK: 5
WHERE: `core-engine.md` Slice 2 Internals: `warnings(entered): … for each region: if dose > target → .pastTarget; if dose ≥ medPersonal → .reachesThreshold`. Slice 4 Internals: `overshoot = rawPerRegion[limiting] > target[limiting].target` and `sunscreen = overshoot ? SunscreenSolver.outcome(raw, target, w, …)` where `outcome … attenuation = raw/target`.
THE FLAW: Use case 4 is the second session of the day with "the front has 15% left". The stay-whole-window dose that matters is `doseToday + dose`, and the budget the sunscreen must protect is `remaining`, not `target`. Both comparisons use this window's dose alone against the full target: a 2.0 SED afternoon on a front that already has 2.0 SED logged (target 2.25, MED 2.5) compares 2.0 < 2.25 → no `.pastTarget`, no `.reachesThreshold`, no sunscreen — while the day's total, 4.0 SED, is 1.6 × MED. This is the one place the design asks for Module 7 burn language and V2's "never under-warn", and it under-warns exactly on the second session.
CONSEQUENCE: The blind promise "`.stayWholeWindow` with entered window past target → `.pastTarget`" is tested from `DerivedState.initial` (doseToday 0), where both formulas agree. A second-session warning test cannot be written from the contract because the contract never mentions `doseToday` in the warning rule. In use, the after-lunch return is the burn the app exists to prevent.
THE FIX (internals; one contract line):
```text
warnings(entered): for each region: total = rs.doseToday + dose(region over entered)
  if total ≥ medPersonal → .reachesThreshold(region, total) else if total > target → .pastTarget(region, total)
Planner: overshoot = rawPerRegion[limiting] > target[limiting].remaining
         sunscreen = overshoot ? SunscreenSolver.outcome(rawSED: raw, targetSED: target[limiting].remaining, …)
// Signatures promise to add: "warnings compare doseToday + this window's dose; a second session whose sum reaches medPersonal warns strongly even when the window alone does not"
```

### 6. Replay recomputes history under today's profile, and the state cache never notices a profile change

POSTURE: 1 (wrong shape), 2 (silent failure)
SILENCE RANK: 6
WHERE: `core-engine.md` Slice 3 Internals: `target = TanningGoal.target(region, …, now: s.actualWindow.start, stale: false) // recomputed from replayed state, NOT s.targetsShown` … `rs = advanced(rs, doseFraction: s.dosePerRegion[region] / target.target)`, with `Replay.replay(_ h: History, profile:, now:, tunables:)` taking one `Profile`. `data-layer.md` Slice 3 Internals: `HistoryStore.state: cache (history hash, tunables.version, DayKey(now)) → DerivedState; invalidate on every write`, and `init(container:, tunables:, profileProvider: @Sendable () -> Profile)`.
THE FLAW: `doseFraction = dose / target` (R12) is meant to make a session at *the target of the time* advance tan state equally. The pseudocode divides by the target computed with **today's** `profile.ceiling` and `manualMultiplier`. A user who tanned six weeks at conservative (target 0.75 × MED) and switches to aggressive sees every historical session re-read as 0.75 of target: tan state replays lower, the factor drops, the recommendation shrinks. Move the selector back and it all comes back. The manual override does the same to every historical calibration `est`. R44 forbids using *stored factors and targets* as replay inputs because they are derived; the ceiling and the override are user choices, not derived numbers, and must travel with the record. Separately, the memo key omits the profile: `overrideMultiplier` in Settings changes nothing on the result until the next write or the next day, because `state(now)` returns the cached state.
CONSEQUENCE: "a Tunables change (different halfLife) followed by state(now) changes the result" passes; nothing tests a ceiling change mid-history or a Settings change without a write, because neither is in a contract. The owner sees a number jump when they touch the selector, and an override that "does nothing" until tomorrow.
THE FIX (structural — SessionRecord Signatures and the export format gain two fields; the store's memo key changes):
```text
public struct SessionRecord { …; public let ceilingAtPlan: Ceiling; public let manualMultiplierAtPlan: Double?   // replay INPUTS: what the user had chosen, not what was derived
Replay: target = TanningGoal.target(region, profile: Profile(skinType: profile.skinType, ceiling: s.ceilingAtPlan, manualMultiplier: s.manualMultiplierAtPlan), …)
CalibrationEngine.apply: est uses the day's sessions' ceilingAtPlan/manualMultiplierAtPlan (last session of the day), not the current profile
HistoryStore.state memo key: (history hash, tunables.version, DayKey(now), profileProvider())   // and a public func invalidate()
// Promise to add (S10): "changing profile.ceiling after N sessions leaves state.regions[*].tanState unchanged"
```

### 7. "All exposed" redness is calibrated from the highest-dose region — the least conservative reading of a burn

POSTURE: 1 (wrong shape)
SILENCE RANK: 7
WHERE: `core-engine.md` Slice 3 Signatures: `evidenceRegion(_ report: SkinReport, daySessions:) -> Region // named region, or the highest-dose region for .allExposed`; Internals: `dose = Σ daySessions dosePerRegion[region] … ratio = dose / est … implied = m × (ratio / impliedRatio[answer])`. DESIGN §11 asks for exactly this choice to be reviewed here.
THE FLAW: For a "normal" answer the highest dose is right: every region tolerated its dose, and the largest is the strongest one-sided bound. For a redness answer it is backwards. "Clearly pink, all exposed" means every region crossed its line, including the one that received the least — and the tightest (lowest) implied threshold comes from the lowest-dose region. Lying face-up-first credits head-and-shoulders with `faceUp + 0.5 × faceDown`, the highest dose almost every time, so a burn on all exposed is attributed to the region that best excuses it and the multiplier moves least. That is the V2 direction reversed on the report type that matters most.
CONSEQUENCE: S3's simulations use a single region; the blind test for `evidenceRegion` asserts the contract's words. In use, "red all over" nudges the multiplier down by less than a "red on the front" would, and the next day's dose is higher than the evidence supports.
THE FIX (contract line changes; not structural):
```text
public static func evidenceRegion(_ report: SkinReport, daySessions:) -> Region
    // named region; for .allExposed: answer == .normal → the highest-dose region (strongest one-sided evidence);
    // any redness → the lowest-dose region among regions with dose > 0 that day (tightest bound on the threshold)
```

### 8. A report on a day with no logged dose drives the multiplier to the clamp; the "factor in force that day" is read after the day's sessions advanced it

POSTURE: 2 (silent failure)
SILENCE RANK: 8
WHERE: `core-engine.md` Slice 3 Internals: `.report(r): sessions = h.sessions.filter(day == r.day && logged)`; `CalibrationEngine.apply: … dose = Σ daySessions dosePerRegion[region]; af = factor in force that day (replayed); est = medPersonal(region) at that day (replayed); ratio = dose / est … else: implied = m × (ratio / impliedRatio[answer]) … m += weight × (implied − m)`. Replay order: `.session(s) … rs = advanced(rs, …)` precedes `.report(r)` for the same day.
THE FLAW: (a) The skin-check flow proceeds to Q1 after every planned session is answered "no" (`SkinCheckFlow pages: DidYouDoThis (repeat per planned) → Q1 → …`). With zero logged dose, `ratio = 0`; a "clearly pink" from a walk the app never planned gives `implied = 0`, `m += weight × (0 − m)` — with weight 1.0 at n = 0 the multiplier goes straight to the clamp and the user is told to revisit their skin type. (b) "In force that day" is evaluated *after* `advanced` ran for that day's sessions, so `est` is the post-session threshold, not the one the session was planned against (the one R21 says to divide out). The bias is systematic (≈ gain × Δtan ≈ 9% of the factor early in a cycle) and always in the same direction.
CONSEQUENCE: (a) is reachable by any user on day two; no contract mentions the zero-dose case. (b) S3's promises are stated at ratios that do not move the multiplier (normal at 0.9) or are insensitive to a 9% shift; the separation simulation absorbs it. Neither shows in a test.
THE FIX (internals; one contract line):
```text
apply: guard dose > 0 else → (state unchanged, .none)   // a report with no logged dose is recorded, never calibrated
       af = rs.factorAtLastSession                        // set in .session before advanced; the factor the day's plan used
       est = baseline[skinType] × m × af
// Contract: "a report on a day with no logged session returns .none and leaves multiplier and tanState unchanged"
// SkinCheckFlow: when every planned session is answered "no" and none is logged, skip Q1–confounders and say so (copy key .noSessionToReport)
```

### 9. Planned sessions are created on every recompute and never discarded

POSTURE: 1 (wrong shape), 2 (silent failure)
SILENCE RANK: 9
WHERE: `calculator-ui.md` Slice 3 Internals: `compute(): … if case .plan → env.history.addPlanned(SessionRecord(planned from req and result, …))`. `data-layer.md` Slice 3 Signatures: `addPlanned(_ s: SessionRecord)`, `plannedSessions(on: DayKey)`; Slice 4 Internals `dueInApp: for each day with any planned-or-logged session and no report: …`. `logging-calibration.md` Slice 1: `planned: [SessionRecord] // still-planned sessions that day` and `one "Did you do this session?" per still-planned session`. R45: "A planned session never logged is discarded when its skin-check prompt is answered 'no' or when the prompt's in-app window closes unanswered, never before."
THE FLAW: `compute()` runs on every window, posture, cover or intent change; each run appends a planned record. Ten tweaks → ten "Did you do this session?" questions the next day. Nothing in any plan discards planned sessions when the 72-hour in-app window closes (`dueInApp` only lists; no caller discards), so they accumulate forever, and `SettingsModel.unreportedDays` ("days with sessions and no report") counts a day the user merely looked at.
CONSEQUENCE: The contracts promise `didThis writes a logged SessionRecord` and `submit twice … throws`; neither can see the multiplicity. The owner meets it on day two as a prompt that asks about the same lunch break six times, and a Settings count that never reaches zero.
THE FIX (structural — HistoryStore Signatures change):
```text
public func upsertPlanned(_ s: SessionRecord, replacing id: UUID?) throws -> UUID   // compute() passes plannedSessionID; a new model instance passes nil
public func discardPlanned(before cutoff: Date) throws -> Int                         // every .planned session whose skin-check in-app window closed; called from dueInApp's caller on appear/foreground
unreportedDays counts days with a LOGGED session and no report
// Promise: "compute() twice in one model leaves exactly one planned session; a planned session older than lastEnd + 72 h is discarded on the next launch"
```

### 10. The lasting-colour answer has no time, so replay cannot place it; the colour prompt is scheduled for days that have no report

POSTURE: 1 (wrong shape), 3 (drift), 5 (seam)
SILENCE RANK: 10
WHERE: `core-engine.md` Slice 3 Signatures: `SkinReport { …; public var lastingColour: LastingColour?; …}`; `History.ordered() // by time: logged sessions (actual end), reports (reportedAt)`; `HistoryEvent … case lastingColour(SkinReport)`; Internals `.lastingColour(r): for region with doseFraction that day ≥ lastingColourRegionFraction: if r.lastingColour == .no && tanState ≥ 0.9 → noColourNearCeiling += 1`. `data-layer.md` Slice 4: `sessionsChanged … (re)schedule skinCheck day+20h, lastingColour +4d` and `setLastingColour(day: DayKey, _ lc:)`. `logging-calibration.md` Slice 2: "Four days after a reported day … attaches to that day's report".
THE FLAW: `ordered()` defines a time for two of the three event kinds. `.lastingColour` has none — `SkinReport` carries no `lastingColourAt` — so the coder places it wherever is convenient (immediately after the report, most likely). The rule reads `tanState` at that moment, four days early and before the intervening sessions; and "doseFraction that day" needs the per-region dose *and target* of a day that replay has already left behind (`RegionState.doseToday` only holds the running day). Separately, `PromptScheduler` schedules the colour notification from the *session* end whether or not a report was ever made, while `dueInApp` lists colour only "for each day with a report"; tapping the notification on a report-less day calls `setLastingColour(day:)`, whose behaviour with no report is undefined (throw? create? drop?).
CONSEQUENCE: Replay is promised to be "a pure function of (history, profile, now, tunables)"; with an untimed event it is a function of the coder's ordering choice, and export/import round-trips a history that a different build could replay differently. The blind tests construct reports with `lastingColour` set and assert counts — they pass under any ordering. In use: plateau counts are wrong in a way nothing displays, and a notification leads to an undefined action.
THE FIX (structural — SkinReport Signatures and the export format gain a timestamp; PromptScheduler gains one call):
```text
public struct SkinReport { …; public var lastingColour: LastingColour?; public var lastingColourAt: Date? }
History.ordered(): sessions by actualWindow.end, reports by reportedAt, lastingColour by lastingColourAt (absent → not emitted)
Replay: keep dayDose: [DayKey: [Region: (dose: SED, target: SED)]] as sessions fold; .lastingColour reads dayDose[r.day]
PromptScheduler.reportAdded(on day: DayKey, at: Date) async   // schedules lastingColour at + lastingColourDelayDays; sessionsChanged no longer schedules it
HistoryStore.setLastingColour(day:, _:, at:) throws HistoryError.noReport(day)
```

### 11. "I did this" pairs the full planned window with the sub-window's doses

POSTURE: 2 (silent failure)
SILENCE RANK: 11
WHERE: `calculator-ui.md` Slice 3 Internals: `didThis(): env.history.log(id, actual: plannedWindow, sunscreen: confirmed, doses: plan.perRegionDose, factors, targets)`.
THE FLAW: With intent `.bestMinutes` the headline is "the best 18 minutes" and `plan.perRegionDose` is the dose of those 18 minutes; the record's `actual` is written as the entered 45-minute slot. The record now says 45 minutes at 18 minutes' dose. `ExportService.reproduce` re-derives "perRegionDose of the logged actual window … over actual sub-intervals" — 45 minutes' worth — and disagrees with the stored doses; History shows a 45-minute session; the day-after question names the wrong window; the stored `curveUsed` is right but the interval it applies to is wrong. With intent `.stayWholeWindow` the opposite mismatch: the window is right and the doses are the bare sub-window's (see finding 1).
CONSEQUENCE: `reproduce(session) == session.dosePerRegion within 1e-6` is tested on records the test builds itself; the mismatch is between two UI decisions no contract states. The owner sees a History that disagrees with the result they acted on.
THE FIX (internals):
```text
didThis(): actual = (headline == .bareSubWindow) ? plan.sides.first.window.start … plan.sides.last.window.end : plannedWindow
           doses  = (headline == .bareSubWindow) ? plan.perRegionDose : attenuated(rawPerRegion over plannedWindow, confirmedSunscreen)
// contract: "didThis logs actual == the plan's sides' span when the headline is the bare sub-window, and the entered window when it is the sunscreen answer"
```

### 12. `DayKey` has no calendar of its own, so day boundaries are an implicit global and solar-noon lookups can miss

POSTURE: 1 (wrong shape), 2 (silent failure)
SILENCE RANK: 12
WHERE: `core-engine.md` Slice 1 Signatures: `public struct DayKey: Codable, Sendable, Hashable { public init(_ date: Date, calendar: Calendar) }`; Slice 3 Internals: `final decay of every region to now; doseToday recomputed for DayKey(now)` inside `Replay.replay(h, profile, now, tunables)`, which takes no calendar; Slice 4 Internals `uvaHeavy = isUVAHeavy(w, solarNoon)` via `curve.solarNoon(on: DayKey)`, again with no calendar in `PlanRequest`. `data-layer.md` Slice 1: `WeatherKitProvider … daily sun.solarNoon` keyed by `DayKey` built in the Data layer with an unstated calendar; `HourlyUVI` from WeatherKit's `uvIndex` — and WeatherKit's `solarNoon` is `Date?`, with no fallback in the pseudocode despite §6's "the Data layer computes it from date and location by formula".
THE FLAW: Every `DayKey(now)` inside Core must pick a calendar the signature does not carry — `Calendar.current` in practice — so `Replay` is a function of the process's time zone, not of its arguments. A test that logs 23:30Z and replays at 00:30Z expects `doseToday == 0` on the Linux runner (UTC) and gets the previous day's dose on a developer's Mac in the US. The provider keys `solarNoon` by whatever calendar the mapping used (the location's day? the device's?); if it differs from the Planner's, `solarNoon(on:)` is `nil` and `isUVAHeavy` has no defined input — the pseudocode force-unwraps or defaults silently. A `nil` from WeatherKit does the same for a whole day.
CONSEQUENCE: The purity promise ("replay is a pure function of …") is untestable as written and false as built. In use: a user who plans across a time-zone change or in the polar summer gets a UVA note (or none) from a missing solar noon, and a day boundary that moves with the phone's settings.
THE FIX (contract; not structural if done in Slice 1):
```text
public struct DayKey: Codable, Sendable, Hashable { public let year: Int; public let month: Int; public let day: Int; public let timeZoneID: String
    public init(_ date: Date, timeZone: TimeZone) ; public func start(in:) -> Date }
public struct ForecastCurve { …; public let timeZone: TimeZone /* the location's, from the provider */; public func solarNoon(on: DayKey) -> Date /* stored, else computed by the NOAA formula from location and day */ }
PlanRequest and Replay take no calendar: every DayKey they build uses curve.timeZone (Planner) or the record's own day (Replay); doseToday is keyed by the session's stored DayKey, never by DayKey(now) recomputed.
```

### 13. `ExposureModel.solve` returns nil on the wrong condition and divides by zero on the right one

POSTURE: 3 (drift), 2 (silent failure)
SILENCE RANK: 13
WHERE: `core-engine.md` Slice 2 Signatures: `solve(_ r: ExposureRequest, tunables:) -> ExposurePlan? // nil when no region has remaining budget > 0 (→ Planner returns .budgetSpent)`; Internals: `d = bisection over [0, w.minutes] on maxOverRegions(dose/remaining) ≤ 1; if d == 0 → nil`. Slice 4 Internals: `if all remaining == 0 → .budgetSpent … plan = ExposureModel.solve(request with targets) … bare: plan.totalMinutes`.
THE FLAW: The internals return nil whenever *any exposed* region has `remaining == 0` (its ratio is ∞ for every d > 0, so d = 0), which is a different and more common condition than the contract's "no region has remaining > 0". Front fully spent this morning, head-and-shoulders not: Planner's `all remaining == 0` is false, `solve` returns nil, and the next line uses `plan.totalMinutes` — a crash or a fabricated zero. With the cover toggle on and head-and-shoulders remaining 0, `dose/remaining` is 0/0 = NaN, the comparison is false, and bisection returns garbage.
CONSEQUENCE: The blind test holds "second session: remaining = target − doseToday drives the solve" with a partial budget, and "all remaining == 0 → .budgetSpent" with none; the mixed case is between them and in no contract. R17 promises "never a crash, a nil, or a fabricated number" for "dose already logged today".
THE FIX (structural — one contract line changes):
```text
solve → nil when any region that receives dose in this posture (cover applied) has remaining ≤ 0
bisection: ratio(region) = remaining > 0 ? dose/remaining : (dose > 0 ? .infinity : 0)   // covered/zero-dose regions never limit
Planner: if all remaining == 0 → .budgetSpent ; plan = solve(…) ?? return .budgetSpent   // typed, with limiting region: case budgetSpent(Region)
```

### 14. Import discards the exported profile

POSTURE: 2 (silent failure)
SILENCE RANK: 14
WHERE: `data-layer.md` Slice 3 Signatures: `ExportFile { formatVersion; tunablesVersion; profile: Profile; history; exportedAt }`, `import(_ data: Data, into store:) async throws -> ImportSummary // replaces the history`, `ImportSummary { sessions; reports; tunablesVersion }`; Internals: `import: decode; guard formatVersion ≤ 1; store.replaceAll(history); return summary`.
THE FLAW: The store replays under `profileProvider()`, the device's current profile. An export made as type II imported on a phone onboarded as type III replays every session against 3.0 SED baselines: tan states, factors, and every historical calibration silently differ from the exporting device, and R25's "importing it reproduces the state and every figure" is false. The summary does not even say which profile the file carried.
CONSEQUENCE: "export → import → history() equal and state equal" is tested on one store with one profile and passes. The owner meets it when they change phones.
THE FIX (structural — ImportSummary gains a field; the caller applies it):
```text
public struct ImportSummary { sessions; reports; tunablesVersion; public let profile: Profile }
SettingsModel.importFile: summary = try await ExportService.import(data, into: env.history); env.profile.save(summary.profile); env.history.invalidate()
import: decode fully, validate every record, then replace inside one ModelContext transaction — a failure leaves the old history intact (history.md Slice 3 promises this; the pseudocode's replaceAll does not deliver it)
```

### 15. `dose(of side:)` cannot express "up and about" or the cover toggle it documents

POSTURE: 3 (drift)
SILENCE RANK: 15
WHERE: `core-engine.md` Slice 2 Signatures: `public static func dose(of side: Side, over w: Window, curve:, tunables:) -> [Region: SED] // faceUp: … faceDown: … // upAndAbout (single "side"): headAndShoulders = full; front = back = frontBackFraction × full // coverHeadAndShoulders → headAndShoulders = 0 in every case`, with `public enum Side { case faceUp, faceDown }`.
THE FLAW: The parameter list has a `Side` and nothing else; the comment describes three exposures and a cover flag. The blind test-writer can only call it with `.faceUp`/`.faceDown` and no cover. The coder must either add parameters (compile break at assembly — loud) or add a second, undeclared function for up-and-about and cover, which is then built and never tested. The up-and-about fractions are the labelled assumptions R30 wants provenance-tracked; the untested path is the one carrying them.
CONSEQUENCE: Half the posture model is outside the contract's reach; the `frontBackFraction` and cover behaviour promised in S5 are tested only through `solve`, indirectly.
THE FIX (structural — Signatures):
```text
public enum Exposure: Sendable, Equatable { case lying(Side), upAndAbout }
public static func dose(_ exposure: Exposure, coverHeadAndShoulders: Bool, over w: Window, curve:, tunables:) -> [Region: SED]
// SideAllocation.side becomes SideAllocation.exposure; upAndAbout is no longer "faceUp /*label only*/"
```

### 16. `submit()` promises a `CalibrationEffect` that no store or replay API can return

POSTURE: 5 (seam between logging-calibration, data-layer and core-engine), 3 (drift)
SILENCE RANK: 16
WHERE: `logging-calibration.md` Slice 1 Signatures: `public func submit(now: Date) async throws -> CalibrationEffect // … returns the effect for the confirmation copy`; Internals: `effect = CalibrationEngine.apply(...) recomputed by the store's replay (the store returns the last effect for the confirmation)`. `data-layer.md` Slice 3: `addReport(_ r: SkinReport) throws` returns nothing; `core-engine.md` Slice 3: `Replay.replay(…) -> DerivedState` returns no effect.
THE FLAW: The effect exists only inside `Replay`'s fold at the report's position in history. The UI coder, finding no API, will call `CalibrationEngine.apply` directly with `state(now)` — a state decayed to now, not the state at the report's place in the fold — and can get a different effect (`.tanStateCredited` vs `.multiplierMoved` hinges on tan state) from the one replay applied. The confirmation copy then explains something other than what happened.
CONSEQUENCE: The promise "confirmation copy key follows the effect" is tested against whichever path the coder wired. The divergence is silent by construction.
THE FIX (structural — two Signatures blocks):
```text
core-engine Slice 3: public static func replay(_ h: History, profile:, now:, tunables:) -> (state: DerivedState, effects: [UUID: CalibrationEffect])   // keyed by report id
data-layer Slice 3:  public func addReport(_ r: SkinReport) throws -> CalibrationEffect   // from the replay the write triggers
```

### 17. Three different viability bars, and the "no viable window" outcome is never produced

POSTURE: 3 (drift), 2
SILENCE RANK: 17
WHERE: `core-engine.md` Slice 1: `isViable … sed(max(start, now) → end) ≥ viabilityFraction × targetSED`; Slice 4 Internals: `melShortfall check: if for the limiting region rawPerRegion < viabilityFraction × melanogenic → .tooWeak(shortfall: melanogenic − raw, nextViable: nextViableWindow(after: w.end))`; Signatures: `case noViableWindow(days: Int, peakUVI: UVI)`, promise `noViableWindow.days == forecastHorizonDays`.
THE FLAW: R17 defines viability as a fraction of the *target*. The Planner tests the *melanogenic dose* (for an uncalibrated type II, 1.25 SED against a target of 1.875 × 0.5 = 0.94 SED), and neither uses `remaining`: a second session with 0.3 SED left on the front is declared "too weak to matter" by a bar it clears three times over. `nextViableWindow(after:)` is passed no target in the pseudocode — today's `remaining` would be wrong for tomorrow, whose budget is the full target. And no branch of `Planner.plan` maps `nextViable == nil` to `.noViableWindow(days:, peakUVI:)`; the internals produce `.tooWeak(…, nextViable: nil)`.
CONSEQUENCE: The `noViableWindow` promise fails loudly at assembly (good) — but the bar inconsistency does not: fixtures use fresh state where the three bars nearly coincide. In use, the after-lunch return at 17:00 gets "this window will not produce a lasting tan".
THE FIX (internals):
```text
viable(region) = rawPerRegion[region] ≥ viabilityFraction × min(target[region].remaining, target[region].target)
tooWeak when !viable(limiting): shortfall = target[limiting].melanogenic − raw ; nv = nextViableWindow(after: w.end, targetSED: target[limiting].target)
   nv == nil → .noViableWindow(days: forecastHorizonDays, peakUVI: curve.hourly.map(\.uvi).max())
```

### 18. The forecast is fetched on window change, against R1

POSTURE: 2 (silent failure)
SILENCE RANK: 18
WHERE: `calculator-ui.md` Slice 3 Internals: `compute(): loc = …; fr = await env.forecast.current(for: coord, now)`; `data-layer.md` Slice 1: `current … if !force, let c, now − fetchedAt < fetchMinIntervalHours, distance ≤ fetchMoveKm → .cached … else fetch`.
THE FLAW: R1: fetch "on foreground, on a location change of more than 10 km, and on explicit refresh; never on window or posture change." `compute()` runs on every input change and calls `current()`, which fetches whenever the last fetch is over an hour old. So a window tweak 61 minutes into a session replaces the curve under the user, and the number changes for a reason they cannot see. The plan's own S8 promise ("two calls 30 min apart → one call") is true and does not cover this.
CONSEQUENCE: The design's S8 says "no fetch on window change"; the plan's S8 does not, so no blind test holds it. Visible only as a number that moves on its own.
THE FIX (internals; one contract line in calculator-ui):
```text
compute(): curve = (await env.forecast.cached())?.curve ; if curve == nil || foregroundedSinceLastFetch || moved > fetchMoveKm → fr = await env.forecast.current(…)
AppEnvironment: scenePhase .active → forecast.current(for: lastCoord, now)   // the foreground trigger R1 names
// Promise: "changing window or posture between two compute() calls never invokes the provider"
```

### 19. The SPF ladder cannot produce use case 3's "SPF 30"; the solver hardcodes the density it is supposed to read from Tunables; the alternative ignores what the user said they can manage

POSTURE: 2, 3 — arithmetic
SILENCE RANK: 19
WHERE: `core-engine.md` Slice 4 Internals: `SunscreenSolver.outcome: labels = [15, 20, 30, 50]; attenuation = raw/target; pick first label with pow(label, 0.5) ≥ attenuation`; `alternative(have): eff = have.effectiveSPF; if pow(label, 1.0) [thick] ≥ attenuation → .alternativeThickEnough with .thick`. Tunables: `densityDefault: Double // 1.0 mg/cm²`.
THE FLAW: Normal-application effectives are 15 → 3.87, 20 → 4.47, 30 → 5.48, 50 → 7.07. Use case 3 says "about four times the minutes" (attenuation ≈ uvaMultiple ≈ 4 on the flat beach curve) and "SPF 30" — the ladder returns SPF 20 for any attenuation ≤ 4.47, and "the best 40 minutes per side" (80 of 180 minutes) implies attenuation 2.25 → SPF 15. The fixture author will have to pick a curve that contradicts one of the use case's three numbers. `pow(label, 0.5)` and `pow(label, 1.0)` are literals: `densityDefault` is declared, provenance-tracked, and never read — S1's "the declared constant set of every outcome equals the constants its tests observe being read" cannot see a constant that is never read. `alternative` suggests thick application whenever thick would suffice, whether or not `have.application` was `.thick` — the user who said "SPF 15, normal only" is told to apply thickly.
CONSEQUENCE: S18 use case 3 mismatch is loud at fixture-writing time and gets resolved by editing the fixture. The hardcoded density is silent until the owner tunes `densityDefault` and nothing moves.
THE FIX (internals):
```text
outcome: effective(label) = pow(Double(label), densityDefault / 2); pick the lowest label with effective ≥ attenuation
alternative(have): if have.effectiveSPF ≥ attenuation → covered whole window with `have` (.alternativeThickEnough only when have.application == .thick)
                   else coveredMinutes = longest prefix with sed(w.start, t)/have.effectiveSPF ≤ remaining; shade for the rest; cover H&S
// Owner: use case 3's "SPF 30 / four times / 40 min per side" cannot all hold on this ladder; the fixture should assert the ladder's answer for its curve and the design text be reconciled.
```

### 20. Types the contracts use but never declare, one of which is the export format

POSTURE: 5 (slice seams), 1
SILENCE RANK: 20
WHERE: `core-engine.md` Slice 3: `public var curveUsed: StoredCurve // hourly UVI + solar noon for the day (R22)` — `StoredCurve` is defined nowhere. `calculator-ui.md` Slice 3: `curveUsed: curve.dayCurve(window.day)` — `dayCurve` is on no signature. `data-layer.md` Slice 3: `reproduce: curve = ForecastCurve(from: s.curveUsed)` — no such init. Slice 2: `Figure { key: FigureKey; value; unit: Unit; … }` — `FigureKey` and `Unit` undeclared. Slice 2 Internals: `→ add rednessReportCount` to `DerivedState`, absent from its Signatures. Slice 1: `posture: PostureFractions` undeclared. Slice 2 Signatures `var copyKey: CopyKey` and Slice 3 `sunscreen: SunscreenChoice?` use types declared only in Slice 4.
THE FLAW: `StoredCurve` is serialised into every `SessionRecord`, exported in `ExportFile` (`formatVersion 1`), and is what `reproduce` re-plans from. Its shape — samples for the day only? which "day" when the window is 23:00–00:30? does it carry the time zone (finding 12)? — is picked by whichever coder gets there first and frozen into an external format. `DerivedState` is `Codable` and part of nothing external, but a field the tests cannot construct means the "upper edge narrows only with redness reports" promise is tested only through `apply`. The Slice 2/3 forward references force each slice's coder to stub `CopyKey`/`SunscreenChoice` and Slice 4's coder to replace the stubs — file-list drift the review gate will flag on every PR.
CONSEQUENCE: Mostly loud (compile), except `StoredCurve`'s shape, which compiles under any definition and then cannot change without a `formatVersion` bump.
THE FIX (structural — declares a type that is an external format; moves two declarations):
```text
// core-engine Slice 1 Signatures
public struct StoredCurve: Codable, Sendable, Equatable { public let hourly: [HourlyUVI] /* every sample from the day's 00:00 to the next day's 06:00 in curve.timeZone */; public let solarNoon: Date; public let timeZoneID: String
    public init(_ curve: ForecastCurve, day: DayKey) ; public func curve(location:, fetchedAt:) throws -> ForecastCurve }
public struct PostureFractions: Codable, Sendable { public let frontBackFraction: Double; public let shoulderFraction: Double }
public enum FigureKey: String, Codable, Sendable, CaseIterable { case headlineMinutes, sideMinutes, regionDose, remainingBudget, cycleDose, rangeLower, rangeUpper, uvaMultiple, shortfall }
public enum Unit: Sendable, Equatable { case minutes, sed, multiple }
// DerivedState gains `public var rednessReportCount: Int`
// SunscreenChoice, Application and CopyKey move to Slice 1's Models (Slice 4 keeps SunscreenSolver and the outcome types)
```

### 21. Onboarding (M3) needs Learn's `ModuleIndex` and `ModuleView` (M4)

POSTURE: 5 (slice seam between plans)
SILENCE RANK: 21
WHERE: `calculator-ui.md` Slice 2 Internals: `OnboardingFlow: @State page; ModuleView(module 1) page with a single continue`; promise `Module 1 text equals ModuleIndex.module(1).markdown`. Slice 3: "links into Learn" and `App/RootTabs … handles icarus:// URLs`. `learn-tab.md` (M4) declares `ModuleIndex`, `ModuleView`, `DeepLink`.
THE FLAW: The milestone order M1 → M2 → M3 → M4 has M3 consuming three M4 symbols. A coder blocked on a missing `ModuleView` has one green path: put Module 1's text in an onboarding view — the exact V5/R34 violation the content package exists to prevent — and the S11 literal grep is not in place until this very slice.
CONSEQUENCE: Loud if the coder waits; silent if the coder inlines. The second is the likelier under a "get green" incentive.
THE FIX (ordering; not structural): build `learn-tab` Slice 1 (content only, no UI) before `calculator-ui` Slice 2, or move `ModuleIndex`/`LearnModule`/`Citation` into `calculator-ui` Slice 1's IcarusContent work and leave `learn-tab` with the views. Record the dependency in both plans' `Delivers`.

### 22. Provenance labels that do not say what the plan claims

POSTURE: 2 (silent failure of V12)
SILENCE RANK: 22
WHERE: `core-engine.md` Slice 1 Signatures: `decayHalfLifeDays: Double // 21.0 citation Module 6 (fast end)`; Slice 4 Internals: `range figure (reads uncertaintyBandAtZero → assumption? NO: cite Module 11 → citation)`.
THE FLAW: Module 6 says adaptation fades "over roughly four to eight weeks", not the 3–4-week range the design and plan cite; a half-life of 21 days is a modelling choice on top of a fade time, and the honest label is `assumption` with the Module 6 range named as the basis. The 30% line lives in Module 4 ("Two people who both count as type II can differ by 30% or more"), not Module 11, and the pseudocode's comment reads as choosing the label to keep the estimate badge off the range figure. S1 checks that every entry *carries* a citation, not that the citation supports the number, so both pass.
CONSEQUENCE: V12's "a note beside the number is" a basis only if the note is true. A reader who follows the citation finds it does not say that.
THE FIX (internals):
```text
decayHalfLifeDays: 21.0  assumption — Module 6 gives a 4–8 week fade; a 3-week half-life sits at the fast end so escalation after a gap errs shorter (V2)
uncertaintyBandAtZero: 0.30  citation Module 4 ("differ by 30% or more"); the range figure reads it and is therefore NOT an estimate — say so in the reads set, not by relabelling
```

### 23. View-level promises with no seam a blind test can reach; half of S15 has no script

POSTURE: 4 (untestable promises)
SILENCE RANK: 23
WHERE: `calculator-ui.md` Slice 2: "flow cannot complete without disclaimer acknowledged and a skin type"; Slice 3: "entry view has no Figure … 'change place' reachable from the result's place line"; `learn-tab.md` Slice 2: "ModuleView for module 4 renders a table (MarkdownUI Table node present); ModuleView contains no banner slot"; `history.md` Slice 1: "HistoryView contains no banner slot". `release-readiness.md` Slice 1: `acceptance/S15-ads.sh: swift test --filter IcarusAdsTests + grep for GoogleMobileAds imports`.
THE FLAW: These are assertions about rendered SwiftUI trees. With XCTest and no introspection library (none is approved under the dependency rule) the blind test-writer cannot hold them; MarkdownUI exposes no block AST publicly. S15's "the result, flip timer, onboarding, prompt, History, and Settings views contain no banner slot; the Calculator entry and Learn list contain exactly one and the entry view contains no figure" is a scripted (unmarked) criterion, and the only script named runs ad tests and an import grep.
CONSEQUENCE: The tenets V14 (no ad next to a number) and R39 (entry holds inputs only) are checked by nothing; the tests that exist will be written as "the view initialises". Silent by design.
THE FIX (contract; not structural):
```text
// Every screen declares its slots statically, and a script reads the declarations:
public protocol ScreenManifest { static var hasBannerSlot: Bool { get }; static var showsFigures: Bool { get } }   // each View conforms; a compile-time constant per screen
acceptance/S15-ads.sh: swift test --filter ScreenManifestTests   // asserts the table: {CalculatorEntryView: (true,false), LearnListView: (true,false), everything else: (false, _)}
                       + grep: `FigureView(` must not appear in Sources/IcarusUI/Calculator/CalculatorEntryView.swift or Prompts/
// Onboarding/quiz promises move to OnboardingModel (a @MainActor ObservableObject with canComplete: Bool) and are tested there.
```

### 24. `ForecastResult.none(ProviderError?)` swallows the reason the curve was rejected

POSTURE: 2 (silent failure)
SILENCE RANK: 24
WHERE: `data-layer.md` Slice 1 Internals: `curve = try ForecastCurve(location, fetchedAt: now, hourly: p.hourly, solarNoon: p.solarNoon) … catch { if let c → .cached(c.curve, .offline) else .none(error as? ProviderError) }`, and `c = cache.load()` with `load() throws` inside a non-throwing `current`.
THE FLAW: A provider that returns one sample or unsorted samples throws `ForecastCurve`'s `.tooFewSamples/.unsorted`, which is not a `ProviderError`, so the result is `.none(nil)` — "no forecast, no reason" — or, with a stale cache present, `.cached(_, .offline)`, which tells the user they are offline when they are not. A corrupt cache file (`load()` throws) has to be `try?`-ed to fit the signature and is indistinguishable from "no cache".
CONSEQUENCE: The promise "provider failing → .cached(.offline) if a cache exists, else .none(error)" passes with a fake that throws `ProviderError`. The malformed-response path reaches the owner as a `.missingForecast` outcome with no diagnostic, on the first live WeatherKit fetch (S8 owner part), where a diagnostic is the whole point.
THE FIX (contract):
```text
public enum ForecastFailure: Error, Sendable, Equatable { case provider(ProviderError), malformed(ForecastCurveError), cacheUnreadable(String) }
public enum ForecastResult { case fresh(ForecastCurve), cached(ForecastCurve, reason: CacheReason), none(ForecastFailure) }
public enum CacheReason { case withinInterval, providerFailed(ForecastFailure) }   // "offline" is one of several reasons; name the real one
```

### 25. The S11 literal grep will be eroded into an allowlist

POSTURE: 2
SILENCE RANK: 25
WHERE: `calculator-ui.md` Slice 1 Internals: `acceptance/S11-static.sh: grep for Text(" / "..." literals in Sources/IcarusUI (allowlist: system image names, accessibility ids)`.
THE FLAW: SwiftUI code is full of legitimate string literals — `Image(systemName:)`, `accessibilityIdentifier`, format strings, URL schemes, `Bundle` resource names, `#Preview` names. A grep for `"…"` fails on day one; the fix will be a growing allowlist, and an allowlist is where a copy literal hides. The check runs on every PR (acceptance-criteria), so the erosion is continuous.
CONSEQUENCE: The check is either red permanently or quietly hollowed. Both end with a literal in a view that no gate sees.
THE FIX (internals):
```text
S11: match only copy-bearing call sites — Text(" , Label(" , Button(" , .navigationTitle(" , .alert(" , .confirmationDialog(" , Section(" , accessibilityLabel(" , accessibilityHint(" — with a string literal as the first argument; no allowlist. Everything else is not copy.
```

### 26. The Learn `[VERIFY]` sidecar is a second artifact for information the source already carries

POSTURE: 1 (wrong shape)
SILENCE RANK: 26
WHERE: `learn-tab.md` Slice 1 Internals: `scripts/split-learn-content.sh: … remove [VERIFY] tokens` and `needsVerification if the line had [VERIFY] in the SOURCE (the script records a sidecar module-NN.verify.json listing citation indexes before stripping)`; Files list names `module-01.md … module-12.md` only.
THE FLAW: The sidecars are not in the file list, so S7's "regenerate and diff" either ignores them or the coder omits them; without a sidecar the parser has no marker and `needsVerification` is silently `false` for every citation — the flag S13 depends on. Stripping at generation and re-deriving at load is two mechanisms for one bit.
CONSEQUENCE: Silent: the flag is not rendered, so nothing shows; S13 (owner) is done by hand from the source, not from the flag.
THE FIX (internals): the split script only splits; module files keep `[VERIFY]` verbatim; `LearnModule` strips it at load (`LearnSource.normalise` already exists) and sets `needsVerification` from the presence it just stripped. No sidecar.

### 27. "Memoize on first call" in a `let`-only `Sendable` value type

POSTURE: 1 (shape picked by default)
SILENCE RANK: 27
WHERE: `core-engine.md` Slice 1 Internals: `sed(from a, to b): … // cache: memoize prefix integral at minute resolution on first call (prefix[i] = sed(start, start+i min))`, on `public struct ForecastCurve: Codable, Sendable { public let … }`.
THE FLAW: A struct with `let` fields cannot memoize on first call; under strict concurrency a reference cache inside a `Sendable` struct needs a lock and `@unchecked`, and `Codable` will try to encode it. The coder either builds the prefix in `init` (right: O(14 400) doubles, excluded from `CodingKeys`) or drops the cache and lets S14 catch the cost — or keeps it and lets the forecast cache file grow tenfold silently.
CONSEQUENCE: S14 catches the missing cache loudly; an encoded cache is silent bloat.
THE FIX (internals): `init` computes `prefixSED: [Double]` at minute resolution from `hourly.first.time`; explicit `CodingKeys` exclude it; `sed(a, b) = interp(prefix, b) − interp(prefix, a)`.

### 28. A Linux history store no gate ever runs

POSTURE: 1
SILENCE RANK: 28
WHERE: `data-layer.md` Slice 3 Internals: `#if canImport(SwiftData) — on Linux the Data target compiles the protocol surface and an in-memory JSON-backed store used by tests there`; `core-engine.md` Slice 1 Internals: `core-tests … swift test --filter 'IcarusCoreTests|IcarusContentTests'`.
THE FLAW: The Linux CI job filters out `IcarusDataTests`, so the JSON store is a second implementation of the store's logic that compiles on a runner where nothing calls it. Two implementations of "replayed state, memoised until the next write" will drift.
CONSEQUENCE: Dead code that reads as live; a future agent "fixes" the wrong one.
THE FIX (internals): one `HistoryStore` actor over a `HistoryPersistence` protocol (`SwiftDataPersistence` under `canImport`, `MemoryPersistence` everywhere); `inMemory()` returns the actor over `MemoryPersistence` on every platform; add `IcarusDataTests` to the Linux filter or delete the Linux path.

### 29. The 21.4-minute promise fails on the minute grid the internals prescribe

POSTURE: 3 (drift) — arithmetic
SILENCE RANK: 29
WHERE: `core-engine.md` Slice 1 Signatures: `type II, m=1.0, standard, UVI 7 steady → bestSubWindow.minutes ≈ 21.4 (target 2.25 SED → 150 UVI·min → 21.4 min; tolerance ±0.5)`; Internals: `// two-pointer on the minute grid: for each start minute, advance end until sed ≥ target`.
THE FLAW: 2.25 SED × 66.7 / 7 = 21.44 minutes. On a one-minute grid the shortest block delivering ≥ 2.25 SED is 22 minutes (21 minutes gives 2.204 SED). |22 − 21.4| = 0.6 > 0.5. The contract's own arithmetic is right; the internals' grid cannot return it.
CONSEQUENCE: Fails at assembly — loud — and the cheapest repair is widening the tolerance to ±1, which then hides a one-minute error everywhere. (S1 says "about 21 minutes"; this is the plan's tightening.)
THE FIX (internals): the end of the block is interpolated within the last minute: `d = (k − 1) + (target − prefix[k−1]) / (prefix[k] − prefix[k−1])` minutes; the promise stays ±0.5 and headline minutes are shown rounded.

### 30. The S4 "one week under 25% of the cap rise" is unreachable for any τ

POSTURE: 4 (a promise no implementation of F3 can hold) — arithmetic
SILENCE RANK: 30
WHERE: `core-engine.md` Slice 3 Signatures: `6 weeks × 5/wk at standard (type II): … 1-week factor rise < 25% of cap rise`, alongside the F3 constraint `21 daily sessions at doseFraction 1.0 land at tanState 0.8`.
THE FLAW: A single-exponential rise that reaches 0.8 in 21 sessions is at 1 − 0.2^(5/21) = 0.318 after five, whatever τ; with gain 1.25 that is a factor rise of 0.40 = 32% of the 1.25 cap rise (30% with the decay, at τ = 13; 48% at the τ ≈ 7 that actually satisfies F3 with decay). "Eventual cap" read as the saturation actually reached makes it worse (45%). The two promises contradict each other under D-F3's closed form.
CONSEQUENCE: Loud at assembly; the repair will be to loosen one bound. Better to pick now which one the design means.
THE FIX (contract line; not structural): replace with a bound the recurrence satisfies — `1-week factor rise < 40% of cap rise` — or, if "25%" is the intent, change the rise shape (a two-parameter sigmoid) which is a design change and a second ruling on F3. State the choice in the promise.

### 31. Two loud seams on M1's first pull request

POSTURE: 5
SILENCE RANK: 31
WHERE: `core-engine.md` Slice 1 Internals: `macOS test keeps xcodebuild test (app + UI/Data tests); test-the-tests unchanged` with `project.yml … ProjectIcarusTests sources [Tests/AppTests]`; `.github/scripts/test-the-tests.sh` runs `xcodebuild test -scheme ProjectIcarus`. Slice 2/3 forward references (finding 20).
THE FLAW: The scheme lists only `ProjectIcarusTests`; local-package test targets are not run by `xcodebuild test` unless the scheme names them (`schemes.ProjectIcarus.test.targets: [- package: Icarus/IcarusCoreTests, …]` in XcodeGen). With the package tests absent from the scheme, the macOS suite passes with Sources reverted and `test-the-tests` fails the first Core PR for a reason unrelated to the tests.
CONSEQUENCE: Loud, on the critical path, and easy to misread as a flaky gate.
THE FIX (internals): `project.yml: schemes.ProjectIcarus.test.targets: [ProjectIcarusTests, {package: Icarus/IcarusCoreTests}, {package: Icarus/IcarusDataTests}, {package: Icarus/IcarusContentTests}, {package: Icarus/IcarusUITests}]`; `Package.swift` declares `resources: [.copy("Resources")]` for IcarusContent and the Data fixtures so `Bundle.module` exists.

### 32. File collisions and an estimate that hides three slices

POSTURE: 5
SILENCE RANK: 32
WHERE: `calculator-ui.md` Slice 4 Files and `release-readiness.md` Slice 2 Files both own `Sources/IcarusUI/Settings/AttributionView.swift`. `core-engine.md` Slice 4 (~700 lines) owns `SunscreenSolver`, `Planner`, `DoseResult`, `CopyKey` (30+ cases), four test files, `PerformanceTests`, `acceptance/S18-usecases.sh` and eight use-case fixtures each with its own forecast series, history and expectations. `logging-calibration.md` Slices 1–3, `history.md` Slice 2, `calculator-ui.md` Slice 4 reference copy keys (`.immediateDarkeningExplained`, `.revisitSkinType`, `.pauseSuggested`, `.sensitivitySentence`, `.deleteHistoryWarning`, `.trajectoryTitle`) absent from Core's `CopyKey` list, and none of those slices lists `Sources/IcarusCore/Models/CopyKey.swift` or `docs/APP_COPY.md` (owner-approved under S17 "before M3 begins") in Files.
THE FLAW: The attribution view is built twice. Slice 4 of Core is three deliverables (sunscreen; planner and outcomes; fixtures and performance) under one tripwire, so the overrun will be large and unattributable. Every later plan quietly adds enum cases in Core and copy lines in an owner-approved document, and the plan's Files lists do not say so — the review gate will flag scope on each, or the owner approves copy after the fact.
CONSEQUENCE: CI reports the overrun (loud); the copy-ownership drift is silent until the review gate blocks an M5 PR for touching Core.
THE FIX (slice boundaries — flagged structural only in that it changes a Files list): drop `AttributionView.swift` from release Slice 2 (it is built in M3; M2 of release adds the entitlement and links). Split core Slice 4 into 4a `SunscreenSolver` (+tests) and 4b `Planner`/`DoseResult`/`CopyKey`/fixtures/perf. Give `CopyKey` its complete case list in Core Slice 1 (every key any plan names) and add `docs/APP_COPY.md` + `CopyKey.swift` to the Files of every later slice that adds a key, with the S17 owner cost repeated in those plans' headers.

---

## Closed angles — attacks the pseudocode survives

- S3 weights: `weight(0,·) = 1.0`, `weight(15, burn) = 0.286`, `weight(100, burn) = 0.222 ≥ 0.11`, non-burn floor at nCap = 0.111 — all reproduce from `min(1, (burn ? 2 : 1) × k / (min(n, nCap) + k))`.
- S3 outliers at report 15 for true m = 0.75: a forced "red and sore" moves −0.145 (inside −0.10…−0.20); a "normal" at ratio 0.9 moves 0 — both hold with the internals as written.
- SPF density points 50/7.07/2.66 and "attenuation 8 → nothingRealistic" reproduce; "30 normal over 50 thin" holds trivially because thin is never solved for.
- The S4 gap: after six weeks at 5/wk (τ = 13) a 28-day gap drops the factor from 1.80 to 1.32, a 26.8% dose reduction — clears the 25% bar (thinly) and the 10% `.dropped` notice comfortably; the message is factor-based so it is window-independent as promised.
- The F2 scalar shrink is monotone in `s` (both doses grow with duration), so bisection is sound once the sides are consecutive (finding 3 fixes the precondition, not the method).
- `clip` and the from-now solve (use case 9): `clip(window, now)` → nil for a passed window, shortened otherwise; consistent across Slices 1, 2 and 4.
- Stale levels: 3 h → headsUp, 6 h or > 25 km or unknown location → warn with ×1.5 range and −5% target — consistent with R3 and use case 9; a manual place passes as the device coordinate so a manual user is not permanently "far".
- Cache cadence: within the hour and within 10 km → no provider call; a 10.1 km move or `force` → a call; provider failure with a cache → the cache. Holds as specified (the R1 trigger question is finding 18, not the cadence).
- `TanningGoal.effectiveScale`: conservative until 3 reports, aggressive refused without 5 reports and a redness bound in the current cycle; a new cycle (per region, after a 14-day gap) re-locks aggressive — consistent with V15 and decision 20.
- `target ≤ medPersonal` for every type and setting: `min(mel, med) × scale ≤ med` with scale ≤ 1.0; the range's upper edge is clipped at `med` and flagged.
- Type IV vs II at m = 1: IV binds melanogenic (0.75 × 4.5 × 0.9 = 3.04 SED, 0.675 MED) below II's 0.9 MED; boundBy comes out `.melanogenic` for IV and `.burnLine` for II.
- Q2 reclassification (`faintPink` + `withinHourGoneByEvening` → `.normal`, `.reclassifiedAsNormal`) sits before the branch, so it also skips the redness bound — correct.
- The per-region tan cycle and the "bound from a previous cycle does not count" rule: `decayed` clears `rednessBoundInCycle` when a region's own gap exceeds 14 days; the plateau test's construction cannot cheat it.
- Export determinism: `JSONEncoder` with iso8601 dates and sorted keys; `formatVersion` refused when newer.
- Learn deep links and `ModuleID(13) == nil`; the Sources blockquote kept in `markdown` for S7 and replaced by `CitationRow`s at render time — the two promises do not conflict.
- `reapplyAt` non-empty iff the window exceeds 2 h: `start + 2h < end` gives exactly that at the boundary.
- Replay ignoring `factorsShown`/`targetsShown` (R44) — honoured everywhere; History shows them as "what you were shown" only.
- Header caps, `Rulings:` receipts and the Signatures/Internals split: every plan passes `plan-format.sh` and `plan-parse.sh` as they stand (checked by reading the scripts, not by running them — the container has no CI).
