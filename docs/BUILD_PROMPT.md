# Build Prompt — Project Acuras (iOS)

> **Companion document:** `LEARN_CONTENT.md` contains all copy for the Learn tab, including citations. Treat it as a content input, not as something to rewrite. Do not paraphrase it, do not summarise it, and do not drop the citations.

---

## 1. What we're building

**Project Acuras** (placeholder name — do not bake this string into user-facing copy or bundle identifiers in a way that's painful to change).

A free iOS app that helps a user plan sun exposure to maximise **durable tanning** (new melanin production) while staying below their personal burn threshold.

The core problem it solves: most people can't be outside at solar noon. They have a work schedule, and their available window sits somewhere on the shoulder of the UV curve. Working out what that window is actually worth — and whether they need sunscreen, and how much — requires integrating a changing UV index over time and knowing their personal sensitivity. Nobody does that arithmetic by hand.

**Two tabs**, standard iOS tab bar:
1. **Calculator** — the planning engine
2. **Learn** — the educational content

---

## 2. Non-negotiable constraints

- **Free.** No paid APIs, no subscription infrastructure, no cost that scales with users.
- **Native iOS.** Swift + SwiftUI. Target the current iOS release, minus one.
- **Modular.** This is a hard requirement, see §7. I expect to revise the Learn copy repeatedly without touching engine code, and to tune the engine without touching UI.
- **Offline-tolerant.** Cache the last fetched forecast. Degrade gracefully with a clear "this data is N hours old" indicator rather than failing.
- **Privacy.** All logs stay on device. No accounts, no analytics, no network calls except the weather fetch.

A project template already exists and should be pulled with `copier`. Follow whatever conventions it establishes.

---

## 3. Data source

Use **Apple WeatherKit** for hourly UV index.

- It's the same source the built-in iOS Weather app uses, which matters because the user's mental model is calibrated to that app's numbers.
- Free tier: 500,000 calls/month, included with the Apple Developer Program.
- Native Swift API, no key management in-app.
- Requires the WeatherKit capability enabled and Apple's attribution requirements met (attribution logo + legal link — implement these, they're a review requirement).

Location via CoreLocation, `kCLLocationAccuracyKilometer` is plenty. Request when-in-use only. Handle denial with a manual location entry fallback.

If WeatherKit proves unworkable, **Open-Meteo** is the fallback (free, no key, hourly `uv_index`) — but flag this to me before switching, don't decide silently.

---

## 4. The calculation engine

This is the heart of the app. Get it right.

### 4.1 Units

- **1 SED** = 100 J/m² erythemally weighted UV.
- **UV Index 1** = 25 mW/m² erythemally weighted.
- Therefore: **1 SED accumulates in 66.7 UVI-minutes.**

Canonical conversion:

```
dose_SED = (∫ UVI(t) dt, in UVI·minutes) / 66.7
```

### 4.2 Dose integration — do not average endpoints

WeatherKit returns UVI at hourly resolution. The user's window will rarely align to hour boundaries, and UVI is strongly non-linear across the day.

**Required approach:**
1. Linearly interpolate the hourly UVI series to fine resolution (1-minute steps is cheap and removes all ambiguity).
2. Integrate over the user's window by **trapezoidal rule**.
3. Divide by 66.7 for SED.

**Explicitly do not** take `(UVI_start + UVI_end) / 2 × duration`. Worked counter-example the engine must handle correctly: a window from 14:00 to 17:00 where UVI drops steeply from 14:00–15:00 and then sits flat from 15:00–17:00. Endpoint averaging materially overestimates this. Write a unit test using exactly this shape.

Cache the interpolated curve; recompute only on new forecast fetch or window change.

### 4.3 Personal threshold

```
MED_personal_SED = MED_baseline(skinType) × userMultiplier × adaptationFactor
```

Three distinct terms, and they must stay separate:

- `MED_baseline` — fixed prior from skin type.
- `userMultiplier` — **how this person differs from their type.** Stable, learned slowly, does not decay. See §5.3.
- `adaptationFactor` — **how tanned they currently are.** Dynamic, rises with cumulative dose, decays during gaps. See §4.5.

Do not collapse these into one number. Conflating "this user is unusually sensitive" with "this user is currently untanned" produces wrong behaviour after every break in exposure.

Baseline priors (untanned skin):

| Type | MED (SED) |
|---|---|
| I | 2.0 |
| II | 2.5 |
| III | 3.0 |
| IV | 4.5 |
| V | 6.0 |
| VI | 10.0 |

`userMultiplier` starts at **1.0** and is learned from logs (§5).

### 4.4 Target dose

