import Foundation
import IcarusCore

/// A provider that replays a recorded forecast. It is how the whole engine runs
/// end to end with no network — in the tests, in the simulator, and in the
/// offline demo (S8) — and how a named failure is provoked on purpose.
public struct FakeForecastProvider: UVForecastProvider {
    public let name = "fake"

    private let fixture: ProviderForecast
    private let delay: Duration
    private let failing: ProviderError?
    private let malformed: Bool

    /// - Parameters:
    ///   - fixture: what a successful fetch returns.
    ///   - delay: how long the fetch takes, for testing what happens meanwhile.
    ///   - failing: when set, every fetch throws this instead of answering.
    ///   - malformed: when true, the answer is a forecast no curve can be built
    ///     from — the samples come back out of order — so the service must
    ///     report `.malformed` and never `.provider`.
    public init(
        fixture: ProviderForecast,
        delay: Duration = .zero,
        failing: ProviderError? = nil,
        malformed: Bool = false
    ) {
        self.fixture = fixture
        self.delay = delay
        self.failing = failing
        self.malformed = malformed
    }

    public func forecast(at _: Coordinate, days _: Int) async throws(ProviderError) -> ProviderForecast {
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        if let failing {
            throw failing
        }
        guard malformed else { return fixture }
        return ProviderForecast(
            hourly: fixture.hourly.reversed(),
            solarNoon: fixture.solarNoon,
            timeZone: fixture.timeZone,
            horizonDays: fixture.horizonDays
        )
    }

    /// Loads `<named>.json` — a recorded WeatherKit answer, shipped with this
    /// target — and maps it exactly as the live provider maps a live one.
    public static func fixture(named: String) throws -> ProviderForecast {
        let data = try fixtureData(named: named)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(WeatherKitHourlyResponse.self, from: data)
        let days = Set(response.days.map(\.date)).count
        return try WeatherKitMapping.forecast(from: response, horizonDays: max(days, 1))
    }

    private static func fixtureData(named: String) throws -> Data {
        let subdirectory = "Resources/Fixtures"
        if let url = Bundle.module.url(forResource: named, withExtension: "json", subdirectory: subdirectory) {
            return try Data(contentsOf: url)
        }
        let fallback = Bundle.module.bundleURL
            .appendingPathComponent(subdirectory)
            .appendingPathComponent("\(named).json")
        guard FileManager.default.fileExists(atPath: fallback.path) else {
            throw ProviderError.unavailable("fixture \(named)")
        }
        return try Data(contentsOf: fallback)
    }
}
