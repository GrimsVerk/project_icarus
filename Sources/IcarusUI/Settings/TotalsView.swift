#if canImport(SwiftUI)
    import Foundation
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
    /// No approved line names either span or any region (R42), so the sections
    /// are headed by a symbol and each row is labelled by the region's own name
    /// as words. That name is data, split mechanically out of the raw value the
    /// same way the prompt options are: it is not a sentence this file made up.
    public struct TotalsView: View {
        private let totals: Totals

        public init(totals: Totals) {
            self.totals = totals
        }

        public var body: some View {
            Section {
                rows(totals.week)
            } header: {
                Image(systemName: "calendar.day.timeline.left")
            }
            Section {
                rows(totals.cycle)
            } header: {
                Image(systemName: "calendar")
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
                    label: PromptWords.words(region.rawValue)
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
