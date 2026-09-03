#if canImport(SwiftData)
    import Foundation
    import IcarusCore
    import SwiftData

    /// One stored session row.
    ///
    /// The record itself is kept as its own JSON, because `SessionRecord` is an
    /// EXTERNAL format (R22, R25): the export and the store must agree on it to
    /// the byte, and a hand-mapped column per field is where the two drift. The
    /// day and the state are mirrored into columns so the common queries — the
    /// day's sessions, the stale planned ones — do not decode every row.
    @Model
    final class SessionEntity {
        /// The record's own id, which is what every caller addresses it by.
        @Attribute(.unique) var id: UUID
        /// `DayKey.id`, the zone-carrying day string.
        var dayID: String
        /// `SessionState.rawValue`.
        var state: String
        var payload: Data

        init(id: UUID, dayID: String, state: String, payload: Data) {
            self.id = id
            self.dayID = dayID
            self.state = state
            self.payload = payload
        }

        convenience init(_ record: SessionRecord, encoder: JSONEncoder) throws {
            try self.init(
                id: record.id,
                dayID: record.day.id,
                state: record.state.rawValue,
                payload: encoder.encode(record)
            )
        }

        func record(_ decoder: JSONDecoder) throws -> SessionRecord {
            try decoder.decode(SessionRecord.self, from: payload)
        }

        func update(_ record: SessionRecord, encoder: JSONEncoder) throws {
            dayID = record.day.id
            state = record.state.rawValue
            payload = try encoder.encode(record)
        }
    }
#endif
