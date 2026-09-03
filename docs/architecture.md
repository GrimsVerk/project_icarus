# project_icarus — Architecture

<!-- The living description of what exists RIGHT NOW. Updated at the end of every
slice (AGENTS.md, "Architecture doc"), so it describes the system as built, never
as planned. `docs/DESIGN.md` is the intent and doesn't change; this changes.

Keep it at the level of LOGIC, NOT CODE. -->

The app is one Swift package (`Package.swift`) plus a thin app shell in `App/`.
The package holds five library targets; `project.yml` builds the iOS app from
the shell and the package's UI product.

As of Slices 1, 2 and 4 of the `core-engine` plan, the engine has its
foundation — the shared value types, the constants table, and dose
arithmetic over a forecast curve — and, on top of it, the budget and the
solver (what each region may take today, and the session that fits inside
it) and the sunscreen answer. The other four targets are placeholders.

## Components

| Component | Responsible for |
| --- | --- |
| `IcarusCore` | The whole engine, as pure functions over values. No network, no storage, no system services. Imports Foundation and nothing else. |
| `IcarusCore` / models | The shared vocabulary: days, windows, regions, skin types, sunscreen, forecast curves, session and skin-report records, copy keys, figures. |
| `IcarusCore` / `Tunables` | Every tunable constant, each readable only through an accessor that reports its key, plus one basis (citation or assumption) per number. |
| `IcarusCore` / `DoseCalculator` | Dose arithmetic against the clock: how long a target takes, the best block of a window, viability, the next viable window, the UVA-heavy flag, and the "window has passed" clip. |
| `IcarusCore` / `SunscreenSolver` | The sunscreen answer: what to wear for the whole window, the UVA multiple, the reapplication times, and the re-solve with whatever the user actually has. |
| `IcarusCore` / `TargetModel` | What one region may take today: the two thresholds, the scale actually applied, the uncertainty range, and what is left after earlier sessions. `TargetGoal` is the seam a second goal slots into. |
| `IcarusCore` / `ExposureModel` | The posture geometry — who gets what dose lying down or up and about — the one attenuation function, and the solver that turns a window into a session. |
| `IcarusData` | Placeholder. Will own persistence and the forecast cache (M2). |
| `IcarusContent` | Placeholder. Will own generated copy and Learn content (M3). |
| `IcarusUI` | Placeholder. Will own the SwiftUI surface (M4). Not built on Linux. |
| `IcarusAds` | Placeholder. Will own the ad banner behind a protocol (M7). Not built on Linux. |
| `App/` | The iOS app shell. Depends only on `IcarusUI`. |

Two things follow from the layout and are deliberate. `IcarusCore` depends on
nothing, so the engine is testable on Linux and in CI without a simulator. And
`IcarusUI` and `IcarusAds` are declared only under `#if !os(Linux)` in the
manifest, so a Linux build sees exactly Core, Content and Data.

## Data flow

The engine is given data; it never fetches any.

- A caller supplies hourly UVI samples, a place, a time zone and a fetch time
  → `ForecastCurve`, which integrates them once into a one-minute prefix
  integral of SED. Every later dose question is two lookups and a subtraction.
- `ForecastCurve` --(SED over an interval)--> `DoseCalculator`.
- `DoseCalculator` --(minutes, windows, flags)--> the target and exposure models
  (Slice 2, not yet built).
- The whole window's raw dose and the remaining budget of the hardest-pushed
  region --> `SunscreenSolver` --(a label and application, or an honest
  "shorten the window")--> the result. The solver is pure and holds no state.
- `DoseCalculator` --(minutes, windows, flags)--> `ExposureModel`.
- A profile and a replayed `DerivedState` --(per region)--> `TargetModel`, which
  answers one `RegionTarget` per region: the budget, the range around it, and
  the two thresholds behind both.
- Those targets, a window, a posture and the clock --> `ExposureModel.solve`,
  which answers one `ExposurePlan`: the stretches to spend outside, what each
  region takes from each, which region limited the session, and how much longer
  it could run with the head and shoulders covered.
- `Tunables` --(constants, and the key of every constant read)--> everything.
  A `Tunables` created with `recording(_:)` reports each read to a sink; a
  `Figure` carries the set of keys its number came from, and is marked an
  estimate when any of them is an assumption.
