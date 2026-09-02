# Conceptual adversarial review — 1

Reviewed: `docs/DESIGN.md` (draft, 2026-09-02), `docs/VISION.md`, against
`docs/BUILD_PROMPT.md` and `docs/LEARN_CONTENT.md` as the owner's inputs.
Read-only; nothing in the design or vision was changed.

## What the promises reduce to

Strip the design to what would exist if built exactly as written: a Swift
engine that integrates a two-day hourly UV forecast over a user-entered window,
multiplies a skin-type prior by two learned numbers (one shared "sensitivity"
that only reports can move, one per-region "tan state" that only dose can
move), takes 90% of the product as the day's budget, splits that budget across
three body regions by a posture table, and, when the window overshoots, picks a
sunscreen and application from a small menu. Around that engine sit a flip
timer, two local notifications whose answers feed the sensitivity number, a
Learn tab that renders the owner's twelve modules verbatim, one ad banner, and
a history of dose. The promise the owner actually cares about is narrower than
the requirement list and is stated in V1 and in §2: **a person who follows the
number does not go red into the next day, keeps gaining colour past week three,
and does not burn on the first day back from a break.** Almost all of the
findings below are places where the requirements, satisfied literally, produce
a system that passes every §13 test and still does not deliver that sentence —
most of them inside the calibration loop, which is the only part of the design
that turns the user's reality into the app's numbers, and which the design
specifies with constants it has not run.

---

## Findings, by silence rank

### 1. A "normal" skin report is a point estimate, so a correctly-typed user is walked upward until they go pink

