import Foundation
@testable import IcarusCore
import XCTest

/// Collects the keys a recording `Tunables` reports, in the order they were read.
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

/// R30: every engine constant lives in one file and carries a citation or an
/// `assumption` note. These are the documented values; changing one is a
/// decision, and this test is where that decision has to be made deliberately.
final class TunablesValueTests: XCTestCase {
    private let tunables = Tunables.current

    func testTheVersionIsStamped() {
        XCTAssertFalse(tunables.version.isEmpty)
    }

    func testDoseConstantsAreTheModuleFourFigures() {
        XCTAssertEqual(tunables.uviMinutesPerSED, 66.7, accuracy: 1e-9)
        XCTAssertEqual(tunables.uncertaintyBandAtZero, 0.30, accuracy: 1e-9)
    }

    func testMEDBaselinesAreTheBuildPromptSet() {
        XCTAssertEqual(tunables.medBaselineSED(.i), 2.0, accuracy: 1e-9)
        XCTAssertEqual(tunables.medBaselineSED(.ii), 2.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.medBaselineSED(.iii), 3.0, accuracy: 1e-9)
        XCTAssertEqual(tunables.medBaselineSED(.iv), 4.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.medBaselineSED(.v), 6.0, accuracy: 1e-9)
        XCTAssertEqual(tunables.medBaselineSED(.vi), 10.0, accuracy: 1e-9)
    }

    func testSkinTypesFallIntoTheThreeBands() {
        XCTAssertEqual(SkinType.i.band, .fair)
        XCTAssertEqual(SkinType.ii.band, .fair)
        XCTAssertEqual(SkinType.iii.band, .medium)
        XCTAssertEqual(SkinType.iv.band, .dark)
        XCTAssertEqual(SkinType.v.band, .dark)
        XCTAssertEqual(SkinType.vi.band, .dark)
    }

    func testTargetConstantsMatchRequirementSix() {
        XCTAssertEqual(tunables.melanogenicFraction(.fair), 1.0, accuracy: 1e-9)
        XCTAssertEqual(tunables.melanogenicFraction(.medium), 0.95, accuracy: 1e-9)
        XCTAssertEqual(tunables.melanogenicFraction(.dark), 0.75, accuracy: 1e-9)
        XCTAssertEqual(tunables.ceilingScale(.conservative), 0.75, accuracy: 1e-9)
        XCTAssertEqual(tunables.ceilingScale(.standard), 0.90, accuracy: 1e-9)
        XCTAssertEqual(tunables.ceilingScale(.aggressive), 1.0, accuracy: 1e-9)
        XCTAssertEqual(tunables.calibrationReports, 3)
        XCTAssertEqual(tunables.aggressiveUnlockReports, 5)
    }

    func testNoCeilingScaleEverExceedsTheLine() {
        for ceiling in Ceiling.allCases {
            XCTAssertLessThanOrEqual(tunables.ceilingScale(ceiling), 1.0)
            XCTAssertGreaterThan(tunables.ceilingScale(ceiling), 0)
        }
    }

    func testPostureFractionsAreTheGeometryAssumptions() {
        XCTAssertEqual(tunables.frontBackFraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.shoulderFraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.sideDifferenceForTwoFigures, 0.15, accuracy: 1e-9)
    }

    func testAdaptationConstantsAreTheSolvedPair() {
        XCTAssertEqual(tunables.riseTimeConstantDays, 7.2, accuracy: 1e-9)
        XCTAssertEqual(tunables.decayHalfLifeDays, 21.0, accuracy: 1e-9)
        XCTAssertEqual(tunables.plateauTanState, 0.75, accuracy: 1e-9)
        XCTAssertEqual(tunables.tolerantCredit, 0.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.escalationNoticeFraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.gapDays, 14, accuracy: 1e-9)
        XCTAssertEqual(tunables.ceilingNoColourCount, 3)
        XCTAssertEqual(tunables.maintenanceFraction, 0.7, accuracy: 1e-9)
        XCTAssertEqual(tunables.lastingColourRegionFraction, 0.5, accuracy: 1e-9)
    }

    func testAdaptationTablesRiseFasterForDarkerSkin() {
        XCTAssertEqual(tunables.riseMultiplier(.fair), 1.0, accuracy: 1e-9)
        XCTAssertEqual(tunables.riseMultiplier(.medium), 1.0, accuracy: 1e-9)
        XCTAssertEqual(tunables.riseMultiplier(.dark), 1.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.adaptationGain(.fair), 1.25, accuracy: 1e-9)
        XCTAssertEqual(tunables.adaptationGain(.medium), 1.25, accuracy: 1e-9)
        XCTAssertEqual(tunables.adaptationGain(.dark), 2.0, accuracy: 1e-9)
    }

