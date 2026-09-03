import Foundation

/// Everything the user has done. Replay folds this into derived state (R44):
/// the history is the record, and nothing derived from it is authoritative.
///
/// The record types themselves — `SessionRecord` and `SkinReport` — live in
/// `Models/Reports.swift` with the rest of the shared vocabulary.
public struct History: Codable, Sendable, Equatable {
    public var sessions: [SessionRecord]
    public var reports: [SkinReport]

    public init(sessions: [SessionRecord] = [], reports: [SkinReport] = []) {
        self.sessions = sessions
        self.reports = reports
    }

    /// The history as one ordered stream: logged sessions at the end of what
    /// was faced, reports when they were answered, and a lasting-colour answer
    /// at its own timestamp — never at the report's. An answer that has not
    /// been given is not emitted, and neither is a session that was never
    /// logged or never faced anything.
    public func ordered() -> [HistoryEvent] {
        var stamped: [Stamped] = []
        for session in sessions where session.state == .logged {
            guard let end = session.actualWindow?.end else { continue }
            stamped.append(Stamped(time: end, rank: 0, event: .session(session)))
        }
        for report in reports {
            stamped.append(Stamped(time: report.reportedAt, rank: 1, event: .report(report)))
            if report.lastingColour != nil, let answeredAt = report.lastingColourAt {
                stamped.append(Stamped(time: answeredAt, rank: 2, event: .lastingColour(report)))
            }
        }
        return stamped
            .sorted { ($0.time, $0.rank) < ($1.time, $1.rank) }
            .map(\.event)
    }

    /// The logged sessions of each day, which is the evidence a report about
    /// that day is judged against.
    func loggedSessionsByDay() -> [DayKey: [SessionRecord]] {
        var byDay = [DayKey: [SessionRecord]]()
        for session in sessions where session.state == .logged && session.actualWindow != nil {
            byDay[session.day, default: []].append(session)
        }
        return byDay
    }
}

/// One event with the instant it belongs at, and a rank that keeps the order
/// stable when a session and a report share a timestamp.
private struct Stamped {
    let time: Date
    let rank: Int
    let event: HistoryEvent
}

/// One thing that happened, in replay order.
public enum HistoryEvent: Sendable {
    case session(SessionRecord)
    case report(SkinReport)
    case lastingColour(SkinReport)
}
