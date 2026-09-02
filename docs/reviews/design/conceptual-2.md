# Conceptual adversarial review — 2

Reviewer: a fresh agent that did not write `docs/DESIGN.md` or `docs/VISION.md`.
Read in the prescribed order: DESIGN, VISION, then `design-flow.md`, then the
owner's inputs `BUILD_PROMPT.md` and `LEARN_CONTENT.md`. Read-only; no design
text was changed. `conceptual-1.md` was neither read nor waited for.

## What the promises reduce to

Strip the design to what it would actually produce and it is this: an on-device
calculator that integrates a two-day hourly UV forecast over a user-chosen
window, divides by a per-person threshold made of three multiplied numbers (a
skin-type prior, a slowly learned personal multiplier, a fast-moving per-region
tan factor), and reports the minutes that land at 90% of that threshold, plus a
sunscreen that would stretch the same dose over a longer window. Around that
core sit a day-after questionnaire that nudges the multiplier, a decay clock
that shrinks the tan factor over gaps, a flip timer, twelve verbatim Learn
modules with citations, one ad banner on two entry screens, and a rule that the
whole thing must be honest about cost. The promise the owner actually cares
about — "the number I act on stays under my burn, grows as my tan grows, and
shrinks after a break" — rests entirely on three things the design treats as
tunables and never pins: what the day-after answers *mean* in dose terms, how
fast the tan factor rises, and which sessions count as having happened. Those
three are where most of the findings below live, and they are the ones most
likely to survive to a device looking exactly as designed.

**Mega-forks found** (full entries in the ranked list): #4 one per-side figure
versus per-region solved times; #13 what makes a session real; #17 the forecast
horizon behind "next viable window" and "no viable day this season".

## Findings, ordered by silence rank

---

### 1. The calibration loop's resting point is the redness threshold, not 90% of it

QUESTION: 1 (goal gap)
SILENCE RANK: 1
WHERE: §5 R21 — "Each Q1 answer maps to an implied dose-to-threshold ratio
(tunable table; defaults normal 0.7, faint pink 1.0, clearly pink 1.5, red and
sore 2.5, blistered 4.0)." together with R6 — "mapping to 0.75 / 0.90 / 0.95,
default standard." and §13 S3 — "a user with true multiplier 1.0 who tans
normally for six weeks stays within 0.05 of 1.0 while adaptation accumulates".

THE GAP: The design says the multiplier is learned so the dose stays under the
threshold. What the table produces is different. A correctly typed user is
planned at 0.9 of their threshold, sees nothing the next day, and honestly
answers "normal". The table turns that into "the dose was 0.7 of the
threshold", so the implied multiplier is 0.9 ÷ 0.7 = 1.286 × the current one.
The first log carries weight k/(0+k) = 1.0, so one honest "normal" moves the
multiplier to 1.286 and the next session is planned at 1.16 MED — above the
user's real burn line. If no-reaction reports are half-weighted (the design does
not say how the 2× asymmetry is applied) the second session lands at 1.03 MED
instead. Either way the loop only stops climbing when the user reports pink; its
fixed point is "regularly faintly pink", i.e. the threshold itself. That is the
opposite of R6's 0.9 and of V2. S3 cannot catch this because it never states
what the simulated user reports at a given fraction of their true threshold;
whoever writes the simulator picks a response model, and the only model that
passes S3 is one where "normal" is not reported at 0.9 — which is not how skin
behaves (Module 7: redness appears from ~1 MED).

CONSEQUENCE: The build passes S3 with a simulator tuned to pass it, the owner
sees plausible sensitivity sentences in Settings, and every truthful user is
walked up to their burn line over their first few logs. This is precisely the
"plausible-looking number that could burn someone" the build prompt's last
paragraph warns about, and it originates in a constant the design invented
(the build prompt gives no table).

THE FIX: Replace the ratio sentence in R21 with: "A 'normal' report is a lower
bound, not an estimate: it says the threshold was above the delivered dose. It
moves the multiplier upward only when the delivered dose already exceeded the
current estimate of the threshold (estimated ratio > 1), and then only to the
delivered dose ÷ the target fraction; a 'normal' report at or below the target
dose moves the multiplier by nothing. Redness reports (faint pink 1.0, clearly
pink 1.5, red and sore 2.5, blistered 4.0) are point estimates and move it in
either direction." Add to S3: "The simulated user's response model is a fixture
in the acceptance script, not the test author's choice: 'normal' below 0.95 of
the true threshold, 'faint pink' 0.95–1.15, 'clearly pink' 1.15–2.0, 'red and
sore' 2.0–4.0, 'blistered' above 4.0; a user at true multiplier 1.0 reporting
truthfully at the standard target for 20 logs moves by no more than 0.05."

---

### 2. One target fraction for every skin type contradicts what the app teaches

QUESTION: 1 (goal gap)
SILENCE RANK: 2
WHERE: §5 R6 — "The target dose is a tunable fraction of the personal
threshold, selectable in Settings as conservative / standard / aggressive,
mapping to 0.75 / 0.90 / 0.95, default standard." against Learn Module 5 (which
R26 renders verbatim) — "If you are type III or above: you have room. Your burn
threshold sits well above the dose that gets pigment production going, so you
can tan steadily at a comfortable distance from redness. You do not need to
flirt with a burn at all, and you shouldn't."

