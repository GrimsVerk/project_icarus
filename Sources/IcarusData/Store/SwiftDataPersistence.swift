#if canImport(SwiftData)
    import Foundation
    import IcarusCore
    import SwiftData

    /// The history on disk, on Apple platforms (R25).
    ///
    /// Every call opens its own `ModelContext` on the shared container and saves
    /// once at the end, so a call either lands whole or leaves the store as it
    /// was — which is what `replaceAll` promises the import.
    public struct SwiftDataPersistence: HistoryPersistence {
        private let container: ModelContainer

        public init(container: ModelContainer) {
            self.container = container
        }

        /// The store the app runs on: the default on-disk container for the two
        /// entities. They are internal to this package — nothing outside it
        /// knows the shape of the stored rows — so the app asks for this rather
        /// than building a container itself.
        public static func onDisk() throws -> SwiftDataPersistence {
            try SwiftDataPersistence(container: ModelContainer(for: SessionEntity.self, ReportEntity.self))
        }

        public func load() throws -> History {
            let context = ModelContext(container)
            let decoder = JSONDecoder()
            let sessions = try context.fetch(FetchDescriptor<SessionEntity>())
                .map { try $0.record(decoder) }
            let reports = try context.fetch(FetchDescriptor<ReportEntity>())
                .map { try $0.report(decoder) }
            return History(sessions: sessions, reports: reports)
        }

        public func replaceAll(_ new: History) throws {
            let context = ModelContext(container)
            let encoder = JSONEncoder()
            // Everything is encoded before anything is deleted: a record that
            // cannot be written must not cost the caller the history it had.
            let sessions = try new.sessions.map { try SessionEntity($0, encoder: encoder) }
            let reports = try new.reports.map { try ReportEntity($0, encoder: encoder) }
            try context.delete(model: SessionEntity.self)
            try context.delete(model: ReportEntity.self)
            for session in sessions {
                context.insert(session)
            }
            for report in reports {
                context.insert(report)
            }
            try context.save()
        }

        public func upsertSession(_ session: SessionRecord) throws {
            let context = ModelContext(container)
            let encoder = JSONEncoder()
            let id = session.id
            let existing = try context.fetch(
                FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == id })
            ).first
            if let existing {
                try existing.update(session, encoder: encoder)
            } else {
                try context.insert(SessionEntity(session, encoder: encoder))
            }
            try context.save()
        }

        public func upsertReport(_ report: SkinReport) throws {
            let context = ModelContext(container)
            let encoder = JSONEncoder()
            let id = report.id
            let existing = try context.fetch(
                FetchDescriptor<ReportEntity>(predicate: #Predicate { $0.id == id })
            ).first
            if let existing {
                try existing.update(report, encoder: encoder)
            } else {
                try context.insert(ReportEntity(report, encoder: encoder))
            }
            try context.save()
        }
    }
#endif
