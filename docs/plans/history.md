---
slug: history
status: draft
created: 2026-09-02
design: M6 — History
covers: [R24, R25]
format: pseudocode
---

# History — Plan

## Summary

The record, on screen: a session log, the weekly and cycle totals already
computed in M5, a dose-trajectory chart labelled as dose and never as colour,
and the export and import actions moved into a History screen reachable from
the Calculator toolbar. No banner here.

Non-goals:
- We do NOT claim or plot pigment; the chart's axis is SED and its title says so.
- We do NOT add a fourth tab; History is reached from the Calculator toolbar.

Owner costs:
- None.

Rulings: D-2026-09-02 revision 2 (History carries no banner; chart is a record of dose)

## The slices

## Slice 1 — The session log

- **Delivers:** A History screen lists logged sessions newest first with date, window, posture, per-region dose, sunscreen confirmed and the day's report outcome; tapping one shows the stored figures and the place the forecast was for; discarded sessions are hidden.
- **Files:** `Sources/IcarusUI/History/HistoryView.swift`, `Sources/IcarusUI/History/SessionRow.swift`, `Sources/IcarusUI/History/SessionDetailView.swift`, `Sources/IcarusUI/History/HistoryModel.swift`, `Tests/IcarusUITests/HistoryModelTests.swift`
- **Estimate:** ~300 lines

### Signatures

```text
@MainActor public final class HistoryModel: ObservableObject {
    public init(env: AppEnvironment)
    @Published public private(set) var days: [DaySummaryRow]     // newest first; logged sessions only, grouped by day with the day's report
    public func reload(now: Date) async
}
public struct DaySummaryRow: Sendable, Equatable, Identifiable { public let id: DayKey; public let sessions: [SessionRecord]; public let report: SkinReport?; public let dosePerRegion: [Region: SED] }
public struct HistoryView: View { public init(env: AppEnvironment) }      // no banner slot (S15)
// Promises (S15, UI tests): discarded sessions absent; rows sorted newest first; HistoryView contains no banner slot
```

### Internals

```text
reload: h = history(); group logged sessions by day; attach the day's report; sum doses
SessionDetailView: shows factorsShown/targetsShown as "what you were shown", forecastPlace, curveUsed peak UVI, sunscreen; all via FigureView
```

## Slice 2 — The dose-trajectory chart

- **Delivers:** A Swift Charts line per region of cycle-to-date cumulative dose over the current cycle, with the escalation notice line marked, titled as a record of dose in SED and carrying the copy that it is not a measurement of colour; VoiceOver reads the series.
- **Files:** `Sources/IcarusUI/History/TrajectoryChart.swift`, `Sources/IcarusUI/History/TrajectoryModel.swift`, `Tests/IcarusUITests/TrajectoryModelTests.swift`
- **Estimate:** ~240 lines

### Signatures

```text
public struct TrajectoryPoint: Sendable, Equatable, Identifiable { public let id: Date; public let region: Region; public let cumulativeSED: SED }
@MainActor public final class TrajectoryModel: ObservableObject { public init(env: AppEnvironment); @Published public private(set) var points: [TrajectoryPoint]; public func reload(now: Date) async }
public struct TrajectoryChart: View { public init(points: [TrajectoryPoint]) }   // title from AppCopy .trajectoryTitle ("dose, not colour")
// Promises: points are monotone non-decreasing per region within a cycle and reset at a cycle start; the title copy key is .trajectoryTitle
```

### Internals

```text
reload: walk logged sessions in order; per region running sum since cycleStart (from state.regions); emit a point per session day
TrajectoryChart: Chart { ForEach(points) LineMark(x: date, y: cumulativeSED) .foregroundStyle(by: region) } .chartYAxisLabel("SED") .accessibilityLabel(series summary)
```

## Slice 3 — Export and import from History

- **Delivers:** History carries the export (share sheet) and import (file picker) actions from Settings as well; import shows the summary and re-replays; a failed import leaves the history untouched.
- **Files:** `Sources/IcarusUI/History/ExportImportView.swift`, `Tests/IcarusUITests/ExportImportTests.swift`
- **Estimate:** ~160 lines

### Signatures

```text
public struct ExportImportView: View { public init(env: AppEnvironment) }
// Promises (S10): export produces an ExportFile the M2 import accepts; a corrupt file → error shown, history unchanged
```

### Internals

```text
ShareLink with a transient file URL from ExportService.export; fileImporter(.json) → ExportService.import → alert with ImportSummary; errors → alert, no write
```