THE GAP: The goal is honest numbers plus honest teaching from one app. Built as
written, the Learn tab tells a type IV user they should never flirt with a burn,
and the Calculator, on the same day, plans them a 4.05 SED session (0.9 × 4.5)
— flirting with a burn by the app's own definition, and escalating from there
under R12. Module 5's whole argument is that "ride the line" applies to types I
and II because their melanogenic and erythemal thresholds coincide; for III–VI
the tanning dose is well below the burn dose. The design carries the I–II rule
to everyone. Nothing in §13 compares the two.

CONSEQUENCE: Every test passes; on a device the numbers look sober. Types III–VI
receive a materially larger dose than their goal needs, the seasonal cumulative
total (the cost the app says it is honest about) is inflated for the users with
the most room to avoid it, and a reader of Module 5 sees the app not doing what
it says. V10 ("never soften the no-safe-threshold point") is violated in
arithmetic rather than copy.

THE FIX: Replace R6 with: "The target fraction is a per-skin-type-band table in
Tunables. Types I–II use the selector's 0.75 / 0.90 / 0.95 because their
melanogenic threshold sits at the burn threshold (Module 5). Types III–VI use a
lower band, default 0.60 / 0.70 / 0.80 (owner to set), because Module 5 states
their tanning dose sits well below their burn dose; the result screen says which
band applies and why, with a link to Module 5." Add to S1: "a type IV at
multiplier 1.0 and steady UVI 7 is planned materially shorter, as a fraction of
MED, than a type II."

---

### 3. Head and shoulders receive no dose while lying down

QUESTION: 1 (goal gap)
SILENCE RANK: 3
WHERE: §5 R9 — "In 'lying down, turning over', front and back each receive the
full per-side time and the session total is twice the per-side time" and §13
S5 — "lying-down total equals twice the per-side time and both regions receive
the full per-side dose".

THE GAP: The design says three regions each carry their own dose today so that
the daily budget is honest per region. R9 defines the lying-down dose for front
and back only; head-and-shoulders is not mentioned, and S5's "both regions"
confirms the omission is what gets tested. A face is up for the whole
face-up side and shoulders are up for both sides. Built as written, a user who
lies 30 minutes per side at lunch has delivered a full target dose to their face
and the model records 0% of the head-and-shoulders budget used. Use case 4 then
runs in the afternoon: "up and about" is limited by head-and-shoulders, whose
budget reads empty, so the app recommends a second full head-and-shoulders
dose.

CONSEQUENCE: The one region the design calls out as "the region that limits
walking sessions" is the one whose budget is silently wrong in the dangerous
direction on any day that mixes postures, and the region tan state for the face
never rises from lying sessions, so the plateau feature misfires there too.
Passes S5.

THE FIX: Add to R9: "In 'lying down, turning over', head-and-shoulders receives
the front-side dose in full (face up) plus a tunable fraction (default 0.5) of
the back-side dose for the shoulders, unless the cover toggle is on; the cover
toggle is available in both postures." Add to S5: "a lying-down session credits
head-and-shoulders with the face-up dose, and a following up-and-about session
the same day is limited by that credited dose."

---

### 4. One "per side" figure defeats the per-region model, and S5 enshrines it

QUESTION: mega-fork
SILENCE RANK: 4
WHERE: §5 R9 — "the result is shown as 'X min per side, Y min total'"; §13
S5 — "lying-down total equals twice the per-side time"; against §8 decision 3
— "Front and back do tan independently in real life".

THE GAP: The design gives front and back separate tan states, separate daily
budgets, and separate adaptation factors, on the stated ground that they diverge
in real life — and then defines the answer as a single per-side time. When the
regions diverge (a park sitter who always faces the sun; a morning session that
used 60% of the front budget), one number must be either the minimum (safe;
the more-tanned side plateaus, which is the failure the app exists to fix) or
the maximum (burns the other side). A second problem hides in "per-side time":
UVI changes across the session, so equal *times* are unequal *doses*. A
09:00–10:00 lying session gives the second side more than the first; a
17:00–18:00 one gives it less. Splitting by time over-doses one side every
morning. Each candidate answer reshapes `DoseResult`, `ExposureModel`, the
Result view, the flip timer and S5 — which is why this is a mega-fork: the
pseudocode pass will pick one and every downstream screen and test inherits it.

CONSEQUENCE: Built to S5 as written, the app shows "30 min per side" while its
own model knows the two sides should get different times, and the flip timer
alerts at the midpoint regardless of the UV slope. A pass that picks "single
figure" cannot later grow two figures without rewriting the result contract.

THE FIX: Replace the quoted R9 sentence with: "Per-side times are solved per
region, each against that region's threshold and remaining budget and over the
actual sub-interval that side will face the sun, so that each side receives its
target dose, not an equal time. The result shows one 'X min per side' figure
when the two differ by less than a tunable fraction (default 15%) and 'front X
min, back Y min' otherwise; the flip timer alerts at the first side's end and at
the session's end." Replace S5's first clause with: "lying-down credits each
region with its own target dose over its own sub-interval; the total is the sum
of the two sides and equals twice the per-side time only when the regions are
equal and the UVI is flat."

---

### 5. The number the user acts on ignores the uncertainty the app admits

QUESTION: 2 (vision) and 1 (goal gap)
SILENCE RANK: 5
WHERE: `VISION.md` V2 — "Never under-warn. When the model is unsure, it errs
toward the shorter session and says why." against §5 R7 — "Every
recommendation shows a specific number at the target fraction and a range that
reflects the current uncertainty: about ±30% (tunable) before any logs" and §8
decision 8 — "The number sits at the target fraction; the range narrows as logs
arrive."

