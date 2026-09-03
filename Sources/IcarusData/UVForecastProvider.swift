import Foundation
import IcarusCore

/// Why a provider could not answer. Every one of these is a named failure the
/// app can say out loud: nothing is ever flattened into "offline" (R1).
public enum ProviderError: Error, Sendable, Equatable {
    /// The service answered, but not with a forecast for this place.
    case unavailable(String)
    /// The entitlement or the token is missing or refused.
    case unauthorized
    /// The request never completed.
    case network(String)
}

/// What a provider hands back: the raw forecast, before it becomes a curve.
/// The engine never sees this type; `ForecastService` turns it into a
/// `ForecastCurve` and that is what leaves the data layer.
public struct ProviderForecast: Codable, Sendable {
    public let hourly: [HourlyUVI]
    public let solarNoon: [DayKey: Date]
    /// The time zone of the place the forecast is for, not of this device.
    public let timeZone: TimeZone
    /// How many days ahead the provider was asked for.
    public let horizonDays: Int

    public init(hourly: [HourlyUVI], solarNoon: [DayKey: Date], timeZone: TimeZone, horizonDays: Int) {
        self.hourly = hourly
        self.solarNoon = solarNoon
        self.timeZone = timeZone
        self.horizonDays = horizonDays
    }
}

/// A source of hourly UV index for a coordinate. WeatherKit is one; the fake
/// that replays recorded fixtures is another, and it is the one the tests and
/// the offline end-to-end run use (S8).
public protocol UVForecastProvider: Sendable {
    func forecast(at location: Coordinate, days: Int) async throws(ProviderError) -> ProviderForecast
    /// Recorded with the cached forecast, so the app can say where it came from.
    var name: String { get }
}
