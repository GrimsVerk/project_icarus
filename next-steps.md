# Next steps

Work in flight. Write a task here before starting it; delete it when done.
Keep this short enough to read in one go.

## State (2026-10-29, after the move to template v2)

On `main`: M1 core engine, M2 data layer, M4 Learn slice 1 (modules as data).
Built in the 2026-09-03 run but not merged, each branch stacked on the one
before (commits, not PRs; cut before the v2 move, so expect conflicts in
`.github/`, `AGENTS.md` and removed docs: keep v2's side there):

1. `feat/calculator-ui`: M3 slice 1 (copy as data, ad protocol, manifest).
2. `feat/learn-tab-2`: M4 slice 2 (Learn views, swift-markdown-ui, DEP1).
3. `feat/calculator-ui-2`: M3 slices 2-4 (onboarding, calculator, result, timer, Settings).
4. `feat/logging-calibration`: M5 (S10).
5. `feat/history`: M6; carries everything above.
6. `docs/run-followups-20260903` (BL-2: no approved copy for skin-check answers,
   regions, confounders, Learn tab title) and `docs/plan-corrections-20260903`
   (plan fixes, WeatherKit mapping seam). Their pipeline rows (ESC-*) are moot.

IcarusUI, IcarusAds and `App/` on those branches have never been compiled
(written on Linux). Merge them one at a time; the first Xcode build (nightly or
a Mac) will need fix rounds. Plans for them: `docs/plans/`.

## Next

- Owner rules on BL-1 (`docs/BACKLOG.md`).
- Bring `feat/calculator-ui` onto `main` (rebase onto v2 `main`, run the checks, PR).
- M7 release readiness needs the owner's inputs: AdMob app id, WeatherKit
  entitlement and signing, privacy-policy URL.
