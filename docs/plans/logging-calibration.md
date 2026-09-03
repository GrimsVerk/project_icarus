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
report; both by notification and in-app, routed by the day's zone-carrying
id; the answers flowing through the store into replay, with the confirmation
copy taken from the effect the replay applied; the sensitivity sentence, the
unreported-days count, and the weekly and cycle totals. Revision 3 lands the
second tactical pass.

Non-goals:
- We do NOT compute the update here; `CalibrationEngine` and `Replay` (M1) do.
- We do NOT draw the trajectory chart (M6).
- We do NOT show MED or SED anywhere in the prompt flow.
- We do NOT add copy keys: every key this plan uses is in Core's list already.

Owner costs:
- None.

Rulings: D-2026-09-03-F5, F7 (docs/DECISIONS.md); design revision 3 for log = report and prompt scheduling

## The slices

## Slice 1 — The skin-check flow: did you do it, did you wear it, how does it look, when, where, anything unusual

- **Delivers:** Tapping the day-after notification (its id resolves to the day through `DayKey(id:)`), or the in-app due card, opens the skin-check flow for that day: one "Did you do this session?" per still-planned session (yes asks "Did you wear <the prescribed pair>?" with as-prescribed / another product / none, then logs it from editable intervals defaulting to the planned sides with the attenuated dose; no discards it), then Q1, Q2 if any redness, the region picker defaulting to "all exposed", and the confounders list; if no session that day is logged the flow says so and records nothing; submitting writes one `SkinReport` and shows the confirmation copy for the effect the replay applied.
- **Files:** `Sources/IcarusUI/Prompts/SkinCheckFlow.swift`, `Sources/IcarusUI/Prompts/DidYouDoThisView.swift`, `Sources/IcarusUI/Prompts/IntervalEditor.swift`, `Sources/IcarusUI/Prompts/SkinCheckModel.swift`, `Sources/IcarusUI/Prompts/DuePromptsCard.swift`, `Sources/IcarusUI/Prompts/NotificationRouting.swift`, `Tests/IcarusUITests/SkinCheckModelTests.swift`
- **Estimate:** ~520 lines

### Signatures

```text
@MainActor public final class SkinCheckModel: ObservableObject {
    public init(env: AppEnvironment, day: DayKey, channel: Channel)
    @Published public private(set) var planned: [SessionRecord]
    @Published public var answer: SkinAnswer?; @Published public var timing: RednessTiming?; @Published public var region: ReportRegion = .allExposed
    @Published public var confounders: Set<Confounder>
    public func didDo(_ id: UUID, actual: [ExposureInterval], wore: SunscreenConfirmation) async throws
        // .asPrescribed resolves to the record's prescribedSunscreen (throws .noPrescription when nil); doses = attenuated(Σ dose(i.exposure, cover, over i.window, curveUsed), choice, cover)
    public func didNotDo(_ id: UUID) async throws
    public var hasLoggedSession: Bool; public var canSubmit: Bool
    public func submit(now: Date) async throws -> CalibrationEffect
}
public enum SkinCheckError: Error, Equatable { case noPrescription(UUID) }
public struct SkinCheckFlow: View, ScreenManifest { public init(model: SkinCheckModel) }    // (false, false)
public struct DuePromptsCard: View { public init(env: AppEnvironment) }
public enum NotificationRouting { public static func route(_ id: String) -> DuePrompt? }       // PromptScheduler.day(fromNotificationID:); nil → the caller opens DuePromptsCard
// Promises (S10): submit twice on one day → .alreadyReported; canSubmit false with no logged session; timing required iff redness;
//  didDo(.asPrescribed) on a record with prescribedSunscreen SPF 30 normal logs doses == attenuated(bare over the intervals, SPF 30 normal); on a record with nil → .noPrescription;
//  route("skin-2026-09-03@Europe/Oslo") == .skinCheck(that DayKey); route("skin-garbage") == nil; submit's effect == the store's replay effect; confirmation key follows the effect
```

### Internals

```text
pages: DidYouDoThis (per planned: yes → DidYouWearIt → IntervalEditor (defaults plannedIntervals)) → (no logged session → NoSessionToReport, end) → Q1 → (Q2 if redness) → Region → Confounders → Confirmation
didDo: rec = planned[id]; choice per wore; curve = try rec.curveUsed.curve(); doses = attenuated(Σ ExposureModel.dose(i.exposure, rec.cover, over i.window, curve), choice, rec.cover); history.log(id, actual, sunscreen: choice, doses, factorsShown: rec.factorsShown, targetsShown: rec.targetsShown)
submit: report = SkinReport(day, now, …); effect = try await history.addReport(report); await prompts.reportAdded(on: day, at: now); return effect
```

## Slice 2 — Lasting colour, in-app fallbacks, housekeeping, and the unreported count

- **Delivers:** Four days after a report the lasting-colour prompt asks yes / a little / no and attaches to that day's report with its timestamp; with notifications denied or a prompt ignored, the Calculator entry shows a due card inside the in-app windows and Settings counts unreported logged days; answering removes the card; planned sessions whose window has closed are discarded on foreground.
- **Files:** `Sources/IcarusUI/Prompts/LastingColourView.swift`, `Sources/IcarusUI/Prompts/LastingColourModel.swift`, `Tests/IcarusUITests/LastingColourModelTests.swift`, `Tests/IcarusDataTests/PromptSchedulerInAppTests.swift`
- **Estimate:** ~230 lines

### Signatures

```text
@MainActor public final class LastingColourModel: ObservableObject { public init(env: AppEnvironment, day: DayKey, channel: Channel); public func submit(_ lc: LastingColour, now: Date) async throws }
public struct LastingColourFlow: View, ScreenManifest { public init(model: LastingColourModel) }   // (false, false)
// Promises (S10): as revision 2
```

### Internals

```text
DuePromptsCard reads env.prompts.dueInApp on appear and on foreground; AppEnvironment.didBecomeActive (M3) discards stale planned sessions; this slice adds the test
```

## Slice 3 — Totals in the store and the sensitivity sentence in Settings, end to end

- **Delivers:** Weekly and cycle-to-date totals per region are computed from the history and shown in Settings; the sensitivity sentence renders from the replayed multiplier and report count; the S3 simulation is re-run through the real store so the whole loop is exercised end to end, and S18's use case 7 fixture passes from its own fixture file.
- **Files:** `Sources/IcarusUI/Settings/TotalsView.swift`, `Tests/IcarusDataTests/EndToEndCalibrationTests.swift`, `Tests/IcarusCoreTests/Fixtures/UseCaseLogging.swift`, `acceptance/S10-logging.sh`
- **Estimate:** ~260 lines

### Signatures

```text
public struct TotalsView: View { public init(totals: Totals) }
// EndToEndCalibrationTests: a SimulatedUser through HistoryStore.upsertPlanned/log/addReport with the S3 reporter; the S3 bounds hold against store.state(now); TZ=UTC and TZ=Europe/Oslo
// UseCaseLogging.swift: use case 7's fixture, registered with the S18 runner without touching UseCases.swift
// acceptance/S10-logging.sh: `swift test --filter 'IcarusDataTests|IcarusUITests'` and prints the S10 checklist
```

### Internals

```text
TotalsView: two sections × three rows via FigureView
EndToEndCalibrationTests: weeks × sessions: upsertPlanned → log with attenuated doses → addReport with the simulated answer; assert the S3 bounds
```
