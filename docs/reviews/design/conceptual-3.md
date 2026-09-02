# Conceptual review 3 — project_icarus design intent (blind)

Reviewer: fresh agent, 2026-09-02. Read, in order: `docs/DESIGN.md`,
`docs/VISION.md`, `docs/design-flow.md`, then the owner's inputs
`docs/BUILD_PROMPT.md`, `docs/LEARN_CONTENT.md`,
`docs/MELANOGENIC_THRESHOLDS.md`. Not consulted, by instruction: the earlier
reviews under `docs/reviews/design/`, `docs/DECISIONS.md`,
`docs/DESIGN.oracle.md`, git history. Read-only; no design text changed.

Every finding below traces to one of the two questions (does the design
produce what it claims to want; is the vision a north star) or is a
mega-fork. Findings are ordered by silence rank: 1 is the gap most likely to
survive pseudocode, rulings, tactical review and CI, and reach the owner as a
built thing that is quietly not what they wanted.

## What the promises reduce to

Strip the prose and the design promises one thing: a pure function from
(forecast curve, skin type, learned sensitivity, per-region tan state, today's
logged dose, window, posture, cover, sunscreen choice) to a per-region number
of minutes that lands each region at `min(melanogenic, ceiling) × MED_personal`
and never above `MED_personal`, plus a second sunscreen answer for the whole
window, plus typed edge-case outcomes with copy keys. Around that function sit
three loops: a session becomes real only when the user says so; a next-day
report moves a persistent sensitivity multiplier (down freely, up only when
the user overran the estimate); a decaying tan state raises the target as the
user tans and lowers it after a gap. Everything else — replay from the
history, the Learn tab, the ad banner, the export — is plumbing that keeps
those loops honest, traceable, free, and independently editable. The vision
adds a single ordering that actually bites: when in doubt, the shorter number
wins and the screen says why. Most of the findings below are places where the
requirements, read literally, produce a number that is *not* the one the
loops describe — and where no test in §13 would notice.

---

## Findings

### 1. Every lying-down session plans head-and-shoulders past the burn line

