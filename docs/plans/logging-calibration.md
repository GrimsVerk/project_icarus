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

The loop that makes the app learn: the one-per-day skin check that opens with
"did you do this session?" and "did you wear it?" for planned sessions, then
Q1, Q2, region and confounders; the four-day lasting-colour prompt after a
report; both by notification and in-app; the answers flowing through the store
into replay, with the confirmation copy taken from the effect the replay
actually applied; the sensitivity sentence, the unreported-days count, and
the weekly and cycle totals. Revision 2 lands the tactical review.

Non-goals:
- We do NOT compute the update here; `CalibrationEngine` and `Replay` (M1) do.
- We do NOT draw the trajectory chart (M6).
- We do NOT show MED or SED anywhere in the prompt flow.

Owner costs:
- None beyond the copy keys this plan adds to `docs/APP_COPY.md` (S17).

Rulings: D-2026-09-03-F5, F7 (docs/DECISIONS.md); design revision 3 for log = report and prompt scheduling

## The slices

## Slice 1 — The skin-check flow: did you do it, did you wear it, how does it look, when, where, anything unusual

- **Delivers:** Tapping the day-after notification, or the in-app due card, opens the skin-check flow for that day: one "Did you do this session?" per still-planned session (yes asks "Did you wear <prescribed>?" then logs it with editable times and the attenuated dose; no discards it), then Q1 with five plain answers, Q2 if any redness, the region picker defaulting to "all exposed", and the confounders list; if no session that day is logged the flow says so and records nothing; submitting writes one `SkinReport` for the day and shows the confirmation copy for the effect the replay applied.
- **Files:** `Sources/IcarusUI/Prompts/SkinCheckFlow.swift`, `Sources/IcarusUI/Prompts/DidYouDoThisView.swift`, `Sources/IcarusUI/Prompts/SkinCheckModel.swift`, `Sources/IcarusUI/Prompts/DuePromptsCard.swift`, `App/NotificationRouting.swift`, `Tests/IcarusUITests/SkinCheckModelTests.swift`
- **Estimate:** ~500 lines

### Signatures

```text
@MainActor public final class SkinCheckModel: ObservableObject {
    public init(env: AppEnvironment, day: DayKey, channel: Channel)
    @Published public private(set) var planned: [SessionRecord]
    @Published public var answer: SkinAnswer?; @Published public var timing: RednessTiming?; @Published public var region: ReportRegion = .allExposed
    @Published public var confounders: Set<Confounder>
    public func didDo(_ id: UUID, actual: Window, wore: SunscreenConfirmation) async throws   // doses = attenuated(dose over actual sub-intervals from the stored curve, wore, cover)
    public func didNotDo(_ id: UUID) async throws
    public var hasLoggedSession: Bool                                      // false → the flow shows .noSessionToReport and cannot submit
    public var canSubmit: Bool                                             // hasLoggedSession && answer set && (timing set iff answer != .normal)
    public func submit(now: Date) async throws -> CalibrationEffect        // history.addReport → the replay's effect; then prompts.reportAdded
}
public struct SkinCheckFlow: View, ScreenManifest { public init(model: SkinCheckModel) }    // (false, false)
public struct DuePromptsCard: View { public init(env: AppEnvironment) }                       // on the Calculator entry; no figure
// App/NotificationRouting: "skin-<day>" → SkinCheckFlow(day, .notification); "colour-<day>" → LastingColourFlow
// Promises (S10): submit twice on one day → .alreadyReported; canSubmit false with no logged session; timing required iff redness;
//  didDo with wore .asPrescribed halves… (exact: doses == attenuated(bare over actual, prescribed pair)); submit's effect == the store's replay effect for that report;
//  confirmation copy key follows the effect (.reclassifiedAsNormal → .immediateDarkeningExplained; .clampHit → .revisitSkinType; .blisterCorrection → .pauseSuggested; .noDoseThatDay → .noSessionToReport)
```

### Internals