THE GAP: Two readings that both cite V2. Reading A: "errs toward the shorter
session" means the *displayed number* is the shorter end of what the
uncertainty allows, at least until logs exist. Reading B: the number is the
point estimate at the target fraction (as R7 and decision 8 say) and V2 is
satisfied by showing the range and saying why. Under B, an uncalibrated user
with ±30% uncertainty is handed a number whose upper error bar is 1.17 MED — a
burn — and told to act on it, and the app's own Module 11 ("build in margin,
especially early on") is advice the app does not follow itself. Under A the
design's R7 sentence is wrong. The design picks B explicitly; the vision, read
plainly, asks for A. Nobody unattended can tell which the owner meant.

CONSEQUENCE: An agent implementing R7 literally builds B, S6 passes ("carries a
specific number and a range"), and the top-priority vision statement is not
what the result screen does. The owner sees a number and a range and cannot
tell from the screen which reading was built.

THE FIX: Replace the R7 sentence with: "Every recommendation shows a specific
number and a range. Before n reaches a tunable calibration count (default 3
logs) the specific number is computed at the conservative fraction whatever the
selector says, and the copy says 'shorter until the app has learned your skin';
after that the number sits at the selected fraction. The range is ±30%
(tunable) at n = 0 and narrows with n." And amend V2 to make it decidable:
"V2 — Never under-warn. When two defensible numbers differ, the shorter session
is the one shown, and the result names the uncertainty that made it shorter."

---

### 6. Escalation ships without the counterweight the owner asked to be prominent

QUESTION: 1 (goal gap)
SILENCE RANK: 6
WHERE: §5 R14 — "Cumulative dose tracking continues regardless."; §12 — "M6 —
History. Session log, weekly and seasonal totals per region" under "Later";
§7 IcarusUI Result — "(specific number, range, per-side times, sub-window,
sunscreen advice, warnings, UVA note, forecast age, links into Learn)".
Against `BUILD_PROMPT.md` §4.5 — "Do not let adaptation imply safety. …
Cumulative dose tracking (§5.5) continues regardless, and the seasonal total
should remain prominent as adaptation climbs."

THE GAP: The owner tied escalation to a visible cumulative total on purpose.
The design keeps the tracking (R14) but drops "prominent as adaptation climbs":
the Result view lists everything except a cumulative figure, and the only place
totals appear is History, which is a "Later" milestone after the MVP that ships
escalation (M5). Built as written, the MVP tells a user "today's session is
longer because your threshold has risen" with no cost figure beside it.

CONSEQUENCE: The MVP's escalation message reads as reassurance — exactly the
"adaptation implies safety" framing the owner forbade — and no §13 criterion
notices, because R24 is evidenced by S10 which checks the History model, not the
result screen.

THE FIX: Add to R13: "Whenever the recommendation is longer than the user's
first session because of adaptation, the result screen shows the season's
cumulative dose for the limiting region beside it ('Front: 41 SED since 1
May'), in the same type size as the recommendation." Move "weekly and seasonal
totals per region" from M6 into M5, and add to S6: "an escalated result carries
the cumulative-dose figure."

---

### 7. A sunscreened three hours and a bare forty minutes are presented as the same answer

QUESTION: 1 (goal gap)
SILENCE RANK: 7
WHERE: §4 use case 3 — "The app solves for 'SPF 30, applied normally' for the
three hours, explains that application thickness matters more than the label
number, and offers the alternative: 40 minutes per side, no sunscreen."; §5
R16 — "still say so when the UVA load is high" (attached only to the
no-sunscreen-needed case); R18 (UVA note keyed only to distance from solar
noon).

THE GAP: The design's honesty goal (and V3) is that costs are stated. By the
design's own Module 3 and Module 8, SPF attenuates the erythemal (UVB-dominated)
dose while UVA protection is separate and typically lower; so a 0.9 MED dose
spread over three sunscreened hours delivers several times the UVA of the same
0.9 MED in forty bare minutes — several times the photoaging for the same
pigment. The design surfaces UVA only by clock position (R18) and only says
"UVA load is high" when no sunscreen is needed (R16). The sunscreen route's
UVA cost has no requirement, no copy key, and no test, and use case 3 offers
the two routes as interchangeable.

CONSEQUENCE: The app's "main differentiator" (build prompt §4.6) quietly
becomes the higher-photoaging route sold as equivalent. Passes S2 and S6.

THE FIX: Add R42: "Whenever a sunscreen solution is offered alongside a shorter
bare-skin sub-window, the result states that the same tanning dose over N times
the minutes carries roughly N times the UVA, names N, and links to Modules 3
and 8; the two are never presented as equivalent." Evidenced by S6: "the
sunscreen outcome carries the UVA-multiple copy key with N computed."

---

### 8. Adaptation's rise rate is nowhere, so S4 is written to pass itself

QUESTION: 1 (goal gap)
SILENCE RANK: 8
WHERE: §5 R12 — "rising with cumulative recent effective dose with diminishing
returns so it saturates, and decaying toward zero with a half-life of about 3.5
weeks (tunable)"; R30's list of tunables (no rise constant); §13 S4 — "six
weeks of regular sessions raises the adaptation factor, saturates below the cap
… a four-week gap after that makes the next recommendation materially shorter
(at least 25%)". Against `BUILD_PROMPT.md` §4.5 — "Type-dependent: types IV–VI
adapt further and faster." and "a single combined decay term is acceptable for
v1, but bias it toward the faster end."

THE GAP: The design gives the ceiling (gain cap) and the fall (half-life) but
not the rise: how many sessions at target take tanState from 0 to, say, 0.8?
"Regular" in S4 is undefined too. The rise rate is the whole plateau feature —
too fast and the app escalates ahead of the real tan (the burn path); too slow
and the plateau it exists to fix persists. Arithmetic shows S4 hinges on it:
with a 3.5-week half-life a four-week gap leaves 45% of tanState; from a
saturated 2.25× that gives a 30% shorter session (passes), from tanState 0.6 a
23% shorter one (fails). So whoever writes the rise constant also decides
whether S4 passes. Two owner instructions were also bent or dropped: "faster
for IV–VI" survives only as "further" (the 3× cap), and "bias decay toward the
faster end" became 3.5 weeks, the middle of the 3–4 range.

CONSEQUENCE: A constant nobody stated, chosen by the agent who wrote the test
that constrains it, decides how quickly the app lengthens sessions. The owner
sees escalation "eventually" and cannot tell whether it tracked the skin.

THE FIX: Add to R12: "tanState rises as a leaky integrator of each region's
effective dose measured in units of that region's current threshold, with a
rise time constant in Tunables (listed in R30) set so that daily sessions at the
standard target reach tanState 0.8 in about three weeks for types I–III — never
faster than the two-to-three-week tanning course in Module 6 — and a
type-dependent rise multiplier (tunable, default 1.5× for IV–VI). The decay
half-life defaults to 3 weeks, the faster end the build prompt asks for." Add
to S4: "'regular sessions' means five sessions per week at the standard target,
stated in the acceptance script; escalation after one week of sessions is
below 25% of the eventual cap."

---

### 9. The second session of the day: warn, or solve against what is left?

QUESTION: 1 (goal gap)
SILENCE RANK: 9
WHERE: §5 R19 — "When a planned or logged session would take a region past 90%
(tunable) of its target, warn; past 100%, warn strongly"; §3 goal — "the day's
remaining budget"; §4 use case 4 — "shows the front is already at 85% of its
budget, and warns when the planned session would pass 90%".

THE GAP: Two builds satisfy R19. Build A: the afternoon recommendation is
solved against the remaining budget per region (front has 15% left, so the
number is small) and the warnings fire only if the user enters a longer window
than recommended. Build B: the recommendation ignores the morning and the
warning does the work, so the headline number for the afternoon is the same 22
minutes as at lunch with a red line under it. Use case 4's wording ("warns
when the planned session would pass 90%") reads as B; the goal's "remaining
budget" reads as A; V2 reads as A. S5 passes either way ("accumulate per region
and trigger the 90% warning").

CONSEQUENCE: Under B the number the user acts on is wrong by the whole morning,
and the app relies on the user reading a warning beneath a confident figure —
the V12 "confident-looking number with no basis" shape.

THE FIX: Replace R19's first sentence with: "The recommendation is always
solved against each region's remaining budget (target minus today's logged
dose), so the headline number already accounts for earlier sessions. When the
user's entered window exceeds that recommendation the result warns at 90% of
the region's target and warns strongly, in Module 7's burn language, past
100%."

