# project_icarus — Architecture

<!-- The living description of what exists RIGHT NOW. Updated at the end of every
slice (AGENTS.md, "Architecture doc"), so it describes the system as built, never
as planned. `docs/DESIGN.md` is the intent and doesn't change; this changes.

Keep it at the level of LOGIC, NOT CODE. -->

The app is one Swift package (`Package.swift`) plus a thin app shell in `App/`.
The package holds five library targets; `project.yml` builds the iOS app from
the shell and the package's UI product.

As of Slices 1 to 5 of the `core-engine` plan, the engine is whole. It has its
foundation — the shared value types, the constants table, and dose
arithmetic over a forecast curve — and, on top of it, the budget and the
solver (what each region may take today, and the session that fits inside
it), the sunscreen answer, the loop that learns (the history folded into
derived state, session by session and report by report), and the `Planner`
that composes all of them into one typed result.

As of Slice 1 of the `data-layer` plan, `IcarusData` exists too: the forecast
side of it. It fetches a forecast through a provider protocol — WeatherKit on
Apple platforms, a fake that replays a recorded answer everywhere — keeps the
last good curve in one file, refetches only at the ruled cadence, and names
every failure it meets. `IcarusContent`, `IcarusUI` and `IcarusAds` are still
placeholders.
`IcarusData` is the M2 layer around it: the `data-layer` plan's Slice 3 adds the
history store, its persistence seam, and the JSON export and import. The other
three targets are placeholders.

`Planner.plan` is the engine's only entry point. Everything above it — the
data layer, the UI, the notifications — asks it one question and reads one
answer.

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
| `IcarusCore` / `AdaptationModel` | How a region's tan state moves: up with the share of its target a session delivered, down with elapsed time, and what the two together are worth telling the user — the escalation and gap notices, and the plateau outcome. |
| `IcarusCore` / `CalibrationEngine` | One skin report against one day's logged dose: which region it is evidence about, and what it does to that region's tan state and to the person's one sensitivity multiplier. |
| `IcarusCore` / `Replay` | The fold. The ordered history in, the current derived state and every report's effect out. |
| `IcarusCore` / `Planner` | The engine's one entry point. A `PlanRequest` in, a `DoseResult` out: the outcome, the budgets it was solved against, the notices, every figure with the constants behind it, and the copy keys in display order. |
| `IcarusData` | Everything that touches the outside world or the disk, behind protocols the engine never sees: the forecast provider and cache, location, the history store and its persistence, export and import, and the prompts. Imports `IcarusCore` and Foundation; Apple frameworks sit behind `#if canImport(...)`. |
| `IcarusData` / `UVForecastProvider` | The seam a forecast comes through: hourly UVI, solar noon per day, the place's time zone, and the horizon asked for. Its failures are named — unavailable, unauthorized, network. |
| `IcarusData` / `WeatherKitProvider` | The live source, built only where WeatherKit is. It maps its answer into the recorded response shape first, so the mapping is one pure function tested on every platform; the place's zone comes from a reverse geocode, cached per coordinate. |
| `IcarusData` / `FakeForecastProvider` | Replays a recorded answer, with an optional delay, a forced failure, or a deliberately malformed answer. Ships the `beach-oslo` fixture, so the whole engine runs end to end with no network. |
| `IcarusData` / `ForecastCacheStore` | One forecast, kept, with the name of the provider it came from. `FileForecastCache` is a JSON file written by temp-and-rename; `MemoryForecastCache` is the same thing without a disk. |
| `IcarusData` / `ForecastService` | The one way into a forecast: the cadence, the cache, and the named failure. Answers `.fresh`, `.cached` with the reason, or `.none` with the failure. |
| `IcarusData` / `LocationService` | Where the user is (R2). One actor over a `LocationSource` and a `PlaceResolver`; a manual place, once set, wins over the device. |
| `IcarusData` / geocoding | `Place` — a name, a coordinate and the zone the day boundaries are read in — plus the resolver that turns typed text into candidate places. `AppleGeocoder` on Apple platforms, `FakePlaceResolver` (a table) everywhere. |
| `IcarusData` / `HistoryPersistence` | The one seam under the history: load the whole record, replace it whole, upsert one session or one report. `MemoryPersistence` is the reference implementation and what Linux runs; `SwiftDataPersistence` is the same contract over a SwiftData container, built only where SwiftData exists. |
| `IcarusData` / `HistoryStore` | The one way in and out of the history: it stores planned sessions, logs them, discards them, records reports and lasting colour, and answers with the replayed state and the weekly and cycle totals. Nothing derived is stored. |
| `IcarusData` / `ExportService` | The export file (version 1), the atomic import, and the recomputation that proves a session record is enough on its own. |
| `IcarusData` / `PromptScheduler` | Every prompt the app makes: the skin check about a day's sessions, the lasting-colour question about a report, the flip timer's alerts, and the in-app fallback for anything the system never delivered. |
| `IcarusData` / `NotificationPort` | The system notification centre, as the only four things this layer needs from it. `FakeNotificationPort` records; `UserNotificationAdapter` is the real one, and exists only where `UserNotifications` does. |
| `IcarusContent` | Placeholder. Will own generated copy and Learn content (M3). |
| `IcarusUI` | Placeholder. Will own the SwiftUI surface (M4). Not built on Linux. |
| `IcarusAds` | Placeholder. Will own the ad banner behind a protocol (M7). Not built on Linux. |
| `App/` | The iOS app shell. Depends only on `IcarusUI`. |

