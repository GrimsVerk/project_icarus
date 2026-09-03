import Foundation

/// Why a forecast curve could not be built.
public enum ForecastCurveError: Error, Equatable {
    case tooFewSamples
    case unsorted
}

/// A forecast, ready to integrate. The hourly samples are interpolated linearly
/// to one-minute resolution once, at construction, into a prefix integral of
/// SED; every dose question is then two lookups and a subtraction (R4). The
/// window's endpoints are never averaged.
///
/// The curve carries the time zone of the place it is for, because the day —
/// the unit of budget — is a local calendar day there, not here.
public struct ForecastCurve: Codable, Sendable {
    public let location: Coordinate
    public let timeZone: TimeZone
    public let fetchedAt: Date
    /// The last instant the forecast says anything about.
    public let horizonEnd: Date
    public let hourly: [HourlyUVI]

    private let solarNoons: [DayKey: Date]
    /// Cumulative SED at each whole minute from `prefixStart`.
    let prefixSED: [Double]
    let prefixStart: Date

    public init(
        location: Coordinate,
        timeZone: TimeZone,
        fetchedAt: Date,
        hourly: [HourlyUVI],
        solarNoon: [DayKey: Date]
    ) throws {
        guard hourly.count >= 2 else { throw ForecastCurveError.tooFewSamples }
        for (earlier, later) in zip(hourly, hourly.dropFirst()) where later.time <= earlier.time {
            throw ForecastCurveError.unsorted
        }
        self.location = location
        self.timeZone = timeZone
        self.fetchedAt = fetchedAt
        self.hourly = hourly
        solarNoons = solarNoon
        let first = hourly[0].time
        let last = hourly[hourly.count - 1].time
        horizonEnd = last
        prefixStart = first
        prefixSED = Self.prefixIntegral(hourly, from: first, to: last)
    }

    /// UV index at an instant, linearly interpolated. Zero outside the samples.
    public func uvi(at time: Date) -> UVI {
        Self.interpolatedUVI(hourly, at: time)
    }

    /// SED delivered to bare skin between two instants, by the trapezoidal rule
    /// on the one-minute curve. Zero when the interval is empty or reversed;
    /// clamped at the ends of the forecast.
    public func sed(from start: Date, to end: Date) -> SED {
        guard end > start else { return 0 }
        return prefixValue(at: end) - prefixValue(at: start)
    }

    /// The forecast's own solar noon for a day, or the NOAA value computed from
    /// the place and the date when the forecast did not supply one.
    public func solarNoon(on day: DayKey) -> Date {
        solarNoons[day] ?? Self.noaaSolarNoon(location: location, day: day)
    }

    /// The local calendar day an instant falls in, at this forecast's place.
    public func day(_ date: Date) -> DayKey {
        DayKey(date, timeZone: timeZone)
    }

    /// The export-facing slice of this curve for one day: every sample from
    /// local midnight to six hours past the next, so a session logged near
    /// midnight still has its curve.
    public func stored(for day: DayKey) -> StoredCurve {
        let opens = day.start()
        let closes = day.end().addingTimeInterval(6 * 3600)
        return StoredCurve(
            hourly: hourly.filter { $0.time >= opens && $0.time <= closes },
            solarNoon: solarNoon(on: day),
            timeZoneID: timeZone.identifier,
            location: location,
            fetchedAt: fetchedAt
        )
    }

    /// Cumulative SED at `time`, interpolated within the minute.
    func prefixValue(at time: Date) -> Double {
        let minutes = time.timeIntervalSince(prefixStart) / 60
        guard minutes > 0 else { return 0 }
        let lastIndex = prefixSED.count - 1
        guard minutes < Double(lastIndex) else { return prefixSED[lastIndex] }
        let index = Int(minutes)
        let fraction = minutes - Double(index)
        return prefixSED[index] + fraction * (prefixSED[index + 1] - prefixSED[index])
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case location, timeZone, fetchedAt, hourly, solarNoons
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var noons = [DayKey: Date]()
        for (id, date) in try container.decode([String: Date].self, forKey: .solarNoons) {
            if let day = DayKey(id: id) {
                noons[day] = date
            }
        }
        try self.init(
            location: container.decode(Coordinate.self, forKey: .location),
            timeZone: container.decode(TimeZone.self, forKey: .timeZone),
            fetchedAt: container.decode(Date.self, forKey: .fetchedAt),
            hourly: container.decode([HourlyUVI].self, forKey: .hourly),
            solarNoon: noons
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(location, forKey: .location)
        try container.encode(timeZone, forKey: .timeZone)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encode(hourly, forKey: .hourly)
        var noons = [String: Date]()
        for (day, date) in solarNoons {
            noons[day.id] = date
        }
        try container.encode(noons, forKey: .solarNoons)
    }
}

// MARK: - Integration and astronomy

private extension ForecastCurve {
    /// Trapezoidal integration of the interpolated curve at one-minute steps,
    /// divided by the UVI·minutes per SED constant.
    static func prefixIntegral(_ samples: [HourlyUVI], from start: Date, to end: Date) -> [Double] {
        let perSED = Tunables.current.uviMinutesPerSED
        let minutes = max(1, Int((end.timeIntervalSince(start) / 60).rounded()))
        var prefix = [Double](repeating: 0, count: minutes + 1)
        var previous = interpolatedUVI(samples, at: start)
        var total = 0.0
        for minute in 1 ... minutes {
            let current = interpolatedUVI(samples, at: start.addingTimeInterval(Double(minute) * 60))
            total += (previous + current) / 2 / perSED
            prefix[minute] = total
            previous = current
        }
        return prefix
    }

    static func interpolatedUVI(_ samples: [HourlyUVI], at time: Date) -> UVI {
        guard let first = samples.first, let last = samples.last else { return 0 }
        guard time >= first.time, time <= last.time else { return 0 }
        var low = 0
        var high = samples.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if samples[middle].time <= time {
                low = middle
            } else {
                high = middle
            }
        }
        let before = samples[low]
        let after = samples[high]
        let span = after.time.timeIntervalSince(before.time)
        guard span > 0 else { return before.uvi }
        let fraction = time.timeIntervalSince(before.time) / span
        return before.uvi + fraction * (after.uvi - before.uvi)
    }

    /// NOAA's solar-noon formula: the equation of time for the day, corrected
    /// for longitude. Accurate to well under a minute, which is far finer than
    /// anything the UVA notice needs.
    static func noaaSolarNoon(location: Coordinate, day: DayKey) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.year = day.year
        parts.month = day.month
        parts.day = day.day
        guard let midnightUTC = calendar.date(from: parts),
              let dayOfYear = calendar.ordinality(of: .day, in: .year, for: midnightUTC)
        else { return Date(timeIntervalSince1970: 0) }
        let gamma = 2 * Double.pi / 365 * (Double(dayOfYear) - 1)
        let equationOfTime = 229.18 * (0.000075
            + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let minutesUTC = 720 - 4 * location.longitude - equationOfTime
        return midnightUTC.addingTimeInterval(minutesUTC * 60)
    }
}
