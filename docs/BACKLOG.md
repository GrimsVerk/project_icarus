# Backlog: project_icarus

Ideas and open questions not started yet. Move one to `next-steps.md` when you start it; delete it when done. Ids (`BL-<n>`) are cited from code and tests; don't reuse one.

## Open questions for the owner

- **BL-1** — S3's separation bound at 0.7× the modelled adaptation gain: does the multiplier have to stay within 0.10 of 1.0 after six weeks, or is 0.15 acceptable under the ruled constants (D-2026-09-03-T1: τ 7.2 d, half-life 21 d; k 2.5, burn weight 2)? Two independent simulations (the blind test author's and the coder's) both settle near 0.88: the app's escalating dose crosses the slower-adapting user's true line and two faint-pink reports move the multiplier, as R21 attributes them. Proposed default: hold the test at 0.15 and keep the 0.10 figure in S3 until the owner rules (widen S3, or retune a constant, or accept). LOW risk: a bound in a test and a §13 figure, cheap to reverse either way; it errs short (the estimate drops, never rises). — filed by: coder (core-engine, Slice 3)
- **BL-2** — The skin-check and lasting-colour flows show answer options (Q1's five answers, Q2's four timings, the region names, the five confounders, yes / a little / no) and the Learn tab needs a title, but `docs/APP_COPY.md` has no keys for them; the M5 and M4 views show the enum names split into words as data. Proposed default: the owner adds those keys to `docs/APP_COPY.md` (S17) and Core's `CopyKey` list, then a one-slice plan wires them. LOW risk: wording only, no schema; the views change one call each. — filed by: coder (the M5 orchestrator, at assembly)
