#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// Weekly and cycle-to-date dose per region (R24).
    ///
    /// Two sections of three rows: the last seven days of logged sessions, and
    /// everything since each region's tan cycle opened. The store computes both
    /// from the logged record alone, so this view only renders what it is given
    /// and never sums anything itself.
    ///
    /// Every number goes through `FigureView`, which is the one place a figure
    /// is drawn. A total rests on no assumed constant — it is a sum of doses
    /// already recorded — so its `reads` are empty and the estimate badge never
    /// appears on one.
    ///
    /// The two spans are headed SET-12 and SET-13, and each row reads like a
    /// History total, "2.3 SED on your front" (HIST-7).
    public struct TotalsView: View {
        private let totals: Totals

        public init(totals: Totals) {
            self.totals = totals
        }

        public var body: some View {
            Section {
                rows(totals.week)
            } header: {
                Label(AppCopy.text(.settingsWeekHeading), systemImage: "calendar.day.timeline.left")
            }
            Section {
                rows(totals.cycle)
            } header: {
                Label(AppCopy.text(.settingsCycleHeading), systemImage: "calendar")
            }
        }

        // MARK: - Inside

        /// One row per region, in the engine's own order. A region with nothing
        /// logged against it still shows, as zero: an absent row would read as
        /// "no such region" rather than "no dose yet".
        private func rows(_ doses: [Region: SED]) -> some View {
            ForEach(Region.allCases, id: \.self) { region in
                FigureView(
                    figure: figure(region, dose: doses[region] ?? 0),
                    label: HistoryFormat.dose(region)
                )
            }
        }

        /// The total as the figure it is: a dose in SED, resting on no
        /// assumption.
        private func figure(_ region: Region, dose: SED) -> Figure {
            Figure(key: .cycleDose, region: region, exposure: nil, value: dose, unit: .sed, reads: [])
        }
    }
#endif