Two things follow from the layout and are deliberate. `IcarusCore` depends on
nothing, so the engine is testable on Linux and in CI without a simulator. And
`IcarusUI` and `IcarusAds` are declared only under `#if !os(Linux)` in the
manifest, so a Linux build sees exactly Core, Content and Data.

## Data flow

The engine is given data; it never fetches any. `IcarusData` is what gives it.

- A coordinate and a clock --> `ForecastService.current` --(a `ForecastResult`)-->
  the caller. Inside: the cache is read, and either answers as it stands or a
  provider is asked; a good answer becomes a `ForecastCurve` and is saved.
- A provider --(`ProviderForecast`: hourly samples, solar noon per day, the
  place's zone)--> `ForecastService` --(`ForecastCurve`)--> the engine. The
  curve is the only forecast shape that leaves the data layer.
- A caller supplies hourly UVI samples, a place, a time zone and a fetch time
  → `ForecastCurve`, which integrates them once into a one-minute prefix
  integral of SED. Every later dose question is two lookups and a subtraction.
- `ForecastCurve` --(SED over an interval)--> `DoseCalculator`.
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
- A `History` --(one ordered stream of events)--> `Replay` --(a `DerivedState`
  and one effect per report)--> the target model, which closes the loop: what
  the app learned is what it plans with next.
- A `PlanRequest` — the forecast or the reason there is none, where the device
  is, the clock, the window, the posture, the user and their replayed state —
  --> `Planner.plan` --(one `DoseResult`)--> the caller. The planner calls every
  model above and adds nothing of its own except the order they run in, the
  notices, and the bookkeeping that makes each figure's provenance exact.
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

### Get a forecast for a place

1. `ForecastService.current(for:now:)` reads the cache first. A cache that
   cannot be read is not an error here: it is treated as no cache, and the
   fetch goes ahead.
2. The cached curve answers as it stands when it is **both** less than
   `fetchMinIntervalHours` (one hour) old **and** within `fetchMoveKm` (10 km)
   of the place asked about. The answer says why: `.cached(curve,
   .withinInterval)`. `force: true` skips this test entirely.
3. Otherwise the provider is asked for `forecastHorizonDays` days. Its answer
   becomes a `ForecastCurve` built at `now`, with the place's own time zone, and
   is saved to the cache before it is returned as `.fresh`.
4. Every failure is named and none is flattened into "offline". A provider that
   refuses is `.provider`; an answer no curve can be built from — too few
   samples, samples out of order — is `.malformed`, never reported as a provider
   failure, because the two send the user to different remedies.
5. A failed fetch with a cache present answers `.cached(curve,
   .providerFailed(failure))`: the last good forecast, with the reason attached.
   With no cache it answers `.none(failure)`.
6. `cached()` is the read-only door. It never fetches, and answers whatever is
   on disk whatever its age; a cache that is empty or unreadable is
   `.none(.cacheUnreadable(reason))`.

### Record a forecast, and read it back after a relaunch

1. A save encodes the curve and the provider's name, writes a temporary file
   beside the target, and renames it over the old one. A save cut off halfway
   leaves the previous forecast whole rather than a half-written one.
2. Dates are ISO 8601 in both directions. The round trip keeps the place, the
   fetch time, the horizon, every sample, and the solar noon of every day.
3. A file that decodes into nothing usable throws, which is what turns
   `cached()` into a named `.cacheUnreadable` rather than a silent empty.

### Replay a recorded WeatherKit answer

1. The recorded shape is `hours`, `days`, and a time-zone identifier — what
   WeatherKit actually gives, written down. The live provider maps its answer
   into that shape and then through the same function the fixtures use, so the
   part that can be wrong is exercised on Linux with no framework present.
2. The mapping keeps the hours in order as UVI doubles, keys each day's solar
   noon by the day it falls on **in the forecast's own zone**, and fails with a
   named `unavailable("time zone")` on an identifier it does not know.
3. `FakeForecastProvider.fixture(named:)` loads such a file from the target's
   own resources. `beach-oslo` is ten days from 2026-06-15, hourly, a daytime
   hump peaking at UVI 7, solar noon at 11:15 UTC each day, Europe/Oslo.
### Decide where the user is

The engine is told a coordinate; it never asks for one. `LocationService` is
what answers that question, and it answers it in one of three ways (R2).

1. A manual place, if the user has set one, is the answer — `useManual` pins it
   and `clearManual` releases it. It wins over the device unconditionally: the
   user said where they are, and the app does not argue with them.
2. Otherwise the device source is asked for one reading. A fix becomes the
   device answer; a denial or a failure is returned **as itself**, so the caller
   can offer manual entry with the true reason rather than a generic "no
   location". `LocationAnswer.coordinate` is the coordinate to fetch a forecast
   for, and is nil exactly when a place is still needed.
3. Typed text goes through the `PlaceResolver` and comes back as candidate
   places, each carrying its own time zone — the zone the day boundaries and the
   forecast for that place are read in. Text the resolver does not know resolves
   to no candidates, not to an error.
4. On Apple platforms the source is one CoreLocation request at kilometre
   accuracy with when-in-use permission: a single fix, never a running manager,
   and it gives up after ten seconds as unavailable rather than waiting forever.
   Both the real source and the real geocoder are compiled only where
   CoreLocation exists; the Linux build and its tests see the protocols, the
   fakes and the actor.

How far the device has drifted from the place the cached forecast is for is a
question about two coordinates, answered by `Coordinate.distanceKm(to:)` in the
engine's own vocabulary: the caller compares this answer's coordinate with the
cached curve's location. That one distance is what R1's 10 km refetch and R3's
25 km staleness warning are both measured with.

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

### Plan one window — the whole answer

The order is the answer's meaning, not an implementation detail: staleness and
the plateau both move the budgets, so they are settled first; the budgets are
settled before anything looks at the window; and the sunscreen is judged
against what is left of the budget *after* any maintenance scaling.

1. No forecast is the one outcome that shows no number. It names why — a
   provider failure, a malformed response, an unreadable cache, or no location
   — and stops there, having read no constant and claimed no figure.
2. Staleness is judged on the forecast's age and place: nothing under three
   hours, the age alone under six, and a warning past six, or at any age when
   the device is more than the tunable distance from the place the forecast is
   for, or does not know where it is. A warning trims the target and widens the
   range; it never refuses a number.
3. Each region's plateau outcome is read from the replayed state. A region that
   has one has its budget scaled to the maintenance fraction **before** the
   session is solved, so the session and the sunscreen are both answers about
   the maintained dose.
4. Every region spent is the budget-spent outcome, naming the region that took
   the most today. A window wholly in the past is the window-passed outcome; a
   window partly in the past is clipped and solved from now.
5. The whole window's raw dose per region says which region it pushes hardest
   against what is left — the attenuation region. Everything about overshoot and
   sunscreen is judged there, because a product that covers that region covers
   every other exposed one.
6. Under half of what is left of that region's budget — or of its target,
   whichever is smaller — the window is too weak to bother with. The answer
   carries the shortfall from the melanogenic dose and the next window in the
   cached horizon that could deliver the full target. When the horizon holds
   none, the answer is instead how many days were searched and the strongest UVI
   in them, and it never claims a season.
7. Otherwise the exposure model solves the session against the maintained
   budgets. A solve with nothing to plan is the budget-spent outcome again.
8. The sunscreen answer follows only when the whole window would overshoot the
   attenuation region: the lowest ladder label whose normal application covers
   it, or the honest "no realistic product covers this".
9. The headline is the bare sub-window, unless the window could not reach the
   budget (then the window itself is the answer) or the user has said they will
   stay out for it and there is a realistic product to name. "Nothing realistic"
   never leads.
10. The notices are gathered around the limiting region: its tolerance news, its
    plateau outcome, whether maintenance was applied, the UVA flag, the
    staleness level, and the flags that follow from the skin type and the report
    count. The copy keys are then the outcome first, then the notices, the
    warnings and the sunscreen, each named once.

### How a figure knows what it read

Every number in a result carries the set of constant keys it came from, and a
figure is an estimate exactly when one of those keys is an assumption (R30).
The promise the tests hold is stronger than that: what a recording `Tunables`
observes over a whole `Planner.plan` call is **exactly** the union of the
figures' declared reads.

The planner keeps that true by construction rather than by a table someone
maintains. Every step that touches constants runs through a small helper that
runs it twice — once through a recording copy, which learns the keys, and once
through the caller's own `Tunables`, so a sink the caller installed sees the
same reads. `recording(_:)` replaces the sink rather than chaining onto it, so
a nested recording would swallow the caller's; two runs of a pure computation
is the price of not losing it. The keys are collected in groups — the budgets,
the solve, the viability search, the sunscreen, the UVA threshold, the
escalation notice — and each figure declares the groups its own value actually
came from. A group read for a notice rather than for a number is folded into
the headline figure at the end, so nothing is dropped.

### Replay the history into state

The history is the record; everything the engine knows about the user is
recomputed from it under today's constants (R44). One pass, in time order.

1. `History.ordered()` puts the record into one stream: a logged session at the
   end of what was actually faced, a report when it was answered, and a
   lasting-colour answer at its own timestamp, days later. A session never
   logged, or logged with nothing faced, is not in the stream at all.
2. A **session** first fades every region to the moment it ended. If that fade
   closed the last tan cycle for every region, this session opens a new one, and
   its start is remembered — the last two cycle starts are the window the report
   count is taken over.
3. Each region then records the adaptation factor and tan state it had *before*
   this session, because that is what a report about this session is evidence
   about, and what the gap notice measures the drop from.
4. The target for the region is recomputed here, under the ceiling and the
   manual override **that session was planned with** and the state as it stood
   at that moment — never under today's settings. That is what makes changing
   the ceiling leave the replayed tan state alone. The dose itself is never
   recomputed: it is what the session stored, because the forecast is not part
   of the replay.
5. The region rises by the share of that target the session delivered. Today's
   dose accumulates within a day and is replaced, not carried, on a new one.
6. A **report** goes through the calibration engine and its effect is kept
   against the report's id, so the app can always say what an answer changed.
   The report count is then re-taken over the two-cycle window.
7. A **lasting-colour** answer counts for every region that took at least its
   share of its target that day. "No" builds the plateau count while the region
   is near saturation; "yes" or "a little" clears it.
8. Finally every region fades to the clock, and today's dose is zeroed when the
   day the fold ended on is over.

### Move the tan state

Each event is one decay and one rise in closed form (D-2026-09-03-F3), never a
day-by-day loop, so a year of history costs no more per session than a week of
it does.

1. The fade is a half-life on elapsed time. A gap longer than the tunable two
   weeks also ends the tan cycle: the cycle's start, its redness bound, its
   cumulative dose and its plateau count all go.
2. The rise is a leaky integrator toward saturation, driven by the **share of
   the region's target** the session delivered rather than by the dose, so a
   session at the target advances every skin type and every ceiling setting
   equally. The band's rise multiplier is applied on top.
3. The escalation notice fires when the factor has risen by half the maximum
   rise the skin type has available. The gap notice fires when a gap longer than
   two weeks has undone half the rise actually achieved, and says what share is
   gone. A gap is judged first: news that tolerance has dropped is what the user
   needs before they plan.
4. The plateau outcome hangs on the count of "no lasting colour" answers, never
   on the tan state re-read at plan time, so it does not flicker with a
   weekend's decay. With a redness bound in the current cycle it is the ceiling
   outcome; without one, the app cannot tell a finished skin from an under-dosed
   one, and says so.

### Learn from one skin report

1. The report's evidence is one region. A named region is itself. "All exposed"
   takes the strongest bound the answer supports: the highest-dose region when
   the skin stayed normal, the lowest-dose region that took any dose when it
   reddened. A day with no logged dose is evidence about nothing, and the report
   is recorded without being calibrated.
2. Redness that showed within an hour and had faded by evening is immediate
   pigment darkening, not erythema. It is calibrated as "normal", and the effect
   says so.
3. A **normal** answer is one-sided: it says only that the threshold lies above
   what was delivered. At or below the estimate it confirms and changes nothing.
   Above it, the excess is credited to the region's tan state first, and only
   the part saturation cannot absorb reaches the multiplier — never above the
   dose actually tolerated.
4. A **redness** answer maps to an implied dose-to-threshold ratio, divided by
   the adaptation factor in force before the session, and moves the multiplier
   by the confidence weight. The weight falls with the number of reports in the
   current and previous cycle, floors at the cap, and doubles for a burn. It
   bounds the region for the cycle — every region that took dose that day, for
   an "all exposed" report.
5. A confounded report counts for a quarter of itself. A blistering report also
   pulls the multiplier under a protective fraction of what it implied, whatever
   the count, and asks for a pause.
6. The multiplier always moves **from itself**, even when a manual override was
   what the session was planned with, so an override never becomes the thing the
   app has learned. It is clamped at both ends, and hitting a clamp is the cue
   to ask the user to revisit their skin type.

### Plan, log and learn from one session

1. The result screen has an answer, so the caller stores a planned session with
   `upsertPlanned`. It carries the pair the result prescribed and the intervals
   it proposed. Replanning the same window passes the old id as `replacing`: the
   superseded record leaves the history, and the new one's id comes back.
2. The user goes out. `log` writes what was actually faced — the sub-intervals,
   the sunscreen confirmed, the per-region dose after sunscreen and cover, and
   the factors and targets that were on screen — and moves the session to
   *logged*. The timer's stop calls the same method again on the same session,
   which is how stopping early shortens the stored record rather than adding a
   second one. A discarded session refuses to be logged.
3. A planned session nobody logged is discarded either one at a time, or in bulk
   by `discardPlanned(before:)`, which takes every planned session whose in-app
   skin-check window closed before the cutoff.
4. The day after, `addReport` records one skin report — a second report for the
   same day is refused — and answers with what that report did, taken from the
   replay that follows the write, never from a stored number. Days later,
   `setLastingColour` writes the answer against that report at the instant it
   was given; a day with no report refuses it.
5. Anything that reads state calls `state(now:)`, which replays the whole
   history under the current profile and constants. `totals(now:)` is the
   History screen's pair: the week is the logged doses whose actual window ended
   in the last seven days, and the cycle is each region's doses since its tan
   cycle opened, with the cycle start taken from that same replay.

### Export the history and import it back

1. `ExportService.export` asks the store for the whole history and writes one
   JSON file: the format version, the constants version the store replays under,
   the profile, every session with its stored curve, every report, and the
   instant it was written. Dates are ISO 8601 and keys are sorted, so the same
   history exports to the same bytes.
2. `ExportService.import` decodes the file, refuses a format version it does not
   know, and validates every record — intervals that run forwards and do not
   overlap, no negative dose, and a stored curve that rebuilds. Only then does it
   replace the store's history in one atomic write. A file that fails any check
   leaves the store exactly as it was.
3. The summary reports what landed and the profile the file carried, because the
   importing app must ask about that profile rather than assume its own.
4. `ExportService.reproduce` recomputes a session's per-region dose from the
   record alone: each faced interval's dose over the stored curve, summed, then
   attenuated by the sunscreen and the cover. It needs no derived state, which
   is what makes an exported session checkable — a session stopped before its
   flip reproduces the doses it stored.

## State and storage

`Profile` is what the user told the app; `DerivedState` is everything else the
engine knows, and it is derived, never stored — one sensitivity multiplier for
the person, the report counts, per-region tan state and dose, and the tan-cycle
starts. `DerivedState.initial` is a user the engine knows nothing about, and
`Replay.replay` is how a real one is built.

Nothing in `IcarusCore` persists anything. Two things are stored, both by
`IcarusData`: the forecast — one `CachedForecast`, a curve and the provider's
name, in `forecast.json` in whatever directory the caller gives
`FileForecastCache` — and the history, through `HistoryPersistence` (SwiftData
on Apple platforms, memory everywhere else), described below.

`SessionRecord` and `SkinReport` are the record
types the history is made of, and `History.ordered()` puts them in one stream —
logged sessions at the end of what was actually faced, reports when they were
answered, and a lasting-colour answer at its own timestamp rather than at its
report's.
Nothing in `IcarusCore` persists anything. `SessionRecord` and `SkinReport` are
the record types the history is made of, and `History.ordered()` puts them in
one stream — logged sessions at the end of what was actually faced, reports when
they were answered, and a lasting-colour answer at its own timestamp rather than
at its report's.

`HistoryStore` is where the record actually lives. It is an actor over a
`HistoryPersistence`, so only one caller at a time changes the history, and it
holds exactly one derived thing: a memo of the replayed state, keyed by the
history itself, the constants version, the day `now` falls in (in the zone the
history was recorded in) and the profile. Any write drops the memo, and so does
`invalidate()`, which is what a profile change calls. A different day, a
different profile or a different constant set is a different key, so the answer
is recomputed rather than reused — the state is never a stored number.

`MemoryPersistence` is a value type whose records live in a locked box shared by
every copy, so handing it to the actor does not fork the history in two.
`SwiftDataPersistence` keeps one row per record, each holding the record as its
own JSON with the day and the state mirrored into columns for the day queries;
the JSON is the same external shape the export uses, so the two can never drift
apart. It opens a context per call and saves once, which is what makes
`replaceAll` all-or-nothing.

## The success criteria that are scripts

`acceptance/S1.sh` runs the dose, target and constants tests and prints every
read key the single `Tunables` file exposes. `acceptance/S18.sh` runs the
use-case fixtures twice, under `TZ=UTC` and `TZ=Europe/Oslo`, and fails when the
filter matched nothing — `swift test` exits 0 on an empty selection, and "no
fixtures" must not read like "every fixture passed". Both take class-name
prefixes rather than exact names, because the classes are split by subject and
the fixtures are written blind.

The file names are `S<n>.sh` exactly: `.github/scripts/acceptance-criteria.sh`
matches a criterion id to `acceptance/S<n>.sh` and runs nothing else, so a
descriptive suffix would be a script the check never runs.

### Ask about a day's skin, once

1. The store tells `PromptScheduler` that a day's planned-or-logged sessions
   changed, and gives it the end of the last of them. The scheduler never counts
   sessions itself and never reads the history for this.
2. The identifier is the day: `"skin-" + day.id`. So the scheduler cancels that
   identifier and schedules one alert at the last session's end plus
   `skinCheckDelayHours` (20 h). A later session on the same day simply moves the
   same alert; there is only ever one per day, and no bookkeeping to lose.
3. `lastSessionEnd` of nil means the day's last session was discarded. Both of
   the day's questions — the skin check and the lasting colour — are cancelled.
4. A report about the day is the only thing that schedules the lasting-colour
   question, at the answer's time plus `lastingColourDelayDays` (4 d), under
   `"colour-" + day.id`. It is asked days after the answer, not after the
   session, so a report given late moves it. Adding the report does not cancel
   the day's skin check.
5. `PromptScheduler.day(fromNotificationID:)` reads either identifier back to the
   day it is about, because `DayKey.id` carries its own time zone and round-trips
   whatever zone the host is in. That is how a tapped notification knows which
   day it is asking about.

### When the system will not alert

1. Every schedule asks the port for authorization first. Anything but `granted`
   drops the request rather than pretending it is pending. Cancelling is
   unconditional.
2. `dueInApp(history:now:)` is then what surfaces the question. It is a pure
   read of the history against the clock, so it also covers a prompt that fired
   and went unanswered.
3. A day with a planned or logged session and no report is due for the skin
   check while now sits inside `inAppSkinCheckWindowHours` (12 h to 72 h) after
   that day's last session — the actual end when the session was logged, the
   planned end when it was not.
4. A report with no lasting-colour answer is due for that question while now
   sits inside `inAppLastingColourWindowDays` (3 d to 10 d) after the answer.
5. At most one question per day comes back, ordered by day, so the launch path
   asks them in a stable order.

### Alert through a flip timer

1. `scheduleTimer` replaces the whole set: it cancels everything under
   `"timer-"`, then schedules the first side's end (`"timer-side"`, absent for a
   standing session), one alert per reapplication time
   (`"timer-reapply-<index>"`, from zero), and the session's end
   (`"timer-end"`).
