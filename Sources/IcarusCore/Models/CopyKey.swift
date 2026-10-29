import Foundation

/// Every line of user-facing text the engine can ask for. The engine never
/// renders words: an outcome carries keys, and the content layer resolves them
/// against `docs/APP_COPY.md` (D-2026-09-03-F7).
///
/// THIS LIST IS COMPLETE FOR EVERY PLAN. A later plan that needs a key adds it
/// here and to `docs/APP_COPY.md`, and lists both files.
public enum CopyKey: String, Codable, Sendable, CaseIterable {
    // Outcomes
    case planBareSubWindow
    case planStayWearThis
    case planStayWholeWindowFits
    case tooWeak
    case noViableWindow
    case windowPassed
    case budgetSpent
    case missingForecast
    case missingForecastNoLocation

    // Notices
    case staleHeadsUp
    case staleWarn
    case staleFarFromCache
    case escalationRisen
    case toleranceDropped
    case ceilingReached
    case underDosed
    case maintenance
    case thinMargin
    case fairSkinPreCalibration
    case conservativeUntilCalibrated
    case aggressiveLocked
    case uvaHeavy
    case cloudCaveat
    case coverToRunLonger
    case boundByMelanogenic
    case boundByBurnLine
    case whichSideFirst
    case timerStoppedAtPlannedEnd
    case timerNeedsNotifications
    case timerCannotStart
    case oneSideSpent

    // Warnings
    case warnPastTarget
    case warnReachesThreshold

    // Sunscreen
    case sunscreenNotNeeded
    case sunscreenPrescribed
    case sunscreenApplicationBeatsLabel
    case uvaMultiple
    case reapply
    case nothingRealistic
    case alternativeWholeWindow
    case alternativeThickEnough
    case alternativeShadeForRest
    case didYouWearIt

    // Prompts
    case didYouDoThisSession
    case noSessionToReport
    case immediateDarkeningExplained
    case revisitSkinType
    case pauseSuggested
    case reportRecorded
    case alreadyReported

    // Settings and history
    case sensitivitySentence
    case deleteHistoryWarning
    case trajectoryTitle
    case unreportedDays
    case privacyOptions
    case importApplied
    case importFailed

    // Onboarding
    case onboardingWhyLocation
    case onboardingWhyNotifications
    case disclaimer

    // Tabs (provisional, D-2026-10-29-C1)
    case tabPlan // TAB-1
    case tabLearn // TAB-2

    // Plan screen (the Calculator entry) (provisional, D-2026-10-29-C1)
    case calcSlotHeader // CALC-1
    case calcFrom // CALC-2
    case calcUntil // CALC-3
    case calcPostureLabel // CALC-4
    case postureLyingTurning // CALC-5
    case postureUpAndAbout // CALC-6
    case calcCover // CALC-7
    case calcCoverFootnote // CALC-8
    case calcStay // CALC-9
    case calcStayFootnote // CALC-10
    case calcCompute // CALC-11
    case calcHistory // CALC-12
    case calcSettings // CALC-13

    // Due questions on the Plan screen (provisional, D-2026-10-29-C1)
    case dueSkinCheck // DUE-1
    case dueLastingColour // DUE-2

    // Result screen (provisional, D-2026-10-29-C1)
    case resultTitle // RES-1
    case resultForecastHere // RES-2
    case resultForecastFor // RES-3
    case resultChangePlace // RES-4
    case resultRefresh // RES-5
    case resultDoTheNumber // RES-6
    case resultNoSuchSPF // RES-7
    case resultDidThis // RES-8
    case resultLogged // RES-9
    case resultStartTimer // RES-10

    // Result figures (the numbers' labels) (provisional, D-2026-10-29-C1)
    case figHeadlineMinutes // FIG-1
    case figSideMinutes // FIG-2
    case figSideMinutesFaceUp // FIG-3
    case figSideMinutesFaceDown // FIG-4
    case figRegionDose // FIG-5
    case figRemainingBudget // FIG-6
    case figCycleDose // FIG-7
    case figRangeLower // FIG-8
    case figRangeUpper // FIG-9
    case figRangeUpperClipped // FIG-10
    case figUvaMultiple // FIG-11
    case figShortfall // FIG-12
    case figExtraIfCovered // FIG-13

