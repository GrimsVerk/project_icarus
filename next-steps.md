# Next steps

Work in flight. Write a task here before starting it; delete it when done.
Keep this short enough to read in one go.

## State (2026-10-29)

On `main`, built and tested on macOS (nightly) and Linux (CI), all green:
M1 core engine, M2 data layer, M3 calculator UI (slices 1-4), M4 Learn
(slices 1-2), M5 logging and calibration (S10), M6 history.

The five stacked UI branches from the 2026-09-03 run landed as three merge PRs
(#26, #28, #29) plus one lint fix (#27): `feat/calculator-ui` already held
`feat/learn-tab-2`, and `feat/logging-calibration` already held `feat/history`.
Fixes needed: two swiftformat 0.64.4 rewrites, one SwiftLint brace, jq in the
`core-tests` job (S11 needs it), and one macOS test (a one-ulp span end, fixed
by the run's own `18bf77c`). The old `feat/*` branches are fully contained in
`main` and can be deleted.

Local format and lint without Docker or Swift: the Linux release binaries of
swiftformat 0.64.4 and SwiftLint 0.65.1 (`gh release download`) match CI. Tests
need CI: `gh workflow run ci.yml --ref <branch>` and `gh workflow run
nightly.yml --ref <branch>` both work on any branch.

The two September docs branches are on `main` too (BL-2 in
`docs/BACKLOG.md`, the plan corrections in `docs/plans/`); they can be deleted.

## Waiting on the owner

- BL-1 ruling (`docs/BACKLOG.md`).
- BL-2 copy (`docs/BACKLOG.md`): no approved `docs/APP_COPY.md`
  lines for the skin-check answers and timings, the regions, the confounders,
  the lasting-colour answers and the Learn tab title. Until then the views show
  enum names as words. Copy is owner-approved line by line (S17).
- M7 release inputs: AdMob app id, WeatherKit entitlement and signing,
  privacy-policy URL, and a real bundle id (`project.yml` has `com.example`).

## Next

- In progress (branch `feat/screenshots`): a manual CI job (GitHub-hosted macOS) that runs the app in a
  simulator and uploads every main screen as a run artifact. Run it, look,
  fix what is clearly broken. Found before the first run: nothing opens
  onboarding, the Learn list (the tab is `Color.clear`) or the flip timer, and
  the `icarus://` scheme the Result's Learn links use is not registered. Wiring
  them in the same branch.
- M7 release readiness (`docs/plans/release-readiness.md`) as far as it goes
  without the owner's inputs.