2. `cancelTimer` cancels the same prefix. Stopping the timer therefore takes no
   record of what was pending.

## Known rough edges

- A `Planner.plan` call solves the session twice over: once to learn which
  constants the solve reads and once for the answer. It is bounded — the worst
  case measured here, a ten-hour lying window on a cached curve, is about 13 ms
  in a debug build against the 100 ms R38 allows — but it is a doubling, and the
  reason for it is the sink-replacing shape of `Tunables.recording(_:)` rather
  than anything the planner wants.
- The UVA-heavy threshold is read for a notice, not for a number, so its key is
  folded into the headline figure. That makes the headline an estimate on
  grounds it did not quite use. The alternative — dropping the key — would break
  the stronger promise that a recording `Tunables` sees exactly what the figures
  declare, and that promise is the one the provenance rests on.
- The cloud-cover caveat is always false. Nothing in a `PlanRequest` carries
  cloud cover; the data layer supplies it when it exists (M2).
- A result with no forecast carries no figures and no notices beyond the
  thin-margin line, because it reads no constants at all. The flags that would
  need a constant — the pre-calibration line among them — are not claimed rather
  than guessed.
- The budget-spent check runs before the window-passed check, as the plan's
  Internals order them. A window that has passed for a user with nothing left
  today is reported as spent, which is the more useful of the two.
