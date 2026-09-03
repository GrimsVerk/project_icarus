#if canImport(SwiftUI)
    import Foundation
    import IcarusCore
    import SwiftUI

    /// One logged session in the History list (R24).
    ///
    /// It shows what was faced — the window, the posture, the sunscreen the user
    /// confirmed — and the dose that was stored for each region. Every number
    /// goes through `FigureView`, which is where the estimate badge lives (R22,
    /// R30); the doses on a record read no assumed constant, so no badge shows.
    ///
    /// The words are the record's own: a window is two clock times, a posture is
    /// the case name of the posture that was chosen. None of it is app copy.
    public struct SessionRow: View {
        private let session: SessionRecord

        public init(session: SessionRecord) {
            self.session = session
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(windowText)
                    .font(.headline)
                Text(HistoryFormat.words(session.posture.rawValue))
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
                        label: HistoryFormat.label("dosePerRegion", dose.region)
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
