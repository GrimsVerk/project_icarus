#if canImport(SwiftUI)
    import Foundation
    import IcarusContent
    import IcarusCore

    /// The words for the engine's own values, from `docs/APP_COPY.md` (R42).
    ///
    /// Every case of an enum the screens show has a line of its own, and this
    /// is the one place that says which. The ids in the comments are the
    /// lines' ids in the document (D-2026-10-29-C1), which is how the owner
    /// names them.
    enum CopyWords {
        /// FILL-1, lower case: a region inside a sentence.
        static func region(_ region: Region) -> String {
            switch region {
            case .front: AppCopy.text(.regionFront)
            case .back: AppCopy.text(.regionBack)
            case .headAndShoulders: AppCopy.text(.regionHeadAndShoulders)
            }
        }

        /// FILL-2: the word after "applied".
        static func application(_ application: Application) -> String {
            switch application {
            case .thin: AppCopy.text(.applicationThin)
            case .normal: AppCopy.text(.applicationNormal)
            case .thick: AppCopy.text(.applicationThick)
            }
        }

        /// SUN-4 to SUN-6: an application as a picker option.
        static func applicationOption(_ application: Application) -> String {
            switch application {
            case .thin: AppCopy.text(.sunscreenOptionThin)
            case .normal: AppCopy.text(.sunscreenOptionNormal)
            case .thick: AppCopy.text(.sunscreenOptionThick)
            }
        }

        /// CALC-5, CALC-6.
        static func posture(_ posture: Posture) -> String {
            switch posture {
            case .lyingTurning: AppCopy.text(.postureLyingTurning)
            case .upAndAbout: AppCopy.text(.postureUpAndAbout)
            }
        }

        /// TIM-3, TIM-4.
        static func side(_ side: Side) -> String {
            switch side {
            case .faceUp: AppCopy.text(.sideFaceUp)
            case .faceDown: AppCopy.text(.sideFaceDown)
            }
        }

        /// DID-8: one stretch of a session.
        static func exposure(_ exposure: Exposure) -> String {
            switch exposure {
            case .lying(.faceUp): AppCopy.text(.exposureFaceUp)
            case .lying(.faceDown): AppCopy.text(.exposureFaceDown)
            case .upAndAbout: AppCopy.text(.exposureUpAndAbout)
            }
        }

        /// SKIN-3 to SKIN-7.
        static func answer(_ answer: SkinAnswer) -> String {
            switch answer {
            case .normal: AppCopy.text(.skinAnswerNormal)
            case .faintPink: AppCopy.text(.skinAnswerFaintPink)
            case .clearlyPink: AppCopy.text(.skinAnswerClearlyPink)
            case .redSore: AppCopy.text(.skinAnswerRedSore)
            case .blistered: AppCopy.text(.skinAnswerBlistered)
            }
        }

        /// SKIN-9 to SKIN-12.
        static func timing(_ timing: RednessTiming) -> String {
            switch timing {
            case .withinHourGoneByEvening: AppCopy.text(.timingWithinHourGoneByEvening)
            case .thatEvening: AppCopy.text(.timingThatEvening)
            case .nextMorning: AppCopy.text(.timingNextMorning)
            case .notSure: AppCopy.text(.timingNotSure)
            }
        }

        /// SKIN-14, SKIN-15.
        static func reportRegion(_ region: ReportRegion) -> String {
            switch region {
            case .allExposed: AppCopy.text(.reportRegionAllExposed)
            case .front: AppCopy.text(.reportRegionFront)
            case .back: AppCopy.text(.reportRegionBack)
            case .headAndShoulders: AppCopy.text(.reportRegionHeadAndShoulders)
            }
        }

        /// SKIN-17 to SKIN-21.
        static func confounder(_ confounder: Confounder) -> String {
            switch confounder {
            case .photosensitisingMedication: AppCopy.text(.confounderPhotosensitisingMedication)
            case .illness: AppCopy.text(.confounderIllness)
            case .waterOrSnow: AppCopy.text(.confounderWaterOrSnow)
            case .altitude: AppCopy.text(.confounderAltitude)
            case .alcohol: AppCopy.text(.confounderAlcohol)
            }
        }

        /// LC-3.
        static func lastingColour(_ answer: LastingColour) -> String {
            switch answer {
            case .yes: AppCopy.text(.lastingYes)
            case .aLittle: AppCopy.text(.lastingALittle)
            case .no: AppCopy.text(.lastingNo)
            }
        }

        /// FILL-3 to FILL-5: `{reason}` in `missingForecast`. A missing
        /// location has a line of its own with no reason in it.
        static func reason(_ kind: ForecastFailureKind?) -> String {
            switch kind {
            case .provider: AppCopy.text(.reasonProvider)
            case .malformed: AppCopy.text(.reasonMalformed)
            case .cacheUnreadable: AppCopy.text(.reasonCacheUnreadable)
            case .noLocation, nil: ""
            }
        }

        /// HIST-12: the plan a session was made for.
        static func intent(_ intent: Intent) -> String {
            switch intent {
            case .bestMinutes: AppCopy.text(.intentBestMinutes)
            case .stayWholeWindow: AppCopy.text(.intentStayWholeWindow)
            }
        }

        /// HIST-12: the setting a session was planned at.
        static func recordedCeiling(_ ceiling: Ceiling) -> String {
            switch ceiling {
            case .conservative: AppCopy.text(.ceilingConservative)
            case .standard: AppCopy.text(.ceilingStandard)
            case .aggressive: AppCopy.text(.ceilingAggressive)
            }
        }

        /// SET-4: the setting as a selector option.
        static func ceiling(_ ceiling: Ceiling) -> String {
            switch ceiling {
            case .conservative: AppCopy.text(.settingsConservative)
            case .standard: AppCopy.text(.settingsStandard)
            case .aggressive: AppCopy.text(.settingsAggressive)
            }
        }

        /// HIST-12.
        static func yesNo(_ value: Bool) -> String {
            AppCopy.text(value ? .valueYes : .valueNo)
        }

        /// `{type}` in SET-21 and QUIZ-3: the type's roman numeral, which is
        /// how the skin-type table names it ("Type III").
        static func roman(_ type: SkinType) -> String {
            switch type {
            case .i: "I"
            case .ii: "II"
            case .iii: "III"
            case .iv: "IV"
            case .v: "V"
            case .vi: "VI"
            }
        }

        /// VO-1: what the estimate badge reads, naming each assumption by its
        /// line (VO-2 to VO-12). A constant the document has no line for is
        /// read by its key, which is data, rather than dropped.
        static func estimate(_ assumptionKeys: [String]) -> String {
            var named: [String] = []
            for key in assumptionKeys {
                let family = String(key.prefix { $0 != "." })
                let words = assumptionLines[family].map { AppCopy.text($0) } ?? key
                if !named.contains(words) {
                    named.append(words)
                }
            }
            return AppCopy.text(.voEstimate, args: ["assumptions": named.joined(separator: ", ")])
        }

        /// The line for each `Tunables` key family, without its band or
        /// answer suffix.
        private static let assumptionLines: [String: CopyKey] = [
            "melanogenicFraction": .assumptionMelanogenicFraction,
            "riseMultiplier": .assumptionRiseMultiplier,
            "adaptationGain": .assumptionAdaptationGain,
            "frontBackFraction": .assumptionFrontBackFraction,
            "shoulderFraction": .assumptionShoulderFraction,
            "riseTimeConstantDays": .assumptionRiseTimeConstantDays,
            "decayHalfLifeDays": .assumptionDecayHalfLifeDays,
            "plateauTanState": .assumptionPlateauTanState,
            "tolerantCredit": .assumptionTolerantCredit,
            "uvaHeavyHoursFromNoon": .assumptionUvaHeavyHoursFromNoon,
            "impliedRatio": .assumptionImpliedRatio,
        ]
    }
#endif
