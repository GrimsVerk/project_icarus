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

## Done: screen review fixes F1-F15 (2026-10-30)

Owner ruling (2026-10-29): "do the obvious fixes" = F1-F15; D1-D4 stay the
owner's (untouched). Merged: #46, #45, #47, #49. Checked on main `5350f91`,
Screenshots run 40987923475 (shot names below are in its artifact):

| Fix | Done | Shot |
|---|---|---|
| F1 Calculator in the forecast's zone | yes | 03-calculator 11:15-12:15 = 04-result |
| F2 first side only on the flip timer | yes | 04-result-middle (no line), 05-flip-timer |
| F3 range in minutes | yes | 04-result-middle (23 / 44 minutes) |
| F4 dark mode, largest text | yes | 15-dark-*, 16-large-calculator, 16-large-result |
| F5 44-pt place/refresh, full-width timer | yes | 04-result, 05-flip-timer |
| F6 locked aggressive refused | yes, tests only | `SettingsCeilingTests`; a still can't show a tap |
| F7 History/Settings in Learn's bar | yes | 08-learn-list |
| F8 citation venues grey | yes | 09-learn-module |
| F9 no bar title on modules | yes | 09-learn-module |
| F10 disclaimer switch on its own row | yes (before this run) | 01-onboarding-2-disclaimer |
| F11 walk gaps | yes | 38 shots, incl. 10-skin-check-questions, 12-sheet-*, 13-quiz, 14-* |
| F12 privacy link, weather credit | yes | 07-settings-scrolled |
| F13 day totals in the footer | yes | 06-history, 06-history-past-session |
| F14 one session on the chart | yes | 06-history-past-session |
| F15 Done on every sheet | yes | 06-history, 10-skin-check, 11-lasting-colour |

`../review/icarus-screens.html` is on the owner's desktop; not updated here.

Seen on the way, not F items (left as they are):
- 04-result-scrolled lists "8 more minutes per side with head and shoulders
  covered" twice (once per side, same words).
- 05-flip-timer-running: "The timer cannot start ... That slot has already
  passed": the walk's preview slot is in June 2026, so the timer's own check
  presumably reads the wall clock, not the preview clock. Unchecked.
- The chart's front and back dots coincide when their doses match.
- Nightly `xcode` job: twice the runner had no "iPhone 16" simulator
  (destination is a fixed name, template-owned); a rerun passed. The
  PerformanceTests flake (below) recurred once at 310 ms on a slow runner.
- Screenshots: simulator boots hang now and then; `boot-simulator.sh` erases
  and retries (3 x 5 min). A clean walk is about 11 min.

## Waiting on the owner

- Screen review (2026-10-29): D1-D4 in `../review/icarus-screens.html`
  (the owner's local file) are the owner's call; F1-F15 are done (above).
- Copy (D-2026-10-29-C1): all 186 draft lines are in the app, **provisional**
  (owner OK 2026-10-29, work in progress): `docs/APP_COPY.md` by id,
  `docs/privacy-policy.md`, and PERM-1 in `project.yml`. The owner settles
  lines by id on the Desk; a changed line keeps its id. Then run
  `scripts/build-app-copy.sh` and regenerate the owner's list,
  `python3 scripts/copy-review.py ../review/icarus-copy.html` (add
  `--screenshots <dir>` with an unzipped Screenshots artifact). S17 is not
  met while a line is provisional. For the owner:
  - FIG-8 to FIG-10 say "minutes": since #45 the engine gives the range in
    minutes (F3) and the lines fit as written.
  - FILL-6 ("your location") does not fit `staleFarFromCache` ("The saved
    forecast is for {place}, which is not where you are"); that line shows
    the cached coordinate instead.
  - Agent defaults to confirm: TIM-7's `{side}` is TIM-3/TIM-4 in lower case;
    the skin check's other-product pickers reuse SUN-2 to SUN-6; the Settings
    skin-type page (SET-21) is titled ONB-5 and changes the type without a
    warning; lasting colour stays open after an answer to show LC-4.
- AdMob: the app id and banner unit id (`ADMOB_APP_ID`, `ADMOB_BANNER_UNIT_ID`
  in `project.yml`; now Google's test ids), and a GDPR consent message created
  in the AdMob console: without one Google's form never shows (R39, S16).
- Signing for release: the paid program, a real bundle id (the app's is
  `com.example.ProjectIcarus` in `Signing.xcconfig`), a `DEVELOPMENT_TEAM`,
  and the WeatherKit capability on that App ID. A free Personal Team can
  already run it on the owner's iPhone, without a forecast (README, "Run on
  your iPhone").
- Privacy policy: the text is `docs/privacy-policy.md` (provisional, not
  published). It needs the app's name, a contact address and the date; then
  it is served from this repo's GitHub Pages (turning Pages on is a repo
  setting, the owner's) and `PRIVACY_POLICY_URL` (now example.com) points
  there.
- App icon (1024×1024; no asset catalog yet), the App Store listing copy, the
  privacy-label answers (`docs/release/privacy-labels.md` has one open
  question) and the device criteria S8, S9, S12, S13, S16
  (`docs/release/app-store-listing.md`).

## Next

- The app runs on the owner's iPhone 16 (iOS 26.5.2) since 2026-10-29, as
  `com.grimsverk.icarus.personaldev` on a Personal Team, no forecast. The
  Mac built it with signing overrides on the `xcodebuild` line, not
  `Local.xcconfig`, after keychain fixes; README "Run on your iPhone" now
  has that route. Still untried: `Local.xcconfig` signing a real build.
  Split (owner, 2026-10-29): agents check screens via CI screenshots (and the
  Mac simulator if needed); the owner tests by hand on the phone.
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
