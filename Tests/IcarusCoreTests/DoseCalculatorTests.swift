@testable import IcarusCore
import XCTest

/// R4: dose is the trapezoid of a one-minute interpolation of the hourly UVI
/// series, divided by 66.7 — never the average of the window's endpoints.
final class ForecastCurveIntegrationTests: XCTestCase {
    private let uviMinutesPerSED = 66.7

    func testSEDOverAnAnalyticRampMatchesTheClosedForm() throws {
        let curve = try Curves.ramp()
        // A triangle: base 480 minutes, height UVI 8.
        let expected = 0.5 * 480 * 8 / uviMinutesPerSED
        let measured = curve.sed(from: Curves.date(2026, 6, 15, 8), to: Curves.date(2026, 6, 15, 16))
        XCTAssertEqual(measured, expected, accuracy: expected * 0.005)
    }

    func testSEDOverASteepThenFlatWindowIsNotTheEndpointMean() throws {
        let curve = try Curves.steepThenFlat14to17()
        let from = Curves.date(2026, 6, 15, 14)
        let till = Curves.date(2026, 6, 15, 17)
        let endpointMean = (curve.uvi(at: from) + curve.uvi(at: till)) / 2 * 180 / uviMinutesPerSED
        XCTAssertEqual(endpointMean, 13.49, accuracy: 0.05)
        XCTAssertGreaterThan(abs(curve.sed(from: from, to: till) - endpointMean), 1.0)
    }

    func testSEDOverASteepThenFlatWindowIsTheTrapezoid() throws {
        let curve = try Curves.steepThenFlat14to17()
        // 8 → 2 over the first hour, then 2 flat: 300 + 120 + 120 UVI-minutes.
        let expected = 540 / uviMinutesPerSED
        let measured = curve.sed(from: Curves.date(2026, 6, 15, 14), to: Curves.date(2026, 6, 15, 17))
        XCTAssertEqual(measured, expected, accuracy: expected * 0.005)
    }

    func testSEDIsZeroWhenTheIntervalDoesNotRunForwards() throws {
        let curve = try Curves.beachFlatUVI8()
        let noon = Curves.date(2026, 6, 15, 12)
        XCTAssertEqual(curve.sed(from: noon, to: noon), 0, accuracy: 1e-12)
        XCTAssertEqual(curve.sed(from: noon, to: noon.addingTimeInterval(-3600)), 0, accuracy: 1e-12)
    }

    func testUVIIsInterpolatedBetweenHourlySamples() throws {
        let curve = try Curves.ramp()
        XCTAssertEqual(curve.uvi(at: Curves.date(2026, 6, 15, 9, 30)), 3.0, accuracy: 1e-9)
        XCTAssertEqual(curve.uvi(at: Curves.date(2026, 6, 15, 12)), 8.0, accuracy: 1e-9)
    }

    func testSolarNoonForAnUnsuppliedDayFollowsTheNOAAFormula() throws {
        let curve = try Curves.steadyUVI(7, withSolarNoon: false)
        let day = curve.day(Curves.date(2026, 6, 15, 12))
        // NOAA: gamma from the day of year (2026-06-15 is day 166), then the
        // equation of time in minutes; solar noon = 720 - 4*longitude - eqTime.
        let gamma = 2 * Double.pi / 365 * (166 - 1)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let reference = day.start().addingTimeInterval((720 - 4 * Curves.location.longitude - eqTime) * 60)
        XCTAssertEqual(curve.solarNoon(on: day).timeIntervalSince(reference), 0, accuracy: 300)
    }

    func testASuppliedSolarNoonIsUsedAsGiven() throws {
        let curve = try Curves.steadyUVI(7)
        let day = curve.day(Curves.date(2026, 6, 15, 12))
        XCTAssertEqual(curve.solarNoon(on: day), Curves.date(2026, 6, 15, 12))
    }
}

/// The export-facing `StoredCurve` must reproduce the dose it was cut from.
final class StoredCurveTests: XCTestCase {
    func testTheStoredCurveReproducesTheSameSED() throws {
        let curve = try Curves.ramp()
        let day = curve.day(Curves.date(2026, 6, 15, 12))
        let rebuilt = try curve.stored(for: day).curve()
        let from = Curves.date(2026, 6, 15, 10)
        let till = Curves.date(2026, 6, 15, 14)
        XCTAssertGreaterThan(curve.sed(from: from, to: till), 0)
        XCTAssertEqual(rebuilt.sed(from: from, to: till), curve.sed(from: from, to: till), accuracy: 1e-9)
    }

    func testTheStoredCurveSpansTheDayAndSixHoursBeyondIt() throws {
        let curve = try Curves.ramp()
        let day = curve.day(Curves.date(2026, 6, 15, 12))
        let stored = curve.stored(for: day)
        let first = try XCTUnwrap(stored.hourly.first)
        let last = try XCTUnwrap(stored.hourly.last)
        XCTAssertEqual(first.time, day.start())
        XCTAssertGreaterThanOrEqual(last.time, day.end())
        XCTAssertLessThanOrEqual(last.time, day.end().addingTimeInterval(6 * 3600))
    }