---

### 10. Q2 is asked and its answer goes nowhere

QUESTION: 1 (goal gap)
SILENCE RANK: 10
WHERE: §5 R20 — "Q2 (if any redness) 'When did it show up?'"; R21 maps Q1 only.
Against `BUILD_PROMPT.md` §5.2 — "Q2 … helps distinguish genuine erythema from
immediate darkening."

THE GAP: The owner asked Q2 for a reason: immediate pigment darkening (Module
2) appears within minutes and fades by evening and is not a burn. The design
collects the answer, stores it on `SkinReport`, and defines no effect. An agent
will either leave it inert or invent a rule. Either way, a user who reports
"faintly pink" because they looked bronzed at 18:00 is calibrated as if they
had reached their threshold, and their multiplier is pushed down.

CONSEQUENCE: Silent — S10 tests Q1 movements only. The multiplier drifts
downward for users who tan fast, which is safe but is the plateau again, with
no trace in any log of why.

THE FIX: Add to R21: "Q2 reclassifies the report: redness that appeared within
about an hour and had faded by the evening is immediate pigment darkening, not
erythema; the report is calibrated as 'normal' and the confirmation says so
with a link to Module 2. Q2's options are 'within an hour and gone by evening',
'that evening', 'the next morning', 'not sure'." Add to S10: "a 'faint pink'
report with the immediate-darkening Q2 answer moves the multiplier as 'normal'
does."

---

### 11. "Realistic" sunscreen has no ceiling, so the shorten-the-window outcome may never fire

QUESTION: 1 (goal gap)
SILENCE RANK: 11
WHERE: §5 R15 — "When no realistic combination is enough, say so and recommend
shortening the window instead." and §13 S2 — "an attenuation no realistic
pair delivers returns the 'shorten the window' outcome."

THE GAP: The solver's product set is not stated. If "SPF 50, applied thickly"
(effective 50×) counts as realistic — and the build prompt lists it as an output
phrase — then almost any window at any UVI is solvable, and the outcome the
owner wrote for dangerous windows ("recommend shortening the window") is
reachable only in fixtures. Module 8 says of 2.0 mg/cm²: "essentially nobody
does this." If the ceiling is "SPF 50 applied normally" (≈7×), the outcome is
common and useful. S2 passes with whichever fixture the test author writes.

CONSEQUENCE: A user with six hours at UVI 9 is told "SPF 50, applied thickly"
and the app has, in the owner's terms, manufactured a reassuring number.

THE FIX: Add to R15: "'Realistic' means at most SPF 50 applied normally
(effective about 7×). Thick application is never solved for; it is offered
only as a choice the user can select on the calculator, and when they do the
result repeats Module 8's line that almost nobody achieves it." Add to S2: "a
required attenuation of 8 returns the shorten-the-window outcome."

