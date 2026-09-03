import Foundation

/// Standard Erythemal Dose. 1 SED = 100 J/m² erythemally weighted.
public typealias SED = Double

/// UV Index, as the forecast reports it.
public typealias UVI = Double

/// A point on the earth. The engine never reads it from the device; the caller
/// supplies it with the forecast it came from.
public struct Coordinate: Codable, Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in kilometres (spherical earth, mean radius).
    public func distanceKm(to other: Coordinate) -> Double {
        let earthRadiusKm = 6371.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let chord = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusKm * atan2(sqrt(chord), sqrt(max(0, 1 - chord)))
    }
}

/// One forecast sample: the UV index at an instant.
public struct HourlyUVI: Codable, Sendable, Equatable {
    public let time: Date
    public let uvi: UVI

    public init(time: Date, uvi: UVI) {
        self.time = time
        self.uvi = uvi
    }
}
