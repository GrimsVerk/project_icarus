# Implementation check 1 — did design revision 2 land what it claims?

Checked: `docs/DESIGN.md` and `docs/VISION.md` as of commit `dd8a06d` ("Design
revision 2"), against `docs/reviews/design/conceptual-reconciled.md` (A1–A18,
B1–B14, C1–C7), the two source reports, and the owner's rulings in the last
entry of `docs/DECISIONS.md`. Read-only; nothing in the design or vision was
changed. `conceptual-3.md` was neither read nor waited for.

Statuses: IMPLEMENTED / PARTIAL / MISSING / CONTRADICTED / SUPERSEDED, as
defined in the brief. Where the owner's ruling differs from a reviewer's fix,
the ruling is the reference. Quotes are from the current text.

## A. Found by both reviewers

| id | finding | status | evidence (current text) | what is missing |
|---|---|---|---|---|
| A1 | "Normal" is a point estimate; S3 reporter unspecified | IMPLEMENTED | R21: "A 'normal' report is one-sided evidence: it asserts only that the threshold lies above the delivered dose. It moves the multiplier upward only when the delivered dose was at or above the current estimated threshold for that region (dose ratio ≥ 1.0), and then to an implied threshold equal to the delivered dose, never higher; at or below the target it is a confirmation and changes nothing." S3: "the simulated reporter answers Q1 from the true dose-to-threshold ratio with bands normal < 0.95, faint pink 0.95–1.15, clearly pink 1.15–2.0, red and sore 2.0–4.0, blistered ≥ 4.0, and the bands live in Tunables beside the implied-ratio table … a user at true multiplier 1.0 reporting truthfully at the standard ceiling for 20 logs moves by no more than 0.05." | — (but see Cross-cutting (c) item 3: R21's new B1 sentence forks against this one) |
| A2 | One target fraction for all types; no melanogenic threshold | SUPERSEDED | Ruling: "Target per skin type is a formula, not a table. `targetDose = min(MED × melanogenicFraction(type), MED × ceiling)`; fractions … I–II 1.0, III 0.95, IV–VI 0.75". R6: "`melanogenicDose = MED_personal × melanogenicFraction(skinType)`; `targetDose = min(melanogenicDose, MED_personal × ceiling)` … types I–II 1.0 …, type III 0.95, types IV–VI 0.75 … `ceiling` is set by the Settings selector: conservative 0.75, standard 0.90, aggressive 1.0". R17: "shortfall from the melanogenic dose". S1: "a type IV at multiplier 1.0 is planned materially shorter, as a fraction of MED, than a type II, and the melanogenic dose is what bound it". | Reviewer's per-type selector table was replaced by the owner's min-formula; text follows the ruling. See (c) item 1 for a claim in R6 the numbers do not deliver for type III. |
| A3 | Seasonal total pushed to M6 | IMPLEMENTED | R13: "shows the limiting region's season-to-date cumulative dose in SED beside the message in the same type size as the recommendation". R24: "Weekly and seasonal totals per region ship with M5; the chart with M6." §12 M3: "escalation message with season total". S6: "an escalated result carries the cumulative-dose figure". | — |
| A4 | MEGA-FORK: what makes a session real | IMPLEMENTED | R45: "A `Session` is created as *planned* when a result is shown and becomes *logged* only by a user action: starting the flip timer, tapping 'I did this' on the result, or answering 'yes' to the skin-check prompt's opening question … Only logged sessions count toward today's dose, tanState, and History; a planned session never logged is discarded at local midnight. A skin report adjusts the multiplier; logging is what advances tanState." R12 defines effective dose "as a fraction of that region's personal threshold at the time". R11: "Starting it starts the session at the actual clock time and recomputes the per-side times from that start on the cached curve." | — (see (c) item 6: the third logging path in R45 cannot fire under R20) |
| A5 | MEGA-FORK: UV horizon behind "next viable window" / "this season" | IMPLEMENTED | Ruling: "Forecast horizon = whatever WeatherKit forecasts, `forecastHorizonDays` default 10". R1: "for the provider's full horizon (`forecastHorizonDays`, default 10, tunable to match what WeatherKit actually returns)". R17: "A window is viable when it can deliver at least a tunable fraction (default 0.5) of the target. 'Next viable window' is searched across the cached horizon only. 'No viable window' is the outcome when no hour in the horizon reaches viability; its copy says 'not in the next N days', names the horizon's peak UVI, and never claims a season." §3: "The app never says 'this season'." §11: "The actual horizon WeatherKit returns is confirmed then and `forecastHorizonDays` set to match." | — |
| A6 | V2 vs R7; uncertainty never acted on | IMPLEMENTED | R7: "Until the calibration count is reached (`calibrationLogs`, default 3) the number is computed at the conservative ceiling whatever the selector says, and the copy says 'shorter until the app has learned your skin' … Its lower edge narrows with any report; its upper edge narrows only with redness reports". V2: "When two defensible numbers differ, the shorter session is the one shown, and the result names the uncertainty that made it shorter. 'Says why' means the number moved, not that a range was drawn beside it. This bounds V1: escalation that could be either right or early is late." | — |
| A7 | Two skin checks about one skin | IMPLEMENTED | R20: "One skin-check prompt per day that had sessions, about 20 hours (tunable) after the day's last logged session … Its evidence is the day's summed dose per region and the adaptation factors in force that day, and it counts as one log." S10: "a day with two logged sessions schedules one skin-check prompt after the last". | — |
| A8 | Sunscreen route hides UVA cost; headline on overshoot | PARTIAL | R15: "the headline is the bare-skin sub-window per region … The sunscreen answer always states that the same tanning dose over N times the minutes carries roughly N times the UVA, names N, notes that the product filters UVB more than UVA unless it carries a UVA rating, names the reapplication times when the plan exceeds the reapplication interval (2 h, tunable), and links to Modules 3 and 8; the two answers are never presented as equivalent. The order is reversed only when the user has marked that they will stay out for the whole window." S2: "the sunscreen answer carries the UVA multiple with N computed and the reapplication times". | The reconciled ruling accepted "both" fixes; R1 #13's last clause — "the timer alerts at them [the reapplication times]" — did not land: R11's timer alerts only "at the first side's end and at the session's end". Add to R11 or R15: "When a logged session uses the sunscreen answer and exceeds the reapplication interval, the session clock alerts at each reapplication time." |
| A9 | Notification denied → loop never runs | IMPLEMENTED | R20: "If notification permission is denied, or a prompt goes unanswered, the skin check is asked in-app on the next launch between 12 and 72 hours after the day's sessions and the lasting-colour question between 3 and 10 days after; Settings shows how many session days have no report." R11: "If notification permission is denied it says, before starting, that it cannot alert with the screen locked." S10: "with notifications denied the questions are asked in-app within their windows". | — |
| A10 | Fetch cadence unstated | IMPLEMENTED | R1: "Fetch at most once per hour per location (tunable): on foreground, on a location change of more than 10 km (tunable), and on explicit refresh; never on window or posture change." R33: "At R1's fetch cadence the included WeatherKit tier covers on the order of ten thousand daily users; that is the point at which V6 needs revisiting." S8: "the fetch cadence holds (no fetch on window change, one within an hour, one after a 10 km move)". | — |
| A11 | Type I *and II* thin-margin line dropped to a use case | IMPLEMENTED | R43: "For skin types I and II every result states, in the same copy for both, that the margin between a tanning dose and a burn is thin and that deciding it is not worth it is a reasonable conclusion; the copy does not push either way. The copy key is present for types I and II and absent for III–VI. — Evidenced by: S6". S6: "the thin-margin copy key is present for types I and II and absent for III–VI". | — |
| A12 | Half-life at the midpoint; rise rate absent; IV–VI "faster" dropped | IMPLEMENTED | R12: "It rises as a leaky integrator of each region's effective dose … The rise time constant is in Tunables, set so that daily sessions at the standard target reach tanState 0.8 in about three weeks for types I–III and never faster than the two-to-three-week course in Module 6, with a type-dependent rise multiplier (default 1.5× for IV–VI). It decays toward zero with a half-life of 3.0 weeks (tunable), the fast end of the cited 3–4 week range". S4: "'regular sessions' means five sessions per week at the standard ceiling, stated in the acceptance script … escalation after one week is below 25% of the eventual cap". R30 lists "rise time constant and multipliers". | — |
| A13 | V7 decides nothing | IMPLEMENTED | V7: "Fewer controls over more options. The calculator asks exactly what the engine needs — window, posture, the cover toggle, a sunscreen choice, and whether the user stays the whole window — and nothing else. A choice the user would make once lives in Settings; a choice they would never make lives in Tunables; a Settings item that does not change a number the user acts on is not added." | — |
| A14 | V12's "trace" ambiguous; a Tunables entry is not a basis | IMPLEMENTED | V12: "an entry in the tunables file that carries its citation or the word `assumption` with a one-line rationale. 'Trace' means a reader of the repository: every figure on the result screen is reproducible from the JSON export and the tunables version it carries, and a result that depends on an `assumption` constant is labelled an estimate on screen. A file is not a basis; a note beside the number is." R30: "Every entry carries, beside it, either a citation into the Learn modules or the addendum, or the word `assumption` with a one-line rationale". | — |
| A15 | Entry screen may carry a number; History unassigned | IMPLEMENTED | R39: "The Calculator entry screen holds inputs only: no UVI, forecast age, budget, warning, or any figure the user could act on; every figure lives on the Result screen. Never on the result screen, the flip timer, onboarding, the skin-check or lasting-colour prompts, History, or Settings." V14: "it stays on the two entry screens, which carry no figure at all; it never appears on the result, the flip timer, onboarding, a skin-check prompt, History, or Settings." S15: "the entry view contains no figure". | — |
| A16 | Citations without DOI; `[VERIFY]` renders; V5 forbids S13's corrections | IMPLEMENTED | V5: "A citation may be corrected only so that it resolves to the paper it names — identifier, year, venue — never in wording, and every correction is listed in `docs/reviews/citations.md`." R26: "a citation without a DOI renders the identifier it carries (PMID, tappable via PubMed; ISO number; URL) or its text as given, and is never assigned an identifier the source does not carry and never omitted for lack of a link. `[VERIFY]` markers and the document's preamble above Module 1 are build annotations and are never rendered; S7's normalisation strips exactly those and whitespace." S13: "corrected only in identifier, year or venue where wrong". | — |
| A17 | Cover toggle: what dose is logged; "SPF 30+" is not a cover | IMPLEMENTED | R10 (R2's ruling): "a single toggle 'head and shoulders covered' means opaque cover, a hat or a shirt: that region is logged at zero dose and removed from the limit … Sunscreen is never a cover; sunscreen on the face is the session's sunscreen choice applied to that region through the R15 model." S5: "the cover toggle logs head-and-shoulders at zero and lifts the limit". | — |
| A18 | Budget warnings: 90% line fires every session; second session solved against what is left | PARTIAL | R19: "The recommendation is always solved against each region's remaining budget (target minus today's logged dose), so the headline number already accounts for earlier sessions. When the user's entered window exceeds that recommendation the result warns; when it would reach the region's personal threshold (target ÷ ceiling) it warns strongly in Module 7's burn language. Both lines are measured against the threshold, not the target, so the strong warning means redness is expected." Ruling: "plain past the target, strong (Module 7 language) only at the personal threshold." | The parenthetical "(target ÷ ceiling)" is wrong under the new R6: where the melanogenic dose binds (types III–VI), `target ÷ ceiling` is below `MED_personal` (type IV, standard: 3.375 ÷ 0.90 = 3.75 SED = 0.83 MED), so the Module 7 burn language would fire where redness is not expected — the exact fatigue the finding was about. Replace the parenthetical with: "(`MED_personal` as defined in R5, never derived from the target)". Also "Both lines are measured against the threshold" is loose: the plain line is at the target; say "the plain line is at the target and the strong line at the threshold". |

## B. Found by one reviewer, judged real

| id | finding | status | evidence (current text) | what is missing |
|---|---|---|---|---|
| B1 | Sensitivity/adaptation separation asserted, not learned | IMPLEMENTED | R21: "Evidence that the skin tolerated more than the model predicted is attributed to the region's tanState, which decays; evidence that the skin reacted at a lower dose than predicted is attributed to the multiplier, which persists; disagreement in the tolerant direction therefore cannot survive a gap." S3: "The separation simulation runs with the simulated user's true adaptation gain at 0.7× and at 1.3× the modelled gain; in both cases the multiplier stays within 0.10 of 1.0 after six weeks and the first post-gap recommendation is at or below the simulated user's true threshold." §8 decision 5. | — (but see (c) item 3: this sentence and A1's sentence in the same R21 give two answers for a "normal" report at ratio ≥ 1.0) |
| B2 | All non-Learn copy unwritten and authored unattended | IMPLEMENTED | R42: "All non-Learn user-facing copy — … — is authored in `docs/APP_COPY.md` before M3 begins, rendered by IcarusContent exactly as the Learn modules are, and never appears as a literal in a view. The agent drafts it; the owner approves every line. — Evidenced by: S11, S17". S17 (owner): "Every string in `docs/APP_COPY.md` was written or approved by the owner, and the file exists before M3 begins." | — |
| B3 | MEGA-FORK: stored vs replayed state | IMPLEMENTED | R44: "Region states and the multiplier are derived, never authoritative. The ordered session and report history is the record. On launch and after every logged session or report, `AdaptationModel` and `CalibrationEngine` replay that history under the current Tunables to produce the current state, which is cached for display only. A Tunables change therefore takes effect for every existing user on next launch." R25: "The export is the full session and report history plus the Tunables version, and importing it reproduces the state." §9 `DerivedState` "(cache, never authoritative)". §7: "Nothing writes state directly." | — |
| B4 | No use case is a fixture | IMPLEMENTED | S18: "Each §4 use case is a fixture under `acceptance/`: a forecast series, profile, history, window, posture, and the expected outcome type, headline minutes within ±10%, per-region doses, and the copy keys named in the use case. M1 is not done until use cases 1–6, 8 and 9 pass; M5 adds 7." §4 preface: "Every use case below is also an acceptance fixture (S18)". | — |
| B5 | S3's 0.03 bound unachievable with k = 2.5 | IMPLEMENTED | S3: "one 'normal' outlier at log 15 moves the multiplier by at most 0.05 and one 'red and sore' report at log 15 moves it down by at least 0.10 and at most 0.20". R21: "the effective weight of any single update is capped at 1.0". (Checked: 2 × 2.5/17.5 × (0.36 − 1) = −0.18, inside the band.) | — |
| B6 | Ceiling message cannot tell "at maximum" from "under-dosed" | IMPLEMENTED | R14: "The ceiling outcome requires that at least one redness report in the current tan cycle has bounded the region's threshold from above … Without that bound the same signals produce the under-dosed outcome: the app has not yet seen the skin react, so it cannot tell whether the dose is too low or the skin is done, and the copy never asserts a pigment ceiling." S4: "without the bound it produces the under-dosed outcome and never the ceiling copy." | — |
| B7 | Cached forecast is for wherever the phone last had signal | IMPLEMENTED | R3: "or whenever the device is more than 25 km (tunable) from the cache's location or the location is unknown, the result warns that the data may be outdated, names the place the forecast is for". S6: "a cache 30 km away is stale at any age". | — |
| B8 | Head and shoulders receive no dose while lying down | IMPLEMENTED | R9: "head-and-shoulders is credited with the face-up dose in full plus a tunable fraction (default 0.5) of the back-side dose for the shoulders". R10: "In either posture, a single toggle". S5: "a lying-down session credits head-and-shoulders with the face-up dose and a following up-and-about session the same day is limited by that credit". | — |
| B9 | MEGA-FORK: one per-side figure vs per-region solved times | IMPLEMENTED | R9: "the front side and the back side are each solved per region against that region's threshold and remaining budget over the actual sub-interval that side will face the sun, so each side receives its target dose rather than an equal time … one 'X min per side' figure when the two sides differ by less than a tunable fraction (default 15%) and 'front X min, back Y min' otherwise; the total is the sum." R11: "alerts at the first side's end and at the session's end". S5: "the total equals twice the per-side time only when the regions are equal and the UVI is flat". | — (see (c) item 5: which side faces the sun first is unstated) |
| B10 | Q2 goes nowhere | IMPLEMENTED | R20 Q2 options: "'within an hour and gone by evening', 'that evening', 'the next morning', 'not sure'". R21: "Q2 reclassifies: redness that appeared within about an hour and had faded by evening is immediate pigment darkening, not erythema; the report is calibrated as 'normal' and the confirmation says so with a link to Module 2." S3: "a 'faint pink' report with the immediate-darkening Q2 answer moves the multiplier as 'normal' does." | — |
| B11 | "Realistic" sunscreen has no ceiling | IMPLEMENTED | R15: "'Realistic' means at most SPF 50 applied normally (about 7×); thick application is never solved for and is offered only as a choice the user can select, and when they do the result repeats Module 8's line that almost nobody achieves it." S2: "a required attenuation of 8 returns the shorten-the-window outcome". | — |
| B12 | At the ceiling: hold or drop to maintenance | IMPLEMENTED | R14: "stop escalating, drop the recommendation to a maintenance dose (`maintenanceFraction`, default 0.7 of the current target, tunable) … escalation resumes after a later 'yes' or 'a little'". S4: "drops to the maintenance dose with the ceiling message". | — |
| B13 | Six hours from fetch is the wrong clock; "non-confident" undefined | IMPLEMENTED | Ruling: "Stale data degrades, never refuses. Heads-up with the age at 3 h, warning at 6 h, range widened, recommendation reduced by `staleReduction` (5%, tunable)." R3: "At three hours (tunable) the result carries a heads-up naming the age. At six hours (tunable) … the result warns that the data may be outdated, names the place the forecast is for, widens the range by a tunable factor (default 1.5×), and reduces the recommendation by `staleReduction` (default 5%, tunable). A number is always shown; only a missing forecast shows none." §8 decision 23 records the bend of the build prompt. Use case 9 and S6 match. | — |
| B14 | Onboarding table vs Module 4; quiz has no source | IMPLEMENTED | R28: "The onboarding table is the app's own copy in IcarusContent, written to V13 and citing Fitzpatrick 1988; Module 4's table is Learn copy and stays verbatim under V5. The optional quiz is the Fitzpatrick skin-type questionnaire with its published scoring bands; questions, bands and citation live in IcarusContent." | — |

## C. Owner rulings (reconciled C1–C7 plus the extra rulings in DECISIONS.md)

| id | ruling | status | evidence (current text) | what is missing |
|---|---|---|---|---|
| C1 | Target bands per skin type → formula `min(MED × melanogenicFraction, MED × ceiling)`, fractions 1.0 / 0.95 / 0.75 | IMPLEMENTED | R6 (quoted under A2); §8 decision 19: "The target derives from two thresholds … The melanogenic fraction is static per band; exposure history lives only in the adaptation factor, so the two never compound." §11: "The melanogenic fractions for III–VI are the addendum's extrapolations and are labelled so." | — |
| C2 | Forecast horizon = WeatherKit's, default 10, confirmed on first live fetch; never "this season" | IMPLEMENTED | R1, R17, §3, §6 ("The forecast horizon is whatever WeatherKit actually forecasts. Nothing in the app reasons past it: no clear-sky model, no seasonal table, no claim about a season."), S8 (owner): "the horizon it returns is recorded in Tunables". | — |
| C3 | Stale forecast: degrade, not refuse | IMPLEMENTED | R3, §8 decision 23, use case 9 ("still gives a number"), S6. See B13. | — |
| C4 | App copy: agent drafts, owner approves every line; S17 owner criterion | IMPLEMENTED | R42: "The agent drafts it; the owner approves every line." S17 **(owner)**. §12 M3: "`docs/APP_COPY.md` approved (S17)". | — |
| C5 | Conservative until 3 logs, then the selected ceiling with its range | IMPLEMENTED | R7: "Until the calibration count is reached (`calibrationLogs`, default 3) the number is computed at the conservative ceiling whatever the selector says … after that the number sits at the selected ceiling." §8 decision 8. S6: "the number is at the conservative ceiling before three logs". | — |
| C6 | Derived state, not stored; history is the record | IMPLEMENTED | R44, R25, §8 decision 14, §9. See B3. | — |
| C7 | Warning lines: plain past the target, strong (Module 7) only at the personal threshold | PARTIAL | R19 as quoted under A18; §8 decision 9: "warn past the target, warn strongly only at the threshold, so the burn language means redness is expected". | Same defect as A18: R19 defines the threshold as "(target ÷ ceiling)", which is not `MED_personal` when the melanogenic dose binds; the strong line lands below the burn line for types III–VI. Fix as in A18. |
| X1 | Aggressive = at the line, never past it, unlocked after 5 logs with ≥ 1 redness report in the current cycle | IMPLEMENTED | R7: "The aggressive ceiling unlocks only after `aggressiveUnlockLogs` (default 5) logs of which at least one reported redness in the current tan cycle." R6: "aggressive 1.0 … `targetDose` never exceeds `MED_personal` for any type or setting: aggressive means at the line, never past it." V15: "Aggressive means at the line, never past it, and it unlocks only after the app has seen the user's skin react." S6: "the aggressive ceiling is refused before five logs with a redness report". §8 decision 20. | — ("current tan cycle" is undefined; see (c) item 4) |
| X2 | Never above MED for any type or setting | IMPLEMENTED | R6 as above; S1: "no setting produces a target above MED for any type"; V15: "No setting, no adaptation, and no calibration may plan a dose above the user's personal threshold." | — |
| X3 | Build prompt MED baselines (III 3.0, IV 4.5) authoritative; addendum's 3.5 / 5.0 never used | IMPLEMENTED | R5: "Baselines, in SED: I 2.0, II 2.5, III 3.0, IV 4.5, V 6.0, VI 10.0. **These are the build prompt's baselines and they are authoritative.** `docs/MELANOGENIC_THRESHOLDS.md` computed its reference table from a different set (III 3.5, IV 5.0); that set is not used anywhere in this project, and no agent may substitute it." §6: "The MED baselines are the build prompt's (R5). The addendum's alternative set is reference material only." | — |
| X4 | Derived state with a delete warning | IMPLEMENTED | R44: "Deleting the history is offered in Settings behind a warning that says plainly the app will start over from the skin-type prior: calibration, tan state, budgets, and History are all lost, and the export is the only way to keep them." S10: "deleting the history shows the warning and resets to the prior". R42 lists "the delete-data warning" as app copy. | — |
| X5 | Warning lines (restated ruling) | PARTIAL | As C7. | As C7. |
| X6 | Stale handling: 3 h heads-up / 6 h warning / range widened / `staleReduction` 5% | IMPLEMENTED | R3 as quoted under B13; R30 lists "staleness limits and reduction"; S6: "a forecast at three hours carries the heads-up, at six hours the warning, the widened range and the stale reduction"; use case 9: "at three hours it shows the age; past six hours it warns that the data may be outdated, widens the range, trims the recommendation by the stale reduction, and still gives a number." | — |

## Cross-cutting

### (a) Requirement ids vs §13 covers lists

Checked mechanically over the current `docs/DESIGN.md`. §5 declares 45 ids
(R1–R45, none renumbered). The eighteen covers lists (S1–S18) name only ids
that exist, and every one of the 45 is named at least once: R1 (S8), R2 (S8),
R3 (S6), R4 (S1), R5 (S4), R6 (S1, S18), R7 (S6), R8 (S5), R9 (S5, S18), R10
(S5), R11 (S9), R12 (S4), R13 (S4, S6, S18), R14 (S4), R15 (S2, S6, S18), R16
(S6), R17 (S6), R18 (S6), R19 (S5, S18), R20 (S10), R21 (S3, S18), R22 (S3),
R23 (S10), R24 (S10), R25 (S10), R26 (S7, S13), R27 (S7), R28 (S9), R29 (S9),
R30 (S1), R31 (S9), R32 (S11), R33 (S12), R34 (S11), R35 (S9), R36 (S9), R37
(S8), R38 (S14), R39 (S15, S16), R40 (S15), R41 (S15, S16), R42 (S11, S17),
R43 (S6), R44 (S10), R45 (S5, S10, S18). Every requirement's "Evidenced by"
list agrees with the criteria's covers lists. **Clean.**

### (b) The criteria the reviews called circular or unspecified

- **S3's response model** — pinned. The reporter's bands (normal < 0.95, faint
  pink 0.95–1.15, clearly pink 1.15–2.0, red and sore 2.0–4.0, blistered ≥ 4.0)
  are in S3 itself and are to live "in Tunables beside the implied-ratio
  table"; the truthful-reporter bound ("20 logs moves by no more than 0.05")
  and the separation gains (0.7× and 1.3×) are numeric. A script can be written
  from S3 plus R21 alone. One caveat carried into (c) item 3: R21 now contains
  two rules for the same "normal at ratio ≥ 1.0" event, and the script's
  expected value differs by which one the engine implements.
- **S4's "regular sessions" and rise rate** — pinned. S4: "five sessions per
  week at the standard ceiling, stated in the acceptance script"; R12 fixes the
  rise by outcome ("daily sessions at the standard target reach tanState 0.8
  in about three weeks for types I–III"), the 1.5× IV–VI multiplier, and the
  3.0-week half-life; S4 adds the one-week bound ("below 25% of the eventual
  cap"). Checked: at half-life 3.0 a four-week gap leaves 0.40 of tanState, so
  from a saturated I–III factor of 2.25 the post-gap factor is about 1.50 and
  the session is about 33% shorter — the "at least 25%" clause is reachable
  and no longer depends on an unstated constant. S4 does not name the skin type
  it runs; the script must pick one (I–III is implied by R12's constant).
- **S5's per-side arithmetic** — pinned in dose terms ("each region with its
  own target dose over its own sub-interval … twice the per-side time only when
  the regions are equal and the UVI is flat … two figures past the 15%
  difference"). One input a script needs is still absent from S5 and R9: which
  side faces the sun first (see (c) item 5). Use case 2 assumes an order ("the
  second side gets a few minutes more") without saying which side it is.

### (c) New gaps introduced by the revision

1. **R6 claims a binding the numbers do not deliver for type III.** R6: "for
   types III–VI the melanogenic dose binds, so they get a genuine no-redness
   protocol." With `melanogenicFraction(III) = 0.95` and ceilings 0.75 / 0.90 /
   1.0, the ceiling binds for type III at conservative and standard; only at
   aggressive does 0.95 bind. A type III at standard is therefore planned at
   0.90 × MED — the same fraction as a type II — while Module 5 (rendered
   verbatim) tells them "you do not need to flirt with a burn at all". Goal 3
   ("darker skin tans well below its burn line") is delivered for IV–VI and
   not for III, and S1 tests only type IV. Either the sentence should read
   "for types IV–VI" (and the goal narrowed accordingly), or the owner's 0.95
   is revisited. This is the owner's number; the report flags the claim, not
   the value.
2. **R19's threshold formula contradicts R6 and R19's own last sentence.**
   Detailed under A18/C7. "(target ÷ ceiling)" equals `MED_personal` only when
   the ceiling binds; for IV–VI (and type III at aggressive) it is lower, so
   "the strong warning means redness is expected" is false for those types.
3. **R21 carries two rules for one event.** Sentence 2 (from A1): a "normal"
   report at dose ratio ≥ 1.0 "moves the multiplier upward … to an implied
   threshold equal to the delivered dose". Sentence 5 (from B1): "Evidence that
   the skin tolerated more than the model predicted is attributed to the
   region's tanState, which decays" — and a "normal" at ratio ≥ 1.0 is exactly
   that evidence. Two agents would build different `CalibrationEngine`s; S3's
   "normal outlier at log 15 moves by at most 0.05" passes under both. §7 says
   only "attribution to tanState or multiplier". One sentence should state
   which wins, e.g. "A 'normal' report at ratio ≥ 1.0 raises the region's
   tanState to the level that would have predicted the delivered dose and
   never the multiplier; the multiplier rises only through the manual override
   in R23." (That reading also makes the 1.8 upper clamp unreachable by
   calibration, which R21 should then say.)
4. **"Current tan cycle" is undefined.** It gates the aggressive unlock (R7),
   the ceiling outcome (R14), and is stored as a "redness-in-cycle flag"
   (§9 DerivedState), but nothing says what starts or ends a cycle — a gap of
   more than two weeks (R13's gap message), tanState decaying below some
   floor, a calendar season, or deleting the history. Two agents would
   implement it differently and S6's "refused before five logs with a redness
   report" cannot tell them apart. One sentence in R7 or R12 is needed, e.g.
   "A tan cycle ends when the region's tanState decays below `cycleFloor`
   (default 0.1, tunable) or after a gap longer than R13's; redness reports
   from a closed cycle do not count toward the unlock or the ceiling outcome."
5. **Which side faces the sun first while lying down is not stated.** R9
   solves "over the actual sub-interval that side will face the sun" and R11
   "alerts at the first side's end", but neither names the first side. The
   choices are "front first, always", "the side with the larger remaining
   budget first", or a user control — the last is a control V7 does not list.
   The fixtures in S5 and use case 2 cannot be written without it.
6. **R45's third logging path cannot fire under R20.** R45 lets a session
   become logged by "answering 'yes' to the skin-check prompt's opening
   question 'Did you do this session?'", but R20 schedules the skin check
   "about 20 hours after the day's last *logged* session" and R45 discards
   unlogged plans at midnight, so a day with only planned sessions never gets
   a prompt and the path is dead. Either R20 should schedule the prompt after
   the day's last planned-or-logged session (and the prompt then does the
   logging), or the path should be deleted from R45 and §8 decision 21.
7. **"Log" is used for two things.** R20 says a skin report "counts as one
   log"; R45 uses "logged" for sessions; R7's `calibrationLogs` (3) and
   `aggressiveUnlockLogs` (5) say "logs"; R23's sentence says "based on 11
   sessions". Whether the conservative period ends after three logged sessions
   or three skin reports changes the number the user sees for their first
   week. Use case 8 ("five logs, one of them pink") implies reports; one
   definition sentence in R20 would close it.
8. **§3's new non-goal reads against R14.** §3: "the app never asserts a
   pigment ceiling it cannot see." R14, with a redness bound, says "the user
   has likely reached their biological maximum" — still a claim about pigment
   the app cannot see, hedged by "likely". A strict reader of §3 removes the
   ceiling message entirely; a loose one keeps it. Minor, but it is the kind
   of two-readings sentence the reviews hunted; §3 could say "never asserts a
   pigment ceiling without a redness bound in the cycle (R14)".

## Totals

IMPLEMENTED 40 / PARTIAL 4 (A8, A18, C7, X5) / MISSING 0 / CONTRADICTED 0 /
SUPERSEDED 1 (A2). Rows counted: A1–A18, B1–B14, C1–C7, X1–X6 = 45.
