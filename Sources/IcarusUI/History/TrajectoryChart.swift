#if canImport(SwiftUI)
    import Charts
    import Foundation
    import IcarusContent
    import IcarusCore
    import SwiftUI

    /// The dose trajectory of the current tan cycle: one line per region of
    /// cumulative SED, with each region's escalation-notice line marked (R24).
    ///
    /// The title is the owner's own wording and it is the point of the screen:
    /// this is a record of dose, not a measurement of colour. Nothing here
    /// plots pigment, and the y axis is SED — a unit, which is data rather than
    /// copy.
    ///
    /// The chart is one accessibility element that reads the title and then the
    /// last number of each region, because a VoiceOver user asking what the
    /// chart says is asking where each region now stands.
    public struct TrajectoryChart: View {
        private let points: [TrajectoryPoint]
        private let notices: [Region: SED]

        public init(points: [TrajectoryPoint]) {
            self.init(points: points, notices: [:])
        }

        /// The same chart with the escalation-notice line the model computed.
        public init(points: [TrajectoryPoint], notices: [Region: SED]) {
            self.points = points
            self.notices = notices
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppCopy.text(.trajectoryTitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                chart
                    .frame(height: 200)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: summary))
            }
        }

        // MARK: - Inside

        private var chart: some View {
            Chart {
                ForEach(points, id: \.self) { point in
                    LineMark(
                        x: .value("date", point.id),
                        y: .value("sed", point.cumulativeSED)
                    )
                    .foregroundStyle(by: .value("region", CopyWords.region(point.region)))
                    // A line needs two sessions; the point shows the first one
                    // on its own (screen review F14).
                    PointMark(
                        x: .value("date", point.id),
                        y: .value("sed", point.cumulativeSED)
                    )
                    .foregroundStyle(by: .value("region", CopyWords.region(point.region)))
                }
                ForEach(noticeLines, id: \.region) { line in
                    RuleMark(y: .value("notice", line.value))
                        .foregroundStyle(by: .value("region", CopyWords.region(line.region)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartYAxisLabel { Text(verbatim: unit) }
            .chartLegend(position: .bottom)
        }

        /// The marked lines, in a fixed region order so the chart does not
        /// reshuffle itself between rebuilds.
        private var noticeLines: [NoticeLine] {
            Region.allCases.compactMap { region in
                notices[region].map { NoticeLine(region: region, value: $0) }
            }
        }

        /// The title, then where each region stands: the region's name (FILL-1)
        /// and its dose.
        private var summary: String {
            let parts = Region.allCases.compactMap { region -> String? in
                guard let last = points.last(where: { $0.region == region }) else { return nil }
                return "\(CopyWords.region(region)) \(number(last.cumulativeSED)) \(unit)"
            }
            return ([AppCopy.text(.trajectoryTitle)] + parts).joined(separator: ". ")
        }

        private func number(_ dose: SED) -> String {
            String(format: "%.1f", dose)
        }

        /// The unit the axis is in. Not copy: it is the name of the measure.
        private let unit = "SED"

        private struct NoticeLine: Hashable {
            let region: Region
            let value: SED
        }
    }
#endif