---

### 12. The skin check is per session; two sessions a day break the arithmetic

QUESTION: 1 (goal gap)
SILENCE RANK: 12
WHERE: §5 R20 — "About 20 hours after a session (tunable), a local notification
asks Q1"; R21 — "The implied threshold is divided by the adaptation factor in
force for that region at the session"; R19 — "A user may log any number of
sessions per day."

THE GAP: Skin at 20 hours reports the day's total, not one session's. Built as
written, a user with a 60% morning and a 50% afternoon session gets two prompts
(or one attached to one session — the design does not say), and a "clearly
pink" answer attributed to the afternoon session alone implies a threshold of
0.5 ÷ 1.5 = one third of the estimate — the multiplier crashes toward the 0.5
clamp and the app tells a correctly typed user to revisit their skin type.

CONSEQUENCE: Silent until the first two-session day, then wrong in a way that
looks like a feature ("revisit your skin type"). S10 tests one session.

THE FIX: Replace the quoted R20 clause with: "One skin-check prompt per day
that had sessions, scheduled about 20 hours (tunable) after the day's last
session; its evidence is the day's summed dose per region and the adaptation
factor in force that day. The lasting-colour prompt is likewise per day, and its
answer applies to every region that received at least a tunable fraction
(default 0.5) of its target that day."

---

### 13. What makes a session real: planned, confirmed, or reported?

QUESTION: mega-fork
SILENCE RANK: 13
WHERE: §7 data flow — "A logged session writes a `Session` with per-region dose
and the adaptation factors in force; the day-after `SkinReport` runs through
`CalibrationEngine` to update the shared multiplier and through
`AdaptationModel` to update per-region states." and §9 Session — "whether
planned, logged, or both".

THE GAP: Nothing says how a planned session becomes logged. Three candidate
answers, each reshaping most of M2–M5: (A) an explicit user action — starting
the flip timer, or a "I did this" tap — with editable actual times; only logged
sessions count toward today's dose, adaptation and the prompt schedule. (B)
every displayed result is assumed done: the calculator is a logger. (C) the
day-after report is the confirmation, so tanState only advances for users who
answer notifications. Under B a user who checks the app and stays indoors is
modelled as tanning, escalates, and burns when they finally go out. Under C the
majority who dismiss notifications never escalate — the plateau returns — while
their decay still runs. The data flow sentence reads as C for adaptation and A
or B for the budget, which is the worst mix.

CONSEQUENCE: This decides the Planner's inputs, the `Session` lifecycle, the
`PromptScheduler` trigger, whether the Result screen needs a confirm step, and
what History is a record of. A pseudocode pass guessing wrong has to redo the
UI flow, the data model and the acceptance scripts.

THE FIX: Add to §7: "A `Session` is created as *planned* when a result is shown
and becomes *logged* only by a user action: starting the flip timer, tapping
'I did this' on the result, or answering 'yes' to the skin-check prompt's
opening question 'Did you do this session?'. Actual start and end are editable
at logging. Only logged sessions count toward today's dose, adaptation, and
History; a planned session never logged is discarded at midnight. The skin
check adjusts the multiplier; it is not what advances tanState."

---

### 14. The thin-margin statement for types I and II is not a requirement

QUESTION: 1 (goal gap)
SILENCE RANK: 14
WHERE: §4 use case 8 — "A very fair user runs the calculator. The app gives the
number, says plainly that their margin is thin, and that deciding it is not
worth it is a reasonable conclusion." Against `BUILD_PROMPT.md` §8 — "For type
I and II users, be explicit that their margin is thin and that deciding it isn't
worth it is a reasonable conclusion."

THE GAP: The design demotes an owner instruction from a requirement to a use
case and narrows it from "type I and II" to "the type I user". Coverage is
mechanical over §5 requirement ids; a use case has no id, so no plan is required
to cover it and no criterion evidences it. Type II — the app's worked example
user throughout — loses the statement entirely.

CONSEQUENCE: Passes `coverage.sh`; passes every §13 criterion; a type II user
never sees the one sentence the owner wrote specifically for them.

THE FIX: Add R43: "For skin types I and II every result states, in the same
copy for both, that the margin between a tanning dose and a burn is thin and
that deciding it is not worth it is a reasonable conclusion; the copy does not
push either way. — Evidenced by: S6 (the copy key is present for types I and
II and absent for III–VI)."

---

### 15. At the ceiling: hold the dose, or drop to maintenance?

QUESTION: 1 (goal gap)
SILENCE RANK: 15
WHERE: §5 R14 — "stop escalating and say the user has likely reached their
biological maximum and further dose buys damage without colour."

