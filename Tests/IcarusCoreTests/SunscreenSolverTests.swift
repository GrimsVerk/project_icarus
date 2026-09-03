import Foundation
@testable import IcarusCore
import XCTest

// MARK: - Shared fixtures

/// Every window in this file sits on 2026-06-15 in the fixtures' UTC calendar,
/// so no test reads the wall clock (AGENTS.md: the suite is deterministic).
private func window(hours: Double, fromHour hour: Int = 10) -> Window {
    let start = Curves.date(2026, 6, 15, hour)
    return Window(start: start, end: start.addingTimeInterval(hours * 3600))
}

private func outcome(
    rawSED: SED,
    budgetSED: SED,
    window: Window,
    bareMinutes: Double = 30,
    uvaHeavy: Bool = false,
    tunables: Tunables = .current
) -> SunscreenOutcome {
    SunscreenSolver.outcome(rawSED: rawSED, budgetSED: budgetSED, window: window,
                            bareMinutes: bareMinutes, uvaHeavy: uvaHeavy, tunables: tunables)
}

private extension SunscreenOutcome {
    /// The advice a prescription carries, or nil for the other two outcomes.
    var advice: SunscreenAdvice? {
        if case let .prescribe(advice) = self { return advice }
        return nil
    }
}

/// Collects the Tunables keys an outcome read.
private final class KeyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var keys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ key: String) {
        lock.lock()
        storage.append(key)
        lock.unlock()
    }
}

// MARK: - S2: the density curve

/// S2: the label is measured at 2 mg/cm²; what a person actually applies is
/// worth the label raised to density / 2.
final class SunscreenDensityTests: XCTestCase {
    func testTheDensityCurveGivesTheS2Numbers() {
        XCTAssertEqual(SunscreenChoice(spfLabel: 50, application: .thick).effectiveSPF, 50, accuracy: 0.01)
        XCTAssertEqual(SunscreenChoice(spfLabel: 50, application: .normal).effectiveSPF, 7.07, accuracy: 0.01)
        XCTAssertEqual(SunscreenChoice(spfLabel: 50, application: .thin).effectiveSPF, 2.66, accuracy: 0.01)
    }
}

// MARK: - The prescription

/// R15: the engine prescribes the lowest ladder label whose normally-applied
/// effective SPF covers what the whole window needs, and never solves for a
/// thick application.
final class SunscreenSolverOutcomeTests: XCTestCase {
    private let tunables = Tunables.current

    func testNoSunscreenIsNeededWhenTheWindowFitsTheBudget() {
        XCTAssertEqual(outcome(rawSED: 1.5, budgetSED: 2.0, window: window(hours: 3)),
                       .notNeeded(uvaHeavy: false))
    }

    func testNoSunscreenIsNeededWhenTheRawDoseExactlyMeetsTheBudget() {
        XCTAssertEqual(outcome(rawSED: 2.0, budgetSED: 2.0, window: window(hours: 3)),
                       .notNeeded(uvaHeavy: false))
    }

    func testTheNotNeededOutcomeCarriesTheUVAFlagItWasGiven() {
        XCTAssertEqual(outcome(rawSED: 1.0, budgetSED: 2.0, window: window(hours: 3), uvaHeavy: true),
                       .notNeeded(uvaHeavy: true))
    }

    func testAnAttenuationOfFourPrescribesSPFTwentyAppliedNormally() throws {
        let advice = try XCTUnwrap(outcome(rawSED: 8.0, budgetSED: 2.0, window: window(hours: 3)).advice)
        XCTAssertEqual(advice.prescribed, SunscreenChoice(spfLabel: 20, application: .normal))
    }

    func testAnAttenuationOfFivePrescribesSPFThirtyAppliedNormally() throws {
        let advice = try XCTUnwrap(outcome(rawSED: 10.0, budgetSED: 2.0, window: window(hours: 3)).advice)
        XCTAssertEqual(advice.prescribed, SunscreenChoice(spfLabel: 30, application: .normal))
    }