QUESTION: 1 (goal gap)
SILENCE RANK: 1
WHERE: §5 R21 — "Each Q1 answer maps to an implied dose-to-threshold ratio
(tunable table; defaults normal 0.7, faint pink 1.0, clearly pink 1.5, red and
sore 2.5, blistered 4.0)." and §13 S3 — "a user with true multiplier 1.0 who
tans normally for six weeks stays within 0.05 of 1.0 while adaptation
accumulates".
THE GAP: The build prompt (§5.3) calls "nothing happened" *censored* data — the
threshold is somewhere above the dose, distance unknown. R21 turns it into a
point: "the dose was 70% of threshold." Run the design's own numbers. Standard
target delivers 0.9 × T_est. A "normal" report implies T = 0.9/0.7 = 1.29 ×
T_est, so the implied multiplier is 1.29 × the current one. At n = 0 the weight
is 1.0, so one uneventful first session moves a perfectly-typed user from 1.00
to 1.29. The next session lands at 1.16 × their true MED — Module 7's "mild
sunburn" band — and the "clearly pink" report (weighted 2 × 2.5/3.5 = 1.43,
which overshoots) drops them to about 0.55. The loop then climbs again, because
every "normal" report multiplies the estimate by 1.29 regardless of truth. The
fixed point is not the user's threshold; it is an oscillation around the user's
pink line. S3's "stays within 0.05 of 1.0" cannot pass against any reporter
that answers "normal" below 1 MED and "pink" above it — and the design never
says what the simulated reporter does, so the test will be written against
whatever reporter makes it pass.
CONSEQUENCE: The one mechanism that is supposed to keep the user under their
threshold instead searches for it by exceeding it. V1 ("stay clear of redness
that persists into the next day") is violated by design on session two for a
user who did nothing wrong. Because S3's reporter is unspecified, the test
suite will be green.
THE FIX: Replace the first two sentences of R21 with: "A 'normal' report is
one-sided evidence: it asserts only that the threshold lies above the delivered
dose. It moves the multiplier only upward, only when the delivered dose was at
or above the current estimated threshold for that region (dose ratio ≥ 1.0),
and then to an implied threshold equal to the delivered dose, never higher. At
or below the target fraction it is a confirmation and changes nothing. Redness
reports map to an implied dose-to-threshold ratio (tunable; faint pink 1.0,
clearly pink 1.5, red and sore 2.5, blistered 4.0)." And add to S3: "The
simulated reporter answers Q1 from the true dose-to-threshold ratio with bands
normal < 1.0, faint pink 1.0–1.3, clearly pink 1.3–2.0, red and sore 2.0–4.0,
blistered ≥ 4.0; the bands live in Tunables beside the implied-ratio table so
the two are visibly inverse."

### 2. The sensitivity/adaptation separation is asserted by construction, not learned; the S3 separation test is circular

QUESTION: 1 (goal gap)
SILENCE RANK: 2
WHERE: §8 decision 5 — "adaptation normalised out of every log before the
multiplier updates" and §13 S3 — "a user with true multiplier 1.0 who tans
normally for six weeks stays within 0.05 of 1.0 while adaptation accumulates".
THE GAP: Dividing the implied threshold by the *modelled* adaptation factor
separates the two terms only if the model's adaptation is the user's actual
adaptation. Nothing in the design ever corrects the adaptation factor from a
report; every disagreement between model and skin is booked to the multiplier,
which never decays. Take a user whose real adaptation runs higher than the
model (the design itself says types IV–VI are extrapolated): in August the
model says 2.0×, the skin is at 3.0×, every report is "normal", the multiplier
climbs toward the 1.8 clamp — and in February the adaptation factor decays to
1.0 while the multiplier stays at 1.5. Dose = 1.35 × true MED. That is the
build prompt's "exact path to a serious burn", reproduced by the mechanism
meant to prevent it. The S3 separation simulation will be built with the same
adaptation model on both sides of the simulator, so it passes by construction.
CONSEQUENCE: The burn-prevention guarantee (S4, "release blocker") guards the
decay of a modelled number. Model error in the tolerant direction is silently
converted into permanent intrinsic tolerance. Nothing in §13 can see it.
THE FIX: Add to R21: "Evidence that the skin tolerated more than the model
predicted is attributed to the region's tanState (which decays), never to the
multiplier; evidence that the skin reacted at a lower dose than predicted is
attributed to the multiplier (which persists). Disagreement in the tolerant
direction therefore cannot survive a gap." Add to S3: "The separation
simulation runs with the simulated user's true adaptation gain at 0.7× and at
1.3× the modelled gain; in both cases the multiplier stays within 0.10 of 1.0
after six weeks, and the first post-gap recommendation is at or below the
simulated user's true threshold."

### 3. Every user-facing word outside the Learn tab is unwritten and will be authored unattended

QUESTION: 1 (goal gap)
SILENCE RANK: 3
WHERE: §7 IcarusContent — "the copy table for engine outcome keys (edge-case
copy, warnings, explanations) so that no UI view holds literal copy"; §5 R28 —
"the six-row table with plain factual descriptions and an optional short
quiz"; §13 S11 — "every user-visible string in IcarusUI resolves through
IcarusContent".
THE GAP: The design guards *where* copy lives, never *what it says*. The result
screen, every R17 edge-case answer, the 90%/100% warnings, the tolerance-
dropped and ceiling messages, the skin-type descriptions, the quiz, the
disclaimer, the sensitivity sentence, the type-I thin-margin line, the "not
needed for the tanning goal" sunscreen line, the notification texts — none of
this exists in any input. The Learn modules are protected verbatim; the words
the user actually acts on will be written by coding agents with only R36 and
V10/V13 for guidance, and the only check is the owner's S9 read-through at M7.
The build prompt also demands the thin-margin line for types "I and II"; the
design has it as a use case for type I only and as no requirement at all.
CONSEQUENCE: The frank-not-preachy tone, the "no safe threshold" framing on
the result screen, and V13's "never ridiculous" are decided by whichever agent
fills the copy table. Everything passes CI.
THE FIX: Add R42: "All non-Learn user-facing copy — outcome keys, warnings,
onboarding, skin-type descriptions, the quiz, the disclaimer, notification
text, the sensitivity sentence — is authored in `docs/APP_COPY.md` before M3
begins, rendered by IcarusContent exactly as the Learn modules are, and is an
owner criterion (S17): every string in that file was written or approved by
the owner. For skin types I and II every result carries the thin-margin line
from that file."

### 4. MEGA-FORK: stored state or replayed state

QUESTION: mega-fork
SILENCE RANK: 4
WHERE: §7 data flow — "the day-after SkinReport runs through CalibrationEngine
to update the shared multiplier and through AdaptationModel to update
per-region states"; §9 — "Tunables — the configuration file, versioned,
exported with the JSON so a report can be reproduced"; §5 R22 — "so the
normalisation in R21 is possible retrospectively".
THE GAP: Two designs fit these sentences. (a) Mutable stored state: the
multiplier and three tanStates live in SwiftData and are nudged forward on
each event; decay is applied lazily on read. (b) Derived state: the session
and report log is the record, and the current multiplier and tanStates are
recomputed by replaying it under the current Tunables on every launch and
event. They differ in the shape of `UserProfile` and `RegionState` (stored vs
cache), in what export/import means, in how the "before and after" multiplier
in SkinReport is produced, and — the part the owner cares about — in what
happens when a constant is tuned. Under (a) changing the half-life leaves
every existing user's state where it was; under (b) it reshapes everyone's
state on next launch, which is what "tune the engine in one place" and V12
("trace to the tunables file") actually mean. R22's "retrospectively" and the
versioned-Tunables export point at (b); the data-flow sentence reads as (a).
CONSEQUENCE: The pseudocode pass builds Data, the models, export, and the
update flow around one of these. Guessed wrong, all of M2 and M5 are redone.
THE FIX: Add to §7: "Region states and the multiplier are derived, never
authoritative: on launch and after every logged session or report,
`AdaptationModel` and `CalibrationEngine` replay the ordered session and
report history under the current Tunables to produce the current state, which
is cached for display. Session records keep the adaptation factors and targets
in force at their time for the export and for R21; a Tunables change therefore
takes effect for every existing user on next launch. The JSON export is the
history plus the Tunables version, and importing it reproduces the state."

