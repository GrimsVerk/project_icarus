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
}
