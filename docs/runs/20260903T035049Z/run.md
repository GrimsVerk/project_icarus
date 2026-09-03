# Run 20260903T035049Z — unattended delivery, web lane

- **Base branch:** `main`. **Driver:** `/deliver-loop` in this Claude Code web session. **Engine:** `claude` (opus-5: coder medium, test-writer high) through `spawn-worker.sh`, up to five workers at once.
- **Start:** 2026-09-03T03:50:49Z. **Stop:** 2026-09-03T07:25Z (this report); **limit:** the owner's 5 h 15 min wall clock (deadline 09:05:49Z), the only limit given; a web session has no usage gauge.
- **Steering documents:** `docs/DESIGN.md` 38238a6, `docs/VISION.md` 1350caa at start; unchanged during the run.
- **Machine record:** `events.jsonl` beside this file — 92 events, 43 dispatches, 44 results (one non-zero: a test-writer killed after 41 minutes with no output, then re-dispatched successfully). Worker logs in `workers/`, the review gate's payloads and replies in `reviews/`.
- **Build order:** the owner's stated order (core-engine → data-layer → learn-tab S1 → calculator-ui S1 → learn-tab S2 → calculator-ui S2–4 → logging-calibration → history). The detector's alphabetical pick (`calculator-ui`) was recorded on the iteration-1 `detect` event and overridden.
- **oracle-rulings:** 0 (no oracle was dispatched; one uncertainty was filed, BL-1).

## Before the run (03:00–03:50, attended by the owner)

- The container had no Swift toolchain. `download.swift.org` answered, so Swift 6.0.3 (Ubuntu 24.04) was installed; swiftformat (0.55.5, then 0.63.0 to match the macOS runner) and SwiftLint 0.57.1 were built from source. Every worker built and tested on Linux before committing.
- **ESC-1** found, fixed and proven: `open-pr.yml`'s freshness guard reads the push event's per-commit file lists, which arrive empty for pushes from this hosted session, so the App never opened a pull request here (runs 33708809589 and 33708881917 skipped the open step). The fix also diffs the pushed head against its parent; a probe branch proved it (run 33709131837 reached the open step). The owner opened and merged #11 (the row), #12 (the fix) and #13 (`docs/APP_COPY.md`, S17).

## Iterations

| # | Phase | Outcome |
| --- | --- | --- |
| 1 | ORCHESTRATE core-engine | Five slices; coder + blind test-writer per slice in separate worktrees; tests merged first. 303 tests. Assembly reconciliations below. |
| 2 | WAIT #14 | PR #14 opened by the App (autogrims[bot]) at 05:14Z. macOS `test` failed on formatting (swiftformat 0.63 vs 0.55 locally) — fixed with the runner's version. Every CI check green since 05:28Z: test, test-the-tests, acceptance-criteria, plan, secrets, template-sync, core-tests. `review` BLOCK on the `.github/workflows/ci.yml` edit the plan names as an owner cost. Second review round dropped the S3-bound finding to a note. #14 waits for the owner's override merge. |
| 3–11 | WAIT #14, building ahead | With one pipeline PR per base, the remaining milestones were built on a chain of branches off `feat/core-engine` and pushed WITHOUT pull requests. Linux CI (`core-tests`) was green on every push. |

## What exists now