    func testAnAttenuationOfEightIsBeyondAnythingRealistic() {
        XCTAssertEqual(outcome(rawSED: 16.0, budgetSED: 2.0, window: window(hours: 3)),
                       .nothingRealistic(requiredAttenuation: 8))
    }

    func testThePrescriptionIsNeverThick() throws {
        for attenuation in [1.2, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0] {
            let result = outcome(rawSED: attenuation * 2, budgetSED: 2.0, window: window(hours: 3))
            let advice = try XCTUnwrap(result.advice, "no prescription at attenuation \(attenuation)")
            XCTAssertEqual(advice.prescribed.application, .normal, "thick solved at attenuation \(attenuation)")
        }
    }

    func testThePrescribedLabelIsTheLowestOnTheLadderThatCovers() throws {
        let exponent = tunables.densityDefault / 2
        for attenuation in [1.5, 2.0, 3.0, 3.9, 4.5, 5.5, 7.0] {
            let result = outcome(rawSED: attenuation * 2, budgetSED: 2.0, window: window(hours: 3))
            let label = try XCTUnwrap(result.prescribedChoice?.spfLabel, "no label at attenuation \(attenuation)")
            XCTAssertGreaterThanOrEqual(pow(Double(label), exponent), attenuation,
                                        "SPF \(label) does not cover \(attenuation)")
            for lower in tunables.spfLadder where lower < label {
                XCTAssertLessThan(pow(Double(lower), exponent), attenuation,
                                  "SPF \(lower) already covered \(attenuation)")
            }
        }
    }

    func testAModerateLabelAppliedNormallyBeatsAHighOneAppliedThinly() throws {
        let advice = try XCTUnwrap(outcome(rawSED: 10.0, budgetSED: 2.0, window: window(hours: 3)).advice)
        XCTAssertGreaterThanOrEqual(advice.prescribed.effectiveSPF, 5.0)
        XCTAssertLessThan(SunscreenChoice(spfLabel: 50, application: .thin).effectiveSPF, 5.0)
    }

    func testTheAdviceSaysWhyAModerateLabelIsEnough() throws {
        let advice = try XCTUnwrap(outcome(rawSED: 8.0, budgetSED: 2.0, window: window(hours: 3)).advice)
        XCTAssertEqual(advice.whyModerateSPF, .sunscreenApplicationBeatsLabel)
    }

    func testThePrescribedChoiceIsExposedForAPrescription() throws {
        let result = outcome(rawSED: 8.0, budgetSED: 2.0, window: window(hours: 3))
        XCTAssertEqual(result.prescribedChoice, try XCTUnwrap(result.advice).prescribed)
    }

    func testThereIsNoPrescribedChoiceWhenNoSunscreenIsNeeded() {
        XCTAssertNil(outcome(rawSED: 1.0, budgetSED: 2.0, window: window(hours: 3)).prescribedChoice)
    }

    func testThereIsNoPrescribedChoiceWhenNothingIsRealistic() {
        XCTAssertNil(outcome(rawSED: 16.0, budgetSED: 2.0, window: window(hours: 3)).prescribedChoice)
    }

    func testTheSolverReadsTheAppliedDensityFromTunables() {
        let recorder = KeyRecorder()
        let spy = tunables.recording { recorder.record($0) }
        _ = outcome(rawSED: 8.0, budgetSED: 2.0, window: window(hours: 3), tunables: spy)
        XCTAssertTrue(recorder.keys.contains("densityDefault"), "read \(recorder.keys)")
    }
}

// MARK: - The UVA multiple

/// R15: the same tanning dose spread over N times the minutes carries about N
/// times the UVA, and the answer names N.
final class SunscreenUVAMultipleTests: XCTestCase {
    func testTheUVAMultipleIsTheWholeWindowOverTheBareMinutes() throws {
        let advice = try XCTUnwrap(
            outcome(rawSED: 8.0, budgetSED: 2.0, window: window(hours: 3), bareMinutes: 30).advice
        )
        XCTAssertEqual(advice.uvaMultiple, 6.0, accuracy: 1e-9)
    }

