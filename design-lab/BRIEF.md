# Design lab brief (shared by every design)

The owner of Icarus, an iOS app that plans sun exposure for a lasting tan while
staying under the user's burn line, finds the current app "a bit boring, very
colorless". This lab holds 10 fundamentally different clickable phone
prototypes. The owner will open them on an iPhone 16 and judge them by feel;
favourites get built into the real SwiftUI app later. These are explorations:
be bold, don't feel constrained by the current look (iOS grouped lists, system
blue, no colour).

## What the app is (read before designing)

- `../README.md`, `../docs/VISION.md` (tone rules V2, V3, V10, V13: never
  imply tanning is safe; honest; not folksy), `../docs/DESIGN.md` §1-4 for the
  use cases.
- `../docs/APP_COPY.md`: every UI string, with ids. Use the real copy, via
  `ICARUS.t(key, vars)` from `shared/copy.js`, not your own wording, for
  everything the real app says. You may add a design's own small labels
  (section names, a mascot's interjection) but no new claims about skin or
  safety. Learn text is verbatim: render it with `ICARUS.md(module.md)`.
- Screenshots of the current app: in the caller's brief (plain iOS lists).

## Screens and flows each prototype must have

Everything clickable; one HTML file per design.

1. **Plan** (tab 1, CALC-*): slot From / Until (today), posture (Lying down,
   turning over / Up and about), Head and shoulders covered (+ footnote),
   Staying the whole slot (+ footnote), Plan this slot. Due rows (DUE-1 skin
   check for Friday, DUE-2 lasting colour from Tuesday 9 June) that open their
   flows. History and Settings reachable from here.
2. **Loading** between Plan and the answer (forecast fetch, ~0.8-1.5 s), with a
   design-specific loading state.
3. **Your answer** (RES-*, FIG-*): the headline outcome, its figures (minutes,
   per side, range low/high, per-region plan dose, left today, this cycle),
   the notices (boundByMelanogenic, conservativeUntilCalibrated,
   coverToRunLonger, cloudCaveat, with Learn links that jump into the Learn
   reader), the sunscreen line, place line (Forecast for your location, Change
   place, Refresh forecast), I don't have that SPF, I did this (→ RES-9 Logged
   state), Start the flip timer (lying only). The answer must react to the
   inputs: use `ICARUS.results.lyingBest / lyingCovered / upBest / stayWhole`,
   and show at least one edge case (e.g. a slot that has passed → windowPassed,
   an evening slot → tooWeak + uvaHeavy) when the user enters such times.
   Do the number, not the range: the range is secondary (RES-6).
4. **Sheets**: The sunscreen you have (SUN-*: SPF picker + application, Use
   this → re-solved line `alternativeShadeForRest` / `alternativeWholeWindow`),
   Change place (PLACE-*: search field, results, PLACE-3 not found).
5. **Flip timer** (TIM-*): Which side is up first?, Start, running state with
   big countdown (until you turn over / until the session ends), small
   countdown (left in the session), Now: face up, turn-over moment, Stop +
   footnote, session end. Provide a visible but unobtrusive demo speed-up
   (e.g. a "×60" chip) so the owner can watch a whole session in ~40 s.
6. **Skin check** (SKIN-*, DID-*): Did you do this session? → sunscreen
   question → times → How does your skin look today? (5 answers) → When did it
   show up? → Where? → Anything unusual? → Send report → Report saved +
   effect line (FILL-7..11). Also **Lasting colour** (LC-*).
7. **History** (HIST-*): trajectory chart (trajectoryTitle), days with
   sessions, per-region SED, skin answers, unreportedDays, session detail
   (What you did / What you were shown / The forecast it used), Export /
   Import (with the import warning).
8. **Settings** (SET-*): skin type row, How close to your line
   (Conservative / Standard / Aggressive-locked with aggressiveLocked line),
   sensitivity sentence, manual stepper + reset, week and cycle totals,
   your data (export, share, import, delete with deleteHistoryWarning and
   confirm), About (attribution, privacy policy, disclaimer).
9. **Learn** (tab 2): the 12 modules list and a reader that renders a whole
   module (headings, tables, formula, sources block). Deep links from the
   answer's notices open the right module.
10. **Onboarding**: Module 1 page, Before you start (disclaimer + I have read
    this), Your skin type (6 types + Take the questionnaire → the 10-question
    quiz → QUIZ-3 result), Two permissions, Start. Show it on first load of
    the page OR make it reachable (e.g. a "Replay onboarding" item in
    Settings); pick what suits the design, but it must be reachable.
11. **Ad banner** placeholder (VO-14 "Advertisement") on the two entry screens
    only (Plan, Learn list), never on the answer, timer, onboarding, prompts,
    History or Settings. Small, honest, designed to fit.

Depth over breadth: transitions between every screen, pressed states,
spring/ease motion that suits the design, a sheet that can be dragged down,
scroll that feels native (`-webkit-overflow-scrolling`, `overscroll-behavior`),
haptic ticks (`ICARUS.haptic()` inside tap handlers; real haptics on iOS 18+),
loading, empty (HIST-6 after Delete history) and error states where they fit.

## Technical rules (hard)

- One self-contained file per design: `design-lab/dNN-<slug>.html`. Inline
  CSS and JS. Load the shared files with relative paths, in this order, at the
  end of `<body>` (before your own script):
  `shared/copy.js`, `shared/learn.js`, `shared/icarus.js`,
  `<script src="shared/switcher.js" defer></script>`. Don't edit `shared/`;
  if something there is wrong or missing, work around it in your file and
  say so in your report.
- Starts with `<!doctype html>`, `<meta charset="utf-8">`,
  `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">`,
  a short `<title>` (the design's name, e.g. `Gnomon`), and
  `<meta name="theme-color">` in the design's colour.
- External scripts ONLY from cdnjs.cloudflare.com, cdn.jsdelivr.net/npm or
  unpkg.com with an exact pinned version (prefer none: plain JS/CSS/SVG/canvas
  is enough). Fonts/stylesheets ONLY from Google Fonts. No other network calls,
  no images from the web: draw with SVG, CSS, canvas, or generate them.
- localStorage/sessionStorage only through `ICARUS.store` (never required).
- iPhone 16 viewport 390 x 844, mobile Safari: use `100dvh`, `env(safe-area-inset-*)`
  for top (status bar / Dynamic Island, ~59 px) and bottom (home indicator,
  ~34 px), tap targets >= 44 px, `touch-action` and `user-select` where
  needed, `-webkit-tap-highlight-color: transparent`. No horizontal page scroll
  at 390 px (long words and URLs wrap). On a desktop browser, centre the app
  in a 390 x 844 phone-sized frame (e.g. `@media (min-width: 600px)`).
- Leave the floating switcher tab (right edge, ~40% height, 30 x 52 px) usable:
  nothing of yours should need to sit under it permanently.
- Keep each file under ~400 KB.
- Respect `prefers-reduced-motion` with a calmer variant where cheap.

## Check your work

`python tools/shoot.py <page.html> <out_prefix> step...` (Chrome headless via
Playwright, 390 x 844, mobile): steps `shot:name`, `click:<css or text=...>`,
`tap:x,y`, `wait:ms`, `scroll:<css>:px`, `js:code`. It prints console errors,
page errors and horizontal overflow. Put screenshots in your scratch folder,
not in the repo. Walk every flow, look at the screenshots, and fix what looks
broken or bland. Note that headless Chrome is not iOS Safari: avoid features
Safari lacks (e.g. check `:has()` is fine, CSS `@property` is fine in Safari
16.4+, no `scrollend` reliance).
