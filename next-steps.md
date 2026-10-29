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

## In progress: screen review fixes (2026-10-29)

Owner ruling (2026-10-29, via Verkmester): "do the obvious fixes" = F1-F15
of `../review/icarus-screens.html`; D1-D4 stay the owner's. Re-check run on
main `b03489b` (copy wired): Screenshots 40937984262. F10 is already done
there (the switch has its own labelled row, ONB-4); Settings already had
Done. The other fourteen still showed.

Open PRs, none merged yet (the machine went down mid-run; macOS CI keeps
running on GitHub). Merge each with `gh pr merge --rebase --delete-branch`
once its CI (Linux) and `nightly.yml -f new_xcode=true` are green:

- #45 `fix/range-minutes-and-ceiling`: F3 (range in minutes, FIG-8 to
  FIG-10, tests `PlannerRangeTests`) and F6 (locked aggressive refused,
  tests in `SettingsCeilingTests`). CI green on 27f5d47; nightly
  40940881849 running. The first nightly caught two bugs, fixed in 27f5d47.
- #46 `fix/screen-polish`: F1, F2, F5, F7, F8, F9, F13, F14, F15. Its
  Screenshots run 40939844348 showed all but F1 working; d77bf34 fixes F1.
  CI, nightly and Screenshots running on d77bf34. #45 and #46 both touch
  `Planner.swift` and `PlannerTests.swift` (different places): rebase the
  second one after the first merges, then rerun CI.
- #47 `fix/screenshot-walk` (draft): F11 (walk gaps) and F12 (preview
  privacy link and stand-in weather credit), plus dark-mode and
  largest-text screenshots. Screenshots run 40940398809 in progress;
  nightly not run yet.

Left to do:
1. F4: read #47's `15-dark-*` and `16-large-*` screenshots, fix what breaks
   on that branch, run nightly, undraft and merge.
2. After all three merge: `gh workflow run screenshots.yml --ref main`,
   then update `../review/icarus-screens.html` in place (each F item fixed /
   no longer needed / not done, new scores, the after-run URL, D1-D4 at the
   top), and clear this section.
3. Copy gaps for the owner: none found; F15 reuses SET-2 ("Done").

## Waiting on the owner

- Screen review (2026-10-29): every screen of Screenshots run 40924394592
  (main `8604dde`) scored against DESIGN, the S criteria and Apple's HIG,
  with 19 proposed fixes (F1-F15 obvious, D1-D4 the owner's call), in a
  local file, `../review/icarus-screens.html` from this repo's parent folder
  (outside every repo; may be deleted once answered). **Fix nothing until
  the owner answers** on the GrimsVerk Desk: "do all obvious fixes" or fix
  ids. Copy problems point at the copy review's ids, not new words. Two are
  bugs found in the code while scoring: F6 (tapping 100% before aggressive
  unlocks saves it, then disables the whole selector) and F3 (the range is
  per-region SED, R7 says minutes on the recommendation).
  The review predates the copy (#40 to #43): its screens had no words.

- Copy (D-2026-10-29-C1): all 186 draft lines are in the app, **provisional**
  (owner OK 2026-10-29, work in progress): `docs/APP_COPY.md` by id,
  `docs/privacy-policy.md`, and PERM-1 in `project.yml`. The owner settles
  lines by id on the Desk; a changed line keeps its id. Then run
  `scripts/build-app-copy.sh` and regenerate the owner's list,
  `python3 scripts/copy-review.py ../review/icarus-copy.html` (add
  `--screenshots <dir>` with an unzipped Screenshots artifact). S17 is not
  met while a line is provisional. For the owner:
  - FIG-8 to FIG-10 say "minutes": with #45 the engine gives the range in
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