```text
pages: DidYouDoThis (per planned: yes → DidYouWearIt (asPrescribed / alternative picker / none) → editable times) → (no logged session → NoSessionToReport, end) → Q1 → (Q2 if redness) → Region → Confounders → Confirmation
didDo: rec = planned[id]; curve = try rec.curveUsed.curve(); sides = ExposureModel.dose(exposure, cover, over each actual sub-interval per rec.posture/firstSide); doses = attenuated(Σ, choice, cover); history.log(id, actual, sunscreen: choice, doses, factorsShown: rec.factorsShown, targetsShown: rec.targetsShown)
submit: report = SkinReport(day, reportedAt: now, answer, timing, region, confounders, channel); effect = try await history.addReport(report); await prompts.reportAdded(on: day, at: now); return effect
```

## Slice 2 — Lasting colour, in-app fallbacks, housekeeping, and the unreported count

- **Delivers:** Four days after a report the lasting-colour prompt asks yes / a little / no and attaches to that day's report with its timestamp; with notifications denied or a prompt ignored, the Calculator entry shows a due card inside the in-app windows and Settings counts unreported logged days; answering removes the card; planned sessions whose window has closed are discarded on foreground.
- **Files:** `Sources/IcarusUI/Prompts/LastingColourView.swift`, `Sources/IcarusUI/Prompts/LastingColourModel.swift`, `Tests/IcarusUITests/LastingColourModelTests.swift`, `Tests/IcarusDataTests/PromptSchedulerInAppTests.swift`
- **Estimate:** ~230 lines

### Signatures

```text
@MainActor public final class LastingColourModel: ObservableObject {
    public init(env: AppEnvironment, day: DayKey, channel: Channel)
    public func submit(_ lc: LastingColour, now: Date) async throws   // history.setLastingColour(day, lc, at: now); throws .noReport
}
public struct LastingColourFlow: View, ScreenManifest { public init(model: LastingColourModel) }   // (false, false)
// Promises (S10): with notifications denied, a session day is due in-app from 12 h to 72 h; a reported day is due for colour from 3 to 10 days; submit on a report-less day surfaces .noReport;
//  after didBecomeActive, planned sessions older than 72 h after their end are discarded and unreportedDays counts logged days only
```

### Internals

```text
DuePromptsCard reads env.prompts.dueInApp(history, now) on appear and on foreground; each row opens the matching flow with channel .inApp
AppEnvironment.didBecomeActive (M3) already calls history.discardPlanned(before: now); this slice adds the test
```

## Slice 3 — Totals in the store and the sensitivity sentence in Settings, end to end

- **Delivers:** Weekly and cycle-to-date totals per region are computed from the history and shown in Settings; the sensitivity sentence renders from the replayed multiplier and report count; the S3 simulation is re-run through the real store (fake provider, memory persistence) so the whole loop is exercised end to end, and S18's use case 7 fixture passes.
- **Files:** `Sources/IcarusUI/Settings/TotalsView.swift`, `Tests/IcarusDataTests/EndToEndCalibrationTests.swift`, `Tests/IcarusCoreTests/Fixtures/UseCases.swift`, `acceptance/S10-logging.sh`
- **Estimate:** ~260 lines

### Signatures

```text
public struct TotalsView: View { public init(totals: Totals) }   // "Front: 41 SED since 1 May" rows per region, week and cycle
// EndToEndCalibrationTests: a SimulatedUser through HistoryStore.upsertPlanned/log/addReport with the S3 reporter; the S3 bounds hold against store.state(now); runs under TZ=UTC and TZ=Europe/Oslo
// acceptance/S10-logging.sh: `swift test --filter 'IcarusDataTests|IcarusUITests'` (xcodebuild in CI) and prints the S10 checklist
```

### Internals

```text
TotalsView: two sections × three rows via FigureView (cycle dose figure reads only cited keys → no estimate badge)
EndToEndCalibrationTests: for week in 1...6: for session in 1...5: upsertPlanned → log with attenuated doses on a flat curve → addReport with the simulated answer; assert |state.multiplier − true| ≤ 0.05 after 8 reports etc.
```
