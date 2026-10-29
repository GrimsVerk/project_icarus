#if canImport(SwiftUI)
    import Foundation
    import IcarusCore
    import SwiftUI

    /// One logged session, opened from the History list (R24, R25).
    ///
    /// It shows the stored record and nothing recomputed: the factors and the
    /// targets the user was shown at the time, the dose that was stored for each
    /// region, and the forecast the plan was made from — the place it was for,
    /// when it was fetched, and the strongest hour on the curve that was used.
    /// A figure recomputed here would be a different number from the one the
    /// user acted on, so nothing here is computed at all (R22).
    ///
    /// Every number goes through `FigureView`; every word is the record's own
    /// vocabulary, split into words. Three field names carry the meaning of the
    /// three figure groups, because no copy key names a column (R42, S11).
    public struct SessionDetailView: View {
        private let session: SessionRecord

        public init(session: SessionRecord) {
            self.session = session
        }

        public var body: some View {
            List {
                Section {
                    whatHappened
                }
                Section {
                    whatYouWereShown
                }
                Section {
                    theForecast
                }
            }
        }

        // MARK: - What happened

        @ViewBuilder
        private var whatHappened: some View {
            row("day", HistoryFormat.date(session.day))
            row("window", windowText)
            row("posture", HistoryFormat.words(session.posture.rawValue))
            row("coverHeadAndShoulders", String(session.coverHeadAndShoulders))
            row("intent", HistoryFormat.words(session.intent.rawValue))
            row("sunscreen", HistoryFormat.sunscreen(session.sunscreen))
            row("ceilingAtPlan", HistoryFormat.words(session.ceilingAtPlan.rawValue))
        }

        // MARK: - What you were shown

        /// The display record R22 keeps: the adaptation factor and the target
        /// each region was shown under, and the dose that was stored against it.
        ///
        /// The factor is a multiple and the two doses are in SED, so each takes
        /// the figure key of its own unit; the label is the record's field name,
        /// which is what tells the three groups apart.
        @ViewBuilder
        private var whatYouWereShown: some View {
            ForEach(RegionValue.list(session.factorsShown)) { factor in
                FigureView(
                    figure: Figure(
                        key: .uvaMultiple,
                        region: factor.region,
                        value: factor.value,
                        unit: .multiple,
                        reads: []
                    ),
                    label: HistoryFormat.label("factorsShown", factor.region)
                )
            }
            ForEach(RegionValue.list(session.targetsShown)) { target in
                FigureView(
                    figure: Figure(
                        key: .rangeUpper,
                        region: target.region,
                        value: target.value,
                        unit: .sed,
                        reads: []
                    ),
                    label: HistoryFormat.label("targetsShown", target.region)
                )
            }
            ForEach(RegionValue.list(session.dosePerRegion)) { dose in
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

        // MARK: - The forecast it was made from

        @ViewBuilder
        private var theForecast: some View {
            row("forecastPlace", HistoryFormat.place(session.forecastPlace))
            row("forecastFetchedAt", HistoryFormat.time(session.forecastFetchedAt, in: zone))
            row("peakUVI", HistoryFormat.decimal(peakUVI))
            row("timeZoneID", session.curveUsed.timeZoneID)
        }

        /// The strongest hour on the curve the plan was made from. It is a stored
        /// sample, read straight off the record.
        private var peakUVI: UVI {
            session.curveUsed.hourly.map(\.uvi).max() ?? 0
        }

        // MARK: - Inside

        private var zone: TimeZone {
            HistoryFormat.zone(session.day)
        }

        private var windowText: String {
            HistoryFormat.window(session.actualWindow ?? session.plannedWindow, in: zone)
        }

        /// One field of the record: its name, and its value as data.
        private func row(_ field: String, _ value: String) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Text(HistoryFormat.words(field))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.body)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
