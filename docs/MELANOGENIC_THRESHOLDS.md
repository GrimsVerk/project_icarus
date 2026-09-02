# Addendum — Melanogenic Threshold by Skin Type

**Status:** Provenance note for the reviewer's item *"One target fraction for all skin types contradicts Learn Module 5; no melanogenic threshold in the engine."*

**Resolution accepted:** R1's three bands (I–II / III / IV–VI) plus `melanogenicFraction(skinType)`. Owner sets the final numbers.

**Purpose of this document:** The original table these numbers came from was built in June, for skin type III, before empirical testing established type II. Some of those figures were measured, and some were my extrapolation. This separates the two so the owner isn't setting numbers on top of an unmarked guess.

---

## 1. The original table

Built 2026-06-27. Format: **minutes to 1 MED (minutes to MMD in parentheses)**.

MED baselines used: **type II = 2.5 SED, type III = 3.5 SED, type IV = 5.0 SED.**
MMD/MED ratios used: **type II = 1.16, type III ≈ 0.95, type IV ≈ 0.75.**

| UVI | Type II | Type III | Type IV |
|-----|---------|----------|---------|
| 1 | 167 (194) | 233 (222) | 333 (250) |
| 2 | 83 (97) | 117 (111) | 167 (125) |
| 3 | 56 (65) | 78 (74) | 111 (83) |
| 4 | 42 (49) | 58 (55) | 83 (63) |
| 5 | 33 (39) | 47 (44) | 67 (50) |
| 6 | 28 (32) | 39 (37) | 56 (42) |
| 7 | 24 (28) | 33 (32) | 48 (36) |
| 8 | 21 (24) | 29 (28) | 42 (31) |
| 9 | 19 (22) | 26 (25) | 37 (28) |
| 10 | 17 (20) | 23 (22) | 33 (25) |
| 11 | 15 (18) | 21 (20) | 30 (23) |
| 12 | 14 (16) | 19 (18) | 28 (21) |

The pattern is the whole point: **type II's tan number is above its burn number. Type III's sits just below. Type IV's is comfortably below.** That crossover is what the current single 0.9 target fraction erases.

---

## 2. What is measured vs. what I extrapolated

### Measured — reasonable confidence

**The direction of the effect.** Wulf, Philipsen & Ravnbak (2010) is titled, in effect, *the MMD/MED ratio declines with increasing skin pigmentation*. That the ratio falls as skin darkens is a published finding, not my inference.
https://doi.org/10.1111/j.1600-0781.2010.00508.x

**Type II ratio = 1.16.** This is the repeated-exposure ratio for a source with roughly 5% UVB — i.e. solar-like. Single exposure with the same spectrum is 1.38.
⚠️ **Sourcing caveat, flagged at the time:** I took this from US Patent 11,311,744, which compiles published photobiology data in its Table 1. It attributes the figures to earlier work (likely the Wulf group) but does not identify the primary citation. **This is a secondary source and the 1.16 figure has never been traced to its original paper.** If any number in the engine deserves verification before shipping, it is this one.

**0.75 MED does not work.** Ten exposures over four weeks at 0.75 MED induced no pigmentation. Same patent, same caveat. This is the strongest argument that a sub-threshold target is not merely less effective but useless for fair skin.

**Repeated exposure lowers the per-session dose needed.** Six exposures over ~3 weeks roughly halves it; twelve roughly thirds it.
⚠️ I attributed this to "Wulf et al., Acta Derm-Venereol 2010" but the Acta paper in my reference list is Wulf, Sandby-Møller, Kobayasi & Gniadecki (2004), *Skin pigmentation kinetics after UVB exposure*, https://doi.org/10.1080/00015550410026948. **The year is likely a conflation of the two Wulf papers. Verify which paper carries this finding.**

### Extrapolated — my inference, not measured

**Type III ratio ≈ 0.95 and type IV ratio ≈ 0.75 are mine.** I said so explicitly when I produced the table.

The reasoning: MMD is roughly constant across phototypes II–IV while MED increases with pigmentation. If the numerator holds and the denominator grows, the ratio falls. I picked values consistent with that shape and with the published direction of travel.

**What I did not have:** directly measured repeated-exposure MMD/MED ratios for types III and IV. I had no data at all for types I, V, or VI — the original table did not cover them, and the type I and V/VI numbers in the current build prompt are inferred from the same shape argument.

---

## 3. The unresolved primary-literature conflict