    func testTheUVAMultipleIsOneWhenTheBareMinutesAlreadyFillTheWindow() throws {
        let advice = try XCTUnwrap(
            outcome(rawSED: 8.0, budgetSED: 2.0, window: window(hours: 2), bareMinutes: 120).advice
        )
        XCTAssertEqual(advice.uvaMultiple, 1.0, accuracy: 1e-9)
    }
}

// MARK: - Reapplication

/// R15: reapplication times are named when the plan exceeds the interval, and
/// the interval itself is never shortened to make a weak product do.
final class SunscreenReapplicationTests: XCTestCase {
    private let tunables = Tunables.current

    func testAThreeHourWindowIsReappliedOnceAtTwoHours() {
        let span = window(hours: 3)
        XCTAssertEqual(SunscreenSolver.reapplicationTimes(window: span, tunables: tunables),
                       [Curves.date(2026, 6, 15, 12)])
    }

    func testAWindowOfExactlyTwoHoursNeedsNoReapplication() {
        let span = window(hours: 2)
        XCTAssertEqual(SunscreenSolver.reapplicationTimes(window: span, tunables: tunables), [])
    }

    func testAShortWindowNeedsNoReapplication() {
        let span = window(hours: 1)
        XCTAssertEqual(SunscreenSolver.reapplicationTimes(window: span, tunables: tunables), [])
    }

    func testAFiveHourWindowIsReappliedEveryTwoHours() {
        let span = window(hours: 5)
        XCTAssertEqual(SunscreenSolver.reapplicationTimes(window: span, tunables: tunables),
                       [Curves.date(2026, 6, 15, 12), Curves.date(2026, 6, 15, 14)])
    }

    func testTheAdviceCarriesTheTimesWhenTheWindowExceedsTheInterval() throws {
        let span = window(hours: 3)
        let advice = try XCTUnwrap(outcome(rawSED: 8.0, budgetSED: 2.0, window: span).advice)
        XCTAssertEqual(advice.reapplyAt, [Curves.date(2026, 6, 15, 12)])
    }

    func testTheAdviceCarriesNoTimesWhenTheWindowDoesNotExceedTheInterval() throws {
        let span = window(hours: 2)
        let advice = try XCTUnwrap(outcome(rawSED: 8.0, budgetSED: 2.0, window: span).advice)
        XCTAssertEqual(advice.reapplyAt, [])
    }
}

// MARK: - "I don't have that SPF"

/// R15: the re-solve uses exactly what the user said they can manage — thick if
/// that is enough, otherwise covered minutes plus shade — and never offers more
/// frequent application as the fix.
final class SunscreenAlternativeTests: XCTestCase {
    private let tunables = Tunables.current
    private let span = window(hours: 3)

    /// The raw dose of the three-hour window on the flat UVI 8 beach day.
    private func rawSED(_ curve: ForecastCurve) -> SED {
        curve.sed(from: span.start, to: span.end)
    }

    private func plan(have: SunscreenChoice, budgetSED: SED) throws -> AlternativePlan {
        let curve = try Curves.beachFlatUVI8()
        return SunscreenSolver.alternative(have: have, rawSED: rawSED(curve), budgetSED: budgetSED,
                                           window: span, curve: curve, tunables: tunables)
    }

    func testWhatTheyHaveIsKeptWhenItAlreadyCoversTheWholeWindow() throws {
        let result = try plan(have: SunscreenChoice(spfLabel: 50, application: .normal), budgetSED: 4.0)
        XCTAssertEqual(result.with, SunscreenChoice(spfLabel: 50, application: .normal))
        XCTAssertEqual(result.copy, .alternativeWholeWindow)
        XCTAssertEqual(result.coveredWindow, span)
    }