Default target: **0.90 × MED_personal**. Make this a tunable constant, not a magic number — expose it in settings as a conservative/standard/aggressive selector mapping to roughly 0.75 / 0.90 / 0.95.

Sanity check the maths: for type II at multiplier 1.0, target = 2.25 SED = 150 UVI-minutes. So the unprotected window at steady UVI is `150 / UVI` minutes. At UVI 7 that's ~21 minutes. Assert this in a test.

### 4.5 Adaptation and escalation — the plateau problem

**This is a first-class feature, not a refinement.** It's the single most common failure mode for anyone tanning deliberately, and the app exists partly to solve it.

**The mechanism.** As a tan develops, two things raise the burn threshold: melanin (worth roughly SPF 2–3 at full development) and epidermal thickening, which blocks UV independently of pigment. Because melanogenesis for fair skin requires a dose *near* the burn threshold (§4.4, Learn Module 5), a fixed dose that worked in week one becomes sub-threshold by week three. The user stops gaining colour while doing everything the same. The correct response is to escalate the dose as the threshold rises.

**Model.** Track `adaptationFactor`, starting at 1.0:

```
adaptationFactor = 1 + adaptationGain × tanState
tanState ∈ [0, 1]
```

- `tanState` rises with cumulative recent effective dose, with **diminishing returns** — it must saturate, not grow without bound. Each skin type has a real biological pigment ceiling.
- `adaptationGain` caps the total achievable increase at roughly **2.0–2.5×** for types I–III. Do not let this run higher. The literature supports SPF 2–3 from a full tan plus a modest thickening contribution; anything beyond that is unsupported and dangerous.
- Type-dependent: types IV–VI adapt further and faster.

**Decay — critical for safety.** `tanState` decays toward zero with a half-life of roughly **3–4 weeks** without exposure, reaching baseline by about 8 weeks. The epidermal thickening component decays faster than the pigment component; a single combined decay term is acceptable for v1, but bias it toward the faster end.

This decay is the main burn-prevention mechanism in the whole model. The classic injury is a user who takes three weeks off, returns at the dose that felt easy in August, and burns badly because their threshold has fallen back. On resuming after a gap of more than ~2 weeks, the app should explicitly surface this: *"Your tolerance has dropped since your last session — today's recommendation is shorter than what you were doing."*

**Escalation behaviour.** As `adaptationFactor` rises, the target dose rises with it, so recommended session length grows. This should be visible and explained, not silent — a line such as *"Your threshold has risen since you started. Today's session is longer than your first because a fixed dose would no longer trigger new pigment."* Deep-link to Learn Module 6.

**Ceiling handling.** When `tanState` approaches saturation and logged sessions stop yielding new colour (Q3 in §5.2 returning "no" repeatedly at high `tanState`), stop escalating and **say so honestly**: they have likely reached their biological maximum, and further dose buys damage without colour. Do not keep lengthening sessions in pursuit of a result that isn't available.

**Do not let adaptation imply safety.** Increased tolerance means the *visible* response saturated, not the damage. Cumulative dose tracking (§5.5) continues regardless, and the seasonal total should remain prominent as adaptation climbs.

### 4.6 The sunscreen inversion

This is the interesting part and the app's main differentiator. The user fixes the *time*; the engine solves for the *filter*.

Given a window that would deliver `raw_SED` and a target of `target_SED`:

```
required_attenuation = raw_SED / target_SED
```

If `required_attenuation <= 1.0` → no sunscreen needed for the tanning goal (still surface the option, and still say so if UVA load is high — see §4.8).

If `> 1.0`, solve for a realistic product + application pair using the exponential density model:

```
SPF_effective = SPF_label ^ (density_mg_per_cm2 / 2)
```

Reference points that must be reflected in output:
- 2.0 mg/cm² → full labelled SPF (lab standard, essentially nobody does this)
- 1.0 mg/cm² → √(SPF_label)
- 0.5 mg/cm² → SPF_label^0.25

**Default assumption when the user doesn't specify: 1.0 mg/cm², i.e. square root of label.**

Output should be phrased the way a person thinks, not as a density figure:

- *"SPF 30, applied thinly"* (~0.5 mg/cm²)
- *"SPF 30, applied normally"* (~1.0 mg/cm²)
- *"SPF 50, applied thickly — a full shot glass for your whole body"* (~2.0 mg/cm²)

Prefer solutions the user can actually execute. If several combinations work, favour a moderate SPF applied properly over a high SPF applied thinly, and say why (the exponential relationship means application quality dominates label number). Include a plain-language line explaining this on the result screen.

Where the required attenuation exceeds what any realistic combination delivers, say so directly and recommend shortening the window instead.

### 4.7 Edge cases — all must be handled explicitly with useful copy

