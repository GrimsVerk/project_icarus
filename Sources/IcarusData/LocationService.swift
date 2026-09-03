import Foundation
import IcarusCore

#if canImport(CoreLocation)
    import CoreLocation
#endif

/// What a location source can answer with. `accuracyKm` is the radius the fix is
/// good to; R2 asks only for kilometre accuracy, so a large radius is normal and
/// is not a failure.
public enum LocationReading: Sendable, Equatable {
    case fix(Coordinate, accuracyKm: Double)
    case denied
    case unavailable
}

/// One shot at the device's position. The service never talks to CoreLocation
/// itself, so the tests drive it with a fake.
public protocol LocationSource: Sendable {
    func current() async -> LocationReading
}

/// A fixed answer, for tests and previews.
public struct FakeLocationSource: LocationSource {
    private let reading: LocationReading

    public init(reading: LocationReading) {
        self.reading = reading
    }

    public func current() async -> LocationReading {
        reading
    }
}

/// What the app should use as its place right now.
public enum LocationAnswer: Sendable, Equatable {
    /// The device's own position.
    case device(Coordinate)
    /// A place the user typed and chose; it wins over the device.
    case manual(Place)
    /// No usable position, and why. R2's manual entry is offered from here.
    case needsManual(reason: LocationReading)

    /// The coordinate to fetch a forecast for, or nil when the app must ask the
    /// user for a place first.
    public var coordinate: Coordinate? {
        switch self {
        case let .device(coordinate): coordinate
        case let .manual(place): place.coordinate
        case .needsManual: nil
        }
    }
}

/// The one place that decides where the user is (R2).
///
/// A manual place, once set, wins over the device until it is cleared: the user
/// said where they are and the app does not argue with them. Otherwise the
/// device is asked, and a denial or a failure is reported as itself rather than
/// masked, so the caller can offer manual entry with the true reason.
///
/// How far the device has drifted from the forecast the cache holds is a
/// question of two coordinates: the caller compares this answer's `coordinate`
/// with the cached curve's location through `Coordinate.distanceKm(to:)`, which
/// is what R1's 10 km refetch and R3's 25 km staleness warning are measured with.
public actor LocationService {
    private let source: any LocationSource
    private let resolver: any PlaceResolver
    private var manual: Place?

    public init(source: any LocationSource, resolver: any PlaceResolver) {
        self.source = source
        self.resolver = resolver
    }

    /// The manual place if there is one, else the device's position, else the
    /// reason there is none.
    public func location(now _: Date) async -> LocationAnswer {
        if let manual {
            return .manual(manual)
        }
        let reading = await source.current()
        switch reading {
        case let .fix(coordinate, _):
            return .device(coordinate)
        case .denied, .unavailable:
            return .needsManual(reason: reading)
        }
    }

    /// Candidate places for typed text, through the geocoder.
    public func resolve(_ text: String) async throws -> [Place] {
        try await resolver.resolve(text)
    }

    /// Pins the app to a place the user chose.
    public func useManual(_ place: Place) {
        manual = place
    }

    /// Goes back to the device's position.
    public func clearManual() {
        manual = nil
    }
}

#if canImport(CoreLocation)
    /// The real source: one CoreLocation request at kilometre accuracy with
    /// when-in-use permission (R2). It never keeps the manager running — a
    /// single fix, then it stops — and it gives up after ten seconds rather
    /// than leaving the caller waiting for a fix that may never arrive.
    public struct CoreLocationSource: LocationSource {
        private let timeout: TimeInterval

        public init() {
            self.init(timeout: 10)
        }

        init(timeout: TimeInterval) {
            self.timeout = timeout
        }

        public func current() async -> LocationReading {
            let request = await MainActor.run { OneShotLocationRequest() }
            return await request.read(timeout: timeout)
        }
    }

    /// Bridges CoreLocation's delegate callbacks to one `async` answer. The
    /// continuation is resumed exactly once — by a fix, by a denial, by a
    /// failure, or by the timeout, whichever comes first.
    private final class OneShotLocationRequest: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
        private let manager = CLLocationManager()
        private let lock = NSLock()
        private var continuation: CheckedContinuation<LocationReading, Never>?

        func read(timeout: TimeInterval) async -> LocationReading {
            await withCheckedContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()

                manager.delegate = self
                manager.desiredAccuracy = kCLLocationAccuracyKilometer
                start(for: manager.authorizationStatus)

                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(.unavailable)
                }
            }
        }

        private func start(for status: CLAuthorizationStatus) {
            switch status {
            case .denied, .restricted:
                finish(.denied)
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            default:
                manager.requestLocation()
            }
        }

        private func finish(_ reading: LocationReading) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: reading)
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            start(for: manager.authorizationStatus)
        }

        func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.last else { return }
            let coordinate = Coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            finish(.fix(coordinate, accuracyKm: max(0, location.horizontalAccuracy) / 1000))
        }

        func locationManager(_: CLLocationManager, didFailWithError _: any Error) {
            finish(.unavailable)
        }
    }
#endif
