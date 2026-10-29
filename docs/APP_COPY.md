# App copy — project_icarus

Every non-Learn string the app shows, keyed by `CopyKey` (R42). The owner
approves every line here (S17). `scripts/build-app-copy.sh` (M3) turns this
file into `Sources/IcarusContent/Resources/app-copy.json`; views never hold a
literal. Learn text is not here: it lives in `docs/LEARN_CONTENT.md` and is
rendered verbatim (V5).

Two kinds of line (D-2026-10-29-C1). The lines with no `- id:` were approved
one by one in 2026-09. The lines with an id came from the 2026-10-29 copy
draft and are **provisional**: the owner OK'd them all so they can be judged in
the app, and they stay work in progress until the owner settles each one. The
ids (`CALC-9`, `FILL-2`, …) are how the owner and agents refer to a line; never
renumber or reuse one. A line the owner changes keeps its id. The owner's
readable list is regenerated from this file by `scripts/copy-review.py`.

Format, read by the build script:

- One `### <CopyKey>` heading per key, spelled exactly as the enum case.
- Under it, `- base:` is the text for every skin type. An optional `- fair:`
  line replaces it for types I and II.
- Provisional lines also carry `- id:`, `- where:` (where it shows),
  `- why:` (the draft's reason, when it gave one) and `- status:`. The build
  script ignores them. One id with several values (`FILL-1`: front · back ·
  head and shoulders) is one key per value, each with the same id.
- Values the engine fills in are written in `{braces}`. The argument names
  are part of the contract: `{minutes}`, `{sideMinutes}`, `{frontMinutes}`,
  `{backMinutes}`, `{region}`, `{hours}`, `{place}`, `{days}`, `{peakUVI}`,
  `{shortfall}`, `{nextDay}`, `{nextHour}`, `{spf}`, `{application}`,
  `{multiple}`, `{times}`, `{percent}`, `{count}`, `{cycleDose}`,
  `{coveredMinutes}`, `{sed}`, `{window}`, `{pauseDays}`, `{reason}`,
  `{direction}`, `{reports}`, `{effect}`, `{day}`, `{side}`, `{seconds}`,
  `{answer}`, `{value}`, `{type}`, `{assumptions}`.
- A Learn link is written as `[Module N]`; the view turns it into the deep
  link `icarus://learn/N`.
- The skin-type table and the quiz are the two non-keyed sections at the end.

Tone (R36, V10, V13): frank, plain, never "safe", never a lecture. Estimates
are estimates. Numbers are what the user is told to do; ranges say how sure
the app is.

## Outcomes

### planBareSubWindow
- base: Best {minutes} minutes, no sunscreen. Your slot is longer than your skin needs today, so these are the minutes to take.

### planStayWearThis
- base: To stay the whole {window}, wear {spf}, applied {application}. The bare-skin alternative is below.

### planStayWholeWindowFits
- base: The whole {window} fits under today's budget. Stay for all of it, no sunscreen needed for the tan.

### tooWeak
- base: This slot will not build lasting colour. It delivers {shortfall} SED less than your skin needs for new pigment. The next slot that can is {nextDay} around {nextHour}.

### noViableWindow
- base: No slot in the next {days} days reaches a useful dose. The highest UV index in the forecast is {peakUVI}. This app does not guess past its forecast.

### windowPassed
- base: That slot has already passed. Enter a slot that ends after now.

### budgetSpent
- base: Today's budget for your {region} is used up. More sun today buys damage, not colour. Tomorrow starts a fresh budget.

### missingForecast
- base: No forecast is available, so there is no number to show. Reason: {reason}. Refresh, or check the place the forecast is for.

### missingForecastNoLocation
- base: The app does not know where you are, and there is no saved forecast. Allow location, or enter a place.

## Notices

### staleHeadsUp
- base: Forecast fetched {hours} hours ago for {place}.

### staleWarn
- base: The forecast is {hours} hours old and may be outdated. The number is shorter and the range wider until it is refreshed.

### staleFarFromCache
- base: The saved forecast is for {place}, which is not where you are. The number is shorter and the range wider until you refresh or change the place.

### escalationRisen
- base: Your threshold has risen since this tan cycle began. A fixed dose would no longer trigger new pigment, so today's dose is larger. Cycle dose so far: {cycleDose} SED. [Module 6]

### toleranceDropped
- base: Your tolerance has dropped by about {percent}% since your last session. Today's dose is smaller than the last one you did. [Module 6]

### ceilingReached
- base: The last {count} lasting-colour answers were "no" near modelled saturation, and this cycle has shown a redness report. You have likely reached your skin's maximum. More dose buys damage without colour. The dose drops to maintenance.

### underDosed
- base: The last {count} lasting-colour answers were "no" near modelled saturation, but this cycle has shown no redness, so the app cannot tell whether the dose is too low or your skin is done. At this tan state a maintenance dose keeps what you have.

### maintenance
- base: Maintenance dose: {percent}% of your usual target. It changes back after a "yes" or "a little" to the lasting-colour question.

### thinMargin
- base: For your skin type the dose that tans and the dose that turns skin red are close together. Deciding a tan is not worth it is a reasonable conclusion. This app will not push you either way. [Module 5]

### fairSkinPreCalibration
- base: The first sessions are set below the dose that reliably tans fair skin, on purpose, so that a first redness report arrives at a low dose.

### conservativeUntilCalibrated
- base: Shorter until the app has learned your skin. It uses the conservative setting until you have sent {count} skin reports.

### aggressiveLocked
- base: Aggressive unlocks after {count} skin reports with at least one redness report in the current tan cycle. The app needs to have seen where your line is.

### uvaHeavy
- base: This slot is far from solar noon. The light is UVA-heavy: more ageing per unit of lasting colour. [Module 3]

### cloudCaveat
- base: The forecast already includes expected cloud. Real conditions vary, and thin cloud passes most UV.

### coverToRunLonger
- base: With a hat or shirt on head and shoulders, each side could run {minutes} minutes longer.

### boundByMelanogenic
- base: Today's target is your tanning dose, which sits below your redness line. [Module 5]

### boundByBurnLine
- base: Today's target is set by your redness line. For your skin type the tanning dose is at that line, not below it. [Module 5]

### whichSideFirst
- base: Which side is up first?

### timerStoppedAtPlannedEnd
- base: The timer was still running at midnight. The session was stopped at its planned end.

### timerNeedsNotifications
- base: Notifications are off, so the timer cannot alert you with the screen locked. Turn them on in Settings, or keep the screen on.

### timerCannotStart
- base: The timer cannot start: there is no session to run. {reason}

### oneSideSpent
- base: Your {region} has no budget left today, so that side gets no minutes. The other side is solved on its own.

## Warnings

### warnPastTarget
- base: Staying the whole {window} takes your {region} past today's target, to {sed} SED. Expect more damage than colour.

### warnReachesThreshold
- base: Staying the whole {window} reaches your {region}'s redness threshold, {sed} SED. Expect redness the next day: this is the dose at which skin cells die and the inflammation Module 7 describes begins. [Module 7]

## Sunscreen

### sunscreenNotNeeded
- base: No sunscreen is needed for the tanning goal in these minutes. You may still wear it; then the tan takes longer.

### sunscreenPrescribed
- base: Wear {spf}, applied {application}. That covers every exposed region for the whole {window}.

### sunscreenApplicationBeatsLabel
- base: How much you apply matters more than the number on the bottle: half the amount gives about the square root of the label. A moderate SPF applied properly beats a high SPF applied thinly. [Module 8]

### uvaMultiple
- base: The same tanning dose spread over {multiple} times the minutes carries about {multiple} times the UVA. Sunscreen filters UVB more than UVA unless it carries a UVA rating. [Module 3] [Module 8]

### reapply
- base: Reapply at {times}.

### nothingRealistic
- base: No realistic product covers this slot. Even SPF 50 applied normally is not enough. Shorten the slot instead.

### alternativeWholeWindow
- base: {spf} applied {application} covers the whole {window}.

### alternativeThickEnough
- base: {spf} is enough if you apply it thickly: about a shot glass for the whole body. Applied normally it is not.

### alternativeShadeForRest
- base: {spf} applied {application} covers the first {coveredMinutes} minutes. Shade for the rest of the {window}, and cover head and shoulders.

### didYouWearIt
- base: Did you wear {spf}, applied {application}?

## Prompts

### didYouDoThisSession
- base: Did you do this session? {window}

### noSessionToReport
- base: No session was logged for this day, so there is nothing to report. Nothing was recorded.

### immediateDarkeningExplained
- base: Redness that shows within an hour and is gone by evening is immediate darkening, not a burn. The report was counted as "normal". [Module 2]

### revisitSkinType
- base: Your reports put your sensitivity outside the range for your skin type. Check your skin type in Settings.

### pauseSuggested
- base: Blistering means the dose was far past your line. The estimate was corrected at once. Pause for {pauseDays} days and let the skin recover. [Module 7]

### reportRecorded
- base: Report saved. {effect}

### alreadyReported
- base: This day already has a skin report. One report per day is all the app uses.

## Settings and History

### sensitivitySentence
- base: {percent}% {direction} sensitive than typical for your skin type, based on {count} skin reports.

### deleteHistoryWarning
- base: Deleting the history starts the app over from your skin-type prior. Calibration, tan state, today's budget and History are all lost. Export first if you want to keep them.

### trajectoryTitle
- base: Dose per tan cycle, in SED. This is a record of dose, not a measurement of colour.

### unreportedDays
- base: {count} session days have no skin report.

### privacyOptions
- base: Privacy options for the ad banner.

### importApplied
- base: Import complete: {count} sessions and {reports} reports. The file's profile was applied.

### importFailed
- base: The file could not be read. Nothing was changed.

## Onboarding

### onboardingWhyLocation
- base: Location is used for one thing: fetching the UV forecast for where you are. It never leaves the phone except in that request.

### onboardingWhyNotifications
- base: Notifications carry the day-after skin check, the lasting-colour question and the flip-timer alerts. Without them the same questions wait for the next launch, and the timer cannot alert with the screen locked.

### disclaimer
- base: This app is not medical advice and does not diagnose or treat anything. It estimates a dose from a forecast and from what you report; the estimate can be wrong. Any tan is a sign of skin damage, and there is no dose of ultraviolet light that is known to be free of risk. If you have a skin condition, take medication that affects sun sensitivity, or are unsure, ask a doctor. Sunbeds are outside this app's scope and are not recommended.

## Tabs

### tabPlan
- id: TAB-1
- where: Tab bar, first tab (sun icon)
- base: Plan
- why: The tab is where you plan today's slot. “Calculator” is the code's word, not the user's.
- status: provisional (owner OK 2026-10-29, work in progress)

### tabLearn
- id: TAB-2
- where: Tab bar, second tab (book icon)
- base: Learn
- status: provisional (owner OK 2026-10-29, work in progress)

## Plan screen (the Calculator entry)

### calcSlotHeader
- id: CALC-1
- where: Header above the two times
- base: Your slot today
- why: A slot is always today (R17); saying so stops people entering tomorrow.
- status: provisional (owner OK 2026-10-29, work in progress)

### calcFrom
- id: CALC-2
- where: Start-time row (sun icon)
- base: From
- status: provisional (owner OK 2026-10-29, work in progress)

### calcUntil
- id: CALC-3
- where: End-time row (clock icon)
- base: Until
- status: provisional (owner OK 2026-10-29, work in progress)

### calcPostureLabel
- id: CALC-4
- where: Posture row label (walking-figure icon)
- base: You'll be
- why: Reads as a sentence with the chosen option beside it: “You'll be — Up and about”.
- status: provisional (owner OK 2026-10-29, work in progress)

### postureLyingTurning
- id: CALC-5
- where: Posture option (lyingTurning)
- base: Lying down, turning over
- why: R9's own words.
- status: provisional (owner OK 2026-10-29, work in progress)

### postureUpAndAbout
- id: CALC-6
- where: Posture option (upAndAbout)
- base: Up and about
- status: provisional (owner OK 2026-10-29, work in progress)

### calcCover
- id: CALC-7
- where: Cover toggle (person icon)
- base: Head and shoulders covered
- why: R10's wording.
- status: provisional (owner OK 2026-10-29, work in progress)

### calcCoverFootnote
- id: CALC-8
- where: Small text under the cover toggle
- base: A hat or a shirt. Sunscreen doesn't count as cover.
- why: R10: sunscreen is never cover. Without this line people switch it on because they wear sunscreen.
- status: provisional (owner OK 2026-10-29, work in progress)

### calcStay
- id: CALC-9
- where: Stay toggle (hourglass icon)
- base: Staying the whole slot
- status: provisional (owner OK 2026-10-29, work in progress)

### calcStayFootnote
- id: CALC-10
- where: Small text under the stay toggle
- base: Off: the app picks the best minutes inside your slot. On: it plans for all of it, with sunscreen, and warns you if that goes too far.
- why: This toggle swaps the answer's order and turns the warnings on (R15, R19). Nobody could guess that from the label alone.
- status: provisional (owner OK 2026-10-29, work in progress)

### calcCompute
- id: CALC-11
- where: Compute button (arrow icon)
- base: Plan this slot
- status: provisional (owner OK 2026-10-29, work in progress)

### calcHistory
- id: CALC-12
- where: Top-right button (clock icon)
- base: History
- status: provisional (owner OK 2026-10-29, work in progress)

### calcSettings
- id: CALC-13
- where: Top-right button (gear icon)
- base: Settings
- status: provisional (owner OK 2026-10-29, work in progress)

## Due questions on the Plan screen

### dueSkinCheck
- id: DUE-1
- where: Row above the inputs when a skin check is due (in-app fallback, R20)
- base: Skin check for {day}
- why: The row now reuses “Did you do this session?” with an empty time, which reads as a broken sentence.
- status: provisional (owner OK 2026-10-29, work in progress)

### dueLastingColour
- id: DUE-2
- where: Row when a lasting-colour question is due
- base: Lasting colour from {day}
- status: provisional (owner OK 2026-10-29, work in progress)

## Result screen

### resultTitle
- id: RES-1
- where: Screen title
- base: Your answer
- why: Not every outcome is a plan (too weak, no forecast, slot passed), so “plan” would sometimes be wrong.
- status: provisional (owner OK 2026-10-29, work in progress)

### resultForecastHere
- id: RES-2
- where: Place line, when the forecast is for the phone's location
- base: Forecast for your location
- why: Coordinates mean nothing to a reader. Turning them into a town name would be one more network call (V11), so the line doesn't name one.
- status: provisional (owner OK 2026-10-29, work in progress)

### resultForecastFor
- id: RES-3
- where: Place line, after a place was entered by hand
- base: Forecast for {place}
- why: {place} is the name the user picked.
- status: provisional (owner OK 2026-10-29, work in progress)

### resultChangePlace
- id: RES-4
- where: Button beside the place line (pin icon)
- base: Change place
- status: provisional (owner OK 2026-10-29, work in progress)

### resultRefresh
- id: RES-5
- where: Button beside the place line (circular arrow)
- base: Refresh forecast
- status: provisional (owner OK 2026-10-29, work in progress)

### resultDoTheNumber
- id: RES-6
- where: Line above the figures
- base: Do the number. The range shows how sure the app is about your skin.
- why: R7 says the copy must say that the number, not the range, is what to do. APP_COPY.md has no key for it yet.
- status: provisional (owner OK 2026-10-29, work in progress)

### resultNoSuchSPF
- id: RES-7
- where: Button under a sunscreen answer (drop icon)
- base: I don't have that SPF
- why: R15's wording.
- status: provisional (owner OK 2026-10-29, work in progress)

### resultDidThis
- id: RES-8
- where: Button that logs the session (tick icon)
- base: I did this
- why: R45's wording.
- status: provisional (owner OK 2026-10-29, work in progress)

### resultLogged
- id: RES-9
- where: Line after “I did this” is tapped
- base: Logged. The app asks about your skin tomorrow.
- why: Nothing shows after the tap today, so people tap twice.
- status: provisional (owner OK 2026-10-29, work in progress)

### resultStartTimer
- id: RES-10
- where: Button, lying-down plans only (timer icon)
- base: Start the flip timer
- status: provisional (owner OK 2026-10-29, work in progress)

## Result figures (the numbers' labels)

### figHeadlineMinutes
- id: FIG-1
- where: headlineMinutes
- base: minutes in total
- why: Each label sits right after its number: “33 minutes in total”.
- status: provisional (owner OK 2026-10-29, work in progress)

### figSideMinutes
- id: FIG-2
- where: sideMinutes, sides equal
- base: min per side
- why: R9's own figure.
- status: provisional (owner OK 2026-10-29, work in progress)

### figSideMinutesFaceUp
- id: FIG-3
- where: sideMinutes, face up
- base: min face up
- why: R9's “front X min, back Y min”, in the timer's words.
- status: provisional (owner OK 2026-10-29, work in progress)

### figSideMinutesFaceDown
- id: FIG-4
- where: sideMinutes, face down
- base: min face down
- status: provisional (owner OK 2026-10-29, work in progress)

### figRegionDose
- id: FIG-5
- where: regionDose
- base: SED on your {region} in this plan
- status: provisional (owner OK 2026-10-29, work in progress)

### figRemainingBudget
- id: FIG-6
- where: remainingBudget
- base: SED left for your {region} today
- status: provisional (owner OK 2026-10-29, work in progress)

### figCycleDose
- id: FIG-7
- where: cycleDose
- base: SED on your {region} this tan cycle
- status: provisional (owner OK 2026-10-29, work in progress)

### figRangeLower
- id: FIG-8
- where: rangeLower
- base: minutes: low end of the range
- status: provisional (owner OK 2026-10-29, work in progress)

### figRangeUpper
- id: FIG-9
- where: rangeUpper
- base: minutes: high end of the range
- status: provisional (owner OK 2026-10-29, work in progress)

### figRangeUpperClipped
- id: FIG-10
- where: rangeUpper when clipped at your redness line
- base: minutes: redness likely beyond
- why: R7's wording for the clipped edge.
- status: provisional (owner OK 2026-10-29, work in progress)

### figUvaMultiple
- id: FIG-11
- where: uvaMultiple
- base: × the UVA of the bare-skin minutes
- status: provisional (owner OK 2026-10-29, work in progress)

### figShortfall
- id: FIG-12
- where: shortfall
- base: SED short of a tanning dose
- status: provisional (owner OK 2026-10-29, work in progress)

### figExtraIfCovered
- id: FIG-13
- where: extraIfCovered
- base: more minutes per side with head and shoulders covered
- status: provisional (owner OK 2026-10-29, work in progress)

## Words filled into approved lines

### regionFront
- id: FILL-1
- where: {region} inside sentences, e.g. “Today's budget for your {region} is used up”
- base: front
- why: Lower case, because they sit mid-sentence.
- status: provisional (owner OK 2026-10-29, work in progress)

### regionBack
- id: FILL-1
- where: {region} inside sentences, e.g. “Today's budget for your {region} is used up”
- base: back
- why: Lower case, because they sit mid-sentence.
- status: provisional (owner OK 2026-10-29, work in progress)

### regionHeadAndShoulders
- id: FILL-1
- where: {region} inside sentences, e.g. “Today's budget for your {region} is used up”
- base: head and shoulders
- why: Lower case, because they sit mid-sentence.
- status: provisional (owner OK 2026-10-29, work in progress)

### applicationThin
- id: FILL-2
- where: {application} in “applied {application}”
- base: thinly
- why: R15 phrases it “SPF 30, applied normally”.
- status: provisional (owner OK 2026-10-29, work in progress)

### applicationNormal
- id: FILL-2
- where: {application} in “applied {application}”
- base: normally
- why: R15 phrases it “SPF 30, applied normally”.
- status: provisional (owner OK 2026-10-29, work in progress)

### applicationThick
- id: FILL-2
- where: {application} in “applied {application}”
- base: thickly
- why: R15 phrases it “SPF 30, applied normally”.
- status: provisional (owner OK 2026-10-29, work in progress)

### reasonProvider
- id: FILL-3
- where: {reason} in missingForecast, when the weather service fails
- base: the weather service did not answer
- why: Reads as “Reason: the weather service did not answer.”
- status: provisional (owner OK 2026-10-29, work in progress)

### reasonMalformed
- id: FILL-4
- where: {reason}, forecast unreadable
- base: the forecast arrived incomplete
- status: provisional (owner OK 2026-10-29, work in progress)

### reasonCacheUnreadable
- id: FILL-5
- where: {reason}, saved forecast unreadable
- base: the saved forecast could not be read
- status: provisional (owner OK 2026-10-29, work in progress)

### placeYourLocation
- id: FILL-6
- where: {place} in staleHeadsUp / staleFarFromCache, for the phone's location
- base: your location
- why: Same reason as RES-2: “Forecast fetched 4 hours ago for your location.”
- status: provisional (owner OK 2026-10-29, work in progress)

### effectNone
- id: FILL-7
- where: {effect} in “Report saved. {effect}”: the report changed nothing
- base: It matched what the app expected, so nothing changed.
- why: Today {effect} is either empty or a bare number like “0.27”.
- status: provisional (owner OK 2026-10-29, work in progress)

### effectTanCredited
- id: FILL-8
- where: {effect}: a tolerant day credited to the tan (R21)
- base: Your skin took more than expected without redness. The app counts that as tan first, so later plans may run a little longer.
- status: provisional (owner OK 2026-10-29, work in progress)

### effectMoreSensitive
- id: FILL-9
- where: {effect}: the sensitivity estimate moved up
- base: The app now treats your skin as more sensitive. Plans get shorter.
- status: provisional (owner OK 2026-10-29, work in progress)

### effectLessSensitive
- id: FILL-10
- where: {effect}: the sensitivity estimate moved down
- base: The app now treats your skin as a little less sensitive. Plans may run a little longer.
- status: provisional (owner OK 2026-10-29, work in progress)

### effectDiscounted
- id: FILL-11
- where: {effect}: the report named something unusual
- base: Something unusual was going on that day, so this report counts for less.
- status: provisional (owner OK 2026-10-29, work in progress)

## “I don't have that SPF” sheet

### sunscreenSheetTitle
- id: SUN-1
- where: Sheet title
- base: The sunscreen you have
- status: provisional (owner OK 2026-10-29, work in progress)

### sunscreenSheetSPF
- id: SUN-2
- where: SPF picker label (drop icon)
- base: SPF on the bottle
- status: provisional (owner OK 2026-10-29, work in progress)

### sunscreenSheetApplication
- id: SUN-3
- where: Application picker label (hand icon)
- base: How you'll put it on
- status: provisional (owner OK 2026-10-29, work in progress)

### sunscreenOptionThin
- id: SUN-4
- where: Application option thin
- base: Thinly
- status: provisional (owner OK 2026-10-29, work in progress)

### sunscreenOptionNormal
- id: SUN-5
- where: Application option normal
- base: Normally, as most people do
- why: Module 8: most people apply about half the label's amount.
- status: provisional (owner OK 2026-10-29, work in progress)

### sunscreenOptionThick
- id: SUN-6
- where: Application option thick
- base: Thickly, about a shot glass for the whole body
- why: Same measure as the approved alternativeThickEnough line.
- status: provisional (owner OK 2026-10-29, work in progress)

### sunscreenSheetConfirm
- id: SUN-7
- where: Confirm button (tick icon)
- base: Use this
- status: provisional (owner OK 2026-10-29, work in progress)

## Change place sheet

### placeSheetTitle
- id: PLACE-1
- where: Sheet title
- base: Change place
- status: provisional (owner OK 2026-10-29, work in progress)

### placeSearchPrompt
- id: PLACE-2
- where: Search field placeholder (magnifier icon)
- base: Town or place
- status: provisional (owner OK 2026-10-29, work in progress)

### placeNotFound
- id: PLACE-3
- where: When the search finds nothing
- base: No place found by that name.
- why: Today the list just stays empty.
- status: provisional (owner OK 2026-10-29, work in progress)

## Flip timer

### timerTitle
- id: TIM-1
- where: Screen title
- base: Flip timer
- status: provisional (owner OK 2026-10-29, work in progress)

### timerSidePicker
- id: TIM-2
- where: Side picker label, under the approved “Which side is up first?”
- base: Side up first
- why: VoiceOver label for the picker.
- status: provisional (owner OK 2026-10-29, work in progress)

### sideFaceUp
- id: TIM-3
- where: Side option (arms-open figure)
- base: Face up
- status: provisional (owner OK 2026-10-29, work in progress)

### sideFaceDown
- id: TIM-4
- where: Side option (waving figure)
- base: Face down
- status: provisional (owner OK 2026-10-29, work in progress)

### timerStart
- id: TIM-5
- where: Start button (play icon)
- base: Start
- status: provisional (owner OK 2026-10-29, work in progress)

### timerStartWithoutAlerts
- id: TIM-6
- where: Button shown when notifications are off (outlined play icon)
- base: Start without alerts
- why: Follows the approved timerNeedsNotifications line.
- status: provisional (owner OK 2026-10-29, work in progress)

### timerNow
- id: TIM-7
- where: Running: the current side, beside its figure
- base: Now: {side}
- why: {side} is TIM-3 or TIM-4, lower case.
- status: provisional (owner OK 2026-10-29, work in progress)

### timerUntilTurn
- id: TIM-8
- where: Under the big countdown
- base: until you turn over
- status: provisional (owner OK 2026-10-29, work in progress)

### timerUntilEnd
- id: TIM-9
- where: Under the big countdown, on the last side
- base: until the session ends
- status: provisional (owner OK 2026-10-29, work in progress)

### timerLeftInSession
- id: TIM-10
- where: Under the small countdown
- base: left in the session
- status: provisional (owner OK 2026-10-29, work in progress)

### timerStop
- id: TIM-11
- where: Stop button (stop icon)
- base: Stop
- status: provisional (owner OK 2026-10-29, work in progress)

### timerStopFootnote
- id: TIM-12
- where: Small text under Stop
- base: Stopping ends the session now and logs the time you were out.
- why: R11: stopping shortens the record. People should know before they tap.
- status: provisional (owner OK 2026-10-29, work in progress)

## Skin check (the day-after questions)

### skinCheckTitle
- id: SKIN-1
- where: Screen title
- base: Skin check
- status: provisional (owner OK 2026-10-29, work in progress)

### didYes
- id: DID-1
- where: Under “Did you do this session?” (tick icon)
- base: Yes, I did
- status: provisional (owner OK 2026-10-29, work in progress)

### didNo
- id: DID-2
- where: Same (cross icon)
- base: No
- status: provisional (owner OK 2026-10-29, work in progress)

### woreAsSuggested
- id: DID-3
- where: Sunscreen answer: the suggested pair
- base: Yes, as suggested
- why: Answers the approved “Did you wear SPF 30, applied normally?”. “Prescribed” sounds medical.
- status: provisional (owner OK 2026-10-29, work in progress)

### woreDifferent
- id: DID-4
- where: Sunscreen answer: another product
- base: A different sunscreen
- status: provisional (owner OK 2026-10-29, work in progress)

### woreNone
- id: DID-5
- where: Sunscreen answer: none
- base: None
- status: provisional (owner OK 2026-10-29, work in progress)

### promptNext
- id: DID-6
- where: Next button (chevron)
- base: Next
- status: provisional (owner OK 2026-10-29, work in progress)

### timesHeader
- id: DID-7
- where: Header on the times page
- base: When were you out? Change the times if they were different.
- why: R45: the times are editable when logging.
- status: provisional (owner OK 2026-10-29, work in progress)

### exposureFaceUp
- id: DID-8
- where: Interval labels
- base: Face up
- why: Same words as the timer and the posture picker.
- status: provisional (owner OK 2026-10-29, work in progress)

### exposureFaceDown
- id: DID-8
- where: Interval labels
- base: Face down
- why: Same words as the timer and the posture picker.
- status: provisional (owner OK 2026-10-29, work in progress)

### exposureUpAndAbout
- id: DID-8
- where: Interval labels
- base: Up and about
- why: Same words as the timer and the posture picker.
- status: provisional (owner OK 2026-10-29, work in progress)

### intervalFrom
- id: DID-9
- where: Interval time pickers
- base: From
- why: Same as CALC-2 and CALC-3.
- status: provisional (owner OK 2026-10-29, work in progress)

### intervalUntil
- id: DID-9
- where: Interval time pickers
- base: Until
- why: Same as CALC-2 and CALC-3.
- status: provisional (owner OK 2026-10-29, work in progress)

### promptSave
- id: DID-10
- where: Save button (tick icon)
- base: Save
- status: provisional (owner OK 2026-10-29, work in progress)

### skinQuestionLook
- id: SKIN-2
- where: Q1 heading
- base: How does your skin look today?
- why: R20's question, already approved in the notification. The flow shows the answers with no question above them.
- status: provisional (owner OK 2026-10-29, work in progress)

### skinAnswerNormal
- id: SKIN-3
- where: Q1 answer normal
- base: Normal, no redness
- status: provisional (owner OK 2026-10-29, work in progress)

### skinAnswerFaintPink
- id: SKIN-4
- where: Q1 answer faintPink
- base: Faint pink
- why: R21's names for the four redness steps.
- status: provisional (owner OK 2026-10-29, work in progress)

### skinAnswerClearlyPink
- id: SKIN-5
- where: Q1 answer clearlyPink
- base: Clearly pink
- status: provisional (owner OK 2026-10-29, work in progress)

### skinAnswerRedSore
- id: SKIN-6
- where: Q1 answer redSore
- base: Red and sore
- status: provisional (owner OK 2026-10-29, work in progress)

### skinAnswerBlistered
- id: SKIN-7
- where: Q1 answer blistered
- base: Very red, painful or blistered
- why: R20's wording for the top answer.
- status: provisional (owner OK 2026-10-29, work in progress)

### skinQuestionTiming
- id: SKIN-8
- where: Q2 heading
- base: When did it show up?
- why: R20's question.
- status: provisional (owner OK 2026-10-29, work in progress)

### timingWithinHourGoneByEvening
- id: SKIN-9
- where: Q2 answer
- base: Within an hour, gone by evening
- status: provisional (owner OK 2026-10-29, work in progress)

### timingThatEvening
- id: SKIN-10
- where: Q2 answer
- base: That evening
- status: provisional (owner OK 2026-10-29, work in progress)

### timingNextMorning
- id: SKIN-11
- where: Q2 answer
- base: The next morning
- status: provisional (owner OK 2026-10-29, work in progress)

### timingNotSure
- id: SKIN-12
- where: Q2 answer
- base: Not sure
- status: provisional (owner OK 2026-10-29, work in progress)

### skinQuestionRegion
- id: SKIN-13
- where: Region heading
- base: Where?
- status: provisional (owner OK 2026-10-29, work in progress)

### reportRegionAllExposed
- id: SKIN-14
- where: Region answer allExposed (first, the default)
- base: All skin that was in the sun
- why: Clearer than “all exposed”, which can read as indecent exposure.
- status: provisional (owner OK 2026-10-29, work in progress)

### reportRegionFront
- id: SKIN-15
- where: Region answers
- base: Front
- status: provisional (owner OK 2026-10-29, work in progress)

### reportRegionBack
- id: SKIN-15
- where: Region answers
- base: Back
- status: provisional (owner OK 2026-10-29, work in progress)

### reportRegionHeadAndShoulders
- id: SKIN-15
- where: Region answers
- base: Head and shoulders
- status: provisional (owner OK 2026-10-29, work in progress)

### skinQuestionConfounders
- id: SKIN-16
- where: Confounder heading
- base: Anything unusual that day? Pick any that apply, or none.
- why: R20's “anything unusual?”.
- status: provisional (owner OK 2026-10-29, work in progress)

### confounderPhotosensitisingMedication
- id: SKIN-17
- where: Confounder photosensitisingMedication
- base: Medication that makes skin sun-sensitive
- status: provisional (owner OK 2026-10-29, work in progress)

### confounderIllness
- id: SKIN-18
- where: Confounder illness
- base: Illness or fever
- status: provisional (owner OK 2026-10-29, work in progress)

### confounderWaterOrSnow
- id: SKIN-19
- where: Confounder waterOrSnow
- base: Water or snow nearby
- why: Water and snow reflect UV.
- status: provisional (owner OK 2026-10-29, work in progress)

### confounderAltitude
- id: SKIN-20
- where: Confounder altitude
- base: High altitude
- status: provisional (owner OK 2026-10-29, work in progress)

### confounderAlcohol
- id: SKIN-21
- where: Confounder alcohol
- base: Alcohol
- status: provisional (owner OK 2026-10-29, work in progress)

### skinSendReport
- id: SKIN-22
- where: Submit button (tick icon)
- base: Send report
- why: Matches “skin reports” in the approved lines.
- status: provisional (owner OK 2026-10-29, work in progress)

## Lasting colour

### lastingColourTitle
- id: LC-1
- where: Screen title
- base: Lasting colour
- status: provisional (owner OK 2026-10-29, work in progress)

### lastingColourQuestion
- id: LC-2
- where: Question at the top of the flow
- base: Did you notice lasting colour from {day}?
- why: Same as the approved notification line, shown in the flow as well.
- status: provisional (owner OK 2026-10-29, work in progress)

### lastingYes
- id: LC-3
- where: Answers yes / aLittle / no
- base: Yes
- status: provisional (owner OK 2026-10-29, work in progress)

### lastingALittle
- id: LC-3
- where: Answers yes / aLittle / no
- base: A little
- status: provisional (owner OK 2026-10-29, work in progress)

### lastingNo
- id: LC-3
- where: Answers yes / aLittle / no
- base: No
- status: provisional (owner OK 2026-10-29, work in progress)

### lastingSaved
- id: LC-4
- where: After answering
- base: Answer saved.
- status: provisional (owner OK 2026-10-29, work in progress)

## History

### historyTitle
- id: HIST-1
- where: Screen title
- base: History
- status: provisional (owner OK 2026-10-29, work in progress)

### historyExport
- id: HIST-2
- where: Toolbar button (share icon)
- base: Export
- status: provisional (owner OK 2026-10-29, work in progress)

### historyImport
- id: HIST-3
- where: Toolbar button (download icon)
- base: Import
- status: provisional (owner OK 2026-10-29, work in progress)

### importWarning
- id: HIST-4
- where: Warning before an import
- base: Importing replaces everything on this phone with the file: sessions, reports and your skin-type settings. Export first if you want to keep what is here.
- why: Import overwrites the whole history with no warning today. Delete has one (R44), so import should too.
- status: provisional (owner OK 2026-10-29, work in progress)

### importConfirm
- id: HIST-5
- where: Buttons on that warning
- base: Import and replace
- status: provisional (owner OK 2026-10-29, work in progress)

### importCancel
- id: HIST-5
- where: Buttons on that warning
- base: Cancel
- status: provisional (owner OK 2026-10-29, work in progress)

### historyEmpty
- id: HIST-6
- where: When there is no session yet
- base: No sessions yet. A session is saved when you tap “I did this” or start the flip timer.
- why: R45: only those two actions log a session.
- status: provisional (owner OK 2026-10-29, work in progress)

### historyDayDose
- id: HIST-7
- where: Day total per region, under each day
- base: SED on your {region}
- status: provisional (owner OK 2026-10-29, work in progress)

### historySkinAnswer
- id: HIST-8
- where: Day footer, when the day has a skin report
- base: Skin: {answer}
- why: {answer} is SKIN-3 to SKIN-7.
- status: provisional (owner OK 2026-10-29, work in progress)

### historySunscreen
- id: HIST-9
- where: Session row: sunscreen
- base: SPF {spf}, {application}
- why: {application} from FILL-2: “SPF 30, normally”.
- status: provisional (owner OK 2026-10-29, work in progress)

### historyNoSunscreen
- id: HIST-9
- where: Session row: sunscreen
- base: No sunscreen
- why: {application} from FILL-2: “SPF 30, normally”.
- status: provisional (owner OK 2026-10-29, work in progress)

### detailWhatYouDid
- id: HIST-10
- where: Session detail, section headers
- base: What you did
- status: provisional (owner OK 2026-10-29, work in progress)

### detailWhatYouWereShown
- id: HIST-10
- where: Session detail, section headers
- base: What you were shown
- status: provisional (owner OK 2026-10-29, work in progress)

### detailTheForecast
- id: HIST-10
- where: Session detail, section headers
- base: The forecast it used
- status: provisional (owner OK 2026-10-29, work in progress)

### detailDay
- id: HIST-11
- where: Session detail rows
- base: Day
- status: provisional (owner OK 2026-10-29, work in progress)

### detailTime
- id: HIST-11
- where: Session detail rows
- base: Time
- status: provisional (owner OK 2026-10-29, work in progress)

### detailPosition
- id: HIST-11
- where: Session detail rows
- base: Position
- status: provisional (owner OK 2026-10-29, work in progress)

### detailCovered
- id: HIST-11
- where: Session detail rows
- base: Head and shoulders covered
- status: provisional (owner OK 2026-10-29, work in progress)

### detailPlan
- id: HIST-11
- where: Session detail rows
- base: Plan
- status: provisional (owner OK 2026-10-29, work in progress)

### detailSunscreen
- id: HIST-11
- where: Session detail rows
- base: Sunscreen
- status: provisional (owner OK 2026-10-29, work in progress)

### detailSetting
- id: HIST-11
- where: Session detail rows
- base: Setting
- status: provisional (owner OK 2026-10-29, work in progress)

### valueYes
- id: HIST-12
- where: Values for those rows
- base: Yes
- status: provisional (owner OK 2026-10-29, work in progress)

### valueNo
- id: HIST-12
- where: Values for those rows
- base: No
- status: provisional (owner OK 2026-10-29, work in progress)

### intentBestMinutes
- id: HIST-12
- where: Values for those rows
- base: Best minutes
- status: provisional (owner OK 2026-10-29, work in progress)

### intentStayWholeWindow
- id: HIST-12
- where: Values for those rows
- base: Whole slot
- status: provisional (owner OK 2026-10-29, work in progress)

### ceilingConservative
- id: HIST-12
- where: Values for those rows
- base: Conservative
- status: provisional (owner OK 2026-10-29, work in progress)

### ceilingStandard
- id: HIST-12
- where: Values for those rows
- base: Standard
- status: provisional (owner OK 2026-10-29, work in progress)

### ceilingAggressive
- id: HIST-12
- where: Values for those rows
- base: Aggressive
- status: provisional (owner OK 2026-10-29, work in progress)

### detailTanProtection
- id: HIST-13
- where: Session detail figures
- base: Tan protection, {region}
- why: Tan protection is the adaptation factor, shown as ×1.4.
- status: provisional (owner OK 2026-10-29, work in progress)

### detailTarget
- id: HIST-13
- where: Session detail figures
- base: Target SED, {region}
- why: Tan protection is the adaptation factor, shown as ×1.4.
- status: provisional (owner OK 2026-10-29, work in progress)

### detailReceived
- id: HIST-13
- where: Session detail figures
- base: SED received, {region}
- why: Tan protection is the adaptation factor, shown as ×1.4.
- status: provisional (owner OK 2026-10-29, work in progress)

### detailForecastFor
- id: HIST-14
- where: Session detail, forecast rows
- base: Forecast for
- status: provisional (owner OK 2026-10-29, work in progress)

### detailForecastFetched
- id: HIST-14
- where: Session detail, forecast rows
- base: Forecast fetched
- status: provisional (owner OK 2026-10-29, work in progress)

### detailPeakUVI
- id: HIST-14
- where: Session detail, forecast rows
- base: Highest UV index
- status: provisional (owner OK 2026-10-29, work in progress)

### detailTimeZone
- id: HIST-14
- where: Session detail, forecast rows
- base: Time zone
- status: provisional (owner OK 2026-10-29, work in progress)

## Settings

### settingsTitle
- id: SET-1
- where: Screen title
- base: Settings
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsDone
- id: SET-2
- where: Close button
- base: Done
- why: The sheet can only be swiped away today.
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsCeilingHeading
- id: SET-3
- where: Heading over the setting selector (dial icon)
- base: How close to your line
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsConservative
- id: SET-4
- where: Selector options
- base: Conservative
- why: R6's names.
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsStandard
- id: SET-4
- where: Selector options
- base: Standard
- why: R6's names.
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsAggressive
- id: SET-4
- where: Selector options
- base: Aggressive
- why: R6's names.
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsCeilingFootnote
- id: SET-5
- where: Small text under the selector
- base: Conservative gives the shortest sessions, aggressive the longest. Aggressive goes up to your redness line, never past it.
- why: V15 in user words.
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsSensitivityHeading
- id: SET-6
- where: Heading over the sensitivity
- base: Your skin's sensitivity
- status: provisional (owner OK 2026-10-29, work in progress)

### sensitivityNoReports
- id: SET-7
- where: Sensitivity line before any report
- base: No skin reports yet, so the app uses the typical sensitivity for your skin type.
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsManualValue
- id: SET-8
- where: Stepper label
- base: Set by hand: {value}
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsManualFootnote
- id: SET-9
- where: Small text under the stepper
- base: 1.00 is typical for your skin type. Lower means more sensitive and shorter sessions.
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsResetSensitivity
- id: SET-10
- where: Reset button (anticlockwise arrow)
- base: Go back to what your reports say
- why: R23's reset.
- status: provisional (owner OK 2026-10-29, work in progress)

### unreportedNone
- id: SET-11
- where: Unreported days, when there are none
- base: Every session day has a skin report.
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsWeekHeading
- id: SET-12
- where: Heading over the first totals block (timeline icon)
- base: This week, in SED
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsCycleHeading
- id: SET-13
- where: Heading over the second totals block (calendar icon)
- base: This tan cycle, in SED
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsDataHeading
- id: SET-14
- where: Heading over the data buttons
- base: Your data
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsExport
- id: SET-15
- where: Data buttons (share, share-again, download, bin icons)
- base: Export history
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsShare
- id: SET-15
- where: Data buttons (share, share-again, download, bin icons)
- base: Share the file
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsImport
- id: SET-15
- where: Data buttons (share, share-again, download, bin icons)
- base: Import history
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsDelete
- id: SET-15
- where: Data buttons (share, share-again, download, bin icons)
- base: Delete history
- status: provisional (owner OK 2026-10-29, work in progress)

### deleteConfirm
- id: SET-16
- where: Buttons on the approved delete warning
- base: Delete everything
- status: provisional (owner OK 2026-10-29, work in progress)

### deleteCancel
- id: SET-16
- where: Buttons on the approved delete warning
- base: Cancel
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsAboutHeading
- id: SET-17
- where: Heading over attribution, privacy and disclaimer
- base: About
- status: provisional (owner OK 2026-10-29, work in progress)

### attributionMark
- id: SET-18
- where: Apple Weather mark, VoiceOver label
- base: Weather data from Apple Weather
- status: provisional (owner OK 2026-10-29, work in progress)

### attributionLink
- id: SET-19
- where: Link beside the mark (info icon)
- base: Weather data sources
- why: Goes to Apple's legal attribution page (R29).
- status: provisional (owner OK 2026-10-29, work in progress)

### privacyPolicyLink
- id: SET-20
- where: Privacy policy link (hand icon)
- base: Privacy policy
- status: provisional (owner OK 2026-10-29, work in progress)

### settingsSkinType
- id: SET-21
- where: Skin type row
- base: Skin type: Type {type}
- why: The approved revisitSkinType line says “Check your skin type in Settings”, but Settings has no skin-type row. The words are here; the row has to be built.
- status: provisional (owner OK 2026-10-29, work in progress)

## Onboarding

### onboardingBack
- id: ONB-1
- where: Bottom buttons (chevrons)
- base: Back
- status: provisional (owner OK 2026-10-29, work in progress)

### onboardingNext
- id: ONB-1
- where: Bottom buttons (chevrons)
- base: Next
- status: provisional (owner OK 2026-10-29, work in progress)

### onboardingStart
- id: ONB-2
- where: Last page's button (tick icon)
- base: Start
- status: provisional (owner OK 2026-10-29, work in progress)

### onboardingDisclaimerHeading
- id: ONB-3
- where: Disclaimer page heading
- base: Before you start
- status: provisional (owner OK 2026-10-29, work in progress)

### onboardingAcknowledge
- id: ONB-4
- where: Disclaimer toggle; the disclaimer itself stays as text above
- base: I have read this
- why: The approved disclaimer stays as text above; the switch gets a short label of its own.
- status: provisional (owner OK 2026-10-29, work in progress)

### onboardingSkinTypeHeading
- id: ONB-5
- where: Skin-type page heading
- base: Your skin type
- status: provisional (owner OK 2026-10-29, work in progress)

### onboardingSkinTypeIntro
- id: ONB-6
- where: Skin-type page, under the heading
- base: Pick the description that fits you best. Not sure? The questionnaire works it out.
- status: provisional (owner OK 2026-10-29, work in progress)

### onboardingTakeQuiz
- id: ONB-7
- where: Questionnaire button (question-mark icon)
- base: Take the questionnaire
- status: provisional (owner OK 2026-10-29, work in progress)

### quizTitle
- id: QUIZ-1
- where: Questionnaire title
- base: Skin-type questionnaire
- status: provisional (owner OK 2026-10-29, work in progress)

### quizDone
- id: QUIZ-2
- where: Questionnaire done button (tick icon)
- base: See my type
- status: provisional (owner OK 2026-10-29, work in progress)

### quizResult
- id: QUIZ-3
- where: After the questionnaire
- base: Your answers point to type {type}. You can pick another if it fits better.
- status: provisional (owner OK 2026-10-29, work in progress)

### onboardingPermissionsHeading
- id: ONB-8
- where: Permissions page heading
- base: Two permissions
- status: provisional (owner OK 2026-10-29, work in progress)

### onboardingAllowLocation
- id: ONB-9
- where: Location button (location icon)
- base: Allow location
- status: provisional (owner OK 2026-10-29, work in progress)

### onboardingAllowNotifications
- id: ONB-10
- where: Notifications button (bell icon)
- base: Allow notifications
- status: provisional (owner OK 2026-10-29, work in progress)

### onboardingPermissionsFootnote
- id: ONB-11
- where: Small text under both
- base: Both are optional, and you can change them later in the iPhone's Settings.
- status: provisional (owner OK 2026-10-29, work in progress)

## Learn

### learnTitle
- id: LEARN-1
- where: Learn list title (BL-2)
- base: Learn
- why: Same as the tab.
- status: provisional (owner OK 2026-10-29, work in progress)

## VoiceOver only (S9)

### voEstimate
- id: VO-1
- where: Estimate badge (question-mark icon)
- base: Estimate. It rests on an assumption: {assumptions}.
- why: R30: name the assumption. {assumptions} is a list from VO-2 to VO-12.
- status: provisional (owner OK 2026-10-29, work in progress)

### assumptionMelanogenicFraction
- id: VO-2
- where: melanogenicFraction (types III–VI)
- base: how far below your redness line your skin starts to tan
- status: provisional (owner OK 2026-10-29, work in progress)

### assumptionRiseMultiplier
- id: VO-3
- where: riseMultiplier.dark
- base: how fast darker skin builds a tan
- status: provisional (owner OK 2026-10-29, work in progress)

### assumptionAdaptationGain
- id: VO-4
- where: adaptationGain.dark
- base: how much protection a tan gives darker skin
- status: provisional (owner OK 2026-10-29, work in progress)

### assumptionFrontBackFraction
- id: VO-5
- where: frontBackFraction
- base: how much sun each side gets while you move about
- status: provisional (owner OK 2026-10-29, work in progress)

### assumptionShoulderFraction
- id: VO-6
- where: shoulderFraction
- base: how much sun your shoulders get lying face down
- status: provisional (owner OK 2026-10-29, work in progress)

### assumptionRiseTimeConstantDays
- id: VO-7
- where: riseTimeConstantDays
- base: how fast a tan builds
- status: provisional (owner OK 2026-10-29, work in progress)

### assumptionDecayHalfLifeDays
- id: VO-8
- where: decayHalfLifeDays
- base: how fast a tan fades
- status: provisional (owner OK 2026-10-29, work in progress)

### assumptionPlateauTanState
- id: VO-9
- where: plateauTanState
- base: when a tan counts as near its peak
- status: provisional (owner OK 2026-10-29, work in progress)

### assumptionTolerantCredit
- id: VO-10
- where: tolerantCredit
- base: how much of a day without redness is put down to your tan
- status: provisional (owner OK 2026-10-29, work in progress)

### assumptionUvaHeavyHoursFromNoon
- id: VO-11
- where: uvaHeavyHoursFromNoon
- base: how far from midday the light counts as UVA-heavy
- status: provisional (owner OK 2026-10-29, work in progress)

### assumptionImpliedRatio
- id: VO-12
- where: impliedRatio (skin answers)
- base: what each skin-check answer says about your redness line
- status: provisional (owner OK 2026-10-29, work in progress)

### voTimerUntilTurn
- id: VO-13
- where: Timer countdowns
- base: {minutes} minutes {seconds} seconds until you turn over
- why: Plus the same with TIM-9 and TIM-10.
- status: provisional (owner OK 2026-10-29, work in progress)

### voTimerUntilEnd
- id: VO-13
- where: Timer countdowns
- base: {minutes} minutes {seconds} seconds until the session ends
- why: Plus the same with TIM-9 and TIM-10.
- status: provisional (owner OK 2026-10-29, work in progress)

### voTimerLeftInSession
- id: VO-13
- where: Timer countdowns
- base: {minutes} minutes {seconds} seconds left in the session
- why: Plus the same with TIM-9 and TIM-10.
- status: provisional (owner OK 2026-10-29, work in progress)

### voAdvertisement
- id: VO-14
- where: Ad banner container
- base: Advertisement
- why: So nobody mistakes the banner for part of the app.
- status: provisional (owner OK 2026-10-29, work in progress)

## Lines outside CopyKey

Two provisional lines that no view resolves through `AppCopy`, written as
`- <id>: <text>` so the build script reads past them. PERM-1 is the
`INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` build setting in
`project.yml`, because iOS reads it from the Info.plist; `acceptance/S11.sh`
fails when the two differ. VO-15 is a rule rather than a line.

- PERM-1: Used to fetch the UV forecast for where you are. Nothing else uses it.
  - where: Purpose string in the system location dialog (NSLocationWhenInUseUsageDescription)
  - why: Same promise as the approved onboardingWhyLocation, short enough for the dialog. Without this line iOS never asks.
  - status: provisional (owner OK 2026-10-29, work in progress)
- VO-15: Its line above (CALC-11, RES-4, TIM-5 …)
  - where: Every other icon button: VoiceOver reads the button's own visible line
  - why: One label per control; nothing extra to approve.
  - status: provisional (owner OK 2026-10-29, work in progress)

## Skin types

The onboarding table. Citation: Fitzpatrick TB. *The validity and practicality of sun-reactive skin types I through VI.* Archives of Dermatology, 1988. https://doi.org/10.1001/archderm.1988.01670060015008

| Type | Name | Description |
| --- | --- | --- |
| I | Type I | Skin goes red after a short time in strong sun and does not turn brown afterwards. Often very fair skin, light eyes, red or very light hair, freckles. |
| II | Type II | Skin goes red easily and turns only slightly brown afterwards. Often fair skin, light or hazel eyes, blond or light brown hair. |
| III | Type III | Skin sometimes goes red, then turns brown gradually. Often light to medium skin, any eye colour, brown hair. |
| IV | Type IV | Skin rarely goes red and turns brown easily. Often olive or light brown skin, dark eyes, dark hair. |
| V | Type V | Skin very rarely goes red and turns dark brown readily. Often brown skin, dark eyes, dark hair. |
| VI | Type VI | Skin does not go visibly red under ordinary sun. Deeply pigmented skin. |

## Fitzpatrick quiz

The published questionnaire. Each answer scores 0 to 4 in the order listed.
Total 0–6: type I; 7–12: type II; 13–18: type III; 19–24: type IV; 25–30:
type V; 31 and above: type VI. Citation: Fitzpatrick 1988, as above.

1. What colour are your eyes? — Light blue, grey or green | Blue, grey or green | Blue | Dark brown | Brownish black
2. What is your natural hair colour? — Red or light blond | Blond | Chestnut or dark blond | Dark brown | Black
3. What colour is your skin where it is not exposed to the sun? — Reddish | Very pale | Pale with a beige tint | Light brown | Dark brown
4. Do you have freckles on unexposed areas? — Many | Several | Few | Incidental | None
5. What happens when you stay in the sun too long? — Painful redness, blistering, peeling | Blistering followed by peeling | Burns sometimes followed by peeling | Rare burns | Never had burns
6. To what degree do you turn brown? — Hardly or not at all | Light colour tan | Reasonable tan | Tan very easily | Turn dark brown quickly
7. Do you turn brown within several hours after sun exposure? — Never | Seldom | Sometimes | Often | Always
8. How does your face react to the sun? — Very sensitive | Sensitive | Normal | Very resistant | Never had a problem
9. When did you last expose your body to the sun, a sunbed or a tanning cream? — More than 3 months ago | 2–3 months ago | 1–2 months ago | Less than a month ago | Less than 2 weeks ago
10. Did you expose the area to be treated to the sun? — Never | Hardly ever | Sometimes | Often | Always

## Notification texts

These keys are not yet in `CopyKey`. The plan that wires the notification
adapter adds them to the enum and to this file in the same change (M2 or M5);
the wording is approved here so that change carries no new copy.

### notificationSkinCheck
- base: How does your skin look today? One skin report for {day}.

### notificationLastingColour
- base: Did you notice lasting colour from {day}?

### notificationTimerSideEnd
- base: Time to turn over.

### notificationTimerReapply
- base: Time to reapply sunscreen.

### notificationTimerSessionEnd
- base: Session over. Time to get out of the sun.
