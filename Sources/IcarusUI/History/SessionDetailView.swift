#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
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
    /// Every number goes through `FigureView`. The words are HIST-10 to HIST-14
    /// in `docs/APP_COPY.md`.
    public struct SessionDetailView: View {
        private let session: SessionRecord

        public init(session: SessionRecord) {
            self.session = session
        }

        public var body: some View {
            List {
                Section {
                    whatHappened
                } header: {
                    Text(AppCopy.text(.detailWhatYouDid))
                }
                Section {
                    whatYouWereShown
                } header: {
                    Text(AppCopy.text(.detailWhatYouWereShown))
                }
                Section {
                    theForecast
                } header: {
                    Text(AppCopy.text(.detailTheForecast))
                }
            }
        }

        // MARK: - What happened

        @ViewBuilder
        private var whatHappened: some View {
            row(.detailDay, HistoryFormat.date(session.day))
            row(.detailTime, windowText)
            row(.detailPosition, CopyWords.posture(session.posture))
            row(.detailCovered, CopyWords.yesNo(session.coverHeadAndShoulders))
            row(.detailPlan, CopyWords.intent(session.intent))
            row(.detailSunscreen, HistoryFormat.sunscreen(session.sunscreen))
            row(.detailSetting, CopyWords.recordedCeiling(session.ceilingAtPlan))
        }

        // MARK: - What you were shown

        /// The display record R22 keeps: the adaptation factor and the target
        /// each region was shown under, and the dose that was stored against it.
        ///
        /// The factor is a multiple and the two doses are in SED, so each takes
        /// the figure key of its own unit; the label (HIST-13) is what tells the
        /// three groups apart, so it leads the row. The adaptation factor reads
        /// as "Tan protection, front ×1.4".
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
                    label: figureLabel(.detailTanProtection, factor.region),
                    labelFirst: true
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
                    label: figureLabel(.detailTarget, target.region),
                    labelFirst: true
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
                    label: figureLabel(.detailReceived, dose.region),
                    labelFirst: true
                )
            }
        }

        private func figureLabel(_ key: CopyKey, _ region: Region) -> String {
            AppCopy.text(key, args: ["region": CopyWords.region(region)])
        }

        // MARK: - The forecast it was made from

        @ViewBuilder
        private var theForecast: some View {
            row(.detailForecastFor, HistoryFormat.place(session.forecastPlace))
            row(.detailForecastFetched, HistoryFormat.time(session.forecastFetchedAt, in: zone))
            row(.detailPeakUVI, HistoryFormat.decimal(peakUVI))
            row(.detailTimeZone, session.curveUsed.timeZoneID)
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

        /// One field of the record: its name, and its value.
        private func row(_ field: CopyKey, _ value: String) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Text(AppCopy.text(field))
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
