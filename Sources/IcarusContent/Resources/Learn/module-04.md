## Module 4 — Dose: MED, SED, and Why We Count in Units

To plan sun exposure you need a unit, the way a recipe needs grams rather than "some."

**SED (Standard Erythema Dose)** is a fixed physical unit of sunburn-weighted UV energy. It is the same for everybody — it's a measure of the *light*, not of you. One SED equals 100 joules per square metre of erythemally weighted UV.

**MED (Minimal Erythemal Dose)** is the dose *your particular skin* needs before it goes visibly pink about a day later. This varies enormously between people, which is why the app calibrates it to you over time.

Rough starting values for untanned skin:

| Skin type | Typical description | Approx. MED |
|---|---|---|
| I | Always burns, never tans | ~2 SED |
| II | Burns easily, tans slightly | ~2.5 SED |
| III | Burns moderately, tans gradually | ~3 SED |
| IV | Burns rarely, tans easily | ~4.5 SED |
| V | Very rarely burns, tans darkly | ~6 SED |
| VI | Never burns | ~10 SED |

These are **starting guesses only**. Two people who both count as type II can differ by 30% or more. That's what the app's logging is for.

**Converting UV Index to dose.** A UV Index of 1 delivers 1 SED in about 67 minutes. So:

> **Minutes to reach 1 SED = 66.7 ÷ UV Index**

For type II skin, one MED is 2.5 SED, so at a steady UVI of 7 you'd hit your burn threshold in roughly `2.5 × 66.7 ÷ 7 ≈ 24 minutes`.

> **Sources**
> - Diffey BL, Jansén CT, Urbach F, Wulf HC. *The standard erythema dose: a new photobiological concept.* Photodermatology, Photoimmunology & Photomedicine, 1997. https://doi.org/10.1111/j.1600-0781.1997.tb00110.x
> - Fitzpatrick TB. *The validity and practicality of sun-reactive skin types I through VI.* Archives of Dermatology, 1988. https://doi.org/10.1001/archderm.1988.01670060015008
> - International Organization for Standardization. *ISO 17166:1999 — Erythema reference action spectrum and standard erythema dose.*
