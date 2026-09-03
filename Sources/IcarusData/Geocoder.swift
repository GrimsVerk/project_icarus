import Foundation
import IcarusCore

#if canImport(CoreLocation)
    import CoreLocation
#endif

/// A named place with the coordinate and the time zone the forecast for it must
/// be read in (R2). The zone travels with the place because the engine's day
/// boundaries are local to the place, not to the device.
public struct Place: Sendable, Equatable, Codable {
    public let name: String
    public let coordinate: Coordinate
    public let timeZone: TimeZone

    public init(name: String, coordinate: Coordinate, timeZone: TimeZone) {
        self.name = name
        self.coordinate = coordinate
        self.timeZone = timeZone
    }

    /// The zone is written as its identifier — an external, stable spelling that
    /// survives a round trip through the export and the cache.
    private enum CodingKeys: String, CodingKey {
        case name
        case coordinate
        case timeZone
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        coordinate = try container.decode(Coordinate.self, forKey: .coordinate)
        let identifier = try container.decode(String.self, forKey: .timeZone)
        guard let zone = TimeZone(identifier: identifier) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timeZone,
                in: container,
                debugDescription: "Unknown time zone identifier \(identifier)"
            )
        }
        timeZone = zone
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(coordinate, forKey: .coordinate)
        try container.encode(timeZone.identifier, forKey: .timeZone)
    }
}

/// Turns typed text into candidate places. The only geocoding the app does; the
/// engine never sees it.
public protocol PlaceResolver: Sendable {
    func resolve(_ text: String) async throws -> [Place]
}

/// A table-driven resolver for tests and previews: no network, no framework.
/// Lookup is exact first, then trimmed and case-insensitive, so a fixture keyed
/// "Nice" answers "  nice " as well. Unknown text resolves to no candidates
/// rather than to an error — an empty result list is what a geocoder returns
/// for a place it does not know.
public struct FakePlaceResolver: PlaceResolver {
    private let table: [String: [Place]]

    public init(table: [String: [Place]]) {
        self.table = table
    }

    public func resolve(_ text: String) async throws -> [Place] {
        if let exact = table[text] {
            return exact
        }
        let needle = Self.normalised(text)
        let match = table.first { key, _ in Self.normalised(key) == needle }
        return match?.value ?? []
    }

    private static func normalised(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

#if canImport(CoreLocation)
    /// The real resolver: Apple's geocoder, which is what R2 names for the
    /// manual entry path. A placemark without a coordinate is dropped; a
    /// placemark without a zone falls back to the device's current zone.
    public struct AppleGeocoder: PlaceResolver {
        public init() {}

        public func resolve(_ text: String) async throws -> [Place] {
            let placemarks = try await CLGeocoder().geocodeAddressString(text)
            return placemarks.compactMap { placemark in
                guard let location = placemark.location else { return nil }
                let name = placemark.name
                    ?? placemark.locality
                    ?? placemark.administrativeArea
                    ?? text
                return Place(
                    name: name,
                    coordinate: Coordinate(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    ),
                    timeZone: placemark.timeZone ?? .current
                )
            }
        }
    }
#endif