- `ForecastCurve` --(one day's samples)--> `StoredCurve`, the external form kept
  inside a session record and inside the export. `StoredCurve.curve()` rebuilds
  a curve that answers the same dose questions.

Days carry their zone. `DayKey` is a calendar date plus a time-zone identifier,
and its string form — `2026-09-03@Europe/Oslo` — is the only day identity used
anywhere, including notification ids and the export. The same instant is two
different days in two different places, and the engine never loses that.

Dictionaries keyed by `Region` encode as JSON objects keyed `front` / `back` /
`headAndShoulders`, never as arrays; every payload-free enum in a record type
has a string raw value, so the export is readable and stable.

## Main paths

### Compute a dose over a window

1. The caller builds a `ForecastCurve` from the forecast's hourly samples, the
   place, its time zone and the fetch time. Construction rejects fewer than two
   samples and samples that are not strictly increasing in time.
2. Construction interpolates the samples linearly to one-minute steps and
   integrates by the trapezoidal rule, dividing UVI·minutes by the
   `uviMinutesPerSED` constant, into a cumulative array. The window's endpoints
   are never averaged — that is the whole point of the prefix integral.
3. `sed(from:to:)` answers any interval as the difference of two cumulative
   values, interpolated inside the minute at each end, and zero for an empty or
   reversed interval.

### Find the best block of minutes for a target dose

1. `DoseCalculator.clip` drops the part of the window that has already passed.
   A window that has passed entirely yields nothing at all — that is the
   "window has passed" outcome.
2. `durationFrom` answers, for one start instant, the shortest run that reaches
   the target, interpolated inside the last minute, or nothing when the curve
   never reaches the target or would only reach it past the allowed end.
3. `bestSubWindow` searches start minutes across the clipped window for the
   shortest such run, then repeats the search at one-second steps around the
   winner so a block on a rising curve ends at the window's end rather than up
   to a minute early. Ties — a flat curve makes every start equal — go to the
   block whose middle sits closest to solar noon.
4. Solar noon comes from the forecast when it supplied one for that day, and
   otherwise from the NOAA formula for the place and date.

### Decide whether a window is worth going out for

1. `isViable` asks whether the clipped window can deliver the viability share of
   the target.
2. When it cannot, `nextViableWindow` steps forward hour by hour, asking at each
   hour whether that share can be delivered before that day is out. It stops at
   the end of the forecast and never returns a start beyond it.
3. `isUVAHeavy` flags a window whose middle sits further from solar noon than
   the tunable threshold.

### Prescribe sunscreen for a whole window

The engine tells the user what to wear; it never asks what they have (R15).

1. The caller gives `SunscreenSolver.outcome` the whole window's raw dose, the
   budget left for the region that window pushes hardest, the window, the
   minutes the bare sub-window would have taken, and whether the dose is
   UVA-heavy.
2. The attenuation needed is the raw dose over the budget. At or below one,
   nothing is needed — the answer still carries the UVA-heavy flag, because a
   high UVA load is worth saying even when no sunscreen is.
3. Otherwise the answer is the lowest label on the ladder, applied normally,
   whose effective protection covers that attenuation. Protection is the label
   raised to half the applied density, so the default density of 1 mg/cm² makes
   it the square root of the label: SPF 50 applied normally is worth about 7,
   not 50. Thick application is never solved for, and a label above the
   realistic maximum is not an answer.
4. When no label is enough, the answer says so and carries the attenuation that
   would have been required — the honest outcome is to shorten the window.
5. A prescription also carries the UVA multiple (the covered window over the
   bare sub-window: the same tanning dose over N times the minutes is roughly N
   times the UVA) and the reapplication times, which are one interval apart from
   the start and empty for a window no longer than one interval.

### Re-solve when the user does not have that SPF

1. `SunscreenSolver.alternative` takes exactly what the user said they can
   manage — the label and the application both — and asks whether its
   protection covers the attenuation the window needs.
2. If it does, they wear it for the whole window; the answer says whether that
   rests on a thick application.
3. If it does not, the answer is less time, never more frequent application.
   The covered part is the longest prefix of the window whose attenuated dose
   still fits the budget, found by bisection on the curve's prefix integral
   because dose from the start only ever grows. The rest of the window is
   shade, head and shoulders are covered, and the reapplication times fall
   inside the covered part only.
### Work out what one region may take today

1. The region's replayed state gives its tan state, which gives the adaptation
   factor `1 + gain(band) × tanState`. That factor, the baseline for the skin
   type and the sensitivity multiplier — the manual one when the user set it,
   the learned one otherwise — multiply into the personal burn line.
2. The dose that tans is a static fraction of that line, per skin band. The
   target is the lower of the two, scaled by the ceiling — so the selector moves
   the number for every skin type, and no setting ever plans past the line.
3. The scale is not always the one the user picked. Below the calibration count
   the number sits at the conservative scale; an aggressive selection that has
   not unlocked falls back to standard. The target says which happened, so the
   result can explain itself.
4. A stale forecast shortens the target by a fixed fraction and widens the
   range around it.
5. The range is centred on the target. Its lower edge narrows with any report,
   its upper edge only with redness reports, and its upper edge is clipped at
   the personal burn line — the app never draws a range past it, and it records
   that it clipped.
6. What is left for today is the target minus what the region already took.

### Turn a window into a session

1. The window is clipped to now. Head and shoulders uncovered with nothing left
   is no session at all, and neither is a lying session with both torso sides
   spent or a standing one with every exposed region spent.
2. Up and about, every region is exposed at once, so the whole session is one
   block. The tightest budget fixes the bare dose the block may deliver, and the
   shortest block that delivers it is the answer — the same search the dose
   calculator uses, so ties go to the block nearest solar noon.
3. Lying down, the two sides run consecutively from one start. Each side runs
   exactly as long as its own torso region's budget allows, and a side whose
   budget is spent runs not at all. Start minutes are searched across the
   window; the start whose two sides finish soonest wins, ties by solar noon.
4. Head and shoulders take the face-up dose in full plus a share of the
   face-down dose, so they can overrun while both torso sides are still within
   budget. Both sides then shrink by one scalar, found by bisection, until that
   credit fits (D-2026-09-03-F2) — never by solving a linear programme.
5. A window that cannot reach any budget is planned in full rather than as zero
   minutes, and says so. Lying down, the flip time is then placed where both
   sides get the same fraction of their budgets.
6. The plan is solved a second time with the head and shoulders covered, and
   the difference is how much longer each stretch could run that way.
7. Warnings compare today's total — what the region already took plus what the
   whole entered window would add — against the target and the burn line, and
   only when the user has said they mean to stay out for it.

## State and storage

`Profile` is what the user told the app; `DerivedState` is everything else the
engine knows, and it is derived, never stored — one sensitivity multiplier for
the person, the report counts, per-region tan state and dose, and the tan-cycle
starts. `DerivedState.initial` is a user the engine knows nothing about. Folding
the history into it is Slice 3; until then a caller supplies it.

Nothing here persists anything. `SessionRecord` and `SkinReport` are the record
types the history is made of, and `History.ordered()` puts them in one stream —
logged sessions at the end of what was actually faced, reports when they were
answered, and a lasting-colour answer at its own timestamp rather than at its
report's. Replaying that stream into derived state is Slice 3.

## Known rough edges

- `Tunables` reads report their key through a sink, which means provenance is
  only as accurate as the engine's discipline about reading constants through
  the request's `Tunables` rather than `Tunables.current`. `ForecastCurve` does
  read `Tunables.current` for the SED conversion, because a curve is built
  before any request exists.
- The best-block search is a one-minute scan with a one-second refinement, not
  a solver. It is fast enough for a day-long window and easy to reason about,
  but it is a scan, and a much longer window would cost proportionally more.
- `SessionRecord`, `SkinReport` and `History` live in `Models/Reports.swift`
  because Slice 1 declares every shared type; the adaptation and calibration
  logic that folds them into state arrives in Slice 3.
- `SunscreenSolver.outcome` and `.alternative` carry an inline
  `swiftlint:disable:this function_parameter_count`: their parameter lists are
  the plan's declared signatures, which a blind test author writes against, so
  they are not ours to shorten. The rule stays on everywhere else.
- The lying-down start search is a one-minute scan, like the best-block search,
  and each candidate costs two binary searches over the prefix integral. A whole
  day's window solves in well under a millisecond, but it is still a scan.
- `ExposureModel.solve` calls itself once, with the head and shoulders covered,
  to answer "how much longer if I cover up?". The recursion stops there because
  the covered solve returns no such answer of its own.
- `TanningGoal.copyKey` has to be one of the closed `CopyKey` list, which has no
  key naming a goal; it returns `boundByMelanogenic`, the nearest thing to a
  line about the tanning threshold. When the vitamin D goal lands (M8) both
  goals will want a key of their own.
- `.swiftlint.yml` disables `trailing_comma` because SwiftFormat's
  `trailingCommas` rule adds exactly what it removes, and both run in CI; and
  it excludes the short names the design fixes (skin types `i`–`vi`, the
  lasting-colour answer `no`, the calibration constant `k`).