QUESTION: 1 (goal gap) — also a mega-fork for `ExposureModel`
SILENCE RANK: 1
WHERE: §5 R9 — "head-and-shoulders is credited with the face-up dose in full
plus a tunable fraction (default 0.5) of the back-side dose for the
shoulders." and, for the other posture only, "so the session length is
limited by head-and-shoulders." §5 R8 — "Each region carries ... its own
remaining budget, and its own solved time." §4 use case 2 — "credits head and
shoulders with the face-up dose."
THE GAP: In "lying down, turning over" the design solves front and back each
to that region's own target and *credits* head-and-shoulders with front's
dose plus half of back's. It never says head-and-shoulders limits a lying
session. So with equal front and back targets T, head-and-shoulders is
planned at 1.5 T on every lying session. At the standard ceiling that is
1.35 × MED for the face; at conservative it is 1.125 × MED; at aggressive
1.5 × MED. The design's own goal ("Stay under the user's personal burn
threshold") and V15 ("No setting, no adaptation, and no calibration may plan
a dose above the user's personal threshold") are violated by the headline
number of the app's most common use case. The alternative reading — that
head-and-shoulders binds in both postures because R10 says "In either
posture ... removed from the limit" — cannot deliver use case 2 as written,
because then neither side can reach its target unless the head is covered.
The two readings reshape the per-side solve (independent per-side solves
versus a coupled constraint), which is why this is also a mega-fork.
CONSEQUENCE: S5 as written enshrines the credit ("a lying-down session
credits head-and-shoulders with the face-up dose") and tests only that a
*following* session is limited by it. Nothing checks that the lying session
itself keeps head-and-shoulders under threshold. The built app tells a type
II at the pool "20 min per side", the face gets 30 min-equivalent, the
next-day report says "clearly pink" on "all exposed", the calibration takes
the highest-dose region (head-and-shoulders, ratio 1.5) as evidence, finds
the model predicted exactly that, and changes nothing. The app plans a face
burn and confirms its own model, every session, for every lying-down user.
THE FIX: Replace the last clause of R9's lying-down sentence with:
"In every posture the session is limited by whichever region's remaining
budget is exhausted first, head-and-shoulders included, and the cover toggle
is the only thing that removes a region from the limit. In 'lying down,
turning over' the solver therefore shortens both sides until the
head-and-shoulders credit (face-up dose plus the shoulder fraction of the
back-side dose) fits that region's budget, and the result says how much
longer each side could run with the head and shoulders covered." Amend use
case 2 and S5 to match: "each side receives its target dose" becomes "each
side receives the largest dose that keeps every region, head-and-shoulders
included, at or under its budget".

### 2. The third way to log a session cannot happen

QUESTION: 1 (goal gap) — also a mega-fork for `PromptScheduler` and the
`Session` lifecycle
SILENCE RANK: 2
WHERE: §5 R45 — "becomes *logged* only by a user action: starting the flip
timer, tapping 'I did this' on the result, or answering 'yes' to the
skin-check prompt's opening question 'Did you do this session?'" and "a
planned session never logged is discarded at local midnight." §5 R20 — "One
skin-check prompt per day that had sessions, about 20 hours (tunable) after
the day's last logged session."
THE GAP: The skin-check prompt is scheduled from the day's last *logged*
session. A user who reads the number, goes out, and never taps anything has
only a *planned* session, so no prompt is scheduled, so the opening question
that would log it is never asked — and by the time 20 hours have passed the
planned session has been discarded at midnight anyway. Decision 21 chose
this path precisely so that "counting only reports never escalates users who
ignore notifications"; as written the path is dead and those users are
exactly the ones who never calibrate.
CONSEQUENCE: S10 tests "a day with two logged sessions schedules one
skin-check prompt". Every test passes. The largest user segment — people who
look at the number and go — never generates a report, never advances
tanState, and never sees the sensitivity sentence change. Goal 2 ("learn
that threshold from day-after reports") is delivered only to users who
already tap "I did this", and the plateau feature (goal 4) never fires for
anyone else.
THE FIX: Replace R20's first sentence with: "One skin-check prompt per day
that had a planned or logged session, about 20 hours (tunable) after the
day's last such session. When the day has planned sessions that were never
logged, the prompt opens with 'Did you do this session?' (naming the planned
window); 'yes' logs it with its planned times, editable, before Q1 is asked;
'no' discards it." Replace R45's midnight clause with: "A planned session
never logged is discarded when its skin-check prompt is answered 'no' or
when the prompt's in-app window closes unanswered (72 hours), never before."

### 3. "Log" means two different things, and the calibration gate counts the wrong one

QUESTION: 1 (goal gap) — mega-fork for every count in `DerivedState`
SILENCE RANK: 3
WHERE: §5 R7 — "Until the calibration count is reached (`calibrationLogs`,
default 3) the number is computed at the conservative ceiling whatever the
selector says, and the copy says 'shorter until the app has learned your
skin'". §5 R20 — a skin report "counts as one log". §5 R21 — "`weight = k /
(n + k)`" with n unnamed. §5 R23 — "based on 11 sessions". §5 R45 — a
session "becomes *logged*". §8 decision 21 — "user-logged".
THE GAP: The design uses "log" for a logged *session* (R45, D21) and for a
skin *report* (R20). `calibrationLogs`, `aggressiveUnlockLogs`, R21's n, and
R23's "11 sessions" each read plausibly either way. One reasonable agent
counts logged sessions: after three sessions with no reports, the number
jumps from conservative to standard and the copy has claimed the app
"learned your skin" from nothing. Another counts reports. The two builds
differ in when the number rises, when aggressive unlocks, and how fast the
multiplier moves — and both pass S6 ("the number is at the conservative
ceiling before three logs") because the test author picks one meaning too.
CONSEQUENCE: Under the session-count reading, the design's central safety
gate — conservative until the app has evidence — is satisfied by a counter,
and the copy is untrue. Under the report-count reading, "based on 11
sessions" in R23 is wrong. Either way the owner sees a plausible sentence.
THE FIX: Add to R20: "'Log' in this document means a skin report. Logged
sessions are called sessions. `calibrationLogs`, `aggressiveUnlockLogs`, n in
R21's weight, and the count in R23's sentence all count skin reports; a
session day without a report counts toward none of them." Change R23's
example to "based on 11 skin reports".

### 4. The strong burn warning fires where no redness is expected

QUESTION: 1 (goal gap)
SILENCE RANK: 4
WHERE: §5 R19 — "when it would reach the region's personal threshold (target
÷ ceiling) it warns strongly in Module 7's burn language. Both lines are
measured against the threshold, not the target, so the strong warning means
redness is expected."
THE GAP: The parenthetical defines the threshold as target ÷ ceiling. That
is only MED_personal when the ceiling bound; for types III–VI the melanogenic
dose binds (R6), so target ÷ ceiling is 0.75 ÷ 0.90 ≈ 0.83 × MED for a type
IV at standard, and 0.95 ÷ 0.90 > MED for a type III at standard. A type IV
sees "redness is expected" at 83% of their burn dose; a type III never sees
it until 5% past their burn dose. The sentence's own promise — the strong
warning means redness is expected — is broken for four of six skin types.
CONSEQUENCE: Decision 9's stated fear was burn language "learned to be
ignored". The literal formula produces exactly that for darker skin, and the
owner (type II, per the addendum) would never see it on their own device.
S5's test is written from the same formula and passes.
THE FIX: Replace the parenthetical: "when it would reach the region's
personal threshold — MED_personal for that region, never a quantity derived
from the target — it warns strongly in Module 7's burn language."

### 5. Tolerant evidence has two homes

QUESTION: mega-fork (also a goal gap under question 1)
SILENCE RANK: 5
WHERE: §5 R21 — "It moves the multiplier upward only when the delivered dose
was at or above the current estimated threshold for that region (dose ratio
≥ 1.0), and then to an implied threshold equal to the delivered dose, never
higher" and, four sentences later, "Evidence that the skin tolerated more
than the model predicted is attributed to the region's tanState, which
decays". §8 decision 5 — "Evidence the skin tolerated more than predicted
goes to the decaying tan state".
THE GAP: Both sentences describe the same event — a "normal" report at a
dose at or above the estimated threshold — and send it to different places.
Reading A (sentence 2): the multiplier rises toward the delivered dose,
persists, and the [0.5, 1.8] clamp's upper half exists for a reason. Reading
B (sentence 6 and D5): the multiplier never rises from a "normal"; the
region's tanState is bumped instead and decays, so the app can never learn
that a correctly reported user is tougher than their type. Reading B also
requires a mechanism the design never describes — a skin report feeding
`AdaptationModel` — while §7 lists tanState as a function of dose only. The
S3 separation simulation passes under either reading (it checks the
multiplier stays near 1.0; it does not check what moved).
CONSEQUENCE: Under A, the winter-return burn that D5 was written to prevent
is possible again through overruns. Under B, the sensitivity sentence can
say "more sensitive" but never "less sensitive" for a truthful user, the
upper clamp is dead code, and the pseudocode pass must invent how a report
raises tanState (by how much, capped where, replayed how). The pass will
pick one, silently, and every downstream calibration number depends on it.
THE FIX: Choose one and delete the other. If the owner's intent is D5, replace
R21's second sentence with: "A 'normal' report never moves the multiplier
upward. When the delivered dose was at or above the region's estimated
threshold, the excess (delivered ÷ estimated − 1) is credited to that
region's tanState as an additional rise of `tolerantCredit` × excess
(tunable, default 0.5), capped at tanState 1.0, folded into the replay in
report order, and decaying with the ordinary half-life." If the owner's
intent is reading A, delete the sentence beginning "Evidence that the skin
tolerated more" and revise D5 to say the multiplier may rise only to the
delivered dose.

### 6. Types IV–VI get no pre-calibration margin, and are told they do

QUESTION: 1 (goal gap)
SILENCE RANK: 6
WHERE: §5 R6 — "`ceiling` is set by the Settings selector: conservative
0.75, standard 0.90, aggressive 1.0 (tunable)" with "types IV–VI 0.75". §5 R7
— "Until the calibration count is reached ... the number is computed at the
conservative ceiling whatever the selector says, and the copy says 'shorter
until the app has learned your skin'". §8 decision 8 — "V2 says err shorter
when unsure, and before three logs the model is at its most unsure".
THE GAP: For types IV–VI the melanogenic dose (0.75 × MED) equals the
conservative ceiling (0.75 × MED). `min` of the two is 0.75 × MED at every
selector position and at every calibration count. So: the uncalibrated
number is not shorter than the calibrated one; the copy "shorter until the
app has learned your skin" is false for these users; the selector's standard
and aggressive positions change nothing; and the aggressive unlock, when it
arrives, unlocks nothing. Decision 8's V2 argument ("err shorter when
unsure") is applied to fair skin and not at all to the skin types whose
melanogenic fraction the addendum calls "extrapolation off an extrapolation"
— the *most* unsure numbers in the model carry the *least* margin.
CONSEQUENCE: V3 (never dress an estimate as a measurement) is broken by copy
that announces a caution that does not exist. V7's rule that a Settings item
which does not change a number is not added is broken by a selector that is
inert for three skin types. Nobody notices, because every test in S1/S6 uses
a type II or a type IV at a single setting.
THE FIX: Replace R6's ceiling sentence with: "The selector scales whichever
bound binds: `targetDose = min(melanogenicDose, MED_personal) ×
ceilingScale`, with ceilingScale conservative 0.75, standard 0.90,
aggressive 1.0 (tunable) — so 'shorter until the app has learned your skin'
is true for every type, and the selector changes the number for every type.
For types I–II this reproduces the current numbers exactly." If the owner
instead wants IV–VI pinned at the melanogenic dose, add to R7: "For a skin
type whose melanogenic dose binds at the conservative ceiling, the
pre-calibration copy key is absent and the selector is shown disabled with
the copy 'your tanning dose sits below every ceiling'."

### 7. The addendum's `headroom` term was dropped without a word

QUESTION: 1 (goal gap)
SILENCE RANK: 7
WHERE: §5 R6 — "`targetDose = min(melanogenicDose, MED_personal × ceiling)`".
Addendum §5 — "`targetDose = min(melanogenicDose × headroom, MED_personal ×
safetyCeiling)`".
THE GAP: The owner's input multiplies the melanogenic dose by a headroom
factor before the min; the design drops it. For I–II nothing changes (the
ceiling binds). For III–VI the target now sits *exactly* at an estimated
melanogenic threshold that the addendum labels low-confidence. An estimate
of a threshold, dosed at exactly that estimate, undershoots for roughly half
the users; the addendum's own strongest finding is that a sub-threshold dose
"is not merely less effective but useless". The design neither carries the
term nor says why it left it out.
CONSEQUENCE: A type IV user follows the app for weeks at a dose that, for
them, produces nothing; tanState rises anyway (it integrates dose, not
colour), the target escalates with it, and the app only speaks near
saturation with "cannot tell whether the dose is too low or the skin is
done". Goal 3 ("the dose its own biology needs") is delivered to the mean
user and not to the half below it, and the design cannot tell the two apart.
THE FIX: Either restore the term — "`melanogenicDose = MED_personal ×
melanogenicFraction(skinType) × melanogenicHeadroom`, headroom 1.10
(`assumption`: the fraction is a threshold estimate; dosing at its point
estimate undershoots half of users)" — or add one sentence to R6: "The
addendum's `headroom` factor is deliberately omitted: the melanogenic
fractions are already the upper end of the addendum's candidates, and V2
prefers the shorter number." Either closes it; silence does not.

### 8. The escalation and gap messages compare minutes, not tolerance

QUESTION: 1 (goal gap)
SILENCE RANK: 8
WHERE: §5 R13 — "When the recommended session is longer than the user's
first because of adaptation, the result card says so" and "say explicitly
that tolerance has dropped and that today's recommendation is shorter than
what they were doing." §4 use case 5 — "recommends a session materially
shorter than the last one they did".
THE GAP: Minutes depend on the window and the UVI; tolerance does not. A
user whose first session was 8 minutes at noon in July and who now enters an
evening window in September gets a longer recommendation with tanState at
zero — R13's condition is literally met, the message says "your threshold
has risen", and it is false. Conversely the post-gap user whose June sessions
were evening UVI 4 and who returns at noon UVI 9 is told "today's
recommendation is shorter than what you were doing" while the minutes are
longer, and disbelieves the app at the moment it matters most.
CONSEQUENCE: The two messages that carry goal 4's honesty ("say when the
threshold has moved") fire on the wrong signal. S6 tests only that "an
escalated result carries the cumulative-dose figure" — a test author sets up
an obviously escalated fixture and never a noon-versus-evening one.
THE FIX: Replace R13's trigger: "The escalation message shows when the
limiting region's adaptation factor exceeds 1 + `escalationNoticeFraction`
(tunable, default 0.10); the gap message shows when a gap of more than two
weeks has reduced that factor by at least the same fraction from its value
at the last logged session. Both messages speak of tolerance and dose, never
of minutes, and the copy is written so it stays true when today's window
differs from the last one."

### 9. The overshoot outcome carries a permanent warning

QUESTION: 1 (goal gap)
SILENCE RANK: 9
WHERE: §5 R19 — "When the user's entered window exceeds that recommendation
the result warns; when it would reach the region's personal threshold ... it
warns strongly". §5 R15 — "When the window's raw dose exceeds the target,
the headline is the bare-skin sub-window per region".
THE GAP: R19 was written for the two-sessions case (use case 4: "If the user
enters a longer window than that, the result warns") but its wording is
unconditional. Use case 3's three-hour beach window "exceeds the
recommendation" of 40 minutes per side, so the literal build shows the
sub-window headline *and* a warning, and since three hours at the beach also
reaches the threshold, the strong "redness expected" language too — on a
result whose whole point is that the user should stay out for 40 minutes.
CONSEQUENCE: Every user who enters their real availability rather than the
minutes they intend to stay sees burn language on every result. Decision 9's
reason for the strong warning ("never learned to be ignored") is defeated on
day one, quietly, because S5's test ("an entered window past the target
warns") is satisfied by the same behaviour.
THE FIX: Add to R19: "These two warnings apply only when the user has marked
that they will stay out for the whole window, or has started the flip timer
for a duration past the recommendation. Otherwise a window longer than the
recommendation is the R17 sub-window outcome and carries no warning."

### 10. The multiplier freezes after one season

QUESTION: 1 (goal gap)
SILENCE RANK: 10
WHERE: §5 R21 — "Update: `weight = k / (n + k)` with k ≈ 2.5" and "The
multiplier never decays for seasonal change." Build prompt §5.3 — "Mild
recency weighting is acceptable only for genuine drift in intrinsic
sensitivity (age, medication changes), and should be slow."
THE GAP: n is unbounded. After two summers of daily reports n ≈ 100 and a
"red and sore" report (implied ratio 2.5, burn weight 2×) moves the
multiplier by about 0.03. The build prompt allowed slow recency weighting
for genuine drift; the design dropped the allowance and added no cap, so
goal 2's "learn that threshold" becomes "learned it once, in year one".
Only the blistering correction and the clamp can move a veteran user.
CONSEQUENCE: A user who starts doxycycline in year three and reports
"clearly pink" three times moves by less than 0.1 in total. S3 runs 20 logs
and passes; the freeze is only visible after a year of use.
THE FIX: Add to R21: "n is the number of reports in the current and previous
tan cycle, capped at `nCap` (tunable, default 20), so the weight of a report
never falls below k ÷ (nCap + k) ≈ 0.11. This is the build prompt's 'slow
recency weighting' and it is the only recency the multiplier has."

### 11. The engine does not know what time it is

QUESTION: 1 (goal gap) — mega-fork on what a "window" is
SILENCE RANK: 11
WHERE: §1 — "which minutes are best". §5 R11 — "Starting it starts the
session at the actual clock time and recomputes the per-side times from that
start on the cached curve." §5 R45 — "a planned session never logged is
discarded at local midnight."
THE GAP: Only the flip timer is told the clock. The Planner takes a window
and a curve; nothing says it takes "now". A user at the beach at 13:00 who
entered 12:30–13:15 is told the best 18 minutes start at 12:31. Nothing in
R17's edge-case list covers a window that has partly or wholly passed.
Separately, the design never says whether a window can be on a later day
inside the ten-day horizon. Use cases and R45's midnight rule imply today
only; R1's full-horizon fetch and R17's next-viable-window search imply the
user might plan tomorrow. If tomorrow is allowed, "today's remaining budget",
the planned-session lifecycle, tanState at that date, and the prompt
schedule all change shape.
CONSEQUENCE: Fixtures use fixed windows with no clock and pass. The first
real use at a beach produces a recommendation in the past. If the pseudocode
pass guesses "any day in the horizon" it re-plumbs Planner, Session and
PromptScheduler around a date that R45 then discards at midnight.
THE FIX: Add to R17: "The engine takes the current time as an input and never
recommends a minute before it; a window wholly in the past is the 'window
has passed' outcome, and a window partly in the past is solved from now."
Add to §3 non-goals or R1: "A window is always today. The horizon beyond
today serves only the next-viable-window search, whose answer is a day and
hour, never a planned session."

### 12. "Tan cycle" and "season" are undefined, and both drive numbers

QUESTION: 1 (goal gap)
SILENCE RANK: 12
WHERE: §5 R7 — "at least one reported redness in the current tan cycle". §5
R14 — "at least one redness report in the current tan cycle has bounded the
region's threshold from above". §5 R13 — "the limiting region's
season-to-date cumulative dose in SED beside the message in the same type
size as the recommendation". §5 R24 — "weekly and seasonal cumulative dose
per region".
THE GAP: Neither term is defined anywhere. "Cycle" gates the aggressive
unlock and the ceiling outcome; "season" is the figure the build prompt
wants "prominent as adaptation climbs" and R13 shows at headline size. One
agent starts a cycle at the first session after a two-week gap; another at
the first session of the calendar year; another never resets it. One agent's
season is cycle-to-date, another's is year-to-date; the number on screen
differs by a factor of several. R7 counts the redness bound globally, R14
per region — a pink face unlocks aggressive for the back under one reading
and not the other.
CONSEQUENCE: Whichever definitions the pass picks look fine, pass S4/S6, and
ship. The owner sees a season total and cannot tell what it sums.
THE FIX: Add to R14: "A tan cycle begins at the first logged session after a
gap of more than two weeks (R13's gap) or after a history delete, and ends
when the next such gap begins. 'In the current cycle' means since that
start. The redness bound is per region; a report on 'all exposed' bounds
every region that received dose that day." Add to R13: "'Season' means the
current tan cycle; History may also show the calendar year, labelled."

### 13. V12's reproducibility promise is unmet by the data model

QUESTION: 1 (goal gap)
SILENCE RANK: 13
WHERE: `docs/VISION.md` V12 — "every figure on the result screen is
reproducible from the JSON export and the tunables version it carries". §9
Session — "forecast fetch time and place used". §5 R25 — "The export is the
full session and report history plus the Tunables version".
THE GAP: A result figure is a function of the forecast curve, and the record
stores only when and where the forecast was fetched, not the UVI values. A
reader of the repository with the export and the Tunables cannot reproduce a
single minutes figure. The export reproduces *state* (S10 tests that); the
vision demands it reproduce *figures*.
CONSEQUENCE: The one clause of V12 that is testable is untested and false.
When a user reports a burn and the owner wants to see what the app told them
and why, the curve is gone.
THE FIX: Add to §9 Session: "the hourly UVI values and solar noon covering
the session's day, as used, so that the result is reproducible from the
record alone." Add to S10: "a result recomputed from an exported session's
stored curve, profile and Tunables version matches the stored per-region
doses."

### 14. The estimate label is on for every result, so it labels nothing

QUESTION: mega-fork (provenance tracking) — also question 1
SILENCE RANK: 14
WHERE: §5 R30 — "a result that depends on an `assumption` constant is
labelled an estimate on screen." §6 Assumptions — the up-and-about fractions
"and the shoulder fraction are coarse geometric approximations, not
measurements, and are labelled `assumption`"; the density default; the
melanogenic fractions for III–VI.
THE GAP: Every lying-down result depends on the shoulder fraction; every
up-and-about result on the posture fractions; every sunscreen answer on the
density default; every III–VI target on an extrapolated fraction. There is
no result that does not touch an `assumption` constant, so the label is
permanently on and distinguishes nothing. Two implementations also diverge
structurally: (a) a static list of which outcome uses which constants, or
(b) provenance threaded through every engine call so each `DoseResult`
carries the set of constants it read. (b) changes every signature in Core;
(a) is a hand-maintained table that drifts. The design does not say which,
and the pseudocode pass must pick before writing a single engine function.
CONSEQUENCE: Under either, the owner sees "estimate" on every screen and
accepts it as honest (Module 11 says the same), but the sentence in V12 that
was meant to *discriminate* has become decoration, and if (b) was intended
the whole Core API is wrong.
THE FIX: Replace R30's last clause with: "Provenance is static and per
figure, not per screen: Tunables declares each constant's basis, each engine
outcome declares at compile time the constants it reads, and the estimate
label is attached to the individual figure that depends on an `assumption`
constant, naming that assumption in its VoiceOver label and its detail text.
S1 checks the declared set of every outcome against the constants its tests
observe being read."

### 15. The user's sunscreen input and the engine's sunscreen answer never meet

QUESTION: 1 (goal gap)
SILENCE RANK: 15
WHERE: `docs/VISION.md` V7 — "The calculator asks exactly what the engine
needs — window, posture, the cover toggle, a sunscreen choice, and whether
the user stays the whole window". §5 R15 — "The second answer solves the
full window for a product and application pair". §5 R10 — "sunscreen on the
face is the session's sunscreen choice applied to that region through the
R15 model".
THE GAP: The user enters a sunscreen choice; the engine solves for one. The
design never says how they interact. If the user enters "SPF 30, normally"
and the raw window exceeds the target, R15's headline is "the best 40
minutes, no sunscreen" — contradicting what they said they will wear — and
the second answer may recommend a different product. If the user enters SPF
50 thick and the window is short, the headline is a bare-skin number they
will not receive. Two reasonable builds: (a) the input is only for logging
the actual dose; (b) the input is the first thing solved for ("with what you
entered, X minutes"), and the R15 pair is offered only when it differs.
CONSEQUENCE: The build prompt calls the inversion "the app's main
differentiator". Under (a) the result screen argues with the user's own
input on every sunscreen session. Under (b) use case 3's copy keys change.
Both pass S2.
THE FIX: Add to R15: "The sunscreen choice on the entry screen is what the
user will wear. The first answer is solved for that choice (bare skin when
'none'); the R15 product-and-application pair is shown as the second answer
only when it differs from the choice, and the logged dose always uses the
choice. The bare-skin sub-window headline appears when the choice is 'none'
and the raw dose exceeds the target."

### 16. Replay: recompute the historical factors, or read the stored ones?

QUESTION: mega-fork
SILENCE RANK: 16
WHERE: §5 R22 — "Every session record stores the adaptation factor per
region and the target per region in force at the time, so the normalisation
in R21 and the replay in R44 are possible retrospectively." §5 R44 — "replay
that history under the current Tunables to produce the current state" and
"A Tunables change therefore takes effect for every existing user on next
launch." §8 decision 14 — "a fixed bug heals every user's state".
THE GAP: If the replay *reads* the stored factor to normalise each report,
a corrected adaptation constant does not heal calibration for existing
users — the stored (wrong) factors keep normalising the old reports — and
decision 14's promise is only half true. If the replay *recomputes* every
historical factor from the history and current Tunables, the stored factor
is a display record only and R22's "so the replay is possible" is
misleading. The two builds differ in what `Replay` takes and what `Session`
must persist, which is structural.
CONSEQUENCE: The pass will store and read, because R22 says so, and the
owner's first Tunables fix will silently leave every veteran user's
multiplier normalised by the bug.
THE FIX: Add to R44: "Replay recomputes the adaptation factor and target for
every historical session and report from the history and the current
Tunables. The per-session factors and targets stored under R22 are the
record of what the user was shown, used for export and History display,
never as replay inputs. Per-region doses are stored, not recomputed, because
the forecast is not part of the replay."

### 17. The range's upper edge is a number past the burn line

QUESTION: 1 (goal gap) and 2 (V15 versus V3)
SILENCE RANK: 17
WHERE: §5 R7 — "The range is ±30% (tunable) at n = 0." `docs/VISION.md` V15
— "A number past the burn line." V3 — "Say what is uncertain as a range."
THE GAP: The design never says what the range is a range *of* (minutes at
which the user's true threshold might sit? the recommendation's error?) nor
what the user is meant to do with it. At the standard ceiling a +30% upper
edge is 1.17 × MED_personal displayed in minutes beside the number. A
deliberate tanner reads "18 min (13–23)" and takes 23. V15 forbids a number
past the burn line; V3 demands the range; V2 says the range is not how
uncertainty is expressed. Two agents reading these produce a clipped range
and an unclipped one.
CONSEQUENCE: S6 checks that "every result carries a specific number and a
range" and nothing about the edge. The built screen shows a minutes figure
above the burn line on every uncalibrated result.
THE FIX: Add to R7: "The range is the uncertainty in the user's threshold,
shown in minutes. Its upper edge is clipped at the minutes to MED_personal
and the clip is labelled 'redness likely beyond'; the number, not the range,
is what the user is told to do, and the copy says so."

### 18. The ceiling message can never reach the users the protocol is built for

QUESTION: 1 (goal gap)
SILENCE RANK: 18
WHERE: §3 Goals — "say when the biological ceiling is reached". §5 R14 —
"The ceiling outcome requires that at least one redness report in the
current tan cycle has bounded the region's threshold from above." §5 R6 —
"for types III–VI the melanogenic dose binds, so they get a genuine
no-redness protocol."
THE GAP: Types III–VI are designed never to go pink. The ceiling outcome
requires that they did. So the users for whom the app claims to model "the
dose its own biology needs" can structurally never be told they have reached
their ceiling; they get "cannot tell" forever, at the cap (3 × MED_baseline
× 0.75 for IV–VI — a dose the design itself says "buys damage without
colour" once saturated). The gate exists to honour the non-goal "never
asserts a pigment ceiling it cannot see", which is right; but the design
does not say what those users are told to *do*.
CONSEQUENCE: A type IV at saturation with no colour keeps being recommended
the maximum dose with a shrug. The build prompt's "Do not keep lengthening
sessions in pursuit of a result that isn't available" is honoured only for
users who burned.
THE FIX: Add to R14: "The under-dosed outcome recommends the maintenance
dose as well, with copy that says the app cannot tell whether the skin is
done, and that at this tan state a maintenance dose keeps what the user has
while more dose has not produced colour; escalation resumes after a later
'yes' or 'a little'." (See finding 19 for why V2 already requires this.)

### 19. V2 decides the under-dosed outcome, and the design overrode it silently

QUESTION: 2 (vision)
SILENCE RANK: 19
WHERE: `docs/VISION.md` V2 — "When two defensible numbers differ, the shorter
session is the one shown, and the result names the uncertainty that made it
shorter." §5 R14 — "Without that bound the same signals produce the
under-dosed outcome: the app has not yet seen the skin react, so it cannot
tell whether the dose is too low or the skin is done".
THE GAP: Run the tiebreak. Two hypotheses, two defensible numbers: if the
skin is done, maintenance (0.7 × target); if the dose is too low, the target
(the cap forbids more). V2 picks maintenance and says why. R14 keeps the
target. This is the one place in the design where V2 is invoked by the
facts and not followed. Either V2 has an unstated exception ("unless the
shorter number would forgo a tan the user might still get"), or R14 is
wrong. Two agents citing V2 here reach the same answer — maintenance — so V2
is a real north star; the design simply did not consult it.
CONSEQUENCE: A vision statement the design contradicts teaches the next
agent that V2 is negotiable. The oracle, citing V2 mid-run, will flip R14 —
correctly by the vision, but against a design the owner approved.
THE FIX: Either change R14 as in finding 18, or add to V2: "The exception is
an ambiguity between 'more will not help' and 'more is needed': there the
number stays and the copy names both readings, because V1's purpose is a
tan." One or the other; the vision and the design must agree.

### 20. V15's "personal threshold" — the estimate, or the truth?

QUESTION: 2 (vision)
SILENCE RANK: 20
WHERE: `docs/VISION.md` V15 — "No setting, no adaptation, and no calibration
may plan a dose above the user's personal threshold. Aggressive means at the
line, never past it".
THE GAP: The true threshold is unknown; the app has an estimate with a
range. Reading A: "personal threshold" is `MED_personal`, the point estimate;
aggressive at 1.0 × estimate satisfies V15. Reading B: V15 is about the
user's skin, so a dose at the point estimate is above the true threshold for
about half of users, and V2 ("shorter when two defensible numbers differ")
says aggressive must sit at the lower edge of the estimate's range. The
design took A. An oracle citing V15 and V2 together mid-run could take B and
rewrite the aggressive setting. Both readings are reasonable.
CONSEQUENCE: The most safety-loaded sentence in the vision does not decide
the most safety-loaded setting in the design.
THE FIX: Append to V15: "'Personal threshold' means the app's current
estimate `MED_personal`; the estimate's own uncertainty is V2's business, and
V2 is satisfied for the aggressive setting by its unlock condition — a
redness report has bounded the estimate from above."

### 21. V7 lists the calculator's inputs and omits one the engine needs

QUESTION: 2 (vision)
SILENCE RANK: 21
WHERE: `docs/VISION.md` V7 — "The calculator asks exactly what the engine
needs — window, posture, the cover toggle, a sunscreen choice, and whether
the user stays the whole window — and nothing else." and "a Settings item
that does not change a number the user acts on is not added."
THE GAP: Location is what the engine needs most, and R2's manual entry on
permission denial has to live somewhere. Agent A cites "exactly what the
engine needs" and puts a location control on the calculator; agent B cites
"and nothing else" and its explicit list, and puts it in Settings under "a
choice the user would make once" — which location is not, for a user who
travels. The second clause fails the tiebreak in the other direction: the
privacy policy link (R41), attribution (R29), export and delete (R25, R44)
change no number, and an agent citing V7 literally refuses each of them.
CONSEQUENCE: V7 is the statement that governs the UI's shape, and it gives
opposite answers on the first question it will be asked.
THE FIX: Replace V7's last two sentences with: "Location comes from the
device, or on denial from a manual entry reached from the result's place
line; it is never a control on the entry screen and never a Settings item. A
choice the user would make once lives in Settings; a choice they would never
make lives in Tunables; a Settings item is added only if it changes a number
the user acts on or is required for release — attribution, disclaimer,
privacy policy, export, import, delete."

### 22. Zero cost is a constraint filed as a priority, below one that can beat it

QUESTION: 2 (vision)
SILENCE RANK: 22
WHERE: `docs/VISION.md` "Priorities, in order" — V2 "Never under-warn" ...
V6 "Zero running cost." §3 Non-goals — "No paid APIs, subscriptions,
accounts, analytics, or any cost that scales with users."
THE GAP: The list is declared ordered. An agent proposing a paid UVA data
feed to reduce under-warning cites V2 > V6 and is, by the vision's own
ordering, right. The design's non-goal says never. A constraint in an
ordered list of trade-offs is a constraint that can lose. V11 (network
calls) is correctly in Core tenets; V6, which is the same kind of rule, is
not.
CONSEQUENCE: S12 (owner-judged, at release) is the only catch, and it is
late. Mid-run the oracle has a citation for spending money.
THE FIX: Move V6 to "Core tenets" and add to the preamble of "Priorities, in
order": "The core tenets and non-goals are never traded against these
priorities; the order below ranks only what may be traded."

### 23. V13 applied to "any copy" lets an agent soften the Learn tab

QUESTION: 2 (vision)
SILENCE RANK: 23
WHERE: `docs/VISION.md` V13 — "A skin-type description, or any copy, that is
folksy enough to be misread. Factual, tolerable to a sensitive reader, never
ridiculous." V5 — "no citation is ever paraphrased, summarised, or dropped."
THE GAP: Module 1 says "Anyone who tells you otherwise is selling something";
Module 8 measures in shot glasses. An agent citing V13 ("any copy") may
rewrite them; an agent citing V5 may not touch a citation but V5 says nothing
about prose. The design resolved this for one table (R28: Module 4 verbatim
under V5, the app's table under V13) — the vision itself did not, and
"folksy" has no test two agents share.
CONSEQUENCE: The reasonable disagreement is real and the vision gives each
side a citation.
THE FIX: Append to V13: "This applies to app copy (`docs/APP_COPY.md`),
which the owner approves line by line. Learn copy is rendered verbatim
under V5 and is never edited by an agent, folksy or not; an agent who thinks
a Learn line fails this test files it for the owner."

### 24. Stopping the timer early does not shorten the record

QUESTION: 1 (goal gap)
SILENCE RANK: 24
WHERE: §5 R11 — "Starting it starts the session at the actual clock time and
recomputes the per-side times from that start on the cached curve." §5 R45 —
"Actual start and end are editable at logging."
THE GAP: Starting the timer logs the session (R45). The end is the planned
end unless edited "at logging" — which was at the start. The design never
says that stopping the timer, or the session-end alert being dismissed
early, sets the actual end. A user who gets up after ten of twenty minutes
is recorded at twenty, reports "normal", and the record confirms a dose they
did not receive — the tolerant direction, the one D5 says must not be
booked on false evidence.
CONSEQUENCE: Calibration and tanState advance on phantom dose for every
interrupted session, which is most real sessions.
THE FIX: Add to R11: "Stopping the timer sets the session's actual end to
the stop time and re-credits every region on the actual sub-intervals; the
session-end alert stops it; a timer still running at local midnight is
stopped at its planned end and the result says so at the next launch."

### 25. Use case 1 and R15 disagree about the sunscreen second answer

QUESTION: 1 (goal gap)
SILENCE RANK: 25
WHERE: §4 use case 1 — "The result says sunscreen is not needed for the
tanning goal at that dose". §5 R15 — "When the window's raw dose exceeds the
target ... The second answer solves the full window for a product and
application pair".
THE GAP: The lunch-hour window is 45 minutes at midday; its raw dose is well
over the 1.875 SED target, so R15 mandates a second answer ("SPF 15, applied
thinly" for the 45 minutes, with the UVA multiple). The use case shows only
the no-sunscreen line. S18 takes the use case's copy keys as the fixture, so
either the fixture forbids the second answer or R15 does not apply; a test
author will pick whichever makes the fixture pass.
CONSEQUENCE: The first use case the owner reads is not what the requirement
builds.
THE FIX: Amend use case 1: "The result says sunscreen is not needed for the
best 18 minutes, and as its second answer gives the product and application
that would let them stay the full 45, with the UVA multiple, per R15." Or
amend R15 to say the second answer is omitted when the sub-window fits
inside the slot with room to spare — but say which.

### 26. Fair skin's first three sessions are at a dose the owner's evidence calls useless, and the copy does not say so

QUESTION: 1 (goal gap)
SILENCE RANK: 26
WHERE: §5 R7 — "the number is computed at the conservative ceiling whatever
the selector says, and the copy says 'shorter until the app has learned your
skin'". Addendum §2 — "**0.75 MED does not work.** Ten exposures over four
weeks at 0.75 MED induced no pigmentation." §5 R21 — "at or below the target
it is a confirmation and changes nothing."
THE GAP: For types I–II the conservative ceiling is 0.75 × MED — the dose the
addendum reports as producing no pigment. Meanwhile a "normal" report at
that dose changes nothing (R21), so the three sessions are a sensitivity
screen, not learning, and produce no tan. That is a defensible V2 choice; it
is not an honest V3 one unless the copy says it. "Shorter until the app has
learned your skin" implies both learning and a tan that is merely delayed.
CONSEQUENCE: Fair-skinned users — the owner's own type — spend their first
week at a dose the app's own sources say does nothing, told it is learning.
THE FIX: Add to R7: "For types I–II the pre-calibration copy also says that
the first sessions are set below the dose that reliably tans fair skin, on
purpose, so that a first redness report arrives at a low dose; the app
learns from a report that the skin reacted, not from one that it did not."

### 27. tanState normalises by threshold and claims to advance equally at target

QUESTION: 1 (goal gap)
SILENCE RANK: 27
WHERE: §5 R12 — "effective dose is the region's dose after sunscreen
expressed as a fraction of that region's personal threshold at the time, so
a session at the target advances tanState equally for every skin type."
THE GAP: A type II session at target is 0.9 of threshold; a type IV's is
0.75. Normalised by threshold they do not advance equally; normalised by
target they do. The "so" is false as written and the two normalisations
give different rise curves for III–VI. S4 passes under either.
CONSEQUENCE: A quiet choice that sets how fast darker skin escalates.
THE FIX: Replace with: "expressed as a fraction of that region's target dose
at the time, so a session at the target advances tanState equally for every
skin type and ceiling setting; the type-dependent rise multiplier is applied
on top."

### 28. The Pathak-versus-Wulf conflict is not required in Tunables

QUESTION: 1 (goal gap)
SILENCE RANK: 28
WHERE: Addendum §3 — "This is worth stating plainly in the engine's comments,
because the two readings differ by nearly a factor of two and a future
maintainer will otherwise assume one of them is a typo." §5 R6 — "types I–II
1.0 (Pathak & Fanselow 1983, solar spectrum)".
THE GAP: R30 requires a citation beside each constant; the addendum asks for
the *conflict* beside this one. A citation to Pathak alone is exactly the
note that invites a future maintainer to "fix" it toward Wulf's 1.5–1.9.
CONSEQUENCE: Low silence in the sense that it is a comment; high in that a
later tuning pass changes fair skin's melanogenic fraction by a factor of
two on a reasonable reading of the literature.
THE FIX: Add to R6: "The Tunables entry for the type I–II fraction names
both Pathak & Fanselow (solar, ≈1.0, used) and Wulf et al. 2010 (solar
simulator, 1.5–1.9, not used) and says why the solar figure applies."

### 29. AdMob in the EEA needs a consent flow the design says it will not have

QUESTION: 1 (goal gap) — flagged for the owner to verify
SILENCE RANK: 29
WHERE: §8 decision 18 — "non-personalised mode sends no tracking identifier,
so the app needs no 'Allow tracking' prompt". `docs/VISION.md` V7 — "Fewer
controls over more options."
THE GAP: To the best of this reviewer's knowledge Google requires a
Google-certified consent management platform (its UMP SDK) for EEA and UK
users regardless of personalisation mode, and serves at most "limited ads"
without it. That is a consent screen the design never mentions, network
calls to Google's consent service that V11 does not list, and a revenue
outcome in Europe the owner has not priced. The design's "no prompt" claim
is about Apple's ATT, which is a different thing.
CONSEQUENCE: An unattended builder either adds an unplanned screen or ships
without it and the banner does not pay in the owner's own market. S16 is
owner-judged with a live app id and will show a banner in a test region.
THE FIX: Owner to confirm the requirement, then add to R39: "In regions
where the ad network requires a consent form, the IcarusAds package shows
the network's own consent flow once, before the first request, behind the
`AdBannerProvider` protocol; the app declares its consent-service calls
under V11; refusal serves limited ads and never removes the banner slot."

---

## Mega-forks, collected

For the pseudocode pass. Each is open in the design, and a wrong guess
reshapes most of the implementation. Closing sentences are in the findings
named.

- **MF-A — Head-and-shoulders limits lying sessions or not** (finding 1).
  Independent per-side solves versus one coupled solve under three budgets.
- **MF-B — Prompts schedule from planned or logged sessions** (finding 2).
  Session lifecycle, `PromptScheduler`, the midnight rule.
- **MF-C — "Log" is a report or a session** (finding 3). Every count in
  `DerivedState` and every gate that reads one.
- **MF-D — Tolerant evidence goes to the multiplier or to tanState**
  (finding 5). Whether `AdaptationModel` takes reports as input at all, and
  the replay's fold order.
- **MF-E — The window is today only or any day in the horizon** (finding
  11). `Planner`'s budget input, `Session` dates, prompt scheduling.
- **MF-F — Provenance is static or threaded through the engine** (finding
  14). Every Core signature.
- **MF-G — Replay recomputes historical factors or reads stored ones**
  (finding 16). What `Session` persists and what `Replay` takes.
- **MF-H — The user's sunscreen input is a logging fact or the first solve**
  (finding 15). The shape of `DoseResult` and the result screen.

---

## CLOSED ANGLES

Intent questions probed that the documents genuinely answer. One line each.

- Endpoint averaging is forbidden and tested with the owner's own
  counter-example (R4, S1).
- The three threshold terms are stored separately and never collapsed (R5).
- Which MED baseline set: the build prompt's, by ruling; the addendum's is
  reference only (R5, §6).
- The melanogenic fraction is static per band; all exposure history lives in
  the adaptation factor; the two never compound (R6, D19).
- Aggressive is 1.0 × MED_personal and never above, for any type (R6, V15).
- Stale data degrades the number and never withholds it (R3, D23).
- Nothing reasons past the forecast horizon; the app never says "season" of
  the weather (R17, D12, §3).
- The bare sub-window is the headline and the sunscreen route is never sold
  as equivalent; the UVA multiple is named (R15, D22).
- Sunscreen is never cover; the toggle means opaque cover only (R10, D4).
- A session is real only when the user says so (D21) — the principle is
  closed; one of its three mechanisms is not (finding 2).
- Reports are day-level, summed per region, one per day (R20, D15).
- The multiplier never decays for seasonal change (R21) — though it freezes
  (finding 10).
- Upward learning from a truthful "normal" happens only when the user
  overran the estimate; a compliant user is never learned to be tougher
  than their type without a redness report. Deliberate under V2 and D6/D8.
- Q2's immediate-darkening reclassification is explicit (R21).
- Blistering corrects at any n; the clamp prompts a skin-type revisit;
  confounded logs are discounted (R21).
- Types IV–VI adapt faster and further, with a higher cap (R12).
- Learn copy is verbatim; citations are never paraphrased or dropped;
  `[VERIFY]` and the preamble are the only strippable text (R26, V5, S7).
- Module 4's table is Learn copy under V5; the onboarding table is app copy
  under V13 (R28).
- All non-Learn copy is owner-approved data and never a view literal (R42,
  S11, S17).
- The banner is never on a figure; the entry screen carries no figure (R39,
  V14, S15).
- The only network calls are weather, the geocoder that feeds it, and the
  non-personalised banner (V11, R32, D13).
- Zero cost, with the Developer Program as the one carve-out (R33) — filed
  in the wrong section of the vision (finding 22) but unambiguous in intent.
- V2 outranks V3 on range-versus-number: the number moves, the range is
  additional (V2's own wording).
- Nothing blocks iPad, Watch, widgets, or another weather provider (R31,
  D17, D2, V9).
- State is derived; the history is the record; a Tunables change reaches
  every user on next launch (R44, D14) — save the replay-input question
  (finding 16).
- Deleting history means starting over and the app says so (R44).
- The flip timer is the session clock and starts the session at real time
  (R11, D10) — save the stop question (finding 24).
- The day-after prompt is the next day, never the same evening (D15).
- iOS 18 floor, Swift and SwiftUI, SwiftData, five local packages (R31, R34,
  D1, D16).
- The History chart is M6, not MVP; the totals are M5 (R24, §12).
- The Fitzpatrick quiz is optional and its scoring bands are cited (R28).
- Switching to Open-Meteo is an owner decision, never silent (§6, D2).
- "Best minutes" means the shortest contiguous block that delivers the
  target, which on a unimodal curve is the slice nearest solar noon that the
  window permits (R17, Module 3); no split-block search is intended.
- V10 ("never imply safe") is enforced for app copy by the owner's line
  approval (R42) and for Learn copy by verbatim rendering; it never has to
  decide unattended.
- V4 and V8 never decide anything, and harmlessly so: nobody proposes pretty
  over correct or flair over function; V4's operative sentence is the
  release block on the decay test, which is a rule, not a tiebreak.
