# Pass 2 — reconciled

Inputs: `conceptual-3.md` (blind review of revision 2) and
`implementation-check-1.md` (audit of revision 2 against the pass 1 findings
and the owner's rulings). "C3 #n" is a finding in the blind review; "IC" is
the implementation check (its PARTIAL rows and its cross-cutting list (c)).

## Verdict of the implementation check

40 of 45 accepted items implemented, 4 partial, 0 missing, 0 contradicted,
1 superseded by ruling. All 45 requirement ids covered by criteria.

## Found by both (highest confidence)

| # | Finding | C3 | IC | Ruling |
|---|---|---|---|---|
| P1 | The strong warning line is "target ÷ ceiling", which is MED only when the ceiling binds; for IV–VI burn language fires at 0.83 MED | #4 | A18/C7/X5, (c)2 | Accept: threshold is `MED_personal`, never derived from the target |
| P2 | Tolerant evidence has two homes in R21 (multiplier up vs tanState credit) | #5 | (c)3 | Owner ruling (see below) |
| P3 | "Log" means session in some places and report in others; the calibration and unlock gates count the wrong thing | #3 | (c)7 | Accept: "log" = a skin report; sessions are sessions; all counts count reports |
| P4 | The third logging path (skin-check "did you do this?") can never fire, because the prompt schedules from logged sessions | #2 | (c)6 | Accept: prompt schedules from planned-or-logged sessions; "yes" logs the planned one |
| P5 | "Tan cycle" is undefined and gates the aggressive unlock and the ceiling outcome | #12 | (c)4 | Accept: cycle starts at first logged session after a >2-week gap or a delete; redness bound per region, "all exposed" bounds every dosed region; "season" = current cycle |
| P6 | R6 claims the melanogenic dose binds for type III, but 0.95 > 0.90 so the ceiling binds at standard | #6 (IV–VI inert selector) | (c)1 | Owner ruling (see below) |
| P7 | Which side faces the sun first is never stated | — | (c)5, S5 | Accept: the timer asks "face up first / face down first", default face up; without the timer, face up first |
| P8 | Sunscreen reapplication times were accepted but the timer does not alert at them | — | A8 | Accept: timer alerts at reapplication times |
| P9 | §3 non-goal "never asserts a pigment ceiling" reads against R14's hedged message | — | (c)8 | Accept: non-goal reads "without a redness bound in the cycle (R14)" |

## Found by the blind review only, judged real

| # | Finding | Ruling |
|---|---|---|
| P10 | Every lying-down session plans head-and-shoulders past the burn line: it is credited but never limits (C3 #1) | Accept: every region limits in every posture; the solver shortens both sides until the head-and-shoulders credit fits; the result says how much longer each side could run with cover |
| P11 | The addendum's `headroom` term was dropped without a word (C3 #7) | Owner ruling (see below) |
| P12 | Escalation and gap messages compare minutes, not tolerance (C3 #8) | Accept: trigger on the adaptation factor, not minutes; copy speaks of tolerance and dose |
| P13 | The overshoot outcome carries a permanent warning for users who enter their availability (C3 #9) | Accept: warnings only when "staying the whole window" is marked or the timer runs past the recommendation |
| P14 | The multiplier freezes after a season because n is unbounded (C3 #10) | Accept: n counts reports in the current and previous cycle, capped at `nCap` (20, tunable) |
| P15 | The engine does not take "now"; a window can be in the past; today-only vs any day is open (C3 #11) | Accept: the engine takes the current time; a window is always today; the horizon serves only the next-viable-window search |
| P16 | V12's "reproducible from the export" fails because the record stores no UVI values (C3 #13) | Accept: the session record stores the day's hourly UVI and solar noon as used |
| P17 | The estimate label is on for every result, so it labels nothing; provenance static vs threaded is open (C3 #14) | Accept: static per-figure provenance declared per outcome; label on the figure that depends on the assumption |
| P18 | The user's sunscreen input and the engine's sunscreen answer never meet (C3 #15) | Owner ruling (see below) |
| P19 | Replay reads stored factors or recomputes them (C3 #16) | Accept: replay recomputes factors and targets; stored ones are display records; doses are stored |
| P20 | The range's upper edge is a minutes figure past the burn line (C3 #17) | Accept: upper edge clipped at MED_personal and labelled |
| P21 | The under-dosed outcome keeps the target although V2 says maintenance (C3 #18, #19) | Accept: under-dosed also drops to maintenance; V2 is followed |
| P22 | V15's "personal threshold": the estimate or the truth (C3 #20) | Accept: the estimate; V2 is satisfied by the unlock condition |
| P23 | V7 omits location and forbids release items (C3 #21) | Accept the rewrite |
| P24 | V6 is a constraint filed as a priority (C3 #22) | Accept: V6 moves to core tenets; priorities preamble says tenets are never traded |
| P25 | V13 "any copy" lets an agent soften Learn (C3 #23) | Accept the append |
| P26 | Stopping the timer early does not shorten the record (C3 #24) | Accept |
| P27 | Use case 1 and R15 disagree about the second answer (C3 #25) | Accept: amend use case 1 |
| P28 | Fair skin's first three sessions are at 0.75 MED, which the addendum says does not tan, and the copy does not say so (C3 #26) | Accept the copy sentence |
| P29 | tanState normalised by threshold does not advance equally; normalise by target (C3 #27) | Accept |
| P30 | The Pathak-vs-Wulf conflict belongs beside the constant (C3 #28) | Accept |
| P31 | AdMob in the EEA and UK needs Google's consent flow regardless of personalisation (C3 #29) | Owner to verify; the R39 sentence is added as conditional on the network's requirement |

## Owner rulings needed

1. **P6 — the selector for types III–VI.** As written the selector changes nothing for IV–VI and type III at standard is planned at 0.90 MED like a type II. Proposal: `targetDose = min(melanogenicDose, MED_personal) × ceilingScale` with scale 0.75 / 0.90 / 1.0. Types I–II are unchanged. Types III–VI get conservative / standard / aggressive as fractions of their own tanning dose, and "shorter until the app has learned your skin" becomes true for everyone.
2. **P11 — headroom.** The addendum multiplied the melanogenic dose by a headroom factor. Proposal: omit it, and say so in R6, because aggressive already reaches 1.0 × the tanning dose and V2 prefers the shorter number.
3. **P2 — where a tolerant surprise goes.** Proposal: to the region's tanState first, up to saturation; only the part tanState cannot absorb raises the multiplier, and never above the delivered dose. A user who is truly tougher than their type is learned upward slowly; a tan-driven tolerance decays.
4. **P18 — the user's sunscreen input.** Proposal: it is what they will wear; the first answer is solved for it; the R15 pair is the second answer only when it differs; the logged dose always uses the choice.
5. **P31 — EEA consent.** Confirm Google's requirement. If it holds, the ad package shows the network's consent form once, its calls are declared under V11, and refusal serves limited ads.