Two credible studies disagree about type II, and the engine's behaviour for fair skin depends on which one you follow.

| | Source | Finding for type II |
|---|---|---|
| **Pathak & Fanselow (1983)** | Solar spectrum | MMD ≈ MED |
| **Wulf et al. (2010)** | Solar simulator + narrowband UVB | MMD ≈ 1.5–1.9 × MED (single exposure) |

The explanation is spectral: Pathak used actual solar light; the UVB-richer sources shift the ratio. **Since this app is for outdoor sun, Pathak is the more applicable one**, and that is why the protocol settled on ≈0.9–1.0 MED rather than deliberately overshooting into 1.5×.

Pathak & Fanselow: https://doi.org/10.1016/S0190-9622(83)70186-6

This is worth stating plainly in the engine's comments, because the two readings differ by nearly a factor of two and a future maintainer will otherwise assume one of them is a typo.

---

## 4. Discrepancy to reconcile before setting numbers

**The MED baselines in `BUILD_PROMPT.md` §4.3 do not match the ones behind this table.**

| Type | Build prompt | Original table |
|---|---|---|
| III | 3.0 SED | **3.5 SED** |
| IV | 4.5 SED | **5.0 SED** |

Both fall inside the published spread, but they are not the same numbers, and the table's minute values were computed from the second set. Pick one set and apply it consistently, or the derived times won't reproduce.

For reference, the type II figure is the best-supported one in the whole model: literature centres on **2–3 SED**, one study of 20 type II volunteers found 150–300 J/m² (mean ~2.4 SED), and 2.5 SED sits mid-range.

---

## 5. Suggested shape for `melanogenicFraction(skinType)`

Numbers below are **candidates traceable to §2, not recommendations.** Owner sets the finals.

| Band | Candidate `melanogenicFraction` | Basis | Confidence |
|---|---|---|---|
| **I–II** | 1.00–1.16 | Pathak (≈1.0, solar) to patent-sourced repeated-exposure figure (1.16) | Moderate — direction solid, exact value secondary-sourced |
| **III** | ~0.95 | My extrapolation | **Low — inferred** |
| **IV–VI** | ~0.75 | My extrapolation from type IV; V–VI unevidenced | **Low — inferred, and V–VI is extrapolation off an extrapolation** |

### Engine implications

**Target dose should derive from both thresholds, not from a fixed fraction of MED:**

```
melanogenicDose = MED_personal × melanogenicFraction(skinType)
targetDose      = min(melanogenicDose × headroom, MED_personal × safetyCeiling)
```

- **Types I–II:** because `melanogenicFraction ≥ 1.0`, the safety ceiling binds. Target lands at ~0.9–1.0 MED — riding the line, exactly as Learn Module 5 describes. The app should be explicit that there is no sub-erythemal option for these users.
- **Types III–VI:** `melanogenicFraction < 1.0`, so the melanogenic threshold binds instead and the target lands **below** MED. These users get a genuine no-redness protocol. The current uniform 0.9 both under-doses type III and needlessly pushes IV–VI toward a burn threshold they never needed to approach.

**Two cautions for implementation:**

1. **Do not let `targetDose` exceed MED for any type**, even though the type I–II melanogenic threshold sits at or above it. The correct behaviour is to sit just under, accept that pigment accrues slowly, and let repeated exposure tighten the ratio — not to deliberately dose into a burn.

2. **Watch for double-counting against `adaptationFactor` (§4.5).** The 1.38 → 1.16 tightening with repeated exposure and the rising tolerance modelled by `adaptationFactor` are overlapping descriptions of the same adaptation. If `melanogenicFraction` is also made to fall with exposure history, the two will compound and the engine will escalate too fast. **Pick one home for repeated-exposure effects.** My recommendation: keep `melanogenicFraction` static per band, and let `adaptationFactor` carry all exposure-history dynamics.

---

## 6. Summary for the owner

- The type II ratio (1.16) is usable but rests on a **patent compiling secondary data**, with the primary citation never traced.
- The type III and IV ratios are **my extrapolations**, presented as such at the time. They have never been validated against a measured source.
- Types I, V and VI have **no supporting data** in this project at all.
- The **direction** of the effect — ratio declines as pigmentation increases — is well supported and is the part worth trusting.
- Two MED baseline sets are currently in circulation. Reconcile before setting anything.

If the numbers matter enough to ship, types III–VI warrant a fresh literature pass rather than inheriting my June extrapolations. They were built to answer a question about type III skin that turned out to be the wrong question.
