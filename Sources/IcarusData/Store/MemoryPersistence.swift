import Foundation
import IcarusCore

/// The history in memory. This is what Linux tests and previews run against,
/// and it is the reference behaviour every other implementation must match.
///
/// It is a `struct` the protocol's `Sendable` requirement is happy with, but
/// the records live in a reference-typed box behind a lock: a copy of the value
/// shares the same store, so handing it to an actor does not quietly fork the
/// history in two.
public struct MemoryPersistence: HistoryPersistence {
    private let box = Box()

    public init() {}

    public func load() throws -> History {
        box.read()
    }

    public func replaceAll(_ new: History) throws {
        box.write { $0 = new }
    }

    public func upsertSession(_ session: SessionRecord) throws {
        box.write { history in
            if let existing = history.sessions.firstIndex(where: { $0.id == session.id }) {
                history.sessions[existing] = session
            } else {
                history.sessions.append(session)
            }
        }
    }

    public func upsertReport(_ report: SkinReport) throws {
        box.write { history in
            if let existing = history.reports.firstIndex(where: { $0.id == report.id }) {
                history.reports[existing] = report
            } else {
                history.reports.append(report)
            }
        }
    }
}

/// The shared history, and the lock that makes sharing it safe.
private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var history = History()

    func read() -> History {
        lock.lock()
        defer { lock.unlock() }
        return history
    }

    func write(_ change: (inout History) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        change(&history)
    }
}