    // Words filled into approved lines (provisional, D-2026-10-29-C1)
    case regionFront // FILL-1
    case regionBack // FILL-1
    case regionHeadAndShoulders // FILL-1
    case applicationThin // FILL-2
    case applicationNormal // FILL-2
    case applicationThick // FILL-2
    case reasonProvider // FILL-3
    case reasonMalformed // FILL-4
    case reasonCacheUnreadable // FILL-5
    case placeYourLocation // FILL-6
    case effectNone // FILL-7
    case effectTanCredited // FILL-8
    case effectMoreSensitive // FILL-9
    case effectLessSensitive // FILL-10
    case effectDiscounted // FILL-11

    // “I don't have that SPF” sheet (provisional, D-2026-10-29-C1)
    case sunscreenSheetTitle // SUN-1
    case sunscreenSheetSPF // SUN-2
    case sunscreenSheetApplication // SUN-3
    case sunscreenOptionThin // SUN-4
    case sunscreenOptionNormal // SUN-5
    case sunscreenOptionThick // SUN-6
    case sunscreenSheetConfirm // SUN-7

    // Change place sheet (provisional, D-2026-10-29-C1)
    case placeSheetTitle // PLACE-1
    case placeSearchPrompt // PLACE-2
    case placeNotFound // PLACE-3

    // Flip timer (provisional, D-2026-10-29-C1)
    case timerTitle // TIM-1
    case timerSidePicker // TIM-2
    case sideFaceUp // TIM-3
    case sideFaceDown // TIM-4
    case timerStart // TIM-5
    case timerStartWithoutAlerts // TIM-6
    case timerNow // TIM-7
    case timerUntilTurn // TIM-8
    case timerUntilEnd // TIM-9
    case timerLeftInSession // TIM-10
    case timerStop // TIM-11
    case timerStopFootnote // TIM-12

    // Skin check (the day-after questions) (provisional, D-2026-10-29-C1)
    case skinCheckTitle // SKIN-1
    case didYes // DID-1
    case didNo // DID-2
    case woreAsSuggested // DID-3
    case woreDifferent // DID-4
    case woreNone // DID-5
    case promptNext // DID-6
    case timesHeader // DID-7
    case exposureFaceUp // DID-8
    case exposureFaceDown // DID-8
    case exposureUpAndAbout // DID-8
    case intervalFrom // DID-9
    case intervalUntil // DID-9
    case promptSave // DID-10
    case skinQuestionLook // SKIN-2
    case skinAnswerNormal // SKIN-3
    case skinAnswerFaintPink // SKIN-4
    case skinAnswerClearlyPink // SKIN-5
    case skinAnswerRedSore // SKIN-6
    case skinAnswerBlistered // SKIN-7
    case skinQuestionTiming // SKIN-8
    case timingWithinHourGoneByEvening // SKIN-9
    case timingThatEvening // SKIN-10
    case timingNextMorning // SKIN-11
    case timingNotSure // SKIN-12
    case skinQuestionRegion // SKIN-13
    case reportRegionAllExposed // SKIN-14
    case reportRegionFront // SKIN-15
    case reportRegionBack // SKIN-15
    case reportRegionHeadAndShoulders // SKIN-15
    case skinQuestionConfounders // SKIN-16
    case confounderPhotosensitisingMedication // SKIN-17
    case confounderIllness // SKIN-18
    case confounderWaterOrSnow // SKIN-19
    case confounderAltitude // SKIN-20
    case confounderAlcohol // SKIN-21
    case skinSendReport // SKIN-22

    // Lasting colour (provisional, D-2026-10-29-C1)
    case lastingColourTitle // LC-1
    case lastingColourQuestion // LC-2
    case lastingYes // LC-3
    case lastingALittle // LC-3
    case lastingNo // LC-3
    case lastingSaved // LC-4

