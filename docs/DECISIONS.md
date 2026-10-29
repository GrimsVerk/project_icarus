# Decisions — project_icarus

Settled decisions and owner rulings, oldest first (this file predates the
template's newest-first default; keep appending at the bottom). Don't
relitigate them; to change one, the owner rules and a superseding entry is
added. Ids like `D-2026-09-03-F1` are cited from code, tests and docs.

The design-review files cited below (`docs/reviews/design/`) were removed when
the project moved to template v2; they are in git history before that move.

## 2026-09-02 — Design revision 2: the owner's rulings on the stage 2 reviews

Two conceptual reviews (`docs/reviews/design/conceptual-1.md`, `-2.md`,
reconciled in `conceptual-reconciled.md`) were landed into `docs/DESIGN.md`
and `docs/VISION.md` with these owner rulings, each one line:

- **Target per skin type is a formula, not a table.** `targetDose =
  min(MED × melanogenicFraction(type), MED × ceiling)`; fractions static per
  band (I–II 1.0, III 0.95, IV–VI 0.75, `assumption`-labelled per
  `docs/MELANOGENIC_THRESHOLDS.md`); the addendum's table is reference only.
- **MED baselines are the build prompt's** (III 3.0, IV 4.5 SED), the more
  conservative set. The addendum's 3.5 / 5.0 are never used. Explicit so no
  later agent substitutes them.
- **Forecast horizon = whatever WeatherKit forecasts**, `forecastHorizonDays`
  default 10, confirmed on the first live fetch. Nothing reasons past it; the
  app never says "this season".
- **Stale data degrades, never refuses.** Heads-up with the age at 3 h, warning
  at 6 h, range widened, recommendation reduced by `staleReduction` (5%,
  tunable). This bends the build prompt's "block confident recommendations".
- **App copy:** agent drafts `docs/APP_COPY.md`, owner approves every line
  (S17, owner criterion).
- **Conservative until calibrated:** the number sits at the conservative
  ceiling until 3 logs; then the selected ceiling with its range.
- **Derived state, not stored.** The history is the record; state is replayed
  under current Tunables. Deleting the history means starting over and the app
  warns so.
- **Warning lines:** plain past the target, strong (Module 7 language) only at
  the personal threshold.
- **Aggressive = at the line, never past it**, unlocked after 5 logs with at
  least one redness report in the current cycle.
- **Second conceptual pass, later:** two agents — one blind on the revised
  draft, one checking every accepted finding was actually implemented.

## 2026-09-02 — Design revision 3: the owner's rulings on the pass 2 reviews

A blind conceptual review of revision 2 and an implementation check of the
pass 1 findings (`docs/reviews/design/conceptual-3.md`,
`implementation-check-1.md`, reconciled in `conceptual-reconciled-2.md`) were
landed with these owner rulings, one line each:

- **The scale applies to whichever bound binds.** `targetDose =
  min(melanogenicDose, MED_personal) × ceilingScale`, scale 0.75 / 0.90 / 1.0.
  Types I–II unchanged; III–VI get the selector as fractions of their tanning
  dose, so it is never inert.
- **Headroom omitted, in writing.** The addendum's factor is left out because
  aggressive already reaches the full tanning dose and V2 prefers shorter.
- **A tolerant surprise goes to tan state first**, up to saturation; only the
  remainder raises the multiplier, never above the dose tolerated.
- **The engine prescribes sunscreen; it never asks what the user has.** "I
  don't have that SPF" re-solves honestly with what they can manage: thicker
  application if enough, otherwise less time and shade, never more frequent
  application as a substitute for a higher label.
- **EEA/UK ad consent** is the owner's understanding to confirm; the
  network's consent flow is designed in behind the ad protocol.
- **Every region limits in every posture**, head-and-shoulders included; a
  credited region that never limits is a planned burn.
- **Vitamin D is a possible future goal** for skin types IV and up. Not now;
  the target is a protocol seam so it slots in later without reorganising
  the code (M8, decision 26).
- The remaining accepted findings (log = skin report; prompts from planned or
  logged sessions; tan cycle defined; threshold = MED_personal; window is
  today and the engine takes the clock; n capped; replay recomputes; range
  clipped at the line; under-dosed drops to maintenance; per-figure
  provenance; timer stop shortens the record; V6 is a tenet; V7, V13, V15
  made decidable) are recorded in the design text itself.

## 2026-09-03 — Pseudocode pass, batch 1: the owner's rulings (all trunks)

Stage 5 of the design flow. Each id is cited by the plans' `Rulings:` line.

- **D-2026-09-03-F1** — One root `Package.swift` with five library targets under `Sources/<Target>` and `Tests/<Target>Tests`; app shell in `App/`; `project.yml` references the local package at `.`. Not five separate packages.
- **D-2026-09-03-F2** — The coupled lying-down solve shrinks both sides by one scalar found by bisection until the head-and-shoulders credit fits. Not a linear programme.
- **D-2026-09-03-F3** — Tan state updates per event, closed form: decay by elapsed time, then a leaky-integrator rise; τ solved offline so 21 daily standard sessions reach 0.8 for types I–III. Not a day-by-day loop.
- **D-2026-09-03-F4** — Learn module files are generated from `docs/LEARN_CONTENT.md` by a script and committed; S7 fails on drift. Not hand-split copies.
- **D-2026-09-03-F5** — XCTest everywhere. Not Swift Testing.
- **D-2026-09-03-F6** — Engine and content tests run on a Linux CI job (`core-tests`); macOS keeps the app build. The owner adds `core-tests` to the ruleset after its first green run.
- **D-2026-09-03-F7** — Copy keys are a Swift enum in Core; text comes from `docs/APP_COPY.md` through a generated JSON; S11 checks both directions. Not string keys.
- **D-2026-09-03-F8** — The flip timer asks which side is up first, default face up; without the timer, face up.

## 2026-09-03 — Tactical review 1: rulings that touch design text (approved by the owner)

Four findings in `docs/reviews/design/tactical-1.md` could not be fixed in the
plans alone. The recommended fix was applied to `docs/DESIGN.md` and the
owner approved all four explicitly ("rulings seem fine", 2026-09-03). These
are owner rulings, not agent defaults; do not reopen them.

- **D-2026-09-03-T1** — The tan-state rise constant is solved together with the decay the engine applies (τ ≈ 7.2 d), the half-life is labelled `assumption` against Module 6's 4–8 week fade, "near saturation" is the tunable `plateauTanState` (0.75), and the escalation notice fires when the factor has risen by a fraction (0.5) of the type's maximum rise, not 0.10 above 1. Without this the plateau outcomes were unreachable and the notice fired on session two.
- **D-2026-09-03-T2** — S4's "one-week rise below 25% of the cap rise" becomes 40%: a single-exponential rise that reaches 0.8 in three weeks is at about 32% after five sessions.
- **D-2026-09-03-T3** — Use case 3 no longer names "SPF 30" and "four times": the SPF ladder with normal application cannot produce all three of the use case's numbers on one curve; the fixture asserts the ladder's answer for its curve and the UVA multiple is named as N.
- **D-2026-09-03-T4** — An "all exposed" report takes the highest-dose region when the answer is "normal" and the lowest-dose region when it is redness; a report on a day with no logged dose is never calibrated. Closes the §11 open item.

## 2026-09-03 — Tactical pass 2: rulings and dependency approvals (approved by the owner)

Findings in `docs/reviews/design/tactical-2.md` and `implementation-check-2.md`
that touch design text or the dependency rule. Applied on the pass-2 branch
and approved by the owner explicitly on 2026-09-03: T5, T6, DEP1 and DEP2 are
owner rulings, not agent defaults; do not reopen them.

- **D-2026-09-03-T5** — The gap notice is relative: it fires when a gap of more than two weeks has undone at least `escalationNoticeFraction` of the rise the factor had achieved, inclusive at the half-life boundary. The absolute rule never fired for the three-to-four-week gaps in use case 5 and S4.
- **D-2026-09-03-T6** — Supersedes T2: S4's one-week bound is 50% of the cap rise. The rise solved with the decay (T1) is 0.47 after five sessions; T2's 32% was the no-decay figure.
- **D-2026-09-03-DEP1** — Dependency approved: `swift-markdown-ui` 2.4.1 (MIT), for the Learn tab. Apple's `AttributedString` markdown renders no tables and two modules carry them. Isolated in IcarusUI.
- **D-2026-09-03-DEP2** — Dependency approved: Google Mobile Ads SDK with its User Messaging Platform (Google's licence), for the banner in non-personalised mode and the regional consent form. The only network with fill in non-personalised mode. Isolated in IcarusAds behind `AdBannerProvider`.
- Also landed in the plans without design text: every region limits and the whole-window lying split is half/half in side order; the solver never returns zero minutes; today's dose resets per day in replay; maintenance is solved before the sunscreen; `.nothingRealistic` never pairs with the stay headline; sessions store the intervals actually faced and the prescribed pair; Tunables reads are recordable and provenance is per band; day ids carry the zone; the range is centred on the target and widens when stale; the learned multiplier moves from itself under an override; confounded credits are discounted; two cycle starts are kept for the report window; export enums carry string raw values; the environment lives in IcarusUI; Linux builds only the non-UI targets.

## 2026-10-29 — Licence: PolyForm Shield 1.0.0 (owner ruling)

- **D-2026-10-29-L1** — The owner licensed the project under PolyForm Shield 1.0.0 ahead of making the repository public. `LICENSE` carries the official text verbatim, preceded by `Required Notice: Copyright 2026 GrimsVerk (https://github.com/GrimsVerk)`. This is the owner-placed `LICENSE` the AGENTS.md licensing rule refers to: never remove or second-guess it. No `license` field is added elsewhere (Swift packages have none). Outside contributions need a CLA first; until one exists, no outside code merges.

## 2026-10-29 — Moved to template v2

- **D-2026-10-29-T1** — The project follows grimsverk-template v2 (v1.0.1): no unattended pipeline, oracle, review gate or ceremony checks; fresh sessions, `next-steps.md` as memory, plan mode. CI runs only on pushes to `main`: `ci.yml` (gitleaks, swiftformat and SwiftLint in pinned images, and `core-tests`: `swift test` plus `acceptance/S*.sh` in the official `swift:6.0.3-noble` image) and `nightly.yml` (Xcode build and tests on macOS). Why: summer CI ran 9-23 times per merged PR, and `swift-actions/setup-swift@v2` does not support the Ubuntu 26.04 runners. F6 still holds; its ruleset step is moot because no check gates PRs any more.

## 2026-10-29 — S3's separation bound (owner ruling)

- **D-2026-10-29-S3** — Closes BL-1. In S3's separation simulation, a user whose true adaptation gain is 0.7× the modelled one keeps the multiplier within 0.15 of 1.0 after six weeks, not 0.10; the 1.3× case stays at 0.10. Under the ruled constants (D-2026-09-03-T1) the estimate settles near 0.88: the escalating dose crosses the slower-adapting user's line and two faint-pink reports move the multiplier, as R21 attributes them. It errs short (the estimate drops, never rises). The owner accepted 0.15 on 2026-10-29 and noted it may change later.
