#if canImport(SwiftUI)
    import Combine
    import Foundation
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

    /// How the History screens turn record data into short strings.
    ///
    /// Every one of these is data — a date, a clock time, a coordinate, a stored
    /// number, or the name of a case in the record's own vocabulary — so none of
    /// it is app copy and none of it goes through `AppCopy` (R42, S11). A case
    /// name is split at its capitals so "headAndShoulders" reads as words rather
    /// than as an identifier; the words are the data's, not the app's.
    enum HistoryFormat {
        /// "headAndShoulders" → "Head and shoulders". The prompts already split
        /// a case name this way and there is only one right answer, so this is
        /// their splitter rather than a second one.
        static func words(_ raw: String) -> String {
            PromptWords.words(raw)
        }

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

        /// The pair the user confirmed at logging, or the case name for none.
        static func sunscreen(_ choice: SunscreenChoice?) -> String {
            guard let choice else { return words("none") }
            return "SPF \(choice.spfLabel) · \(words(choice.application.rawValue))"
        }

        static func decimal(_ value: Double) -> String {
            String(format: "%.1f", value)
        }

        /// A label for one region's figure: the record's field name and the
        /// region, both as their own words.
        static func label(_ field: String, _ region: Region) -> String {
            "\(words(field)) · \(words(region.rawValue))"
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
