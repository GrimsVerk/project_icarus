import Foundation

/// A calendar day in a named time zone. The day is the engine's unit of budget
/// and of history, so it always carries the zone it was decided in: the same
/// instant is two different days in two different places.
///
/// `id` is THE string form — notification identifiers and the export use it and
/// nothing else — and it round-trips: `DayKey(id: d.id) == d` for every `d`.
public struct DayKey: Codable, Sendable, Hashable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let timeZoneID: String

    public init(_ date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1970
        month = parts.month ?? 1
        day = parts.day ?? 1
        timeZoneID = timeZone.identifier
    }

    /// "2026-09-03@Europe/Oslo".
    public var id: String {
        let paddedMonth = String(format: "%02d", month)
        let paddedDay = String(format: "%02d", day)
        return "\(year)-\(paddedMonth)-\(paddedDay)@\(timeZoneID)"
    }

    /// Parses `id`. Returns nil for anything malformed, including an unknown
    /// time zone identifier.
    public init?(id: String) {
        guard let separator = id.firstIndex(of: "@") else { return nil }
        let datePart = String(id[id.startIndex ..< separator])
        let zonePart = String(id[id.index(after: separator)...])
        let fields = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3,
              fields[1].count == 2, fields[2].count == 2,
              let year = Int(fields[0]), let month = Int(fields[1]), let day = Int(fields[2]),
              (1 ... 12).contains(month), (1 ... 31).contains(day),
              let zone = TimeZone(identifier: zonePart)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
        timeZoneID = zone.identifier
    }

    /// Local midnight that opens this day.
    public func start() -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    /// Local midnight that opens the next day.
    public func end() -> Date {
        adding(days: 1).start()
    }

    /// The day `days` calendar days later in the same zone.
    public func adding(days: Int) -> DayKey {
        let moved = calendar.date(byAdding: .day, value: days, to: start()) ?? start()
        return DayKey(moved, timeZone: zone)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day, lhs.timeZoneID)
            < (rhs.year, rhs.month, rhs.day, rhs.timeZoneID)
    }

    private var zone: TimeZone {
        TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
}