These are not error states. They're legitimate answers, and handling them well is a large part of the app's value.

1. **Window too weak to matter.** Total achievable dose is far below the melanogenic threshold — e.g. type II, 17:00–18:00, northern latitude, UVI 2 and falling. Tell them plainly: this window will not produce a lasting tan, here's the shortfall, here's when the next viable window is. Do not manufacture a reassuring number.
2. **Window massively overshoots.** Even with the best realistic sunscreen the dose is dangerous. Recommend a shorter sub-window and show which sub-window is optimal.
3. **Optimal sub-window exists.** If the user gives a 3-hour availability but only needs 25 minutes, recommend *which* 25 minutes — the highest-UVB-fraction slice, which in practice means as close to solar noon as their window permits. Explain the reasoning briefly (see Learn Module 3).
4. **No viable day.** Winter, high latitude — UVI never reaches useful levels. Say so seasonally, not as an error.
5. **Stale or missing forecast.** Show age of data prominently; block confident recommendations on data older than ~6 hours.
6. **User already logged a session today.** Carry forward accumulated dose and subtract it from today's remaining budget.
7. **Cloud cover.** WeatherKit's UVI already accounts for forecast cloud, but note in the UI that actual conditions vary and thin cloud passes most UV.

### 4.8 UVA note

The UV Index is erythema-weighted and therefore close to blind to UVA. When the user's window sits well off solar noon, surface a note that they're getting a comparatively UVA-heavy dose — worse ratio of photoaging to durable pigment. Link to Learn Module 3.

---

## 5. Logging and the calibration loop

This is what makes the app improve rather than just calculate. Build it properly.

### 5.1 Prompt timing

**Prompt the day after the session, not the same evening.** Erythema peaks at 12–24 hours. A same-day "did you burn?" collects near-worthless data. Schedule a local notification for roughly 18–24 hours post-session.

### 5.2 What to ask

Plain language only. Never expose MED or SED in the logging flow.

**Q1 — "How does your skin look today?"**
- Normal, no colour change
- Slightly warm or faintly pink
- Clearly pink
- Red and sore
- Very red, painful, or blistered

**Q2 (conditional, if any redness) — "When did it show up?"** — helps distinguish genuine erythema from immediate darkening.

**Q3 (3–5 days later, separate lightweight prompt) — "Did you notice lasting colour?"** This measures the melanogenic outcome, which is the actual goal, and is distinct from the burn question. Yes / a little / no.

### 5.3 The multiplier update

