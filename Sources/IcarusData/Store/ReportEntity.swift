#if canImport(SwiftData)
    import Foundation
    import IcarusCore
    import SwiftData

    /// One stored skin report, kept the same way a session is: the record as its
    /// own JSON, with the day mirrored into a column for the day queries.
    ///
    /// The lasting-colour answer lives inside the payload, at its own timestamp,
    /// because it belongs to the report it followed and never to a report of its
    /// own.
    @Model
    final class ReportEntity {
        @Attribute(.unique) var id: UUID
        /// `DayKey.id`, the zone-carrying day string.
        var dayID: String
        var payload: Data

        init(id: UUID, dayID: String, payload: Data) {
            self.id = id
            self.dayID = dayID
            self.payload = payload
        }

        convenience init(_ report: SkinReport, encoder: JSONEncoder) throws {
            try self.init(id: report.id, dayID: report.day.id, payload: encoder.encode(report))
        }

        func report(_ decoder: JSONDecoder) throws -> SkinReport {
            try decoder.decode(SkinReport.self, from: payload)
        }

        func update(_ report: SkinReport, encoder: JSONEncoder) throws {
            dayID = report.day.id
            payload = try encoder.encode(report)
        }
    }
#endif
