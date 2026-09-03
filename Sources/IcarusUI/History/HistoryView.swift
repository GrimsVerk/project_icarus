#if canImport(SwiftUI)
    import Foundation
    import IcarusCore
    import SwiftUI

    /// The History screen: the record, newest day first (R24, R25).
    ///
    /// One section per day. The section is headed by the day itself, carries one
    /// row per logged session, and closes with that day's totals per region and
    /// the answer the user gave about their skin, when they gave one. A
    /// discarded session is nowhere on it — the model drops those — and neither
    /// is a planned one.
    ///
    /// It carries no ad banner: R39 keeps the banner off every screen that shows
    /// a figure the user could act on, and this screen is nothing but figures.
    /// `ScreenTable` already records that pair, and `acceptance/S15.sh` checks
    /// the row against this declaration.
    ///
    /// No heading here is copy. No approved key names a column, and a view may
    /// not invent one (R42), so what the screen shows is the data: dates, clock
    /// times, stored numbers, and the record's own case names as words.
    public struct HistoryView: View, ScreenManifest {
        public nonisolated static let hasBannerSlot = false
        public nonisolated static let showsFigures = true

        @StateObject private var model: HistoryModel
        @StateObject private var trajectory: TrajectoryModel
        private let env: AppEnvironment

        /// On the main actor because the model it builds is: the screen owns one
        /// `HistoryModel` for as long as it is open, and the environment it
        /// reads is main-actor state.
        @MainActor
        public init(env: AppEnvironment) {
            _model = StateObject(wrappedValue: HistoryModel(env: env))
            _trajectory = StateObject(wrappedValue: TrajectoryModel(env: env))
            self.env = env
        }

        public var body: some View {
            NavigationStack {
                List {
                    // The dose-trajectory chart sits above the log (R24): a record
                    // of dose per cycle, never a claim about colour.
                    Section {
                        TrajectoryChart(points: trajectory.points)
                    }
                    ForEach(model.days) { day in
                        Section {
                            sessions(of: day)
                            totals(of: day)
                        } header: {
                            Text(HistoryFormat.date(day.id))
                        } footer: {
                            outcome(of: day)
                        }
                    }
                }
                // The record's own two actions: take it out, or put one back
                // (R25). They sit here rather than only in Settings, because
                // this is the screen the record is on.
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ExportImportView(env: env)
                    }
                }
            }
            .task {
                await model.reload(now: env.clock())
                await trajectory.reload(now: env.clock())
            }
        }

        // MARK: - One day

        private func sessions(of day: DaySummaryRow) -> some View {
            ForEach(day.sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    SessionRow(session: session)
                }
            }
        }

        /// The day's dose per region, summed over its sessions.
        private func totals(of day: DaySummaryRow) -> some View {
            ForEach(RegionValue.list(day.dosePerRegion)) { total in
                FigureView(
                    figure: Figure(
                        key: .regionDose,
                        region: total.region,
                        value: total.value,
                        unit: .sed,
                        reads: []
                    ),
                    label: HistoryFormat.label("dosePerRegion", total.region)
                )
            }
        }

        /// What the user answered about that day's skin, as the answer's own
        /// name. A day with no report says nothing rather than saying "none":
        /// an unanswered question is not an answer.
        @ViewBuilder
        private func outcome(of day: DaySummaryRow) -> some View {
            if let report = day.report {
                Text(HistoryFormat.words(report.answer.rawValue))
            }
        }
    }
#endif