THE GAP: "Stop escalating" leaves the recommendation at its highest-ever level,
while the same sentence says that dose "buys damage without colour". Module 6
says a sub-threshold dose is "enough to maintain what you have". Two builds:
hold the current target (V1's "grows the dose") or fall to a maintenance dose
(V2, V10, the sentence's own logic). The design says neither.

CONSEQUENCE: The user who has hit their ceiling keeps receiving the largest
sessions the model ever computed, labelled as pointless, with the app's own copy
saying more buys only damage.

THE FIX: Replace the quoted clause with: "stop escalating and drop the
recommendation to a maintenance dose — a tunable fraction (default 0.7) of the
current target — saying the user has likely reached their biological maximum
and that more buys damage without colour; escalation resumes only after a later
'yes' or 'a little' lasting-colour answer."

---

### 16. Six hours from fetch is the wrong clock, and "non-confident" is undefined

QUESTION: 1 (goal gap)
SILENCE RANK: 16
WHERE: §5 R3 — "block confident recommendations on data older than six hours
(tunable)"; §4 use case 9 — "refuses to give a confident recommendation once the
data is older than six hours"; R37 — "degrading with an age indicator rather
than failing".

THE GAP: The offline requirement exists for the beach: fetch at breakfast with
signal, use at 15:00 without. A forecast issued at 08:00 for 15:00 is a
forecast for 15:00; its usefulness does not expire at 14:00. Measured from
fetch time, the six-hour rule blocks precisely the case R37 was written for.
Separately, "block confident recommendations" has two readings: no number at
all (use case 9's "refuses"), or the number with its age and a widened range
(R37's "degrading"). V3 favours the second; V2 the first. The design also never
says when fetches happen, so whether a same-morning fetch is normally refreshed
is unknown.

CONSEQUENCE: The offline story works in the test (S6: "older than six hours
returns the stale outcome") and fails on the beach, which is the only place it
was for.

THE FIX: Replace R3 with: "Show the fetch age whenever the forecast is not
fresh. A forecast is fetched on every foreground and on a location change,
never on window change. Past the staleness limit (tunable, default six hours
from fetch) the result is still computed from the cached curve but its range is
widened by a tunable factor (default 1.5×) and the age moves into the headline;
only a missing forecast shows no number." Add to use case 9: "the number is
shown, shorter and with a wider range, not withheld."

---

### 17. "Next viable window" and "no viable day this season" need inputs the design does not have

QUESTION: mega-fork
SILENCE RANK: 17
WHERE: §5 R17 — "window too weak to matter (with the shortfall and the next
viable window); … no viable day this season" against §9 Forecast — "hourly UVI
series for the day and the next" and §8 decision 12 (no sun-position model
except as a solar-noon fallback).

THE GAP: With two days of forecast, "the next viable window" can only be found
in the next two days, and "no viable day this season" cannot be established at
all. The candidate answers each reshape Data and the Planner: (A) cache
WeatherKit's ten-day horizon and search it, phrasing the outcome as "not in the
next ten days"; (B) add a clear-sky UVI model by latitude and date to Core — a
new engine component with its own constants and its own tests — and say
"season" honestly; (C) keep two days and let the copy say "season" on the
strength of two days, which is V3's "dressing one up as the other". "Viable"
itself has no threshold (what fraction of the target counts as "too weak to
matter"?).

CONSEQUENCE: An agent will most likely build C: the copy key says "this
season", the evidence is 48 hours. Passes S6 with a fixture.

THE FIX: Add to R1: "The cache holds WeatherKit's full hourly horizon (ten
days)." Add to R17: "A window is viable when it can deliver at least a tunable
fraction (default 0.5) of the target. 'Next viable window' is searched across
the cached horizon. 'No viable day' is the outcome when no hour in the horizon
reaches viability, and its copy says 'not in the next ten days' and the
horizon's peak UVI; it never claims a season."

---

### 18. The learning loop has one channel and the user can switch it off

QUESTION: 1 (goal gap)
SILENCE RANK: 18
WHERE: §5 R20 — "a local notification asks Q1"; R11 — "works with the screen
locked via a scheduled local notification".

THE GAP: The goal is to learn the threshold "from day-after reports rather than
from the skin-type prior alone". Every report arrives by notification; a user
who declines the permission, or swipes prompts away, never calibrates and never
advances adaptation (under reading C of finding 13), and the app never says so.
The design has no in-app path to the questions and no statement about denied
permission for the flip timer.

CONSEQUENCE: For a large share of users the app is the "skin-type prior alone"
calculator the goal says it is not, and nothing in §13 notices.

THE FIX: Add to R20: "If notification permission is denied, or a prompt is not
answered, the skin check is asked in-app on the next launch between 12 and 72
hours after the day's sessions, and the lasting-colour question between 3 and
10 days after; Settings shows how many sessions have no report. The flip timer
says before starting that it cannot alert with the screen locked when
notifications are denied."

---

### 19. When the window overshoots, which answer is the headline?

QUESTION: 1 (goal gap)
SILENCE RANK: 19
WHERE: §4 use case 2 — "recommends the earliest 30 minutes per side, 60 total"
(no sunscreen mentioned for a two-hour pool slot); use case 3 — "solves for
'SPF 30, applied normally' for the three hours … and offers the alternative: 40
minutes per side, no sunscreen."; R15 — "When the window's raw dose exceeds the
target, solve for a product and application pair".

THE GAP: Use case 2 leads with a sub-window, use case 3 leads with sunscreen,
R15 says overshoot means solve for sunscreen. The pseudocode pass must pick a
primary outcome for the most common result, and the two candidates order the
Result screen and the Planner's outcome types differently.

CONSEQUENCE: Built sunscreen-first, the app's headline for most afternoons is
the longer, higher-UVA route (finding 7). Built sub-window-first, the "main
differentiator" is the second answer. Either is defensible; the owner should
say.

THE FIX: Add to R15: "When the window overshoots, the headline is the bare-skin
sub-window ('the best 40 minutes per side, no sunscreen'); the sunscreen
solution for the full window is the second answer, with its UVA multiple
(R42). The order is reversed only when the user has marked that they will stay
out for the whole window."

---

### 20. V2's "unsure" never resolves, and V1 versus V2 is unordered where it matters

QUESTION: 2 (vision)
SILENCE RANK: 20
WHERE: `VISION.md` V2 — "When the model is unsure, it errs toward the shorter
session and says why." and V1 — "It grows the dose as their tan grows".

THE GAP: The model is always unsure (the range is never zero), so an agent
reading V2 literally always picks the shorter option and the app never
escalates; an agent reading it as "unsure beyond the normal range" needs a
threshold V2 does not give. The real disagreement this project will hit is the
rise rate (finding 8): V1 says beat the plateau, V2 says be shorter, and V1
is outside the "Priorities, in order" list so nothing ranks them.

CONSEQUENCE: The single most consequential constant in the engine has no
vision tiebreak; two agents citing the vision reach opposite answers.

THE FIX: Replace V2 with: "V2 — Never under-warn. When two defensible answers
differ, the shorter session is shown and the result names the uncertainty that
made it shorter. This bounds V1: escalation that could be either right or early
is late." (Ids are append-only; if editing V2 in place is not wanted, append
this as V15 and note that it governs V1 and V2.)

---

### 21. The banner sits beside the budget warning, and History is unassigned

QUESTION: 2 (vision)
SILENCE RANK: 21
WHERE: `VISION.md` V14 — "An ad next to a number the user acts on. … it never
appears on the result, the flip timer, onboarding, a skin-check prompt, or
Settings." and §5 R39 — "shown at the bottom of the Calculator entry screen and
the Learn module list"; §4 use case 4 — "shows the front is already at 85% of
its budget".

THE GAP: Use case 4 puts a budget figure and a warning on the calculator entry
flow, where R39 puts the banner. V14's principle ("a number the user acts on")
and V14's list disagree at that screen. History (a screen of dose figures) is
on neither list. Two agents citing V14 diverge: one builds the entry screen with
budget bars above the banner, one moves the budget to the result.

CONSEQUENCE: S15 passes (it counts banner slots by view name, not by what is on
the view) and the owner sees an ad under "front: 85% used".

THE FIX: Add to R39: "The Calculator entry screen shows no dose figure and no
warning; today's used budget and its warnings appear on the result screen only.
History carries no banner." And to V14's list, append "History".

---

### 22. Fetch cadence is unstated, and V6's "zero running cost" has a threshold

QUESTION: 1 (goal gap)
SILENCE RANK: 22
WHERE: `VISION.md` V6 — "Zero running cost."; §3 non-goals — "any cost that
scales with users"; §6 — "WeatherKit's included tier (500,000 calls/month with
the developer membership)"; R4 — "recompute only on new forecast or window
change" (which an agent may read as fetch on window change).

THE GAP: The design never says when a fetch happens. At one fetch per app open,
the included tier is roughly ten thousand daily users; on window change it is a
fraction of that. Beyond the tier WeatherKit bills per call — the cost that
scales with users the non-goals exclude. The owner accepted WeatherKit
knowingly, but the cadence that keeps it free is an agent's guess.

CONSEQUENCE: A bill is loud, but late; the cadence is decided silently now.

THE FIX: Add to R1: "The forecast is fetched at most once per hour per
location (tunable): on foreground, on a location change of more than 10 km, and
on explicit refresh; never on window or posture change. At that cadence the
included tier covers on the order of ten thousand daily users, the point at
which V6 needs revisiting."

---

### 23. V5 and V13 collide at the skin-type table

QUESTION: 2 (vision)
SILENCE RANK: 23
WHERE: `VISION.md` V13 — "A skin-type description, or any copy, that is folksy
enough to be misread. Factual, tolerable to a sensitive reader, never
ridiculous." and V5 — "no citation is ever paraphrased, summarised, or
dropped" with §5 R28 — "asks for skin type via the six-row table with plain
factual descriptions" and Module 4's table — "VI | Never burns".

THE GAP: If R28's table is Module 4's table (the only six-row table in the
inputs), it must be verbatim (V5, R26) and it says type VI "never burns",
which is false and, to a type VI reader, the "ridiculous" V13 forbids. If R28's
table is new copy written to V13, an agent writes skin-type descriptions
unattended with no source. Two agents citing the vision diverge.

CONSEQUENCE: Either the onboarding table contradicts V13 or it is agent-authored
copy that V12 would call untraceable.

THE FIX: Add to R28: "The onboarding table is the app's own copy in
IcarusContent, written to V13 and citing Fitzpatrick 1988; Module 4's table is
Learn copy and stays verbatim under V5." (Or the owner edits the Module 4 row in
`LEARN_CONTENT.md`, which is theirs to change — the design must say which.)