    func testCalibrationConstantsMatchRequirementTwentyOne() {
        XCTAssertEqual(tunables.k, 2.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.nCap, 20)
        XCTAssertEqual(tunables.burnWeight, 2.0, accuracy: 1e-9)
        XCTAssertEqual(tunables.multiplierClamp, 0.5 ... 1.8)
        XCTAssertEqual(tunables.confoundedDiscount, 0.25, accuracy: 1e-9)
        XCTAssertEqual(tunables.blisterProtectiveFactor, 0.8, accuracy: 1e-9)
        XCTAssertEqual(tunables.blisterPauseDays, 4)
    }

    func testSunscreenConstantsMatchRequirementFifteen() {
        XCTAssertEqual(tunables.densityDefault, 1.0, accuracy: 1e-9)
        XCTAssertEqual(tunables.spfLadder, [15, 20, 30, 50])
        XCTAssertEqual(tunables.realisticMaxSPF, 50)
        XCTAssertEqual(tunables.reapplicationIntervalHours, 2, accuracy: 1e-9)
    }

    func testStalenessAndHorizonConstantsMatchRequirementsThreeAndSeventeen() {
        XCTAssertEqual(tunables.staleHeadsUpHours, 3, accuracy: 1e-9)
        XCTAssertEqual(tunables.staleWarnHours, 6, accuracy: 1e-9)
        XCTAssertEqual(tunables.staleRangeWiden, 1.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.staleReduction, 0.05, accuracy: 1e-9)
        XCTAssertEqual(tunables.staleDistanceKm, 25, accuracy: 1e-9)
        XCTAssertEqual(tunables.fetchMinIntervalHours, 1, accuracy: 1e-9)
        XCTAssertEqual(tunables.fetchMoveKm, 10, accuracy: 1e-9)
        XCTAssertEqual(tunables.forecastHorizonDays, 10)
        XCTAssertEqual(tunables.viabilityFraction, 0.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.uvaHeavyHoursFromNoon, 3, accuracy: 1e-9)
    }

    func testPromptDelaysMatchRequirementTwenty() {
        XCTAssertEqual(tunables.skinCheckDelayHours, 20, accuracy: 1e-9)
        XCTAssertEqual(tunables.lastingColourDelayDays, 4, accuracy: 1e-9)
        XCTAssertEqual(tunables.inAppSkinCheckWindowHours, 12 ... 72)
        XCTAssertEqual(tunables.inAppLastingColourWindowDays, 3 ... 10)
    }
}

/// The S3 reporter model and its inverse: the implied-ratio table and the
/// bands that turn a true dose-to-threshold ratio back into an answer.
final class TunablesReporterTests: XCTestCase {
    private let tunables = Tunables.current

    func testTheImpliedRatioTableIsTheBuildPromptShape() {
        XCTAssertEqual(tunables.impliedRatio(.faintPink), 1.0, accuracy: 1e-9)
        XCTAssertEqual(tunables.impliedRatio(.clearlyPink), 1.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.impliedRatio(.redSore), 2.5, accuracy: 1e-9)
        XCTAssertEqual(tunables.impliedRatio(.blistered), 4.0, accuracy: 1e-9)
    }

    func testTheReporterBandEdgesAreTheFixture() {
        XCTAssertEqual(tunables.reporterBandEdges, [0.95, 1.15, 2.0, 4.0])
    }

    func testTheReporterAnswersOnTheBandEdges() {
        XCTAssertEqual(tunables.reporterAnswer(ratio: 0.9499), .normal)
        XCTAssertEqual(tunables.reporterAnswer(ratio: 0.95), .faintPink)
        XCTAssertEqual(tunables.reporterAnswer(ratio: 1.15), .clearlyPink)
        XCTAssertEqual(tunables.reporterAnswer(ratio: 2.0), .redSore)
        XCTAssertEqual(tunables.reporterAnswer(ratio: 4.0), .blistered)
    }

    func testTheReporterAnswersInsideEachBand() {
        XCTAssertEqual(tunables.reporterAnswer(ratio: 0.4), .normal)
        XCTAssertEqual(tunables.reporterAnswer(ratio: 1.0), .faintPink)
        XCTAssertEqual(tunables.reporterAnswer(ratio: 1.6), .clearlyPink)
        XCTAssertEqual(tunables.reporterAnswer(ratio: 3.0), .redSore)
        XCTAssertEqual(tunables.reporterAnswer(ratio: 9.0), .blistered)
    }
}

/// R30 again: provenance is per stored number, and every read reports the key
/// it read, so an outcome's declared constant set can be checked against what
/// its figures actually observed.
final class TunablesProvenanceTests: XCTestCase {
    func testReadingThreeAccessorsReportsExactlyThoseThreeKeys() {
        let recorder = KeyRecorder()
        let spy = Tunables.current.recording { recorder.record($0) }
        _ = spy.uviMinutesPerSED
        _ = spy.nCap
        _ = spy.burnWeight
        XCTAssertEqual(recorder.keys, ["uviMinutesPerSED", "nCap", "burnWeight"])
    }

