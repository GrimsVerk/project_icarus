# Vision — project_icarus

**Not requirements.** `docs/DESIGN.md` says what gets built; this file says what
matters when two reasonable designs disagree. It is the tiebreaker an agent
reaches for when the evidence is genuinely ambiguous and nobody is awake to ask.

`CODEOWNERS` puts this file behind the owner, and that is not a restriction
bolted on — it is the mechanism. The oracle names, in every decision it writes,
the statement here that it leaned on (`docs/DESIGN.oracle.md`). When a decision
comes out wrong, the owner edits the statement rather than arguing with the
decision, and every future decision moves with it.

**An agent may WRITE this file. Only the owner LANDS it.** `/design` interviews
the owner and writes their answers into a branch, which is most of the work —
and then stops. The owner opens the pull request themselves, reads the diff, and
merges. That is checked, not asked for: `.github/scripts/owner-authored.sh`
fails any pull request touching this file that the owner did not open.

Every statement carries an id — `V1`, `V2`, … — running continuously across the
file. Ids are never renumbered; new statements are appended.

## What this project is for

- **V1** — This app is for people who actually want to develop a tan and stay
  clear of redness that persists into the next day. They put in the time slot
  they actually have and get an honest, specific answer: how long, which sides,
  which minutes, and how much sunscreen. The app learns their real skin from
  what happened the next day. It grows the dose as their tan grows and shrinks
  it after a break, so the classic burn after a holiday does not happen. The
  Learn section says it plainly: getting a tan has a cost to your skin, period.
  This is not something you do if you want to stay perfectly supple into your
  old age.

## Priorities, in order

- **V2** — Never under-warn. When two defensible numbers differ, the shorter
  session is the one shown, and the result names the uncertainty that made it
  shorter. "Says why" means the number moved, not that a range was drawn
  beside it. This bounds V1: escalation that could be either right or early is
  late.
- **V3** — Honest over reassuring. Say what is known precisely. Say what is
  uncertain as a range. Never dress one up as the other, and never present an
  estimate as a measurement.
- **V4** — The engine is correct before anything is pretty. A failing decay
  test blocks a release.
- **V5** — Copy and citations are data. Changing them never touches code, and
  no citation is ever paraphrased, summarised, or dropped. A citation may be
  corrected only so that it resolves to the paper it names — identifier, year,
  venue — never in wording, and every correction is listed in
  `docs/reviews/citations.md`.
- **V6** — Zero running cost. Revenue comes from one small non-personalised
  ad banner. No user data leaves the phone beyond what that banner needs to
  load, and it never carries a tracking identifier.
- **V7** — Fewer controls over more options. The calculator asks exactly what
  the engine needs — window, posture, the cover toggle, a sunscreen choice, and
  whether the user stays the whole window — and nothing else. A choice the user
  would make once lives in Settings; a choice they would never make lives in
  Tunables; a Settings item that does not change a number the user acts on is
  not added. Polish matters; it does not need to be flashy to be polished.

## What I would trade away

- **V8** — Animation and flair. They are not important.
- **V9** — Breadth: Watch, widgets, iPad, other languages, other weather
  sources. Later is fine, and no design decision may block any of them.

## Core tenets

- **V10** — No screen, notification, or line of copy may state or imply that
  tanning is safe, or soften the "there is no safe threshold" point.
- **V11** — The only network calls are the weather fetch, the location lookup
  that feeds it, and the ad banner in non-personalised mode. No accounts. No
  analytics. No tracking identifier, ever.

## Durable evidence is a requirement, not a nicety

**This section is not a question for you to answer.** It is a statement about
how unattended operation works here, kept in the vision file for one reason:
the oracle must be able to *cite* it. A decision to add a measurement needs
something in this document standing behind it, and without this section there
is nothing.

The owner's ruling, in their words:

> the data needs to be collected in a sensible way so that future runs can be
> improved by not repeating mistakes… if a change is necessary in an unattended
> run that goes outside or misses built in data collection mechanisms, then new
> data collection mechanisms need to be added to track the performance of the
> changes that are downstream of the oracle's ruling.

What follows from it, and what is already built:

- **A run leaves a record.** `docs/runs/<timestamp>/run.md` — committed, on its
  own pull request, at every stop whatever the reason. The run log used to be
  gitignored, and in a web session it lived in a container that is reclaimed, so
  the evidence that would tell the next run what went wrong was destroyed by
  default.
- **The review gate keeps what it was shown and what it said.**
  `docs/runs/<timestamp>/reviews/` holds the payload and the reply for every
  review in that run. It is the only load-bearing gate with no fixtures, and it
  was also the only one leaving no trace to build fixtures from.
- **A change nothing can observe is a change nobody can evaluate.** When a
  decision alters behaviour that no existing check, test, run report or review
  artifact would notice, adding the thing that notices is part of the decision —
  not a follow-up, and not optional. This is what the owner's ruling means by
  measurements "downstream of the oracle's ruling", and an oracle decision may
  cite this statement to justify adding one.

**On space.** Committed evidence grows, and the owner has weighed that
deliberately: *"i would rather risk gathering too much data and deal with space
issues, than getting stuck without the info to get out of it."* A space problem
is visible, bounded and fixable later; missing evidence is none of those. If it
becomes a problem the answer is a retention rule — prune payloads older than N
runs, keep every verdict — and never a return to discarding them.

## What makes an answer unacceptable

- **V12** — A confident-looking number with no basis. A rule, a constant, or a
  line of copy that cannot be traced to a citation, a logged report, or an
  entry in the tunables file that carries its citation or the word
  `assumption` with a one-line rationale. "Trace" means a reader of the
  repository: every figure on the result screen is reproducible from the JSON
  export and the tunables version it carries, and a result that depends on an
  `assumption` constant is labelled an estimate on screen. A file is not a
  basis; a note beside the number is.
- **V13** — A skin-type description, or any copy, that is folksy enough to be
  misread. Factual, tolerable to a sensitive reader, never ridiculous.
- **V14** — An ad next to a number the user acts on. The banner is small and
  it stays on the two entry screens, which carry no figure at all; it never
  appears on the result, the flip timer, onboarding, a skin-check prompt,
  History, or Settings.
- **V15** — A number past the burn line. No setting, no adaptation, and no
  calibration may plan a dose above the user's personal threshold. Aggressive
  means at the line, never past it, and it unlocks only after the app has seen
  the user's skin react.