    func testTheStoredCurveCarriesItsPlaceAndZone() throws {
        let curve = try Curves.ramp()
        let day = curve.day(Curves.date(2026, 6, 15, 12))
        let stored = curve.stored(for: day)
        XCTAssertEqual(stored.timeZoneID, "UTC")
        XCTAssertEqual(stored.location, Curves.location)
        XCTAssertEqual(stored.solarNoon, Curves.date(2026, 6, 15, 12))
    }
}

/// The engine's answer to "how long, starting when" for a target dose.
/// A calibrated type II at multiplier 1.0 and the standard scale has a target
/// of 2.5 x 0.90 = 2.25 SED; at a steady UVI 7 that is 21.44 minutes.
final class DoseCalculatorDurationTests: XCTestCase {
    private let typeIIStandardTarget: SED = 2.25

    func testDurationForTypeIIAtSteadyUVISevenIsAboutTwentyOneMinutes() throws {
        let curve = try Curves.steadyUVI(7)
        let start = Curves.date(2026, 6, 15, 12)
        let minutes = DoseCalculator.durationFrom(start,
                                                  targetSED: typeIIStandardTarget,
                                                  curve: curve,
                                                  notAfter: Curves.date(2026, 6, 15, 16))
        XCTAssertEqual(try XCTUnwrap(minutes), 21.44, accuracy: 0.5)
    }

    func testDurationIsShorterOnAStrongerCurve() throws {
        let curve = try Curves.beachFlatUVI8()
        let start = Curves.date(2026, 6, 15, 12)
        let minutes = DoseCalculator.durationFrom(start,
                                                  targetSED: typeIIStandardTarget,
                                                  curve: curve,
                                                  notAfter: Curves.date(2026, 6, 15, 16))
        XCTAssertEqual(try XCTUnwrap(minutes), 18.76, accuracy: 0.5)
    }

    func testDurationIsNilWhenTheCutOffArrivesFirst() throws {
        let curve = try Curves.steadyUVI(7)
        let start = Curves.date(2026, 6, 15, 12)
        XCTAssertNil(DoseCalculator.durationFrom(start,
                                                 targetSED: typeIIStandardTarget,
                                                 curve: curve,
                                                 notAfter: Curves.date(2026, 6, 15, 12, 10)))
    }

    func testBestSubWindowOnASteadyCurveIsTheSameTwentyOneMinutes() throws {
        let curve = try Curves.steadyUVI(7)
        let window = Window(start: Curves.date(2026, 6, 15, 11), end: Curves.date(2026, 6, 15, 15))
        let best = DoseCalculator.bestSubWindow(curve: curve,
                                                within: window,
                                                now: Curves.date(2026, 6, 15, 10),
                                                targetSED: typeIIStandardTarget,
                                                tunables: .current)
        XCTAssertEqual(try XCTUnwrap(best).minutes, 21.44, accuracy: 0.5)
    }

    func testBestSubWindowTakesTheLastMinutesWhenTheCurveIsStillRising() throws {
        let curve = try Curves.morningRising()
        let window = Window(start: Curves.date(2026, 6, 15, 9), end: Curves.date(2026, 6, 15, 12))
        let best = try XCTUnwrap(DoseCalculator.bestSubWindow(curve: curve,
                                                              within: window,
                                                              now: Curves.date(2026, 6, 15, 8),
                                                              targetSED: typeIIStandardTarget,
                                                              tunables: .current))
        XCTAssertEqual(best.end.timeIntervalSince(Curves.date(2026, 6, 15, 12)), 0, accuracy: 1)
    }

    func testBestSubWindowStartsAtNowWhenTheCurveIsFalling() throws {
        let curve = try Curves.eveningFalling()
        let now = Curves.date(2026, 6, 15, 17)
        let window = Window(start: Curves.date(2026, 6, 15, 16), end: Curves.date(2026, 6, 15, 20))
        let best = try XCTUnwrap(DoseCalculator.bestSubWindow(curve: curve,
                                                              within: window,
                                                              now: now,
                                                              targetSED: 1.0,
                                                              tunables: .current))
        XCTAssertEqual(best.start.timeIntervalSince(now), 0, accuracy: 1)
    }
}

/// R17's clock rules: viability, the horizon search, the UVA flag, and the
/// clip that refuses to recommend a minute that has already gone.
final class DoseCalculatorWindowTests: XCTestCase {
    private let target: SED = 2.25

    func testClipReturnsNilForAWindowThatHasPassed() {
        let window = Window(start: Curves.date(2026, 6, 15, 9), end: Curves.date(2026, 6, 15, 11))
        XCTAssertNil(DoseCalculator.clip(window, toStartNoEarlierThan: Curves.date(2026, 6, 15, 11)))
        XCTAssertNil(DoseCalculator.clip(window, toStartNoEarlierThan: Curves.date(2026, 6, 15, 13)))
    }

