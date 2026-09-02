# Pseudocode pass — batch 1 for the owner

Stage 5 of `docs/design-flow.md`. Every item below is a structural pick the
pass had to make (it changes file layout, a Signatures block, or something
expensive to reverse). Each arrives pre-chewed: the question, the default
already applied in the plans (the trunk), the alternative, and why the trunk
won. Small picks were made in the pseudocode and are not listed.

Rule with "1a" style answers, or "all trunks".

| # | Question | Trunk (applied) | Alternative | Why the trunk |
|---|---|---|---|---|
| F1 | Package layout | One root `Package.swift` with five library targets under `Sources/<Target>` and `Tests/<Target>Tests`; app shell in `App/`; `project.yml` references the local package at `.` | Five separate packages under `Packages/`, each with its own manifest | The template's checks already look at `Sources/` and `Tests/`; one `swift test --filter` command runs the engine on Linux; dependency enforcement is identical because target dependencies are explicit either way |
| F2 | The coupled lying-down solve (every region limits) | Independent per-side optima, then one scalar `s ∈ (0,1]` shrinks both sides by bisection until the head-and-shoulders credit fits | A two-variable linear programme under three constraints | Monotone, exact to a second in 40 iterations, no library, trivially testable; the LP is more code for the same answer |
| F3 | Discrete form of the tan-state integrator | Per-event update: decay by elapsed time, then `tanState += (1−tanState)(1−exp(−f·mult/τ))`; τ solved offline so 21 daily standard sessions reach 0.8 for types I–III | A day-by-day simulation loop | Exact for sparse events, O(events), replay-friendly; the loop is slower and no more faithful |
| F4 | Learn module files | A script splits `docs/LEARN_CONTENT.md` into twelve committed resource files; S7 fails on drift | Hand-split files, with the design document as a mirror | One source of truth; editing a module is editing one section of one document |
| F5 | Test framework | XCTest everywhere | Swift Testing | The template's placeholder and scripts assume XCTest; XCTest runs on Linux with the Swift 6 toolchain; nothing in the plans needs Swift Testing's features |
| F6 | Engine tests on a Linux runner | A `core-tests` CI job on `ubuntu-latest` runs `IcarusCoreTests` and `IcarusContentTests`; macOS keeps the app build | Everything on macOS | Cuts the expensive runner to what needs Xcode; the owner adds `core-tests` to the ruleset after the first green run (owner cost, M1) |
| F7 | Copy keys | A Swift `enum CopyKey` in Core; Content maps keys to text from `docs/APP_COPY.md` via a generated JSON; S11 checks both directions | String keys | The compiler catches a missing key; the enum is the contract between engine outcomes and copy |
| F8 | Which side first while lying | The timer asks (face up / face down), default face up; without the timer, face up | Always face up | Asking is one tap and the engine needs it; V7 allows exactly what the engine needs |

## Not forks, for the record

- The mega-forks the reviews named (session lifecycle, forecast horizon, state
  model, tolerant evidence, sunscreen input, provenance, replay inputs) are
  closed in the design and are implemented as ruled; none re-opened.
- The Linux Swift toolchain in the agent's container is a network-policy
  question, not a design pick; until it is allowed, `core-tests` in CI is
  where the engine tests run.