    func testAThickApplicationOfWhatTheyHaveIsUsedWhenItSuffices() throws {
        let result = try plan(have: SunscreenChoice(spfLabel: 30, application: .normal), budgetSED: 3.0)
        XCTAssertEqual(result.with, SunscreenChoice(spfLabel: 30, application: .thick))
        XCTAssertEqual(result.copy, .alternativeThickEnough)
    }

    func testTheThickAlternativeNeedsNoShade() throws {
        let result = try plan(have: SunscreenChoice(spfLabel: 30, application: .normal), budgetSED: 3.0)
        XCTAssertEqual(result.shadeMinutes, 0, accuracy: 1e-9)
        XCTAssertEqual(result.coveredWindow, span)
    }

    func testALabelTooLowBuysCoveredMinutesAndShadeForTheRest() throws {
        let result = try plan(have: SunscreenChoice(spfLabel: 15, application: .normal), budgetSED: 1.0)
        XCTAssertGreaterThan(result.shadeMinutes, 0)
    }

    func testTheShadeAlternativeSaysShadeForTheRest() throws {
        let result = try plan(have: SunscreenChoice(spfLabel: 15, application: .normal), budgetSED: 1.0)
        XCTAssertEqual(result.copy, .alternativeShadeForRest)
    }

    func testTheShadeAlternativeCoversHeadAndShoulders() throws {
        let result = try plan(have: SunscreenChoice(spfLabel: 15, application: .normal), budgetSED: 1.0)
        XCTAssertTrue(result.coverHeadAndShoulders)
    }

    func testTheShadeAlternativeKeepsTheLabelTheUserSaidTheyHave() throws {
        let result = try plan(have: SunscreenChoice(spfLabel: 15, application: .normal), budgetSED: 1.0)
        XCTAssertEqual(result.with.spfLabel, 15)
    }

    func testTheCoveredWindowStartsWhenTheWindowStarts() throws {
        let result = try plan(have: SunscreenChoice(spfLabel: 15, application: .normal), budgetSED: 1.0)
        XCTAssertEqual(result.coveredWindow.start, span.start)
        XCTAssertLessThan(result.coveredWindow.minutes, span.minutes)
    }

    func testTheCoveredMinutesAndTheShadeMinutesFillTheWindow() throws {
        let result = try plan(have: SunscreenChoice(spfLabel: 15, application: .normal), budgetSED: 1.0)
        XCTAssertEqual(result.coveredWindow.minutes + result.shadeMinutes, span.minutes, accuracy: 1e-6)
    }

    func testTheCoveredMinutesStayInsideTheBudget() throws {
        let curve = try Curves.beachFlatUVI8()
        let result = try plan(have: SunscreenChoice(spfLabel: 15, application: .normal), budgetSED: 1.0)
        let covered = curve.sed(from: result.coveredWindow.start, to: result.coveredWindow.end)
        XCTAssertLessThanOrEqual(covered / result.with.effectiveSPF, 1.0 + 1e-6)
    }

    func testTheAlternativeNeverReappliesMoreOftenThanTheInterval() throws {
        let result = try plan(have: SunscreenChoice(spfLabel: 15, application: .normal), budgetSED: 1.0)
        let interval = tunables.reapplicationIntervalHours * 3600
        var previous = result.coveredWindow.start
        for time in result.reapplyAt {
            XCTAssertGreaterThanOrEqual(time.timeIntervalSince(previous), interval - 1e-6,
                                        "reapplication at \(time) comes too soon after \(previous)")
            previous = time
        }
    }
}

// MARK: - The honest answer

/// R15: more frequent application is never offered as a substitute for a higher
/// SPF, so no copy key can even say it.
final class SunscreenCopyKeyTests: XCTestCase {
    func testNoCopyKeyOffersMoreFrequentApplication() {
        for key in CopyKey.allCases {
            let name = key.rawValue.lowercased()
            XCTAssertFalse(name.contains("moreoften"), "\(key.rawValue) offers more frequent application")
            XCTAssertFalse(name.contains("reapplymore"), "\(key.rawValue) offers more frequent application")
        }
    }
}
