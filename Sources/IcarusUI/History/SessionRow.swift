#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore
    import SwiftUI

    /// One logged session in the History list (R24).
    ///
    /// It shows what was faced — the window, the posture, the sunscreen the user
    /// confirmed — and the dose that was stored for each region. Every number
    /// goes through `FigureView`, which is where the estimate badge lives (R22,
    /// R30); the doses on a record read no assumed constant, so no badge shows.
    ///
    /// A window is two clock times; the posture and the sunscreen are in the
    /// words the Plan screen and the skin check use (CALC-5, CALC-6, HIST-9).
    public struct SessionRow: View {
        private let session: SessionRecord

        public init(session: SessionRecord) {
            self.session = session
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(windowText)
                    .font(.headline)
                Text(CopyWords.posture(session.posture))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(HistoryFormat.sunscreen(session.sunscreen))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(doses, id: \.region) { dose in
                    FigureView(
                        figure: Figure(
                            key: .regionDose,
                            region: dose.region,
                            value: dose.value,
                            unit: .sed,
                            reads: []
                        ),
                        label: HistoryFormat.dose(dose.region)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// What was actually faced, and the plan's window only while nothing was
        /// faced at all — a logged session always has the first.
        private var windowText: String {
            let zone = HistoryFormat.zone(session.day)
            return HistoryFormat.window(session.actualWindow ?? session.plannedWindow, in: zone)
        }

        private var doses: [RegionValue] {
            RegionValue.list(session.dosePerRegion)
        }
    }

    /// One region's number, in the order the engine lists its regions. A
    /// dictionary has no order of its own and a list on screen must have one.
    struct RegionValue: Identifiable, Equatable {
        let region: Region
        let value: Double

        var id: Region {
            region
        }

        static func list(_ values: [Region: Double]) -> [RegionValue] {
            Region.allCases.compactMap { region in
                values[region].map { RegionValue(region: region, value: $0) }
            }
        }
    }
#endif
