import Foundation
import IcarusCore

// MARK: - The recorded shape

/// The shape of a WeatherKit answer, as recorded. The provider maps its live
/// answer into this before anything else happens, so the mapping — the part
/// that can be wrong — is testable on every platform without the framework.
public struct WeatherKitHourlyResponse: Codable, Sendable {
    public let hours: [WeatherKitHour]
    public let days: [WeatherKitDay]
    public let timeZoneIdentifier: String

    public init(hours: [WeatherKitHour], days: [WeatherKitDay], timeZoneIdentifier: String) {
        self.hours = hours
        self.days = days
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public struct WeatherKitHour: Codable, Sendable {
    public let date: Date
    public let uvIndex: Int

    public init(date: Date, uvIndex: Int) {
        self.date = date
        self.uvIndex = uvIndex
    }
}

public struct WeatherKitDay: Codable, Sendable {
    public let date: Date
    public let solarNoon: Date?

    public init(date: Date, solarNoon: Date?) {
        self.date = date
        self.solarNoon = solarNoon
    }
}

// MARK: - The mapping

/// Turns a recorded WeatherKit answer into a `ProviderForecast`. The day keys
/// are built in the forecast's own zone, because a day is a local day there.
public enum WeatherKitMapping {
    public static func forecast(
        from response: WeatherKitHourlyResponse,
        horizonDays: Int
    ) throws(ProviderError) -> ProviderForecast {
        guard let zone = TimeZone(identifier: response.timeZoneIdentifier) else {
            throw ProviderError.unavailable("time zone")
        }
        let hourly = response.hours.map { HourlyUVI(time: $0.date, uvi: Double($0.uvIndex)) }
        var noons = [DayKey: Date]()
        for day in response.days {
            guard let noon = day.solarNoon else { continue }
            noons[DayKey(day.date, timeZone: zone)] = noon
        }
        return ProviderForecast(hourly: hourly, solarNoon: noons, timeZone: zone, horizonDays: horizonDays)
    }
}

// MARK: - The live provider

#if canImport(WeatherKit) && canImport(CoreLocation)
    import CoreLocation
    import WeatherKit

    /// Remembers the zone of a place, so one reverse geocode serves every fetch
    /// at that coordinate.
    private actor ZoneCache {
        static let shared = ZoneCache()
        private var zones = [String: String]()

        private func key(_ location: Coordinate) -> String {
            String(format: "%.3f,%.3f", location.latitude, location.longitude)
        }

        func zone(for location: Coordinate) -> String? { zones[key(location)] }

        func remember(_ identifier: String, for location: Coordinate) {
            zones[key(location)] = identifier
        }
    }

    public struct WeatherKitProvider: UVForecastProvider {
        public let name = "WeatherKit"

        public init() {}

        public func forecast(at location: Coordinate, days: Int) async throws(ProviderError) -> ProviderForecast {
            let place = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let start = Date()
            let end = start.addingTimeInterval(Double(days) * 24 * 3600)
            let identifier = await Self.zoneIdentifier(for: location, place: place)
            let hours: [WeatherKitHour]
            let dayEntries: [WeatherKitDay]
            do {
                let answer = try await WeatherService.shared.weather(
                    for: place,
                    including: .hourly(startDate: start, endDate: end), .daily(startDate: start, endDate: end)
                )
                hours = answer.0.forecast.map { WeatherKitHour(date: $0.date, uvIndex: $0.uvIndex.value) }
                dayEntries = answer.1.forecast.map { WeatherKitDay(date: $0.date, solarNoon: $0.sun.solarNoon) }
            } catch {
                throw ProviderError.network(String(describing: error))
            }
            let response = WeatherKitHourlyResponse(hours: hours, days: dayEntries, timeZoneIdentifier: identifier)
            return try WeatherKitMapping.forecast(from: response, horizonDays: days)
        }

        /// The place's own zone, from a reverse geocode, cached per coordinate.
        /// A geocode that fails falls back to the device zone rather than
        /// failing the fetch: a wrong-by-an-hour day boundary is far less bad
        /// than no forecast at all.
        private static func zoneIdentifier(for location: Coordinate, place: CLLocation) async -> String {
            if let known = await ZoneCache.shared.zone(for: location) { return known }
            let marks = try? await CLGeocoder().reverseGeocodeLocation(place)
            let identifier = marks?.first?.timeZone?.identifier ?? TimeZone.current.identifier
            await ZoneCache.shared.remember(identifier, for: location)
            return identifier
        }
    }

#else

    /// WeatherKit is an Apple framework. Off Apple platforms the provider still
    /// exists — the engine is built against the protocol — and says plainly
    /// that it cannot answer here.
    public struct WeatherKitProvider: UVForecastProvider {
        public let name = "WeatherKit"

        public init() {}

        public func forecast(at _: Coordinate, days _: Int) async throws(ProviderError) -> ProviderForecast {
            throw ProviderError.unavailable("WeatherKit is not available on this platform")
        }
    }

#endif
