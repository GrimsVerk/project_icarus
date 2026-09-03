# Decisions — project_icarus

ADR-lite. One dated entry per decision, newest at the bottom. A recorded ruling
is never silently reversed: to change one, argue it in chat, wait for the owner,
then append a superseding entry. History is never rewritten.

The entries below shipped with the template — rulings the template's owner made
once so every generated project does not re-ask them. They bind here like any
other entry: to change one for this project, supersede it.

## 2026-08-16 — Waiting is mechanical, and belongs to the driver

Resolves the open question `/deliver` step 4 used to carry (idle vs poll vs
scheduled wake-up). The wait is not agentic: a **driver** — deterministic
tooling, not a model — invokes one headless session per phase and waits between
phases on `gh pr checks --watch`-style polling, so no model budget is spent
watching CI. Run it locally (`.claude/scripts/deliver-loop.sh`) or from a
Claude Code web session (`/deliver-loop`); the mode is chosen explicitly by
which entry point you start. The exit condition stands as previously decided:
wait until **no check is still pending**, never until the pull request is no
longer open — a failing pull request never leaves the open state, so the second
condition makes red indistinguishable from still-running.

## 2026-08-16 — Mid-run authority: the design layer rules, the oracle rules it

Plans derive only from the design layer. When new work surfaces mid-run, it
enters through the chain — the oracle amends `docs/DESIGN.oracle.md` on its own
pull request, a plan follows on its own pull request, then code — never
directly. Uncertainties a plan raises are handled by risk class, judged by a
contract test: **HIGH** if the candidate answers change slice boundaries,
Signatures blocks, external formats or schemas, or anything expensive to
reverse — and when unsure, that doubt itself makes it HIGH. High-risk: the
planner files the question in `docs/BACKLOG.md` and waits for the oracle's
ruling. Low-risk: the planner proceeds on a recorded default and the oracle
reviews it next cycle. Attended runs keep the original behaviour: the owner
rules. The owner steers unattended runs by editing `docs/VISION.md` and
`docs/DESIGN.md`, and reviews at the end.

## 2026-08-16 — Unattended runs act as a GitHub App, not as the owner

A user PAT shares the owner's per-hour API budget with every tool acting as
that user, and the built-in Actions token cannot trigger workflows from its own
events — both were hit in practice. A GitHub App has its own rate-limit budget,
its events fire workflows (so merged branches actually get deleted), and pull
requests it opens are authored as the app, which makes "opened by the owner"
(`.github/scripts/owner-authored.sh`) mean exactly that. Fallback when no App
is configured: `AUTO_MERGE_TOKEN`, then the Actions token plus the nightly
branch sweep.

## 2026-08-16 — The budget ceiling is subscription percentage points, and it halts

An unattended run stops — it does not degrade to a cheaper model or a smaller
scope — when it has consumed its allowance, measured in percentage points of
the owner's subscription rate limit from the run's start. Because that probe is
best-effort, two hard backstops always also apply: a pull-request count and a
wall-clock limit. A loop that quietly gets worse when it runs low is harder to
diagnose than one that stops and says why.

## 2026-08-18 — After a merge, the other open pull requests are updated for you

Branch protection here requires branches to be up to date, so the moment one
pull request merges every other open one becomes unmergeable however green it
is. GitHub calls that `BEHIND`, and it is not a check — it never appears in the
checks list, so the pull request shows a column of green ticks and simply does
not merge. Auto-merge does not rescue it either.

So `auto-merge.yml` updates them: on a merge, `gh pr update-branch` over every
other open pull request in this repository. It **never fails** — a real conflict
is reported and left for a human, not turned into a red check on a pull request
that did nothing wrong — and it **will not run on the built-in Actions token**,
because a push made with that token creates no workflow runs, so the branch
would come up to date with its required checks permanently missing. That is
worse than being behind. Configure the App (`scripts/setup-github.sh --app`);
without it, the run summary says so and nothing is touched.

## 2026-08-19 — Two credentials, total: the App, and the review token. No PATs.

The owner's ruling, taken to reduce setup: a project configures exactly one
GitHub credential — the App (`APP_ID` + `APP_PRIVATE_KEY`) — and one Anthropic
credential — `CLAUDE_CODE_OAUTH_TOKEN` for the review gate. Everything GitHub
needs beyond the built-in Actions token is minted from the App at use time:
`template-sync` mints a read-only token scoped to the template repository
(which is why the App must be installed there too), the driver mints its
pull-request identity per request, and a web session mints `gh`'s token per
turn. `TEMPLATE_TOKEN` and `AUTO_MERGE_TOKEN` are gone, deliberately without
fallbacks — a fallback that must be set up defeats the point of having less to
set up, PATs expire and fail every project at once, and a PAT acts as the
owner, which hollows out `owner-authored.sh`. The App stays at exactly
Contents RW, Pull requests RW, Checks RO: never Administration or Secrets, or
the unattended driver could edit its own gates.

## 2026-08-27 — The design hardening loop: pseudocode is the attended plan

The owner's ruling set for the attended path, taken in one working session and
built as `docs/design-flow.md`. Between the design doc and the build sit a
conceptual adversarial review, one pseudocode pass over the whole design, the
owner's batched rulings, and a tactical adversarial review of the settled
result. Attended plans are pseudocode-bodied (`format: pseudocode`): a
lint-capped header carries only what pseudocode cannot express — intent,
non-goals, owner costs — and open questions never land in a plan; they are
ruled in batch, folded in (losing fork branches deleted), and recorded here,
the plan keeping a `Rulings:` receipt line. Each slice splits into a
Signatures contract — all the blind test-writer sees, enforced structurally by
`spawn-worker.sh --strip-internals` — and pseudocode Internals for the coder.
Mid-pass, a structural fork (the HIGH-risk contract test) is branched locally
with effort shrinking in branch count, a trunk chosen, and the pass continues
on the trunk; five-plus plausible branches are listed with two-sentence cases,
not implemented. Review cadence: one conceptual plus one tactical is standard;
a level gets a second pass only when landing its feedback made structural
changes; hard cap two per level, past it only the owner opens more. The
claimed payoff — fewer mid-run oracle rulings — is measured: every run report
carries `oracle-rulings: <n>`. The unattended path is unchanged throughout.

<!-- Append project decisions below, newest at the bottom. -->

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
