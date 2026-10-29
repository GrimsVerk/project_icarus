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

Xcode 26+: a plain ⌘R in the owner's Xcode 27.1 failed because codesign
rejected the SwiftPM resource bundles, which held a top-level `Resources/`
folder. The targets now copy that folder's children (`Package.swift`). The
pinned jobs build unsigned on Xcode 16.4 and cannot see this class of break;
`gh workflow run nightly.yml --ref <branch> -f new_xcode=true` adds a signed
simulator build on `macos-26` (Xcode 26.6) and the `xcode-27` preview image
(27.1, the owner's build). Run it after touching resources or build settings.

Branch rules: the `grimsverk-gates` ruleset makes `feat/**` PR-only after the
first push and undeletable, so don't name work branches `feat/`. Its leftover
`feat/screenshots` is merged and can only be deleted by the owner.

## Waiting on the owner

- Copy (BL-2, S17): a draft of every missing line is with the owner as a
  local file, `../review/icarus-copy.html` from this repo's parent folder,
  outside every repo (it may be deleted once answered). It has 186 lines with
  ids by screen (TAB, CALC, RES, FIG, FILL, SUN, PLACE, TIM, DID, SKIN, LC,
  HIST, SET, ONB, QUIZ, LEARN, VO, PERM) plus the privacy policy text
  (PRIV-1 to PRIV-11). The owner answers on the GrimsVerk Desk: "all OK" or
  the ids to change. Then add the approved lines to `docs/APP_COPY.md` and
  `CopyKey` and wire them in one planned change. Nothing is approved until
  then. The lines tagged "needs a small code change" also need behaviour:
  `{application}` renders the enum (`applied normal`), `{effect}` gets a bare
  number, the skin-check questions have no headings, import replaces the
  history with no warning, and Settings has no skin-type row, though the
  approved `revisitSkinType` line sends the user there.
- AdMob: the app id and banner unit id (`ADMOB_APP_ID`, `ADMOB_BANNER_UNIT_ID`
  in `project.yml`; now Google's test ids), and a GDPR consent message created
  in the AdMob console: without one Google's form never shows (R39, S16).
- Signing: a real bundle id (`bundleIdPrefix` is `com.example`), a
  `DEVELOPMENT_TEAM`, and the WeatherKit capability on that App ID.
- Privacy policy page URL (`PRIVACY_POLICY_URL`; now example.com). Its text
  and the location purpose string (PERM-1) are in the copy draft above. The
  policy still needs the app's name and a contact address.
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
- `PerformanceTests` (S14) times the slowest of 100 plans with wall-clock
  `Date` against 100 ms; on a shared macOS runner one plan once took 271 ms
  and failed the nightly (a rerun passed). Flaky, not slow code: a fix would
  bound the median or a high percentile instead of the maximum.
- Release risk: the pinned CI jobs build on `macos-15`'s Xcode 16.4, and App
  Store uploads need a current Xcode SDK, so a release build cannot come from
  that pin. The pin is the template's; Verkmester handles it there. Until then
  `gh workflow run nightly.yml --ref <branch> -f new_xcode=true` builds signed
  on Xcode 26 and 27.
