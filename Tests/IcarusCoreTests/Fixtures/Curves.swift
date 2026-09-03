import Foundation
@testable import IcarusCore

/// Deterministic forecast fixtures for the Core tests.
///
/// Every curve is built in UTC, starting 2026-06-15, at Oslo's coordinates
/// (59.9 N, 10.75 E), with hourly samples covering whole days. Solar noon is
/// supplied explicitly for every day so that no test depends on the NOAA
/// formula except the one test that checks it (`withSolarNoon: false`).
enum Curves {
    static let location = Coordinate(latitude: 59.9, longitude: 10.75)
    static let zone = TimeZone(identifier: "UTC")!

    /// Midnight UTC on the fixtures' first day.
    static var start: Date { date(2026, 6, 15) }

    /// A fixed instant in the fixtures' UTC calendar. Never derived from `Date()`.
    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)!
    }

    // MARK: - Curves

    /// Flat UVI across whole days.
    static func steadyUVI(_ uvi: Double, days: Int = 2, withSolarNoon: Bool = true) throws -> ForecastCurve {
        try build(days: days, withSolarNoon: withSolarNoon) { _ in uvi }
    }

    /// UVI rises linearly 0 → 8 over 08:00–12:00 and falls 8 → 0 to 16:00,
    /// repeated for three days. Its 08:00–16:00 SED has a closed form: a
    /// triangle of base 480 minutes and height 8, divided by 66.7.
    static func ramp() throws -> ForecastCurve {
        try build(days: 3, shape: rampShape)
    }

    /// UVI 8 at 14:00, falling steeply to 2 at 15:00, then flat 2 until 17:00.
    /// The build prompt's counter-example to averaging a window's endpoints.
    static func steepThenFlat14to17() throws -> ForecastCurve {
        try build(days: 2, shape: steepShape)
    }

    /// UVI falls by one point an hour through the afternoon and evening.
    static func eveningFalling() throws -> ForecastCurve {
        try build(days: 2, shape: eveningShape)
    }

    /// UVI rises through 09:00–12:00 to its peak at noon.
    static func morningRising() throws -> ForecastCurve {
        try build(days: 2, shape: morningShape)
    }

    /// Ten days whose peak UVI is 0.1 — far below any usable dose.
    static func winterLow() throws -> ForecastCurve {
        try build(days: 10) { lowShape(peak: 0.1, from: 9, to: 15, hour: $0) }
    }

    /// Ten days with an even narrower low hump than `winterLow`.
    static func tenDayLow() throws -> ForecastCurve {
        try build(days: 10) { lowShape(peak: 0.1, from: 10, to: 14, hour: $0) }
    }

    /// Flat UVI 8 — a strong midsummer beach day.
    static func beachFlatUVI8() throws -> ForecastCurve {
        try steadyUVI(8)
    }

    /// Flat UVI 2 — a shoulder hour that still delivers, slowly.
    static func shoulderHourUVI2() throws -> ForecastCurve {
        try steadyUVI(2)
    }

    // MARK: - Shapes

    private static func rampShape(_ hour: Int) -> Double {
        switch hour {
        case 8 ... 12: Double(hour - 8) * 2
        case 13 ... 16: 8 - Double(hour - 12) * 2
        default: 0
        }
    }

    private static func steepShape(_ hour: Int) -> Double {
        switch hour {
        case 6 ... 12: Double(hour - 6) / 6 * 8
        case 13, 14: 8
        case 15, 16, 17: 2
        case 18: 1
        default: 0
        }
    }

    private static func eveningShape(_ hour: Int) -> Double {
        switch hour {
        case 8 ... 12: Double(hour - 8) * 2
        case 13 ... 19: 8 - Double(hour - 12)
        case 20: 0.5
        default: 0
        }
    }

    private static func morningShape(_ hour: Int) -> Double {
        switch hour {
        case 6 ... 9: Double(hour - 5) * 0.5
        case 10 ... 12: Double(hour - 8) * 2
        case 13, 14: 20 - Double(hour)
        case 15: 4
        case 16: 2
        case 17: 1
        case 18: 0.5
        default: 0
        }
    }

    private static func lowShape(peak: Double, from first: Int, to last: Int, hour: Int) -> Double {
        guard hour > first, hour < last else { return 0 }
        let middle = Double(first + last) / 2
        let halfSpan = Double(last - first) / 2
        return peak * (1 - abs(Double(hour) - middle) / halfSpan)
    }

    // MARK: - Builder

    private static func build(
        days: Int,
        withSolarNoon: Bool = true,
        shape: (Int) -> Double
    ) throws -> ForecastCurve {
        var samples: [HourlyUVI] = []
        for index in 0 ... (days * 24) {
            let time = start.addingTimeInterval(Double(index) * 3600)
            samples.append(HourlyUVI(time: time, uvi: shape(index % 24)))
        }
        var noon: [DayKey: Date] = [:]
        if withSolarNoon {
            for index in 0 ..< days {
                let dayStart = start.addingTimeInterval(Double(index) * 86400)
                noon[DayKey(dayStart, timeZone: zone)] = dayStart.addingTimeInterval(12 * 3600)
            }
        }
        return try ForecastCurve(location: location,
                                 timeZone: zone,
                                 fetchedAt: start,
                                 hourly: samples,
                                 solarNoon: noon)
    }
}