    // History (provisional, D-2026-10-29-C1)
    case historyTitle // HIST-1
    case historyExport // HIST-2
    case historyImport // HIST-3
    case importWarning // HIST-4
    case importConfirm // HIST-5
    case importCancel // HIST-5
    case historyEmpty // HIST-6
    case historyDayDose // HIST-7
    case historySkinAnswer // HIST-8
    case historySunscreen // HIST-9
    case historyNoSunscreen // HIST-9
    case detailWhatYouDid // HIST-10
    case detailWhatYouWereShown // HIST-10
    case detailTheForecast // HIST-10
    case detailDay // HIST-11
    case detailTime // HIST-11
    case detailPosition // HIST-11
    case detailCovered // HIST-11
    case detailPlan // HIST-11
    case detailSunscreen // HIST-11
    case detailSetting // HIST-11
    case valueYes // HIST-12
    case valueNo // HIST-12
    case intentBestMinutes // HIST-12
    case intentStayWholeWindow // HIST-12
    case ceilingConservative // HIST-12
    case ceilingStandard // HIST-12
    case ceilingAggressive // HIST-12
    case detailTanProtection // HIST-13
    case detailTarget // HIST-13
    case detailReceived // HIST-13
    case detailForecastFor // HIST-14
    case detailForecastFetched // HIST-14
    case detailPeakUVI // HIST-14
    case detailTimeZone // HIST-14

    // Settings (provisional, D-2026-10-29-C1)
    case settingsTitle // SET-1
    case settingsDone // SET-2
    case settingsCeilingHeading // SET-3
    case settingsConservative // SET-4
    case settingsStandard // SET-4
    case settingsAggressive // SET-4
    case settingsCeilingFootnote // SET-5
    case settingsSensitivityHeading // SET-6
    case sensitivityNoReports // SET-7
    case settingsManualValue // SET-8
    case settingsManualFootnote // SET-9
    case settingsResetSensitivity // SET-10
    case unreportedNone // SET-11
    case settingsWeekHeading // SET-12
    case settingsCycleHeading // SET-13
    case settingsDataHeading // SET-14
    case settingsExport // SET-15
    case settingsShare // SET-15
    case settingsImport // SET-15
    case settingsDelete // SET-15
    case deleteConfirm // SET-16
    case deleteCancel // SET-16
    case settingsAboutHeading // SET-17
    case attributionMark // SET-18
    case attributionLink // SET-19
    case privacyPolicyLink // SET-20
    case settingsSkinType // SET-21

    // Onboarding (provisional, D-2026-10-29-C1)
    case onboardingBack // ONB-1
    case onboardingNext // ONB-1
    case onboardingStart // ONB-2
    case onboardingDisclaimerHeading // ONB-3
    case onboardingAcknowledge // ONB-4
    case onboardingSkinTypeHeading // ONB-5
    case onboardingSkinTypeIntro // ONB-6
    case onboardingTakeQuiz // ONB-7
    case quizTitle // QUIZ-1
    case quizDone // QUIZ-2
    case quizResult // QUIZ-3
    case onboardingPermissionsHeading // ONB-8
    case onboardingAllowLocation // ONB-9
    case onboardingAllowNotifications // ONB-10
    case onboardingPermissionsFootnote // ONB-11

    // Learn (provisional, D-2026-10-29-C1)
    case learnTitle // LEARN-1

    // VoiceOver only (S9) (provisional, D-2026-10-29-C1)
    case voEstimate // VO-1
    case assumptionMelanogenicFraction // VO-2
    case assumptionRiseMultiplier // VO-3
    case assumptionAdaptationGain // VO-4
    case assumptionFrontBackFraction // VO-5
    case assumptionShoulderFraction // VO-6
    case assumptionRiseTimeConstantDays // VO-7
    case assumptionDecayHalfLifeDays // VO-8
    case assumptionPlateauTanState // VO-9
    case assumptionTolerantCredit // VO-10
    case assumptionUvaHeavyHoursFromNoon // VO-11
    case assumptionImpliedRatio // VO-12
    case voTimerUntilTurn // VO-13
    case voTimerUntilEnd // VO-13
    case voTimerLeftInSession // VO-13
    case voAdvertisement // VO-14
}
