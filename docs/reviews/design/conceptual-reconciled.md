# Conceptual reviews 1 and 2 — reconciled

Two independent reviewers attacked the same draft of `docs/DESIGN.md` and
`docs/VISION.md` (after PR #6). Neither saw the other's report. This file maps
their findings onto one list so the owner rules once. "R1 #n" and "R2 #n" are
finding numbers in `conceptual-1.md` and `conceptual-2.md`.

## A. Found by both reviewers (highest confidence)

| # | Finding | R1 | R2 | Where they differ | Recommended ruling |
|---|---|---|---|---|---|
| A1 | A "normal" skin report is a point estimate (0.7), so a correctly typed user is walked up to the burn line; S3's simulator is unspecified | #1 | #1 | Same fix in substance | Accept: "normal" is a lower bound that only confirms or raises; the simulated reporter's response bands are a fixture in S3 |
| A2 | One target fraction for all skin types contradicts Learn Module 5; no melanogenic threshold in the engine | #7 | #2 | Numbers: R1 three bands (I–II / III / IV–VI), R2 two bands (I–II / III–VI) | Accept R1's three bands plus `melanogenicFraction(skinType)`; owner sets the numbers |
| A3 | The seasonal cumulative total was pushed to M6; the owner asked for it "prominent as adaptation climbs" | #8 | #6 | None | Accept: total on the result card beside the escalation message, in M3/M5 |
| A4 | MEGA-FORK: what makes a session real (planned / timer / logged / reported) | #5 | #13 | Same trunk | Accept: only a user-logged session counts (timer start, "I did this", or skin-check confirm); plan expires at midnight; report moves the multiplier, logging moves tanState |
| A5 | MEGA-FORK: "next viable window" and "no viable day this season" need a UV horizon the two-day cache cannot give | #18 | #17 | R1: two days + a static seasonal UVI table; R2: cache WeatherKit's ten-day horizon and never claim "season" | Accept R2: ten-day horizon, copy says "not in the next ten days" |
| A6 | V2 ("err shorter") vs R7 (number at the target); uncertainty is displayed, never acted on | #9 | #5, #20 | R1: conservative until the first report; R2: conservative until 3 logs; both rewrite V2 to be decidable | Accept R2's 3-log calibration count and the V2 rewrite; upper edge of the range narrows only with redness reports (R1) |
| A7 | Two sessions in a day give two skin checks about one skin | #14 | #12 | None | Accept: one skin check per day on the day's summed dose per region |
| A8 | The sunscreen route hides its UVA cost; which answer is the headline on overshoot | #13 | #7, #19 | R2 adds: bare-skin sub-window is the headline | Accept both: bare sub-window first, sunscreen second with its UVA multiple, reapplication times, Modules 3 and 8 linked |
| A9 | Notification denied → the learning loop never runs | #17 | #18 | None | Accept: in-app fallback for both prompts; Settings shows unreported sessions |
| A10 | Fetch cadence is unstated; "zero running cost" depends on it | #16 | #22 | None | Accept: fetch at most hourly, on foreground / >10 km move / explicit refresh, never on window change |
| A11 | The type I *and II* thin-margin line was dropped to a use case | #3 (part) | #14 | None | Accept R43 as a requirement with a copy key, evidenced by S6 |
| A12 | Decay half-life set to the midpoint the build prompt said not to use; rise rate absent; IV–VI "faster" dropped | #20 | #8 | R2 also defines the rise constant and "regular" in S4 | Accept: 3.0-week half-life, leaky-integrator rise with a stated time constant, 1.5× rise for IV–VI, "regular" = 5 sessions/week in S4 |
| A13 | V7 decides nothing | #23 | #26 | Same replacement | Accept: "Fewer controls over more options…" |
| A14 | V12's "trace" is ambiguous; a Tunables entry is not a basis | #24 | #25 | R1: every constant carries a citation or `assumption`; R2: "trace" means a repository reader | Accept both sentences |
| A15 | V14/R39: the Calculator entry screen may carry a number under the banner; History unassigned | #21 | #21 | None | Accept: entry screen is inputs only; History carries no banner |
| A16 | Citations without a DOI; `[VERIFY]` markers would render; V5 forbids the corrections S13 requires | #22 | #24 | None | Accept: markers never render; non-DOI identifiers render as given; corrections limited to identifiers and listed |
| A17 | The cover toggle: what dose is logged, and "SPF 30+" is not a cover | #15 | #28 | R1: log at √30 attenuation; R2: only opaque cover counts, sunscreen on the face goes through R15 | Accept R2 (opaque cover = zero dose for that region); sunscreen is the session's sunscreen choice |
| A18 | Budget warnings: the 90% line fires on every standard session; the second session must be solved against what is left | #10 | #9 | R1: warn past target, strong at threshold; R2: keep 90%/100% of target | Accept: solve against remaining budget (R2); warn when the entered window exceeds the target and strongly at the threshold (R1), so the burn language means redness is expected |

## B. Found by one reviewer, judged real

| # | Finding | Who | Recommended ruling |
|---|---|---|---|
| B1 | Sensitivity/adaptation separation is asserted, not learned; tolerant model error lands in the never-decaying multiplier | R1 #2 | Accept: tolerant evidence → tanState (decays), sensitive evidence → multiplier (persists); S3 runs with true gain at 0.7× and 1.3× the model |
| B2 | Every non-Learn user-facing word is unwritten and will be authored unattended | R1 #3 | Accept in principle: `docs/APP_COPY.md` before M3, rendered through IcarusContent, owner criterion S17. Ruling needed on who drafts (agent drafts, owner approves line by line, is the proposal) |
| B3 | MEGA-FORK: stored mutable state vs replayed/derived state | R1 #4 | Accept replay: the log is the record; state is derived under current Tunables; export = history + tunables version |
| B4 | No use case is a fixture | R1 #6 | Accept S18: each §4 use case is an acceptance fixture |
| B5 | S3's 0.03 outlier bound is unachievable with k = 2.5 | R1 #11 | Accept the replacement bounds and the weight cap at 1.0 |
| B6 | The ceiling message cannot tell "at maximum" from "under-dosed" | R1 #12 | Accept: ceiling outcome requires a redness bound in the cycle; otherwise the under-dosed outcome |
| B7 | The cached forecast is for wherever the phone last had signal | R1 #19 | Accept: stale when >25 km from the cache's location |
| B8 | Head and shoulders receive no dose while lying down | R2 #3 | Accept: face-up side in full, 0.5 of the back side for shoulders (tunable); cover toggle in both postures |
| B9 | MEGA-FORK: one per-side figure vs per-region solved times; equal times are unequal doses on a sloping curve | R2 #4 | Accept: solve per region over its own sub-interval; one figure when within 15%, else two; timer alerts at the first side's end |
| B10 | Q2 is asked and goes nowhere | R2 #10 | Accept: immediate darkening reclassifies the report as "normal" |
| B11 | "Realistic" sunscreen has no ceiling | R2 #11 | Accept: at most SPF 50 applied normally; thick application is user-selected only |
| B12 | At the ceiling: hold or drop to maintenance | R2 #15 | Accept: drop to a maintenance fraction (0.7, tunable) until a later "yes / a little" |
| B13 | Six hours from fetch is the wrong clock; "non-confident" undefined | R2 #16 | Accept with a note: this bends the build prompt's "block confident recommendations" into "show it shorter, wider, with the age in the headline". Owner ruling needed |
| B14 | The onboarding skin-type table vs Module 4's "never burns"; the quiz has no source | R2 #23, #27 | Accept: onboarding table is app copy citing Fitzpatrick 1988; quiz is the Fitzpatrick questionnaire; Module 4 stays verbatim |

## C. Rulings only the owner can make

1. **Target bands per skin type** (A2): three bands (R1) or two (R2), and the numbers.
2. **Forecast horizon** (A5): ten-day cache (R2, recommended) or two days plus a seasonal table (R1).
3. **Stale forecast** (B13): refuse a number past six hours (build prompt), or show a shorter, wider one with the age in the headline (R2, recommended).
4. **App copy** (B2): who writes `docs/APP_COPY.md`. Proposal: agent drafts, owner approves every line; S17 is an owner criterion.
5. **Calibration count before the number leaves conservative** (A6): first report (R1) or three logs (R2, recommended).
6. **State model** (B3): replayed (recommended) or stored.
7. **Warning lines** (A18): strong warning at the threshold (R1, recommended) or at 100% of target (R2).

## D. Structural consequences

Landing A4, A5, B3, B9 changes milestone content, the `Session` lifecycle, the
result contract, and the Data layer. Under `docs/design-flow.md` that earns a
second conceptual pass. Two review files already exist because two reviewers
ran in parallel on the same draft; a pass on the revised draft would be
`conceptual-3.md` and is the owner's call to open.