    func testARecordingCopyReportsWithoutChangingAnyValue() {
        let recorder = KeyRecorder()
        let spy = Tunables.current.recording { recorder.record($0) }
        XCTAssertEqual(spy.uviMinutesPerSED, Tunables.current.uviMinutesPerSED, accuracy: 1e-12)
        XCTAssertEqual(spy.spfLadder, Tunables.current.spfLadder)
        XCTAssertFalse(recorder.keys.isEmpty)
    }

    func testEveryKeyAReadReportsHasAProvenanceEntry() {
        let recorder = KeyRecorder()
        let spy = Tunables.current.recording { recorder.record($0) }
        Self.readScalars(spy)
        Self.readMoreScalars(spy)
        Self.readTables(spy)
        XCTAssertGreaterThan(recorder.keys.count, 40)
        for key in Set(recorder.keys) {
            XCTAssertNotNil(Tunables.provenance[key], "no provenance entry for \(key)")
        }
    }

    func testAssumptionKeysAreExactlyTheKeysWhoseBasisIsAnAssumption() {
        let assumed = Tunables.provenance.compactMap { key, basis -> String? in
            if case .assumption = basis {
                return key
            }
            return nil
        }
        XCTAssertFalse(assumed.isEmpty)
        XCTAssertEqual(Tunables.assumptionKeys, Set(assumed))
    }

    func testTheDarkAdaptationGainIsAnAssumptionAndTheFairOneIsNot() {
        XCTAssertTrue(Tunables.assumptionKeys.contains("adaptationGain.dark"))
        XCTAssertFalse(Tunables.assumptionKeys.contains("adaptationGain.fair"))
    }

    func testEveryBasisCarriesANonEmptyReason() {
        XCTAssertFalse(Tunables.provenance.isEmpty)
        for (key, basis) in Tunables.provenance {
            switch basis {
            case let .citation(text), let .assumption(text):
                XCTAssertFalse(text.isEmpty, "empty basis for \(key)")
            }
        }
    }

    private static func readScalars(_ tunables: Tunables) {
        _ = tunables.uviMinutesPerSED
        _ = tunables.calibrationReports
        _ = tunables.aggressiveUnlockReports
        _ = tunables.uncertaintyBandAtZero
        _ = tunables.frontBackFraction
        _ = tunables.shoulderFraction
        _ = tunables.sideDifferenceForTwoFigures
        _ = tunables.riseTimeConstantDays
        _ = tunables.decayHalfLifeDays
        _ = tunables.plateauTanState
        _ = tunables.tolerantCredit
        _ = tunables.escalationNoticeFraction
        _ = tunables.gapDays
        _ = tunables.ceilingNoColourCount
        _ = tunables.maintenanceFraction
        _ = tunables.lastingColourRegionFraction
        _ = tunables.reporterBandEdges
        _ = tunables.k
        _ = tunables.nCap
        _ = tunables.burnWeight
        _ = tunables.multiplierClamp
    }

    private static func readMoreScalars(_ tunables: Tunables) {
        _ = tunables.confoundedDiscount
        _ = tunables.blisterProtectiveFactor
        _ = tunables.blisterPauseDays
        _ = tunables.densityDefault
        _ = tunables.spfLadder
        _ = tunables.realisticMaxSPF
        _ = tunables.reapplicationIntervalHours
        _ = tunables.staleHeadsUpHours
        _ = tunables.staleWarnHours
        _ = tunables.staleRangeWiden
        _ = tunables.staleReduction
        _ = tunables.staleDistanceKm
        _ = tunables.fetchMinIntervalHours
        _ = tunables.fetchMoveKm
        _ = tunables.forecastHorizonDays
        _ = tunables.viabilityFraction
        _ = tunables.uvaHeavyHoursFromNoon
        _ = tunables.skinCheckDelayHours
        _ = tunables.lastingColourDelayDays
        _ = tunables.inAppSkinCheckWindowHours
        _ = tunables.inAppLastingColourWindowDays
    }

    private static func readTables(_ tunables: Tunables) {
        for type in SkinType.allCases {
            _ = tunables.medBaselineSED(type)
        }
        for band in SkinBand.allCases {
            _ = tunables.melanogenicFraction(band)
            _ = tunables.riseMultiplier(band)
            _ = tunables.adaptationGain(band)
        }
        for ceiling in Ceiling.allCases {
            _ = tunables.ceilingScale(ceiling)
        }
        for answer in [SkinAnswer.faintPink, .clearlyPink, .redSore, .blistered] {
            _ = tunables.impliedRatio(answer)
        }
    }
}