---

### 24. "Verbatim" renders `[VERIFY]`, and four citations have no DOI to link

QUESTION: 1 (goal gap)
SILENCE RANK: 24
WHERE: §5 R26 — "renders the twelve modules of `docs/LEARN_CONTENT.md`
verbatim" and "Every citation renders with authors, title, and a tappable DOI
link."; §13 S7 — "the module text equals the corresponding section … after
normalisation".

THE GAP: `[VERIFY]` markers are instructions to the agent that sit inside
module text; verbatim rendering shows them to users, and "after normalisation"
is whatever the test author decides to strip. Four citations (Routaboul —
"No DOI; PMID", McKinlay/Diffey — ISO reference, the EC recommendation, Ledo
1993) have no DOI, so R26's "tappable DOI link" cannot be met for them and an
agent must fabricate, omit, or leave them unlinked — V5 forbids the second.

CONSEQUENCE: Users see "[VERIFY]" in a health app, or citations vanish to make
S7's "with its DOI link intact" pass.

THE FIX: Add to R26: "`[VERIFY]` markers and the document's preamble above
Module 1 are build annotations and are never rendered; S7's normalisation
strips exactly those markers and whitespace. A citation without a DOI renders
its text and any identifier it carries (PMID, ISO number) as plain text, a
PMID may link to PubMed, and absence of a link is never grounds to omit it."