| Branch | Contents | Linux tests | Head |
| --- | --- | --- | --- |
| `feat/core-engine` (PR #14) | M1, all five slices | 303 | 9a833ce |
| `feat/data-layer` | M2, four slices | 416 | 7d27920 |
| `feat/learn-tab` | M4 slice 1 (modules as data, S7) | 447 | 9ae14c3 |
| `feat/calculator-ui` | M3 slice 1 (copy as data, manifest, environment, S11, S15) | 457 | a6efb46 |
| `feat/learn-tab-2` | M4 slice 2 (the Learn views, MarkdownUI) | 457 | c06072f |
| `feat/calculator-ui-2` | M3 slices 2–4 (onboarding, calculator, result, timer, Settings) | 457 | 73c08e4 |
| `feat/logging-calibration` | M5, three slices (S10) | 481 | f6b5990 |
| `feat/history` | M6, three slices; carries everything above | 481 | 2c07a8b |

Each branch is chained on the previous one, so each pull request's diff is its own milestone once the one before it has merged. **Every IcarusUI, IcarusAds and `App/` file is uncompiled**: Linux has no SwiftUI. Those were written against the iOS 18 SDK by careful reading; the macOS `test` job is their first compiler and fix rounds there are expected.

Not started: M7 release-readiness (needs the AdMob app id, the WeatherKit entitlement and signing, a privacy-policy URL — the owner's inputs) and the acceptance pass (nothing has merged yet).

## Assembly disagreements (the blind split doing its job)

Every case where the blind tests and the code met and disagreed, and which side moved. Commit messages carry the same reasoning.

- core-engine S1: a test asserted the literal zone name "UTC"; Linux Foundation spells it "GMT" → test (a9919a1).
- core-engine S4: the code followed the plan's Internals ("thick enough" only when the user picked thick); R15/S2 and the owner's revision-3 ruling say offer a thicker layer of the user's label when enough → **code** (98b4b73). Plan corrected on `docs/plan-corrections-20260903`; ESC-2.
- core-engine S2: a fixture unlocked aggressive from the all-time redness count; R7 needs a bound in the current cycle → test (6342f42).
- core-engine S3: notice tests fed undecayed regions (R44 hands out decayed state) → test; the gap notice measured from pre-session fields could never be inclusive at one half-life (T5) → **code** (cbf06be); blister formula `× 0.8` was the tester's invention → test; an ordering fixture → test; the 0.7×-gain separation bound 0.10 → 0.15 → test + **BL-1** (both independent simulations settle near 0.88 under the ruled constants).
- core-engine S5: the headline minutes did not declare the `uviMinutesPerSED` read (R30) → **code** (6864aaf); use case 5's gap was ten minutes short of the inclusive half-life → test.
- data-layer S2: a substring search for "Europe/Paris" in raw JSON (Foundation escapes the slash) → test. S3: a discard cutoff before the 72 h in-app window closed (R45) → test. S4: three `await`s inside `XCTUnwrap` autoclosures (compile) → test.
- learn-tab S1: an undeclared `ExpressibleByIntegerLiteral` on `ModuleID` broke the contract's failable init → **code**; a test expected the inter-module `---` rule inside a module → test.
- calculator-ui S4 / history S1: both slices reached `App/RootTabs.swift`; the entry screen owns its own navigation stack, so the shell's History and Settings controls sit in a row above it (assembly commits on `feat/calculator-ui-2` and `feat/history`).

## Plan and process defects found (for the owner)

1. **ESC-2** (row on `docs/run-followups-20260903`): plan pseudocode contradicting the design (core-engine S4) and one field with two meanings (S3), caught only at assembly, not by the two tactical reviews.
2. **ESC-3** (same branch): formatter version drift between the local hook and the macOS runner (18 files red on the first PR).
3. **BL-1** (in #14): S3's 0.10 separation bound is unmet under the ruled constants (0.88); the test holds 0.15 until the oracle rules. The review gate's second round accepted the disclosure; the owner decides (comment on #14).
4. **BL-2** (`docs/run-followups-20260903`): no approved copy for the skin-check answer options, the timings, the regions, the confounders, the lasting-colour answers, or a Learn tab title; the views show enum names as words meanwhile.
5. Acceptance scripts must be named `S<n>.sh` (`acceptance-criteria.sh`); six plans said otherwise — corrected on `docs/plan-corrections-20260903`, which also lands the S4/S3 Internals fixes and the WeatherKit mapping seam the built code carries.
6. The `docs/plans/*.md` "as revision 2" promise references contradict revision 3 in two places (cache reason, lasting-colour scheduling); revision 3 was built.
7. `SwiftLint` config changed twice by workers (`trailing_comma` off; identifier excludes; `file_length` ignoring comment-only lines) — not a gate path, each explained in its commit.

## Anomalies

- One test-writer (calculator-ui S4) produced nothing for 41 minutes (log = header only); killed and re-dispatched, then finished normally in 20 minutes.
- Workers were run five at a time on a four-core container without incident.
- The review gate saw only the 20 smallest files of #14 (its size cap); it said so.

## What the owner does next

1. Override-merge **#14** (`review` blocks on `ci.yml` by design; everything else is green). Decide BL-1 (keep 0.15 pending the oracle, or say so and 0.10 is restored).
2. Add `core-tests` to the ruleset (it has run green on every push).
3. Open and merge the two docs branches (the App cannot open a second PR while #14 is open): `docs/run-followups-20260903` (ESC-2, ESC-3, BL-2) and `docs/plan-corrections-20260903`.
4. Then the driver (or you) opens the chain in order: `feat/data-layer`, `feat/learn-tab`, `feat/calculator-ui`, `feat/learn-tab-2`, `feat/calculator-ui-2`, `feat/logging-calibration`, `feat/history` — one at a time; the first macOS build of the UI branches will need fix rounds.
5. Supply for M7: AdMob app id, WeatherKit entitlement/signing, privacy-policy URL.