    func testClipShortensAWindowThatIsAlreadyUnderWay() throws {
        let window = Window(start: Curves.date(2026, 6, 15, 9), end: Curves.date(2026, 6, 15, 11))
        let now = Curves.date(2026, 6, 15, 10)
        let clipped = try XCTUnwrap(DoseCalculator.clip(window, toStartNoEarlierThan: now))
        XCTAssertEqual(clipped.start, now)
        XCTAssertEqual(clipped.end, window.end)
        XCTAssertEqual(clipped.minutes, 60, accuracy: 1e-9)
    }

    func testClipLeavesAFutureWindowAlone() throws {
        let window = Window(start: Curves.date(2026, 6, 15, 14), end: Curves.date(2026, 6, 15, 16))
        let clipped = try XCTUnwrap(DoseCalculator.clip(window, toStartNoEarlierThan: Curves.date(2026, 6, 15, 12)))
        XCTAssertEqual(clipped, window)
    }

    func testAWindowIsViableWhenItDeliversHalfTheTarget() throws {
        let curve = try Curves.shoulderHourUVI2()
        let now = Curves.date(2026, 6, 15, 11)
        // Half of 2.25 SED is 75.0 UVI-minutes: 37.5 minutes at UVI 2.
        let full = Window(start: Curves.date(2026, 6, 15, 12), end: Curves.date(2026, 6, 15, 13))
        XCTAssertTrue(DoseCalculator.isViable(curve: curve, window: full, now: now,
                                              targetSED: target, tunables: .current))
    }

    func testAWindowIsNotViableWhenItCannotReachHalfTheTarget() throws {
        let curve = try Curves.shoulderHourUVI2()
        let now = Curves.date(2026, 6, 15, 11)
        let short = Window(start: Curves.date(2026, 6, 15, 12), end: Curves.date(2026, 6, 15, 12, 30))
        XCTAssertFalse(DoseCalculator.isViable(curve: curve, window: short, now: now,
                                               targetSED: target, tunables: .current))
    }

    func testAPassedWindowIsNeverViable() throws {
        let curve = try Curves.beachFlatUVI8()
        let window = Window(start: Curves.date(2026, 6, 15, 9), end: Curves.date(2026, 6, 15, 11))
        XCTAssertFalse(DoseCalculator.isViable(curve: curve, window: window,
                                               now: Curves.date(2026, 6, 15, 13),
                                               targetSED: target, tunables: .current))
    }

    func testTheNextViableWindowStaysInsideTheHorizon() throws {
        let curve = try Curves.ramp()
        let after = Curves.date(2026, 6, 15, 22)
        let next = try XCTUnwrap(DoseCalculator.nextViableWindow(curve: curve, after: after,
                                                                 targetSED: target, tunables: .current))
        XCTAssertGreaterThanOrEqual(next.start, after)
        XCTAssertLessThanOrEqual(next.start, curve.horizonEnd)
        XCTAssertLessThanOrEqual(next.end, curve.horizonEnd)
    }

    func testThereIsNoViableWindowInATenDayWinter() throws {
        let curve = try Curves.winterLow()
        XCTAssertNil(DoseCalculator.nextViableWindow(curve: curve,
                                                     after: Curves.date(2026, 6, 15, 0),
                                                     targetSED: 6.0, tunables: .current))
    }

    func testThereIsNoViableWindowInATenDayLowForecast() throws {
        let curve = try Curves.tenDayLow()
        XCTAssertNil(DoseCalculator.nextViableWindow(curve: curve,
                                                     after: Curves.date(2026, 6, 15, 0),
                                                     targetSED: 6.0, tunables: .current))
    }

    func testAWindowFourHoursAfterSolarNoonIsUVAHeavy() {
        let noon = Curves.date(2026, 6, 15, 12)
        let window = Window(start: Curves.date(2026, 6, 15, 15, 30), end: Curves.date(2026, 6, 15, 16, 30))
        XCTAssertTrue(DoseCalculator.isUVAHeavy(window: window, solarNoon: noon, tunables: .current))
    }

    func testAWindowFourHoursBeforeSolarNoonIsUVAHeavy() {
        let noon = Curves.date(2026, 6, 15, 12)
        let window = Window(start: Curves.date(2026, 6, 15, 7, 30), end: Curves.date(2026, 6, 15, 8, 30))
        XCTAssertTrue(DoseCalculator.isUVAHeavy(window: window, solarNoon: noon, tunables: .current))
    }

    func testAWindowAnHourFromSolarNoonIsNotUVAHeavy() {
        let noon = Curves.date(2026, 6, 15, 12)
        let window = Window(start: Curves.date(2026, 6, 15, 12, 30), end: Curves.date(2026, 6, 15, 13, 30))
        XCTAssertFalse(DoseCalculator.isUVAHeavy(window: window, solarNoon: noon, tunables: .current))
    }
}