Map each response to an implied MED ratio (i.e. what fraction of the user's true MED the delivered dose apparently represented), then update.

**Confidence-weighted update — this is the specific behaviour requested, implement it exactly:**

```
weight = k / (n + k)          // n = number of prior logs, k ≈ 2.5
multiplier_new = multiplier_old + weight × (implied_multiplier − multiplier_old)
```

So the first log moves the multiplier a long way; the twentieth barely nudges it. A single bad session after three weeks of good data should not swing the estimate.

**Asymmetric weighting — important.** A burn is strong evidence (the threshold was definitively crossed). "Nothing happened" is weak evidence (the threshold was somewhere above the dose — censored data, you don't know how far above). Weight burn observations roughly 2× the no-reaction observations.

**Separating adaptation from sensitivity — do not skip this.** When a log arrives, the implied threshold must be divided by the `adaptationFactor` in force at the time of that session *before* it updates `userMultiplier`. Otherwise the model attributes a tan-driven rise in tolerance to intrinsic sensitivity, `userMultiplier` drifts upward all summer, and it never decays — so the first session after a winter break is calculated from a threshold the user no longer has. That is the exact path to a serious burn. Store the `adaptationFactor` alongside each session record so this normalisation is possible retrospectively.

This replaces the recency-weighting note below: seasonal adaptation is handled by `adaptationFactor` (§4.5), **not** by decaying `userMultiplier`.

**Additional rules:**
- Clamp `multiplier` to [0.5, 1.8]. Anything outside that suggests the skin type selection is wrong — prompt the user to revisit it rather than silently accepting an absurd value.
- A severe burn (blistering) triggers an immediate protective correction regardless of `n`, plus a suggestion to pause for several days and a pointer to Learn Module 7.
- **Discard or heavily discount logs flagged as confounded** — the log flow should offer a quick "anything unusual?" with options for photosensitising medication, illness/fever, water or snow reflection, altitude, or alcohol.
- Do **not** apply decay to `userMultiplier` to capture seasonal change — that is `adaptationFactor`'s job (§4.5). Mild recency weighting is acceptable only for genuine drift in intrinsic sensitivity (age, medication changes), and should be slow.

### 5.4 Visibility

Hidden by default, exposed **read-only in Settings** as something like "Your sensitivity: 15% more sensitive than typical for your skin type, based on 11 sessions." Offer a manual override for users who know their own skin, and a reset.

### 5.5 History

- Session log with date, window, computed dose, sunscreen used, and outcome.
- Cumulative dose view — weekly and seasonal totals.
- A simple tan-trajectory chart. Keep this honest: it's a record of dose, not a measurement of pigment.
- Local persistence via SwiftData. Export to JSON.

---

## 6. Learn tab

Content comes from `LEARN_CONTENT.md`, which is structured as 12 modules. Requirements:

- **Each module is a separate content file/object.** Editing one must not require touching any other, or any view code.
- **Render markdown**, including tables and links. Citations must be tappable and open the DOI link.
- **Preserve every citation.** Author names, article titles, and DOI links all render. They are not decoration — the whole point is that a reader can go check the claim.
- Several citations are marked `[VERIFY]`. Before shipping, confirm each resolves to the stated paper and correct it if not. Report back on any that don't resolve rather than quietly dropping them.
- Deep-linkable from the Calculator, so a result screen can point at the relevant explanation.
- Reading-progress tracking is a nice-to-have, not required.

Module 1 (or an equivalent first-run screen) should be shown during onboarding. The "there is no safe tan" framing is not optional and should not be softened.

---

## 7. Architecture — modularity requirement

I will be revising this repeatedly. Structure it so that changing Learn copy, tuning the dose model, and adjusting UI are three independent operations.

Suggested separation:

```
AcurasCore/          — pure Swift, no UI, no networking
    DoseCalculator       (integration, SED conversion)
    SunscreenSolver      (the inversion in §4.6)
    CalibrationEngine    (the multiplier update in §5.3)
    AdaptationModel      (tan state, escalation and decay in §4.5)
    Models               (SkinType, Session, DoseResult…)

AcurasData/          — WeatherKit client, location, caching, SwiftData

AcurasContent/       — Learn modules as data. No logic.

AcurasUI/            — SwiftUI views. No calculation.
```

- **All tunable constants in one configuration file.** Target fraction, MED baselines, `k`, clamps, decay rate, density assumptions. I want to change these in one place.
- `AcurasCore` must be pure and fully unit-testable with no mocking of network or system services.
- Content is data, never string literals in views.

**Required tests:**
- Trapezoidal integration against a known analytic curve.
- The 14:00–17:00 non-linear window from §4.2 versus a naive endpoint average — assert they differ and that the trapezoidal result is correct.
- Type II at UVI 7 → ~21 min to 0.9 MED.
- SPF density model at 0.5 / 1.0 / 2.0 mg/cm².
- Calibration convergence: simulate a user whose true multiplier is 0.75 and confirm the estimate converges within ~8 logs and is not destabilised by one outlier at log 15.
- Adaptation: simulate 6 weeks of regular sessions and assert `adaptationFactor` rises, saturates below the ~2.5× cap, and that recommended session length grows accordingly.
- Decay: simulate 6 weeks of sessions, then a 4-week gap, and assert the next recommendation is **materially shorter** than the pre-gap one. This test is the burn-prevention guarantee — treat a regression here as a release blocker.
- Separation: simulate a user with true `userMultiplier` 1.0 who tans normally, and assert `userMultiplier` stays near 1.0 rather than drifting upward as adaptation accumulates.
- Every §4.7 edge case produces useful output rather than a crash, a nil, or a fake number.

---

## 8. Tone and framing

The app should be **frank, not preachy, and not promotional**.

- It must never imply tanning is safe. Module 7's "no safe threshold" point is load-bearing.
- It must not moralise at a user who has decided to tan. Give them the accurate number and the honest cost.
- For type I and II users, be explicit that their margin is thin and that deciding it isn't worth it is a reasonable conclusion.
- Never present estimates as measurements. Show uncertainty, especially before calibration has data.
- Include a persistent, findable medical disclaimer. Sunbeds are out of scope and should be actively discouraged where they come up.

Note for App Store review: health-adjacent apps get scrutiny. Keep the disclaimer prominent, avoid any claim resembling medical guidance, and don't promise outcomes.

---

## 9. Build order

1. `AcurasCore` with full test coverage — the engine, standalone and correct.
2. WeatherKit integration and caching.
3. Calculator UI against the working engine.
4. Learn tab from `LEARN_CONTENT.md`.
5. Logging, notifications, calibration.
6. History and charts.
7. Polish, edge-case copy, accessibility.

Build the engine first and prove it with tests before any UI exists. If anything in this spec is ambiguous or looks wrong, raise it rather than guessing — particularly anything in §4, where a silent error produces a plausible-looking number that could burn someone.