---

### 25. V12's "the user cannot trace" has two audiences

QUESTION: 2 (vision)
SILENCE RANK: 25
WHERE: `VISION.md` V12 — "A rule, a constant, or a line of copy the user cannot
trace to the tunables file, a citation, or a logged report."

THE GAP: Reading A: "the user" means the person holding the phone, which
requires an in-app "why this number" screen the design does not have. Reading
B: it means a reader of the repository. An agent under A adds a feature; under
B adds comments. Both cite V12.

CONSEQUENCE: A quiet scope decision (an explanation screen or not) lands on an
agent.

THE FIX: Append to V12: "'Trace' means a reader of the repository: every
constant in Tunables carries a comment naming its citation or the report it
came from, and every figure on the result screen is reproducible from the JSON
export and the tunables version it carries."

---

### 26. V7 decides nothing

QUESTION: 2 (vision)
SILENCE RANK: 26
WHERE: `VISION.md` V7 — "Simple and elegant. Polish matters; it does not need
to be flashy to be polished."

THE GAP: No two designs disagree about wanting to be simple and elegant. Test:
should the calculator expose the sunscreen application level as a control or
assume "normally"? Should History be a tab? V7 is cited by both sides of both.

CONSEQUENCE: Every layout and scope tiebreak in M3–M6 falls to taste.

THE FIX: Replace V7 with: "V7 — Fewer controls over more options. A choice the
user would make once lives in Settings; a choice they would never make lives in
Tunables; the calculator asks only for the window, the posture, and the cover
toggle, and everything else has a default the result names."

---

### 27. The skin-type quiz has no source

QUESTION: 1 (goal gap)
SILENCE RANK: 27
WHERE: §5 R28 — "an optional short quiz for those unsure".

THE GAP: The quiz's questions and scoring are a rule that maps answers to a
skin type — the prior every number rests on — and no input supplies them. An
agent writes one. V12 calls an untraceable rule unacceptable.

CONSEQUENCE: The single most consequential input to the engine is set, for
unsure users, by agent-authored questions with no citation.

THE FIX: Add to R28: "The quiz is the Fitzpatrick skin-type questionnaire with
its published scoring bands; questions, bands and the Fitzpatrick 1988 citation
live in IcarusContent."

---

### 28. "SPF 30+" as cover contradicts the app's own sunscreen model

QUESTION: 1 (goal gap)
SILENCE RANK: 28
WHERE: §5 R10 — "a single toggle 'head and shoulders covered' (hat, shirt, or
SPF 30+) removes that region from the limit".

THE GAP: R15 says SPF 30 applied normally is about 5.5×, thinly about 2.3×;
R10 says SPF 30 on the face is opaque. With up-and-about doubling the
head-and-shoulders exposure, thin SPF 30 leaves the face near 0.85 of target —
under, but by luck, not by the model, and V12 objects to the rule either way.

CONSEQUENCE: Low risk today; a later tweak to the posture fraction turns the
luck into a burn with no test to notice.

THE FIX: Replace the parenthesis with: "(a hat or a shirt — opaque cover);
sunscreen on the face is the session's sunscreen choice applied to that region
through the R15 model, never a cover."

---

## CLOSED ANGLES

Intent questions probed that the documents genuinely answer; the next reviewer
need not re-walk them.

- Ads versus the original "no network calls except weather": the owner landed
  V6/V11/V14 and R39–R41 themselves (PR #6); the tension is resolved by the
  vision, not open.
- Sensitivity multiplier never decays for season; adaptation does: R21, R12 and
  decision 5 say so unambiguously and S3's separation test evidences it.
- One shared multiplier, three region tan states: decision 3 states it and why.
- Open-Meteo is a named fallback requiring the owner's explicit decision (§6,
  decision 2) — no silent swap is possible under the text.
- "Conservative / standard / aggressive" existing for type I is the owner's
  instruction (build prompt §4.4), not a design invention.
- The per-region attribution of an "all exposed" report is in §11 as an open
  question with a stated default; not restated here.
- "Up and about" front/back fractions being coarse geometry is flagged in §11
  with the request that this review challenge them; the challenge is finding 3
  (the missing region), not the fraction's value, which is a tunable.
- Solar noon from WeatherKit with a formula fallback (decision 12) is closed and
  the engine's input does not change either way.
- Sunscreen is modelled whole-body per session (§9 Session); per-limb is a
  stated non-goal.
- Sub-window search maximising dose per minute is the same as "closest to solar
  noon", so R17's "highest-UVB slice" is consistent with using UVI alone.
- Learn copy is data, one file per module, MarkdownUI isolated in IcarusUI with
  a named fallback (decision 11, §11): closed.
- Prompt delay of about 20 hours sits inside the owner's 18–24 window; four
  days inside 3–5.
- Reading-progress tracking and slow drift of the multiplier for age were
  optional in the build prompt and are legitimately dropped.
- "Two tabs" survives: History and Settings are reachable from Calculator and
  Learn, not tabs of their own (§7 App target).
- No HealthKit, no sunbeds, no pigment measurement: stated non-goals, and the
  Learn copy's sunbed warning is verbatim input.
- Blind test authorship and blind-test trailers (AGENTS.md) mean the simulator
  in findings 1 and 8 will be written from S3/S4's words alone — which is why
  those criteria must carry the response model and the session cadence
  themselves.