- `Tunables` reads report their key through a sink, which means provenance is
  only as accurate as the engine's discipline about reading constants through
  the request's `Tunables` rather than `Tunables.current`. `ForecastCurve` does
  read `Tunables.current` for the SED conversion, because a curve is built
  before any request exists.
- The best-block search is a one-minute scan with a one-second refinement, not
  a solver. It is fast enough for a day-long window and easy to reason about,
  but it is a scan, and a much longer window would cost proportionally more.
- `SessionRecord` and `SkinReport` live in `Models/Reports.swift` because Slice
  1 declares every shared type; `History` was moved out to `Models/History.swift`
  in Slice 3, unchanged, because that is the file the plan gives the fold.
- `AdaptationModel.escalationNotice` reads the region **as it stands**, and uses
  `now` only to measure the length of the gap. That is right for the state
  `Replay` hands out, which the fold has already faded to the clock; fading it a
  second time inside the notice would double-count the gap. A caller with a
  region state from some earlier moment must decay it first.
- The gap notice measures the drop against `factorAtLastSession` and
  `tanStateAtLastSession`, which are the values from *before* the last session
  advanced them — the meaning Slice 1 declared, and the one the calibration
  rule needs. A state built by the fold therefore reaches the notice line a day
  or so later than a state whose "at last session" values were the post-session
  ones: after six weeks of five-a-week sessions the notice appears at a gap of
  about 22 days rather than exactly one half-life. The four-week gap S4 is a
  release blocker on fires with a drop of 0.59.
