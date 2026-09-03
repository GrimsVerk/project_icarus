import Foundation
import IcarusCore

/// A forecast as it is kept between launches, with the name of the provider it
/// came from so the app can say where the number came from.
public struct CachedForecast: Codable, Sendable {
    public let curve: ForecastCurve
    public let providerName: String

    public init(curve: ForecastCurve, providerName: String) {
        self.curve = curve
        self.providerName = providerName
    }
}

/// One forecast, kept. `load()` throws when the store is there but unreadable —
/// it returns nil only for "nothing saved yet", because a corrupt cache and an
/// empty one are different facts and the app names them differently (R1).
public protocol ForecastCacheStore: Sendable {
    func load() throws -> CachedForecast?
    func save(_: CachedForecast) throws
}

/// The cache that survives relaunch: one JSON file, `forecast.json`, in the
/// directory it was given. A save writes a temporary file and renames it over
/// the old one, so a save interrupted halfway leaves the previous forecast
/// intact rather than a half-written one.
public struct FileForecastCache: ForecastCacheStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private var fileURL: URL { directory.appendingPathComponent("forecast.json") }

    public func load() throws -> CachedForecast? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CachedForecast.self, from: data)
    }

    public func save(_ forecast: CachedForecast) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(forecast)
        let temporary = directory.appendingPathComponent("forecast-\(UUID().uuidString).json")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: temporary, to: fileURL)
    }
}

/// The cache for a run that should not touch the disk: one forecast, held in
/// memory, shared by every copy of the value.
public struct MemoryForecastCache: ForecastCacheStore {
    private let box = Box()

    public init() {}

    public func load() throws -> CachedForecast? {
        box.value
    }

    public func save(_ forecast: CachedForecast) throws {
        box.value = forecast
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: CachedForecast?

        var value: CachedForecast? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return stored
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                stored = newValue
            }
        }
    }
}
