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
BL-1 is closed (D-2026-10-29-S3).

Screenshots: `gh workflow run screenshots.yml --ref <branch>` walks the app on
the preview environment in a simulator and uploads every main screen as the run
artifact `screenshots` (`Tests/Screenshots`). The first runs found, and #31/#33
fixed: onboarding, the Learn list and the flip timer were never opened, the
`icarus://` scheme was not registered, History and Settings could not be
tapped, and the Calculator's top half was blank.

M7 (`docs/plans/release-readiness.md`), as far as it goes without the owner:
the AdMob provider with Google's consent flow (slice 1), the WeatherKit
entitlement, attribution and privacy policy link (slice 2, no live check),
the privacy manifest and the release checklists in `docs/release/` (slice 3,
no copy). Owner inputs are build settings in `project.yml`, now Google's test
ids and an example.com page.

Branch rules: the `grimsverk-gates` ruleset makes `feat/**` PR-only after the
first push and undeletable, so don't name work branches `feat/`. Its leftover
`feat/screenshots` is merged and can only be deleted by the owner.

## In flight (2026-10-29)

- Copy draft for the owner (Verkmester's task): every line with no approved
  `docs/APP_COPY.md` text (BL-2, the bare symbols, posture names, Result
  labels, VoiceOver, the location purpose string) plus a privacy policy text,
  as one local HTML file outside the repo (`../review/icarus-copy.html`
  beside the GrimsVerk repos). Nothing goes into the app or `APP_COPY.md`
  until the owner approves.
- Record the owner's remove-ads ruling in `docs/DECISIONS.md` (small PR).

## Waiting on the owner

- BL-2 copy (`docs/BACKLOG.md`): no approved `docs/APP_COPY.md`
  lines for the skin-check answers and timings, the regions, the confounders,
  the lasting-colour answers and the Learn tab title. Until then the views show
  enum names as words. Copy is owner-approved line by line (S17).
- More copy the screenshots show missing: every control is a bare symbol (the
  Calculator's inputs, the tabs, History, Settings, the onboarding arrows, the
  timer), the posture picker shows `upAndAbout` / `lyingTurning`, and the
  Result's figures are labelled by key (`remainingBudget · front`). VoiceOver
  labels (S9) need the same lines.
- AdMob: the app id and banner unit id (`ADMOB_APP_ID`, `ADMOB_BANNER_UNIT_ID`
  in `project.yml`; now Google's test ids), and a GDPR consent message created
  in the AdMob console: without one Google's form never shows (R39, S16).
- Signing: a real bundle id (`bundleIdPrefix` is `com.example`), a
  `DEVELOPMENT_TEAM`, and the WeatherKit capability on that App ID.
- Privacy policy page URL (`PRIVACY_POLICY_URL`; now example.com) and its text
  (R41).
- The location permission's purpose string
  (`INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`): it is copy. Without it
  iOS never asks and the app falls back to manual places.
- App icon (1024×1024; no asset catalog yet), the App Store listing copy, the
  privacy-label answers (`docs/release/privacy-labels.md` has one open
  question) and the device criteria S8, S9, S12, S13, S16
  (`docs/release/app-store-listing.md`).

## Next

- Small things the screenshots show, none of them blocking: the History chart
  is an empty box with one session; times on the Calculator are in the device's
  zone and on the Result and History in the place's (the simulator runs in UTC,
  the preview place is Oslo).
- Once the owner's inputs arrive: fill `project.yml`, run S16 on a device,
  TestFlight.