- The plan's promise list expects no notice at all after a 13-day gap. With the
  rise the current constants produce, the factor is still 0.64 above baseline
  there — more than the half of the maximum rise the escalation line asks for —
  so the escalation notice is what comes back. The two rules are simply both
  true at that point; the gap rule is the one that does not fire.
- The separation simulation at a true adaptation gain of 0.7× settles the
  learned multiplier near 0.87, a little further from 1.0 than S3's 0.10 bound,
  because a "faint pink" answer implies the threshold *is* the delivered dose
  and the standard scale plans at 0.9 of it, so the equilibrium sits just under
  0.9. The error is in the safe direction — shorter sessions — but it is a
  property of the constants, not of the code.
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
- A fetch that succeeds but whose cache write fails still answers `.fresh`. The
  forecast in hand is worth more than the record of it, and the next call simply
  fetches again.
- When the cache is unreadable **and** the provider fails, `current()` reports
  the provider's failure, not the cache's. The cache failure is still reachable:
  `cached()` names it.
- `MemoryForecastCache` is a value type holding a locked box, so every copy of
  one shares the same forecast. That is what makes it usable as a stand-in for a
  file, and it is not what a value type usually means.
- `WeatherKitProvider` exists on Linux too, and every call there fails with
  `unavailable("WeatherKit is not available on this platform")`. The engine is
  built against the protocol, so the type must exist to be named; the live path
  cannot be run or verified until the entitlement lands (M7).
