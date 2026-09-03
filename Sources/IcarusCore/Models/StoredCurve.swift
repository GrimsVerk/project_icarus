import Foundation

/// The curve as it is written down: inside a session record, and inside the
/// export. This is an EXTERNAL format — version 1 — so its shape is fixed and a
/// change to it bumps the export's `formatVersion`.
///
/// It carries only what one day needs: the samples that cover the day, the
/// solar noon that was used, and the place, zone and fetch time they came from.
public struct StoredCurve: Codable, Sendable, Equatable {
    /// Every sample from the day's local midnight to six hours past the next.
    public let hourly: [HourlyUVI]
    public let solarNoon: Date
    public let timeZoneID: String
    public let location: Coordinate
    public let fetchedAt: Date

    public init(
        hourly: [HourlyUVI],
        solarNoon: Date,
        timeZoneID: String,
        location: Coordinate,
        fetchedAt: Date
    ) {
        self.hourly = hourly
        self.solarNoon = solarNoon
        self.timeZoneID = timeZoneID
        self.location = location
        self.fetchedAt = fetchedAt
    }

    /// Rebuilds a curve that answers dose questions exactly as the original did
    /// over the day it covers.
    public func curve() throws -> ForecastCurve {
        let zone = TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
        return try ForecastCurve(
            location: location,
            timeZone: zone,
            fetchedAt: fetchedAt,
            hourly: hourly,
            solarNoon: [DayKey(solarNoon, timeZone: zone): solarNoon]
        )
    }
}