### 5. MEGA-FORK: which event moves which number — planned, timed, logged, or reported

QUESTION: mega-fork
SILENCE RANK: 5
WHERE: §9 Session — "whether planned, logged, or both"; §5 R19 — "When a
planned or logged session would take a region past 90% ... warn"; §7 data flow
— "the day-after SkinReport runs ... through AdaptationModel to update
per-region states"; §5 R12 — "`tanState ∈ [0, 1]` per region, rising with
cumulative recent effective dose".
THE GAP: Four moments could advance the day's dose and tanState: when a plan
is computed, when the flip timer runs, when the user confirms a session, and
when the day-after report arrives. The design names all four and picks none.
Reading 1: planned sessions count (the user "planned" the beach and stayed in
— tanState rises anyway, the next recommendation is longer, and the return
burn is built by the app). Reading 2: only reports count (§7's sentence) — a
user who never answers notifications gets no escalation and the plateau
feature, the app's reason to exist, never activates for them. Reading 3: the
flip timer's actual start and stop count — then the timer is the source of
truth, the per-side time must be recomputed from the actual start on the
cached curve (a morning session started twenty minutes late is on a rising
curve), and Session needs actual times distinct from the plan. Each reading
gives a different Session model, a different PromptScheduler, and a different
`Planner` input. "Effective dose" is also undefined: SED after sunscreen, or a
fraction of the region's personal threshold? Under absolute SED a type VI user
saturates tanState in a session or two and a type I user never does.
CONSEQUENCE: Reading 1 or 2 is quietly wrong for most users, in opposite
directions; either passes S4 and S5 because the simulations feed sessions
directly. Reading 3 changes UI and Data structurally.
THE FIX: Add to §7: "Only a session the user has confirmed as done ('logged')
feeds today's dose, tanState, and calibration. Starting the flip timer starts
a session at the actual clock time and recomputes the per-side time from that
start on the cached curve; stopping it, or confirming a plan without the
timer, logs the session with its actual start and end. A plan that is never
logged expires at local midnight and contributes nothing. A report adjusts the
multiplier only; tanState advances when the session is logged, from its
per-region dose after sunscreen expressed as a fraction of that region's
personal threshold at the time, so a session at the target fraction advances
tanState equally for every skin type."

### 6. No use case is a fixture; the owner's clearest statement of intent has no test

QUESTION: 1 (goal gap)
SILENCE RANK: 6
WHERE: §4 use cases 1–9, e.g. "the best 22 minutes inside that slot, that head
and shoulders reach the dose in those 22 minutes while the front and back get
about half"; §13 — no criterion references §4.
THE GAP: S1–S6 test components against component-level numbers. Nothing pins
the composed answer: the 22 minutes, the "front is already at 85%", the
"materially shorter than the last one they did", the "earliest 30 minutes per
side". A `Planner` that composes the correct components in a subtly wrong
order (target before posture, sunscreen before budget) passes everything.
CONSEQUENCE: The first time an owner sees the numbers the use cases promised
is on a device at M3, from an app whose engine froze at M1.
THE FIX: Add S18: "Each §4 use case is a fixture under `acceptance/`: a
forecast series, profile, region states, today's logged dose, window, posture,
and the expected outcome type, headline minutes within ±10%, per-region doses,
and the copy keys named in the use case. M1 is not done until S18 passes for
use cases 1–6 and 8–9; M5 adds 7."

### 7. Types III–VI are planned at the burn line the Learn tab tells them not to approach, and the engine has no melanogenic threshold

QUESTION: 1 (goal gap)
SILENCE RANK: 7
WHERE: §5 R6 — "conservative / standard / aggressive, mapping to 0.75 / 0.90 /
0.95, default standard"; §5 R17 — "window too weak to matter (with the
shortfall and the next viable window)"; LEARN_CONTENT Module 5 — "If you are
type III or above: you have room... You do not need to flirt with a burn at
all, and you shouldn't."
THE GAP: The app will render, verbatim, a module telling type III+ users they
should not go near their burn threshold, and its engine will plan them at 90%
of it by default. The build prompt's 0.90 was stated for the type II sanity
check; Module 5 (also the owner's) makes the fraction type-dependent in
substance. Separately, "window too weak" is defined in the build prompt as
"far below the melanogenic threshold", but the design has no such threshold —
its only number is the target — so the "shortfall" will be measured from
whatever an agent picks.
CONSEQUENCE: Type IV–VI users get a dose the app's own Learn tab calls
unnecessary (V10: copy that implies the near-burn dose is fine for them). The
"too weak" outcome and the ceiling message (finding 12) both rest on a number
that does not exist.
THE FIX: Replace R6 with: "The target fraction is per skin type in Tunables,
selectable in Settings as conservative / standard / aggressive. Defaults:
types I–II 0.75 / 0.90 / 0.95; type III 0.65 / 0.80 / 0.90; types IV–VI 0.55
/ 0.70 / 0.85 (assumption; Module 5). Tunables also carries
`melanogenicFraction(skinType)` — the fraction of personal threshold below
which a session is not expected to produce lasting colour: I–II 0.85, III
0.6, IV–VI 0.5 (assumption; Module 5). The 'too weak' outcome is a window
whose best achievable dose falls below it, and the shortfall is measured
from it." (The numbers are the reviewer's proposal; the decision that they
are per-type is the finding.)

### 8. The seasonal cumulative total was moved off the result and into a "Later" milestone

QUESTION: 1 (goal gap)
SILENCE RANK: 8
WHERE: §12 — "**Later** — M6 — History. Session log, weekly and seasonal
totals per region, dose-trajectory chart"; BUILD_PROMPT §4.5 — "Cumulative
dose tracking (§5.5) continues regardless, and the seasonal total should
remain prominent as adaptation climbs."
THE GAP: The build prompt's defence against "adaptation implies safety" is
that the seasonal total stays *prominent* as the session lengthens — beside
the escalation message, not in a history tab. The design puts History after
the MVP and R13's escalation message carries no total.
CONSEQUENCE: The MVP escalates sessions with a line saying the threshold has
risen and nothing saying what the season has already cost. V10's "soften the
no-safe-threshold point" is exactly what a lengthening number with no total
does.
THE FIX: Add to R13: "Whenever the result is longer than the user's first
session because of adaptation, the same result card shows the region's
season-to-date cumulative dose in SED beside the message. This is part of M3;
M6 adds the chart and weekly view."

### 9. Uncertainty is displayed and never acted on; V2 and V3 point opposite ways and the design follows V3

QUESTION: 2 (vision)
SILENCE RANK: 9
WHERE: VISION V2 — "Never under-warn. When the model is unsure, it errs toward
the shorter session and says why." V3 — "Say what is known precisely. Say what
is uncertain as a range." DESIGN §5 R7 — "Every recommendation shows a
specific number at the target fraction and a range that reflects the current
uncertainty: about ±30% (tunable) before any logs".
THE GAP: Reading A (V3): the number is the best estimate at the target
fraction and the ±30% range is "saying why" — the design as written. Reading
B (V2, which is ranked above V3): at n = 0 the model is at its most unsure,
so the number itself should be shorter, and the range explains the shortfall.
Two agents citing the vision reach different numbers for the first session,
and the design has already sided with the lower-ranked statement. The range
also narrows purely with n, so ten "normal" reports that never bounded the
threshold from above narrow it as much as ten pink ones would — a confident
look with no basis (V12).
CONSEQUENCE: The first session for a type I user is 0.9 × a ±30% prior. The
flip timer runs to the number; nobody reads the range on a towel.
THE FIX: Add to R7: "Before the first report (n = 0) the specific number is
computed at the conservative fraction regardless of the Settings choice, and
the copy says so; the chosen fraction applies from the first report onward.
The range's lower edge narrows with reports that bounded the threshold from
below (any report) and its upper edge only with reports that bounded it from
above (redness), so a user who has never gone pink keeps a wide upper edge."
And in VISION V2, append: "'Says why' means the number moved, not that a
range was drawn beside it."

### 10. The 90% budget warning fires on every standard session; burn language at 100% of target is not honest

QUESTION: 1 (goal gap)
SILENCE RANK: 10
WHERE: §5 R19 — "When a planned or logged session would take a region past
90% (tunable) of its target, warn; past 100%, warn strongly using the burn
language of Learn Module 7."
THE GAP: The budget is the target, and a standard session is planned at 100%
of it. Read literally, every first session of the day carries the 90%
warning, and any session that overshoots the plan by a minute carries Module
7's burn language at 0.9 MED — where no redness is expected. An agent citing
V2 keeps the warning everywhere; the user learns to ignore it, and the one
warning that matters (use case 4's afternoon session) looks like all the
others. An agent citing V3 moves the burn language to the threshold. The
document does not decide.
CONSEQUENCE: Either warning fatigue (which under-warns in effect) or a quiet
re-basing of the thresholds by whoever writes ExposureModel.
THE FIX: Replace R19's second sentence with: "The first plan of the day shows
the remaining budget with no warning. A plan or log that, added to dose already
logged today, exceeds the region's target warns; one that reaches the region's
personal threshold (target ÷ target fraction) warns strongly in Module 7's
burn language. Both lines are measured against the threshold, not the target,
so the strong warning means redness is expected."

### 11. S3's outlier bound and R21's constants contradict each other, and the quiet fix will be a mechanism nobody chose

QUESTION: 1 (goal gap)
SILENCE RANK: 11
WHERE: §13 S3 — "is not moved by more than 0.03 by one outlier at log 15";
§5 R21 — "`weight = k / (n + k)` with k ≈ 2.5 ... Burn observations carry
twice the weight".
THE GAP: At n = 15 a "red and sore" report at the planned dose implies 0.36 ×
the current multiplier with weight 2 × 2.5/17.5 = 0.286: the move is −0.18 ×
m, six times the bound. The bound is achievable only with k ≈ 0.4 (which makes
the second log almost inert, contradicting "first logs move far, later logs
nudge") or a per-update cap (which would also cap the blistering correction).
The test fails loudly; the *repair* is silent, and V2 says a burn report at
log 15 should move the estimate materially — so the 0.03 bound is itself
arguable. Also: for n < k the doubled weight exceeds 1 and overshoots the
implied value; the numbers were not run.
CONSEQUENCE: An agent picks k, a cap, or a redefinition of "outlier" to make
S3 green; the owner never sees which.
THE FIX: Replace the S3 clause with: "one 'normal' outlier at log 15 moves the
multiplier by at most 0.05; one 'red and sore' report at log 15 moves it down
by at least 0.10 and at most 0.20; the effective weight of any single update
is capped at 1.0." (Or, if 0.03 for burns is the intent, say "k ≈ 0.4" and
delete "first logs move far".)

### 12. The ceiling message cannot tell "at biological maximum" from "under-dosed"

QUESTION: 1 (goal gap)
SILENCE RANK: 12
WHERE: §5 R14 — "When `tanState` is near saturation and the lasting-colour
prompt returns 'no' repeatedly (tunable count), stop escalating and say the
user has likely reached their biological maximum"; §3 non-goals — "No
measurement of pigment. The history is a record of dose, never a claim about
colour."
THE GAP: tanState is a modelled function of logged dose, not of colour. A user
whose true multiplier is above the estimate (or a type III+ user planned
below their melanogenic dose, finding 7) logs plenty of dose, reaches modelled
saturation, and reports no lasting colour because the dose never triggered
pigment. R14 then tells them they have hit their biological maximum — a claim
about pigment the non-goals forbid — and stops escalating, freezing them in
the plateau the app exists to break. The lasting-colour prompt also has no
region, while the "no" count is stored per region.
CONSEQUENCE: The plateau feature switches itself off with a confident,
wrong, and unfalsifiable sentence for the users most likely to hit it.
THE FIX: Add to R14: "The ceiling outcome requires that at least one redness
report in the current tan cycle has bounded the region's threshold from above;
without that, repeated 'no lasting colour' near modelled saturation produces
the under-dosed outcome instead ('the app has not yet seen your skin react, so
it cannot tell whether the dose is too low or your skin is done'), and the
copy never asserts a pigment ceiling. The lasting-colour answer applies to
every region exposed in that session."

### 13. The sunscreen path — the app's differentiator — is silent about the UVA cost it creates

QUESTION: 1 (goal gap)
SILENCE RANK: 13
WHERE: §5 R16 — "When no sunscreen is needed for the tanning goal, still
surface the option, and still say so when the UVA load is high." §5 R18 — the
UVA note is "tunable threshold on hours from solar noon"; §4 use case 3 —
"solves for 'SPF 30, applied normally' for the three hours ... and offers the
alternative: 40 minutes per side, no sunscreen."
THE GAP: Module 8 (the owner's text, rendered verbatim) says SPF describes
UVB protection and "tells you almost nothing about UVA". A three-hour session
brought to 0.9 erythemal MED through SPF 30 therefore delivers several times
the UVA of the 40-minute bare alternative for the same pigment signal —
Module 3's "worse ratio" — and the only UVA note in the design keys on solar
noon, so at midday the three-hour sunscreen plan carries none. The design's
goal "teach ... what is actually happening to the skin" is met in the Learn tab
and contradicted on the result screen. Reapplication is likewise absent: a
three-hour plan assumes one application holds.
CONSEQUENCE: The recommended answer for use case 3 is the higher-photoaging
one, presented without the caveat the app's own content supplies.
THE FIX: Add to R15: "When the plan reaches the target through sunscreen, the
result states that the product filters UVB more than UVA unless it carries a
UVA rating, that the session's UVA load is therefore higher than the bare-skin
sub-window's, links to Module 8, and always shows the bare-skin sub-window
beside it as the lower-UVA option. A sunscreen plan longer than the
reapplication interval (2 h, tunable) names the reapplication times, and the
timer alerts at them."

### 14. Two sessions in a day produce two skin checks about one skin

QUESTION: 1 (goal gap)
SILENCE RANK: 14
WHERE: §5 R20 — "About 20 hours after a session (tunable), a local
notification asks Q1"; §5 R19 — "A user may log any number of sessions per
day."
THE GAP: The skin the user looks at the next morning shows the *sum* of the
day's sessions. Two prompts, each evaluated against its own session's partial
dose, book the whole reaction to a half-dose twice: the multiplier is pushed
down twice from one observation. Safe in direction, wrong in size, and it
makes n grow twice as fast as the evidence, narrowing the range (R7) on air.
CONSEQUENCE: Users who do the lunch-hour walk and the evening pool (the
design's own use cases 1 and 2 on the same day) get a miscalibrated multiplier
and a falsely narrow range.
THE FIX: Replace R20's first clause with: "One skin-check prompt per day,
scheduled about 20 hours (tunable) after the day's last logged session; the
answer is evaluated against the day's cumulative per-region dose and the
adaptation factors in force, and counts as one log."

### 15. The cover toggle logs the covered region at an unstated dose

QUESTION: 1 (goal gap)
SILENCE RANK: 15
WHERE: §5 R10 — "a single toggle 'head and shoulders covered' (hat, shirt, or
SPF 30+) removes that region from the limit and lets the session run to the
torso's full time, with the doubled head-and-shoulders exposure explained."
THE GAP: A hat, a shirt, and "SPF 30+" applied the way people apply it (√30 ≈
5.5×, or 30^0.25 ≈ 2.3× thinly) are different attenuations by an order of
magnitude, and the design does not say what dose the head-and-shoulders
region is logged at when the toggle is on. Zero is the natural coding choice.
At double session length through thin SPF 30, the face receives 2/2.3 ≈ 87%
of the dose that would have limited the uncovered session — logged as
nothing, invisible to the daily budget and to tanState.
CONSEQUENCE: An afternoon second session on a face already near its limit,
with the app showing that region at 0%. V2 says never under-warn; the
toggle as specified under-logs.
THE FIX: Add to R10: "With the toggle on, head-and-shoulders is logged at the
full session dose attenuated by the weakest named cover, SPF 30 applied
normally (√30, tunable); that figure feeds the daily budget and tanState, and
the result says so."

### 16. Zero running cost has no fetch cadence behind it

QUESTION: 1 (goal gap)
SILENCE RANK: 16
WHERE: §6 — "WeatherKit's included tier (500,000 calls/month with the
developer membership) is the data source"; VISION V6 — "Zero running cost."
THE GAP: Nothing says when the app fetches. Fetch-on-every-calculation (the
obvious coding choice, since R4 says "recompute only on new forecast") at a few
thousand users exceeds the free tier and moves WeatherKit onto a paid tier —
the one recurring cost the design promises not to have. V6 decides this only
for an agent who knows the tier arithmetic.
CONSEQUENCE: A cost that appears at the first success, from a design that
passes S12 ("no cost beyond the Apple Developer Program appears in any
dependency, service, or plan") because the plan never mentions cadence.
THE FIX: Add to R1: "The forecast is fetched at most once per hour per device
(tunable) and only on foreground or an explicit refresh; every calculation in
between is served from the cache. A device therefore costs at most about 24
calls a day, and the fixture test asserts the cadence."

### 17. If notifications are denied, the learning loop never runs

QUESTION: 1 (goal gap)
SILENCE RANK: 17
WHERE: §5 R20 — "a local notification asks Q1"; §3 goals — "learn that
threshold from day-after reports rather than from the skin-type prior alone."
THE GAP: Every report enters through a notification. A user who declines
notification permission — common — never sees a skin check, stays at the prior
forever, and the app's second goal is silently unmet for them. The design
handles location denial explicitly (R2) and notification denial not at all.
CONSEQUENCE: Calibration works only for the permission-granting subset, and
nothing in §13 distinguishes the two.
THE FIX: Add to R20: "If notification permission is denied or a prompt goes
unanswered, the skin-check and lasting-colour questions are asked in-app on
the next launch after their delays have elapsed, with the date of the session
they refer to; the loop must not depend on notifications."

### 18. MEGA-FORK (borderline): "next viable window" and "no viable day this season" need a UV source the design does not have

QUESTION: mega-fork
SILENCE RANK: 18
WHERE: §5 R17 — "window too weak to matter (with the shortfall and the next
viable window) ... no viable day this season"; §9 Forecast — "hourly UVI series
for the day and the next"; §8 decision 12 — "Solar noon from the forecast, not
computed ... no second source of truth".
THE GAP: With two forecast days the engine can name a next viable window only
inside those two days, and it cannot say anything about "this season". Either
Core gains a clear-sky solar model (date + latitude → peak UVI), which
decision 12 rejected for solar noon, or the outcomes are narrowed. Which one
changes Core's scope and Data's inputs.
CONSEQUENCE: An agent adds a solar model (new source of truth, no forecast
cloud, new tunables) or quietly renders "no viable day this season" from two
days of data — a confident sentence with no basis (V12).
THE FIX: Add to R17: "The engine's only UV source is the forecast's two days.
'Next viable window' searches those days only; when neither holds one, the
outcome says so and names no later date. The seasonal outcome is triggered
from a static table in Tunables of monthly clear-sky peak UVI by 10° latitude
band (assumption; WHO 2002), never from a live solar model, and its copy is
phrased as a seasonal likelihood."

### 19. The cached forecast is for wherever the phone last had signal

QUESTION: 1 (goal gap)
SILENCE RANK: 19
WHERE: §4 use case 9 — "With no signal, the app uses the cached forecast,
shows its age prominently"; §5 R3 — staleness is defined by age only.
THE GAP: The beach with no signal is rarely where the morning fetch happened.
A two-hour-old forecast for home is "fresh" by R3 and may be wrong by several
UVI at the coast, on a mountain, or in a different climate. V3 says say what
is uncertain; the design says only how old it is.
CONSEQUENCE: A confident number for the wrong place, shown with a reassuring
age.
THE FIX: Add to R3: "The cache stores its location; when the device is more
than 25 km (tunable) from it, or the location is unknown, the forecast is
treated as stale regardless of age, and the result names the place it was
fetched for."

### 20. The decay half-life was set to the midpoint the build prompt told it not to use

QUESTION: 1 (goal gap)
SILENCE RANK: 20
WHERE: §5 R12 — "decaying toward zero with a half-life of about 3.5 weeks
(tunable)"; BUILD_PROMPT §4.5 — "half-life of roughly 3–4 weeks ... a single
combined decay term is acceptable for v1, but bias it toward the faster end."
THE GAP: 3.5 is the middle of 3–4. The instruction to bias fast (because
epidermal thickening decays faster than pigment) was dropped, and V2 would
have picked 3.
CONSEQUENCE: A constant nobody will ever look at again, one week slower than
the owner asked for, in the direction of the after-holiday burn.
THE FIX: In R12: "half-life 3.0 weeks (tunable), the fast end of the cited
3–4 week range, because the thickening component decays faster than pigment
(Module 6)."

### 21. V14 does not say whether the Calculator entry screen may carry a number

QUESTION: 2 (vision)
SILENCE RANK: 21
WHERE: VISION V14 — "An ad next to a number the user acts on. The banner is
small and it stays on the entry screens"; DESIGN §5 R39 — banner "at the
bottom of the Calculator entry screen".
THE GAP: Reading A: the entry screen is a useful dashboard — today's UVI,
forecast age, remaining budget — and the banner sits under it. Reading B: any
of those is "a number the user acts on", so the entry screen must be inputs
only. Both agents cite V14; the remaining budget is the kind of figure the
user does act on ("is it worth going out again?").
CONSEQUENCE: A banner under the day's remaining budget, on the screen most
users see most, in an app whose vision was written to prevent exactly that.
THE FIX: Add to R39: "The Calculator entry screen holds inputs only — no
UVI, forecast age, budget, or any figure the user could act on; every figure
lives on the Result screen. History carries no banner."

### 22. V5 forbids what S13 requires, and three citations cannot render a DOI

QUESTION: 2 (vision)
SILENCE RANK: 22
WHERE: VISION V5 — "no citation is ever paraphrased, summarised, or dropped";
DESIGN §13 S13 — "checked against doi.org, corrected where wrong"; §5 R26 —
"Every citation renders with authors, title, and a tappable DOI link";
LEARN_CONTENT Module 2 — "(No DOI; PMID 10066941)", Module 3 McKinlay (CIE
standard, no DOI), Module 10 Ledo (no identifier).
THE GAP: Agent 1 reads V5 and refuses to alter a wrong DOI; agent 2 reads S13
and corrects it. And R26 read literally cannot be satisfied for the citations
that carry a PMID, an ISO number, or nothing — the tempting fixes are to
invent a DOI (V12) or to drop the tap (R26). Neither document decides.
CONSEQUENCE: Either a broken link ships, or a fabricated one does.
THE FIX: In VISION V5, append: "A citation may be corrected only so that it
resolves to the paper it names — identifier, year, venue — never in wording,
and every correction is listed in `docs/reviews/citations.md`." In R26:
"A citation without a DOI renders the identifier it carries — PMID (tappable
via pubmed.ncbi.nlm.nih.gov), ISO number, or URL — as given, and is never
assigned an identifier the source does not carry."

### 23. V7 never decides anything

QUESTION: 2 (vision)
SILENCE RANK: 23
WHERE: VISION V7 — "Simple and elegant. Polish matters; it does not need to be
flashy to be polished."
THE GAP: Construct the disagreement: one agent adds a sunscreen-density
slider, a per-region toggle, and a UVA meter to the calculator; the other
keeps two pickers and a switch. Both call their design simple and polished.
V8 already trades away flair; V7 adds nothing an agent can be held to.
CONSEQUENCE: Every UI scope argument in an unattended run is decided by taste.
THE FIX: Replace V7 with: "Fewer controls over more options. The calculator
asks exactly what the engine needs — window, posture, the cover toggle, and a
sunscreen choice — and nothing else; any further knob is a Settings item, and
a Settings item that does not change a number the user acts on is not added."

### 24. V12 accepts "it is in the tunables file" as a basis

QUESTION: 2 (vision)
SILENCE RANK: 24
WHERE: VISION V12 — "A rule, a constant, or a line of copy the user cannot
trace to the tunables file, a citation, or a logged report."
THE GAP: The "up and about" half-dose fraction, the 20-hour delay, the
melanogenic and posture fractions, the type IV–VI gains are all assumptions.
Agent 1 reads V12 as satisfied by placing them in Tunables; agent 2 reads it
as requiring a citation. Both are reasonable; the statement was meant to stop
confident numbers with no basis, and a file is not a basis.
CONSEQUENCE: Every invented constant is laundered through Tunables and the
result screen presents figures built on assumptions as if cited.
THE FIX: Append to V12: "Every entry in Tunables carries, beside it, either a
citation into the Learn modules or the word `assumption` with a one-line
rationale; a result that depends on an `assumption` constant is labelled an
estimate on screen."

---

## CLOSED ANGLES

Intent questions probed and found genuinely answered by the documents, so the
next reviewer need not re-walk them.

- Per-side minutes when the two halves of a lying-down window sit on different
  UVI: V2 decides — the side that hits its target first sets the time for both.
- Which region limits a lying-down session when front and back have different
  adaptation: V2 decides — the lower threshold.
- Best sub-window = closest to solar noon: R17 and Module 3 agree; no fork.
- One shared sensitivity, three tan states: decision 3 and R8, deliberate and
  argued; the "all exposed" report attribution is an acknowledged open item.
- Open-Meteo fallback is an owner decision, never silent: §6, decision 2, and
  the build prompt all say so.
- Ads: placement list in R39 is exhaustive and positive (Calculator entry,
  Learn list only), non-personalised only, no-op provider in tests — V6, V11,
  V14 and R39–R41 agree.
- Network calls: V11 and R32 list the same three; the geocoder is named as part
  of the weather fetch (decision 13).
- Sunbeds: discouraged, never modelled — non-goals, R29, Module 7.
- iOS 18 floor as "current minus one": decision 16 matches the build prompt.
- "No design decision may block Watch/iPad/widgets" (V9) is made concrete by
  R31 and decision 17; it is not decorative in practice.
- Same-evening prompting rejected in favour of ~20 h: decision 15, cited to
  Module 7's erythema timing.
- Multiplier never decays for season: R21 and decision 5 match the build prompt.
- Learn copy verbatim, one file per module, no literals in views: R26, R34,
  S7, S11, V5 all align.
- The "Icarus"/"Acuras" name is a placeholder not to be baked in: §1 header.
