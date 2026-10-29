# project_icarus: rules for agents

An iOS app that plans sun exposure for a durable tan while staying under the user's burn line.

## Every session

- Read `next-steps.md` first. Write your task there before you start; delete it when done. Nothing may live only in chat: the next session starts fresh with only these files.
- One feature per session.
- When unsure, pick a reasonable default, note the assumption (in `docs/DECISIONS.md` if it will matter later), and keep going.
- Read the owner's whole message before acting (the last word on a point wins). Say so when an instruction contradicts something already settled.

## Files

- `docs/VISION.md`: what matters, the tiebreaker. `docs/DESIGN.md`: what we are building (requirements `R<n>`, success criteria `S<n>` in §13). Both change only with the owner's OK.
- `docs/DECISIONS.md`: settled decisions and owner rulings (`D-...`). Don't relitigate them.
- `docs/BACKLOG.md`: ideas and open questions not started. `docs/architecture.md`: what exists and how data flows; update it when components change.
- `docs/BUILD_PROMPT.md`, `docs/MELANOGENIC_THRESHOLDS.md`: the owner's inputs. `docs/LEARN_CONTENT.md` is the only source of Learn text: never paraphrase it; run `scripts/split-learn-content.sh` after editing and commit the result. `docs/APP_COPY.md`: app copy, every line owner-approved; a line with an `- id:` is provisional (D-2026-10-29-C1) and keeps its id for good. After editing it run `scripts/build-app-copy.sh`, and `scripts/copy-review.py <file>` for the owner's readable list (now `../review/icarus-copy.html` from the main checkout).

## Working

- Non-trivial work: plan it in plan mode first. `/adversarial-review` attacks a plan before you build it (optional).
- A feature too big for one context: `/orchestrate`.
- Work on a branch, never on `main`. Run the checks below locally, then open a PR and merge it (`gh pr merge --rebase --delete-branch`). CI runs only on `main`; a red `main` is the next task.
- Never force-push, rewrite pushed history, or skip hooks (`--no-verify`).
- Paths in repo files are relative, so any computer can resume the work. Machine-specific values go in one gitignored local file with a committed `.example`.
- No new dependency without the owner's approval, recorded in `docs/DECISIONS.md` (what for, why not the standard library, licence).
- Every engine constant lives in `Sources/IcarusCore/Tunables.swift` with its citation or `assumption` plus a one-line reason (V12).

## Checks

```sh
swiftformat --lint . && swiftlint lint --strict --quiet
swift test && for s in acceptance/S*.sh; do "$s"; done   # Core, Content, Data; Linux or macOS
xcodegen generate && xcodebuild test -project ProjectIcarus.xcodeproj -scheme ProjectIcarus \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO   # macOS only
```

One root `Package.swift`; targets in `Sources/`, tests in `Tests/<Target>Tests`, the app shell in `App/`. On Linux only IcarusCore, IcarusContent and IcarusData build; IcarusUI, IcarusAds and `App/` need Xcode (nightly CI). `ProjectIcarus.xcodeproj` is generated from `project.yml`; edit `project.yml`, never the project.

## Tests

- Test behaviour, not implementation. Keep tests that protect what matters: core user flows, anything that can lose data, payments.
- Tests run offline and deterministically: no real network, clock or randomness. XCTest, not Swift Testing.
- Each unmarked criterion in DESIGN §13 has `acceptance/S<n>.sh`: exit 0 is pass, stdout is the evidence. `(owner)` criteria get no script.
- For logic with a clear interface, the `test-writer` subagent can write tests from the spec while you write the code.
- Never call something verified that you could not run here; say what is unverified.

## Processes and agents

- Never stop processes or agents by name pattern (`pkill -f`, `killall`): other agents run identical commands. Stop only what you started, by its own ID.
- Before a big fan-out of subagents, check remaining usage; hitting the limit mid-run kills them all.

## Licensing

PolyForm Shield 1.0.0 (`LICENSE`, the owner's choice). Don't change it or add other licences or licence fields. Outside contributions need a CLA first; until one exists, merge no outside code.
