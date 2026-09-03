---
slug: logging-calibration
status: draft
created: 2026-09-02
design: M5 — Logging and calibration
covers: [R20, R23, R24]
format: pseudocode
---

# Logging and calibration — Plan

## Summary

The loop that makes the app learn: the one-per-day skin check that opens
with "did you do this session?" for planned sessions, Q1, Q2, region and
confounders; the four-day lasting-colour prompt; both by notification and
in-app; the answers flowing through the store into replay; the sensitivity
sentence, the unreported-days count, and the weekly and cycle totals.

Non-goals:
- We do NOT compute the update here; `CalibrationEngine` and `Replay` (M1) do, and this milestone only feeds them records.
- We do NOT draw the trajectory chart (M6).
- We do NOT show MED or SED anywhere in the prompt flow.

Owner costs:
- None.

Rulings: D-2026-09-03-F5, F7 (docs/DECISIONS.md); design revision 3 for log = report and prompt scheduling

## The slices

## Slice 1 — The skin-check flow: did you do it, how does it look, when, where, anything unusual

- **Delivers:** Tapping the day-after notification, or the in-app due card, opens the skin-check flow for that day: one "Did you do this session?" per still-planned session (yes logs it with editable times, no discards it), then Q1 with five plain answers, Q2 if any redness, the region picker defaulting to "all exposed", and the confounders list; submitting writes one `SkinReport` for the day and the store's state is replayed. MED and SED never appear.
- **Files:** `Sources/IcarusUI/Prompts/SkinCheckFlow.swift`, `Sources/IcarusUI/Prompts/DidYouDoThisView.swift`, `Sources/IcarusUI/Prompts/SkinCheckModel.swift`, `Sources/IcarusUI/Prompts/DuePromptsCard.swift`, `App/NotificationRouting.swift`, `Tests/IcarusUITests/SkinCheckModelTests.swift`
- **Estimate:** ~460 lines

### Signatures

```text
@MainActor public final class SkinCheckModel: ObservableObject {
    public init(env: AppEnvironment, day: DayKey, channel: Channel)
    @Published public private(set) var planned: [SessionRecord]         // still-planned sessions that day
    @Published public var answer: SkinAnswer?; @Published public var timing: RednessTiming?; @Published public var region: ReportRegion = .allExposed
    @Published public var confounders: Set<Confounder>
    public func didDo(_ id: UUID, actual: Window) async throws          // logs with planned doses re-derived from the stored curve
    public func didNotDo(_ id: UUID) async throws                       // discards
    public var canSubmit: Bool                                          // answer set; timing set iff answer != .normal
    public func submit(now: Date) async throws -> CalibrationEffect     // one report per day; returns the effect for the confirmation copy
}
public struct DuePromptsCard: View { public init(env: AppEnvironment) }   // lists PromptScheduler.dueInApp on the Calculator entry (inputs-only rule: a card with no figure)
// App/NotificationRouting: taps on "skin-<day>" → SkinCheckFlow(day, .notification); "colour-<day>" → LastingColourFlow
// Promises (S10): submit twice on one day → the second throws .alreadyReported; timing required iff redness; submit after didDo logs the planned session first;
//  confirmation copy key follows the effect (.reclassifiedAsNormal → .immediateDarkeningExplained with Module 2 link; .clampHit → .revisitSkinType; .blisterCorrection → .pauseSuggested)
```

### Internals

```text
SkinCheckFlow pages: DidYouDoThis (repeat per planned) → Q1 → (Q2 if redness) → Region → Confounders → Confirmation
didDo(id, actual): doses = ExposureModel doses over actual sub-intervals with the stored curve and the confirmed sunscreen (recomputed from the record's stored curve so a late "yes" is honest); history.log(...)
submit: report = SkinReport(day, reportedAt: now, answer, timing, region, confounders, channel); history.addReport(report); effect = CalibrationEngine.apply(...) recomputed by the store's replay (the store returns the last effect for the confirmation)
```

## Slice 2 — Lasting colour, in-app fallbacks, and the unreported count

- **Delivers:** Four days after a reported day the lasting-colour prompt asks yes / a little / no and attaches to that day's report; with notifications denied or a prompt ignored, the Calculator entry shows a due card inside the in-app windows and Settings counts unreported session days; answering removes the card.
- **Files:** `Sources/IcarusUI/Prompts/LastingColourView.swift`, `Sources/IcarusUI/Prompts/LastingColourModel.swift`, `Tests/IcarusUITests/LastingColourModelTests.swift`, `Tests/IcarusDataTests/PromptSchedulerInAppTests.swift`
- **Estimate:** ~220 lines

### Signatures

```text
@MainActor public final class LastingColourModel: ObservableObject {
    public init(env: AppEnvironment, day: DayKey, channel: Channel)
    public func submit(_ lc: LastingColour) async throws       // store.setLastingColour(day, lc)
}
// Promises (S10): with notifications denied, a session day is due in-app from 12 h to 72 h; a reported day is due for colour from 3 to 10 days; Settings.unreportedDays == days with sessions and no report
```

### Internals

```text
DuePromptsCard reads env.prompts.dueInApp(history, now) on appear and on foreground; each row opens the matching flow with channel .inApp
```

## Slice 3 — Totals in the store and the sensitivity sentence in Settings

- **Delivers:** Weekly and cycle-to-date totals per region are computed from the history and shown in Settings; the sensitivity sentence renders from the replayed multiplier and report count; the S3 simulation is re-run through the real store (fake provider, in-memory SwiftData) so the whole loop is exercised end to end, and S18's use case 7 fixture passes.
- **Files:** `Sources/IcarusUI/Settings/TotalsView.swift`, `Tests/IcarusDataTests/EndToEndCalibrationTests.swift`, `Tests/IcarusCoreTests/Fixtures/UseCases.swift`, `acceptance/S10-logging.sh`
- **Estimate:** ~260 lines

### Signatures

```text
public struct TotalsView: View { public init(totals: Totals) }   // "Front: 41 SED since 1 May" style rows, per region, week and cycle
// EndToEndCalibrationTests: drives a SimulatedUser (M1 fixture) through HistoryStore.addPlanned/log/addReport with the S3 reporter; asserts the same bounds as S3 against store.state(now)
// acceptance/S10-logging.sh: `swift test --filter 'IcarusDataTests|IcarusUITests'` on macOS (xcodebuild in CI) and prints the S10 checklist
```

### Internals

```text
TotalsView: two sections (This week, This cycle) × three rows; figures via FigureView (cycle dose figure reads only cited keys → no estimate badge)
EndToEndCalibrationTests: for week in 1...6: for session in 1...5: addPlanned → log with doses from ExposureModel on a flat curve → addReport with simulated answer; assert |state.multiplier − true| ≤ 0.05 after 8 reports etc.
```
