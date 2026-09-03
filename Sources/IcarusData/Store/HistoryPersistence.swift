import Foundation
import IcarusCore

/// Where the history is written down. The store above it never knows which
/// implementation it has: SwiftData on Apple platforms, memory everywhere else
/// (R25).
///
/// `replaceAll` is the atomic one — an import either lands whole or leaves the
/// stored history exactly as it was — because a half-imported history is a
/// record nobody can replay.
public protocol HistoryPersistence: Sendable {
    /// The whole history as it stands.
    func load() throws -> History

    /// Replace the whole history. All or nothing.
    func replaceAll(_ history: History) throws

    /// Insert the session, or replace the one with the same id.
    func upsertSession(_ session: SessionRecord) throws

    /// Insert the report, or replace the one with the same id.
    func upsertReport(_ report: SkinReport) throws
}

/// Why a write against the history was refused. Each case names the record it
/// was about, so the caller never has to guess which one.
public enum HistoryError: Error, Sendable, Equatable {
    /// A lasting-colour answer for a day that has no skin report.
    case noReport(DayKey)
    /// A second skin report for a day that already has one.
    case alreadyReported(DayKey)
    /// No session with this id.
    case unknownSession(UUID)
    /// The session was discarded, so it can no longer be logged.
    case discarded(UUID)
}
