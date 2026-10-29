#if canImport(SwiftUI)
    import Combine
    import Foundation
    import IcarusContent
    import IcarusCore
    import IcarusData
    import SwiftUI

    /// One day of the record: every session that was actually logged that day,
    /// the report about that day if one was given, and the day's dose per region.
    ///
    /// The dose is summed from the sessions themselves rather than replayed: the
    /// stored per-region dose is what the session record carries (R22), and a
    /// screen that shows the record must show the record.
    public struct DaySummaryRow: Sendable, Equatable, Identifiable {
        public let id: DayKey
        public let sessions: [SessionRecord]
        public let report: SkinReport?
        public let dosePerRegion: [Region: SED]

        public init(id: DayKey, sessions: [SessionRecord], report: SkinReport?, dosePerRegion: [Region: SED]) {
            self.id = id
            self.sessions = sessions
            self.report = report
            self.dosePerRegion = dosePerRegion
        }
    }

    /// The session log, as the History screen reads it (R24, R25).
    ///
    /// It derives nothing and decides nothing: it reads the history the store
    /// holds, keeps the sessions that were logged, groups them by the day they
    /// belong to, attaches that day's report, and sums the doses already stored
    /// on each record. A discarded session never appears — a session the user
    /// planned and did not do is not part of the record the screen shows (R45) —
    /// and neither does a planned one, which has not happened yet.
    ///
    /// `days` is empty until `reload` has run, so a screen never shows a list
    /// assembled before the store was asked.
    @MainActor
    public final class HistoryModel: ObservableObject {
        /// Newest day first.
        @Published public private(set) var days: [DaySummaryRow] = []
        /// True once `reload` has run, so an empty list can say there is no
        /// session yet (HIST-6) without saying it before the store was asked.
        @Published public private(set) var loaded = false

        let env: AppEnvironment

        public init(env: AppEnvironment) {
            self.env = env
        }

        /// Read the history and rebuild the list.
        ///
        /// `now` is the screen's clock, taken so every screen of one app reads
        /// the same instant. Nothing is filtered by it: the log is the whole
        /// record, and hiding part of it would be a second opinion about what
        /// happened.
        ///
        /// A store that cannot be read leaves an empty list rather than a stale
        /// one, because a half-old log reads as a complete one.
        public func reload(now _: Date) async {
            defer { loaded = true }
            guard let history = try? await env.history.history() else {
                days = []
                return
            }
            var byDay = [DayKey: [SessionRecord]]()
            for session in history.sessions where session.state == .logged {
                byDay[session.day, default: []].append(session)
            }
            let reports = Dictionary(
                history.reports.map { ($0.day, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            days = byDay
                .map { day, sessions in
                    let ordered = sessions.sorted { Self.order(of: $0) > Self.order(of: $1) }
                    return DaySummaryRow(
                        id: day,
                        sessions: ordered,
                        report: reports[day],
                        dosePerRegion: Self.summed(ordered)
                    )
                }
                .sorted { $0.id > $1.id }
        }

        /// The instant a session is ordered by: what was actually faced when it
        /// was logged, and the plan's own start for anything else.
        private static func order(of session: SessionRecord) -> Date {
            session.actualWindow?.start ?? session.plannedWindow.start
        }

        private static func summed(_ sessions: [SessionRecord]) -> [Region: SED] {
            var doses = [Region: SED]()
            for session in sessions {
                for (region, dose) in session.dosePerRegion {
                    doses[region, default: 0] += dose
                }
            }
            return doses
        }
    }

    /// How the History screens turn record data into short strings: a date, a
    /// clock time, a coordinate or a stored number, which are data, and the
    /// record's words, which are lines of `docs/APP_COPY.md` (HIST-7, HIST-9).
    enum HistoryFormat {
        /// The zone the day was decided in — the same instant is two different
        /// days in two different places, so the record's own zone is the one.
        static func zone(_ day: DayKey) -> TimeZone {
            TimeZone(identifier: day.timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
        }

        static func date(_ day: DayKey) -> String {
            formatter(in: zone(day), dateStyle: .medium, timeStyle: .none).string(from: day.start())
        }

        /// A window as the two clock times that bound it, in the day's own zone.
        static func window(_ window: Window, in zone: TimeZone) -> String {
            let clock = formatter(in: zone, dateStyle: .none, timeStyle: .short)
            return "\(clock.string(from: window.start))–\(clock.string(from: window.end))"
        }

        static func time(_ instant: Date, in zone: TimeZone) -> String {
            formatter(in: zone, dateStyle: .medium, timeStyle: .short).string(from: instant)
        }

        /// A coordinate, as the two numbers it is. The app has no name for a
        /// place it was given as a pair of numbers, and inventing one is copy.
        static func place(_ coordinate: Coordinate) -> String {
            String(format: "%.2f, %.2f", coordinate.latitude, coordinate.longitude)
        }

        /// The pair the user confirmed at logging, "SPF 30, normally", or "No
        /// sunscreen" (HIST-9).
        static func sunscreen(_ choice: SunscreenChoice?) -> String {
            guard let choice else { return AppCopy.text(.historyNoSunscreen) }
            return AppCopy.text(.historySunscreen, args: [
                "spf": String(choice.spfLabel),
                "application": CopyWords.application(choice.application),
            ])
        }

        static func decimal(_ value: Double) -> String {
            String(format: "%.1f", value)
        }

        /// The label after a region's stored dose: "SED on your front" (HIST-7).
        static func dose(_ region: Region) -> String {
            AppCopy.text(.historyDayDose, args: ["region": CopyWords.region(region)])
        }

        private static func formatter(
            in zone: TimeZone,
            dateStyle: DateFormatter.Style,
            timeStyle: DateFormatter.Style
        ) -> DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = zone
            formatter.dateStyle = dateStyle
            formatter.timeStyle = timeStyle
            return formatter
        }
    }
#endif
