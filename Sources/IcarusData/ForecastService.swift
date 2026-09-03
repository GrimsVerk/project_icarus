import Foundation
import IcarusCore

/// Which kind of failure it was, without the detail — what a caller switches on
/// when it only needs to choose a line of copy.
public enum ForecastFailureKind: Sendable, Equatable {
    case provider
    case malformed
    case cacheUnreadable
}

/// Why there is no fresh forecast. Every failure is named: the provider said
/// no, the answer could not be made into a curve, or the cache could not be
/// read. None of them is ever reported as plain "offline" (R1).
public enum ForecastFailure: Error, Sendable, Equatable {
    case provider(ProviderError)
    case malformed(ForecastCurveError)
    case cacheUnreadable(String)

    public var kind: ForecastFailureKind {
        switch self {
        case .provider: .provider
        case .malformed: .malformed
        case .cacheUnreadable: .cacheUnreadable
        }
    }
}

/// Why the answer came from the cache rather than the network.
public enum CacheReason: Sendable, Equatable {
    /// Inside the fetch interval and close enough to the cached place.
    case withinInterval
    /// A fetch was tried and named its failure; this is the last good forecast.
    case providerFailed(ForecastFailure)
}

/// What a request for a forecast produced.
public enum ForecastResult: Sendable {
    case fresh(ForecastCurve)
    case cached(ForecastCurve, reason: CacheReason)
    case none(ForecastFailure)

    public var curve: ForecastCurve? {
        switch self {
        case let .fresh(curve): curve
        case let .cached(curve, _): curve
        case .none: nil
        }
    }

    public var failure: ForecastFailure? {
        switch self {
        case .fresh: nil
        case let .cached(_, reason):
            if case let .providerFailed(failure) = reason { failure } else { nil }
        case let .none(failure): failure
        }
    }
}

/// The one way into a forecast. It fetches at the ruled cadence — at most once
/// an hour for the same place, again as soon as the user has moved more than
/// `fetchMoveKm` — keeps the last good answer on disk, and names every failure.
public actor ForecastService {
    private let provider: any UVForecastProvider
    private let cache: any ForecastCacheStore
    private let tunables: Tunables

    public init(provider: any UVForecastProvider, cache: any ForecastCacheStore, tunables: Tunables) {
        self.provider = provider
        self.cache = cache
        self.tunables = tunables
    }

    /// The forecast for a place. The cached one when it is recent enough and
    /// close enough, otherwise a fetch; a failed fetch falls back to the cached
    /// curve with the failure attached, and to nothing at all when there is no
    /// cache. `force` always fetches.
    public func current(for location: Coordinate, now: Date, force: Bool = false) async -> ForecastResult {
        let stored = try? cache.load()
        if !force, let stored, isUsable(stored.curve, at: now, for: location) {
            return .cached(stored.curve, reason: .withinInterval)
        }
        do {
            let answer = try await provider.forecast(at: location, days: tunables.forecastHorizonDays)
            let curve = try ForecastCurve(
                location: location,
                timeZone: answer.timeZone,
                fetchedAt: now,
                hourly: answer.hourly,
                solarNoon: answer.solarNoon
            )
            try? cache.save(CachedForecast(curve: curve, providerName: provider.name))
            return .fresh(curve)
        } catch {
            let failure = Self.named(error)
            if let stored { return .cached(stored.curve, reason: .providerFailed(failure)) }
            return .none(failure)
        }
    }

    /// The forecast on disk, whatever its age. Never fetches — this is what the
    /// app shows while a fetch is still running, and what it falls back to when
    /// there is no network at all.
    public func cached() -> ForecastResult {
        do {
            guard let stored = try cache.load() else {
                return .none(.cacheUnreadable("no forecast has been saved"))
            }
            return .cached(stored.curve, reason: .withinInterval)
        } catch {
            return .none(.cacheUnreadable(String(describing: error)))
        }
    }

    /// Recent enough and close enough to answer with as it is.
    private func isUsable(_ curve: ForecastCurve, at now: Date, for location: Coordinate) -> Bool {
        let age = now.timeIntervalSince(curve.fetchedAt)
        guard age < tunables.fetchMinIntervalHours * 3600 else { return false }
        return location.distanceKm(to: curve.location) <= tunables.fetchMoveKm
    }

    /// A curve that could not be built is malformed data, never a provider
    /// failure: the two send the user to different remedies.
    private static func named(_ error: any Error) -> ForecastFailure {
        switch error {
        case let error as ProviderError: .provider(error)
        case let error as ForecastCurveError: .malformed(error)
        default: .provider(.unavailable(String(describing: error)))
        }
    }
}