- The fixture bundle is declared as `.copy("Resources")` on `IcarusData`, so the
  fixture's path inside the bundle is `Resources/Fixtures/<name>.json`. The test
  target declares no resources of its own; a test needing a fixture either loads
  `beach-oslo` through the provider or carries its own JSON as a literal.
- `ForecastCurveError` gained `Sendable` in `IcarusCore` so `ForecastFailure`
  can carry it across an actor boundary. Its cases and meaning are unchanged.
- `LocationService.location(now:)` takes a clock it does not use. The parameter
  is the plan's declared signature, and it is the seam a later rule about how
  long a fix stays good would need; today the answer depends only on whether a
  manual place is set and on what the source says.
- `CoreLocationSource` and `AppleGeocoder` are not exercised by any test: they
  exist only where CoreLocation does, and the Linux suite runs the fakes. Their
  first real evidence is the owner's on-device criterion (S8, S9).
- The notification words in `UserNotificationAdapter` are plain English written
  in place, not resolved copy: the content layer is M3. The skin check carries
  its `CopyKey` in the request's `userInfo` so the copy can be swapped without
  changing the identifiers; the other kinds have no key in the closed `CopyKey`
  list, so they carry none.
- `PromptScheduler` asks the port for authorization on every schedule rather
  than caching it. That is one extra hop per alert, and it is deliberate: the
  user can revoke permission between two sessions, and a cached "granted" would
  schedule alerts that never arrive while the in-app fallback stayed quiet.
- Cancelling is a prefix match, and a day's identifier is a whole `DayKey.id`.
  No other identifier can extend one, because a time-zone name is never a prefix
  of another time-zone name in the same position — but it is a prefix match, not
  an exact one, and that is the assumption it rests on.
- `.swiftlint.yml` disables `trailing_comma` because SwiftFormat's
  `trailingCommas` rule adds exactly what it removes, and both run in CI; and
  it excludes the short names the design fixes (skin types `i`–`vi`, the
  lasting-colour answer `no`, the calibration constant `k`).
